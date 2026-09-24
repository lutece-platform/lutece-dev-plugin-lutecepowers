#!/usr/bin/env bash
# Checks the v7 leg of a comparison: causes.py reads the Tomcat log and its root cause, compare.py does not count as
# fixed a scenario whose v7 page failed on a request parameter it did not get.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS="$HERE/../../skills/lutece-e2e/tools"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tools" "$T/artifacts/logs7" "$T/artifacts/results" "$T/artifacts/v7/results" "$T/artifacts/v8/results"
cp "$TOOLS/causes.py" "$TOOLS/compare.py" "$T/tools/"
NOW=$(date -u +%s)
STAMP=$(date -u -d "@$NOW" '+%Y-%m-%d %H:%M:%S')
cat > "$T/artifacts/logs7/catalina.out" <<LOG
 $STAMP ERROR [http-nio-8080-exec-1] lutece.error - Critical AppException, root cause: _MiscTemplateException: When calling macro "tabs", required parameter "context" (parameter #3) was specified, but had null/missing value.
 fr.paris.lutece.portal.service.util.AppException: MVC Error dispaching view and action
LOG
row() { printf '{"id":"test_scenario[x.%s]","suite":"scenarios","scenario":"%s","status":"%s","t_start":%s,"t_end":%s,"failed_step":3,"failed_step_kind":"expect_ok"}\n' "$1" "$1" "$2" "$3" "$4"; }
row param failed $((NOW - 1)) $((NOW + 1)) > "$T/artifacts/results/scenarios.jsonl"
row real failed $((NOW + 100)) $((NOW + 101)) >> "$T/artifacts/results/scenarios.jsonl"
fail=0
(cd "$T" && E2E_VERSION=v7 python3 tools/causes.py > /dev/null)
if ! grep -q 'root cause\|required parameter \\"context\\"' "$T/artifacts/causes.json" && ! grep -q 'required parameter' "$T/artifacts/causes.json"; then
    echo "FAIL: causes.py did not read the v7 root cause from catalina.out"; cat "$T/artifacts/causes.json"; fail=1
fi
cp "$T/artifacts/results/scenarios.jsonl" "$T/artifacts/v7/results/" && cp "$T/artifacts/causes.json" "$T/artifacts/v7/causes.json"
sed 's/"failed"/"passed"/' "$T/artifacts/results/scenarios.jsonl" > "$T/artifacts/v8/results/scenarios.jsonl"
(cd "$T" && python3 tools/compare.py > /dev/null)
grep -q "^| v7 bloqué | param " "$T/artifacts/compare.md" || { echo "FAIL: a missing-parameter v7 failure counted as fixed"; grep "^| [a-z]" "$T/artifacts/compare.md"; fail=1; }
grep -q "^| corrigé | real " "$T/artifacts/compare.md" || { echo "FAIL: a v7 failure without cause no longer counted as fixed"; grep "^| [a-z]" "$T/artifacts/compare.md"; fail=1; }
[ "$fail" -eq 0 ] && echo "PASS: v7 causes from catalina.out, missing-parameter failures not counted as fixed"
exit $fail
