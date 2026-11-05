#!/usr/bin/env bash
# Checks tools/latest-lutece.py on fake repositories (file://): the latest Lutece 8 snapshot is the highest version whose
# pom has lutece-global-pom 8.x as parent, not the repository's <latest> (a v7 maintenance snapshot deployed after it),
# with its build; --line 7 asks for the Lutece 7 line; lutece-core is judged by its major; the release asked is the highest 8.x; an unreachable repository
# falls back on the local Maven repository.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../../tools/latest-lutece.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
S="$T/snapshots"; R="$T/releases"
snap() {
  local a=$1 v=$2 parent=$3 b=$4 d="$S/fr/paris/lutece/plugins/$1/$2"
  mkdir -p "$d"
  printf '<metadata><versioning><snapshot><timestamp>%s</timestamp><buildNumber>%s</buildNumber></snapshot></versioning></metadata>\n' "${b%-*}" "${b#*-}" > "$d/maven-metadata.xml"
  printf '<project><parent><artifactId>lutece-global-pom</artifactId><version>%s</version></parent><artifactId>%s</artifactId></project>\n' "$parent" "$a" > "$d/$a-${v%-SNAPSHOT}-$b.pom"
}
snap plugin-demo 5.0.1-SNAPSHOT 8.0.1 20261001.101010-7
snap plugin-demo 4.0.9-SNAPSHOT 7.0.2 20261003.090909-3
mkdir -p "$S/fr/paris/lutece/plugins/plugin-demo"
printf '<metadata><versioning><latest>4.0.9-SNAPSHOT</latest><versions><version>4.0.9-SNAPSHOT</version><version>5.0.1-SNAPSHOT</version></versions></versioning></metadata>\n' > "$S/fr/paris/lutece/plugins/plugin-demo/maven-metadata.xml"
mkdir -p "$S/fr/paris/lutece/lutece-core/8.0.2-SNAPSHOT"
printf '<metadata><versioning><versions><version>7.1.10-SNAPSHOT</version><version>8.0.2-SNAPSHOT</version></versions></versioning></metadata>\n' > "$S/fr/paris/lutece/lutece-core/maven-metadata.xml"
printf '<metadata><versioning><snapshot><timestamp>20261002.102953</timestamp><buildNumber>285</buildNumber></snapshot></versioning></metadata>\n' > "$S/fr/paris/lutece/lutece-core/8.0.2-SNAPSHOT/maven-metadata.xml"
mkdir -p "$R/fr/paris/lutece/tools/lutece-global-pom"
printf '<metadata><versioning><versions><version>7.0.2</version><version>8.0.1</version><version>8.0.2</version><version>8.0.3-SNAPSHOT</version></versions></versioning></metadata>\n' > "$R/fr/paris/lutece/tools/lutece-global-pom/maven-metadata.xml"
run() { LUTECE_SNAPSHOT_REPO="file://$S" LUTECE_RELEASE_REPO="file://$R" LUTECE_LATEST_CACHE="$T/cache.json" M2_REPO="$T/m2" python3 "$TOOL" "$@" 2>/dev/null; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected $3, got $2)"; fail=1; fi; }
check "the highest Lutece 8 snapshot, not the last one deployed" "$(run snapshot fr.paris.lutece.plugins:plugin-demo)" "fr.paris.lutece.plugins:plugin-demo:5.0.1-SNAPSHOT:20261001.101010-7"
check "the line asked: the highest Lutece 7 snapshot" "$(run snapshot --line 7 fr.paris.lutece.plugins:plugin-demo)" "fr.paris.lutece.plugins:plugin-demo:4.0.9-SNAPSHOT:20261003.090909-3"
check "lutece-core judged by its major" "$(run snapshot fr.paris.lutece:lutece-core)" "fr.paris.lutece:lutece-core:8.0.2-SNAPSHOT:20261002.102953-285"
check "the highest 8.x release" "$(run release fr.paris.lutece.tools:lutece-global-pom)" "fr.paris.lutece.tools:lutece-global-pom:8.0.2"
mkdir -p "$R/fr/paris/lutece/lutece-core"
printf '<metadata><versioning><versions><version>8.0.1</version><version>8.0.2-beta-04</version><version>8.0.2-beta-10</version></versions></versioning></metadata>\n' > "$R/fr/paris/lutece/lutece-core/maven-metadata.xml"
check "a published beta is a release, beta-10 above beta-04" "$(run release fr.paris.lutece:lutece-core)" "fr.paris.lutece:lutece-core:8.0.2-beta-10"
printf '<metadata><versioning><versions><version>8.0.2</version><version>8.0.1</version><version>8.0.2-beta-10</version></versions></versioning></metadata>\n' > "$R/fr/paris/lutece/lutece-core/maven-metadata.xml"
rm -f "$T/cache.json"
check "a release above its betas" "$(run release fr.paris.lutece:lutece-core)" "fr.paris.lutece:lutece-core:8.0.2"
mkdir -p "$T/m2/fr/paris/lutece/plugins/plugin-other/3.0.0-SNAPSHOT"
printf '<project><parent><artifactId>lutece-global-pom</artifactId><version>8.0.2</version></parent></project>\n' > "$T/m2/fr/paris/lutece/plugins/plugin-other/3.0.0-SNAPSHOT/plugin-other-3.0.0-SNAPSHOT.pom"
check "an unreachable repository falls back on the local Maven repository" "$(LUTECE_SNAPSHOT_REPO=file:///nowhere run snapshot fr.paris.lutece.plugins:plugin-other)" "fr.paris.lutece.plugins:plugin-other:3.0.0-SNAPSHOT"
[ $fail -eq 0 ] || exit 1
