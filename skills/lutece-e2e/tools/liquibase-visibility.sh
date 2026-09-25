#!/usr/bin/env bash
# Which SQL files of the assembled site will Liquibase never see.
#
#   liquibase-visibility.sh [exploded-site-dir]
#
# `lutece:site-assembly` copies every plugin's src/sql to WEB-INF/sql, but plugin-liquibase scans the classpath
# (WEB-INF/classes/sql), and the lutece-maven-plugin copies a file there only when SqlPathInfo can parse its name
# and its first line is `-- liquibase formatted sql`. A file that fails either test is dropped without a log
# line. This lists what is missing, so a missing upgrade script is caught at build time rather than on a site.
set -uo pipefail
SITE="${1:-$(find "$(dirname "$0")/../harness/site/target" -maxdepth 1 -type d -name "e2e-site-*" 2>/dev/null | head -1)}"
[ -n "$SITE" ] && [ -d "$SITE/WEB-INF/sql" ] || { echo "liquibase-visibility: no exploded site (expected <site>/WEB-INF/sql)"; exit 2; }
missing=0; total=0
while IFS= read -r f; do
  rel=${f#"$SITE/WEB-INF/sql/"}
  # Not findings: an empty file (plugin-liquibase ships four), and the per-DBMS variants under init_db/ which the
  # v7 Ant build used and Liquibase never did.
  [ -s "$f" ] || continue
  case "$rel" in init_db/*) continue ;; esac
  total=$((total+1))
  if [ ! -f "$SITE/WEB-INF/classes/sql/$rel" ]; then
    missing=$((missing+1))
    if head -1 "$f" | grep -q "liquibase formatted sql"; then why="name not recognised by SqlPathInfo (versions must be digits and dots)"; else why="no '-- liquibase formatted sql' first line"; fi
    printf '  IGNORED  sql/%s  — %s\n' "$rel" "$why"
  fi
done < <(find "$SITE/WEB-INF/sql" -name "*.sql" -not -path "*/includes/*" -not -name "build*.xml" | sort)
echo "liquibase-visibility: $total SQL files shipped, $missing invisible to Liquibase"
[ "$missing" -eq 0 ]
