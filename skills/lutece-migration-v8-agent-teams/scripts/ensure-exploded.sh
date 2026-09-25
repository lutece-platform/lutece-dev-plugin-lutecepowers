#!/bin/bash
# ensure-exploded.sh — assemble the project's webapp: the precondition of every template analysis.
# Usage: ensure-exploded.sh [project_root] [--force] [--offline]
#
# Prints the assembled templates directory on stdout, or a diagnosis on stderr and a non-zero exit.
# `mvn lutece:exploded-lite` unpacks the core, every declared dependency and the project itself under target,
# so the macros, their signatures, their icon font and the templates a plugin includes from its dependencies
# are the ones this project really resolves — not those of a reference clone, which may be a different version
# of the core or miss a dependency entirely. The lite goal declares no lifecycle phase, so it assembles without
# compiling: it works on a project whose Java is still mid-migration. `lutece:exploded` is the fallback, and it
# does compile (`executePhase=process-classes`).
#
# It also catches the trap that makes an analysis lie: a core artifact installed locally can shadow the
# remote one and carry a different admin theme, in which case every back-office macro signature read from
# the clone is wrong. The check below says so instead of letting the analysis run on the wrong theme.
set -uo pipefail

ROOT="."
FORCE=0
MVN_FLAGS=(-q)
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --offline) MVN_FLAGS+=(-o) ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) ROOT="$arg" ;;
    esac
done

ROOT="$(cd "$ROOT" && pwd)"

say() { echo "$*" >&2; }

# Prints the assembled templates directory: lutece:exploded writes target/lutece, lutece:exploded-lite writes
# target/<artifactId>-<version>. Only a directory carrying both macro families counts as an assembly.
locate() {
    local d
    for d in "$ROOT"/target/lutece "$ROOT"/target/*; do
        [ -d "$d/WEB-INF/templates/admin/themes/tabler" ] && [ -d "$d/WEB-INF/templates/skin/themes/macros" ] && { echo "$d/WEB-INF/templates"; return 0; }
    done
    return 1
}

# Tells whether an assembly exists and is newer than the dependency declaration.
fresh() {
    local t
    t="$(locate)" || return 1
    [ ! -f "$ROOT/pom.xml" ] || [ "$t" -nt "$ROOT/pom.xml" ] || return 1
    return 0
}

# The core, or any project that already ships both macro families, is itself the source: nothing to assemble.
if [ -d "$ROOT/webapp/WEB-INF/templates/admin/themes/tabler" ] && [ -d "$ROOT/webapp/WEB-INF/templates/skin/themes/macros" ]; then
    say "EXPLODED not needed: $ROOT ships both macro families, it is its own source"
    echo "$ROOT/webapp/WEB-INF/templates"
    exit 0
fi

if [ ! -f "$ROOT/pom.xml" ]; then
    say "EXPLODED skipped: $ROOT has no pom.xml (not a Maven project)"
    exit 3
fi

FLOOR_ARGS=("$ROOT"); [[ " ${MVN_FLAGS[*]} " == *" -o "* ]] && FLOOR_ARGS+=(--offline)
bash "$(dirname "$0")/check-v8-floor.sh" "${FLOOR_ARGS[@]}" >/dev/null
[ $? -eq 1 ] && { say "EXPLODED refused: the project is below the Lutece 8 level lutecepowers supports (see above)"; exit 6; }

if [ "$FORCE" -eq 0 ] && fresh; then
    TEMPLATES="$(locate)"
    say "EXPLODED reused: $TEMPLATES"
    echo "$TEMPLATES"
    exit 0
fi

command -v mvn >/dev/null || { say "EXPLODED failed: no mvn on PATH"; exit 4; }

LOG="$(mktemp)"
BUILT=""
for goal in exploded-lite exploded; do
    say "EXPLODED building: mvn lutece:$goal in $ROOT"
    if mvn "${MVN_FLAGS[@]}" -f "$ROOT/pom.xml" "lutece:$goal" > "$LOG" 2>&1 && locate >/dev/null; then
        BUILT="$goal"
        break
    fi
    say "  lutece:$goal did not produce an assembly, $( [ "$goal" = exploded-lite ] && echo "trying lutece:exploded (it compiles the Java)" || echo "giving up" )"
    grep -E "^\[ERROR\]" "$LOG" | head -3 >&2
done
rm -f "$LOG"

if [ -z "$BUILT" ]; then
    say "EXPLODED failed: neither goal produced an assembly"
    say "  the analysis would read macro signatures from a reference clone instead, which may be another version"
    exit 5
fi

TEMPLATES="$(locate)"
if [ ! -d "$TEMPLATES/admin/themes/tabler" ]; then
    say "EXPLODED suspect: the assembly carries no admin/themes/tabler, so the resolved lutece-core artifact is not a Tabler one."
    say "  A locally installed core can shadow the remote snapshot: check ~/.m2/repository/fr/paris/lutece/lutece-core/<version>/"
    say "  for a non-timestamped *-SNAPSHOT artifact and a maven-metadata-local.xml, and move them aside to fall back on the remote build."
    say "  Assembled admin themes: $(ls "$TEMPLATES/admin/themes" 2>/dev/null | tr '\n' ' ')"
    exit 7
fi

say "EXPLODED ready ($BUILT): $TEMPLATES ($(grep -rho '^<#macro [a-zA-Z_]*' "$TEMPLATES" 2>/dev/null | awk '{print $2}' | sort -u | wc -l) macro names reachable)"
echo "$TEMPLATES"
