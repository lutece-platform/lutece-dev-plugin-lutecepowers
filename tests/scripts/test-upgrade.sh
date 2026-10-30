#!/usr/bin/env bash
# Checks lpe2e upgrade without a server: the previous version it starts from (E2E_BEFORE_WAR, then E2E_V7_DUMP, then a
# v7 site: E2E_V7_REF for a plugin, E2E_V7_WAR for a site, else a usage error), the copy of a previous site the hard
# links cannot reach, the takeover scripts (required for a site, optional for a plugin, both files checked), the
# cleanup of a previous upgrade's artifacts, the Lutece logs of an earlier start emptied before each start (the core
# pass reads them), and the summary of a failed upgrade, which replaces any older verdict.
set -u
. "$(dirname "$0")/../../tools/python.sh"
E="$(cd "$(dirname "$0")" && pwd)/../../skills/lutece-e2e"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then :; else echo "FAIL: $1 (expected '$3', got '$2')"; fail=1; fi; }
py() { env -i PATH="$PATH" HOME="$T" LUTECEPOWERS_E2E_HOME="$T/home" "$@" python3 -c "
import sys; sys.path.insert(0, '$E/server'); import upgrade
try:
    print($PY)
except SystemExit as e:
    print('exit', e.code)
" 2>/dev/null; }
PY='upgrade.mode()'
check "a plugin with E2E_V7_REF starts from a v7 site" "$(py E2E_TARGET=plugin E2E_V7_REF=origin/develop_core7)" v7
check "a site starts from its v7 war" "$(py E2E_TARGET=site E2E_V7_WAR=/x)" v7
check "a site ignores E2E_V7_REF" "$(py E2E_TARGET=site E2E_V7_REF=HEAD)" "exit 2"
check "a dump wins over the v7 site" "$(py E2E_TARGET=plugin E2E_V7_REF=HEAD E2E_V7_DUMP=/d.sql)" dump
check "the previous v8 war wins over everything" "$(py E2E_TARGET=plugin E2E_V7_REF=HEAD E2E_V7_DUMP=/d.sql E2E_BEFORE_WAR=/b.war)" before
check "no previous version is a usage error" "$(py E2E_TARGET=plugin)" "exit 2"
mkdir -p "$T/src/WEB-INF/lib" && touch "$T/src/index.html" "$T/src/WEB-INF/lib/a.jar"
PY='(lambda u: (setattr(u, "sh", lambda *a, **k: (__import__("os").makedirs(str(a[-1]) + "/WEB-INF", exist_ok=True), type("R", (), {"returncode": 1})())[1]), sorted(str(p.relative_to(s)) for s in [u.before_site(type("B", (), {"state": __import__("pathlib").Path("'$T'/st"), "e2e": __import__("pathlib").Path("'$T'/e2e")})())] for p in s.rglob("*") if p.is_file() and "override" not in str(p)))[1])(upgrade)'
check "a previous site the hard links cannot reach is copied whole" "$(py E2E_TARGET=plugin E2E_BEFORE_WAR=$T/src)" "['WEB-INF/conf/db.properties', 'WEB-INF/lib/a.jar', 'index.html']"
mkdir -p "$T/tk" "$T/half"; touch "$T/tk/takeover-1-core.sql" "$T/tk/takeover-2-components.sql" "$T/half/takeover-1-core.sql"
PY='[p.name for p in upgrade.takeover_scripts() or []]'
check "a plugin without E2E_TAKEOVER takes over in one start" "$(py E2E_TARGET=plugin)" "[]"
check "a plugin with E2E_TAKEOVER plays both scripts" "$(py E2E_TARGET=plugin E2E_TAKEOVER=$T/tk)" "['takeover-1-core.sql', 'takeover-2-components.sql']"
check "a site without E2E_TAKEOVER is refused" "$(py E2E_TARGET=site)" "exit 2"
check "a takeover directory missing a script is refused" "$(py E2E_TARGET=site E2E_TAKEOVER=$T/half)" "exit 2"
mkdir -p "$T/e2e/artifacts/logs"
touch "$T/e2e/artifacts/liquibase-failure.txt" "$T/e2e/artifacts/datastore-lost.txt" "$T/e2e/artifacts/summary-prev.md"
PY='upgrade.clear(type("B", (), {"e2e": __import__("pathlib").Path("'$T'/e2e")})()) or sorted(p.name for p in __import__("pathlib").Path("'$T'/e2e/artifacts").glob("*.*"))'
check "a previous upgrade's artifacts are removed, nothing else" "$(py)" "['summary-prev.md']"
printf '{"mode": "v7", "status": "failed", "failure": "takeover: LIQUIBASE FAILED changeset x", "changesets": 3, "by_type": {"EXECUTED": 3}, "settings_lost": ["a = 1"], "components_without_version": ["x"]}' > "$T/e2e/artifacts/logs/upgrade.json"
E2E_DIR="$T/e2e" python3 "$E/tools/report.py" upgrade-failed > /dev/null 2>&1
S="$T/e2e/artifacts/summary.md"
check "the summary of a failed upgrade names the failure" "$(grep -c 'MISE À JOUR DE LA BASE ÉCHOUÉE.*LIQUIBASE FAILED changeset x' "$S")" 1
check "it counts the changesets and names the components without version" "$(grep -cE 'Changesets joués : 3|— `x`' "$S")" 2
check "it shows no suite table" "$(grep -c '| Suite |' "$S")" 0
rm "$T/e2e/artifacts/logs/upgrade.json"
E2E_DIR="$T/e2e" python3 "$E/tools/report.py" upgrade-failed > /dev/null 2>&1
check "an upgrade that died before its report still replaces the summary" "$(grep -c 'avant tout rapport' "$S")" 1
L="$T/home/benches/b/output/defaultServer/logs/lutece"; mkdir -p "$L" "$T/e2e/harness"
printf 'Caused by: java.lang.IllegalStateException: an earlier start\n' > "$L/error.log"; echo old > "$L/liquibase.log"; echo kept > "$L/application-1.log.gz"
PY='(lambda s: (setattr(s, "sh", lambda *a, **k: type("R", (), {"returncode": 0, "stdout": "", "stderr": ""})()), s.app_start(s.Bench(), "'$T'/site"), sorted(p.name for p in __import__("pathlib").Path("'$L'").iterdir()))[2])(__import__("server"))'
check "a start leaves no Lutece log of an earlier start to judge it on" "$(py E2E_DIR="$T/e2e" E2E_NAME=b)" "['application-1.log.gz']"
mkdir -p "$T/ds/WEB-INF/plugins"; echo "<plug-in><name>My Plugin Name</name></plug-in>" > "$T/ds/WEB-INF/plugins/p.xml"
PY='sorted(upgrade.descriptors(__import__("pathlib").Path("'$T'/ds")))'
check "a plugin name holding spaces is read whole" "$(py)" "['My Plugin Name']"
if [ $fail = 0 ]; then echo "PASS: lpe2e upgrade picks its previous version, checks its takeover scripts and reports a failure"; else exit 1; fi
