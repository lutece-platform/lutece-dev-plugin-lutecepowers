#!/usr/bin/env bash
# Checks site_check.py on small sites and assembled wars built on the fly: the configuration model (file order inside a
# source, profiles resolved source by source, an empty value masking the key), every SI check on a case it must report
# and on one it must not, the decisions file, the per-environment conversion and the offline gate.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../tools/python.sh"
# The fixtures are written for these parent floors; pinned so a new lutece-global-pom or lutece-site-pom release does
# not move them.
export V8_FLOOR_PARENT=8.0.2 V8_FLOOR_SITE_PARENT=8.0.2
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
python3 - "$HERE/../../tools/site_check.py" "$T" <<'PY'
import os
import pathlib
import subprocess
import sys
import zipfile

TOOL, ROOT = sys.argv[1], pathlib.Path(sys.argv[2])
failures = []


def write(path, text):
    """Writes a file, creating its directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="latin-1")


def jar(path, entries):
    """Writes a jar holding the given name -> text entries."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as z:
        for n, t in entries.items():
            z.writestr(n, t)


def config_source_class(name, ordinal):
    """A minimal class file whose getOrdinal( ) returns the ordinal with sipush, as javac compiles a constant."""
    import struct
    utf = lambda t: b"\x01" + struct.pack(">H", len(t)) + t.encode()
    pool = [utf(name.replace(".", "/")), b"\x07\x00\x01", utf("java/lang/Object"), b"\x07\x00\x03",
            utf("getOrdinal"), utf("()I"), utf("Code")]
    code = b"\x11" + struct.pack(">h", ordinal) + b"\xac"
    attr = struct.pack(">HHI", 1, 1, len(code)) + code + struct.pack(">HH", 0, 0)
    method = struct.pack(">HHHH", 0x0001, 5, 6, 1) + struct.pack(">HI", 7, len(attr)) + attr
    return (b"\xca\xfe\xba\xbe" + struct.pack(">HHH", 0, 52, len(pool) + 1) + b"".join(pool) +
            struct.pack(">HHHHH", 0x0021, 2, 4, 0, 0) + struct.pack(">H", 1) + method + struct.pack(">H", 0))


def org_config_jar(path, properties):
    """A jar shipping a ConfigSource at ordinal 180 and its properties file, like an organisation's configuration library."""
    jar(path, {"META-INF/services/org.eclipse.microprofile.config.spi.ConfigSource": "org.example.OrgConfigSource\n",
               "org/example/OrgConfigSource.class": config_source_class("org.example.OrgConfigSource", 180),
               "org-config.properties": properties})


def war(name, core="8.0.2", extra=None):
    """An assembled site: a core jar, the seven root files, a plugin descriptor."""
    w = ROOT / name
    jar(w / f"WEB-INF/lib/lutece-core-{core}.jar", {"META-INF/maven/fr.paris.lutece/lutece-core/pom.properties":
        f"groupId=fr.paris.lutece\nartifactId=lutece-core\nversion={core}\n", "fr/paris/lutece/portal/Core.class": ""})
    write(w / "WEB-INF/conf/config.properties", "a.base=core\nmail.noreply.email=noreply@nowhere.org\n")
    write(w / "WEB-INF/plugins/forms.xml", "<plug-in><name>forms</name><version>4.0.0</version><db-pool-required>1</db-pool-required></plug-in>")
    for rel, text in (extra or {}).items():
        write(w / rel, text)
    return w


def run(*args):
    """Runs the tool; returns (exit code, output)."""
    r = subprocess.run([sys.executable, TOOL, *map(str, args)], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def expect(name, cond, output):
    """Records a failed expectation with the output that disproves it."""
    print(("PASS: " if cond else "FAIL: ") + name)
    if not cond:
        failures.append(name)
        print(output)


def site(name, pom_extra="", files=None):
    """A v8 site: parent, BOM import, a starter, and its webapp files; committed in a git repository."""
    s = ROOT / name
    write(s / "pom.xml", f"""<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
<parent>
<groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-site-pom</artifactId><version>8.0.2</version>
</parent>
<artifactId>{name}</artifactId><packaging>lutece-site</packaging><version>1.0.0</version>
<dependencyManagement><dependencies><dependency><groupId>fr.paris.lutece.starters</groupId><artifactId>lutece-bom</artifactId>
<version>8.0.0</version><type>pom</type><scope>import</scope></dependency></dependencies></dependencyManagement>
<dependencies><dependency><groupId>fr.paris.lutece.starters</groupId><artifactId>forms-starter</artifactId><version>8.0.0</version></dependency>
{pom_extra}</dependencies></project>""")
    for rel, text in (files or {}).items():
        write(s / rel, text)
    return s


write(ROOT / "bom.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0"><properties><lutece.plugin-forms.version>4.0.0</lutece.plugin-forms.version></properties>
<dependencyManagement><dependencies><dependency><groupId>fr.paris.lutece.plugins</groupId><artifactId>plugin-forms</artifactId>
<version>${lutece.plugin-forms.version}</version><type>lutece-plugin</type></dependency></dependencies></dependencyManagement></project>""")
BOM = ROOT / "bom.pom"

w = war("order", extra={"WEB-INF/conf/override/lutece.properties": "k=from-lutece\n",
                        "WEB-INF/conf/override/plugins/x.properties": "k=from-plugins\n",
                        "WEB-INF/conf/plugins/b.properties": "p=b\nq=plugin\n", "WEB-INF/conf/plugins/a.properties": "p=a\n",
                        "WEB-INF/conf/themes/t.properties": "q=theme\n",
                        "WEB-INF/conf/override/profiles.properties": "e=\n%dev.d=dev\n",
                        "WEB-INF/conf/plugins/z.properties": "e=default\nd=plain\n"})
rc, out = run("config", w)
expect("v8: inside a source the last file loaded wins: override/plugins after override/, themes after plugins, then alphabetical",
       "k=from-plugins" in out and "q=theme" in out and "p=b" in out, out)
expect("an empty value masks the key of a lower source", "e=<masked: empty value>" in out, out)
org_config_jar(w / "WEB-INF/lib/library-orgconfig-1.0.0.jar", "d=env\n%dev.k=env-dev\nmylutece.authentication.class=fr.paris.lutece.plugins.x.Missing\n")
rc, out = run("config", w, "--profile", "dev")
expect("profiles resolve source by source: %dev in the override source wins over the ConfigSource", "d=dev" in out, out)
expect("a plain key of a higher source wins over a %dev key of a lower one", "k=from-plugins" in out, out)
rc, out = run("config", war("v7", core="7.1.8", extra={"WEB-INF/conf/override/plugins/x.properties": "k=from-plugins\n",
                                                          "WEB-INF/conf/override/lutece.properties": "k=from-lutece\n"}))
expect("v7: override/plugins is loaded last and wins", "k=from-plugins" in out, out)

s = site("s1", files={"webapp/WEB-INF/conf/override/profiles-config.properties": "mylutece.authentication.class=fr.paris.lutece.plugins.x.Missing\nrec.a.base=1\n",
                      "webapp/WEB-INF/conf/override/plugins/workflow-notifygru_context.xml": "<beans><bean id='a' class='x.Y'/></beans>",
                      "webapp/WEB-INF/conf/db.properties": "portal.poolservice=fr.paris.lutece.util.pool.service.C3p0ConnectionService\nportal.password=secret\n",
                      "src/conf/prod/WEB-INF/conf/override/x.properties": "a=1\n",
                      "src/java/fr/paris/lutece/Foo.java": "class Foo {}",
                      "src/sql/site/init.sql": "insert into x values (1);\n",
                      "src/sql/plugins/s1/plugin/init_db_s1.sql": "insert into x values (1);\n",
                      "webapp/WEB-INF/templates/skin/site/page.html": "<#assign x = 'a'?new()>"})
w1 = war("w1", extra={"WEB-INF/conf/override/profiles-config.properties": "mylutece.authentication.class=fr.paris.lutece.plugins.x.Missing\nrec.a.base=1\nldap.initialContextProvider=com.sun.jndi.ldap.LdapCtxFactory\n"})
rc, out = run("check", s, "--war", w1, "--bom", BOM, "--m2", ROOT / "m2")
for code, what in (("FAIL [SI28]", "a class the war does not ship"), ("FAIL [SI20]", "a Spring context with a bean"),
                   ("FAIL [SI22]", "a C3p0 pool"), ("WARN [SI24]", "a password in db.properties"),
                   ("FAIL [SI09]", "a per-environment conf directory"), ("FAIL [SI10]", "Java in a site"),
                   ("FAIL [SI12] src/sql/site/init.sql", "an SQL path Liquibase never reads"),
                   ("FAIL [SI12] src/sql/plugins/s1/plugin/init_db_s1.sql", "an SQL file without the Liquibase header"),
                   ("FAIL [SI52]", "?new in a template"), ("WARN [SI29]", "a profile name without %"),
                   ("WARN [SI30]", "a secret in the overlay"), ("FAIL [SI44]", "a war without plugins.dat")):
    expect(f"check reports {what} ({code})", code in out, out)
expect("check exits 1 on a FAIL", rc == 1, out)
expect("SI28 leaves a class of the JDK", "LdapCtxFactory" not in out, out)

s2 = site("s2", files={"webapp/WEB-INF/conf/override/profiles-config.properties": "a.base=site\n",
                       "webapp/WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
w2 = war("w2", extra={"WEB-INF/conf/override/profiles-config.properties": "a.base=site\n",
                      "WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
rc, out = run("check", s2, "--war", w2, "--bom", BOM, "--m2", ROOT / "m2")
expect("a clean v8 site passes (exit 0, no FAIL, no WARN)", rc == 0 and "FAIL [" not in out and "WARN [" not in out, out)
w3 = war("w3", extra={"WEB-INF/plugins/plugins.dat": "old.installed=1\n"})
rc, out = run("check", s2, "--war", w3, "--bom", BOM, "--m2", ROOT / "m2")
expect("a descriptor without its plugins.dat line is reported (SI40)", "WARN [SI40] plugins.dat: forms" in out, out)
expect("a plugins.dat line without descriptor is reported (SI41)", "WARN [SI41] plugins.dat: old" in out, out)

subprocess.run(["git", "init", "-q", str(s2)], check=True)
subprocess.run(["git", "-C", str(s2), "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A"], check=True)
write(s2 / "webapp/WEB-INF/templates/skin/site/footer.html", "<footer>v7</footer>")
subprocess.run(["git", "-C", str(s2), "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A"], check=True)
subprocess.run(["git", "-C", str(s2), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "before"], check=True)
(s2 / "webapp/WEB-INF/templates/skin/site/footer.html").unlink()
before = war("before", extra={"WEB-INF/conf/override/profiles-config.properties": "a.base=site\nsms.server=@contact-everyone.fr\n%rec.url=x\n",
                              "WEB-INF/plugins/address.xml": "<plug-in><name>address</name><version>1.0</version></plug-in>",
                              "WEB-INF/plugins/plugins.dat": "forms.installed=1\n"})
org_config_jar(w2 / "WEB-INF/lib/library-orgconfig-1.0.0.jar", "mail.noreply.email=noreply@example.org\n")
rc, out = run("check", s2, "--war", w2, "--before", before, "--before-ref", "HEAD", "--bom", BOM, "--m2", ROOT / "m2")
expect("a key the site set before and no longer sets is reported (SI80)", "FAIL [SI80] sms.server" in out, out)
expect("a value an added ConfigSource changes is reported (SI80)", "FAIL [SI80] mail.noreply.email" in out and "library-orgconfig" in out, out)
expect("a plugin no longer shipped is reported (SI81)", "FAIL [SI81] plugin address" in out, out)
expect("a site file no longer shipped is reported (SI82)", "FAIL [SI82] webapp/WEB-INF/templates/skin/site/footer.html" in out, out)
expect("a profile the site no longer names is reported (SI84)", "FAIL [SI84] profile rec" in out, out)
dec = ROOT / "decisions.md"
write(dec, "- key sms.server: moved to the pack, same value, checked in the pack war\n"
           "- key mail.noreply.email: the organisation default replaces the core default on purpose\n"
           "- key url: rec is renamed dev, the environment sets MP_CONFIG_PROFILE=dev (asked to the ops team)\n"
           "- plugin address: no form of the site uses an address field (checked in the database)\n"
           "- file WEB-INF/templates/skin/site/footer.html: the v8 theme footer carries the same links\n"
           "- profile rec: renamed dev, MP_CONFIG_PROFILE=dev confirmed for the environment\n"
           "- key too.short: ok\n")
rc, out = run("check", s2, "--war", w2, "--before", before, "--before-ref", "HEAD", "--decisions", dec, "--bom", BOM, "--m2", ROOT / "m2")
expect("every difference answered by a decision passes (SI80)", "PASS [SI80]" in out and "FAIL [SI8" not in out, out)
secret_before = war("secret-before", extra={"WEB-INF/conf/override/x.properties": "elastic.server.pwd=S3cr3tValue\n"})
secret_after = war("secret-after")
rc, out = run("check", s2, "--war", secret_after, "--before", secret_before, "--bom", BOM, "--m2", ROOT / "m2")
expect("a secret is never printed, only reported (SI80)", "FAIL [SI80] elastic.server.pwd" in out and "S3cr3tValue" not in out, out)
rc, out = run("config", secret_before)
expect("config never prints a secret", "elastic.server.pwd=" in out and "S3cr3tValue" not in out, out)

env = site("env", files={"src/conf/rec/WEB-INF/conf/override/plugins/a.properties": "same=1\nurl=https://rec\nldap.password=s3cr3t\n",
                         "src/conf/prod/WEB-INF/conf/override/plugins/a.properties": "same=1\nurl=https://prod\nldap.password=pr0d\n",
                         "src/conf/prod/WEB-INF/conf/override/plugins/x_context.xml": "<beans/>",
                         "src/conf/prod/WEB-INF/conf/override/log.properties": "rootLogger.level=info\n"})
rc, out = run("envconf", env)
expect("envconf keeps a shared value as a plain key", "\nsame=1" in out, out)
expect("envconf writes a differing value as %<env>.key", "%prod.url=https://prod" in out and "%rec.url=https://rec" in out, out)
write(env / "webapp/WEB-INF/conf/override/profiles-config.properties", out.split("UNCONVERTED")[0])
rc2, again = run("envconf", env)
expect("envconf run again on its own output adds nothing (a profile key of the site is not an environment value)",
       again.count("%prod.url=https://prod") == 1, again)
expect("envconf never copies a secret", "s3cr3t" not in out and "pr0d" not in out and "SECRET not copied" in out, out)
expect("envconf lists what it cannot convert", "UNCONVERTED src/conf/prod/WEB-INF/conf/override/plugins/x_context.xml" in out, out)
expect("envconf leaves log.properties out: log4j configuration, not Lutece keys", "rootLogger" not in out.split("UNCONVERTED")[0] and "UNCONVERTED src/conf/prod/WEB-INF/conf/override/log.properties" in out, out)

gw = war("gate", core="7.1.8")
jar(gw / "WEB-INF/lib/plugin-forms-3.0.0.jar", {"META-INF/maven/fr.paris.lutece.plugins/plugin-forms/pom.properties":
    "groupId=fr.paris.lutece.plugins\nartifactId=plugin-forms\nversion=3.0.0\n"})
jar(gw / "WEB-INF/lib/plugin-old-1.0.0.jar", {"META-INF/maven/fr.paris.lutece.plugins/plugin-old/pom.properties":
    "groupId=fr.paris.lutece.plugins\nartifactId=plugin-old\nversion=1.0.0\n"})
java17 = b"\xca\xfe\xba\xbe\x00\x00\x00\x3d"
jar(gw / "WEB-INF/lib/plugin-next-2.0.0.jar", {"META-INF/maven/fr.paris.lutece.plugins/plugin-next/pom.properties":
    "groupId=fr.paris.lutece.plugins\nartifactId=plugin-next\nversion=2.0.0\n", "fr/paris/lutece/plugins/next/A.class": java17})
jar(gw / "WEB-INF/lib/thirdparty-1.0.0.jar", {"META-INF/maven/org.example/thirdparty/pom.properties":
    "groupId=org.example\nartifactId=thirdparty\nversion=1.0.0\n", "org/example/A.class": java17})
rc, out = run("gate", gw, "--bom", BOM, "--offline")
expect("gate: a BOM-managed artefact is fine, another one blocks (exit 1)", rc == 1 and "BOM        plugin-forms" in out and "NO-V8      plugin-old" in out, out)
expect("gate: a Lutece jar built for Java 17 in a v7 war is a drift", "DRIFT      plugin-next-2.0.0.jar" in out, out)
expect("gate: a third-party jar built for Java 17 is no drift", "thirdparty" not in out, out)
write(ROOT / "bom-snapshot.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0"><dependencyManagement><dependencies><dependency>
<groupId>fr.paris.lutece.plugins</groupId><artifactId>plugin-forms</artifactId><version>4.0.1-SNAPSHOT</version><type>lutece-plugin</type>
</dependency></dependencies></dependencyManagement></project>""")
rc, out = run("gate", gw, "--bom", ROOT / "bom-snapshot.pom", "--offline")
expect("gate: an artefact the BOM manages as a snapshot is counted as a snapshot",
       "SNAPSHOT   plugin-forms" in out and "managed by lutece-bom as a snapshot" in out and "1 with a Lutece 8 snapshot only" in out, out)

s3 = site("s3", files={"src/main/liberty/config/server.xml": '<server><variable name="a.base" value="x"/><library><fileset dir="lib" includes="mysql-connector-*.jar"/></library></server>',
                       "webapp/WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
w4 = war("w4", extra={"WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
jar(w4 / "WEB-INF/lib/mariadb-java-client-3.5.1.jar", {"org/mariadb/jdbc/Driver.class": ""})
rc, out = run("check", s3, "--war", w4, "--bom", BOM, "--m2", ROOT / "m2")
expect("a Liberty variable named like a key of the site is reported (SI31)", "WARN [SI31]" in out and "a.base" in out, out)
expect("a driver fileset matching no jar of the war is reported (SI25)", "FAIL [SI25]" in out and "mysql-connector" in out, out)
rc, out = run("plugins-dat", w4)
expect("plugins-dat writes the descriptor names and their pools", out.split() == ["core_extensions.installed=1", "forms.installed=1", "forms.pool=portal"], out)
dump, envf = ROOT / "dump.txt", ROOT / "env.txt"
write(dump, "a.base=core\nmail.noreply.email=from-env\n")
write(envf, "MAIL_NOREPLY_EMAIL=from-env\n")
rc, out = run("config", w4, "--against", dump, "--env", envf)
expect("the model with the container environment agrees with the dump (SI87)", rc == 0 and "0 disagreement" in out, out)
rc, out = run("config", w4, "--against", dump)
expect("without the environment the model disagrees with the dump (SI87)", rc == 1 and "WARN [SI87] mail.noreply.email" in out, out)
scan = subprocess.run(["bash", str(pathlib.Path(TOOL).with_name("scan-project.sh")), "."], cwd=ROOT / "env", capture_output=True, text=True)
expect("scan-project reads a site without src/java as type site", '"type": "site"' in scan.stdout, scan.stdout + scan.stderr)

s4 = site("s4", files={"webapp/WEB-INF/conf/override/plugins/filegenerator.properties": "temporaryfiles.max.size=2147483647\n",
                       "webapp/WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
w5 = war("w5", extra={"WEB-INF/conf/plugins/filegenerator.properties": "filegenerator.temporaryfiles.max.size=16777215\n",
                      "WEB-INF/conf/override/plugins/filegenerator.properties": "temporaryfiles.max.size=2147483647\n",
                      "WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\n"})
rc, out = run("check", s4, "--war", w5, "--bom", BOM, "--m2", ROOT / "m2")
expect("a renamed key whose site value differs from the new default fails (SI27)",
       "FAIL [SI27] temporaryfiles.max.size" in out and "filegenerator.temporaryfiles.max.size" in out, out)

sp = site("sp", files={"src/conf/prod/WEB-INF/conf/override/plugins/oauth2_context.xml":
    '<beans><bean id="oauth2.client" class="x.C"><property name="clientId" value="ID-1"/>'
    '<property name="clientSecret" value="t0pS3cret"/></bean>'
    '<bean id="app.dataClient" class="x.D"><property name="scope"><list><value>openid</value><value>profile</value></list></property></bean></beans>',
    "src/conf/rec/WEB-INF/override/plugins/oauth2_context.xml": '<beans><bean id="oauth2.client" class="x.C"><property name="clientId" value="REC"/></bean></beans>'})
wsp = war("wsp", extra={"WEB-INF/conf/plugins/oauth2.properties": "oauth2.client.clientId=\noauth2.client.clientSecret=\napp.dataclient.main.scopes=\n"})
rc, out = run("spring", sp, "--war", wsp)
expect("spring writes <bean id>.<property> under the profile of its environment", "%prod.oauth2.client.clientId=ID-1" in out, out)
expect("spring never copies a secret", "t0pS3cret" not in out and "SECRET not copied" in out, out)
expect("spring proposes renamed keys as candidates (scope -> scopes)", "candidates: app.dataclient.main.scopes" in out, out)
expect("spring does not convert a context v7 never read", "NOT CONVERTED src/conf/rec/WEB-INF/override/plugins/oauth2_context.xml" in out and "REC" not in out.split("NOT CONVERTED")[0], out)

rb = site("rb", files={"webapp/WEB-INF/templates/admin/x.html": "a\nSITE\nc\n", "webapp/WEB-INF/templates/admin/y.html": "SITE-Y\n"})
m2 = ROOT / "m2rb"
def plugin_zip(ver, files):
    """A plugin jar and its webapp zip in a local repository."""
    base = m2 / f"fr/paris/lutece/plugins/plugin-p/{ver}"
    jar(base / f"plugin-p-{ver}-webapp.zip", files)
    return base
plugin_zip("1.0", {"WEB-INF/templates/admin/x.html": "a\nb\nc\n", "WEB-INF/templates/admin/y.html": "old\n"})
plugin_zip("2.0", {"WEB-INF/templates/admin/x.html": "a0\na\nb\nc\n", "WEB-INF/templates/admin/y.html": "new\n"})
wb, wa = war("rb-before"), war("rb-after")
for w, ver in ((wb, "1.0"), (wa, "2.0")):
    jar(w / f"WEB-INF/lib/plugin-p-{ver}.jar", {"META-INF/maven/fr.paris.lutece.plugins/plugin-p/pom.properties":
        f"groupId=fr.paris.lutece.plugins\nartifactId=plugin-p\nversion={ver}\n"})
rc, out = run("rebase", rb, "--before", wb, "--before-m2", m2, "--war", wa, "--m2", m2, "--write")
expect("rebase replays a site change on the new upstream when it applies cleanly", "CLEAN      WEB-INF/templates/admin/x.html" in out
       and (rb / "webapp/WEB-INF/templates/admin/x.html").read_text() == "a0\na\nSITE\nc\n", out)
expect("rebase reports a conflict and writes it apart", "CONFLICT   WEB-INF/templates/admin/y.html" in out
       and (rb / "webapp/WEB-INF/templates/admin/y.html.conflict").exists() and rc == 1, out)

desc = lambda n, v: f"<plug-in><name>{n}</name><version>{v}</version></plug-in>"
rn = war("rename-dat", extra={"WEB-INF/plugins/newpdf.xml": desc("workflow-newpdf", "2.0.2"),
    "WEB-INF/plugins/plugins.dat": "forms.installed=1\nforms.pool=portal\nworkflow-oldpdf.installed=1\ncore_extensions.installed=1\n",
    "WEB-INF/classes/sql/plugins/workflow/modules/newpdf/plugin/create_db_workflow-oldpdf.sql": "CREATE TABLE t (id int);\n"})
rc, out = run("check", site("rename-dat-site"), "--war", rn)
expect("SI43 fails a plugins.dat line naming a renamed plugin by its former name",
       "FAIL [SI43] plugins.dat: workflow-oldpdf.installed=1 names the former name of workflow-newpdf" in out
       and "SI41] plugins.dat: workflow-oldpdf" not in out and "SI40] plugins.dat: workflow-newpdf" not in out, out)

tb = war("tk-before", core="7.1.5", extra={
    "WEB-INF/plugins/forms.xml": desc("forms", "3.1.3"), "WEB-INF/plugins/legacy.xml": desc("legacy", "2.3.4"),
    "WEB-INF/plugins/oldpdf.xml": desc("workflow-oldpdf", "1.1.0"),
    "WEB-INF/sql/plugins/workflow/modules/oldpdf/plugin/create_db_workflow-oldpdf.sql": "CREATE TABLE workflow_task_pdf_cf (id int);\n"})
ta = war("tk-after", extra={
    "WEB-INF/plugins/legacy.xml": desc("legacy", "2.3.5"), "WEB-INF/plugins/newpdf.xml": desc("workflow-newpdf", "2.0.2"),
    "WEB-INF/plugins/brandnew.xml": desc("brandnew", "1.0.0"),
    "WEB-INF/classes/sql/upgrade/update_db_lutece_core-7.9.9-8.0.0.sql": "DROP TABLE IF EXISTS core_theme;\nCREATE TABLE core_theme (code varchar(50));\n"
        "DROP TABLE IF EXISTS core_xsl_export;\nALTER TABLE core_portlet ADD COLUMN id_template int;\n"
        "DELETE FROM core_datastore WHERE entity_key LIKE 'portal.theme.site_property.%';\n"
        "DELETE FROM core_datastore WHERE entity_key = 'theme.fav';\nINSERT INTO core_datastore VALUES ('theme.fav', '0');\n",
    "WEB-INF/classes/sql/themes/mytheme/init_db_theme_mytheme.sql": "INSERT INTO core_theme VALUES ('mytheme');\n"
        "INSERT INTO core_datastore VALUES ('portal.theme.site_property.Url.x', 'y');\nINSERT INTO core_datastore VALUES ('theme.fav', '0');\n",
    "WEB-INF/classes/sql/plugins/forms/upgrade/update_db_forms-3.1.3-4.0.0.sql": "UPDATE forms_form SET a = 1 WHERE b IN (SELECT id_portlet FROM core_portlet);\n",
    "WEB-INF/classes/sql/plugins/legacy/upgrade/update_db_legacy-2.3.4-2.3.5.sql": "INSERT INTO core_xsl_export VALUES (1);\n",
    "WEB-INF/classes/sql/plugins/workflow/modules/newpdf/plugin/create_db_workflow-newpdf.sql": "DROP TABLE IF EXISTS workflow_task_pdf_cf;\nCREATE TABLE workflow_task_pdf_cf (id int);\n",
    "WEB-INF/sql/plugins/workflow/modules/newpdf/plugin/prerun_db_workflow-newpdf.sql": "-- liquibase formatted sql\n"})
rc, out = run("takeover", tb, ta, "--out", ROOT / "tk")
core_sql = (ROOT / "tk/takeover-1-core.sql").read_text()
comp_sql = (ROOT / "tk/takeover-2-components.sql").read_text()
expect("SI13 leaves a theme script needing a table the core upgrade creates: the core scripts run first",
       "uses core_theme" not in out and "datastore key(s)" not in out, out)
expect("SI13 fails a component upgrade using a table the core upgrade drops",
       "FAIL [SI13] sql/plugins/legacy/upgrade/update_db_legacy-2.3.4-2.3.5.sql: uses core_xsl_export" in out and rc == 1, out)
expect("SI13 does not flag a script naming an altered table without the added column", "update_db_forms-3.1.3-4.0.0" not in out, out)
expect("SI13 names a key a component inserts without a delete while the core upgrade inserts it, the plan deletes it first",
       "WARN [SI13] sql/themes/mytheme/init_db_theme_mytheme.sql: inserts theme.fav without deleting it first" in out
       and "DELETE FROM core_datastore WHERE entity_key = 'theme.fav';" in comp_sql, out + comp_sql)
expect("SI14 names a renamed component whose create script re-creates the former tables",
       "WARN [SI14] workflow-newpdf: renamed from workflow-oldpdf" in out, out)
expect("the core pass sets the core to its v7 version and every component above any script",
       "'core.plugins.status.core.version', '7.1.5'" in core_sql and "'core.plugins.status.forms.version', '2147483647'" in core_sql
       and "'core.theme.status.mytheme.version', '2147483647'" in core_sql, core_sql)
expect("the components pass restores v7 versions, removes new ones and moves a renamed component",
       "'core.plugins.status.forms.version', '3.1.3'" in comp_sql and "'core.plugins.status.legacy.version', '2.3.4'" in comp_sql
       and "DELETE FROM core_datastore WHERE entity_key = 'core.plugins.status.brandnew.version';" in comp_sql
       and "REPLACE(entity_key, 'core.plugins.status.workflow-oldpdf.', 'core.plugins.status.workflow-newpdf.')" in comp_sql
       and "'core.plugins.status.workflow-newpdf.version', '1.1.0'" in comp_sql
       and "DELETE FROM core_datastore WHERE entity_key = 'core.theme.status.mytheme.version';" in comp_sql, comp_sql)


def compiled_jar(path, sources):
    """A jar of the classes javac compiles from the given name -> source entries, against stubs of the CDI annotations."""
    src, out = ROOT / ("src-" + path.stem), ROOT / ("cls-" + path.stem)
    stubs = {"jakarta/inject/Named.java": "package jakarta.inject; import java.lang.annotation.*; "
             "@Retention(RetentionPolicy.RUNTIME) public @interface Named { String value() default \"\"; }",
             "jakarta/enterprise/context/RequestScoped.java": "package jakarta.enterprise.context; import java.lang.annotation.*; "
             "@Retention(RetentionPolicy.RUNTIME) public @interface RequestScoped { }",
             "jakarta/enterprise/inject/Alternative.java": "package jakarta.enterprise.inject; import java.lang.annotation.*; "
             "@Retention(RetentionPolicy.RUNTIME) public @interface Alternative { }"}
    for rel, text in {**stubs, **sources}.items():
        write(src / rel, text)
    subprocess.run(["javac", "-d", str(out), *map(str, src.rglob("*.java"))], check=True)
    jar(path, {str(f.relative_to(out)): f.read_bytes() for f in out.rglob("*.class") if "jakarta" not in f.parts})


bean = lambda pkg, ann: {f"{pkg.replace('.', '/')}/CommentJspBean.java": f"package {pkg}; {ann} public class CommentJspBean {{ }}"}
cdi = war("cdi")
compiled_jar(cdi / "WEB-INF/lib/plugin-a-1.0.0.jar", bean("org.wf", "@jakarta.enterprise.context.RequestScoped @jakarta.inject.Named"))
compiled_jar(cdi / "WEB-INF/lib/module-b-1.0.0.jar", bean("org.ext", "@jakarta.enterprise.context.RequestScoped @jakarta.inject.Named"))
compiled_jar(cdi / "WEB-INF/lib/plugin-alt-1.0.0.jar", bean("org.alt", "@jakarta.enterprise.context.RequestScoped @jakarta.enterprise.inject.Alternative @jakarta.inject.Named( \"x\" )")
             | {"org/plain/X.java": "package org.plain; @jakarta.enterprise.context.RequestScoped @jakarta.inject.Named( \"x\" ) public class X { }"})
rc, out = run("check", site("cdi-site"), "--war", cdi)
expect("SI88 fails two plain beans named alike by default in two plugins (WELD-001414)",
       "FAIL [SI88] CDI bean name commentJspBean carried by org.ext.CommentJspBean" in out and "org.wf.CommentJspBean" in out, out)
expect("SI88 leaves an alternative sharing the name of a plain bean", "bean name x " not in out, out)

pm = ROOT / "m2-parents"
write(pm / "fr/paris/lutece/tools/lutece-site-pom/8.0.2/lutece-site-pom-8.0.2.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0">
<parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-global-pom</artifactId><version>8.0.2</version></parent></project>""")
write(pm / "fr/paris/lutece/tools/lutece-global-pom/8.0.2/lutece-global-pom-8.0.2.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0">
<dependencyManagement><dependencies><dependency><groupId>org.apache.logging.log4j</groupId><artifactId>log4j-core</artifactId>
<version>2.25.0</version></dependency></dependencies></dependencyManagement></project>""")
profiled = site("profiled", pom_extra="""</dependencies><profiles><profile><id>local</id><dependencies>
<dependency><groupId>org.example</groupId><artifactId>local-only</artifactId><scope>provided</scope></dependency>
<dependency><groupId>org.apache.logging.log4j</groupId><artifactId>log4j-core</artifactId><scope>provided</scope></dependency>
</dependencies></profile></profiles><dependencies>""")
rc, out = run("check", profiled, "--bom", BOM, "--m2", pm)
expect("SI06 fails a profile dependency without a version nobody manages, whatever its scope",
       "FAIL [SI06] pom.xml (profile local): local-only has no version" in out, out)
expect("SI06 leaves a neutralised dependency the parent poms manage", "log4j-core" not in out, out)
write(pm / "fr/paris/lutece/tools/lutece-global-pom/8.0.2/lutece-global-pom-8.0.2.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0">
<properties><log4j-bom.version>2.26.1</log4j-bom.version></properties>
<dependencyManagement><dependencies><dependency><groupId>org.apache.logging.log4j</groupId><artifactId>log4j-bom</artifactId>
<version>${log4j-bom.version}</version><type>pom</type><scope>import</scope></dependency></dependencies></dependencyManagement></project>""")
write(pm / "org/apache/logging/log4j/log4j-bom/2.26.1/log4j-bom-2.26.1.pom", """<project xmlns="http://maven.apache.org/POM/4.0.0">
<dependencyManagement><dependencies><dependency><groupId>org.apache.logging.log4j</groupId><artifactId>log4j-core</artifactId>
<version>2.26.1</version></dependency></dependencies></dependencyManagement></project>""")
rc, out = run("check", profiled, "--bom", BOM, "--m2", pm)
expect("SI06 leaves a dependency a BOM imported by the parent poms manages", "log4j-core" not in out, out)
rc, out = run("check", profiled, "--bom", BOM, "--m2", ROOT / "no-m2")
expect("SI06 only warns on a provided dependency when the parent poms cannot be read",
       "WARN [SI06] pom.xml (profile local): local-only" in out and "FAIL [SI06]" not in out, out)

ds = war("fresh-ds", extra={"WEB-INF/classes/sql/init_db_lutece_core.sql": "INSERT INTO core_datastore VALUES ('portal.a', '1');\nINSERT INTO core_datastore VALUES ('portal.b', '1');\nINSERT INTO core_datastore VALUES ('portal.c', '1');\n",
    "WEB-INF/classes/sql/themes/t/init_db_theme_t.sql": "INSERT INTO core_datastore VALUES ('portal.a', '2');\n"
        "DELETE FROM core_datastore WHERE entity_key='portal.b';\nINSERT INTO core_datastore VALUES ('portal.b', '2');\n"
        "INSERT INTO core_datastore VALUES ('portal.c', '2') ON DUPLICATE KEY UPDATE entity_value='2';\n"
        "INSERT INTO core_datastore VALUES ('theme.t.own', '2');\n"})
rc, out = run("check", site("fresh-ds-site"), "--war", ds)
expect("SI89 fails a theme install inserting a datastore key the core install inserts, without DELETE",
       "FAIL [SI89] WEB-INF/classes/sql/themes/t/init_db_theme_t.sql: inserts portal.a that" in out, out)
expect("SI89 leaves a key deleted first, an upsert and a key of the theme's own", "portal.b" not in out and "portal.c" not in out and "theme.t.own" not in out, out)

sys.exit(1 if failures else 0)
PY
