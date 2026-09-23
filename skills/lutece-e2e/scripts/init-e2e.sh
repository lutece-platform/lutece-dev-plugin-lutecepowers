#!/usr/bin/env bash
# Materialises an e2e/ bench in a Lutece project (core, plugin or module) from this skill.
#
#   init-e2e.sh <project-dir> [--target core|plugin] [--name <compose-name>] [--port 18080] [--db-port 13306]
#
# Ports: without --port the bench takes the first free slot, every port shifted by 100 per slot (18080/13306/18025,
# then 18180/13406/18125...). Benches are left running with KEEP=1, so a fixed default would make the second one
# fail to bind, which is how a campaign migrating one artefact after another hits it.
#
# Copies the harness, tools, tests and run.sh, writes e2e.conf and a scenario skeleton. Idempotent on the
# generic files (they are overwritten from the skill), never touches an existing e2e.conf, scenarios/ or baselines/.
set -euo pipefail
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
DIR=""; TARGET=""; NAME=""; PORT=""; DBPORT=""
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --port) PORT="$2"; shift 2;;
  --db-port) DBPORT="$2"; shift 2;;
  -*) echo "unknown option $1" >&2; exit 2;;
  *) DIR="$1"; shift;;
esac; done
[ -n "$DIR" ] && [ -f "$DIR/pom.xml" ] || { echo "usage: init-e2e.sh <project-dir with pom.xml> [--target core|plugin]" >&2; exit 2; }
DIR=$(cd "$DIR" && pwd)
PACKAGING=$(grep -oE "<packaging>[^<]+" "$DIR/pom.xml" | head -1 | sed 's/<packaging>//')
if [ -z "$TARGET" ]; then
  case "$PACKAGING" in
    lutece-core) TARGET=core;;
    lutece-plugin|lutece-module|lutece-library) TARGET=plugin;;
    lutece-site) echo "a site builds with its own pom: set E2E_TARGET=site and point harness/site at it (see SKILL.md)" >&2; TARGET=site;;
    *) echo "cannot infer target from packaging '$PACKAGING', pass --target" >&2; exit 2;;
  esac
fi
# -- ports: first free slot, or the offset implied by --port ------------------------------------------
port_free( ) { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
# The slot decides every host port of the bench. A free port is not enough to choose it: a bench that is not
# running holds no port, so every bench initialised on a quiet machine would take slot 0 and no two of them
# could ever run at the same time. The slots taken are therefore recorded, one line per bench, and a bench keeps
# the slot it was given.
SLOTS="${E2E_SLOTS_FILE:-$HOME/.lutece-e2e-slots}"
touch "$SLOTS" 2>/dev/null || SLOTS=/dev/null
KEY=$(cd "$DIR" && pwd)
SLOT=$(awk -v k="$KEY" '$1 == k {print $2}' "$SLOTS" | tail -1)
if [ -n "$PORT" ]; then
    SLOT=$(( (PORT - 18080) / 100 ))
    [ "$SLOT" -ge 0 ] || SLOT=0
elif [ -z "$SLOT" ]; then
    SLOT=0
    while [ "$SLOT" -lt 40 ]; do
        S=$(( SLOT * 100 ))
        if ! awk -v s="$SLOT" '$2 == s {found=1} END {exit !found}' "$SLOTS" \
           && port_free $(( 18080 + S )) && port_free $(( 13306 + S )) && port_free $(( 18025 + S )); then break; fi
        SLOT=$(( SLOT + 1 ))
    done
fi
if [ "$SLOTS" != /dev/null ]; then
    grep -v "^$KEY " "$SLOTS" > "$SLOTS.tmp" 2>/dev/null || true
    printf '%s %s\n' "$KEY" "$SLOT" >> "$SLOTS.tmp"; mv "$SLOTS.tmp" "$SLOTS"
fi
S=$(( SLOT * 100 ))
PORT=${PORT:-$(( 18080 + S ))}
DBPORT=${DBPORT:-$(( 13306 + S ))}
# Every base ends on a different pair of digits: two ports of different families are then never equal, whatever
# the slots (18080 + 1000 and 19080 + 0 were the same port before oauth2 moved to 19085).
MAILPORT=$(( 18025 + S )); FAKESPORT=$(( 19030 + S )); OAUTH2PORT=$(( 19085 + S )); PORT7=$(( 18081 + S ))
SOLRPORT=$(( 18983 + S )); ESPORT=$(( 19200 + S ))

ARTIFACT=$(grep -oE "<artifactId>[^<]+" "$DIR/pom.xml" | sed -n 2p | sed 's/<artifactId>//')
[ -n "$ARTIFACT" ] || ARTIFACT=$(basename "$DIR")
NAME=${NAME:-"lutece-${ARTIFACT#plugin-}-e2e"}
E2E="$DIR/e2e"
mkdir -p "$E2E"/{harness,tools,tests,scenarios,baselines/aria,artifacts}

# The harness is refreshed from the skill, except what a bench owns and fills in itself: the application
# environment (app.env), its seeds, the organisation's stand-ins and the v7 webapp overlay.
rsync -a --exclude app.env --exclude 'db/seed*.sql' --exclude 'db/post-init.sql' --exclude 'fakes/extra' \
      --exclude 'v7-overlay' "$SKILL/harness/" "$E2E/harness/"
[ -f "$E2E/harness/app.env" ] || cp "$SKILL/harness/app.env" "$E2E/harness/app.env"
[ -f "$E2E/harness/db/post-init.sql" ] || cp "$SKILL/harness/db/post-init.sql" "$E2E/harness/db/post-init.sql"
cp -a "$SKILL/tools/." "$E2E/tools/"
cp -a "$SKILL/tests/." "$E2E/tests/"
cp "$SKILL/templates/run.sh" "$E2E/run.sh"; chmod +x "$E2E/run.sh" "$E2E/tools/gen-site.sh"
cp "$SKILL/reference/DESIGN.md" "$E2E/DESIGN.md"
echo "$SKILL" > "$E2E/.toolkit"
[ -f "$E2E/README.md" ] || sed "s/@@NAME@@/$ARTIFACT/g" "$SKILL/templates/README.md.tpl" > "$E2E/README.md"
# The bench is a local tool, never committed with the plugin: ignore the whole folder at the project root
# (idempotent; a .gitignore that does not end with a newline would glue the entry to its last line).
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  [ -s "$DIR/.gitignore" ] && [ -n "$(tail -c1 "$DIR/.gitignore")" ] && echo >> "$DIR/.gitignore"
  grep -qxF "e2e/" "$DIR/.gitignore" 2>/dev/null || echo "e2e/" >> "$DIR/.gitignore"
fi
# Inside the bench too, for a checkout where the root rule is missing.
[ -f "$E2E/.gitignore" ] || printf '.venv/\n__pycache__/\n*.pyc\nartifacts/\nharness/site/target/\nharness/site/pom.xml\nharness/site/webapp/WEB-INF/plugins/plugins.dat\n' > "$E2E/.gitignore"
[ -f "$E2E/e2e.conf" ] && CONF_KEPT=1
if [ ! -f "$E2E/e2e.conf" ]; then
  sed -e "s/@@TARGET@@/$TARGET/" -e "s/@@NAME@@/$NAME/" -e "s/@@PORT@@/$PORT/" -e "s/@@DBPORT@@/$DBPORT/" \
      -e "s/@@MAILPORT@@/$MAILPORT/" -e "s/@@FAKESPORT@@/$FAKESPORT/" -e "s/@@OAUTH2PORT@@/$OAUTH2PORT/" \
      -e "s/@@PORT7@@/$PORT7/" \
      -e "s/@@SOLRPORT@@/$SOLRPORT/" -e "s/@@ESPORT@@/$ESPORT/" \
      "$SKILL/templates/e2e.conf.tpl" > "$E2E/e2e.conf"
fi
if [ -z "$(ls -A "$E2E/scenarios" 2>/dev/null)" ]; then
  # Copied as .example on purpose: the runner collects scenarios/*.yaml, and an untouched example is a red test
  # that says nothing. Write the bench's own file beside it, then delete this one.
  cp "$SKILL/templates/scenarios-example.yaml" "$E2E/scenarios/${ARTIFACT#plugin-}.yaml.example"
  cp "$SKILL/templates/scenarios-negative-example.yaml" "$E2E/scenarios/${ARTIFACT#plugin-}-negative.yaml.example"
  cp "$SKILL/templates/screens.yaml" "$E2E/scenarios/screens.yaml"
  printf '# Inventory elements the bench cannot reach, each with a written reason (read by tools/coverage.py).\nexclusions: []\n' > "$E2E/scenarios/coverage-exclusions.yaml"
fi
mkdir -p "$E2E/fixtures"; cp -n "$SKILL/templates/fixtures/"* "$E2E/fixtures/" 2>/dev/null || true
if [ -n "${CONF_KEPT:-}" ]; then
  echo "e2e bench refreshed in $E2E (e2e.conf kept: $(grep -E '^E2E_(NAME|PORT|DB_PORT)=' "$E2E/e2e.conf" | tr '\n' ' '))"
else
  echo "e2e bench initialised in $E2E (target=$TARGET, name=$NAME, slot=$SLOT, app=$PORT, db=$DBPORT, mail=$MAILPORT)"
fi
echo "next: edit e2e/e2e.conf (plugins to assemble, plugins to enable), then ./e2e/run.sh"
