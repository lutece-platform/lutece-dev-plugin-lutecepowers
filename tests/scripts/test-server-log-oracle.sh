#!/usr/bin/env bash
# Checks the server-log oracle of the e2e bench (lutece.server_errors) on a synthetic Liberty log: an error logged
# after the mark is reported with its cause, the core noise and the declared patterns are not, a rotated log is read
# from its start.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TESTS="$HERE/../../skills/lutece-e2e/tests"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/artifacts/logs"
mkdir -p "$T/harness"
printf '# a refusal the negative scenarios provoke\nDeclared failure\n' > "$T/harness/server-errors-allow.txt"
LOG="$T/artifacts/logs/messages.log"
printf '[9/23/26, 15:00:00:000 UTC] 0000001 lutece.application   E Before the mark\njava.lang.IllegalStateException: old\n' > "$LOG"
out=$(E2E_DIR="$T" python3 - "$TESTS" "$LOG" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import lutece
from pathlib import Path
lutece.SERVER_LOG = Path(sys.argv[2])
lutece.E2E = Path(os.environ["E2E_DIR"])
mark = lutece.server_log_mark()
with open(sys.argv[2], "a") as f:
    f.write("[9/23/26, 15:01:00:000 UTC] 0000002 com.ibm.ws.webcontainer.util.ApplicationErrorUtils   E SRVE0777E: Exception thrown by application class\n")
    f.write("java.lang.IllegalStateException: SRVE0199E: OutputStream already obtained\n\tat x.y(Z.java:1)\n")
    f.write("[9/23/26, 15:01:01:000 UTC] 0000003 lutece.application   E Error execution 'service' method\n")
    f.write('java.lang.NullPointerException: Cannot invoke "javax.cache.Cache.get(Object)" because "this._cache" is null\n')
    f.write("[9/23/26, 15:01:02:000 UTC] 0000004 lutece.application   E Declared failure of the scenario\n")
    f.write("[9/23/26, 15:01:03:000 UTC] 0000005 lutece.application   I Action : createAppointmentForm\n")
    f.write("[9/23/26, 15:01:04:000 UTC] 0000006 lutece.application   E Scenario specific\n")
errors = lutece.server_errors(mark, ["Scenario specific"])
print(len(errors)); print(errors[0] if errors else "")
open(sys.argv[2], "w").write("[9/23/26, 15:02:00:000 UTC] 0000007 lutece.application   E After rotation\n")
print(len(lutece.server_errors(mark)))
PY
)
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
check "one error reported" '[ "$(echo "$out" | sed -n 1p)" = 1 ]'
check "header and cause" 'echo "$out" | sed -n 2p | grep -q "SRVE0777E.*OutputStream already obtained"'
check "rotated log read from start" '[ "$(echo "$out" | sed -n 3p)" = 1 ]'
if [ $fail = 0 ]; then echo "PASS: server-log oracle reports new errors, skips core noise and declared ones, survives rotation"; else echo "$out"; exit 1; fi
