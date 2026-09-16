#!/bin/sh
# Starter kit: applies whatever seed the bench ships — every harness/db/seed-*.sql, in name order. The generic
# harness ships none: the reference rows and the synthetic volume are written by the agent for the artefact under
# test (its own tables, its own row counts). E2E_VOLUME sizes them and is exposed to the SQL as @users/@groups/
# @roles/@lists/@pages so a generated seed can scale itself; see reference/seed-volume-example.sql.
set -eu
case "${E2E_VOLUME:-none}" in
  large) USERS=100000; GROUPS=500; ROLES=300; LISTS=500; PAGES=3000 ;;
  small) USERS=2000;   GROUPS=50;  ROLES=30;  LISTS=50;  PAGES=200 ;;
  *)     USERS=0;      GROUPS=0;   ROLES=0;   LISTS=0;   PAGES=0 ;;
esac
run() {
  mariadb -h db -ulutece -plutece lutece \
    -e "SET @users=$USERS, @groups=$GROUPS, @roles=$ROLES, @lists=$LISTS, @pages=$PAGES; SOURCE $1;"
}
found=0
# seed7-*.sql: rows only the v7 schema needs (a portlet's XSL style, a column the v8 dropped), applied on the v7
# leg of run.sh compare only.
for f in $(ls /db/seed-*.sql 2>/dev/null | sort) $( [ "${E2E_VERSION:-v8}" = v7 ] && ls /db/seed7-*.sql 2>/dev/null | sort ); do
  [ -f "$f" ] || continue
  found=1
  echo ">> seed $f (volume ${E2E_VOLUME:-none})"
  run "$f"
done
[ "$found" = 1 ] || echo ">> no harness/db/seed-*.sql in this bench: database left as the application created it"
