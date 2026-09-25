#!/usr/bin/env bash
# Checks that SQ05 fails a value glued into a SQL literal and lets a constant of the class glued the same way through.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Prints the SQ05 status of a fixture whose DAO holds the given statement.
sq05() {
    local d="$T/$1"
    mkdir -p "$d/src/java/x"
    printf 'public class MyDAO\n{\n    %s\n}\n' "$2" > "$d/src/java/x/MyDAO.java"
    ( cd "$d" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' | grep -oE "(PASS|FAIL) \[SQ05\]" | cut -d' ' -f1
}

fails=0
[ "$(sq05 value "String q = \"SELECT id FROM my_table WHERE name = '\" + strName + \"'\";")" = "FAIL" ] || { echo "FAIL: a value glued into a SQL literal is not reported"; fails=1; }
[ "$(sq05 constant "String q = \"DELETE FROM my_table WHERE d <= now() - interval '\" + PARAM_TTL + \" minutes'\";")" = "PASS" ] || { echo "FAIL: a class constant glued into a SQL literal is reported"; fails=1; }
[ "$fails" -eq 0 ] && { echo "PASS: SQ05 reports a value glued into a SQL literal, not a class constant"; exit 0; }
exit 1
