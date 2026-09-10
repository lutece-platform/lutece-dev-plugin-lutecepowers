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
# Sanitize DB name: replace hyphens with underscores (hyphens are invalid in SQL identifiers without backticks)
DB_NAME="${DB_NAME_RAW//-/_}"
DB_USER=$(jq -r '.database.user // "root"' "$CONFIG_FILE")
DB_PASSWORD=$(jq -r '.database.password // "root"' "$CONFIG_FILE")
DB_HOST=$(jq -r '.database.host // "localhost"' "$CONFIG_FILE")
DB_PORT=$(jq -r '.database.port // 3306' "$CONFIG_FILE")

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

cat > "$SITE_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">

    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>8.0.2</version>
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
            <groupId>com.mysql</groupId>
            <artifactId>mysql-connector-j</artifactId>
            <version>8.4.0</version>
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
portal.driver=com.mysql.cj.jdbc.Driver
portal.url=jdbc:mysql://$DB_HOST:$DB_PORT/$DB_NAME?autoReconnect=true&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
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

The database will be created automatically by the \`ant\` script.

## Build and run

\`\`\`bash
mvn lutece:site-assembly
cd target/${SITE_NAME}-1.0.0-SNAPSHOT/WEB-INF/sql
ant
cd ../../../..
mvn liberty:dev
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
echo "  3. cd target/${SITE_NAME}-1.0.0-SNAPSHOT/WEB-INF/sql && ant"
echo "  4. cd ../../../.. && mvn liberty:dev"
echo "  5. Open http://localhost:9080/${SITE_NAME}-1.0.0-SNAPSHOT/"
