#!/usr/bin/env bash
# Checks that a full run (run.sh all, through lpe2e) never leaves its bench up without KEEP=1: a run whose coverage gate
# fails reaches its end, keeps rc 9 and takes the bench down, and so does a run that dies on a failed step; lpe2e upgrade
# leaves the bench as it found it, up when it ran before, down otherwise. run.sh runs from a copy of the bench whose
# shared server, docker, curl and python tools are stubs.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL="$HERE/../../skills/lutece-e2e"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
B="$T/bench"; P="$T/plugin-demo"; E="$P/e2e"
mkdir -p "$B/tools" "$B/server" "$T/bin" "$P/src" "$E/scenarios" "$E/artifacts"
cp "$SKILL/run.sh" "$B/"; cp "$SKILL/tools/lock.sh" "$SKILL/tools/src-digest.sh" "$SKILL/tools/dep-digest.py" "$B/tools/"; cp "$HERE/../../tools/python.sh" "$B/tools/"
printf '<project><artifactId>plugin-demo</artifactId></project>\n' > "$P/pom.xml"
printf 'E2E_TARGET=plugin\nE2E_SRC=..\nE2E_NAME=demo-e2e\n' > "$E/e2e.conf"
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/tools/check-v8-floor.sh"
cat > "$B/server/server.py" <<'PY'
import os, sys
open(os.environ["SERVER_LOG"], "a").write(sys.argv[1] + "\n")
if sys.argv[1] == "port":
    print(18999)
PY
printf 'import sys\nsys.exit(0)\n' > "$B/server/upgrade.py"
for f in inventory coverage causes report review source-key; do cat > "$B/tools/$f.py" <<'PY'
import os, sys
name = os.path.basename(sys.argv[0])
if name == "inventory.py":
    print('{"features": [], "screens": [], "stats": {}}' if os.environ.get("BREAK") != "inventory" else "")
    sys.exit(3 if os.environ.get("BREAK") == "inventory" else 0)
if name == "report.py":
    open("artifacts/summary.md", "w").write("ok\n")
if name == "source-key.py":
    print("k1")
sys.exit(1 if name == "coverage.py" and "--gate" in sys.argv else 0)
PY
done
cat > "$T/bin/docker" <<'D'
#!/usr/bin/env bash
case "$*" in
  *runnerd.py\ suite*) echo "1 passed in 0.01s";;
  *core_admin_user*) echo 1;;
  *State.Running*) echo "${APP_UP:-false}";;
esac
exit 0
D
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/curl"
chmod +x "$T/bin/docker" "$T/bin/curl"
run() { : > "$T/server.log"; (cd "$P" && SERVER_LOG="$T/server.log" E2E_DIR="$E" PATH="$T/bin:$PATH" KEEP=0 REVIEW=skip HOME="$T" timeout 120 bash "$B/run.sh" "${1:-all}" > "$T/out.log" 2>&1); }
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; sed -n '/== /p' "$T/out.log"; cat "$T/server.log"; fi; }
run; RC=$?
check "a run whose coverage gate fails reaches its end with rc 9" "grep -q 'done in' '$T/out.log' && [ $RC -eq 9 ]"
check "it takes the bench down at the end" "grep -qx down '$T/server.log'"
BREAK=inventory run; RC=$?
check "a run that dies on a failed step still takes the bench down" "! grep -q 'done in' '$T/out.log' && [ $RC -ne 0 ] && grep -qx down '$T/server.log'"
APP_UP=true run upgrade
check "an upgrade on a bench that ran before leaves it up" "grep -q 'upgrade done' '$T/out.log' && ! grep -qx down '$T/server.log'"
run upgrade
check "an upgrade on a bench that was down takes it down" "grep -q 'upgrade done' '$T/out.log' && grep -qx down '$T/server.log'"
[ $fail -eq 0 ] || exit 1
