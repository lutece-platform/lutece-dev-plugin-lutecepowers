#!/usr/bin/env python3
"""The machine-wide e2e server of lutecepowers benches, driven by run.sh.

One network, one MariaDB and one Mailpit for every bench of the machine, one generic Liberty image, and the assembled
sites cached by the composition of their pom. Per bench only a runner (Playwright container, owner of the bench's
network namespace and of its host port) and an application (generic Liberty joined to the runner's namespace, serving
the bench site from a host directory), and its own database in the shared MariaDB.

    server.py build    assemble the bench site: the cached base of its pom (assembled once by gen-site.sh), the
                       artefact's fresh jar and webapp zip, the bench's own site files
    server.py up       start the bench on the shared server, wait for the application, seed its database
    server.py seed     run the post-init and seed scripts again on the bench's database
    server.py restart  restart the application's JVM (the container and its network namespace stay), wait for it
    server.py watch    the hot loop on a running bench: a changed web file or test page (e2e/harness/site/webapp) is
                       copied into the site at once (the FreeMarker cache and the kept browser contexts emptied), a
                       changed Java method body is compiled and redefined in the running JVM, anything else (a new
                       method, SQL, properties, plugin.xml, resources) packages the jar and webapp zip again and
                       restarts the JVM; then the tests the change can break (the JSP screens that reach it, the
                       scenarios of a changed scenario file, the scenarios when none is named), then every suite
    server.py selftest proof that watch misses no bug: a template bug then a Java bug, each injected through the hot
                       loop's path right after a render, required red, reverted, required green; sources restored
    server.py down     remove the bench's containers and database
    server.py logs     the application console and its Lutece log files
    server.py status   one line per container of the bench
    server.py port     the host port of the bench

Reads the bench from the environment run.sh exports: E2E_DIR, E2E_SRC, E2E_NAME, E2E_TARGET, E2E_CONTEXT,
E2E_VOLUME, E2E_SCOPE, E2E_VERSION, E2E_JVM_ARGS, MVN. State lives in $LUTECEPOWERS_E2E_HOME (~/.lutecepowers-e2e).
"""
import hashlib
import os
import pathlib
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import zipfile

BENCH = pathlib.Path(__file__).resolve().parents[1]
HOME = pathlib.Path(os.environ.get("LUTECEPOWERS_E2E_HOME", pathlib.Path.home() / ".lutecepowers-e2e"))
NET = "lpe2e"
DB = "lpe2e-db"
MAIL = "lpe2e-mail"
LIBERTY = "26.0.0.9"
IMAGE = "lpe2e-liberty:" + LIBERTY
RUNNER_IMAGE = "mcr.microsoft.com/playwright/python:v1.62.0-noble"
UID = "%d:0" % os.getuid()
M2 = pathlib.Path(os.environ.get("M2_REPO", pathlib.Path.home() / ".m2" / "repository")).resolve()
SERVER = "/opt/wlp/usr/servers/defaultServer"
NEIGHBOURS = ("fakes", "oauth2", "solr", "elastic")


def sh(*cmd, **kw):
    """Run a command and return its completed process (text output, no check)."""
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)


def log(msg):
    """Print one progress line."""
    print(msg, flush=True)


def running(name):
    """True when the container runs."""
    return sh("docker", "inspect", "-f", "{{.State.Running}}", name).stdout.strip() == "true"


class Bench:
    """One bench: its project, its names and its state directory."""

    def __init__(self):
        """Read the bench from the environment."""
        self.e2e = pathlib.Path(os.environ["E2E_DIR"]).resolve()
        self.src = (self.e2e / os.environ.get("E2E_SRC", "..")).resolve()
        self.name = os.environ["E2E_NAME"]
        self.context = os.environ.get("E2E_CONTEXT", "lutece")
        self.app = "lpe2e-%s-app" % self.name
        self.runner = "lpe2e-%s-runner" % self.name
        self.db = re.sub(r"\W", "_", self.name)
        self.state = HOME / "benches" / self.name
        self.state.mkdir(parents=True, exist_ok=True)
        self.build = self.state / "build"

    def port(self):
        """The host port of the bench: the one it had, else the first free one from 18080."""
        f = self.state / "port"
        if f.exists():
            return int(f.read_text())
        taken = {int(p.read_text()) for p in (HOME / "benches").glob("*/port") if p.read_text().strip().isdigit()}
        port = 18080
        while port in taken or not free(port):
            port += 1
        f.write_text(str(port))
        return port


def free(port):
    """True when nothing listens on the host port."""
    with socket.socket() as s:
        return s.connect_ex(("127.0.0.1", port)) != 0


def sql(statement):
    """Run one statement as root on the shared MariaDB."""
    return sh("docker", "exec", DB, "mariadb", "-uroot", "-proot", "-e", statement)


def ensure_infra():
    """Start the machine-wide network, MariaDB and Mailpit once, and build the generic Liberty image once."""
    if sh("docker", "network", "inspect", NET).returncode:
        sh("docker", "network", "create", NET)
    harness = BENCH / "harness"
    if not running(DB):
        sh("docker", "rm", "-f", DB)
        sh("docker", "run", "-d", "--name", DB, "--network", NET, "--network-alias", "db", "--tmpfs", "/var/lib/mysql",
           "-e", "MARIADB_ROOT_PASSWORD=root", "-e", "MARIADB_USER=lutece", "-e", "MARIADB_PASSWORD=lutece",
           "-v", "%s/db/my.cnf:/etc/mysql/conf.d/e2e.cnf:ro" % harness, "mariadb:11.8")
        deadline = time.time() + 90
        while time.time() < deadline and sh("docker", "exec", DB, "healthcheck.sh", "--connect", "--innodb_initialized").returncode:
            time.sleep(0.3)
        log("server: MariaDB up")
    if not running(MAIL):
        sh("docker", "rm", "-f", MAIL)
        sh("docker", "run", "-d", "--name", MAIL, "--network", NET, "--network-alias", "mail", "-e", "MP_SMTP_AUTH_ACCEPT_ANY=1",
           "-e", "MP_SMTP_AUTH_ALLOW_INSECURE=1", "axllent/mailpit:v1.31.1")
        log("server: Mailpit up")
    if sh("docker", "image", "inspect", IMAGE).returncode:
        t = time.time()
        r = sh("docker", "build", "-q", "--network", "host", "--build-arg", "LIBERTY_VERSION=" + LIBERTY, "-t", IMAGE,
               "-f", BENCH / "server/Dockerfile.liberty", BENCH / "server")
        if r.returncode:
            raise SystemExit("server: the Liberty image did not build: " + r.stderr[-500:])
        log("server: image %s built in %.0fs" % (IMAGE, time.time() - t))


def artifact(src):
    """The artifactId of the project, read from its pom outside the parent block."""
    pom = re.sub(r"<parent>.*?</parent>", "", (src / "pom.xml").read_text(), flags=re.S)
    return re.search(r"<artifactId>([^<]+)</artifactId>", pom).group(1)


def put(target, data_or_path):
    """Write a file in the bench site without touching the hard-linked cache: unlink first, then write."""
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        target.unlink()
    if isinstance(data_or_path, bytes):
        target.write_bytes(data_or_path)
    else:
        shutil.copyfile(data_or_path, target)


def gen_site(bench, *args):
    """Run the bench's gen-site.sh with the bench's environment; exit on failure."""
    env = dict(os.environ, E2E_DIR=str(bench.e2e), E2E_SITE_BUILD=str(bench.build))
    r = subprocess.run(["bash", str(BENCH / "tools/gen-site.sh"), *args], env=env)
    if r.returncode:
        raise SystemExit("build: gen-site.sh failed (%d)" % r.returncode)


def site_key(bench):
    """The key of the cached site: the site pom and plugins.dat (the artefact's transitive dependencies are in the pom),
    the artefact's SQL scripts by path and content, and the paths of its webapp files. A hit lays the new jar and
    webapp files over the cached site, but never refreshes WEB-INF/classes/sql, where the assembly copied the SQL
    Liquibase reads, and never deletes a file the artefact no longer ships: either change must assemble again."""
    h = hashlib.sha1((bench.build / "pom.xml").read_bytes() + (bench.build / "webapp/WEB-INF/plugins/plugins.dat").read_bytes())
    for root, content in ((bench.src / "src/sql", True), (bench.src / "webapp", False)):
        for f in sorted(root.rglob("*")) if root.is_dir() else []:
            if f.is_file():
                h.update(str(f.relative_to(bench.src)).encode() + b"\0")
                if content:
                    h.update(f.read_bytes() + b"\0")
    return h.hexdigest()[:12]


DEPS = ".lpe2e-deps"
"""File of a cached site holding the digest of the Lutece dependencies it was assembled with (tools/dep-digest.py)."""


def dep_digest(site, artifact_id):
    """The digest of the content of the local repository copies of the Lutece jars a site carries, the artefact's own
    left out: it changes when a dependency is rebuilt and installed locally, whatever the dates of its files."""
    r = sh("python3", BENCH / "tools/dep-digest.py", site, artifact_id)
    return r.stdout.strip() if r.returncode == 0 else ""


def base_site(bench, artifact_id):
    """The assembled site of the bench's composition without the artefact's own jar, cached by site_key. A miss
    assembles it once with gen-site.sh, which installs the artefact first; a hit only packages the artefact. A cached
    site whose Lutece dependencies were rebuilt locally since (their content, DEPS), or one cached without that record,
    is assembled again."""
    gen_site(bench, "--pom-only")
    key = site_key(bench)
    base = HOME / "sites" / key
    if base.exists() and (not (base / DEPS).is_file() or (base / DEPS).read_text().strip() != dep_digest(base, artifact_id)):
        log("build: site %s may carry a Lutece dependency rebuilt since, assembled again" % key)
        shutil.rmtree(base)
    if base.exists():
        mvn = os.environ.get("MVN", "mvn").split()
        r = subprocess.run(mvn + ["-B", "-q", "-o", "-f", str(bench.src / "pom.xml"), "package", "-Dmaven.test.skip=true"])
        if r.returncode:
            r = subprocess.run(mvn + ["-B", "-q", "-f", str(bench.src / "pom.xml"), "package", "-Dmaven.test.skip=true"])
        if r.returncode:
            raise SystemExit("build: mvn package of %s failed" % bench.src)
        log("build: site %s from the cache, artefact packaged" % key)
        return base
    gen_site(bench)
    assembled = next(p for p in (bench.build / "target").glob("e2e-site-*") if p.is_dir())
    tmp = base.with_name(base.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(assembled, tmp)
    for jar in (tmp / "WEB-INF/lib").glob(artifact_id + "-*.jar"):
        jar.unlink()
    (tmp / DEPS).write_text(dep_digest(tmp, artifact_id) + "\n")
    tmp.rename(base)
    log("build: site %s assembled and cached" % key)
    return base


def latest(*coordinates):
    """The latest Lutece 8 snapshot of each groupId:artifactId, as {coordinate: (version, build)} (tools/latest-lutece.py)."""
    r = sh("python3", BENCH / "tools/latest-lutece.py", "snapshot", *coordinates)
    if r.returncode:
        raise SystemExit("build: no latest Lutece 8 snapshot for %s: %s" % (" ".join(coordinates), r.stderr[-300:]))
    found = {}
    for line in r.stdout.split():
        g, a, v, *b = line.split(":")
        found["%s:%s" % (g, a)] = (v, b[0] if b else "")
    return found


def kind(coordinate):
    """The Maven type a Lutece artefact is declared with in a site pom: lutece-core, lutece-plugin for a plugin or a
    module, otherwise its packaging when its pom is in the local repository (a starter is a pom), jar by default."""
    g, a = coordinate.split(":")
    if a == "lutece-core" or re.match(r"(plugin|module)-", a):
        return "lutece-core" if a == "lutece-core" else "lutece-plugin"
    poms = sorted((M2 / g.replace(".", "/") / a).glob("*/%s-*.pom" % a), key=lambda p: p.stat().st_mtime)
    m = re.search(r"<packaging>([^<]+)</packaging>", re.sub(r"<parent>.*?</parent>", "", poms[-1].read_text(), flags=re.S)) if poms else None
    return m.group(1) if m else "jar"


def force_versions(pom, forced):
    """Write the pom from the site's own, each forced artefact declared directly in its project dependencies (outside
    dependencyManagement and profiles) so that its version wins over the one a BOM manages."""
    t = pom.with_suffix(".site").read_text()
    masked = re.sub(r"<(dependencyManagement|profiles)>.*?</\1>", lambda m: " " * len(m.group(0)), t, flags=re.S)
    at = masked.find("</dependencies>")
    if at < 0:
        raise SystemExit("build: %s has no <dependencies> to force the Lutece versions in" % pom)
    deps = "".join("        <dependency><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version><type>%s</type></dependency>\n"
                   % (*c.split(":"), v, kind(c)) for c, (v, _) in sorted(forced.items()))
    pom.write_text(t[:at] + deps + "    " + t[at:])


def held_back(copy, profile):
    """The Lutece artefacts the forced versions need newer than the site's BOM manages them, read from the upper-bound
    rule of the site's enforcer (`<managed version> (managed) <-- <version asked>`). Any other failure of the validation
    stops the build: assembling without the enforcer would hide it."""
    mvn = os.environ.get("MVN", "mvn").split()
    r = subprocess.run(mvn + ["-B", "validate", *(["-P" + profile] if profile else [])], cwd=copy, capture_output=True, text=True)
    if r.returncode and "RequireUpperBoundDeps" not in r.stdout:
        raise SystemExit("build: mvn validate of the site failed for another reason than the versions forced:\n" + r.stdout[-1500:])
    return sorted({m.group(1) for m in re.finditer(r"\+-(fr\.paris\.lutece[\w.]*:[\w.-]+):(\S+) \(managed\) <-- \1:(\S+)", r.stdout)
                   if m.group(2) != m.group(3)})


def site_target(bench):
    """A site under test assembled with its own pom (tools/site-assemble.sh, Maven profile E2E_SITE_PROFILE) from a copy
    of its sources, the latest Lutece 8 snapshots forced over its BOM as on a plugin bench: the core, plugin-liquibase,
    then every Lutece artefact they need newer than the BOM gives, until none is held back. Cached by the content of
    the sources and those builds, reused for an hour (the time latest-lutece.py trusts a snapshot), then assembled again
    with every snapshot checked against the remote repositories. The site's enforcer is skipped for the assembly: its
    upper-bound rule judges the versions the site ships, not the newer ones the bench forces."""
    profile = os.environ.get("E2E_SITE_PROFILE", "")
    copy = bench.state / "site-src"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(bench.src, copy, ignore=shutil.ignore_patterns("target", ".git", "e2e"))
    shutil.copyfile(copy / "pom.xml", copy / "pom.site")
    forced = latest("fr.paris.lutece:lutece-core", "fr.paris.lutece.plugins:plugin-liquibase")
    for _ in range(5):
        force_versions(copy / "pom.xml", forced)
        more = [c for c in held_back(copy, profile) if c not in forced]
        if not more:
            break
        forced.update(latest(*more))
    else:
        raise SystemExit("build: the forced Lutece versions still need newer ones after five rounds: %s" % ", ".join(more))
    log("build: forced over the site's BOM: %s" % ", ".join("%s %s%s" % (c.split(":")[1], v, " (" + b + ")" if b else "") for c, (v, b) in sorted(forced.items())))
    h = hashlib.sha1((profile + repr(sorted(forced.items()))).encode() + (BENCH / "tools/site-assemble.sh").read_bytes())
    for f in sorted(p for p in copy.rglob("*") if p.is_file() and p.name != "pom.site"):
        h.update(str(f.relative_to(copy)).encode() + f.read_bytes())
    base = HOME / "sites" / ("site-" + h.hexdigest()[:12])
    if base.exists() and time.time() - base.stat().st_mtime < 3600:
        log("build: site %s from the cache" % base.name)
        return base
    tmp = base.with_name(base.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    t = time.time()
    r = subprocess.run(["bash", str(BENCH / "tools/site-assemble.sh"), str(copy), "--out", str(tmp), "--update",
                        *(["--profile", profile] if profile else [])],
                       env=dict(os.environ, MAVEN_ARGS=(os.environ.get("MAVEN_ARGS", "") + " -Denforcer.skip=true").strip()))
    if r.returncode:
        raise SystemExit("build: the site did not assemble (%s.log)" % tmp)
    for old in [p for p in (HOME / "sites").glob("site-*") if p != tmp]:
        shutil.rmtree(old, ignore_errors=True) if old.is_dir() else old.unlink()
    tmp.rename(base)
    for f in tmp.parent.glob(tmp.name + ".*"):
        f.unlink()
    log("build: site %s assembled in %.0fs" % (base.name, time.time() - t))
    return base


def cmd_build(bench):
    """The bench site: hard links to the cached base, then the artefact's jar and webapp zip (a plugin) or nothing (a
    site, assembled whole), then the bench's own site files, then the bench settings (FreeMarker reads a template once;
    the bench empties the cache after a change). A site gets the configuration probe (tools/site-config-dump.jsp, its
    token in artifacts/site-config-dump.token) and its solr plugin pointed at the bench's core, as gen-site.sh does for
    a plugin: the default address names no core, and every search then fails."""
    site_under_test = os.environ.get("E2E_TARGET") == "site"
    art = None if site_under_test else artifact(bench.src)
    base = site_target(bench) if site_under_test else base_site(bench, art)
    site = bench.state / "site"
    shutil.rmtree(site, ignore_errors=True)
    if sh("cp", "-al", base, site).returncode:
        shutil.copytree(base, site)
    if art:
        put_artefact(bench, art)
    for own in (BENCH / "harness/site/webapp", bench.e2e / "harness/site/webapp"):
        for f in own.rglob("*") if own.is_dir() else []:
            if f.is_file():
                put(site / f.relative_to(own), f)
    put(site / "WEB-INF/conf/override/e2e-bench.properties", b"service.freemarker.templateUpdateDelay=86400\n")
    if site_under_test:
        token = secrets.token_hex(16)
        put(site / "site-config-dump.jsp", (BENCH / "tools/site-config-dump.jsp").read_text().replace("@@TOKEN@@", token).encode())
        (bench.e2e / "artifacts").mkdir(exist_ok=True)
        (bench.e2e / "artifacts/site-config-dump.token").write_text(token + "\n")
    solr = site / "WEB-INF/conf/override/plugins/search-solr.properties"
    if site_under_test and (site / "WEB-INF/conf/plugins/search-solr.properties").exists() and not solr.exists():
        put(solr, ("solr.server.address=http://solr:8983/solr/%s\nsolr.indexer.commit.size=10000\n" % os.environ.get("E2E_SOLR_CORE", "lutece")).encode())
    (bench.state / "built").write_text(str(time.time()))
    log("build: bench site %s" % site)


def put_artefact(bench, art):
    """The artefact's packaged jar and webapp zip (templates, JSP, bundles under WEB-INF/classes) into the bench site."""
    site = bench.state / "site"
    jar = next(j for j in (bench.src / "target").glob(art + "-*.jar") if not re.search(r"-(sources|javadoc|tests)\.jar$", j.name))
    put(site / "WEB-INF/lib" / jar.name, jar)
    for z in (bench.src / "target").glob(art + "-*-webapp.zip"):
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    put(site / info.filename, zf.read(info))


def server_files(bench):
    """server.xml serving /site on the bench's database, jvm.options and server.env, next to the bench site."""
    harness = BENCH / "harness/liberty"
    xml = (harness / "server.xml").read_text().replace('location="lutece.war"', 'location="/site"')
    xml = re.sub(r'(<variable\s+defaultValue=")[^"]*("\s+name="portal\.dbname"\s*/>)', r"\g<1>%s\2" % bench.db, xml)
    if 'location="/site"' not in xml or bench.db not in xml:
        raise SystemExit("up: server.xml could not be pointed at /site and at the database %s" % bench.db)
    (bench.state / "server.xml").write_text(xml)
    jvm = (harness / "jvm.options").read_text().rstrip("\n") + "\n"
    jvm += "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005\n"
    jvm += "-XX:TieredStopAtLevel=1\n"
    jvm += "".join(o + "\n" for o in os.environ.get("E2E_JVM_ARGS", "").split())
    (bench.state / "jvm.options").write_text(jvm)
    shutil.copyfile(harness / "server.env", bench.state / "server.env")


def pydeps():
    """The Python dependencies of the tests, installed once per requirements.txt into the machine state."""
    req = BENCH / "tools/requirements.txt"
    return HOME / "pydeps" / hashlib.sha1(req.read_bytes()).hexdigest()[:12]


def runner_up(bench):
    """The bench's runner, created when it is missing: Playwright image, the bench code at /bench (read-only), the
    project's e2e folder at /e2e, the Python dependencies installed once for the machine."""
    if running(bench.runner):
        return
    deps = pydeps()
    deps.parent.mkdir(parents=True, exist_ok=True)
    sh("docker", "rm", "-f", bench.runner)
    install = ("[ -f /pydeps/%s/.done ] || { rm -rf /pydeps/%s.tmp && pip install -q --target /pydeps/%s.tmp -r /bench/tools/requirements.txt "
               "&& touch /pydeps/%s.tmp/.done && mv /pydeps/%s.tmp /pydeps/%s 2>/dev/null; [ -f /pydeps/%s/.done ]; } || exit 1; exec sleep infinity"
               % ((deps.name,) * 7))
    r = sh("docker", "run", "-d", "--init", "--name", bench.runner, "--network", NET, "-p", "%d:9090" % bench.port(),
           *[a for h in NEIGHBOURS for a in ("--add-host", h + ":127.0.0.1")], "-u", UID, "-w", "/e2e", "-e", "E2E_DIR=/e2e", "-e", "E2E_BASE=http://localhost:9090/" + bench.context,
           "-e", "E2E_DB_HOST=db", "-e", "E2E_DB_NAME=" + bench.db, "-e", "E2E_MAIL_API=http://mail:8025",
           "-e", "HOME=/tmp", "-e", "PYTHONDONTWRITEBYTECODE=1", "-e", "PYTHONPATH=/pydeps/" + deps.name,
           "-v", "%s:/bench:ro" % BENCH, "-v", "%s:/e2e" % bench.e2e, "-v", "%s:/pydeps" % deps.parent,
           RUNNER_IMAGE, "sh", "-c", install)
    if r.returncode:
        raise SystemExit("up: the runner did not start: " + r.stderr[-400:])
    deadline = time.time() + 600
    while not (deps / ".done").exists():
        if not running(bench.runner):
            raise SystemExit("up: the runner stopped installing the test dependencies:\n" + sh("docker", "logs", bench.runner).stderr[-800:])
        if time.time() > deadline:
            raise SystemExit("up: the test dependencies were not installed in 10 minutes")
        time.sleep(0.5)


def neighbour(bench, name, image, opts, cmd=()):
    """One neighbour of the bench, started in the runner's network namespace with the docker options and command given."""
    sh("docker", "rm", "-f", "lpe2e-%s-%s" % (bench.name, name))
    r = sh("docker", "run", "-d", "--init", "--name", "lpe2e-%s-%s" % (bench.name, name), "--network", "container:" + bench.runner,
           *opts, image, *cmd)
    if r.returncode:
        raise SystemExit("up: %s did not start: %s" % (name, r.stderr[-400:]))


def neighbours_up(bench):
    """The bench's neighbours, in the runner's network namespace: the application and the browser reach them as
    localhost or by their usual names (fakes, oauth2, solr, elastic all resolve to 127.0.0.1 there). E2E_FAKES=1: the
    stand-ins of external systems on 9030 (the project's own in e2e/harness/fakes/extra, every call logged in
    artifacts/fakes/<channel>.log) and an OpenID Connect provider on 8080. E2E_SEARCH=1: Solr on 8983 (the schema of
    the site's solr plugin when it ships one, copied readable: a plugin zip can carry it in mode 640, which Solr's own
    user cannot read) and Elasticsearch on 9200. Started with the application, not awaited."""
    if os.environ.get("E2E_FAKES"):
        fakes = BENCH / "harness/fakes"
        tag = "lpe2e-fakes:" + hashlib.sha1(b"".join(f.read_bytes() for f in sorted(fakes.glob("*")) if f.is_file())).hexdigest()[:12]
        if sh("docker", "image", "inspect", tag).returncode and sh("docker", "build", "-q", "--network", "host", "-t", tag, fakes).returncode:
            raise SystemExit("up: the fakes image did not build")
        data = bench.e2e / "artifacts/fakes"
        shutil.rmtree(data, ignore_errors=True)
        data.mkdir(parents=True)
        extra = bench.e2e / "harness/fakes/extra"
        neighbour(bench, "fakes", tag, ["-u", UID, "-e", "PRO_GUID=" + os.environ.get("E2E_PRO_GUID", "e2e-pro-guid"),
                                         "-v", "%s:/data" % data, *(["-v", "%s:/app/extra:ro" % extra] if extra.is_dir() else [])])
        conf = bench.e2e / "harness/fakes/oauth2.json"
        neighbour(bench, "oauth2", "ghcr.io/navikt/mock-oauth2-server:2.1.10",
                  ["-e", "SERVER_PORT=8080", "-e", "JSON_CONFIG_PATH=/config/oauth2.json",
                   "-v", "%s:/config/oauth2.json:ro" % (conf if conf.exists() else fakes / "oauth2.json")])
    if os.environ.get("E2E_SEARCH"):
        schema = bench.state / "site/WEB-INF/plugins/solr/conf"
        core = os.environ.get("E2E_SOLR_CORE", "lutece")
        conf = bench.state / "solr-conf"
        shutil.rmtree(conf, ignore_errors=True)
        shutil.copytree(schema if (schema / "solrconfig.xml").exists() else BENCH / "harness/search/solr-conf", conf)
        for f in conf.rglob("*"):
            f.chmod(0o755 if f.is_dir() else 0o644)
        neighbour(bench, "solr", "solr:9.10.1-slim", ["-v", "%s:/solr-conf:ro" % conf],
                  ["sh", "-c", "if [ -f /solr-conf/solrconfig.xml ]; then exec solr-precreate %s /solr-conf; else exec solr-precreate %s; fi" % (core, core)])
        neighbour(bench, "elastic", "docker.elastic.co/elasticsearch/elasticsearch:9.5.3",
                  ["-e", "discovery.type=single-node", "-e", "xpack.security.enabled=false", "-e", "xpack.license.self_generated.type=basic",
                   "-e", "ES_JAVA_OPTS=" + os.environ.get("E2E_ES_HEAP", "-Xms1g -Xmx1g")])


def neighbours_ready(bench, timeout=180):
    """Wait for the search engines to answer, so the tests never meet an index still starting."""
    probes = [("solr", "http://localhost:8983/solr/admin/info/system"), ("elastic", "http://localhost:9200/_cluster/health")] if os.environ.get("E2E_SEARCH") else []
    deadline = time.time() + timeout
    for name, url in probes:
        while sh("docker", "exec", bench.runner, "curl", "-sf", "-m", "5", "-o", "/dev/null", url).returncode:
            if not running("lpe2e-%s-%s" % (bench.name, name)):
                raise SystemExit("up: %s stopped:\n%s" % (name, sh("docker", "logs", "--tail", "30", "lpe2e-%s-%s" % (bench.name, name)).stdout[-1500:]))
            if time.time() > deadline:
                raise SystemExit("up: %s does not answer after %ds" % (name, timeout))
            time.sleep(1)


def daemon_up(bench):
    """The bench's warm test daemon (runnerd.py) in the runner: started when none answers with the current code key,
    told to forget its sessions otherwise (the application and its database are new). Started before the application
    so that the browsers launch while Liberty boots; returns without waiting for them. The scope of e2e.conf
    (E2E_SCOPE) reaches the tests through the daemon's environment."""
    workers = os.environ.get("E2E_WORKERS", "4")
    env = ["-e", "LPE2E_VERSION=" + os.environ.get("LPE2E_VERSION", ""), "-e", "E2E_SCOPE=" + os.environ.get("E2E_SCOPE", "")]
    want = sh("docker", "exec", *env, bench.runner, "python", "-c",
              "import sys; sys.argv=['x']; sys.path.insert(0,'/bench/server'); import runnerd; print(runnerd.code(%s))" % workers).stdout.strip()
    have = sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "ping").stdout.strip()
    if have and have == want:
        sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "reset")
        return
    sh("docker", "exec", bench.runner, "pkill", "-f", "runnerd.py serve")
    sh("docker", "exec", "-d", *env, bench.runner, "sh", "-c",
       "exec python /bench/server/runnerd.py serve %s > /e2e/artifacts/.runnerd.out 2>&1" % workers)


def daemon_ready(bench, timeout=120):
    """Wait for the daemon's workers; exit with its output when it died."""
    out = bench.e2e / "artifacts/.runnerd.out"
    deadline = time.time() + timeout
    while time.time() < deadline:
        text = out.read_text() if out.exists() else ""
        if "warm workers" in text:
            return
        if "Traceback" in text or "Error" in text:
            raise SystemExit("runnerd did not start:\n" + text[-1500:])
        time.sleep(0.2)
    raise SystemExit("runnerd: no worker ready after %ds" % timeout)


def app_start(bench, site):
    """Start the bench's Liberty on a site directory and on the bench's database as it is; return the instant it
    started. Liberty's output directory outlives the container: its workarea keeps the JSP the pages compiled, so a
    run only compiles the ones whose source changed (Liberty compares them with the site's files). The Lutece logs it
    also holds are emptied, so a start is judged on its own errors only, never on those of an earlier start."""
    sh("docker", "rm", "-f", bench.app)
    logs = bench.e2e / "artifacts/logs"
    logs.mkdir(parents=True, exist_ok=True)
    env = bench.e2e / "harness/app.env"
    output = bench.state / "output"
    output.mkdir(exist_ok=True)
    for old in (output / "defaultServer/logs/lutece").glob("*.log"):
        old.unlink(missing_ok=True)
    since = sh("date", "-u", "+%Y-%m-%dT%H:%M:%S.%NZ").stdout.strip()
    r = sh("docker", "run", "-d", "--init", "--name", bench.app, "--network", "container:" + bench.runner, "-u", UID,
           "-e", "portal.serverName=db", "-e", "portal.dbname=" + bench.db, "-e", "portal.port=3306", "-e", "portal.user=lutece",
           "-e", "portal.password=lutece", "-e", "context.root=" + bench.context, "-e", "LIQUIBASE_ENABLED_AT_STARTUP=true",
           "-e", "MAIL_SERVER=mail", "-e", "MAIL_SERVER_PORT=1025",
           *(["--env-file", env] if env.exists() else []),
           "-v", "%s:/site" % site, "-v", "%s/server.xml:%s/server.xml:ro" % (bench.state, SERVER),
           "-v", "%s/jvm.options:%s/jvm.options:ro" % (bench.state, SERVER),
           "-v", "%s/server.env:%s/server.env:ro" % (bench.state, SERVER), "-v", "%s:/logs" % logs,
           "-v", "%s:/opt/wlp/output" % output, "-v", "%s:/bench:ro" % BENCH, "-v", "%s:%s:ro" % (bench.src, bench.src),
           "-v", "%s:%s:ro" % (M2, M2), IMAGE)
    if r.returncode:
        raise SystemExit("up: the application did not start: " + r.stderr[-400:])
    return since


def cmd_up(bench):
    """Start the bench: shared server, fresh database, runner, application; wait for it, then seed; the workers log in
    while the host takes the inventory."""
    site = bench.state / "site"
    if not site.is_dir():
        raise SystemExit("up: no bench site, run.sh build first")
    if hot_classes(bench):
        log("up: classes left by watch beside the jar, the jar is packaged again from the sources")
        if not package_jar(bench):
            raise SystemExit("up: mvn package failed; fix the sources or run lpe2e build")
    t0 = time.time()
    ensure_infra()
    sh("docker", "rm", "-f", bench.app)
    sql("DROP DATABASE IF EXISTS `%s`; CREATE DATABASE `%s`; GRANT ALL ON `%s`.* TO 'lutece'@'%%';" % ((bench.db,) * 3))
    server_files(bench)
    runner_up(bench)
    neighbours_up(bench)
    daemon_up(bench)
    since = app_start(bench, site)
    ready(bench, since)
    log("up: application ready in %.1fs, http://localhost:%d/%s" % (time.time() - t0, bench.port(), bench.context))
    seed(bench)
    neighbours_ready(bench)
    daemon_ready(bench)
    sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "login")


def ready(bench, since):
    """Wait for the application started at the given instant to deploy and answer its login page; exit with the cause
    and the whole log kept under artifacts/logs otherwise."""
    w = sh(BENCH / "server/watch-boot.sh", bench.app, since, "60")
    code = login_code(bench)
    if w.returncode or code != "200":
        (bench.e2e / "artifacts/logs").mkdir(parents=True, exist_ok=True)
        full = app_logs(bench)
        (bench.e2e / ("artifacts/logs/unhealthy-%s.log" % bench.app)).write_text(full)
        lines = [l for l in full.splitlines() if re.search(r"Migration failed for changeset|Reason: |Caused by|CWWKZ0002E| E ", l)][:6]
        raise SystemExit("%s unhealthy: %s, login page http %s (full log: artifacts/logs/unhealthy-%s.log)\n  %s"
                         % (bench.app, w.stdout.strip(), code, bench.app, "\n  ".join(l[:300] for l in lines)))


def login_code(bench):
    """The HTTP status of the application's login page, asked from the runner."""
    return sh("docker", "exec", bench.runner, "curl", "-s", "-m", "10", "-o", "/dev/null", "-w", "%{http_code}",
              "http://localhost:9090/%s/jsp/admin/AdminLogin.jsp" % bench.context).stdout


def cmd_restart(bench):
    """Restart the JVM inside the application container: the shell loop of the image starts it again, the runner keeps
    the network namespace and the host port."""
    t = time.time()
    since = sh("date", "-u", "+%Y-%m-%dT%H:%M:%S.%NZ").stdout.strip()
    sh("docker", "exec", bench.app, "/opt/wlp/bin/server", "stop", "defaultServer")
    ready(bench, since)
    sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "reset")
    sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "login")
    log("restart: application ready in %.1fs" % (time.time() - t))


def seed(bench):
    """Run the post-init and seed scripts on the bench's database: the generic ones of the bench code, the bench's own
    from its harness/db."""
    own = bench.e2e / "harness/db"
    r = subprocess.run(["docker", "run", "--rm", "--network", NET, "-v", "%s/harness/db:/db:ro" % BENCH,
                        *(["-v", "%s:/e2e-db:ro" % own] if own.is_dir() else []),
                        "-e", "E2E_DB_NAME=" + bench.db, "-e", "E2E_VOLUME=" + os.environ.get("E2E_VOLUME", "none"),
                        "-e", "E2E_VERSION=" + os.environ.get("E2E_VERSION", "v8"), "--entrypoint", "sh", "mariadb:11.8", "/db/seed.sh"])
    if r.returncode:
        raise SystemExit("up: the seed failed")


def app_logs(bench):
    """The application console, then its Lutece Liquibase and error logs."""
    out = sh("docker", "logs", bench.app)
    files = sh("docker", "exec", bench.app, "sh", "-c",
               'd="${LUTECE_LOG_DIRECTORY:-${WLP_OUTPUT_DIR:-/opt/wlp/output}/defaultServer/logs/lutece}"; cat "$d/liquibase.log" "$d/error.log" 2>/dev/null')
    return out.stdout + out.stderr + files.stdout


def snapshot(src, e2e=None):
    """Modification time of every file of the project a hot change can come from, and of the bench's scenarios and
    site overlay (e2e/harness/site/webapp: the test pages) when the bench's e2e folder is given."""
    out = {}
    tops = [src / "src", src / "webapp", src / "pom.xml"] + ([e2e / "scenarios", e2e / "harness/site/webapp"] if e2e else [])
    for base in tops:
        for f in ([base] if base.is_file() else base.rglob("*") if base.is_dir() else []):
            if f.is_file() and "/target/" not in str(f) and not f.name.startswith("."):
                out[f] = f.stat().st_mtime_ns
    return out


def related(bench, changed):
    """Words naming the tests a change can break: the JSP screens that reach the changed files (a template through the
    classes citing it, a class through the JSPs calling it), the front-office application ids of the plugin when a
    changed class is an XPage, else the words of the file names."""
    java = list((bench.src / "src/java").rglob("*.java"))
    jsps = list((bench.src / "webapp").rglob("*.jsp")) + list((bench.e2e / "harness/site/webapp").rglob("*.jsp"))
    classes, screens, fo = set(), set(), True
    for p in changed:
        if p.suffix in (".yaml", ".yml") and p.is_relative_to(bench.e2e / "scenarios"):
            screens.add(p.stem)
        elif p.suffix == ".jsp":
            screens.add(p.stem)
        elif p.suffix == ".java":
            classes.add(p.stem)
        elif p.suffix == ".html" and "templates" in p.parts:
            rel = "/".join(p.parts[p.parts.index("templates") + 1:])
            classes |= {j.stem for j in java if rel in j.read_text(errors="replace")}
    apps = {a for x in (bench.src / "webapp/WEB-INF/plugins").glob("*.xml")
            for a in re.findall(r"<application-id>\s*([^<\s]+)", x.read_text(errors="replace"))}
    for c in classes:
        bean = c[0].lower() + c[1:]
        hits = {j.stem for j in jsps if c in (t := j.read_text(errors="replace")) or bean in t}
        source = next((j for j in java if j.stem == c), None)
        xpage = bool(source and re.search(r"extends\s+MVCApplication|public\s+XPage\s+getPage", source.read_text(errors="replace")))
        fo &= xpage and not hits
        if xpage:
            hits |= apps
        screens |= hits or {c}
    if screens:
        return sorted(screens), (["fo"] if classes and fo and not [p for p in changed if p.suffix == ".jsp"] else None)
    return sorted({w for p in changed for w in re.findall(r"[A-Za-z][a-z0-9]+|[A-Z]+(?![a-z])", p.stem) if len(w) > 3} | {p.stem for p in changed}), None


def classpath(bench):
    """The project's compile classpath as Maven resolves it (the Jakarta APIs Liberty provides included), its own
    classes first; the sources and the local Maven repository are mounted in the application at the same paths. Cached
    until the pom changes."""
    cache = bench.state / "classpath"
    pom = bench.src / "pom.xml"
    if not cache.exists() or cache.stat().st_mtime < pom.stat().st_mtime:
        mvn = os.environ.get("MVN", "mvn").split()
        r = subprocess.run(mvn + ["-B", "-q", "-o", "-f", str(pom), "dependency:build-classpath", "-Dmdep.outputFile=" + str(cache)])
        if r.returncode:
            raise SystemExit("watch: mvn dependency:build-classpath failed")
    return str(bench.src / "target/classes") + ":" + cache.read_text().strip()


class Hot:
    """The warm compiler and redefiner (HotServer.java), in the application container, attached to its JDWP port."""

    def __init__(self, bench):
        """Start it and wait for READY."""
        self.proc = subprocess.Popen(["docker", "exec", "-i", bench.app, "java", "/bench/server/HotServer.java", "localhost:5005",
                                      classpath(bench), "/tmp/lpe2e-hot"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        line = self.proc.stdout.readline().strip()
        if line != "READY":
            raise SystemExit("watch: the hot compiler did not start: " + line)

    def apply(self, paths):
        """Compile and redefine one batch; return its answer line (OK, COMPILE_ERROR, RESTART)."""
        self.proc.stdin.write(" ".join(paths) + "\n")
        self.proc.stdin.flush()
        return self.proc.stdout.readline().strip()

    def close(self):
        """Stop it."""
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


def keep_classes(bench):
    """Copy the classes of the last hot batch into the bench site's WEB-INF/classes (loaded before the jars), so a JVM
    restart keeps them; never written through a hard link of the site cache."""
    tmp = bench.state / "hot"
    shutil.rmtree(tmp, ignore_errors=True)
    batches = sh("docker", "exec", bench.app, "sh", "-c", "ls -t /tmp/lpe2e-hot | head -1").stdout.strip()
    if not batches:
        return
    sh("docker", "cp", "%s:/tmp/lpe2e-hot/%s" % (bench.app, batches), str(tmp))
    for f in tmp.rglob("*.class"):
        put(bench.state / "site/WEB-INF/classes" / f.relative_to(tmp), f)


def hot_classes(bench):
    """The classes the hot loop kept in the bench site for the project's sources: a source class, or an inner one."""
    own = bench.state / "site/WEB-INF/classes"
    return [f for f in (own.rglob("*.class") if own.is_dir() else [])
            if (bench.src / "src/java" / f.relative_to(own).with_suffix(".java")).exists() or "$" in f.name]


def package_jar(bench):
    """Package the artefact offline and put its jar and webapp zip into the bench site; the hot classes go, the jar now
    holds them. False when mvn package fails, the site unchanged."""
    mvn = os.environ.get("MVN", "mvn").split()
    if subprocess.run(mvn + ["-B", "-q", "-o", "-f", str(bench.src / "pom.xml"), "package", "-Dmaven.test.skip=true"]).returncode:
        return False
    put_artefact(bench, artifact(bench.src))
    for f in hot_classes(bench):
        f.unlink()
    return True


def rebuild(bench):
    """Package the jar into the bench site, then restart the JVM."""
    if not package_jar(bench):
        log("watch: mvn package failed, the running site is unchanged")
        return False
    cmd_restart(bench)
    return True


def suites(bench, words, only=None):
    """Every suite on the warm daemon (the ones named in only, when given), only the tests whose name holds one of the
    words when words are given; the worst exit code (None when no test ran) and the ids of the failed tests (a suite
    that failed without naming a test counts as one)."""
    k = ["-k", " or ".join(words)] if words else []
    plan = [("screens", "test_screens.py", []), ("fo", "test_fo.py", []), ("scenarios", "test_scenarios.py", ["-m", "not serial"]),
            ("scenarios", "test_scenarios.py", ["-m", "serial", "--serial"]), ("forms", "test_forms.py", [])]
    rc, ran, failed = 0, False, set()
    for name, f, extra in plan:
        if only and name not in only:
            continue
        junit = "artifacts/.watch-%s.xml" % name
        r = subprocess.run(["docker", "exec", "-w", "/e2e", bench.runner, "python", "/bench/server/runnerd.py", "suite", name, junit,
                            "/bench/tests/" + f, *extra, *k], capture_output=True, text=True)
        last = (r.stdout.strip().splitlines() or ["?"])[-1]
        ran |= r.returncode != 5
        if r.returncode not in (0, 5):
            rc = max(rc, r.returncode)
            named = {m.group(1) for m in re.finditer(r"^(?:FAILED|ERROR) (\S+\.py(?:::.+?)?)(?: - .*)?$", r.stdout, re.M)}
            failed |= named or {"%s rc=%d" % (name, r.returncode)}
            for line in r.stdout.splitlines():
                if line.startswith(("FAILED", "ERROR")):
                    log("  " + line[:200])
        log("  %-10s %s" % (name, last))
    return (rc if ran else None), failed


def apply(bench, hot, changed):
    """Put one batch of changed files into the running bench: a web file copied into the site (the FreeMarker cache and
    the kept browser contexts emptied), a Java method body compiled and redefined in the JVM, anything else (a new
    method, SQL, properties, plugin.xml, resources) a jar rebuild and a JVM restart. Return the hot compiler (a new one
    after a restart) and True when the batch is in place."""
    overlay = bench.e2e / "harness/site/webapp"
    web = [f for f in changed if f.is_relative_to(bench.src / "webapp") or f.is_relative_to(overlay)]
    java = [f for f in changed if f.suffix == ".java" and f.is_relative_to(bench.src / "src/java")]
    other = [f for f in changed if f not in web and f not in java and not f.is_relative_to(bench.src / "src/test")
             and not f.is_relative_to(bench.e2e)]
    for f in web:
        put(bench.state / "site" / f.relative_to(overlay if f.is_relative_to(overlay) else bench.src / "webapp"), f)
    if web:
        sh("docker", "exec", bench.runner, "bash", "/bench/server/reset_caches.sh", "reset")
        sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "flush")
        subprocess.Popen(["docker", "exec", bench.runner, "bash", "/bench/server/reset_caches.sh", "prime"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log("watch: %d web file(s) in place" % len(web))
    if java and not other:
        answer = hot.apply([str(f) for f in java])
        log("watch: java " + answer[:300])
        if answer.startswith("COMPILE_ERROR"):
            return hot, False
        if answer.startswith("OK"):
            keep_classes(bench)
        else:
            other = java
    if other:
        log("watch: %d change(s) the JVM cannot take hot (%s): jar and webapp zip packaged again, JVM restarted" % (len(other), ", ".join(f.name for f in other[:3])))
        hot.close()
        ok = rebuild(bench)
        hot = Hot(bench)
        if not ok:
            return hot, False
    return hot, True


def hot_start(bench, op):
    """The hot compiler of a running bench, the cache reset token primed; exit when no bench runs."""
    if not running(bench.app):
        raise SystemExit("%s: no running bench, start one with KEEP=1 lpe2e (or lpe2e up)" % op)
    hot = Hot(bench)
    subprocess.run(["docker", "exec", bench.runner, "bash", "/bench/server/reset_caches.sh", "prime"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return hot


def bench_lock(bench):
    """Take the bench lock run.sh takes (<e2e>/.run.lock), for the tests of one batch; False when a live run holds it."""
    d = bench.e2e / ".run.lock"
    try:
        d.mkdir()
    except FileExistsError:
        pid = (d / "pid").read_text().strip() if (d / "pid").exists() else ""
        try:
            os.kill(int(pid), 0)
            return False
        except (ValueError, ProcessLookupError, PermissionError):
            shutil.rmtree(d, ignore_errors=True)
            return bench_lock(bench)
    (d / "pid").write_text(str(os.getpid()))
    (d / "started").write_text(time.strftime("%F %T"))
    (d / "cmd").write_text("lpe2e watch (tests of a batch)")
    return True


def cmd_watch(bench):
    """The hot loop: apply each batch of changes, then the related tests, then every suite. A changed scenario file
    runs its scenarios, a changed test page (e2e/harness/site/webapp) is served at once; a change no test names runs
    the scenarios. The bench lock is held only while the tests of a batch run, so lpe2e test works between batches."""
    hot = hot_start(bench, "watch")
    log("watch: %s (%s), Ctrl-C to stop" % (bench.src, bench.app))
    seen = snapshot(bench.src, bench.e2e)
    try:
        while True:
            time.sleep(0.2)
            now = snapshot(bench.src, bench.e2e)
            changed = [f for f, m in now.items() if seen.get(f) != m]
            if not changed:
                continue
            time.sleep(0.1)
            now = snapshot(bench.src, bench.e2e)
            changed = sorted(f for f, m in now.items() if seen.get(f) != m)
            seen = now
            t = time.time()
            hot, ok = apply(bench, hot, changed)
            if not ok:
                continue
            log("watch: applied in %.2fs" % (time.time() - t))
            if not bench_lock(bench):
                log("watch: another run holds the bench (%s), the tests of this batch are left to it" % (bench.e2e / ".run.lock/cmd").read_text().strip())
                continue
            try:
                words, only = related(bench, changed)
                log("watch: tests related to %s%s" % (", ".join(words[:8]), " (front office)" if only else ""))
                rc_fast, _ = suites(bench, words, only)
                if rc_fast is None:
                    log("watch: no test named after the change, the scenarios instead")
                    rc_fast, _ = suites(bench, [], ["scenarios"])
                log("watch: first verdict %s in %.1fs" % ("rc=%d" % rc_fast if rc_fast is not None else "none (no related test)", time.time() - t))
                rc, _ = suites(bench, [])
                log("watch: full verdict rc=%d in %.1fs" % (rc, time.time() - t))
            finally:
                shutil.rmtree(bench.e2e / ".run.lock", ignore_errors=True)
    except KeyboardInterrupt:
        hot.close()


def selftest_target(src):
    """The Java file, the method and the template the selftest breaks: the first front-office XPage (a class with
    getPage) and the first template it cites, a list one first; else the first JspBean with a getManage method and its
    TEMPLATE_MANAGE template. None when the project has neither."""
    java = sorted((src / "src/java").rglob("*.java"))
    templates = src / "webapp/WEB-INF/templates"
    for p in java:
        text = p.read_text(errors="replace")
        if re.search(r"public\s+XPage\s+getPage\s*\(", text):
            cited = sorted((c for c in re.findall(r'"(skin/[^"]+\.html)"', text) if (templates / c).is_file()), key=lambda c: "list" not in c)
            if cited:
                return p, "getPage", templates / cited[0]
    for p in java:
        text = p.read_text(errors="replace")
        m = re.search(r"public\s+String\s+(getManage\w*)\s*\(", text)
        t = re.search(r'TEMPLATE_MANAGE\w*\s*=\s*"(admin/[^"]+\.html)"', text)
        if p.name.endswith("JspBean.java") and m and t and (templates / t.group(1)).is_file():
            return p, m.group(1), templates / t.group(1)
    return None


def source(path):
    """The text of a source file with every byte kept: line endings untouched, any encoding read as Latin-1."""
    return path.read_bytes().decode("latin-1")


def write_source(path, text):
    """Write a text read by source() back to the same bytes."""
    path.write_bytes(text.encode("latin-1"))


def break_template(text):
    """The template with a FreeMarker directive left open: it no longer parses."""
    return text + "\n<#if broken"


def break_java(text, method):
    """The source with a throw at the start of the body of the method declared with that name; exit when none is."""
    out, n = re.subn(r"(\b%s\s*\([^)]*\)[^{;]*\{)" % re.escape(method), r'\1 if ( true ) throw new RuntimeException( "e2e selftest" );', text, count=1)
    if not n:
        raise SystemExit("selftest: no declaration of %s to break" % method)
    return out


def judge(step, known, failed, red):
    """Whether a step got what it expects, at least one failure new against the baseline when red is expected and none
    when green is, and its SELFTEST line."""
    new = failed - known
    good = bool(new) == red
    return good, "SELFTEST %s %s (%d new failure(s), expected %s)" % (step, "OK" if good else "MISSED", len(new), "red" if red else "green")


def cmd_selftest(bench):
    """Prove the hot loop misses no bug: a baseline verdict, then a template bug and a Java bug each injected right
    after a render through the hot loop's own path, each required red, then reverted and required green; red and green
    count the failures new against the baseline. The sources are restored whatever happens, and the classes the hot
    loop kept for them removed from the bench site (beside the jar, they make a bean ambiguous at the next start). Exit
    0 when every step got what it expects."""
    target = selftest_target(bench.src)
    if target is None:
        raise SystemExit("selftest: no front-office XPage nor manage JspBean to break")
    java, method, tpl = target
    original = {p: (source(p), p.stat()) for p in (tpl, java)}
    steps = [("baseline", {}, False), ("template bug", {tpl: break_template(original[tpl][0])}, True),
             ("template revert", {tpl: original[tpl][0]}, False), ("java bug", {java: break_java(original[java][0], method)}, True),
             ("java revert", {java: original[java][0]}, False)]
    hot = hot_start(bench, "selftest")
    if login_code(bench) != "200":
        hot.close()
        raise SystemExit("selftest: the application does not answer its login page (lpe2e logs)")
    classes = bench.state / "site/WEB-INF/classes"
    kept = set(classes.rglob("*.class"))
    log("selftest: %s, %s.%s" % (tpl.relative_to(bench.src), java.stem, method))
    ok, known = True, set()
    try:
        for step, edits, red in steps:
            t = time.time()
            for p, text in edits.items():
                write_source(p, text)
            if edits:
                hot, _ = apply(bench, hot, list(edits))
            _, failed = suites(bench, [])
            if step == "baseline":
                known = failed
            good, line = judge(step, known, failed, red)
            ok &= good
            log("selftest: %s judged in %.1fs" % (step, time.time() - t))
            log(line)
    finally:
        back = [p for p, (text, _) in original.items() if source(p) != text]
        for p in back:
            write_source(p, original[p][0])
        if back:
            hot, _ = apply(bench, hot, back)
        hot.close()
        for f in set(classes.rglob("*.class")) - kept:
            f.unlink()
        for p, (_, st) in original.items():
            os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
    log("SELFTEST " + ("PASSED" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


def cmd_down(bench):
    """Remove the bench's containers and database; the shared server stays for the other benches."""
    sh("docker", "rm", "-f", bench.app, bench.app + "7", *("lpe2e-%s-%s" % (bench.name, n) for n in NEIGHBOURS), bench.runner)
    if running(DB):
        sql("DROP DATABASE IF EXISTS `%s`;" % bench.db)
    log("down: %s removed" % bench.name)


def cmd_status(bench):
    """One line per container of the bench and of the shared server."""
    for c in (bench.runner, bench.app, DB, MAIL):
        s = sh("docker", "inspect", "-f", "{{.State.Status}}", c).stdout.strip() or "absent"
        print("%-40s %s" % (c, s))


def main():
    """Entry point."""
    op = sys.argv[1] if len(sys.argv) > 1 else ""
    bench = Bench()
    if op == "build":
        cmd_build(bench)
    elif op == "up":
        cmd_up(bench)
    elif op == "seed":
        seed(bench)
    elif op == "restart":
        cmd_restart(bench)
    elif op == "watch":
        cmd_watch(bench)
    elif op == "selftest":
        cmd_selftest(bench)
    elif op == "down":
        cmd_down(bench)
    elif op == "logs":
        sys.stdout.write(app_logs(bench))
    elif op == "status":
        cmd_status(bench)
    elif op == "port":
        print(bench.port())
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
