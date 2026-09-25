#!/usr/bin/env bash
# Empirical scalability proofs for a Lutece v8 cluster (3 instances).
# Generic: works for any plugin. The cluster must be running (docker compose up -d).
# Usage: cluster-verify.sh [site-dir]   (the site dir is informative: the checks target the lutece-* containers)
#   Optional env: LOCK_TABLE=<table>   -> check that a distributed-lock table exists
set -uo pipefail
DB="docker exec lutece-mariadb mariadb -ulutece -psome_password core -N -e"
pass=0; fail=0; warn=0
# Prints a passing check and counts it.
ok(){ echo "  PASS $1"; pass=$((pass+1)); }
# Prints a failing check and counts it.
ko(){ echo "  FAIL $1"; fail=$((fail+1)); }
# Prints a warning and counts it.
wn(){ echo "  WARN $1"; warn=$((warn+1)); }

echo "== 1. The 3 instances serve =="
for a in app1 app2 app3; do
  c=$(docker exec lutece-$a curl -s -o /dev/null -w '%{http_code}' --max-time 20 http://localhost:9090/lutece/jsp/site/Portal.jsp 2>/dev/null)
  [ "$c" = "200" ] && ok "$a -> 200" || ko "$a -> $c"
done

echo "== 2. nginx round-robin reaches the 3 backends =="
n=$(for i in $(seq 1 12); do curl -s -D - http://localhost:8080/lutece/jsp/site/Portal.jsp -o /dev/null 2>/dev/null | awk 'tolower($0)~/x-upstream/{print $2}'|tr -d '\r'; done | sort -u | grep -c :)
[ "$n" -ge 3 ] && ok "$n distinct backends" || ko "only $n backend(s)"

echo "== 3. Shared DB + SINGLE Liquibase migration =="
t=$($DB "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='core';" 2>/dev/null)
c=$($DB "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='core' AND table_name='core_admin_user';" 2>/dev/null)
[ "${c:-0}" -eq 1 ] && ok "shared DB: $t tables, core schema deployed" || ko "DB: ${t:-0} tables, core schema missing"
cs=$($DB "SELECT COUNT(*) FROM DATABASECHANGELOG;" 2>/dev/null)
mig=$(for a in app1 app2 app3; do docker logs lutece-$a 2>&1 | grep -q "Update has been successful" && echo "$a"; done | grep -c .)
{ [ "${cs:-0}" -gt 0 ] && [ "${mig:-0}" -le 1 ]; } && ok "liquibase: $cs changesets, $mig migrating instance" || ko "liquibase: ${cs:-0} changesets, ${mig:-0} migrations (race?)"

echo "== 4. Hazelcast clusters formed — BOTH rings (session 5701 + cache 5703) =="
# Two separate Hazelcast members per JVM (different class loaders): the session ring on 5701 (hex 1645)
# and the JCache ring on 5703 (hex 1647). BOTH must mesh — if only one forms, either session
# replication or the distributed cache silently degrades to node-local. Count ESTABLISHED inter-node
# connections per port (tcp + tcp6). A meshed app1 has >=2 peers (app2 + app3) on each ring.
# Prints the number of ESTABLISHED connections of app1 on the given hex port.
hzpeers(){ docker exec lutece-app1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' | awk -v p=":$1" '($2 ~ p"$"||$3 ~ p"$")&&$4=="01"{c++}END{print c+0}'; }
sring=$(hzpeers 1645); cring=$(hzpeers 1647)
[ "${sring:-0}" -ge 2 ] && ok "session ring (5701): app1 meshed with >=2 peers" || ko "session ring (5701): only ${sring:-0} peer(s) — session replication degraded"
[ "${cring:-0}" -ge 2 ] && ok "cache ring (5703): app1 meshed with >=2 peers"     || ko "cache ring (5703): only ${cring:-0} peer(s) — distributed cache degraded to node-local"

echo "== 5. Contended-resource concurrency primitive (optional: LOCK_TABLE) =="
# A contended resource needs EITHER a DB distributed lock (COUNT(*)-based) OR an atomic CAS on a
# counter column (preferred when a counter exists — no lock table). So a missing lock table is NOT
# a failure: it may be a counter-CAS plugin. The real proof is the concurrent functional test below.
if [ -n "${LOCK_TABLE:-}" ]; then
  e=$($DB "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='core' AND table_name='$LOCK_TABLE';" 2>/dev/null)
  [ "${e:-0}" -ge 1 ] && ok "lock table '$LOCK_TABLE' present (lock-based concurrency)" \
                      || wn "lock table '$LOCK_TABLE' absent — OK if the plugin uses atomic counter-CAS instead; prove via the concurrent functional test (exactly M succeed)."
else
  wn "LOCK_TABLE not provided: if the plugin manages a contended resource (slot, quota...), it MUST be guarded by a distributed lock OR an atomic counter-CAS. Verify via the concurrent functional test."
fi

echo "== 6. Session-cache write policy (writeContents) — the silent cluster killer =="
# Liberty's DEFAULT writeContents=ONLY_SET_ATTRIBUTES does NOT replicate in-place mutations of
# @SessionScoped CDI beans (Weld mutates the bean without a fresh setAttribute) -> any stateful
# wizard breaks on node switch ("session lost"), while admin auth (a plain setAttribute) still
# replicates and HIDES the bug. This static config assertion is what makes section 7 trustworthy.
# Must be GET_AND_SET_ATTRIBUTES (or ALL_SESSION_ATTRIBUTES).
wc=$(docker exec lutece-app1 sh -c 'grep -ho "writeContents=\"[^\"]*\"" /opt/wlp/usr/servers/defaultServer/server.xml 2>/dev/null' | head -1)
case "$wc" in
  *GET_AND_SET_ATTRIBUTES*|*ALL_SESSION_ATTRIBUTES*) ok "httpSessionCache $wc (in-place @SessionScoped mutations replicate)" ;;
  "") ko "httpSessionCache has NO writeContents -> Liberty default ONLY_SET_ATTRIBUTES: @SessionScoped bean mutations are NOT replicated (set writeContents=\"GET_AND_SET_ATTRIBUTES\")" ;;
  *)  ko "httpSessionCache $wc -> @SessionScoped bean mutations NOT replicated (need GET_AND_SET_ATTRIBUTES)" ;;
esac

echo "== 7. HTTP session replication (admin login + authenticated round-robin) =="
# NECESSARY BUT NOT SUFFICIENT: admin auth is a plain setAttribute -> replicates even under the broken
# default (caught by section 6). Stateful @SessionScoped replication is proven by the plugin's own
# functional test (multi-step flow surviving a node switch — see harness/README "Driving a stateful FO flow").
J=/tmp/cj_clv; rm -f $J
curl -s -c $J http://localhost:8080/lutece/jsp/admin/AdminLogin.jsp -o /tmp/clv_lp.html 2>/dev/null
TOK=$(grep -oiE 'name="token" id="token" value="[^"]*"' /tmp/clv_lp.html | grep -oE 'value="[^"]*"' | cut -d'"' -f2)
LOC=$(curl -s -b $J -c $J -D - -o /dev/null --data-urlencode "token=$TOK" --data-urlencode "access_code=admin" --data-urlencode "password=adminadmin" http://localhost:8080/lutece/jsp/admin/DoAdminLogin.jsp 2>/dev/null | awk 'tolower($0)~/location/{print $2}'|tr -d '\r')
if echo "$LOC" | grep -qi "AdminMenu"; then
  authok=0; backs=""
  for i in $(seq 1 9); do
    H=$(curl -s -b $J -D - -o /dev/null http://localhost:8080/lutece/jsp/admin/AdminMenu.jsp 2>/dev/null)
    [ "$(echo "$H"|awk 'NR==1{print $2}')" = "200" ] && authok=$((authok+1))
    backs="$backs $(echo "$H"|awk 'tolower($0)~/x-upstream/{print $2}'|tr -d '\r')"
  done
  nb=$(echo $backs|tr ' ' '\n'|sort -u|grep -c :)
  { [ "$authok" -eq 9 ] && [ "$nb" -ge 3 ]; } && ok "authenticated session recognized on $nb nodes (9/9 -> 200)" || ko "auth $authok/9 across $nb nodes"
else
  ko "admin login failed (redirect: $LOC) — did dbinit apply post-init.sql?"
fi

echo ""
echo "==== RESULT: $pass PASS / $fail FAIL / $warn WARN ===="
[ "$fail" -eq 0 ]
