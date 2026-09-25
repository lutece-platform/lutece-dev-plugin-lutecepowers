#!/usr/bin/env bash
# liquibase-checksum.sh <sql file> [git ref] — the v8 and v9 checksums of each changeset of a formatted SQL file, as it
# is in the work tree or, with a git ref (the last release tag), as that release shipped it.
#
# Only a prerun_db_* changeset is replayed on every start (plugin-liquibase filters init_* and old update_* files out
# before Liquibase sees them): a changed prerun body stops the startup ("ValidationFailedException") unless the former
# checksums are declared on the changeset line (-- validCheckSum: <v8>, -- validCheckSum: <v9>). Anywhere else, fix a
# released script with a new changeset (rules/sql-liquibase.md).
set -euo pipefail
FILE=${1:?usage: liquibase-checksum.sh <sql file> [git ref]}
REF=${2:-}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M2="${M2_REPO:-$HOME/.m2/repository}"
JAR=$(ls "$M2"/org/liquibase/liquibase-core/5.*/liquibase-core-5.*.jar 2>/dev/null | sort -V | tail -1)
[ -n "$JAR" ] || { echo "liquibase-core 5.x not found under $M2 (build any Lutece 8 site once)"; exit 2; }
DEPS=$(python3 - "$JAR" "$M2" <<'PY'
import glob, os, re, sys
jar, m2 = sys.argv[1], sys.argv[2]
pom = open(jar[:-4] + ".pom", encoding="utf-8").read()
out = []
for dep in re.findall(r"<dependency>(.*?)</dependency>", pom, re.S):
    if re.search(r"<scope>(test|provided)</scope>", dep):
        continue
    g = re.search(r"<groupId>([^<]+)", dep).group(1); a = re.search(r"<artifactId>([^<]+)", dep).group(1)
    jars = sorted((j for j in glob.glob(os.path.join(m2, g.replace(".", "/"), a, "*", "%s-*.jar" % a))
                   if not re.search(r"-(sources|javadoc|tests)\.jar$", j)), key=lambda j: [int(x) if x.isdigit() else x for x in re.split(r"[.-]", j.split("/")[-2])])
    if jars:
        out.append(jars[-1])
print(":".join(out) + (":" if out else ""))
PY
)
CP="$JAR:$DEPS$HERE/liquibase"
[ -f "$HERE/liquibase/LiquibaseChecksum.class" ] && [ "$HERE/liquibase/LiquibaseChecksum.class" -nt "$HERE/liquibase/LiquibaseChecksum.java" ] || javac -cp "$CP" -d "$HERE/liquibase" "$HERE/liquibase/LiquibaseChecksum.java"
if [ -n "$REF" ]; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    git -C "$(dirname "$FILE")" show "$REF:$(git -C "$(dirname "$FILE")" ls-files --full-name "$(basename "$FILE")")" > "$TMP/$(basename "$FILE")"
    FILE="$TMP/$(basename "$FILE")"
fi
java -cp "$CP" LiquibaseChecksum "$FILE" 2>&1 | grep -v "^SLF4J\|^WARNING\|INFO"
