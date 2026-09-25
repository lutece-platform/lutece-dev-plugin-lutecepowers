# Open Liberty runtime on Eclipse Temurin (HotSpot), same base as the lutece-e2e bench. The Liberty version is
# pinned; the zip (all features: sessionCache, mpTelemetry, mpHealth, restfulWS) comes from Maven Central.
FROM eclipse-temurin:21-jdk-noble
ARG LIBERTY_VERSION=26.0.0.9
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /tmp/ol.zip "https://repo1.maven.org/maven2/io/openliberty/openliberty-runtime/${LIBERTY_VERSION}/openliberty-runtime-${LIBERTY_VERSION}.zip" \
 && unzip -q /tmp/ol.zip -d /opt && rm /tmp/ol.zip \
 && /opt/wlp/bin/server create defaultServer
ENV PATH="/opt/wlp/bin:${PATH}"
ARG SRV=/opt/wlp/usr/servers/defaultServer

COPY src/main/liberty/config/server.xml  ${SRV}/server.xml
COPY src/main/liberty/config/server.env  ${SRV}/server.env
COPY src/main/liberty/config/jvm.options ${SRV}/jvm.options
COPY hazelcast.xml                       ${SRV}/hazelcast.xml
COPY hazelcast-session.xml               ${SRV}/hazelcast-session.xml
COPY hazelcast-5.5.0.jar                 ${SRV}/hazelcast/hazelcast-5.5.0.jar
COPY target/lutece.war                   ${SRV}/apps/lutece.war

# The JDBC driver must exist before the war is expanded (the dataSource is resolved first): extract it.
RUN mkdir -p /opt/wlp/usr/shared/resources/jdbc \
 && unzip -j -q ${SRV}/apps/lutece.war 'WEB-INF/lib/mariadb-java-client-*.jar' -d /opt/wlp/usr/shared/resources/jdbc \
 && mkdir -p /opt/lutece/shared

EXPOSE 9090
CMD ["server", "run", "defaultServer"]
