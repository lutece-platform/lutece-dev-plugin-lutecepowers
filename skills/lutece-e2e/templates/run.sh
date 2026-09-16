#!/usr/bin/env bash
# One entry point for the whole bench. Without argument: everything, from the sources to the report.
#
#   ./run.sh              build (if needed) + up + seed + inventory + discover + tests + perf + report
#   ./run.sh build        install the artefact under test, assemble the war, build the app image
#   ./run.sh up           start db + app, wait for health, seed (idempotent)
#   ./run.sh inventory    static inventory (artifacts/inventory.json) + EARS requirements
#   ./run.sh discover     dynamic crawl of the running back office (artifacts/discovered.json)
#   ./run.sh test [args]  screens + scenarios + forms, in the Playwright runner container (pytest args pass through)
#   ./run.sh compare      the artefact in v7 (Tomcat) then in v8 on the same database, the suites both times, before/after report
#   ./run.sh external     the suites against an instance already deployed (E2E_BASE_URL, optional E2E_DB_*): no build, no seed, no fuzzer
#   ./run.sh perf         server timings, DB digests, JFR hot methods (artifacts/perf.json); E2E_PERF=1 adds the k6 load
#   ./run.sh report       artifacts/summary.md + report.html from the run artifacts
#   ./run.sh down         stop everything and drop the database volume
#   ./run.sh logs|status|sh   compose shortcuts
#
# Variables: E2E_VOLUME=small|large (seed size), E2E_WORKERS=n, RUNNER=local (host venv instead of the container),
# KEEP=1 (do not stop the stack after a full run). Everything else lives in e2e.conf.
# Exit codes: 1 stack, 2 usage, 3 the bench's own oracle fails, 4 bench invariant broken, 5 unexpected server
# errors, 6 smoke test, 7 visual review missing, 8 a suite with something to prove was entirely skipped;
# otherwise pytest's code (1 = a red test).
set -euo pipefail
E2E=$(cd "$(dirname "$0")" && pwd)
cd "$E2E"
# The environment wins over e2e.conf: E2E_VOLUME=large ./run.sh must not be silently overwritten.
_e2e_env=$(export -p | grep -E "^(declare -x |export )E2E_" || true)
set -a; . ./e2e.conf; set +a
eval "$_e2e_env"
export E2E_UID=$(id -u) E2E_VOLUME=${E2E_VOLUME:-small} E2E_WORKERS=${E2E_WORKERS:-4}
APP="${E2E_NAME}-lutece-1"
# E2E_FAKES=1 starts the stand-ins of the external systems (harness/fakes, SKILL.md § Fakes),
# E2E_SEARCH=1 the search engines (solr, elastic).
COMPOSE=(docker compose -f harness/docker-compose.yml ${E2E_FAKES:+--profile fakes} ${E2E_SEARCH:+--profile search})
START=$SECONDS

step() { printf '\n\033[1m== %s\033[0m (%ds)\n' "$*" "$((SECONDS - START))"; }
health() { docker inspect -f '{{.State.Health.Status}}' "$APP" 2>/dev/null || echo missing; }

# Runs a command in the test runner: the pinned Playwright container by default, the host venv with RUNNER=local.
# pytest returns 5 when a suite collects no tests (a plugin with no front office, no forms): not a failure.
pyrun() { runner "$@"; local c=$?; [ "$c" = 5 ] && return 0 || return $c; }

runner() {
  if [ "${RUNNER:-}" = local ]; then
    [ -x .venv/bin/python ] || { python3 -m venv .venv && .venv/bin/pip install -q -r tools/requirements.txt; }
    E2E_BASE="http://localhost:${E2E_PORT}/${E2E_CONTEXT}" E2E_DB_PORT=${E2E_DB_PORT:-13306} .venv/bin/python "$@"
  else
    "${COMPOSE[@]}" run --rm -T tests python "$@"
  fi
}

cmd_build() {
  step "build: install $E2E_TARGET, assemble war, build image"
  bash tools/gen-site.sh
  # Report only: a shipped SQL file Liquibase will never see (unparseable name, missing header) is a finding
  # to write down, not a reason to stop the bench — the core itself ships one.
  bash tools/liquibase-visibility.sh || true
  "${COMPOSE[@]}" build lutece
}

cmd_up() {
  # Every run starts from a clean slate: drop the database volume (schema recreated from scratch by the app's
  # Liquibase at boot) and wipe the previous run's logs, so results and the server-error analysis are per-run.
  step "up: fresh db + lutece (recreated from scratch each run)"
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
  "${COMPOSE[@]}" up -d db lutece ${E2E_FAKES:+fakes oauth2} ${E2E_SEARCH:+solr elastic}
  step "waiting for the application"
  until [ "$(health)" != starting ]; do sleep 3; done
  if [ "$(health)" != healthy ]; then
    echo "application unhealthy, last log lines:"; docker logs --tail 40 "$APP"
    # Never leave a dead stack holding the ports: the next bench on this slot would fail to bind for no reason of its own.
    [ "${KEEP:-}" = 1 ] || cmd_down
    exit 1
  fi
  step "seed ($E2E_VOLUME)"
  "${COMPOSE[@]}" run --rm dbinit
  # The application is already healthy when the seed lands, so anything it cached from the tables at boot —
  # a plugin's form list, a reference list, a type registry — holds the state of an empty database, and with
  # a 24 h time-to-live it holds it for the whole run. A bench whose target reads such a cache asks for one
  # restart here, after the rows exist, rather than chasing a race that depends on how fast dbinit ran.
  if [ -n "${E2E_RESTART_AFTER_SEED:-}" ]; then
    step "restart the application on the seeded database"
    "${COMPOSE[@]}" restart lutece >/dev/null
    until [ "$(health)" != starting ]; do sleep 3; done
    [ "$(health)" = healthy ] || { echo "application unhealthy after the post-seed restart:"; docker logs --tail 40 "$APP"; exit 1; }
  fi
}

cmd_inventory() {
  step "inventory"
  local exploded; exploded=$(find harness/site/target -maxdepth 1 -type d -name "e2e-site-*" 2>/dev/null | head -1)
  python3 tools/inventory.py "$E2E_SRC" ${exploded:+--extra "$exploded"} > artifacts/inventory.json
  python3 tools/inventory.py "$E2E_SRC" ${exploded:+--extra "$exploded"} --markdown > artifacts/inventory.md
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
for suite, needed in (("fo", fo), ("scenarios", scen), ("screens", bo)):
    f = pathlib.Path("artifacts/junit-%s.xml" % suite)
    if not f.exists() or not needed: continue
    r = ET.parse(f).getroot(); ts = r if r.tag == "testsuite" else r.find("testsuite")
    n, sk = int(ts.get("tests", 0)), int(ts.get("skipped", 0))
    if n and sk == n: bad.append("%s (%d/%d skipped)" % (suite, sk, n))
if bad:
    print("SUITE ENTIRELY SKIPPED with something to prove: " + ", ".join(bad) + " — a skip is not a proof"); sys.exit(1)
PY
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
  skipped_suites || { [ "$rc" -eq 0 ] && rc=8; }
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
  skipped_suites || { [ "$rc" -eq 0 ] && rc=8; }
  python3 tools/coverage.py | head -3; python3 tools/report.py; echo; cat artifacts/summary.md
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

# (#3) True when the war/image are missing OR a source file changed since the war was built: prevents testing a
# stale build (a green run on code that is not in the image).
needs_build() {
  [ -f harness/site/target/lutece.war ] || return 0
  [ -n "$(docker images -q "${E2E_NAME}-server:local")" ] || return 0
  [ -n "$(find "$E2E_SRC/src" "$E2E_SRC/webapp" -type f -newer harness/site/target/lutece.war 2>/dev/null | head -1)" ] && return 0
  # e2e.conf and the harness decide what goes INTO the war (plugins assembled, plugins enabled, liquibase version).
  # Without them here, editing the conf changes nothing, the old war keeps running and the symptom is a screen
  # answering "this page does not exist" with no explanation. Cost a full afternoon once.
  [ -n "$(find e2e.conf harness tools -type f -newer harness/site/target/lutece.war 2>/dev/null | grep -v '^harness/site/target/' | head -1)" ] && return 0
  # A Lutece artefact rebuilt in the local repository since this war was assembled — a dependency fixed locally,
  # a sibling plugin reinstalled — is not in the war yet. Without this the bench silently keeps testing the old
  # jar and the fix looks like it changed nothing. Scoped to fr/paris/lutece, so it costs milliseconds.
  [ -n "$(find "${M2_REPO:-$HOME/.m2/repository}/fr/paris/lutece" \( -name '*.jar' -o -name '*-webapp.zip' \) -newer harness/site/target/lutece.war 2>/dev/null | head -1)" ] && return 0
  return 1
}

# (#4) Fast fail before the full suite: log in and open a few of the artefact's own entry screens; if every one is an
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

# (#2) A run is red when the server log holds an exception outside harness/server-errors-allow.txt.
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
  step "perf: JFR dump, access log, DB digests"
  local pid; pid=$(docker exec "$APP" sh -c 'jcmd -l | awk "/ws-server.jar/{print \$1}"')
  docker exec "$APP" sh -c "jcmd $pid JFR.dump filename=/logs/lutece-run.jfr" | tail -1
  docker exec "$APP" sh -c 'for v in hot-methods allocation-by-class gc-pauses contention-by-site; do echo "## $v"; jfr view $v /logs/lutece-run.jfr; done' > artifacts/jfr.txt 2>&1 || true
  runner tools/metrics.py perf
}

cmd_report() {
  step "report"
  # The structural baseline is taken on the first run, so the next ones have something to diff against.
  # Never from a widened run (E2E_SCOPE=all): it would freeze hundreds of core screens as this artefact's baseline.
  if [ "${E2E_SCOPE:-target}" != all ] && [ -d artifacts/aria ] && [ -z "$(ls -A baselines/aria 2>/dev/null)" ]; then
    mkdir -p baselines/aria && cp artifacts/aria/*.yaml baselines/aria/ 2>/dev/null && echo "baselines/aria seeded from this run ($(ls baselines/aria | wc -l) screens): commit it"
  fi
  python3 tools/coverage.py | head -3
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
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo missing)" != starting ]; do sleep 3; done
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)" = healthy ] || { echo "$c unhealthy, last log lines:"; docker logs --tail 60 "$c"; return 1; }
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
  step "compare 1/6: v7 site and image, v8 image"
  bash tools/gen-site7.sh
  "${COMPOSE[@]}" build lutece7
  needs_build && cmd_build
  step "compare 2/6: v7 on a fresh database, seeded"
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf artifacts/logs artifacts/logs7 artifacts/v7 artifacts/v8 artifacts/compare.md artifacts/compare.html
  mkdir -p artifacts/logs artifacts/logs7; chmod 777 artifacts/logs artifacts/logs7 2>/dev/null || true
  "${COMPOSE[@]}" up -d db mail lutece7
  wait_healthy "$APP7" || exit 1
  # --no-deps: dbinit normally waits for the v8 container to be healthy (Liquibase creates the schema there);
  # here the schema comes from the v7 Ant build and the v8 container must stay down until phase 4.
  E2E_VERSION=v7 "${COMPOSE[@]}" run --rm --no-deps dbinit
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
  cmd_report || true
  docker logs "$APP7" > artifacts/logs7/catalina.out 2>&1 || true
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
  # the hole a core file name leaves in it (the 7.1.x-8.0.0 core script drops the front office: globalTheme null).
  local exploded; exploded=$(find harness/site/target -maxdepth 1 -type d -name "e2e-site-*" | head -1)
  bash tools/liquibase-visibility.sh "$exploded" > artifacts/liquibase-invisible.txt 2>&1 || true
  # `|| true`: under pipefail, a grep that finds nothing would end the script here (it did, silently).
  { grep -oE 'sql/([^ ]+/)?upgrade/[^ ]+\.sql' artifacts/liquibase-invisible.txt || true; } | sort | while read -r rel; do
    echo ">> HAND-APPLIED (Liquibase will never see it, unparseable name): $rel"
    docker exec -i "$db" mariadb -ulutece -plutece lutece < "$exploded/WEB-INF/$rel" || echo ">> hand-apply of $rel reported errors (see above)"
  done
  "${COMPOSE[@]}" up -d lutece
  wait_healthy "$APP" || exit 1
  docker exec "$db" mariadb -ulutece -plutece lutece -N -e "SELECT CONCAT(entity_key,' = ',entity_value) FROM core_datastore WHERE entity_key LIKE 'core.plugins.status.%.version' ORDER BY 1" > artifacts/liquibase-versions-after.txt
  docker exec "$db" mariadb -ulutece -plutece lutece -N -e "SELECT CONCAT(EXECTYPE,' ',FILENAME) FROM DATABASECHANGELOG ORDER BY ORDEREXECUTED" > artifacts/liquibase-changesets.txt 2>/dev/null || true
  echo ">> Liquibase ran $(wc -l < artifacts/liquibase-changesets.txt) changeset(s) on the v7 database (artifacts/liquibase-changesets.txt)"
  "${COMPOSE[@]}" run --rm --no-deps dbinit >/dev/null 2>&1 || true
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
  "${COMPOSE[@]}" down -v --remove-orphans
}

case "${1:-all}" in
  build)     cmd_build ;;
  up)        cmd_up ;;
  inventory) cmd_inventory ;;
  discover)  cmd_discover ;;
  test)      shift; cmd_test "$@" ;;
  perf)      cmd_perf ;;
  report)    cmd_report ;;
  review)    python3 tools/review.py "${2:-check}" ;;
  compare)   cmd_compare ;;
  external)  cmd_external ;;
  down)      cmd_down ;;
  logs)      shift; docker logs "${@:---tail 100}" "$APP" ;;
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
    check_server_errors || { [ "$rc" -eq 0 ] && rc=5; }
    # The bench is not delivered until a human-or-agent eye has judged the rendering of every screen family:
    # the assertions prove behaviour, not that the screens follow the design system and hold together visually.
    if [ "${REVIEW:-}" != skip ]; then
      python3 tools/review.py check || { [ "$rc" -eq 0 ] && rc=7; }
    fi
    [ "${KEEP:-}" = 1 ] || cmd_down
    step "done in $((SECONDS - START))s, tests rc=$rc"
    exit $rc ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
