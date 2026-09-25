#!/bin/bash
# check-v8-floor.sh — refuses a project whose lutece-core is below the Lutece 8 level lutecepowers supports.
# Usage: check-v8-floor.sh [project_root] [--offline]
#
# The floor is v8-floor.conf, next to this script. The core is the one Maven resolves (`dependency:list`), so a
# range, a property or a parent-managed version all end on the artifact the build really uses; a snapshot is dated
# by its jar. The project that is lutece-core itself is judged on its own version. The verdict is cached in target/
# until pom.xml or the resolved jar changes.
# Exit 0 = at or above the floor, 1 = below (diagnosis on stderr), 2 = undecidable (no pom, Maven failure).
set -uo pipefail

ROOT="."
MVN_FLAGS=(-B -q)
for arg in "$@"; do
    case "$arg" in
        --offline) MVN_FLAGS+=(-o) ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) ROOT="$arg" ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/v8-floor.conf"
CACHE="$ROOT/target/.v8-floor"
FLOOR="lutece-core $V8_FLOOR_CORE built on $V8_FLOOR_CORE_BUILD or later"

# Prints a message on stderr.
say() { echo "$*" >&2; }

# Records the verdict with the jar it was read from, prints the diagnosis of a refusal and exits with its code.
verdict() {
    mkdir -p "$ROOT/target"
    printf '%s\t%s\t%s\n' "$1" "${3:-}" "$2" > "$CACHE"
    [ "$1" = 0 ] || say "$2"
    exit "$1"
}

# Compares two Maven versions and prints -1, 0 or 1; a qualified version (-SNAPSHOT, -beta-NN) sorts before its release.
vcmp() {
    python3 - "$1" "$2" <<'PY'
import re, sys
def key(v):
    base, _, qual = v.partition("-")
    nums = ([int(x) for x in re.findall(r"\d+", base)] + [0, 0, 0])[:3]
    return nums, (1 if not qual else 0), qual.lower()
a, b = key(sys.argv[1]), key(sys.argv[2])
print((a > b) - (a < b))
PY
}

# Prints the date of the most recent entry of a jar, which is the date it was built.
built_on() {
    python3 - "$1" <<'PY'
import sys, zipfile
print("%04d-%02d-%02d" % max(i.date_time for i in zipfile.ZipFile(sys.argv[1]).infolist())[:3])
PY
}

[ -f "$ROOT/pom.xml" ] || { say "V8FLOOR undecidable: $ROOT has no pom.xml"; exit 2; }

if [ -f "$CACHE" ] && [ "$CACHE" -nt "$ROOT/pom.xml" ]; then
    IFS=$'\t' read -r rc jar msg < "$CACHE"
    if [ -z "$jar" ] || { [ -f "$jar" ] && [ "$CACHE" -nt "$jar" ]; }; then
        [ "$rc" = 0 ] || say "$msg"
        exit "$rc"
    fi
fi

SELF="$(python3 - "$ROOT/pom.xml" <<'PY'
import re, sys
own = re.sub(r"<parent>.*?</parent>", "", open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S)
a = re.search(r"<artifactId>\s*([^<\s]+)", own)
v = re.search(r"<version>\s*([^<\s]+)", own)
print((a.group(1) if a else "-") + " " + (v.group(1) if v else "-"))
PY
)"
read -r SELF_ID SELF_V <<< "$SELF"

if [ "$SELF_ID" = "lutece-core" ]; then
    [ "$(vcmp "$SELF_V" "$V8_FLOOR_CORE")" -ge 0 ] || verdict 1 "V8FLOOR refused: this is lutece-core $SELF_V; lutecepowers supports $FLOOR."
    verdict 0 "V8FLOOR ok: lutece-core $SELF_V"
fi

OUT="$(mktemp)"
if ! mvn "${MVN_FLAGS[@]}" -f "$ROOT/pom.xml" dependency:list -DincludeGroupIds=fr.paris.lutece -DincludeArtifactIds=lutece-core \
        -DoutputAbsoluteArtifactFilename=true -DoutputFile="$OUT" >/dev/null 2>&1; then
    rm -f "$OUT"
    say "V8FLOOR undecidable: mvn dependency:list fails in $ROOT"
    exit 2
fi
LINE="$(grep -m1 'fr.paris.lutece:lutece-core:' "$OUT")"
rm -f "$OUT"
[ -n "$LINE" ] || verdict 0 "V8FLOOR ok: no lutece-core dependency"

CORE_V="$(echo "$LINE" | awk -F: '{print $4}')"
JAR="$(echo "$LINE" | grep -oE '/[^ ]+\.jar' | head -1)"

[ "$(vcmp "$CORE_V" "$V8_FLOOR_CORE")" -ge 0 ] \
    || verdict 1 "V8FLOOR refused: the project resolves lutece-core $CORE_V; lutecepowers supports $FLOOR. Keep lutece-core on the open range [${V8_DECLARED_CORE},) so it resolves the latest core, refresh with mvn -U, and raise the parent to $V8_FLOOR_PARENT." "$JAR"

if [ "$CORE_V" = "$V8_FLOOR_CORE" ] && [ -f "$JAR" ]; then
    BUILT="$(built_on "$JAR")"
    [[ "$BUILT" < "$V8_FLOOR_CORE_BUILD" ]] \
        && verdict 1 "V8FLOOR refused: lutece-core $CORE_V resolves to a build of $BUILT ($JAR); lutecepowers supports $FLOOR. Refresh it with mvn -U, or move aside a locally installed core." "$JAR"
    verdict 0 "V8FLOOR ok: lutece-core $CORE_V built on $BUILT" "$JAR"
fi
verdict 0 "V8FLOOR ok: lutece-core $CORE_V" "$JAR"
