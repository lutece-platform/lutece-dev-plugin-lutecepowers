#!/bin/bash
# Static checks of the multi-instance configuration of a Lutece 8 site: check-site.sh <site-dir>
# Prints one OK/KO/WARN line per check; exit code 1 if a check is KO.
SITE=${1:-.}
CFG=$SITE/src/main/liberty/config
ko=0
ok()   { echo "OK   $1"; }
bad()  { echo "KO   $1"; ko=1; }
warn() { echo "WARN $1"; }
has()  { [ -f "$1" ] && grep -q -- "$2" "$1"; }
check() { if has "$2" "$3"; then ok "$1"; else bad "$1 ($2: $3)"; fi; }

check "pom: Hazelcast dependency" "$SITE/pom.xml" "<artifactId>hazelcast</artifactId>"
if has "$SITE/pom.xml" "<artifactId>ehcache</artifactId>" && grep -A4 "<artifactId>ehcache</artifactId>" "$SITE/pom.xml" | grep -q "<scope>provided</scope>"; then
  ok "pom: Ehcache provided in the cluster profile"; else warn "pom: Ehcache not neutralised (provided) in the cluster profile"; fi
check "pom: local profile skips cluster.xml" "$SITE/pom.xml" "liberty.bootstrap.cluster.config"
check "pom: plugin-quartz-scheduler" "$SITE/pom.xml" "plugin-quartz-scheduler"

X=$CFG/cluster.xml
[ -f "$X" ] || X=$CFG/server.xml
check "Liberty: sessionCache-1.0 feature" "$X" "sessionCache-1.0"
check "Liberty: session library on every jar of the war" "$X" 'includes="\*\.jar"'
check "Liberty: writeContents=GET_AND_SET_ATTRIBUTES" "$X" 'writeContents="GET_AND_SET_ATTRIBUTES"'
check "Liberty: persistTimeout above the load balancer keep-alive" "$SITE/src/main/liberty/config/server.xml" "persistTimeout"
check "Liberty: thread pool bounded to the CPU limit" "$SITE/src/main/liberty/config/server.xml" "maxThreads="
check "Liberty: Lutece cache on the Hazelcast client" "$X" "HazelcastClientCachingProvider"
if [ -f "$CFG/cluster.xml" ]; then
  check "server.xml: cluster.xml included through cluster.config" "$CFG/server.xml" 'location="${server.config.dir}/${cluster.config}"'
  if has "$CFG/server.xml" "<feature>sessionCache-1.0</feature>"; then bad "server.xml: sessionCache-1.0 also declared outside cluster.xml"; fi
fi

M=$CFG/hazelcast-config-api-mode.yaml
check "member: graceful shutdown" "$M" "hazelcast.shutdownhook.policy: GRACEFUL"
check "member: no JVM shutdown hook (closed by OpenLiberty after the application)" "$M" "hazelcast.shutdownhook.enabled: false"
check "member: immediate near-cache invalidations" "$M" "hazelcast.cache.invalidation.batch.enabled: false"
check "member: fixed port (auto-increment false)" "$M" "auto-increment: false"
check "member: Kubernetes discovery" "$M" "kubernetes:"
if has "$M" "^  cache:"; then bad "member: cache section declared (would enable Lutece caches disabled in database)"; else ok "member: no cache section"; fi

C=$CFG/hazelcast-client-config-api-mode.yaml
check "client: near cache" "$C" "near-cache:"
check "client: own pod member" "$C" "127.0.0.1:5701"
mn=$(grep -m1 "cluster-name:" "$M" 2>/dev/null | awk '{print $2}'); cn=$(grep -m1 "cluster-name:" "$C" 2>/dev/null | awk '{print $2}')
if [ -n "$mn" ] && [ "$mn" = "$cn" ]; then ok "member and client cluster-name: $mn"; else bad "cluster-name differs (member '$mn', client '$cn')"; fi

J=$CFG/jvm.options
check "jvm.options: member provider type" "$J" "hazelcast.jcache.provider.type=member"
check "jvm.options: Hazelcast service name" "$J" "hz.service-name"
if has "$J" "add-opens=java.base/java.lang"; then ok "jvm.options: Hazelcast --add-opens"; else warn "jvm.options: Hazelcast --add-opens missing (startup warning, degraded performance)"; fi

E=$CFG/server.env
if [ -f "$E" ] && grep -Eq "^(OTEL_SDK_DISABLED|OTEL_EXPORTER|MP_CONFIG_PROFILE|PORTAL_|LIQUIBASE)" "$E"; then
  bad "server.env: environment-specific value (server.env overrides the container environment)"; else ok "server.env: no environment-specific value"; fi

P=$SITE/webapp/WEB-INF/plugins/plugins.dat
if [ -f "$P" ] && [ "$(grep -c "installed=1" "$P")" -gt 1 ]; then ok "plugins.dat: $(grep -c "installed=1" "$P") plugins installed on a fresh database"; else bad "plugins.dat: missing or nearly empty"; fi

if grep -rqsa "disallowedClusterConcurrentExecution=true" "$SITE/webapp/WEB-INF/conf/override/"; then
  ok "Quartz: $(grep -rhsa "disallowedClusterConcurrentExecution=true" "$SITE/webapp/WEB-INF/conf/override/" | grep -vc "^#") exclusive daemons declared"
else bad "Quartz: no exclusive daemon declared in conf/override"; fi

D=$SITE/Dockerfile
check "Dockerfile: configure.sh (expanded war)" "$D" "configure.sh"
if has "$D" "hazelcast-.*\.jar"; then warn "Dockerfile: separate copy of the Hazelcast jar (it is in the war)"; fi

exit $ko
