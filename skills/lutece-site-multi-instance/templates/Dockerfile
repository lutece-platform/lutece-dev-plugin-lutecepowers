FROM icr.io/appcafe/open-liberty:kernel-slim-java21-openj9-ubi-minimal

# server.xml, cluster.xml, Hazelcast files, jvm.options, server.env (no environment-specific value), bootstrap.properties
COPY --chown=1001:0 src/main/liberty/config /config/
RUN features.sh
# Built before: mvn clean lutece:site-assembly -Pcontainer-runtime (one war in target/ after "clean").
# Hazelcast is in the war (profile cluster): no separate copy of the Hazelcast jar.
COPY --chown=1001:0 target/*.war /config/apps/lutece.war
# Expands the war (/config/apps/expanded, used by the session library) and populates the shared class cache
RUN configure.sh
