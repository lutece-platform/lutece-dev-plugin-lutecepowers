#!/usr/bin/env bash
# Checks that checkup.sh reports a broken template as blocking (exit 1) and names the parse error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/webapp/WEB-INF/templates/admin/plugins/x"
echo "<@pageContainer><#if></@pageContainer>" > "$T/webapp/WEB-INF/templates/admin/plugins/x/a.html"
OUT=$(bash "$HERE/../../skills/lutece-checkup/scripts/checkup.sh" "$T" 2>&1); RC=$?
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q "errors=1" && echo "$OUT" | grep -q "PARSE_ERROR"; then
    echo "PASS: checkup reports a broken template as blocking"; exit 0
fi
echo "FAIL: expected rc=1 and a parse error; got rc=$RC"; echo "$OUT"; exit 1
