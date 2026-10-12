#!/usr/bin/env bash
# Checks how the e2e bench folds the classes lpe2e watch keeps in the bench site (server/server.py): only the classes
# of the project's sources (and inner classes) count, not the site's own; packaging puts the jar and the webapp zip (its
# bundles under WEB-INF/classes) and replaces them; lpe2e up
# packages the jar again before starting when watch left some, and stops when that packaging fails.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SERVER="$HERE/../../skills/lutece-e2e/server"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
C=state/site/WEB-INF/classes
mkdir -p "$T/src/src/java/a/web" "$T/$C/a/web" "$T/$C/site" "$T/state/site/WEB-INF/lib"
printf '<project><parent><artifactId>p</artifactId></parent><artifactId>plugin-a</artifactId></project>\n' > "$T/src/pom.xml"
touch "$T/src/src/java/a/web/AApp.java" "$T/$C/a/web/AApp.class" "$T/$C/a/web/AApp\$1.class" "$T/$C/site/SiteOwn.class"
mkdir -p "$T/zip/WEB-INF/classes/a/resources" && echo "k=v2" > "$T/zip/WEB-INF/classes/a/resources/a_messages.properties"
(cd "$T/zip" && python3 -c "import shutil; shutil.make_archive('../plugin-a-1.0-webapp', 'zip', '.')")
printf '#!/bin/sh\nmkdir -p "%s/src/target" && touch "%s/src/target/plugin-a-1.0.jar" "%s/src/target/plugin-a-1.0-sources.jar" && cp "%s/plugin-a-1.0-webapp.zip" "%s/src/target/"\n' "$T" "$T" "$T" "$T" "$T" > "$T/mvn-ok"
printf '#!/bin/sh\nexit 1\n' > "$T/mvn-ko"
chmod +x "$T"/mvn-*
run() {
  (cd "$SERVER" && MVN="$T/$1" python3 - "$T" "$1" <<'PY'
import pathlib, sys
import server
t = pathlib.Path(sys.argv[1])
class B:
    state = t / "state"
    src = t / "src"
bench = B()
names = lambda: sorted(str(f.relative_to(bench.state / "site/WEB-INF/classes")) for f in server.hot_classes(bench))
if sys.argv[2] == "mvn-ok":
    before = names()
    ok = server.package_jar(bench)
    print(before, ok, names(), sorted(p.name for p in (bench.state / "site/WEB-INF/lib").iterdir()),
          (bench.state / "site/WEB-INF/classes/site/SiteOwn.class").exists(),
          (bench.state / "site/WEB-INF/classes/a/resources/a_messages.properties").read_text().strip())
else:
    server.ensure_infra = lambda: print("started")
    try:
        server.cmd_up(bench)
    except SystemExit as e:
        print("stopped" if "mvn package failed" in str(e) else "other: %s" % e)
PY
  )
}
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected $3, got $2)"; fail=1; fi; }
check "hot classes: the project's and its inner ones, not the site's own; packaging puts the jar and the bundles, removes them" \
  "$(run mvn-ok)" "['a/web/AApp\$1.class', 'a/web/AApp.class'] True [] ['plugin-a-1.0.jar'] True k=v2"
touch "$T/$C/a/web/AApp.class"
check "up with classes left by watch packages the jar first, and stops when that fails" "$(run mvn-ko | tail -1)" "stopped"
exit $fail
