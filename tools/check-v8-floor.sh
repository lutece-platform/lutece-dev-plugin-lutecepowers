#!/bin/bash
# check-v8-floor.sh — refuses a project whose lutece-core is below the Lutece 8 level lutecepowers supports.
# Usage: check-v8-floor.sh [project_root] [--offline]
#
# The floor is v8-floor.conf, next to this script: the latest published lutece-core. The core is the one Maven
# resolves (`dependency:list`), so a range, a pinned version, a BOM or a parent-managed version all end on the
# artifact the build really uses. A resolved snapshot of the latest snapshot version is dated by its jar against the
# latest build deployed. The project that is lutece-core itself is judged on its own version. The verdict is cached in
# target/ until pom.xml, the resolved jar, the floor or the latest snapshot build changes.
# Exit 0 = at or above the floor, 1 = below (diagnosis on stderr), 2 = undecidable (no pom, Maven failure),
# 3 = at or above the floor on a snapshot older than the latest build deployed (diagnosis on stderr).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/python.sh"

ROOT="."
MVN_FLAGS=(-B -q)
for arg in "$@"; do
    case "$arg" in
        --offline) MVN_FLAGS+=(-o) ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) ROOT="$arg" ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/v8-floor.conf"
if [ -z "${V8_SNAPSHOT_CORE+set}" ] || [ -z "${V8_SNAPSHOT_CORE_BUILD+set}" ]; then
    IFS=: read -r _ _ _snap _build <<< "$(python3 "$HERE/latest-lutece.py" snapshot fr.paris.lutece:lutece-core 2>/dev/null)"
    V8_SNAPSHOT_CORE=${V8_SNAPSHOT_CORE-$_snap}
    V8_SNAPSHOT_CORE_BUILD=${V8_SNAPSHOT_CORE_BUILD-${_build:+${_build:0:4}-${_build:4:2}-${_build:6:2}}}
fi
CACHE="$ROOT/target/.v8-floor"
FLOOR="lutece-core $V8_FLOOR_CORE or later"
KEY="$FLOOR; snapshot $V8_SNAPSHOT_CORE $V8_SNAPSHOT_CORE_BUILD"

# Prints a message on stderr.
say() { echo "$*" >&2; }

# Prints what a verdict depends on beside the pom: the floor, the latest snapshot build and the jar as a file (inode,
# size, modification time). Maven refreshing a snapshot writes a new file but may keep the old modification time, so
# a date alone is not enough.
stamp() {
    python3 - "${1:-}" "$KEY" <<'PY'
import os, sys
try:
    s = os.stat(sys.argv[1]) if sys.argv[1] else None
except OSError:
    s = None
print("%s|%s" % ("%d:%d:%d" % (s.st_ino, s.st_size, s.st_mtime_ns) if s else "-", sys.argv[2]))
PY
}

# Records the verdict with the jar it was read from and its stamp, prints the diagnosis of a refusal and exits with
# its code.
verdict() {
    mkdir -p "$ROOT/target"
    printf '%s\t%s\t%s\t%s\n' "$1" "${3:-}" "$(stamp "${3:-}")" "$2" > "$CACHE"
    [ "$1" = 0 ] || say "$2"
    exit "$1"
}

# Compares two Maven versions in the order of latest-lutece.py and prints -1, 0 or 1: a qualified version (-beta-NN,
# -SNAPSHOT) sorts before its release.
vcmp() {
    python3 - "$HERE/latest-lutece.py" "$1" "$2" <<'PY'
import runpy, sys
vkey = runpy.run_path(sys.argv[1])["vkey"]
a, b = vkey(sys.argv[2]), vkey(sys.argv[3])
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
    rc=$(cut -f1 "$CACHE"); jar=$(cut -f2 "$CACHE"); kept=$(cut -f3 "$CACHE"); msg=$(cut -f4- "$CACHE")
    if [ "$kept" = "$(stamp "$jar")" ]; then
        [ "$rc" = 0 ] || say "$msg"
        exit "$rc"
    fi
fi

SELF="$(python3 - "$ROOT/pom.xml" <<'PY'
import re, sys
own = re.sub(r"<parent>.*?</parent>", "", open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S)
a = re.search(r"<artifactId>\s*([^<\s]+)", own)
v = re.search(r"<version>\s*([^<\s]+)", own)
p = re.search(r"<packaging>\s*([^<\s]+)", own)
print(" ".join(m.group(1) if m else "-" for m in (a, v, p)))
PY
)"
read -r SELF_ID SELF_V SELF_PACKAGING <<< "$SELF"

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
JAR="$(echo "$LINE" | sed -E 's/^ *([^:]*:){5}//; s/ -- .*$//; s/ *$//')"
case "$JAR" in *.jar) ;; *) JAR="" ;; esac

if [ "$(vcmp "$CORE_V" "$V8_FLOOR_CORE")" -lt 0 ]; then
    if [ "$SELF_PACKAGING" = "lutece-site" ]; then
        BOM=$(python3 "$HERE/latest-lutece.py" bom fr.paris.lutece.starters:lutece-bom 2>/dev/null | cut -d: -f3)
        RAISE="Import lutece-bom ${BOM:-<the published one that manages the highest lutece-core>}, or pin lutece-core at $V8_FLOOR_CORE or later; raise the parent to $V8_FLOOR_SITE_PARENT."
    else
        RAISE="Pin lutece-core at $V8_FLOOR_CORE or later, or keep the open range [${V8_DECLARED_CORE},) and refresh with mvn -U; raise the parent to $V8_FLOOR_PARENT."
    fi
    verdict 1 "V8FLOOR refused: the project resolves lutece-core $CORE_V; lutecepowers supports $FLOOR, the latest published. $RAISE" "$JAR"
fi

if [ "$CORE_V" = "$V8_SNAPSHOT_CORE" ] && [ -n "$V8_SNAPSHOT_CORE_BUILD" ] && [ -f "$JAR" ]; then
    BUILT="$(built_on "$JAR")"
    [[ "$BUILT" < "$V8_SNAPSHOT_CORE_BUILD" ]] \
        && verdict 3 "V8FLOOR stale: lutece-core $CORE_V resolves to a build of $BUILT ($JAR), older than the one deployed on $V8_SNAPSHOT_CORE_BUILD. Refresh it with mvn -U, or move aside a locally installed core." "$JAR"
    verdict 0 "V8FLOOR ok: lutece-core $CORE_V built on $BUILT" "$JAR"
fi
verdict 0 "V8FLOOR ok: lutece-core $CORE_V" "$JAR"
