#!/usr/bin/env bash
# Checks that check-v8-floor.sh refuses a core below the floor and accepts one at or above it, on the core itself and
# on a project that resolves the core through Maven (offline, from the local repository).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
C="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/check-v8-floor.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export MAVEN_ARGS="-Daether.enhancedLocalRepository.trackingFilename=none"
fails=0

# Writes a pom that is lutece-core itself at the given version.
core_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version></project>\n' "$2" > "$T/$1/pom.xml"
}

# Writes a pom that depends on lutece-core at the given version or range.
dep_pom() {
    mkdir -p "$T/$1"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>%s</artifactId><version>1.0.0</version><packaging>pom</packaging><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>%s</version><exclusions><exclusion><groupId>*</groupId><artifactId>*</artifactId></exclusion></exclusions></dependency></dependencies></project>\n' "$1" "$2" > "$T/$1/pom.xml"
}

# Runs the check on a fixture and compares the exit code with the expected one.
expect() {
    local dir=$1 want=$2 got
    rm -f "$T/$dir/target/.v8-floor"
    bash "$C" "$T/$dir" --offline 2> "$T/$dir.err"; got=$?
    if [ "$got" != "$want" ]; then
        echo "FAIL: $dir expected rc=$want, got rc=$got: $(cat "$T/$dir.err")"; fails=$((fails + 1))
    fi
}

core_pom core-801 8.0.1;                 expect core-801 1
core_pom core-beta 8.0.2-beta-03;        expect core-beta 1
core_pom core-snap 8.0.2-SNAPSHOT;       expect core-snap 0
core_pom core-803 8.0.3;                 expect core-803 0
dep_pom dep-801 8.0.1;                   expect dep-801 1
dep_pom dep-floor '[8.0.0,)';            expect dep-floor 0
V8_FLOOR_CORE_BUILD=2099-01-01 expect dep-floor 1
mkdir -p "$T/nopom";                     expect nopom 2
grep -q "lutecepowers supports" "$T/dep-801.err" || { echo "FAIL: the refusal does not name the floor"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && { echo "PASS: v8 floor refuses 8.0.1, a beta and an old snapshot build, accepts the floor snapshot and later"; exit 0; }
exit 1
