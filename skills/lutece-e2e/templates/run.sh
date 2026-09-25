#!/usr/bin/env bash
# One entry point for the whole bench. Without argument: everything, from the sources to the report.
#
#   ./run.sh              build (if needed) + up + seed + inventory + discover + tests + perf + report
#   ./run.sh build        install the artefact under test, assemble the war, build the app image
#   ./run.sh up           start db + app, wait for health, seed (idempotent)
#   ./run.sh inventory    static inventory (artifacts/inventory.json) + EARS requirements
#   ./run.sh discover     dynamic crawl of the running back office (artifacts/discovered.json)
#   ./run.sh test         every suite (screens, fo, scenarios, forms) against the running stack
#   ./run.sh test <args>  one pytest call, e.g. `test tests/test_scenarios.py -k my_scenario` (seconds)
#   ./run.sh compare      the artefact in v7 (Tomcat) then in v8 on the same database, the suites both times, before/after report
#   ./run.sh external     the suites against an instance already deployed (E2E_BASE_URL, optional E2E_DB_*): no build, no seed, no fuzzer
#   ./run.sh perf         server timings, DB digests (artifacts/perf.json); E2E_PERF=1 adds the k6 load, E2E_JFR=1 the JFR hot methods
#   ./run.sh report       artifacts/summary.md + report.html from the run artifacts
#   ./run.sh deploy       hot copy into the running app (KEEP=1): webapp/ at once, the jar + a restart when Java changed
#   ./run.sh down         stop everything and drop the database volume
#   ./run.sh logs|status|sh   compose shortcuts
#   ./run.sh py <script> [args]  a Python script in the test runner, with the bench's own environment (a hand-made
#                        `docker compose run` with another environment recreates the running app and db)
#
# Variables: E2E_VOLUME=none|small|large (seed size, none by default), E2E_WORKERS=n (default: from the free cores), RUNNER=local (host venv instead of the container),
# KEEP=1 (do not stop the stack after a full run). Everything else lives in e2e.conf.
# Exit codes: 1 stack, 2 usage, 3 the bench's own oracle fails, 4 bench invariant broken, 5 unexpected server
# errors, 6 smoke test, 7 visual review missing, 8 a suite with something to prove was entirely skipped,
# 9 an action of the artefact proven by no scenario (COVERAGE=skip to iterate), 10 the artefact resolves a lutece-core
# below the Lutece 8 level lutecepowers supports (tools/v8-floor.conf);
# otherwise pytest's code (1 = a red test).
set -euo pipefail
E2E=$(cd "$(dirname "$0")" && pwd)
cd "$E2E"
# The environment wins over e2e.conf: E2E_VOLUME=large ./run.sh must not be silently overwritten.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
set -a; . ./e2e.conf; set +a
# Proving a fix of a dependency before it is published: `mvn install` in its clone puts the patched build in the
# local repository, but Maven still prefers the remote snapshot when it is newer. Offline makes the local build
# win on the v8 legs. It must not reach the v7 leg, which downloads its own artefacts: that leg keeps its own
# command (E2E_MVN7, gen-site7.sh) unless the bench set one.
if [ "${E2E_MVN_OFFLINE:-0}" = 1 ]; then export MVN="${MVN:-mvn} -o"; export E2E_MVN7="${E2E_MVN7:-mvn}"; fi
eval "$_e2e_env"
# Browsers per suite: half the cores left to this bench by the other benches running on the machine, 1 to 4.
auto_workers() {
  local cores others
  cores=$(nproc 2>/dev/null || echo 4)
  others=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c -- '-e2e-lutece-1$' || true)
  [ "$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cx -- "${E2E_NAME}-lutece-1" || true)" -gt 0 ] || others=$((others + 1))
  local n=$(( cores / (others > 0 ? others : 1) / 2 ))
  [ "$n" -gt 4 ] && n=4
  [ "$n" -lt 1 ] && n=1
  echo "$n"
}
# E2E_JFR=1 records the application with the flight recorder (hot methods in the report).
[ "${E2E_JFR:-}" = 1 ] && export E2E_JVM_ARGS="${E2E_JVM_ARGS:-} -XX:StartFlightRecording=filename=/logs/lutece.jfr,dumponexit=true,settings=profile -XX:FlightRecorderOptions=stackdepth=128"
export E2E_UID=$(id -u) E2E_VOLUME=${E2E_VOLUME:-none} E2E_WORKERS=${E2E_WORKERS:-$(auto_workers)}
APP="${E2E_NAME}-lutece-1"
# E2E_FAKES=1 starts the stand-ins of the external systems (harness/fakes, reference/external-systems.md),
# E2E_SEARCH=1 the search engines (solr, elastic).
COMPOSE=(docker compose -f harness/docker-compose.yml ${E2E_FAKES:+--profile fakes} ${E2E_SEARCH:+--profile search})
START=$SECONDS

# A bench refreshed long ago keeps old tools: warn when they differ from the skill that initialised it.
if [ -f "$E2E/.toolkit" ] && [ -d "$(cat "$E2E/.toolkit")/tools" ]; then
  _tk=$(cat "$E2E/.toolkit")
  if ! diff -rq --exclude __pycache__ "$_tk/tools" "$E2E/tools" >/dev/null 2>&1 || ! diff -rq --exclude __pycache__ "$_tk/tests" "$E2E/tests" >/dev/null 2>&1 || ! diff -q "$_tk/templates/run.sh" "$E2E/run.sh" >/dev/null 2>&1; then
    printf '\033[1mbench out of date: its tools differ from %s — run init-e2e.sh on the project to refresh them\033[0m\n' "$_tk" >&2
  fi
fi

step() { printf '\n\033[1m== %s\033[0m (%ds)\n' "$*" "$((SECONDS - START))"; }
health() { docker inspect -f '{{.State.Health.Status}}' "$APP" 2>/dev/null || echo missing; }

# Runs a command in the test runner: the pinned Playwright container by default, the host venv with RUNNER=local.
# pytest returns 5 when a suite collects no tests (a plugin with no front office, no forms): not a failure.
pyrun() { runner "$@"; local c=$?; [ "$c" = 5 ] && return 0 || return $c; }

# One test runner container, reused by every python call through docker exec. It shares the application's network
# namespace: recreated when the application restarted or a variable of its environment changed.
RUNNER_C="${E2E_NAME}-runner"
runner_up() {
  local key; key="$(docker inspect -f '{{.Id}} {{.State.StartedAt}}' "${E2E_NAME}-${E2E_APP:-lutece}-1" 2>/dev/null) ${E2E_SCOPE:-} ${E2E_VERSION:-} ${E2E_APP:-} ${E2E_APP_PORT:-} ${E2E_CONTEXT:-}"
  if [ "$(docker inspect -f '{{.State.Running}}' "$RUNNER_C" 2>/dev/null)" = true ] && [ "$(cat artifacts/.runner-key 2>/dev/null)" = "$key" ]; then
    return 0
  fi
  docker rm -f "$RUNNER_C" >/dev/null 2>&1 || true
  "${COMPOSE[@]}" run -d --name "$RUNNER_C" tests sleep infinity >/dev/null
  until docker exec "$RUNNER_C" sh -c 'H=$(md5sum /e2e/tools/requirements.txt | cut -c1-8); [ -f /e2e/artifacts/.pydeps/.$H ]' 2>/dev/null; do
    [ "$(docker inspect -f '{{.State.Running}}' "$RUNNER_C" 2>/dev/null)" = true ] || { docker logs "$RUNNER_C"; return 1; }
    sleep 1
  done
  mkdir -p artifacts; echo "$key" > artifacts/.runner-key
}

runner() {
  if [ "${RUNNER:-}" = local ]; then
    [ -x .venv/bin/python ] || { python3 -m venv .venv && .venv/bin/pip install -q -r tools/requirements.txt; }
    E2E_BASE="http://localhost:${E2E_PORT}/${E2E_CONTEXT}" E2E_DB_PORT=${E2E_DB_PORT:-13306} .venv/bin/python "$@"
  else
    runner_up
    docker exec -i "$RUNNER_C" python "$@"
  fi
}

cmd_build() {
  step "build: install $E2E_TARGET, assemble war, build image"
  bash tools/check-v8-floor.sh "$E2E_SRC" || [ $? -eq 2 ] || { echo "build: refused, the artefact is below the Lutece 8 level lutecepowers supports"; exit 10; }
  if [ "$E2E_TARGET" = site ]; then
    [ -f harness/site/target/lutece.war ] || { echo "build: E2E_TARGET=site assembles with the site's own pom: run 'mvn ... lutece:site-assembly' in the site, then 'jar -cf harness/site/target/lutece.war' from its exploded directory (SKILL.md, PHASE 1)"; exit 2; }
  else
    bash tools/gen-site.sh
  fi
  bash tools/liquibase-visibility.sh || true
  "${COMPOSE[@]}" build lutece
}

# Ports of this bench already taken, by another bench left running or by anything else: Docker answers with a
# networking error naming an endpoint, which reads like a Docker problem and is not one. Say who holds the port.
ports_free() {
  local p busy=""
  for p in "${E2E_PORT}" "${E2E_PORT7:-18081}" "${E2E_DB_PORT:-13306}" "${E2E_MAIL_PORT:-18025}" ${E2E_FAKES:+${E2E_FAKES_PORT:-19030} ${E2E_OAUTH2_PORT:-19085}} ${E2E_SEARCH:+${E2E_SOLR_PORT:-18983} ${E2E_ES_PORT:-19200}}; do
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { exec 3<&- 3>&-; busy="$busy $p($(docker ps --format '{{.Names}} {{.Ports}}' | grep -m1 ":$p->" | cut -d' ' -f1))"; }
  done
  [ -z "$busy" ] && return 0
  echo "ports already in use:$busy"
  echo "another bench is probably still up — stop it with 'cd <its project> && ./e2e/run.sh down', or give this bench its own slot (scripts/init-e2e.sh reads and records them in ~/.lutece-e2e-slots)."
  return 1
}

cmd_up() {
  # Every run starts from a clean slate: drop the database volume (schema recreated from scratch by the app's
  # Liquibase at boot) and wipe the previous run's logs, so results and the server-error analysis are per-run.
  step "up: fresh db + lutece (recreated from scratch each run)"
  "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  ports_free || exit 1
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  # Keep the previous run's summary: a before/after claim (with volume against without, before a fix against
  # after) is only honest if the baseline still exists to be reread.
  if [ -f artifacts/summary.md ]; then cp artifacts/summary.md artifacts/summary-prev.md; fi
  rm -rf artifacts/logs; mkdir -p artifacts/logs; chmod 777 artifacts/logs 2>/dev/null || true
  # The profile makes the stand-ins eligible; they still have to be named here or nothing starts them and the
  # application quietly calls the real system instead.
  # The Solr schema comes from the search plugin's webapp, which is in the assembled site whatever artefact is
  # under test; a bench only points E2E_SOLR_CONF elsewhere when it ships another one.
  if [ -n "${E2E_SEARCH:-}" ] && [ -z "${E2E_SOLR_CONF:-}" ]; then
    local sconf; sconf=$(find harness/site/target -maxdepth 1 -type d -name "e2e-site-*" | head -1)/WEB-INF/plugins/solr/conf
    [ -f "$sconf/solrconfig.xml" ] && export E2E_SOLR_CONF="$(cd "$sconf" && pwd)" && echo "solr: schema from the assembled site ($E2E_SOLR_CONF)"
  fi
  # The stand-ins' image follows harness/fakes: rebuilt when it changed (a cached no-op otherwise).
  [ -n "${E2E_FAKES:-}" ] && { "${COMPOSE[@]}" build -q fakes || exit 1; }
  "${COMPOSE[@]}" up -d db lutece ${E2E_FAKES:+fakes oauth2} ${E2E_SEARCH:+solr elastic}
  step "waiting for the application"
  until [ "$(health)" != starting ]; do sleep 1; done
  if [ "$(health)" != healthy ]; then
    echo "application unhealthy, last log lines:"; docker logs --tail 40 "$APP"
    # Never leave a dead stack holding the ports: the next bench on this slot would fail to bind for no reason of its own.
    [ "${KEEP:-}" = 1 ] || cmd_down
    exit 1
  fi
  step "seed ($E2E_VOLUME)"
  "${COMPOSE[@]}" run --rm dbinit
  # The application is already healthy when the seed lands, so anything it cached from the tables at boot —
  # a plugin's form list, a reference list, a type registry — holds the state of an empty database, for 1000 s
  # with the core's default time-to-live (lutece.cache.default.timeToLiveSeconds), longer than most runs. A bench whose target reads such a cache asks for one
  # restart here, after the rows exist, rather than chasing a race that depends on how fast dbinit ran.
  if [ -n "${E2E_RESTART_AFTER_SEED:-}" ]; then
    step "restart the application on the seeded database"
    "${COMPOSE[@]}" restart lutece >/dev/null
    until [ "$(health)" != starting ]; do sleep 1; done
    [ "$(health)" = healthy ] || { echo "application unhealthy after the post-seed restart:"; docker logs --tail 40 "$APP"; exit 1; }
  fi
}

cmd_inventory() {
  step "inventory"
  local exploded; exploded=$(find harness/site/target -maxdepth 1 -type d -name "e2e-site-*" 2>/dev/null | head -1)
  python3 tools/inventory.py "$E2E_SRC" ${exploded:+--extra "$exploded"} --markdown-out artifacts/inventory.md > artifacts/inventory.json
  python3 tools/ears.py artifacts/inventory.json scenarios > artifacts/requirements.ears.md
  python3 -c "import json;print(json.load(open('artifacts/inventory.json'))['stats'])"
}

cmd_discover() {
  step "discover"
  runner tools/discover.py
}

# What exactly was tested, written where the report reads it: the war's hash, the image digests, the commit of the
# sources. A green run means nothing when nobody can say which build it was.
fingerprint() {
  python3 - "$E2E_SRC" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
src = sys.argv[1]
def run(*a):
    try: return subprocess.check_output(a, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception: return ""
war = pathlib.Path("harness/site/target/lutece.war")
fp = {"source_commit": run("git", "-C", src, "rev-parse", "--short", "HEAD"),
      "source_dirty": bool(run("git", "-C", src, "status", "--porcelain")),
      "war_sha256": hashlib.sha256(war.read_bytes()).hexdigest()[:16] if war.exists() else None,
      "base_url": os.environ.get("E2E_BASE_URL") or None,
      "images": {}}
name = os.environ.get("E2E_NAME", "")
for img in (name + "-server:local", "mariadb:11.8", "mcr.microsoft.com/playwright/python:v1.62.0-noble"):
    d = run("docker", "image", "inspect", "-f", "{{index .RepoDigests 0}}|{{.Id}}", img)
    if d: fp["images"][img] = d.split("|")[0] or d.split("|")[1][:19]
pathlib.Path("artifacts").mkdir(exist_ok=True)
pathlib.Path("artifacts/fingerprint.json").write_text(json.dumps(fp, indent=1))
print("fingerprint: sources %s%s, war %s" % (fp["source_commit"] or "?", " (uncommitted changes)" if fp["source_dirty"] else "", fp["war_sha256"] or "-"))
PY
}

# A suite that had something to prove and proved nothing: every test skipped while the inventory lists elements
# for that surface. A skip costs nothing in pytest; here it fails the run (code 8).
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
    # A skip the bench declared and justified is an exclusion, not a silence: it is written in the bench, printed in
    # the report and reviewable. The gate is there for a suite that went quiet on its own (data missing, state lost).
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
  "${COMPOSE[@]}" run --rm dbinit > /dev/null 2>&1 || true
  rm -rf artifacts/results artifacts/shots artifacts/aria artifacts/state; mkdir -p artifacts/results
  runner tools/metrics.py snapshot before
  local rc=0
  runner -m pytest tests/test_harness.py -q --tb=line --suite harness --junitxml=artifacts/junit-harness.xml || { echo "the bench's own oracle fails: fix tests/lutece.py before trusting any result"; return 3; }
  pyrun -m pytest tests/test_screens.py -n "$E2E_WORKERS" -q --tb=line --suite screens --junitxml=artifacts/junit-screens.xml "$@" || rc=$?
  pyrun -m pytest tests/test_fo.py -n "$E2E_WORKERS" -q --tb=line --suite fo --junitxml=artifacts/junit-fo.xml "$@" || rc=$?
  pyrun -m pytest tests/test_scenarios.py -n "$E2E_WORKERS" -q --tb=line --suite scenarios -m "not serial" --junitxml=artifacts/junit-scenarios.xml "$@" || rc=$?
  pyrun -m pytest tests/test_scenarios.py -q --tb=line --suite scenarios -m serial --junitxml=artifacts/junit-scenarios-serial.xml "$@" || rc=$?
  pyrun -m pytest tests/test_forms.py -n "$E2E_WORKERS" -q --tb=line --suite forms --junitxml=artifacts/junit-forms.xml "$@" || rc=$?
  runner tools/metrics.py snapshot after
  invariants || rc=4
  skipped_suites || { [ "$rc" -ne 0 ] || rc=8; }
  return $rc
}

# The suites against an instance that already runs somewhere (a recette, a preprod): E2E_BASE_URL, and
# E2E_DB_HOST/PORT/USER/PASSWORD/NAME when the scenarios' sql oracles may reach its database. No build, no
# stack, no seed, and the forms fuzzer stays off: it posts every form it finds, which a shared instance
# does not want. Scenarios that create rows still create them there — run it on an instance meant for that.
cmd_external() {
  [ -n "${E2E_BASE_URL:-}" ] || { echo "external: set E2E_BASE_URL=https://host/context (and E2E_DB_* for the sql oracles)"; exit 2; }
  step "external: $E2E_BASE_URL"
  mkdir -p artifacts; rm -rf artifacts/results artifacts/shots artifacts/aria artifacts/state; mkdir -p artifacts/results
  cmd_inventory
  fingerprint || true
  local rc=0
  ext() { "${COMPOSE[@]}" run --rm -T tests-ext python "$@"; local c=$?; [ "$c" = 5 ] && return 0 || return $c; }
  ext tools/discover.py || true
  ext -m pytest tests/test_harness.py -q --tb=line --suite harness --junitxml=artifacts/junit-harness.xml || { echo "the bench's own oracle fails on this instance"; exit 3; }
  ext -m pytest tests/test_screens.py -n "$E2E_WORKERS" -q --tb=line --suite screens --junitxml=artifacts/junit-screens.xml || rc=$?
  ext -m pytest tests/test_fo.py -n "$E2E_WORKERS" -q --tb=line --suite fo --junitxml=artifacts/junit-fo.xml || rc=$?
  ext -m pytest tests/test_scenarios.py -n "$E2E_WORKERS" -q --tb=line --suite scenarios -m "not serial" --junitxml=artifacts/junit-scenarios.xml || rc=$?
  ext -m pytest tests/test_scenarios.py -q --tb=line --suite scenarios -m serial --junitxml=artifacts/junit-scenarios-serial.xml || rc=$?
  skipped_suites || { [ "$rc" -ne 0 ] || rc=8; }
  python3 tools/coverage.py | sed -n 1,3p; python3 tools/report.py; echo; cat artifacts/summary.md
  step "external done in $((SECONDS - START))s, tests rc=$rc"
  exit $rc
}

# The bench must still be usable after a run: the admin and the restricted account exist with their access codes.
# A broken invariant means a test mutated a protected account (report it, never repair silently).
invariants() {
  # Starter-kit invariant: the account the whole bench authenticates with must survive the run. Accounts the agent
  # seeds for the artefact under test (a restricted user, a workgroup...) are that bench's business: it asserts them
  # in its own scenarios and protects them from the fuzzer via scenarios/screens.yaml (key `protected`).
  local n
  n=$(docker exec "${E2E_NAME}-db-1" mariadb -ulutece -plutece lutece -N -e "SELECT COUNT(*) FROM core_admin_user WHERE id_user=1 AND access_code='${E2E_ADMIN:-admin}'" 2>/dev/null || echo 0)
  if [ "$n" != "1" ]; then
    echo "BENCH INVARIANT BROKEN: the admin account (id 1) is gone or renamed: a test altered it. Results after that point are not trustworthy." | tee artifacts/INVARIANT-BROKEN.txt
    return 1
  fi
  rm -f artifacts/INVARIANT-BROKEN.txt
}

# True when the war/image are missing OR a source file changed since the war was built: prevents testing a
# stale build (a green run on code that is not in the image).
needs_build() {
  [ -f harness/site/target/lutece.war ] || return 0
  [ -n "$(docker images -q "${E2E_NAME}-server:local")" ] || return 0
  [ -n "$(find "$E2E_SRC/src" "$E2E_SRC/webapp" -type f -newer harness/site/target/lutece.war 2>/dev/null | head -1)" ] && return 0
  # e2e.conf, the harness and gen-site.sh decide what goes INTO the war (plugins assembled, plugins enabled, liquibase
  # version); the other tools (inventory, review, report) do not, and a toolkit refresh must not rebuild for them.
  # Without them here, editing the conf changes nothing, the old war keeps running and the symptom is a screen
  # answering "this page does not exist" with no explanation.
  [ -n "$(find e2e.conf harness tools/gen-site.sh tools/liquibase-visibility.sh -type f -newer harness/site/target/lutece.war 2>/dev/null | grep -v '^harness/site/target/' | head -1)" ] && return 0
  # A Lutece artefact rebuilt in the local repository since this war was assembled — a dependency fixed locally,
  # a sibling plugin reinstalled — is not in the war yet. Without this the bench silently keeps testing the old
  # jar and the fix looks like it changed nothing. Scoped to fr/paris/lutece, so it costs milliseconds.
  [ -n "$(find "${M2_REPO:-$HOME/.m2/repository}/fr/paris/lutece" \( -name '*.jar' -o -name '*-webapp.zip' \) -newer harness/site/target/lutece.war 2>/dev/null | head -1)" ] && return 0
  return 1
}

# Fast fail before the full suite: log in and open a few of the artefact's own entry screens; if every one is an
# error page, the build is broadly broken (a missing method, a bad template) — abort with a clear message.
smoke() {
  step "smoke test"
  local base="http://localhost:${E2E_PORT}/${E2E_CONTEXT}" jar; jar=$(mktemp)
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
  # The k6 load is off by default: it costs minutes on every run and a migration is judged on behaviour, not on
  # throughput. Turn it on with E2E_PERF=1 when the question is performance (phase 4 of the skill, usually with
  # E2E_VOLUME). The rest of this step stays: it produces artifacts/perf.json, which the server-error gate reads.
  if [ "${E2E_PERF:-}" = 1 ]; then
    step "perf: k6 load on the entry screens"
    "${COMPOSE[@]}" run --rm k6 run --quiet --summary-export=/e2e/artifacts/k6-summary.json /e2e/tools/load.js || true
  fi
  step "perf: access log, DB digests"
  rm -f artifacts/jfr.txt
  if [ "${E2E_JFR:-}" = 1 ]; then
    local pid; pid=$(docker exec "$APP" sh -c 'jcmd -l | awk "/ws-server.jar/{print \$1}"')
    docker exec "$APP" sh -c "jcmd $pid JFR.dump filename=/logs/lutece-run.jfr" | tail -1
    docker exec "$APP" sh -c 'for v in hot-methods allocation-by-class gc-pauses contention-by-site; do echo "## $v"; jfr view $v /logs/lutece-run.jfr; done' > artifacts/jfr.txt 2>&1 || true
  fi
  runner tools/metrics.py perf
}

cmd_report() {
  step "report"
  # The structural baseline is taken on the first run, so the next ones have something to diff against.
  # Never from a widened run (E2E_SCOPE=all): it would freeze hundreds of core screens as this artefact's baseline.
  if [ "${E2E_SCOPE:-target}" != all ] && [ -d artifacts/aria ] && [ -z "$(ls -A baselines/aria 2>/dev/null)" ]; then
    mkdir -p baselines/aria && cp artifacts/aria/*.yaml baselines/aria/ 2>/dev/null && echo "baselines/aria seeded from this run ($(ls baselines/aria | wc -l) screens): commit it"
  fi
  python3 tools/coverage.py | sed -n 1,3p
  python3 tools/causes.py > /dev/null
  python3 tools/report.py
  python3 tools/review.py todo
  echo; cat artifacts/summary.md
}

# Before / after. The artefact in v7 on Tomcat, the suites, then the v8 site on the SAME database and the suites
# again; tools/compare.py puts the two runs face to face. The database hand-over follows what plugin-liquibase
# does with an existing base: without DATABASECHANGELOG it includes nothing, so one start in migration mode first
# creates the table and records the deployed versions — which would make it skip every v7→v8 upgrade script. The
# recorded versions are therefore reset to the v7 ones (harness/site7/target/versions.properties) before the
# normal start: that is a site already followed by plugin-liquibase in v7, the case where Liquibase does the
# upgrade itself and where a migration that changed a schema without shipping its update_db_* script fails.
APP7="${E2E_NAME}-lutece7-1"
wait_healthy() {
  local c=$1
  # Docker only declares the container unhealthy after start_period + retries × interval, about eight minutes. A
  # site whose Liquibase run stopped, or whose application never deployed, is known lost from the first line that
  # says so: stop waiting right there instead of letting the health check run out.
  local fatal='LiquibaseRunner failed|Migration failed for changeset|CWWKZ0002E|startup failed due to previous errors'
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo missing)" != starting ]; do
    [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || break
    docker logs "$c" 2>&1 | grep -qE "$fatal" && break
    sleep 1
  done
  # The whole log is kept beside the last lines: when the site does not come up, the cause (a Liquibase
  # changeset that stopped, a bean that failed to start) is hundreds of lines above the tail and would otherwise
  # be gone with the container.
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)" = healthy ] || { mkdir -p artifacts/logs; docker logs "$c" > "artifacts/logs/unhealthy-$c.log" 2>&1; echo "$c unhealthy (full log: artifacts/logs/unhealthy-$c.log)"; grep -m1 -oE "Migration failed for changeset [^ ]+" "artifacts/logs/unhealthy-$c.log" | sed 's/^/>> LIQUIBASE STOPPED: /'; grep -m1 -oE "Reason: .{0,200}" "artifacts/logs/unhealthy-$c.log" | sed 's/^/>>   /'; echo "last log lines:"; docker logs --tail 60 "$c"; return 1; }
}
# Hot deploy into the running application, the loop to iterate on a fix in seconds: the artefact's webapp/
# (templates, CSS, JS, JSP) is copied into the expanded war and served at once; when its Java or its resources
# changed since the last deploy, the jar is rebuilt offline without tests, copied into WEB-INF/lib and the
# application restarted. No war assembly, no image, no new stack. A full run stays the proof before hand-over.
cmd_deploy() {
  step "deploy: hot copy of $E2E_TARGET into the running application"
  [ "$(health)" = healthy ] || { echo "no healthy application: start one with KEEP=1 ./run.sh (or ./run.sh up)"; exit 1; }
  local war=/opt/wlp/usr/servers/defaultServer/apps/expanded/lutece.war stamp=artifacts/.deployed ref jar
  [ -d "$E2E_SRC/webapp" ] && docker cp -q "$E2E_SRC/webapp/." "$APP:$war/"
  ref=$stamp; [ -f "$ref" ] || ref=harness/site/target/lutece.war
  if [ -n "$(find "$E2E_SRC/src" "$E2E_SRC/pom.xml" -type f -newer "$ref" 2>/dev/null | grep -v '/src/test/' | head -1)" ]; then
    (cd "$E2E_SRC" && ${MVN:-mvn} -q -o install -DskipTests)
    jar=$(ls "$E2E_SRC"/target/*.jar 2>/dev/null | grep -vE -- '-(sources|javadoc|tests)\.jar$' | head -1)
    [ -n "$jar" ] || { echo "no jar under $E2E_SRC/target"; exit 1; }
    # Liberty expands lutece.war again at start: the restarted server must find the new jar, the webapp files
    # copied above and the bundles of src/java (WEB-INF/classes, not in the jar) in the war itself, a copy into the
    # expanded directory would be overwritten.
    python3 tools/patch-war.py harness/site/target/lutece.war "$jar" "$E2E_SRC/webapp" artifacts/.deploy.war "$E2E_SRC/src/java" >/dev/null || exit 1
    docker cp -q artifacts/.deploy.war "$APP:/opt/wlp/usr/servers/defaultServer/apps/lutece.war"
    rm -f artifacts/.deploy.war
    docker restart "$APP" >/dev/null
    wait_healthy "$APP" || exit 1
    echo "deploy: $(basename "$jar") replaced, application restarted"
  fi
  mkdir -p artifacts; touch "$stamp"
  echo "deploy: webapp copied; replay with ./run.sh test tests/test_scenarios.py -k <id>"
}
snapshot() {
  mkdir -p "artifacts/$1"
  local x; for x in results shots aria state summary.md report.html discovered.json perf.json coverage.json causes.json metrics-before.json metrics-after.json jfr.txt logs logs7; do
    [ -e "artifacts/$x" ] && mv "artifacts/$x" "artifacts/$1/"
  done
  for x in artifacts/junit-*.xml; do [ -e "$x" ] && mv "$x" "artifacts/$1/"; done
  mkdir -p artifacts/logs artifacts/logs7; chmod 777 artifacts/logs artifacts/logs7 2>/dev/null || true
}
cmd_compare() {
  COMPOSE+=(--profile v7)
  # A plugin assembled on the v8 leg but absent from the v7 one arrives on a database where its tables already
  # exist (the v7 core created them) with no version recorded for it: plugin-liquibase installs it as new, marks
  # its creation script as already applied and never runs its upgrades, so the schema stays at the v7 shape and
  # the site fails on a column that upgrade would have added, which reads as a migration defect.
  for dep in ${E2E_PLUGINS//,/ }; do
    IFS=':' read -r _ art _ _ <<< "$dep"
    [ -n "${art:-}" ] || continue
    case ",${E2E_V7_PLUGINS:-}," in *":$art:"*) ;; *)
      echo ">> WARNING: $art is assembled on the v8 leg but not listed in E2E_V7_PLUGINS: its v7→v8 upgrades will not run on the taken-over database." ;;
    esac
  done
  step "compare 1/6: v7 site and image, v8 image"
  bash tools/gen-site7.sh
  "${COMPOSE[@]}" build lutece7
  # Always rebuild the v8 site here, never `needs_build`: a war left from an earlier run may carry plugins the
  # current e2e.conf does not assemble, and their v7→v8 scripts would then run on the v7 database.
  cmd_build
  step "compare 2/6: v7 on a fresh database, seeded"
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf artifacts/logs artifacts/logs7 artifacts/v7 artifacts/v8 artifacts/compare.md artifacts/compare.html
  mkdir -p artifacts/logs artifacts/logs7; chmod 777 artifacts/logs artifacts/logs7 2>/dev/null || true
  # The artefact calls the same outside systems on both legs: the stand-ins and the search engines are part of
  # the comparison, not of `run.sh all` only — without them the v8 leg fails on calls the v7 leg never made.
  "${COMPOSE[@]}" up -d db mail lutece7 ${E2E_FAKES:+fakes oauth2} ${E2E_SEARCH:+solr elastic}
  wait_healthy "$APP7" || exit 1
  # --no-deps: dbinit normally waits for the v8 container to be healthy (Liquibase creates the schema there);
  # here the schema comes from the v7 Ant build and the v8 container must stay down until phase 4.
  local owned before after
  local creates
  creates=$(find "$E2E_SRC/src/sql" -path '*/plugin/create*.sql' 2>/dev/null || true)
  owned=""
  [ -n "$creates" ] && owned=$(grep -hoiE 'CREATE TABLE( IF NOT EXISTS)? +`?[a-z0-9_]+' $creates 2>/dev/null | awk '{print $NF}' | tr -d '`' | sort -u || true)
  rows_owned() { local t q=""; for t in $owned; do q="$q + (SELECT COUNT(*) FROM $t)"; done; [ -n "$q" ] && docker exec "${E2E_NAME}-db-1" mariadb -ulutece -plutece lutece -N -e "SELECT 0 $q" 2>/dev/null || echo 0; }
  before=$(rows_owned)
  E2E_VERSION=v7 "${COMPOSE[@]}" run --rm --no-deps dbinit
  after=$(rows_owned)
  # A migration is proven on data, not on an empty schema: the v7 base must carry what a site in production holds
  # (the artefact's business rows, in the v7 schema), written by the bench in harness/db/seed-<name>*.sql.
  if [ -z "$owned" ]; then
    echo ">> v7 base: the artefact creates no table of its own; the migration is proven on the data of the plugins it extends"
  elif [ "${after:-0}" -le "${before:-0}" ]; then
    echo ">> WARNING: the seed adds no row to the artefact's tables (${before:-0} rows, all from its install scripts): the"
    echo ">>          migration is proven on the schema only. Seed business data of a v7 site (harness/db/seed-<name>-data.sql)."
  else
    echo ">> v7 base: $((after - before)) business row(s) seeded in the artefact's tables, handed to the v8 site"
  fi
  # The v7 Ant build continues on SQL errors, so a plugin whose init_core targets tables the chosen v7 core has
  # already dropped installs silently half-way — and the comparison then reads "corrigé" where the bench simply
  # did not prepare v7. Say it here, with the way out.
  docker logs "$APP7" 2>&1 | grep -q "core_style.*doesn't exist" && cat <<'WARN'
>> WARNING: this plugin's v7 SQL writes core_style* and the core E2E_V7_CORE no longer has those tables.
>> The v7 portlet will render nothing and every portlet scenario will read as "corrigé" in the comparison.
>> Set E2E_V7_CORE to a core that still carries them (7.1.8) in e2e.conf, and run compare again.
WARN
  # The v8 site must take over the v7 database as a site would hand it over — seeded and used, not consumed:
  # the suites create, modify and delete rows (the forms fuzzer posts every form it finds). The seeded state is
  # kept and restored before the hand-over, so what the v8 legs sees is deterministic.
  docker exec "${E2E_NAME}-db-1" mariadb-dump -ulutece -plutece --single-transaction lutece > artifacts/v7-seeded.sql
  step "compare 3/6: suites on v7"
  cmd_inventory
  local rc7=0
  E2E_APP=lutece7 E2E_APP_PORT=8080 E2E_VERSION=v7 cmd_discover || true
  E2E_APP=lutece7 E2E_APP_PORT=8080 E2E_VERSION=v7 cmd_test || rc7=$?
  E2E_APP=lutece7 E2E_APP_PORT=8080 E2E_VERSION=v7 runner tools/metrics.py perf >/dev/null 2>&1 || true
  docker logs "$APP7" > artifacts/logs7/catalina.out 2>&1 || true
  E2E_VERSION=v7 cmd_report || true
  # An XSL portlet whose stylesheet the v7 core cannot load fails there and renders in v8, where the migration
  # ported it to HTML: the verdict "corrigé" is then about the bench's v7 site, not about the artefact. Said in
  # the run and carried into the comparison, where the reader sees the verdict.
  if grep -qE "XmlTransformerService|core_style.*doesn't exist" artifacts/logs7/catalina.out; then
    printf '%s\n' "La jambe v7 n'a pas pu rendre un portlet XSL (XmlTransformerService en erreur, ou tables core_style absentes de ce core v7). Les verdicts « corrigé » portant sur un rendu de portlet sont à lire comme « non rendu en v7 », pas comme un défaut corrigé par la migration." > artifacts/v7-render-warning.txt
    echo ">> WARNING: the v7 leg could not render an XSL portlet — see artifacts/v7-render-warning.txt"
  else
    rm -f artifacts/v7-render-warning.txt
  fi
  snapshot v7
  step "compare 4/6: the v8 site takes over the v7 database"
  "${COMPOSE[@]}" stop lutece7
  docker exec -i "${E2E_NAME}-db-1" mariadb -ulutece -plutece lutece < artifacts/v7-seeded.sql
  echo ">> database restored to its seeded v7 state (what the suites consumed is not handed over)"
  LIQUIBASE_MIGRATION_MODE=true "${COMPOSE[@]}" up -d lutece
  wait_healthy "$APP" || exit 1
  "${COMPOSE[@]}" stop lutece
  local db="${E2E_NAME}-db-1" k v
  while IFS='=' read -r k v; do
    [ -n "$k" ] || continue
    docker exec "$db" mariadb -ulutece -plutece lutece -e "UPDATE core_datastore SET entity_value='$v' WHERE entity_key='core.plugins.status.$k.version'"
    echo ">> recorded version of $k reset to $v (as a v7 site followed by plugin-liquibase would carry it)"
  done < harness/site7/target/versions.properties
  # An upgrade script whose name SqlPathInfo cannot parse is not even copied to the classpath: Liquibase will
  # never run it, on this bench or on a site. Applying it by hand here is what a site would have to do too —
  # and it is written down as a finding, because the bench must show the v8 artefact on a migrated base, not
  # the hole an unparseable file name leaves in it.
  local exploded; exploded=$(find harness/site/target -maxdepth 1 -type d -name "e2e-site-*" | head -1)
  bash tools/liquibase-visibility.sh "$exploded" > artifacts/liquibase-invisible.txt 2>&1 || true
  # `|| true`: under pipefail, a grep that finds nothing would end the script here.
  { grep -oE 'sql/([^ ]+/)?upgrade/[^ ]+\.sql' artifacts/liquibase-invisible.txt || true; } | sort | while read -r rel; do
    echo ">> HAND-APPLIED (Liquibase will never see it, unparseable name): $rel"
    docker exec -i "$db" mariadb -ulutece -plutece lutece < "$exploded/WEB-INF/$rel" || echo ">> hand-apply of $rel reported errors (see above)"
  done
  "${COMPOSE[@]}" up -d lutece ${E2E_FAKES:+fakes oauth2} ${E2E_SEARCH:+solr elastic}
  wait_healthy "$APP" || exit 1
  docker exec "$db" mariadb -ulutece -plutece lutece -N -e "SELECT CONCAT(entity_key,' = ',entity_value) FROM core_datastore WHERE entity_key LIKE 'core.plugins.status.%.version' ORDER BY 1" > artifacts/liquibase-versions-after.txt
  docker exec "$db" mariadb -ulutece -plutece lutece -N -e "SELECT CONCAT(EXECTYPE,' ',FILENAME) FROM DATABASECHANGELOG ORDER BY ORDEREXECUTED" > artifacts/liquibase-changesets.txt 2>/dev/null || true
  echo ">> Liquibase ran $(wc -l < artifacts/liquibase-changesets.txt) changeset(s) on the v7 database (artifacts/liquibase-changesets.txt)"
  "${COMPOSE[@]}" run --rm --no-deps dbinit >/dev/null 2>&1 || true
  # The seed also sets what only exists once the v8 core has migrated the base (its security headers, the CSP a
  # map needs): replayed here, it only reaches the application after the same restart a fresh bench gets.
  if [ -n "${E2E_RESTART_AFTER_SEED:-}" ]; then
    "${COMPOSE[@]}" restart lutece >/dev/null && wait_healthy "$APP" || exit 1
    echo ">> restarted on the seeded, migrated database"
  fi
  step "compare 5/6: suites on v8"
  local rc8=0
  cmd_discover || true
  cmd_test || rc8=$?
  cmd_perf || true
  cmd_report || true
  snapshot v8
  step "compare 6/6: before / after"
  local rcc=0; python3 tools/compare.py || rcc=$?
  [ "${KEEP:-}" = 1 ] || cmd_down
  step "compare done in $((SECONDS - START))s — v7 rc=$rc7, v8 rc=$rc8, compare rc=$rcc"
  # The v7 leg is informative (its reds are the plugin's v7 defects); the v8 leg and the comparison decide.
  local rc=$rcc; [ "$rc8" -ne 0 ] && rc=$rc8
  exit $rc
}

cmd_down() {
  step "down"
  docker rm -f "$RUNNER_C" >/dev/null 2>&1 || true
  rm -f artifacts/.runner-key
  "${COMPOSE[@]}" down -v --remove-orphans
}

case "${1:-all}" in
  build)     cmd_build ;;
  up)        cmd_up ;;
  inventory) cmd_inventory ;;
  discover)  cmd_discover ;;
  test)      shift; if [ $# -gt 0 ]; then runner -m pytest -q --tb=short "$@"; else cmd_test; fi ;;
  perf)      cmd_perf ;;
  report)    cmd_report ;;
  review)    python3 tools/review.py "${2:-check}" ;;
  compare)   cmd_compare ;;
  external)  cmd_external ;;
  deploy)    cmd_deploy ;;
  down)      cmd_down ;;
  logs)      shift; docker logs "${@:---tail 100}" "$APP" ;;
  py)        shift; runner "$@" ;;
  status)    "${COMPOSE[@]}" ps ;;
  sh)        docker exec -it "$APP" sh ;;
  all)
    needs_build && cmd_build
    cmd_up
    cmd_inventory
    cmd_discover
    if ! smoke; then
      cmd_report 2>/dev/null || true
      [ "${KEEP:-}" = 1 ] || cmd_down
      step "aborted on smoke test in $((SECONDS - START))s"
      exit 6
    fi
    rc=0; cmd_test || rc=$?
    cmd_perf
    cmd_report
    check_server_errors || { [ "$rc" -ne 0 ] || rc=5; }
    security_overrides || { [ "$rc" -ne 0 ] || rc=4; }
    # The bench is not delivered until a human-or-agent eye has judged the rendering of every screen family:
    # the assertions prove behaviour, not that the screens follow the design system and hold together visually.
    # A green run that never played the artefact's own actions proves nothing about them: every action of the target
    # is proven by a scenario, tested red, or excluded with a written reason, before the bench is delivered.
    if [ "${COVERAGE:-}" != skip ]; then
      python3 tools/coverage.py --gate > /dev/null || { python3 tools/coverage.py --gate | sed -n '/COVERAGE GATE/,$p'; [ "$rc" -ne 0 ] || rc=9; }
    fi
    if [ "${REVIEW:-}" != skip ]; then
      python3 tools/review.py check || { [ "$rc" -ne 0 ] || rc=7; }
    fi
    [ "${KEEP:-}" = 1 ] || cmd_down
    step "done in $((SECONDS - START))s, tests rc=$rc"
    exit $rc ;;
  *) sed -n '2,/^set -euo/{/^set -euo/!p}' "$0"; exit 2 ;;
esac
