#!/bin/bash
# check-v8-floor.sh — refuses a project whose lutece-core is below the Lutece 8 level lutecepowers supports.
# Usage: check-v8-floor.sh [project_root] [--offline]
#
# The floor is v8-floor.conf, next to this script: the latest published lutece-core; for a site that imports
# lutece-bom, the core the published BOM that manages the highest core manages, when lower (latest-lutece.py bom): a
# core published before its BOM does not refuse a site that follows the BOM. The core is the one Maven
# resolves (`dependency:list`, the lowest of every module), so a range, a pinned version, a BOM or a parent-managed
# version all end on the artifact the build really uses. A resolved snapshot of the latest snapshot version is dated by
# its jar against the latest build deployed. The project that is lutece-core itself is judged on its own version. The
# verdict is cached in target/ until a pom of the project or of its parent directories, the resolved jar, the
# lutece-core versions of the local Maven repository, the floor or the latest snapshot build changes.
# A project other than a site that pins lutece-core (a version, not a range) is not judged on the floor: the core is
# the site's choice (or its BOM's), the project declares the lowest core it needs as a range [X,).
# Exit 0 = at or above the floor, 1 = below (diagnosis on stderr), 2 = undecidable (no pom, Maven failure, a project
# at or above a floor the Lutece repositories could not confirm), 3 = at or above the floor on a snapshot older than
# the latest build deployed, 4 = a project other than a site that pins a Lutece 8 lutece-core (diagnosis on stderr).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/python.sh"

ROOT="."
MVN_FLAGS=(-B -q)
for arg in "$@"; do
    case "$arg" in
        --offline) MVN_FLAGS+=(-o) ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
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

# Prints a message on stderr.
say() { echo "$*" >&2; }

# Prints what a verdict depends on beside the pom: the floor, the latest snapshot build, the jar as a file (inode,
# size, modification time: Maven refreshing a snapshot writes a new file but may keep the old modification time), the
# poms of the project's modules and of its parent directories, and the lutece-core directory of the local Maven
# repository with its metadata (a new version resolved, mvn -U).
stamp() {
    python3 - "${1:-}" "$KEY" "$ROOT" "${M2_REPO:-$HOME/.m2/repository}/fr/paris/lutece/lutece-core" <<'PY'
import glob, os, pathlib, sys
jar, key, root, core = sys.argv[1:]
def st(f):
    try:
        s = os.stat(f)
        return "%d:%d:%d" % (s.st_ino, s.st_size, s.st_mtime_ns)
    except OSError:
        return "-"
root = pathlib.Path(root)
files = [str(d / "pom.xml") for d in root.parents if (d / "pom.xml").is_file()]
files += sorted(glob.glob(str(root / "*/pom.xml")) + glob.glob(str(root / "*/*/pom.xml")))
files += [core] + sorted(glob.glob(core + "/maven-metadata*.xml"))
print("|".join([st(jar) if jar else "-", key] + [st(f) for f in files]))
PY
}

# Records the verdict with the jar it was read from and its stamp, prints the diagnosis of a refusal and exits with
# its code; a pass on a floor the repositories could not confirm is undecidable and not recorded.
verdict() {
    [ "$1" = 0 ] && [ -n "${V8_FLOOR_UNVERIFIED:-}" ] && { say "V8FLOOR undecidable: ${2#V8FLOOR ok: }; the floor ($FLOOR) is not confirmed: $V8_FLOOR_UNVERIFIED."; exit 2; }
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

SELF="$(python3 - "$ROOT/pom.xml" <<'PY'
import re, sys
own = re.sub(r"<parent>.*?</parent>", "", open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S)
a = re.search(r"<artifactId>\s*([^<\s]+)", own)
v = re.search(r"<version>\s*([^<\s]+)", own)
p = re.search(r"<packaging>\s*([^<\s]+)", own)
bom = re.search(r"<dependencyManagement>.*<artifactId>\s*lutece-bom\s*</artifactId>.*</dependencyManagement>", own, re.S)
deps = re.sub(r"<!--.*?-->", "", own, flags=re.S)
core = next((re.search(r"<version>\s*([^<\s]+)", d) for d in re.findall(r"<dependency>(.*?)</dependency>", deps, re.S)
             if re.search(r"<artifactId>\s*lutece-core\s*</artifactId>", d)), None)
print(" ".join([m.group(1) if m else "-" for m in (a, v, p)] + ["bom" if bom else "-", core.group(1) if core else "-"]))
PY
)"
read -r SELF_ID SELF_V SELF_PACKAGING SELF_BOM SELF_CORE <<< "$SELF"

CORE_FLOOR=$V8_FLOOR_CORE
FLOOR="lutece-core $CORE_FLOOR or later, the latest published"
if [ "$SELF_PACKAGING" = "lutece-site" ]; then
    if [ -z "${V8_FLOOR_BOM+set}" ] || [ -z "${V8_FLOOR_BOM_CORE+set}" ]; then
        _bom_out=$(python3 "$HERE/latest-lutece.py" bom fr.paris.lutece.starters:lutece-bom 2>/dev/null) \
            || [ $? != 3 ] || V8_FLOOR_UNVERIFIED="the Lutece repositories cannot be read, the floor is the local Maven repository's"
        IFS=: read -r _ _ _bom _bom_core <<< "$_bom_out"
        V8_FLOOR_BOM=${V8_FLOOR_BOM-$_bom}
        V8_FLOOR_BOM_CORE=${V8_FLOOR_BOM_CORE-$_bom_core}
    fi
    if [ "$SELF_BOM" = bom ] && [ -n "$V8_FLOOR_BOM_CORE" ] && [ "$(vcmp "$V8_FLOOR_BOM_CORE" "$CORE_FLOOR")" -lt 0 ]; then
        CORE_FLOOR=$V8_FLOOR_BOM_CORE
        FLOOR="lutece-core $CORE_FLOOR or later (the core of lutece-bom $V8_FLOOR_BOM, the published BOM that manages the highest core)"
    fi
fi
KEY="$FLOOR; snapshot $V8_SNAPSHOT_CORE $V8_SNAPSHOT_CORE_BUILD"

if [ -f "$CACHE" ] && [ "$CACHE" -nt "$ROOT/pom.xml" ]; then
    rc=$(cut -f1 "$CACHE"); jar=$(cut -f2 "$CACHE"); kept=$(cut -f3 "$CACHE"); msg=$(cut -f4- "$CACHE")
    if [ "$kept" = "$(stamp "$jar")" ]; then
        [ "$rc" = 0 ] || { say "$msg"; exit "$rc"; }
        [ -n "${V8_FLOOR_UNVERIFIED:-}" ] || exit 0
        verdict 0 "$msg" "$jar"
    fi
fi

if [ "$SELF_ID" = "lutece-core" ]; then
    [ "$(vcmp "$SELF_V" "$CORE_FLOOR")" -ge 0 ] || verdict 1 "V8FLOOR refused: this is lutece-core $SELF_V; lutecepowers supports $FLOOR."
    verdict 0 "V8FLOOR ok: lutece-core $SELF_V"
fi

if [[ "$SELF_PACKAGING" != lutece-site && "$SELF_CORE" != - && "$SELF_CORE" != *[,\$]* ]]; then
    PINNED=${SELF_CORE#[}; PINNED=${PINNED%]}
    [ "$(vcmp "$PINNED" "$V8_DECLARED_CORE")" -ge 0 ] \
        || verdict 1 "V8FLOOR refused: the project pins lutece-core $SELF_CORE, below Lutece 8. Declare the lowest Lutece 8 core it needs as a range [${V8_DECLARED_CORE},); raise the parent to $V8_FLOOR_PARENT."
    verdict 4 "V8FLOOR pinned: the project pins lutece-core $SELF_CORE; the core is the site's choice (or its BOM's). Declare the lowest core it needs as a range, [$PINNED,) when it uses the API of $PINNED, else [${V8_DECLARED_CORE},)."
fi

LIST=target/.v8-floor-core
find "$ROOT" -path "*/$LIST" -delete 2>/dev/null
if ! mvn "${MVN_FLAGS[@]}" -f "$ROOT/pom.xml" dependency:list -DincludeGroupIds=fr.paris.lutece -DincludeArtifactIds=lutece-core \
        -DoutputAbsoluteArtifactFilename=true -DoutputFile="$LIST" >/dev/null 2>&1; then
    say "V8FLOOR undecidable: mvn dependency:list fails in $ROOT"
    exit 2
fi
LOWEST="$(python3 - "$HERE/latest-lutece.py" "$ROOT" "$LIST" <<'PY'
import pathlib, re, runpy, sys
vkey = runpy.run_path(sys.argv[1])["vkey"]
lines = [l for f in pathlib.Path(sys.argv[2]).glob("**/" + sys.argv[3])
         for l in f.read_text(encoding="utf-8", errors="replace").splitlines()]
found = []
for line in lines:
    m = re.match(r"\s*fr\.paris\.lutece:lutece-core:[^:]+:([^:]+):[^:]+:(.*?)(?: -- .*)?\s*$", line)
    if m:
        found.append((m.group(1), m.group(2) if m.group(2).endswith(".jar") else ""))
if found:
    print("%s\t%s" % min(found, key=lambda f: vkey(f[0])))
PY
)"
[ -n "$LOWEST" ] || verdict 0 "V8FLOOR ok: no lutece-core dependency"
IFS=$'\t' read -r CORE_V JAR <<< "$LOWEST"

if [ "$(vcmp "$CORE_V" "$CORE_FLOOR")" -lt 0 ]; then
    if [ "$SELF_PACKAGING" = "lutece-site" ]; then
        RAISE="Import lutece-bom ${V8_FLOOR_BOM:-<the published one that manages the highest lutece-core>}, or pin lutece-core at $V8_FLOOR_CORE or later; raise the parent to $V8_FLOOR_SITE_PARENT."
    else
        RAISE="Declare lutece-core as an open range, [${V8_DECLARED_CORE},) or the lowest core it needs, and refresh with mvn -U; raise the parent to $V8_FLOOR_PARENT."
    fi
    verdict 1 "V8FLOOR refused: the project resolves lutece-core $CORE_V; lutecepowers supports $FLOOR. $RAISE" "$JAR"
fi

if [ "$CORE_V" = "$V8_SNAPSHOT_CORE" ] && [ -n "$V8_SNAPSHOT_CORE_BUILD" ] && [ -f "$JAR" ]; then
    BUILT="$(built_on "$JAR")"
    [[ "$BUILT" < "$V8_SNAPSHOT_CORE_BUILD" ]] \
        && verdict 3 "V8FLOOR stale: lutece-core $CORE_V resolves to a build of $BUILT ($JAR), older than the one deployed on $V8_SNAPSHOT_CORE_BUILD. Refresh it with mvn -U, or move aside a locally installed core." "$JAR"
    verdict 0 "V8FLOOR ok: lutece-core $CORE_V built on $BUILT" "$JAR"
fi
verdict 0 "V8FLOOR ok: lutece-core $CORE_V" "$JAR"
