#!/usr/bin/env bash
# Checks the server-log oracle of the e2e bench (lutece.server_errors) on a synthetic Liberty log: an error logged
# after the mark is reported with its cause, the core noise and the declared patterns are not, nor the error page
# Liberty writes on the thread of a static file the client left (even when the Broken pipe precedes the mark), while
# the same SRVE0199E on another thread or later stays reported; a rotated log is read from its start.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
TESTS="$HERE/../../skills/lutece-e2e/tests"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/artifacts/logs"
mkdir -p "$T/harness"
printf '# a refusal the negative scenarios provoke\nDeclared failure\n' > "$T/harness/server-errors-allow.txt"
LOG="$T/artifacts/logs/messages.log"
printf '[9/23/26, 15:00:00:000 UTC] 0000001 lutece.application   E Before the mark\njava.lang.IllegalStateException: old\n' > "$LOG"
printf '[9/23/26, 15:00:59:900 UTC] 0000009 com.ibm.ws.logging.internal.impl.IncidentImpl   I FFDC1015I: An FFDC Incident has been created: "java.io.IOException: Broken pipe com.ibm.ws.webcontainer.servlet.FileServletWrapper.handleRequest 298"\n' >> "$LOG"
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
    f.write('java.io.IOException: Broken pipe\n')
    f.write("[9/23/26, 15:01:02:000 UTC] 0000004 lutece.application   E Declared failure of the scenario\n")
    f.write("[9/23/26, 15:01:03:000 UTC] 0000005 lutece.application   I Action : createAppointmentForm\n")
    f.write("[9/23/26, 15:01:04:000 UTC] 0000006 lutece.application   E Scenario specific\n")
    page = ("java.lang.IllegalStateException: SRVE0199E: OutputStream already obtained\n"
            "\tat com.ibm._jsp._Error500._jspService(_Error500.java:161)\n"
            "\tat com.ibm.ws.webcontainer.webapp.WebApp.sendError(WebApp.java:4396)\n")
    f.write("[9/23/26, 15:01:00:300 UTC] 0000009 com.ibm.ws.webcontainer.util.ApplicationErrorUtils   E SRVE0777E: Exception thrown by application class 'SRTServletResponse.getWriter:861'\n" + page)
    f.write("[9/23/26, 15:01:05:000 UTC] 0000008 com.ibm.ws.logging.internal.impl.IncidentImpl   I FFDC1015I: An FFDC Incident has been created: \"java.io.IOException: Broken pipe com.ibm.ws.webcontainer.servlet.FileServletWrapper.handleRequest 298\"\n")
    f.write("[9/23/26, 15:01:05:200 UTC] 0000007 com.ibm.ws.webcontainer.util.ApplicationErrorUtils   E SRVE0777E: Other thread\n" + page)
    f.write("[9/23/26, 15:01:05:300 UTC] 0000008 com.ibm.ws.webcontainer.util.ApplicationErrorUtils   E SRVE0777E: Same thread\n" + page)
    f.write("[9/23/26, 15:01:09:000 UTC] 0000008 com.ibm.ws.webcontainer.util.ApplicationErrorUtils   E SRVE0777E: Too late\n" + page)
errors = lutece.server_errors(mark, ["Scenario specific"])
print(len(errors)); print(errors[0] if errors else ""); print(" ".join(e.split("SRVE0777E: ")[1].split(" |")[0] for e in errors[1:]))
open(sys.argv[2], "w").write("[9/23/26, 15:02:00:000 UTC] 0000007 lutece.application   E After rotation\n")
print(len(lutece.server_errors(mark)))
PY
)
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
check "three errors reported" '[ "$(echo "$out" | sed -n 1p)" = 3 ]'
check "header and cause" 'echo "$out" | sed -n 2p | grep -q "SRVE0777E.*OutputStream already obtained"'
check "error page of another thread or out of time reported" '[ "$(echo "$out" | sed -n 3p)" = "Other thread Too late" ]'
check "rotated log read from start" '[ "$(echo "$out" | sed -n 4p)" = 1 ]'
if [ $fail = 0 ]; then echo "PASS: server-log oracle reports new errors, skips core noise, static-file aborts and declared ones, survives rotation"; else echo "$out"; exit 1; fi
