#!/usr/bin/env bash
# site-assemble.sh — assembles a Lutece site the way its war is built, into a directory site_check.py can read.
#
#   site-assemble.sh <site_dir> --out DIR [--ref GIT_REF] [--profile ENV] [--repo M2_DIR] [--settings FILE] [--pin G:A:V]... [--update]
#
# Always from a clean target (a stale target/<finalName> makes lutece:site-assembly skip the core and the plugins),
# from a disposable git worktree when --ref is given (the working tree is never touched), with the Maven profile ENV
# of a v7 site (-P<env> copies src/conf/<env>), into a local repository given with --repo so nothing lands in ~/.m2.
# The developer's ~/lutece/conf/<artifactId> is left out: the environments build without it.
# --pin (with --ref) fixes the version of an artefact in the worktree pom only: a v7 pom whose ranges resolve today to a
# Lutece 8 artefact (a Java 17 jar) does not rebuild what the environments run; pin it to the v7 version they run.
# --update checks every snapshot against the remote repositories (-U), so the latest published builds are assembled.
# The exploded site is copied to --out, the dependency list and tree of the build next to it (<out>.deps, <out>.tree).
set -euo pipefail
SITE=""; OUT=""; REF=""; PROFILE=""; REPO=""; SETTINGS=""; PINS=(); UPDATE=""
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT="$2"; shift 2;;
  --ref) REF="$2"; shift 2;;
  --profile) PROFILE="$2"; shift 2;;
  --repo) REPO="$2"; shift 2;;
  --settings) SETTINGS="$2"; shift 2;;
  --pin) PINS+=("$2"); shift 2;;
  --update) UPDATE=1; shift;;
  -*) echo "unknown option $1" >&2; exit 2;;
  *) SITE="$1"; shift;;
esac; done
[ -n "$SITE" ] && [ -n "$OUT" ] && [ -f "$SITE/pom.xml" ] || { sed -n '2,10p' "$0" >&2; exit 2; }
SITE=$(cd "$SITE" && pwd)
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="$SITE"
if [ -n "$REF" ]; then
    WORK=$(mktemp -d)/site
    git -C "$SITE" worktree add -f --detach "$WORK" "$REF" -q
    trap 'git -C "$SITE" worktree remove --force "$WORK" >/dev/null 2>&1 || true' EXIT
fi
if [ ${#PINS[@]} -gt 0 ]; then
    [ -n "$REF" ] || { echo "site-assemble: --pin changes the pom, it needs --ref (a disposable worktree)" >&2; exit 2; }
    for pin in "${PINS[@]}"; do
        python3 - "$WORK/pom.xml" "$pin" <<'PYPIN'
import re, sys
pom, pin = sys.argv[1], sys.argv[2]
g, a, v = pin.split(":")
t = open(pom, encoding="utf-8").read()
kind = "<type>lutece-plugin</type>" if re.match(r"(plugin|module)-", a) else ""
dep = f"        <dependency><groupId>{g}</groupId><artifactId>{a}</artifactId><version>[{v}]</version>{kind}</dependency>\n"
if "</dependencies>" not in t:
    sys.exit(f"site-assemble: the pom has no <dependencies> to pin {g}:{a} in")
open(pom, "w", encoding="utf-8").write(t.replace("</dependencies>", dep + "    </dependencies>", 1))
PYPIN
        echo "site-assemble: pinned $pin in the worktree pom" >&2
    done
fi
MVN=(mvn -B -q -Daether.enhancedLocalRepository.trackingFilename=_qa_none -DlocalConfDirectory="$WORK/.no-local-conf")
[ -n "$REPO" ] && MVN+=(-Dmaven.repo.local="$REPO")
[ -n "$SETTINGS" ] && MVN+=(-s "$SETTINGS")
[ -n "$PROFILE" ] && MVN+=(-P"$PROFILE")
[ -n "$UPDATE" ] && MVN+=(-U)
cd "$WORK"
"${MVN[@]}" clean lutece:site-assembly > "$OUT.log" 2>&1 || { echo "site-assemble: the build failed, see $OUT.log" >&2; tail -20 "$OUT.log" >&2; exit 1; }
"${MVN[@]}" dependency:list -DoutputFile="$OUT.deps" >> "$OUT.log" 2>&1 || true
"${MVN[@]}" dependency:tree -DoutputFile="$OUT.tree" >> "$OUT.log" 2>&1 || true
EXPLODED=$(find target -maxdepth 1 -mindepth 1 -type d ! -name maven-archiver ! -name classes ! -name checkup | head -1)
[ -n "$EXPLODED" ] && [ -d "$EXPLODED/WEB-INF" ] || { echo "site-assemble: no exploded site under $WORK/target" >&2; exit 1; }
rm -rf "$OUT"
cp -a "$EXPLODED" "$OUT"
echo "$OUT"
