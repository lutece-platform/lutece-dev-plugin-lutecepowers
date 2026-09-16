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
SLOT=0
if [ -n "$PORT" ]; then
    SLOT=$(( (PORT - 18080) / 100 ))
    [ "$SLOT" -ge 0 ] || SLOT=0
else
    while [ "$SLOT" -lt 40 ]; do
        S=$(( SLOT * 100 ))
        if port_free $(( 18080 + S )) && port_free $(( 13306 + S )) && port_free $(( 18025 + S )); then break; fi
        SLOT=$(( SLOT + 1 ))
    done
fi
S=$(( SLOT * 100 ))
PORT=${PORT:-$(( 18080 + S ))}
DBPORT=${DBPORT:-$(( 13306 + S ))}
MAILPORT=$(( 18025 + S )); FAKESPORT=$(( 19030 + S )); OAUTH2PORT=$(( 19080 + S ))
SOLRPORT=$(( 18983 + S )); ESPORT=$(( 19200 + S ))

ARTIFACT=$(grep -oE "<artifactId>[^<]+" "$DIR/pom.xml" | sed -n 2p | sed 's/<artifactId>//')
[ -n "$ARTIFACT" ] || ARTIFACT=$(basename "$DIR")
NAME=${NAME:-"lutece-${ARTIFACT#plugin-}-e2e"}
E2E="$DIR/e2e"
mkdir -p "$E2E"/{harness,tools,tests,scenarios,baselines/aria,artifacts}

# The harness is refreshed from the skill, except what a bench owns and fills in itself: the application
# environment (app.env), its seeds and the organisation's stand-ins.
rsync -a --exclude app.env --exclude 'db/seed*.sql' --exclude 'db/post-init.sql' --exclude 'fakes/extra' "$SKILL/harness/" "$E2E/harness/"
[ -f "$E2E/harness/app.env" ] || cp "$SKILL/harness/app.env" "$E2E/harness/app.env"
[ -f "$E2E/harness/db/post-init.sql" ] || cp "$SKILL/harness/db/post-init.sql" "$E2E/harness/db/post-init.sql"
cp -a "$SKILL/tools/." "$E2E/tools/"
cp -a "$SKILL/tests/." "$E2E/tests/"
cp "$SKILL/templates/run.sh" "$E2E/run.sh"; chmod +x "$E2E/run.sh" "$E2E/tools/gen-site.sh"
cp "$SKILL/reference/DESIGN.md" "$E2E/DESIGN.md"
[ -f "$E2E/README.md" ] || sed "s/@@NAME@@/$ARTIFACT/g" "$SKILL/templates/README.md.tpl" > "$E2E/README.md"
# The bench is a local tool, never committed with the plugin: ignore the whole folder at the project root
# (idempotent; a .gitignore that does not end with a newline would glue the entry to its last line).
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  [ -s "$DIR/.gitignore" ] && [ -n "$(tail -c1 "$DIR/.gitignore")" ] && echo >> "$DIR/.gitignore"
  grep -qxF "e2e/" "$DIR/.gitignore" 2>/dev/null || echo "e2e/" >> "$DIR/.gitignore"
fi
# Inside the bench too, for a checkout where the root rule is missing.
[ -f "$E2E/.gitignore" ] || printf '.venv/\n__pycache__/\n*.pyc\nartifacts/\nharness/site/target/\nharness/site/pom.xml\nharness/site/webapp/WEB-INF/plugins/plugins.dat\n' > "$E2E/.gitignore"
if [ ! -f "$E2E/e2e.conf" ]; then
  sed -e "s/@@TARGET@@/$TARGET/" -e "s/@@NAME@@/$NAME/" -e "s/@@PORT@@/$PORT/" -e "s/@@DBPORT@@/$DBPORT/" \
      -e "s/@@MAILPORT@@/$MAILPORT/" -e "s/@@FAKESPORT@@/$FAKESPORT/" -e "s/@@OAUTH2PORT@@/$OAUTH2PORT/" \
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
echo "e2e bench initialised in $E2E (target=$TARGET, name=$NAME, slot=$SLOT, app=$PORT, db=$DBPORT, mail=$MAILPORT)"
echo "next: edit e2e/e2e.conf (plugins to assemble, plugins to enable), then ./e2e/run.sh"
