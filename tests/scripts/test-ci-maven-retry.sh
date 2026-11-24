#!/usr/bin/env bash
# Exercises the CI Maven warm-up with successful, transient and persistent artifact download failures.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
python3 - "$ROOT/.github/workflows/tests.yml" "$T/warm.sh" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)
step = next(s for s in workflow["jobs"]["tests"]["steps"] if s.get("name") == "Maven artifacts the tests read")
with open(sys.argv[2], "w") as f:
    f.write(step["run"])
PY
cat > "$T/bin/python3" <<'SH'
#!/usr/bin/env bash
case "$2" in
  snapshot) echo fr.paris.lutece:lutece-core:8.1.0-SNAPSHOT ;;
  bom) echo fr.paris.lutece.starters:lutece-bom:1.0:8.0 ;;
  *) exit 1 ;;
esac
SH
printf '#!/usr/bin/env bash\necho "<version>2.3.34</version>"\n' > "$T/bin/curl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"
cat > "$T/bin/mvn" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  *-Dartifact=fr.paris.lutece:lutece-core:8.1.0-SNAPSHOT*)
    n=$(grep -c -- '-Dartifact=fr.paris.lutece:lutece-core:8.1.0-SNAPSHOT' "$CALLS")
    [ "$n" -gt "$FAILURES" ] ;;
esac
SH
chmod +x "$T/bin/"*
cd "$ROOT"
for failures in 0 2 3; do
  : > "$T/calls"
  rc=0
  PATH="$T/bin:$PATH" CALLS="$T/calls" FAILURES="$failures" bash -eo pipefail "$T/warm.sh" > "$T/out" 2>&1 || rc=$?
  count=$(grep -c -- '-Dartifact=fr.paris.lutece:lutece-core:8.1.0-SNAPSHOT' "$T/calls")
  if [ "$failures" -lt 3 ]; then
    [ "$rc" -eq 0 ] && [ "$count" -eq $((failures + 1)) ] && grep -q 'dependency:list' "$T/calls"
  else
    [ "$rc" -ne 0 ] && [ "$count" -eq 3 ] && ! grep -q 'dependency:list' "$T/calls" && grep -q 'Failed to download .* after 3 attempts' "$T/out"
  fi
  echo "PASS: $failures failed snapshot downloads"
done
