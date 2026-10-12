#!/usr/bin/env bash
# The e2e bench of a Lutece project, run on the machine's shared e2e server. Started by lpe2e from the project's
# e2e/ folder, which holds only the project's configuration (e2e.conf, scenarios, fixtures, baselines, harness/db
# seeds, harness/site/webapp overlay, app.env, server-errors-allow.txt) and the run's artifacts.
#
#   lpe2e              build (if needed) + up + seed + inventory + discover + tests + perf + report, then down
#                      however it ends; green only with every action covered (a plugin) and the visual review done
#   lpe2e build        package the artefact and lay out the bench site (the assembled site is cached by composition)
#   lpe2e up           build when the sources changed, start the bench on the shared server, wait for the
#                      application, seed
#   lpe2e inventory    static inventory (artifacts/inventory.json)
#   lpe2e discover     dynamic crawl of the running back office (artifacts/discovered.json)
#   lpe2e test         every suite (screens, fo, scenarios, forms) against the running bench
#   lpe2e test <args>  one pytest call, e.g. `test /bench/tests/test_scenarios.py -k my_scenario` (seconds)
#   lpe2e perf         server timings, DB digests (artifacts/perf.json); E2E_JFR=1 adds the JFR hot methods
#   lpe2e report       artifacts/summary.md + report.html from the run artifacts
#   lpe2e review       check the visual review (artifacts/review.md) against the captures of the last run; a run that
#                      only lacked it then counts as passed
#   lpe2e upgrade      the previous version's database (v7 prepared by plugin-liquibase of the v7 line, a recette dump,
#                      or the previous v8 war) taken over by the bench site, what the upgrade did, then every suite
#   lpe2e watch        the hot loop on a running bench (KEEP=1 lpe2e first): a web file or test page is served at
#                      once, a Java method body redefined in the running JVM, anything else packages the artefact
#                      again and restarts the JVM; then the tests the change can break (a changed scenario file: its
#                      scenarios), then every suite. It holds the bench only while those tests run: lpe2e test works
#                      beside it. Ctrl-C to stop
#   lpe2e selftest     proof that watch misses no bug on a running bench: a template bug then a Java bug injected
#                      through watch's path right after a render, each red, reverted, green; sources restored
#   lpe2e down         remove the bench's containers and database (the shared server stays)
#   lpe2e logs|status|port|sh   the application's logs, the containers, the host port, a shell in the application
#   lpe2e key          the key of what a verdict depends on (project, its configuration, the bench code, the Lutece
#                      artefacts of the site): a pass-* stamp holding it is still valid
#   lpe2e py <script> [args]    a Python script in the bench's runner (/bench is the bench code, /e2e the project)
#
# Variables: E2E_VOLUME=none|small|large (seed size, none by default), E2E_WORKERS=n (default: from the free cores),
# KEEP=1 (leave the bench up after a full run), E2E_MIN_MEM_MB=n (memory a bench needs free before it is raised:
# 6144 with E2E_SEARCH, 3072 otherwise; 0 skips the check), E2E_MEM_WAIT=s (how long to wait for it, 120).
# Everything else lives in e2e.conf.
# Exit codes: 1 bench, 2 usage, 3 the bench's own oracle fails, 4 bench invariant broken, 5 unexpected server
# errors, 6 smoke test, 7 visual review missing, 8 a suite with something to prove was entirely skipped,
# 9 an action of the artefact proven by no scenario (COVERAGE=skip to iterate), 10 the artefact resolves a lutece-core
# below the Lutece 8 level lutecepowers supports (tools/v8-floor.conf), 11 the database takeover of lpe2e upgrade failed,
# 12 not enough free memory to raise the bench; otherwise pytest's code (1 = a red test).
set -euo pipefail
BENCH=$(cd "$(dirname "$0")" && pwd)
. "$BENCH/tools/python.sh"
E2E=$(cd "${E2E_DIR:?run the bench through lpe2e, from the project}" && pwd)
export E2E_DIR="$E2E"
cd "$E2E"
case "${1:-all}" in logs|status|port|sh|review|report|watch|-h|--help) ;; *) . "$BENCH/tools/lock.sh"; E2E_LOCK_CMD="lpe2e $*" e2e_lock "$E2E" ;; esac
# The environment wins over e2e.conf: E2E_VOLUME=large lpe2e must not be silently overwritten.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
set -a; . ./e2e.conf; set +a
# Proving a fix of a dependency before it is published: `mvn install` in its clone puts the patched build in the
# local repository, but Maven still prefers the remote snapshot when it is newer. Offline makes the local build win.
if [ "${E2E_MVN_OFFLINE:-0}" = 1 ]; then export MVN="${MVN:-mvn} -o"; fi
eval "$_e2e_env"
SERVER=(python3 "$BENCH/server/server.py")
# Browsers per suite: half the cores left to this bench by the other benches running on the machine, 1 to 4.
auto_workers() {
  local cores others n
  cores=$(nproc 2>/dev/null || echo 4)
  others=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cE -- '^lpe2e-.*-app$' || true)
  [ "$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cx -- "lpe2e-${E2E_NAME}-app" || true)" -gt 0 ] || others=$((others + 1))
  n=$(( cores / (others > 0 ? others : 1) / 2 ))
  [ "$n" -gt 4 ] && n=4
  [ "$n" -lt 1 ] && n=1
  echo "$n"
}
# E2E_JFR=1 records the application with the flight recorder (hot methods in the report).
[ "${E2E_JFR:-}" = 1 ] && export E2E_JVM_ARGS="${E2E_JVM_ARGS:-} -XX:StartFlightRecording=filename=/logs/lutece.jfr,dumponexit=true,settings=profile -XX:FlightRecorderOptions=stackdepth=128"
export E2E_VOLUME=${E2E_VOLUME:-none} E2E_WORKERS=${E2E_WORKERS:-$(auto_workers)} E2E_CONTEXT=${E2E_CONTEXT:-lutece}
APP="lpe2e-${E2E_NAME}-app"
# The bench's state directory: under LUTECEPOWERS_E2E_HOME, as lpe2e and server.py read it.
BENCH_STATE="${LUTECEPOWERS_E2E_HOME:-$HOME/.lutecepowers-e2e}/benches/$E2E_NAME"
export LPE2E_SITE="$BENCH_STATE/site"
RUNNER_C="lpe2e-${E2E_NAME}-runner"
DB_NAME=${E2E_NAME//[^A-Za-z0-9_]/_}
START=$SECONDS

step() { printf '\n\033[1m== %s\033[0m (%ds)\n' "$*" "$((SECONDS - START))"; }
unsupported() { echo "$1: not supported"; exit 2; }
case "$E2E_TARGET" in plugin|site) ;; *) unsupported "E2E_TARGET=$E2E_TARGET" ;; esac
# A site has no screen of its own: what it ships is the screens of its plugins, so its bench opens them all.
[ "$E2E_TARGET" = site ] && export E2E_SCOPE=${E2E_SCOPE:-all}

# The application deployed and answering its login page.
health() {
  [ "$(docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null)" = true ] || { echo missing; return; }
  [ "$(docker exec "$RUNNER_C" curl -s -m 5 -o /dev/null -w '%{http_code}' "http://localhost:9090/$E2E_CONTEXT/jsp/admin/AdminLogin.jsp" 2>/dev/null)" = 200 ] && echo healthy || echo starting
}

# Runs Python in the bench's runner: the bench code at /bench, the project's e2e folder at /e2e (the working directory).
# pytest returns 5 when a suite collects no tests (a plugin with no front office, no forms): not a failure.
runner() { docker exec -i -w /e2e "$RUNNER_C" python "$@"; }
# pytest in the runner: rootdir /bench (node ids tests/test_x.py::…), no cache (the bench code is read-only).
PYTEST=(-m pytest -p no:cacheprovider --rootdir=/bench)
# One suite on the warm daemon (server/runnerd.py): its JUnit file is artifacts/junit-<suite>.xml, or the name given by
# E2E_SUITE_FILE. pysuite reads pytest's 5 (nothing collected: a plugin with no front office, no forms) as a pass.
suite() { local n=$1; shift; runner /bench/server/runnerd.py suite "$n" "artifacts/junit-${E2E_SUITE_FILE:-$n}.xml" "$@"; }
pysuite() { local c=0; suite "$@" || c=$?; [ "$c" = 5 ] && return 0 || return $c; }
pyrun() { local c=0; runner "$@" || c=$?; [ "$c" = 5 ] && return 0 || return $c; }

# Package the artefact and lay out the bench site; a site whose BOM manages an older core is tested on the latest
# Lutece 8 one, and the drift is reported.
cmd_build() {
  step "build: package $E2E_TARGET, lay out the bench site"
  if [ "$E2E_TARGET" = site ]; then
    mkdir -p artifacts
    bash "$BENCH/tools/check-v8-floor.sh" "$E2E_SRC" > artifacts/site-drift.txt 2>&1 && rm -f artifacts/site-drift.txt \
      || { echo ">> the site ships an older Lutece than the bench tests: $(head -c 300 artifacts/site-drift.txt)"; }
  else
    bash "$BENCH/tools/check-v8-floor.sh" "$E2E_SRC" || [ $? -eq 2 ] || { echo "build: refused, the artefact is below the Lutece 8 level lutecepowers supports"; exit 10; }
  fi
  "${SERVER[@]}" build
  mkdir -p "$BENCH_STATE"
  bash "$BENCH/tools/src-digest.sh" "$E2E_SRC" > "$BENCH_STATE/built.src"
  python3 "$BENCH/tools/dep-digest.py" "$LPE2E_SITE" "$(own_artifact)" > "$BENCH_STATE/built.deps"
  bash "$BENCH/tools/liquibase-visibility.sh" "$BENCH_STATE/site" || true
}

# The machine has the memory a bench takes before one is raised (MemAvailable of /proc/meminfo against E2E_MIN_MEM_MB):
# a bench with Solr and Elasticsearch peaks near 4.7 GB on a small plugin, the application's JVM grows with the site,
# and a machine that runs out kills the background jobs, the run with them. Waits E2E_MEM_WAIT seconds for memory to
# come back, then exits 12.
mem_guard() {
  local need=${E2E_MIN_MEM_MB:-$([ -n "${E2E_SEARCH:-}" ] && echo 6144 || echo 3072)} wait=${E2E_MEM_WAIT:-120} t=0 avail
  local info=${LPE2E_MEMINFO:-/proc/meminfo}
  [ "$need" -gt 0 ] && [ -r "$info" ] || return 0
  while avail=$(awk '/^MemAvailable:/{print int($2 / 1024)}' "$info"); [ "${avail:-$need}" -lt "$need" ]; do
    if [ "$t" -ge "$wait" ]; then
      echo "not enough free memory to raise the bench: ${avail} MB available, ${need} MB needed (E2E_MIN_MEM_MB); stop another bench or job, then run again"
      exit 12
    fi
    [ "$t" -gt 0 ] || echo "memory: ${avail} MB available, ${need} MB needed: waiting up to ${wait}s"
    sleep 5; t=$((t + 5))
  done
}

# Start the bench on a fresh database without the previous run's logs, the previous summary kept as summary-prev.md;
# E2E_RESTART_AFTER_SEED restarts the application once the seed is in, for a target that caches tables at boot.
cmd_up() {
  step "up: $E2E_NAME on the shared e2e server (fresh database)"
  mem_guard
  if [ -f artifacts/summary.md ]; then cp artifacts/summary.md artifacts/summary-prev.md; fi
  docker rm -f "$APP" >/dev/null 2>&1 || true
  rm -rf artifacts/logs; mkdir -p artifacts/logs; chmod 777 artifacts/logs 2>/dev/null || true
  "${SERVER[@]}" up
  if [ -n "${E2E_RESTART_AFTER_SEED:-}" ]; then
    step "restart the application on the seeded database"
    "${SERVER[@]}" restart
  fi
}

# Static inventory: of the assembled site for a site, of the artefact's sources otherwise.
cmd_inventory() {
  step "inventory"
  local site="$BENCH_STATE/site"
  [ -d "$site" ] || { echo "inventory: no bench site yet (lpe2e build), the artefact's own sources only"; site=""; }
  if [ "$E2E_TARGET" = site ] && [ -n "$site" ]; then
    python3 "$BENCH/tools/inventory.py" "$site" --markdown-out artifacts/inventory.md > artifacts/inventory.json
  else
    python3 "$BENCH/tools/inventory.py" "$E2E_SRC" ${site:+--extra "$site"} --markdown-out artifacts/inventory.md > artifacts/inventory.json
  fi
  python3 -c "import json;print(json.load(open('artifacts/inventory.json'))['stats'])"
}

cmd_discover() {
  step "discover"
  runner /bench/server/runnerd.py discover
}

# What exactly was tested, written where the report reads it: the source key (tools/source-key.py), the images, the
# commit of the sources. A green run means nothing when nobody can say which build it was.
fingerprint() {
  python3 - "$E2E_SRC" "$BENCH" <<'PY'
import json, os, pathlib, subprocess, sys
src, bench = sys.argv[1], sys.argv[2]
def run(*a):
    try: return subprocess.check_output(a, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception: return ""
fp = {"source_commit": run("git", "-C", src, "rev-parse", "--short", "HEAD"),
      "source_dirty": bool(run("git", "-C", src, "status", "--porcelain")),
      "source_key": run(sys.executable, bench + "/tools/source-key.py", src, bench),
      "base_url": os.environ.get("E2E_BASE_URL") or None,
      "images": {}}
for img in ("lpe2e-liberty:26.0.0.9", "mariadb:11.8", "mcr.microsoft.com/playwright/python:v1.62.0-noble"):
    d = run("docker", "image", "inspect", "-f", "{{index .RepoDigests 0}}|{{.Id}}", img)
    if d: fp["images"][img] = d.split("|")[0] or d.split("|")[1][:19]
pathlib.Path("artifacts").mkdir(exist_ok=True)
pathlib.Path("artifacts/fingerprint.json").write_text(json.dumps(fp, indent=1))
print("fingerprint: sources %s%s, key %s" % (fp["source_commit"] or "?", " (uncommitted changes)" if fp["source_dirty"] else "", fp["source_key"] or "-"))
PY
}

# A suite that had something to prove and proved nothing: every test skipped while the inventory lists elements
# for that surface, fails the run (code 8). A skip the bench declared is not counted.
skipped_suites() {
  python3 - <<'PY'
import json, pathlib, sys, xml.etree.ElementTree as ET
inv = json.loads(pathlib.Path("artifacts/inventory.json").read_text()) if pathlib.Path("artifacts/inventory.json").exists() else {}
tgt = [s for s in inv.get("screens", []) if s.get("origin", "target") == "target"]
fo = any(s.get("surface") == "fo" for s in tgt)
bo = any(s.get("surface", "bo") == "bo" for s in tgt)
scen = any(p.name != "screens.yaml" and not p.name.startswith("coverage-") for p in pathlib.Path("scenarios").glob("*.yaml"))
bad = []
DECLARED = "declared exclusion: "
for suite, needed in (("fo", fo), ("scenarios", scen), ("screens", bo)):
    f = pathlib.Path("artifacts/junit-%s.xml" % suite)
    if not f.exists() or not needed: continue
    r = ET.parse(f).getroot(); ts = r if r.tag == "testsuite" else r.find("testsuite")
    n, sk = int(ts.get("tests", 0)), int(ts.get("skipped", 0))
    if not n or sk != n: continue
    msgs = [s.get("message", "") for tc in ts for s in tc.findall("skipped")]
    if msgs and all(m.startswith(DECLARED) for m in msgs): continue
    bad.append("%s (%d/%d skipped)" % (suite, sk, n))
if bad:
    print("SUITE ENTIRELY SKIPPED with something to prove: " + ", ".join(bad) + " — a skip is not a proof"); sys.exit(1)
PY
}

# A bench override that switches the artefact's own security off turns every test of that security into a test of
# nothing: the refusals are never proven. Any such key under the site's conf/override fails the run (code 4) unless
# e2e.conf names it in E2E_ALLOW_SECURITY_OFF, which the summary then prints as a declared weakening.
security_overrides() {
  local allowed=",${E2E_ALLOW_SECURITY_OFF:-},"
  local bad=""
  while IFS= read -r line; do
    local key=${line%%=*}; key=${key##*:}; key=$(echo "$key" | tr -d ' ')
    case "$allowed" in *",$key,"*) continue;; esac
    bad="$bad$line"$'\n'
  done < <(grep -rHiE '^[[:space:]]*[a-z0-9_.-]*(secur|auth|signature|sign\.|csrf|token|captcha)[a-z0-9_.-]*[[:space:]]*=[[:space:]]*(false|0|off|no|none)[[:space:]]*$' harness/site/webapp/WEB-INF/conf/override 2>/dev/null || true)
  if [ -n "$bad" ]; then
    printf 'SECURITY SWITCHED OFF BY THE BENCH (conf/override), its refusals are never tested:\n%s' "$bad"
    echo "remove the override, or name the key in E2E_ALLOW_SECURITY_OFF in e2e.conf with the reason in a comment"
    return 1
  fi
}

cmd_test() {
  step "tests: screens + scenarios + forms ($E2E_WORKERS workers)"
  fingerprint || true
  "${SERVER[@]}" seed > /dev/null 2>&1 || true
  rm -rf artifacts/results artifacts/shots artifacts/aria artifacts/state; mkdir -p artifacts/results
  runner /bench/tools/metrics.py snapshot before
  local rc=0
  suite harness /bench/tests/test_harness.py || { echo "the bench's own oracle fails: fix tests/lutece.py before trusting any result"; return 3; }
  pysuite screens /bench/tests/test_screens.py "$@" || rc=$?
  pysuite fo /bench/tests/test_fo.py "$@" || rc=$?
  pysuite scenarios /bench/tests/test_scenarios.py -m "not serial" "$@" || rc=$?
  E2E_SUITE_FILE=scenarios-serial pysuite scenarios --serial /bench/tests/test_scenarios.py -m serial "$@" || rc=$?
  pysuite forms /bench/tests/test_forms.py "$@" || rc=$?
  runner /bench/tools/metrics.py snapshot after
  invariants || rc=4
  skipped_suites || { [ "$rc" -ne 0 ] || rc=8; }
  return $rc
}

# The bench must still be usable after a run: the account the whole bench authenticates with exists with its access
# code. A broken invariant means a test mutated a protected account (report it, never repair silently).
invariants() {
  local n
  n=$(docker exec lpe2e-db mariadb -ulutece -plutece "$DB_NAME" -N -e "SELECT COUNT(*) FROM core_admin_user WHERE id_user=1 AND access_code='${E2E_ADMIN:-admin}'" 2>/dev/null || echo 0)
  if [ "$n" != "1" ]; then
    echo "BENCH INVARIANT BROKEN: the admin account (id 1) is gone or renamed: a test altered it. Results after that point are not trustworthy." | tee artifacts/INVARIANT-BROKEN.txt
    return 1
  fi
  rm -f artifacts/INVARIANT-BROKEN.txt
}

# True when the bench site is missing, or anything that goes into it changed since it was laid out: the artefact's
# sources, the bench's configuration of the site, the bench code, a Lutece dependency rebuilt in the local repository
# (a dependency fixed locally, judged by the content of its jar, tools/dep-digest.py, not by its date: an install can
# keep an older date). Prevents testing a stale build.
needs_build() {
  local stamp="$BENCH_STATE/built"
  [ -f "$stamp" ] || return 0
  [ "$(cat "$stamp.src" 2>/dev/null)" = "$(bash "$BENCH/tools/src-digest.sh" "$E2E_SRC")" ] || return 0
  [ -n "$(find "$E2E_SRC/src" "$E2E_SRC/webapp" "$E2E_SRC/pom.xml" -type f -newer "$stamp" 2>/dev/null | head -1)" ] && return 0
  [ -n "$(find e2e.conf harness "$BENCH/harness" "$BENCH/tools/gen-site.sh" "$BENCH/server" -type f -newer "$stamp" 2>/dev/null | head -1)" ] && return 0
  [ "$(cat "$stamp.deps" 2>/dev/null)" = "$(python3 "$BENCH/tools/dep-digest.py" "$LPE2E_SITE" "$(own_artifact)")" ] || return 0
  return 1
}

# The artifactId of the artefact under test: the second one of its pom, after the parent's.
own_artifact() {
  grep -oE "<artifactId>[^<]+" "$E2E_SRC/pom.xml" 2>/dev/null | sed -n 2p | sed 's/<artifactId>//'
}

# Fast fail before the full suite: log in and open a few of the artefact's own entry screens; if every one is an
# error page, the build is broadly broken (a missing method, a bad template) — abort with a clear message.
smoke() {
  step "smoke test"
  local base="http://localhost:$("${SERVER[@]}" port)/${E2E_CONTEXT}" jar; jar=$(mktemp)
  local token; token=$(curl -s -c "$jar" "$base/jsp/admin/AdminLogin.jsp" | grep -oE 'name="token"[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
  curl -s -c "$jar" -b "$jar" -X POST --data-urlencode access_code=admin --data-urlencode password=adminadmin --data-urlencode "token=$token" "$base/jsp/admin/DoAdminLogin.jsp" -o /dev/null
  local urls; urls=$(python3 -c "import json;i=json.load(open('artifacts/inventory.json'));print(' '.join([f['url'] for f in i['features'] if f.get('url') and f.get('origin','target')=='target'][:4]))" 2>/dev/null)
  [ -n "$urls" ] || { rm -f "$jar"; return 0; }
  local n=0 bad=0 u body
  for u in $urls; do
    n=$((n+1)); body=$(curl -s -b "$jar" "$base/$u")
    echo "$body" | grep -qiE 'internal error|erreur technique|contacter immédiatement|MethodNotFound|Method not found' && bad=$((bad+1))
  done
  rm -f "$jar"
  if [ "$n" -gt 0 ] && [ "$bad" -eq "$n" ]; then
    echo "smoke: all $n entry screens of $E2E_TARGET returned an error page — the build looks broken; see artifacts/logs/messages.log"
    return 1
  fi
  echo "smoke: $((n-bad))/$n entry screens render"
  return 0
}

# A run is red when the server log holds an exception outside harness/server-errors-allow.txt.
check_server_errors() {
  local u; u=$(python3 -c "import json;print(json.load(open('artifacts/perf.json'))['server_errors'].get('unexpected_total',0))" 2>/dev/null || echo 0)
  [ "${u:-0}" -gt 0 ] || return 0
  echo "UNEXPECTED SERVER ERRORS: $u (see 'Erreurs serveur inattendues' in artifacts/summary.md) — allowlist: harness/server-errors-allow.txt"
  return 1
}

cmd_perf() {
  step "perf: access log, DB digests"
  rm -f artifacts/jfr.txt
  if [ "${E2E_JFR:-}" = 1 ]; then
    local pid; pid=$(docker exec "$APP" sh -c 'jcmd -l | awk "/ws-server.jar/{print \$1}"')
    docker exec "$APP" sh -c "jcmd $pid JFR.dump filename=/logs/lutece-run.jfr" | tail -1
    docker exec "$APP" sh -c 'for v in hot-methods allocation-by-class gc-pauses contention-by-site; do echo "## $v"; jfr view $v /logs/lutece-run.jfr; done' > artifacts/jfr.txt 2>&1 || true
  fi
  runner /bench/tools/metrics.py perf
}

# Summary and report; the first run outside E2E_SCOPE=all seeds the structural baseline.
cmd_report() {
  step "report"
  if [ "${E2E_SCOPE:-target}" != all ] && [ -d artifacts/aria ] && [ -z "$(ls -A baselines/aria 2>/dev/null)" ]; then
    mkdir -p baselines/aria && cp artifacts/aria/*.yaml baselines/aria/ 2>/dev/null && echo "baselines/aria seeded from this run ($(ls baselines/aria | wc -l) screens)"
  fi
  python3 "$BENCH/tools/coverage.py" | sed -n 1,3p || true
  python3 "$BENCH/tools/causes.py" > /dev/null
  python3 "$BENCH/tools/report.py"
  python3 "$BENCH/tools/review.py" todo
  echo; cat artifacts/summary.md
}

# Records the key of the sources a green run judged (artifacts/pass-<what>), when they did not change during the run.
pass_stamp() {
  local now start
  now=$(python3 "$BENCH/tools/source-key.py" "$E2E_SRC" "$BENCH" 2>/dev/null || true)
  start=$(python3 -c 'import json; print(json.load(open("artifacts/fingerprint.json")).get("source_key") or "")' 2>/dev/null || true)
  if [ -n "$now" ] && [ "$now" = "$start" ]; then echo "$now" > "artifacts/pass-$1"; else rm -f "artifacts/pass-$1"; fi
}

# The database upgrade, lived the way an environment lives it (server/upgrade.py, reference/upgrade.md): the previous
# version's database, brought under Liquibase by one v7 start when it is a v7 one, taken over by the bench site; then
# the suites on that database. Exit 11 when the database upgrade failed (the v7 preparation or the takeover), with a
# summary.md that says so; else the code of the suites.
cmd_upgrade() {
  e2e_on_exit() { [ "${KEEP:-}" = 1 ] || cmd_down; }
  mkdir -p artifacts
  needs_build && cmd_build
  step "upgrade: the previous version's database taken over by the bench site"
  mem_guard
  if [ -f artifacts/summary.md ]; then mv artifacts/summary.md artifacts/summary-prev.md; fi
  rm -f artifacts/pass-upgrade
  rm -rf artifacts/logs artifacts/logs7; mkdir -p artifacts/logs artifacts/logs7; chmod 777 artifacts/logs artifacts/logs7 2>/dev/null || true
  local rc=0
  python3 "$BENCH/server/upgrade.py" || rc=$?
  if [ "$rc" -ne 0 ]; then
    python3 "$BENCH/tools/report.py" upgrade-failed || true
    step "upgrade failed in $((SECONDS - START))s, rc=$rc"
    exit $rc
  fi
  cmd_inventory
  cmd_discover
  cmd_test || rc=$?
  cmd_perf
  cmd_report
  check_server_errors || { [ "$rc" -ne 0 ] || rc=5; }
  if [ "$rc" -eq 0 ]; then pass_stamp upgrade; fi
  step "upgrade done in $((SECONDS - START))s, tests rc=$rc"
  exit $rc
}

cmd_down() {
  step "down"
  "${SERVER[@]}" down
}

case "${1:-all}" in
  build)     cmd_build ;;
  up)        needs_build && cmd_build; cmd_up ;;
  inventory) cmd_inventory ;;
  discover)  cmd_discover ;;
  test)      shift; if [ $# -gt 0 ]; then runner "${PYTEST[@]}" -q --tb=short "$@"; else cmd_test; fi ;;
  perf)      cmd_perf ;;
  report)    cmd_report ;;
  review)    python3 "$BENCH/tools/review.py" "${2:-check}"
             if [ "${2:-check}" = check ] && [ -s artifacts/pass-tests ] && [ "$(cat artifacts/pass-tests)" = "$(python3 "$BENCH/tools/source-key.py" "$E2E_SRC" "$BENCH" 2>/dev/null)" ]; then
               cp artifacts/pass-tests artifacts/pass-all; echo ">> review done: the last run of these sources counts as passed, no need to run it again"
             fi ;;
  upgrade)   cmd_upgrade ;;
  external)  unsupported "external (an instance deployed elsewhere)" ;;
  down)      cmd_down ;;
  clean)     cmd_down ;;
  logs)      "${SERVER[@]}" logs ;;
  status)    "${SERVER[@]}" status ;;
  port)      "${SERVER[@]}" port ;;
  key)       python3 "$BENCH/tools/source-key.py" "$E2E_SRC" "$BENCH" ;;
  watch)     "${SERVER[@]}" watch ;;
  selftest)  "${SERVER[@]}" selftest ;;
  py)        shift; runner "$@" ;;
  sh)        docker exec -it "$APP" sh ;;
  all)
    rm -f artifacts/pass-all artifacts/pass-tests
    mkdir -p artifacts
    e2e_on_exit() { [ "${KEEP:-}" = 1 ] || cmd_down; }
    needs_build && cmd_build
    cmd_up
    cmd_inventory
    cmd_discover
    if ! smoke; then
      cmd_report 2>/dev/null || true
      step "aborted on smoke test in $((SECONDS - START))s"
      exit 6
    fi
    rc=0; cmd_test || rc=$?
    cmd_perf
    cmd_report
    check_server_errors || { [ "$rc" -ne 0 ] || rc=5; }
    security_overrides || { [ "$rc" -ne 0 ] || rc=4; }
    if [ "${COVERAGE:-}" != skip ] && [ "$E2E_TARGET" != site ]; then
      python3 "$BENCH/tools/coverage.py" --gate > /dev/null || { python3 "$BENCH/tools/coverage.py" --gate | sed -n '/COVERAGE GATE/,$p' || true; [ "$rc" -ne 0 ] || rc=9; }
    fi
    [ "$rc" -eq 0 ] && [ "${COVERAGE:-}" != skip ] && pass_stamp tests
    if [ "${REVIEW:-}" != skip ]; then
      python3 "$BENCH/tools/review.py" check || { [ "$rc" -ne 0 ] || { rc=7; echo ">> rc=7: every suite passed, only the visual review is missing: write artifacts/review.md, then lpe2e review (no need to run the bench again)"; }; }
    fi
    if [ "$rc" -eq 0 ] && [ "${COVERAGE:-}" != skip ] && [ "${REVIEW:-}" != skip ]; then pass_stamp all; else rm -f artifacts/pass-all; fi
    step "done in $((SECONDS - START))s, tests rc=$rc"
    exit $rc ;;
  *) sed -n '2,/^set -euo/{/^set -euo/!p}' "$0"; exit 2 ;;
esac
