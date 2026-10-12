#!/usr/bin/env bash
# Checks the pure parts of lpe2e watch (server/server.py): it sees a changed scenario file and a changed test page of
# e2e/harness/site/webapp; a scenario file names its own scenarios; a class cited only by a test page names that page;
# a test page is copied into the site, not rebuilt; the bench lock is taken once, refused while a live run holds it,
# taken over from a dead one; lpe2e up builds first when the sources changed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SERVER="$HERE/../../skills/lutece-e2e/server"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/src/java/a/service" "$T/p/webapp/WEB-INF/plugins" "$T/p/e2e/scenarios" "$T/p/e2e/harness/site/webapp/jsp/e2e" "$T/state/site"
echo 'class AService { void run() { } }' > "$T/p/src/java/a/service/AService.java"
echo '<plug-in><name>a</name></plug-in>' > "$T/p/webapp/WEB-INF/plugins/a.xml"
echo 'scenarios: []' > "$T/p/e2e/scenarios/a-v7data.yaml"
echo '<%= a.service.AService.class %>' > "$T/p/e2e/harness/site/webapp/jsp/e2e/aprobe.jsp"
out=$(cd "$SERVER" && python3 - "$T" <<'PY'
import os, pathlib, sys
import server
t = pathlib.Path(sys.argv[1])
class B:
    src = t / "p"
    e2e = t / "p/e2e"
    state = t / "state"
    runner = "r"
bench = B()
snap = server.snapshot(bench.src, bench.e2e)
print(sorted(str(f.relative_to(bench.src)) for f in snap if "e2e" in f.parts))
print(server.related(bench, [bench.e2e / "scenarios/a-v7data.yaml"])[0])
print(server.related(bench, [bench.src / "src/java/a/service/AService.java"])[0])
class Hot:
    def apply(self, paths): raise AssertionError("compiled")
server.sh = lambda *a, **k: None
server.log = lambda m: None
server.subprocess.Popen = lambda *a, **k: None
_, ok = server.apply(bench, Hot(), [bench.e2e / "harness/site/webapp/jsp/e2e/aprobe.jsp", bench.e2e / "scenarios/a-v7data.yaml"])
print(ok, (bench.state / "site/jsp/e2e/aprobe.jsp").exists())
print(server.bench_lock(bench), server.bench_lock(bench))
(bench.e2e / ".run.lock/pid").write_text("999999999")
print(server.bench_lock(bench), (bench.e2e / ".run.lock/pid").read_text() == str(os.getpid()))
PY
)
expected="['e2e/harness/site/webapp/jsp/e2e/aprobe.jsp', 'e2e/scenarios/a-v7data.yaml']
['a-v7data']
['aprobe']
True True
True False
True True"
fail=0
if [ "$out" = "$expected" ]; then echo "PASS: watch sees scenarios and test pages, names their tests, locks the bench per batch"; else echo "FAIL: watch"; echo "$out"; fail=1; fi
if grep -q '^  up)        needs_build && cmd_build; cmd_up ;;' "$SERVER/../run.sh"; then echo "PASS: lpe2e up builds first when the sources changed"; else echo "FAIL: lpe2e up does not build a changed source"; fail=1; fi
exit $fail
