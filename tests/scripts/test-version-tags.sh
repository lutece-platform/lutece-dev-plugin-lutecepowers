#!/usr/bin/env bash
# Checks that PV02 reads the version of a release tag carrying a build-number suffix, and still fails a pom version
# that is not above the last release.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Prints the PV02 status of a fixture whose pom has the given version and whose repository carries the given tag.
pv02() {
    local d="$T/$1"
    mkdir -p "$d"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>plugin-x</artifactId><version>%s</version></project>\n' "$2" > "$d/pom.xml"
    ( cd "$d" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git tag "$3" )
    ( cd "$d" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' | grep -oE "(PASS|FAIL|WARN) \[PV02\]" | cut -d' ' -f1
}

fails=0
[ "$(pv02 suffix 2.0.0-SNAPSHOT plugin-x-1.20.8-117214)" = "PASS" ] || { echo "FAIL: a tag with a build-number suffix is read as a version above the pom"; fails=1; }
[ "$(pv02 behind 2.0.0-SNAPSHOT plugin-x-2.1.0)" = "FAIL" ] || { echo "FAIL: a pom version below the last release is not reported"; fails=1; }
[ "$fails" -eq 0 ] && { echo "PASS: PV02 reads release tags with a build-number suffix and still fails a version below the last release"; exit 0; }
exit 1
