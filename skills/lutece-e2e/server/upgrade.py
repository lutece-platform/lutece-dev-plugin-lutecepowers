#!/usr/bin/env python3
"""The database upgrade of a bench, driven by run.sh upgrade (reference/upgrade.md).

    upgrade.py    the database of the previous version, then the bench site takes it over, the way an environment does

The previous version's database is one of: a v7 site (tools/gen-site7.sh) installed by its Ant build and seeded
(E2E_VERSION=v7), the default for a plugin with E2E_V7_REF or a site with E2E_V7_WAR; a recette dump (E2E_V7_DUMP);
the bench site's previous Lutece 8 version (E2E_BEFORE_WAR) started on a fresh database. A v7 database is then brought
under Liquibase as the environments will: the v7 site with the plugin-liquibase of the v7 line, started once in
Tomcat. The bench site takes it over in a normal start, or in the two passes of E2E_TAKEOVER (required for a site). The
run is left up, seeded and logged in, for the suites. What ran and what was lost is written under artifacts/.

Exit 0 when the bench site runs on the taken-over database, 11 when the database upgrade failed (the v7 preparation or
the takeover), 2 on a configuration error, 1 when the bench itself failed.
"""
import hashlib
import json
import os
import pathlib
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from server import (Bench, app_start, sh, log, put, sql, ensure_infra, runner_up, neighbours_up, neighbours_ready, daemon_up,
                    daemon_ready, server_files, ready, seed, app_logs, cmd_restart, UID, BENCH, HOME,
                    DB, NET)

UPGRADE_FAILED = 11
LIQUIBASE = "fr.paris.lutece.plugins:plugin-liquibase"
SETTINGS = ("SELECT CONCAT(entity_key,' = ',entity_value) FROM core_datastore WHERE entity_key LIKE 'core.advanced_parameters.%' "
            "OR entity_key LIKE 'portal.%site_property%' OR entity_key LIKE 'core.cache.status.%' OR entity_key LIKE 'theme%' ORDER BY 1")
STATUS = ("SELECT CONCAT(entity_key,' = ',entity_value) FROM core_datastore WHERE entity_key LIKE 'core.plugins.status.%' "
          "OR entity_key LIKE 'core.theme.status.%' ORDER BY 1")
VERSIONS = "SELECT CONCAT(entity_key,' = ',entity_value) FROM core_datastore WHERE entity_key LIKE 'core.plugins.status.%.version' ORDER BY 1"
CHANGESETS = "SELECT CONCAT(EXECTYPE,' ',FILENAME,' ',ID) FROM DATABASECHANGELOG ORDER BY ORDEREXECUTED, DATEEXECUTED"
UNRESOLVED = r"No plugin metadata for (\S+)|resolves to component '([^']+)' which is not declared"
OWN = ("liquibase-changesets.txt", "liquibase-versions-after.txt", "liquibase-failure.txt",
       "liquibase-invisible.txt", "datastore-v7.txt", "datastore-before.txt", "datastore-v8.txt", "datastore-lost.txt",
       "datastore-defaults.txt",
       "upgrade-disabled.txt", "upgrade-orphans.txt", "components-without-version.txt", "v7-liquibase-unmanaged.txt")
DATASTORE_UPDATE = re.compile(r"UPDATE\s+core_datastore\s+SET\s+entity_value\s*=\s*'((?:[^'\\]|\\.|'')*)'\s+WHERE\s+"
                              r"entity_key\s*=\s*'([^']+)'\s+AND\s+entity_value\s*=\s*'((?:[^'\\]|\\.|'')*)'", re.I)
"""An upgrade statement replacing one value of a key by another: a default the new version changes on purpose."""
DATASTORE_ROW = re.compile(r"\(\s*'([^']+)'\s*,\s*'((?:[^'\\]|\\.|'')*)'\s*\)")
GEN_SITE7 = ("E2E_TARGET", "E2E_SRC", "E2E_ENABLE", "E2E_MYLUTECE", "E2E_MVN7", "E2E_SOLR_CORE")


class Failed(Exception):
    """The database upgrade failed, in the v7 preparation or in the takeover: the message says where."""


def db(bench, query):
    """The lines a query returns on the bench's database (no header)."""
    r = sh("docker", "exec", DB, "mariadb", "-ulutece", "-plutece", "-N", "-B", bench.db, "-e", query)
    return [l for l in r.stdout.splitlines() if l.strip()]


def db_load(bench, path):
    """Play a SQL file (gzipped or not) on the bench's database, a row up to 1 GB (a file stored in the database); the
    return code of the client."""
    path = pathlib.Path(path)
    data = subprocess.run(["gzip", "-dc", str(path)], capture_output=True).stdout if path.suffix == ".gz" else path.read_bytes()
    sql("SET GLOBAL max_allowed_packet = 1073741824")
    r = subprocess.run(["docker", "exec", "-i", DB, "mariadb", "-ulutece", "-plutece", "--max-allowed-packet=1G", bench.db], input=data, capture_output=True)
    if r.returncode:
        log("  " + r.stderr.decode(errors="replace").strip()[:400])
    return r.returncode


def write(bench, name, lines):
    """Write lines into artifacts/<name>; return their count."""
    (bench.e2e / "artifacts" / name).write_text("".join(l + "\n" for l in lines))
    return len(lines)


def usage(msg):
    """Stop on a configuration error of the bench (exit 2)."""
    print(msg, file=sys.stderr)
    sys.exit(2)


def fresh_db(bench):
    """An empty bench database."""
    sql("DROP DATABASE IF EXISTS `%s`; CREATE DATABASE `%s`; GRANT ALL ON `%s`.* TO 'lutece'@'%%';" % ((bench.db,) * 3))


def follow(container, since, done, fatal, quiet=120):
    """Follow a container's console from an instant; return (verdict, line): OK on a line matching done, FAIL on one
    matching fatal, STOPPED when the container ends, HANG after quiet seconds without a line."""
    p = subprocess.Popen(["docker", "logs", "-f", "--since", since, container], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    lines = queue.Queue()
    threading.Thread(target=lambda: [lines.put(l) for l in p.stdout] + [lines.put(None)], daemon=True).start()
    try:
        while True:
            try:
                line = lines.get(timeout=quiet)
            except queue.Empty:
                return "HANG", "no console line for %ds" % quiet
            if line is None:
                return "STOPPED", "the container stopped"
            if re.search(fatal, line):
                return "FAIL", line.strip()
            if re.search(done, line):
                return "OK", line.strip()
    finally:
        p.kill()


def now():
    """The current instant, as docker logs --since reads it."""
    return sh("date", "-u", "+%Y-%m-%dT%H:%M:%S.%NZ").stdout.strip()


def liquibase_failure(bench, text):
    """The changeset and the reason of a Liquibase failure in an application log, written to
    artifacts/liquibase-failure.txt; None when the log holds none."""
    lines = [l.strip()[:400] for l in text.splitlines() if re.search(r"Migration failed for changeset|Reason: |LiquibaseRunner failed|Caused by", l)]
    if not lines:
        return None
    write(bench, "liquibase-failure.txt", lines)
    changeset = next((m.group(1) for l in lines for m in [re.search(r"Migration failed for changeset (\S+?):?$", l)] if m), None)
    reason = next((l[l.index("Reason: "):] for l in lines if "Reason: " in l), None)
    return "\n  ".join([("changeset " + changeset) if changeset else lines[0]] + ([reason] if reason else []))


def v8_start(bench, site, what):
    """Start Liberty on a site and wait for it to answer; Failed with the changeset and the reason when Liquibase
    stopped, or with the cause of the failed start."""
    since = app_start(bench, site)
    t = time.time()
    try:
        ready(bench, since)
    except (SystemExit, TypeError) as e:
        why = liquibase_failure(bench, app_logs(bench))
        (bench.e2e / "artifacts/logs" / ("unhealthy-%s.log" % bench.app)).write_text(app_logs(bench))
        raise Failed("%s: %s" % (what, ("LIQUIBASE FAILED\n  " + why) if why else getattr(e, "code", e)))
    log("upgrade: %s, application ready in %.0fs" % (what, time.time() - t))


def stop(bench):
    """Stop the bench's application, its log kept under artifacts/logs."""
    (bench.e2e / "artifacts/logs" / ("%s-%d.log" % (bench.app, int(time.time())))).write_text(app_logs(bench))
    sh("docker", "rm", "-f", bench.app)


def liquibase7():
    """groupId:artifactId:version of the plugin-liquibase of the Lutece 7 line, read in the repositories."""
    r = sh(sys.executable, BENCH / "tools/latest-lutece.py", "snapshot", "--line", "7", LIQUIBASE)
    if r.returncode or not r.stdout.strip():
        raise SystemExit("upgrade: no plugin-liquibase of the Lutece 7 line found: " + r.stderr.strip())
    return ":".join(r.stdout.strip().split(":")[:3])


def v7_key(bench, liquibase):
    """Key of the v7 site: the v7 sources, the bench configuration that shapes the site, the v7 war of a site, the
    bench code that assembles it, the plugin-liquibase it carries."""
    h = hashlib.sha1(liquibase.encode())
    h.update(sh("git", "-C", bench.src, "rev-parse", os.environ.get("E2E_V7_REF", "HEAD")).stdout.encode())
    h.update(repr(sorted((k, v) for k, v in os.environ.items() if k in GEN_SITE7 or k.startswith("E2E_V7_") and k not in ("E2E_V7_DUMP", "E2E_V7_SAFE_RUN"))).encode())
    files = [BENCH / "tools/gen-site7.sh", BENCH / "harness/site/plugins.dat.tpl"]
    for d in (bench.e2e / "harness/site/webapp", bench.e2e / "harness/src7-overlay", bench.e2e / "harness/v7-overlay", BENCH / "harness/site7"):
        files += sorted(p for p in d.rglob("*") if p.is_file()) if d.is_dir() else []
    for f in files:
        if f.is_file():
            h.update(str(f).encode() + f.read_bytes())
    war = pathlib.Path(os.environ.get("E2E_V7_WAR", ""))
    if os.environ.get("E2E_V7_WAR") and war.is_dir():
        for p in sorted(war.rglob("*")):
            if p.is_file():
                h.update(str(p.relative_to(war)).encode() + str(p.stat().st_size).encode())
    return h.hexdigest()[:12]


def site7(bench):
    """The cached v7 site of the bench (HOME/sites7/<key>: site/ and versions.properties), assembled by gen-site7.sh
    with the plugin-liquibase of the v7 line on a miss."""
    liquibase = liquibase7()
    key = v7_key(bench, liquibase)
    base = HOME / "sites7" / key
    if (base / "versions.properties").exists():
        log("upgrade: v7 site %s from the cache (%s)" % (key, liquibase))
        return base
    env = dict(os.environ, E2E_DIR=str(bench.e2e), E2E_SITE7_BUILD=str(bench.state / "build7/site7"))
    if os.environ.get("E2E_TARGET") == "site":
        war = pathlib.Path(os.environ.get("E2E_V7_WAR", ""))
        if not list((war / "WEB-INF/lib").glob("plugin-liquibase-*.jar")):
            usage("upgrade: the v7 war %s has no plugin-liquibase: add %s of the Lutece 7 line to the v7 site's pom, "
                             "as the environments will before the migration" % (war, liquibase))
    else:
        env["E2E_V7_PLUGINS"] = ",".join(p for p in (os.environ.get("E2E_V7_PLUGINS", ""), liquibase + ":lutece-plugin") if p)
    t = time.time()
    if subprocess.run(["bash", str(BENCH / "tools/gen-site7.sh")], env=env).returncode:
        raise SystemExit("upgrade: gen-site7.sh failed")
    target = bench.state / "build7/site7/target"
    tmp = base.with_name(key + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    shutil.copytree(next(p for p in target.glob("e2e-site7-*") if p.is_dir()), tmp / "site")
    shutil.copyfile(target / "versions.properties", tmp / "versions.properties")
    shutil.rmtree(base, ignore_errors=True)
    tmp.rename(base)
    log("upgrade: v7 site %s assembled in %.0fs (%s)" % (key, time.time() - t, liquibase))
    return base


def bench_site7(bench, base):
    """The bench's copy of the v7 site: a real copy of the cache (Lutece 7 writes into its webapp, its configuration and
    its logs), the bench's database, Liquibase at startup, its safe run
    as E2E_V7_SAFE_RUN says (true by default, as plugin-liquibase ships it), its first-run detection confined to the
    bench's schema (the v7 line counts DATABASECHANGELOG in every schema of the shared MariaDB)."""
    site = bench.state / "site7"
    shutil.rmtree(site, ignore_errors=True)
    if sh("cp", "-a", base / "site", site).returncode:
        raise SystemExit("upgrade: the v7 site %s could not be copied" % base)
    conf = site / "WEB-INF/conf/db.properties"
    put(conf, re.sub(r"(?m)^(portal\.url=jdbc:mysql://db:3306/)[^?]*", r"\g<1>" + bench.db,
                     re.sub(r"(?m)^portal\.dbname=.*$", "portal.dbname=" + bench.db, conf.read_text())).encode())
    safe = os.environ.get("E2E_V7_SAFE_RUN", "true")
    put(site / "WEB-INF/conf/override/plugins/liquibase-plugin.properties", (
        "liquibase.enabled.at.startup=true\nliquibase.safeRun=%s\nliquibase.first.run.request=select count(*) FROM "
        "information_schema.tables where table_schema=database() and table_name='DATABASECHANGELOG';\n" % safe).encode())
    return site


def tomcat_image():
    """The generic Tomcat 9 image of the v7 site on the Java of E2E_V7_JAVA (11 by default), built once per Java,
    Dockerfile and entrypoint."""
    harness = BENCH / "harness"
    jdk = os.environ.get("E2E_V7_JAVA") or "11"
    tag = "lpe2e-tomcat:" + hashlib.sha1(jdk.encode() + (harness / "Dockerfile.tomcat").read_bytes() + (harness / "tomcat/entrypoint.sh").read_bytes()).hexdigest()[:12]
    if sh("docker", "image", "inspect", tag).returncode:
        r = sh("docker", "build", "-q", "--network", "host", "--build-arg", "JDK=" + jdk, "-t", tag, "-f", harness / "Dockerfile.tomcat", harness)
        if r.returncode:
            raise SystemExit("upgrade: the Tomcat image did not build: " + r.stderr[-500:])
    return tag


def tomcat(bench, image, site, *args, init=False):
    """docker run arguments of the v7 site on the bench's database: an Ant install (init) or a Tomcat start."""
    logs = bench.e2e / "artifacts/logs7"
    logs.mkdir(parents=True, exist_ok=True)
    return ["docker", "run", *args, "-u", UID, "-e", "E2E_CONTEXT=" + bench.context, "-e", "E2E_V7_INIT_DB=%d" % init,
            "-v", "%s:/usr/local/tomcat/webapps/%s" % (site, bench.context), "-v", "%s:/logs" % logs, image, *(["init"] if init else [])]


def v7_install(bench, image, site):
    """The v7 schema created by the v7 site's Ant build, then the bench seed of the v7 site (seed7-*.sql included) and
    the portlet types a v7 plugin installation registers."""
    t = time.time()
    r = subprocess.run(tomcat(bench, image, site, "--rm", "--network", NET, init=True), capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("upgrade: the v7 Ant install failed:\n" + (r.stdout + r.stderr)[-1500:])
    log("upgrade: v7 schema created by the Ant build in %.0fs (artifacts/logs7/ant-dbinit.log)" % (time.time() - t))
    os.environ["E2E_VERSION"] = "v7"
    try:
        seed(bench)
    finally:
        os.environ["E2E_VERSION"] = "v8"
    types = sh(sys.executable, BENCH / "tools/v7-portlet-types.py", site).stdout
    if types.strip():
        subprocess.run(["docker", "exec", "-i", DB, "mariadb", "-ulutece", "-plutece", bench.db], input=types, text=True)
        log("upgrade: %d portlet type(s) registered as a v7 plugin installation does" % types.count("INSERT"))


def v7_dump(bench):
    """A recette dump loaded as the v7 database; only the admin account gets the bench's password."""
    dump = pathlib.Path(os.environ["E2E_V7_DUMP"])
    if not dump.is_file():
        usage("upgrade: E2E_V7_DUMP: no such file: %s" % dump)
    if db_load(bench, dump):
        raise SystemExit("upgrade: the dump %s did not load" % dump)
    db(bench, "UPDATE core_admin_user SET password='PLAINTEXT:adminadmin', reset_password=0, password_max_valid_date='2099-01-01 00:00:00', status=0 WHERE access_code='admin'")
    log("upgrade: v7 database from the dump %s, admin account set to the bench's password" % dump.name)


def v7_liquibase(bench, image, site, versions):
    """The one v7 start with plugin-liquibase: it creates DATABASECHANGELOG and records the installed versions; stopped
    once Tomcat started. Returns the components the v7 site ships that it recorded no version for."""
    app7 = "lpe2e-%s-app7" % bench.name
    sh("docker", "rm", "-f", app7)
    since = now()
    t = time.time()
    r = sh(*tomcat(bench, image, site, "-d", "--name", app7, "--network", "container:" + bench.runner))
    if r.returncode:
        raise SystemExit("upgrade: the v7 site did not start: " + r.stderr[-400:])
    try:
        verdict, line = follow(app7, since, r"Server startup in", r"LiquibaseRunner failed|LiquibaseRunner not ready|LiquibaseRunner not enabled|Exception in thread")
    finally:
        out = sh("docker", "logs", app7)
        text = out.stdout + out.stderr
        (bench.e2e / "artifacts/logs/v7-liquibase-start.log").write_text(text)
        sh("docker", "rm", "-f", app7)
    unmanaged = [f for m in re.findall(r"LiquibaseRunner files not managed by liquibase are (.*)", text) for f in re.split(r"[\s,\[\]]+", m) if f]
    if unmanaged:
        write(bench, "v7-liquibase-unmanaged.txt", sorted(set(unmanaged)))
    if "LiquibaseRunner not ready to run stopping" in text:
        raise Failed("plugin-liquibase of the v7 line refuses to start: the v7 site ships SQL files without the Liquibase header (%s, "
                     "artifacts/v7-liquibase-unmanaged.txt). An environment meets the same refusal: fix those files in their "
                     "component, or start as an environment would with liquibase.safeRun=false (E2E_V7_SAFE_RUN=false in e2e.conf)"
                     % ", ".join(sorted(set(unmanaged))))
    if verdict != "OK" or "LiquibaseRunner ended" not in text or not db(bench, "SHOW TABLES LIKE 'DATABASECHANGELOG'"):
        reason = [l.strip()[:300] for l in text.splitlines() if re.search(r"LiquibaseRunner|SEVERE|Caused by|IllegalStateException", l)][-6:]
        raise Failed("the v7 start with plugin-liquibase did not bring the database under Liquibase (%s: %s)\n  %s\n  full log: artifacts/logs/v7-liquibase-start.log"
                     % (verdict, line[:300], "\n  ".join(reason)))
    recorded = {l.split(" = ")[0][len("core.plugins.status."):-len(".version")] for l in db(bench, VERSIONS)}
    shipped = [l.split("=")[0] for l in versions.read_text().splitlines() if "=" in l and not l.startswith("core=")]
    missing = sorted({n for n in shipped if n not in recorded} | {a or b for a, b in re.findall(UNRESOLVED, text)})
    log("upgrade: v7 start with plugin-liquibase in %.0fs: DATABASECHANGELOG created, %d version(s) recorded" % (time.time() - t, len(recorded)))
    if unmanaged:
        log("upgrade: SQL files of the v7 site plugin-liquibase does not manage (liquibase.safeRun=false): %s" % ", ".join(sorted(set(unmanaged))))
    return missing


def hand_apply(bench, site):
    """Apply by hand the upgrade scripts of the site Liquibase cannot see (tools/liquibase-visibility.sh), as a site
    would have to; return them."""
    out = sh("bash", BENCH / "tools/liquibase-visibility.sh", site).stdout
    (bench.e2e / "artifacts/liquibase-invisible.txt").write_text(out)
    applied = sorted(set(re.findall(r"sql/(?:\S+/)?upgrade/\S+\.sql", out)))
    for rel in applied:
        rc = db_load(bench, site / "WEB-INF" / rel)
        log("upgrade: HAND-APPLIED (Liquibase will never see it): %s%s" % (rel, " (with errors)" if rc else ""))
    return applied


def before_site(bench):
    """The bench's copy of E2E_BEFORE_WAR (a war or an exploded site) with the bench's own site files, as cmd_build lays
    them over the bench site."""
    src = pathlib.Path(os.environ["E2E_BEFORE_WAR"])
    site = bench.state / "before"
    shutil.rmtree(site, ignore_errors=True)
    if src.is_dir():
        if sh("cp", "-al", src, site).returncode:
            shutil.rmtree(site, ignore_errors=True)
            shutil.copytree(src, site)
    elif src.is_file():
        with zipfile.ZipFile(src) as z:
            z.extractall(site)
    else:
        usage("upgrade: E2E_BEFORE_WAR: no such war or directory: %s" % src)
    for own in (BENCH / "harness/site/webapp", bench.e2e / "harness/site/webapp"):
        for f in own.rglob("*") if own.is_dir() else []:
            if f.is_file():
                put(site / f.relative_to(own), f)
    put(site / "WEB-INF/conf/override/e2e-bench.properties", b"service.freemarker.templateUpdateDelay=86400\n")
    return site


def descriptors(site):
    """Plugin names declared by the descriptors of a site."""
    names = set()
    for x in (site / "WEB-INF/plugins").glob("*.xml"):
        m = re.search(r"<name>\s*([^<]+?)\s*</name>", re.sub(r"<!--.*?-->", "", x.read_text(errors="replace"), flags=re.S))
        if m:
            names.add(m.group(1))
    return names


def install_values(site):
    """The core_datastore values the init scripts of a site write on a fresh install, by key; empty without a site."""
    out = {}
    for f in sorted((site / "WEB-INF/sql").rglob("init*.sql")) if site else []:
        if "upgrade" in f.parts:
            continue
        for line in f.read_text(errors="replace").splitlines():
            if re.search(r"INSERT\s+INTO\s+core_datastore", line, re.I):
                out.update(DATASTORE_ROW.findall(line))
    return out


def default_changes(site):
    """(key, before, after) of every value an upgrade script of the site replaces by another."""
    return {(k, before, after) for f in (site / "WEB-INF/sql").rglob("*.sql") if "upgrade" in f.parts
            for after, k, before in DATASTORE_UPDATE.findall(f.read_text(errors="replace"))}


def settings_diff(before, after, site, previous):
    """The settings of the previous version the takeover changed, split in two: the defaults the new version replaces
    on purpose (an upgrade script turning that value into this one, or the previous install value turned into the new
    install value), and the real losses (a key gone, any other value overwritten)."""
    pairs = lambda lines: dict(l.split(" = ", 1) if " = " in l else (l.rstrip(" ="), "") for l in lines)
    b, a = pairs(before), pairs(after)
    old, new, updates = install_values(previous), install_values(site), default_changes(site)
    expected, lost = [], []
    for k, v in sorted(b.items()):
        if a.get(k) == v:
            continue
        if k in a and ((k, v, a[k]) in updates or (k in old and old[k] == v and new.get(k) == a[k])):
            expected.append("%s = %s -> %s" % (k, v, a[k]))
        else:
            lost.append("%s = %s -> %s" % (k, v, a[k]) if k in a else "%s = %s (gone)" % (k, v))
    return expected, lost


def report(bench, site, settings_before, changesets_before, missing, previous=None):
    """The artifacts of the takeover: what Liquibase ran, the versions after, the settings lost and the defaults the new
    version changed, the plugins left disabled, the orphan status keys, the components without recorded version; one
    line each."""
    known = {" ".join(l.split(" ")[1:]) for l in changesets_before}
    ran = [l for l in db(bench, CHANGESETS) if " ".join(l.split(" ")[1:]) not in known]
    write(bench, "liquibase-changesets.txt", ran)
    log("upgrade: Liquibase ran %d changeset(s) (artifacts/liquibase-changesets.txt): %s" % (
        len(ran), ", ".join("%s %d" % (k, sum(1 for l in ran if l.startswith(k + " "))) for k in sorted({l.split(" ")[0] for l in ran}))))
    versions = db(bench, VERSIONS)
    write(bench, "liquibase-versions-after.txt", versions)
    log("upgrade: %d version(s) recorded after the takeover (artifacts/liquibase-versions-after.txt)" % len(versions))
    after = db(bench, SETTINGS)
    write(bench, "datastore-v8.txt", after)
    expected, lost = settings_diff(settings_before, after, site, previous)
    write(bench, "datastore-defaults.txt", expected)
    n = write(bench, "datastore-lost.txt", lost)
    log("upgrade: %d datastore setting(s) of the previous version overwritten or gone (artifacts/datastore-lost.txt), "
        "%d default(s) the new version changes on purpose (artifacts/datastore-defaults.txt)" % (n, len(expected)))
    status = db(bench, STATUS)
    names = descriptors(site)
    installed = {l.split(" = ")[0][len("core.plugins.status."):-len(".installed")] for l in status
                 if l.endswith((".installed = true", ".installed = 1"))}
    n = write(bench, "upgrade-disabled.txt", sorted(names - installed))
    log("upgrade: %d plugin(s) of the site left disabled by the database (artifacts/upgrade-disabled.txt)" % n)
    keyed = {m.group(1) for l in status for m in [re.match(r"core\.plugins\.status\.(.+)\.[a-zA-Z]+ = ", l)] if m}
    n = write(bench, "upgrade-orphans.txt", sorted(keyed - names - {"core", "core_extensions"}))
    log("upgrade: %d status key name(s) no descriptor declares any more (artifacts/upgrade-orphans.txt)" % n)
    if missing is not None:
        n = write(bench, "components-without-version.txt", missing)
        log("upgrade: %d component(s) the v7 start recorded no version for (artifacts/components-without-version.txt)%s"
            % (n, ": " + ", ".join(missing) if missing else ""))


def lines(bench, name):
    """The lines of an artifact of the upgrade, empty when it was not written."""
    f = bench.e2e / "artifacts" / name
    return [l for l in f.read_text().splitlines() if l.strip()] if f.exists() else []


def clear(bench):
    """Remove the artifacts of a previous upgrade, so that none outlives the run that wrote it."""
    for name in OWN:
        (bench.e2e / "artifacts" / name).unlink(missing_ok=True)


def outcome(bench, how, failure=None):
    """artifacts/logs/upgrade.json, what the report says of the upgrade: its source, its result, what the takeover ran
    and what it lost, read back from the artifacts of this run. Under logs/, which every run empties: a later run of
    the plain bench never reports an upgrade it did not play."""
    ran = lines(bench, "liquibase-changesets.txt")
    data = {"mode": how, "status": "failed" if failure else "ok", "failure": failure,
            "changesets": len(ran), "by_type": {k: sum(1 for l in ran if l.startswith(k + " ")) for k in sorted({l.split(" ")[0] for l in ran})},
            "settings_lost": lines(bench, "datastore-lost.txt"), "settings_defaults": lines(bench, "datastore-defaults.txt"),
            "components_without_version": lines(bench, "components-without-version.txt"),
            "disabled": lines(bench, "upgrade-disabled.txt"), "orphans": lines(bench, "upgrade-orphans.txt"),
            "unmanaged": lines(bench, "v7-liquibase-unmanaged.txt"),
            "hand_applied": sorted(set(re.findall(r"sql/(?:\S+/)?upgrade/\S+\.sql", "\n".join(lines(bench, "liquibase-invisible.txt")))))}
    (bench.e2e / "artifacts/logs/upgrade.json").write_text(json.dumps(data, indent=1, ensure_ascii=False))


def mode():
    """How the previous version's database is made: before (E2E_BEFORE_WAR), dump (E2E_V7_DUMP) or v7."""
    if os.environ.get("E2E_BEFORE_WAR"):
        return "before"
    if os.environ.get("E2E_V7_DUMP"):
        return "dump"
    if os.environ.get("E2E_V7_REF") if os.environ.get("E2E_TARGET") != "site" else os.environ.get("E2E_V7_WAR"):
        return "v7"
    usage("upgrade: no previous version: set E2E_V7_REF (a plugin) or E2E_V7_WAR (a site), E2E_V7_DUMP, or E2E_BEFORE_WAR in e2e.conf")


def takeover_scripts():
    """The two scripts of the takeover (E2E_TAKEOVER), checked: required for a site, optional for a plugin; None for a
    plugin without them."""
    if os.environ.get("E2E_TARGET") != "site" and not os.environ.get("E2E_TAKEOVER"):
        return None
    d = pathlib.Path(os.environ.get("E2E_TAKEOVER", ""))
    scripts = [d / "takeover-1-core.sql", d / "takeover-2-components.sql"]
    if not os.environ.get("E2E_TAKEOVER") or not all(s.is_file() for s in scripts):
        usage("upgrade: E2E_TAKEOVER: the directory written by site_check.py takeover <v7 war> <v8 war> --out <dir> "
                         "(lutece-update-site, reference/database.md), holding takeover-1-core.sql and takeover-2-components.sql")
    return scripts


def takeover(bench, how, site, scripts):
    """The bench site takes the previous version's database over: in one normal start, or in the two passes of
    database.md when the takeover scripts are given; the invisible upgrade scripts of a v7 takeover applied by hand
    first."""
    if scripts:
        db_load(bench, scripts[0])
        log("upgrade: core pass (%s)" % scripts[0])
        since = app_start(bench, site)
        w = sh(BENCH / "server/watch-boot.sh", bench.app, since, "120")
        why = liquibase_failure(bench, app_logs(bench))
        if why or w.returncode:
            raise Failed("core pass: %s" % (("LIQUIBASE FAILED\n  " + why) if why else w.stdout.strip()))
        log("upgrade: core pass, %s core upgrade(s) ran" % db(bench, "SELECT COUNT(*) FROM DATABASECHANGELOG WHERE FILENAME LIKE 'sql/upgrade/%'")[0])
        stop(bench)
        db_load(bench, scripts[1])
        log("upgrade: components set back to what the v7 site had installed (%s)" % scripts[1])
    if how != "before":
        hand_apply(bench, site)
    v8_start(bench, site, "takeover")


def main():
    """Entry point."""
    bench = Bench()
    site = bench.state / "site"
    if not site.is_dir():
        raise SystemExit("upgrade: no bench site, lpe2e build first")
    how = mode()
    scripts = takeover_scripts()
    (bench.e2e / "artifacts/logs").mkdir(parents=True, exist_ok=True)
    clear(bench)
    os.environ["E2E_VERSION"] = "v8"
    t0 = time.time()
    ensure_infra()
    sh("docker", "rm", "-f", bench.app)
    fresh_db(bench)
    server_files(bench)
    runner_up(bench)
    neighbours_up(bench)
    missing, previous = None, None
    try:
        if how == "before":
            previous = before_site(bench)
            v8_start(bench, previous, "previous version on a fresh database")
            seed(bench)
            stop(bench)
        else:
            base = site7(bench) if how == "v7" else None
            if how == "dump":
                v7_dump(bench)
                if not db(bench, "SHOW TABLES LIKE 'DATABASECHANGELOG'"):
                    base = site7(bench)
            image = tomcat_image() if base else None
            s7 = bench_site7(bench, base) if base else None
            previous = s7
            if how == "v7":
                v7_install(bench, image, s7)
            if base:
                missing = v7_liquibase(bench, image, s7, base / "versions.properties")
            else:
                log("upgrade: the dump is already followed by plugin-liquibase (DATABASECHANGELOG): no v7 start")
        settings_before = db(bench, SETTINGS)
        write(bench, "datastore-v7.txt" if how != "before" else "datastore-before.txt", settings_before)
        changesets_before = db(bench, CHANGESETS) if db(bench, "SHOW TABLES LIKE 'DATABASECHANGELOG'") else []
        daemon_up(bench)
        try:
            takeover(bench, how, site, scripts)
        finally:
            if db(bench, "SHOW TABLES LIKE 'DATABASECHANGELOG'"):
                report(bench, site, settings_before, changesets_before, missing, previous)
    except Failed as e:
        log("UPGRADE FAILED: %s" % e)
        outcome(bench, how, str(e))
        sys.exit(UPGRADE_FAILED)
    outcome(bench, how)
    seed(bench)
    if os.environ.get("E2E_RESTART_AFTER_SEED"):
        cmd_restart(bench)
    neighbours_ready(bench)
    daemon_ready(bench)
    sh("docker", "exec", bench.runner, "python", "/bench/server/runnerd.py", "login")
    log("upgrade: the bench site runs on the taken-over database (%.0fs), http://localhost:%d/%s" % (time.time() - t0, bench.port(), bench.context))


if __name__ == "__main__":
    main()
