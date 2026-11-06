#!/usr/bin/env bash
# Checks that no finding stops verify-migration.sh: a core below the floor is PM14, a project that does not assemble
# leaves TM08 and TM09 NOT EVALUATED, and the report still runs every other check to its RESULT line. The floor verdict
# comes from a fresh target/.v8-floor cache and mvn is a stub that fails, so nothing reaches the network.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="$HERE/../../tools/verify-migration.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export V8_FLOOR_CORE=8.0.2 V8_SNAPSHOT_CORE="" V8_SNAPSHOT_CORE_BUILD="" V8_FLOOR_PARENT=8.0.2 V8_FLOOR_SITE_PARENT=8.0.4 M2_REPO="$T/m2"
fails=0

mkdir -p "$T/bin" "$T/p/target" "$T/p/webapp/WEB-INF/templates/admin/plugins/myplugin"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/mvn"; chmod +x "$T/bin/mvn"
cat > "$T/p/pom.xml" <<'POM'
<project>
    <modelVersion>4.0.0</modelVersion>
    <parent><artifactId>lutece-global-pom</artifactId><groupId>fr.paris.lutece.tools</groupId><version>8.0.2</version></parent>
    <groupId>fr.paris.lutece.plugins</groupId>
    <artifactId>plugin-myplugin</artifactId>
    <packaging>lutece-plugin</packaging>
    <version>1.0.0</version>
    <dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>[8.0.1]</version></dependency></dependencies>
</project>
POM
printf '<@pageContainer></@pageContainer>\n' > "$T/p/webapp/WEB-INF/templates/admin/plugins/myplugin/manage.html"
printf '1\t\t-|lutece-core 8.0.2 or later, the latest published; snapshot  |-\tV8FLOOR refused: lutece-core 8.0.1\n' > "$T/p/target/.v8-floor"
touch -d '2099-01-01' "$T/p/target/.v8-floor"

( cd "$T/p" && PATH="$T/bin:$PATH" bash "$V" . ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$T/out"

# Records a failure when the report lacks a line.
expect() {
    grep -qE "$1" "$T/out" || { echo "FAIL: no line matching '$1'"; fails=$((fails + 1)); }
}

expect 'FAIL \[PM14\] lutece-core below'
expect 'V8FLOOR refused: lutece-core 8.0.1'
expect 'FAIL \[TM08\] Template design rules NOT EVALUATED: the project does not assemble'
expect 'FAIL \[TM09\] Template parse NOT EVALUATED: the project does not assemble'
expect '(PASS|FAIL|WARN) \[PM06\]'
expect '(PASS|FAIL|WARN) \[TS09\]'
expect '^RESULT: MIGRATION INCOMPLETE'
grep -q "verify-migration stopped" "$T/out" && { echo "FAIL: the verification stopped"; fails=$((fails + 1)); }

printf '3\t\t-|lutece-core 8.0.2 or later, the latest published; snapshot  |-\tV8FLOOR stale: lutece-core 8.0.3-SNAPSHOT\n' > "$T/p/target/.v8-floor"
touch -d '2099-01-01' "$T/p/target/.v8-floor"
( cd "$T/p" && PATH="$T/bin:$PATH" bash "$V" . ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$T/out"
expect 'WARN \[PM14\] lutece-core snapshot older than the latest build deployed'
expect 'V8FLOOR stale: lutece-core 8.0.3-SNAPSHOT'

rm -f "$T/p/target/.v8-floor"
( cd "$T/p" && PATH="$T/bin:$PATH" bash "$V" . ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$T/out"
expect 'WARN \[PM14\] lutece-core pinned'
sed -i 's|<version>\[8.0.1\]</version>|<version>[8.0.1,)</version>|' "$T/p/pom.xml"; rm -f "$T/p/target/.v8-floor"
( cd "$T/p" && PATH="$T/bin:$PATH" bash "$V" . ) 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$T/out"
expect 'WARN \[PM14\] lutece-core level NOT EVALUATED'

[ "$fails" -eq 0 ] && { echo "PASS: a core below the floor and a project that does not assemble are findings, a stale snapshot a warning, the verification runs to its end"; exit 0; }
cat "$T/out" | head -40
exit 1
