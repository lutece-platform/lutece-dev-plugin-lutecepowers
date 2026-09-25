#!/bin/bash

set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <config.json> <output_directory>"
    echo ""
    echo "Creates a Lutece site from JSON configuration."
    echo ""
    echo "JSON format:"
    echo '{'
    echo '  "siteName": "my-site",'
    echo '  "siteDescription": "My Lutece Site",'
    echo '  "database": {'
    echo '    "name": "lutece_mysite",'
    echo '    "user": "root",'
    echo '    "password": "root",'
    echo '    "host": "localhost",'
    echo '    "port": 3306'
    echo '  },'
    echo '  "plugins": ['
    echo '    {"groupId": "fr.paris.lutece.plugins", "artifactId": "plugin-myapp", "version": "[1.0.0-SNAPSHOT,)", "type": "lutece-plugin"}'
    echo '  ]'
    echo '}'
    exit 1
fi

CONFIG_FILE="$1"
OUTPUT_DIR="$2"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

SITE_NAME=$(jq -r '.siteName' "$CONFIG_FILE")
SITE_DESCRIPTION=$(jq -r '.siteDescription // "Lutece Site"' "$CONFIG_FILE")

DB_NAME_RAW=$(jq -r '.database.name // "lutece"' "$CONFIG_FILE")
DB_NAME="${DB_NAME_RAW//-/_}"
DB_USER=$(jq -r '.database.user // "root"' "$CONFIG_FILE")
DB_PASSWORD=$(jq -r '.database.password // "root"' "$CONFIG_FILE")
DB_HOST=$(jq -r '.database.host // "localhost"' "$CONFIG_FILE")
DB_PORT=$(jq -r '.database.port // 3306' "$CONFIG_FILE")

# Prints the latest released 8.x version of a fr.paris.lutece.tools artifact from the Lutece Maven repository, or the given fallback.
latest_release() {
    local v
    v=$(curl -s -m 10 "https://dev.lutece.paris.fr/maven_repository/fr/paris/lutece/tools/$1/maven-metadata.xml" 2>/dev/null \
        | grep -o '<version>8\.[0-9.]*</version>' | sed 's/<[^>]*>//g' | sort -V | tail -1)
    echo "${v:-$2}"
}

PARENT_VERSION=$(latest_release lutece-site-pom 8.0.2)

SITE_DIR="$OUTPUT_DIR/$SITE_NAME"
mkdir -p "$SITE_DIR/src/conf/default/WEB-INF/conf"

PLUGINS_XML=""
PLUGINS_COUNT=$(jq '.plugins | length' "$CONFIG_FILE")

for ((i=0; i<PLUGINS_COUNT; i++)); do
    GROUP_ID=$(jq -r ".plugins[$i].groupId // \"fr.paris.lutece.plugins\"" "$CONFIG_FILE")
    ARTIFACT_ID=$(jq -r ".plugins[$i].artifactId" "$CONFIG_FILE")
    VERSION=$(jq -r ".plugins[$i].version // \"[1.0.0-SNAPSHOT,)\"" "$CONFIG_FILE")
    TYPE=$(jq -r ".plugins[$i].type // \"lutece-plugin\"" "$CONFIG_FILE")

    PLUGINS_XML="$PLUGINS_XML
        <dependency>
            <groupId>$GROUP_ID</groupId>
            <artifactId>$ARTIFACT_ID</artifactId>
            <version>$VERSION</version>
            <type>$TYPE</type>
        </dependency>"
done

cat > "$SITE_DIR/pom.xml" << POMEOF
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">

    <parent>
        <artifactId>lutece-site-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>$PARENT_VERSION</version>
    </parent>

    <modelVersion>4.0.0</modelVersion>
    <groupId>fr.paris.lutece.portal</groupId>
POMEOF

echo "    <artifactId>$SITE_NAME</artifactId>" >> "$SITE_DIR/pom.xml"
echo "    <packaging>lutece-site</packaging>" >> "$SITE_DIR/pom.xml"
echo "    <version>1.0.0-SNAPSHOT</version>" >> "$SITE_DIR/pom.xml"
echo "    <name>$SITE_DESCRIPTION</name>" >> "$SITE_DIR/pom.xml"

cat >> "$SITE_DIR/pom.xml" << 'POMEOF'

    <repositories>
        <repository>
            <snapshots><enabled>true</enabled></snapshots>
            <id>luteceSnapshot</id>
            <name>luteceSnapshot</name>
            <url>https://dev.lutece.paris.fr/snapshot_repository</url>
        </repository>
        <repository>
            <id>lutece</id>
            <name>luteceRepository</name>
            <url>https://dev.lutece.paris.fr/maven_repository</url>
            <layout>default</layout>
        </repository>
    </repositories>

    <dependencies>
        <dependency>
            <groupId>fr.paris.lutece</groupId>
            <artifactId>lutece-core</artifactId>
            <version>[8.0.0,)</version>
            <type>lutece-core</type>
        </dependency>
        <dependency>
            <groupId>fr.paris.lutece.plugins</groupId>
            <artifactId>plugin-liquibase</artifactId>
            <version>2.0.2-SNAPSHOT</version>
            <type>lutece-plugin</type>
        </dependency>
        <dependency>
            <groupId>org.mariadb.jdbc</groupId>
            <artifactId>mariadb-java-client</artifactId>
            <version>${mariadb.version}</version>
        </dependency>
POMEOF

echo "$PLUGINS_XML" >> "$SITE_DIR/pom.xml"

cat >> "$SITE_DIR/pom.xml" << 'POMEOF'
    </dependencies>

    <properties>
        <jdk.version>17</jdk.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

</project>
POMEOF

cat > "$SITE_DIR/src/conf/default/WEB-INF/conf/db.properties" << DBEOF
portal.poolservice=fr.paris.lutece.util.pool.service.LuteceConnectionService
portal.driver=org.mariadb.jdbc.Driver
portal.url=jdbc:mariadb://$DB_HOST:$DB_PORT/$DB_NAME?autoReconnect=true&useUnicode=yes&characterEncoding=utf8
portal.user=$DB_USER
portal.password=$DB_PASSWORD
portal.initconns=2
portal.maxconns=50
portal.logintimeout=2
portal.checkvalidconnectionsql=SELECT 1
DBEOF

cat > "$SITE_DIR/README.md" << READMEEOF
# $SITE_DESCRIPTION

Automatically generated Lutece site.

## Prerequisites

- Java 17+
- Maven 3.8+
- MySQL 8+

## Configuration

Configure the connection in \`src/conf/default/WEB-INF/conf/db.properties\` if needed (MySQL user/password).

Create the database empty (\`CREATE DATABASE $DB_NAME\`). The schema is deployed at first startup by plugin-liquibase (Lutece 8 replaces the v7 Ant script): every plugin SQL file is a Liquibase changeset, run when \`LIQUIBASE_ENABLED_AT_STARTUP=true\`.

## Build and run

\`\`\`bash
mvn lutece:site-assembly
LIQUIBASE_ENABLED_AT_STARTUP=true mvn liberty:dev
\`\`\`

The site will be available at http://localhost:9080/${SITE_NAME}-1.0.0-SNAPSHOT/

## Included plugins
READMEEOF

for ((i=0; i<PLUGINS_COUNT; i++)); do
    ARTIFACT_ID=$(jq -r ".plugins[$i].artifactId" "$CONFIG_FILE")
    echo "- $ARTIFACT_ID" >> "$SITE_DIR/README.md"
done

echo ""
echo "Site created successfully!"
echo "  Directory: $SITE_DIR"
echo "  Site name: $SITE_NAME"
echo "  Database: $DB_NAME"
echo "  Plugins: $PLUGINS_COUNT"
echo ""
echo "Next steps:"
echo "  1. cd $SITE_DIR"
echo "  2. mvn lutece:site-assembly"
echo "  3. Create the empty database $DB_NAME"
echo "  4. LIQUIBASE_ENABLED_AT_STARTUP=true mvn liberty:dev  (plugin-liquibase deploys the schema at first startup)"
echo "  5. Open http://localhost:9080/${SITE_NAME}-1.0.0-SNAPSHOT/"
