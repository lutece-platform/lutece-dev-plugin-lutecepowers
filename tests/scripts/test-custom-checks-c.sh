#!/usr/bin/env bash
# Checks PM06, PM09, PM10, PM11, PM12, PV01, SQ02, SQ03, XS01, XT01 and XT02 both ways: the defect's shape fires the
# check, the v8 form, a comment or a legitimate look-alike does not. Each pom fixture carries a fresh
# target/.v8-floor verdict, so check-v8-floor.sh answers from its cache and never calls Maven.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# The fixtures are written for these parent floors; pinned so a new lutece-global-pom or lutece-site-pom release does
# not move them.
export V8_FLOOR_PARENT=8.0.2 V8_FLOOR_SITE_PARENT=8.0.4
V="${VERIFY:-$HERE/../../tools/verify-migration.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0

# Writes a file of a fixture project: $1 name, $2 relative path, $3 content.
put() {
    mkdir -p "$T/$1/$(dirname "$2")"
    printf '%s\n' "$3" > "$T/$1/$2"
}

# Writes the pom of a fixture project with a cached v8 floor verdict newer than the pom: $1 name, $2 content.
pom() {
    put "$1" pom.xml "$2"
    mkdir -p "$T/$1/target"
    printf '0\t%s\tok\n' "$T/$1/pom.xml" > "$T/$1/target/.v8-floor"
    touch -d '2099-01-01' "$T/$1/target/.v8-floor"
}

# Writes a plugin pom: $1 name, $2 parent version, $3 own version, $4 extra content before </project>.
plugin_pom() {
    pom "$1" "<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>$2</version>
    </parent>
    <groupId>fr.paris.lutece.plugins</groupId>
    <artifactId>plugin-myplugin</artifactId>
    <packaging>lutece-plugin</packaging>
    <version>$3</version>
$4
</project>"
}

# Wraps dependency blocks into a <dependencies> element.
deps() {
    printf '    <dependencies>\n%s\n    </dependencies>' "$1"
}

# Prints one dependency block: $1 groupId, $2 artifactId, $3 version (empty for none), $4 scope (empty for none).
dep() {
    printf '        <dependency>\n            <groupId>%s</groupId>\n            <artifactId>%s</artifactId>\n' "$1" "$2"
    [ -n "$3" ] && printf '            <version>%s</version>\n' "$3"
    [ -n "${4:-}" ] && printf '            <scope>%s</scope>\n' "$4"
    printf '        </dependency>\n'
}

# Prints the status of one check on a fixture directory, running the verification once per fixture.
status() {
    [ -f "$T/$1.out" ] || ( cd "$T/$1" && bash "$V" . 2>/dev/null ) | sed 's/\x1b\[[0-9;]*m//g' > "$T/$1.out"
    grep -oE "(PASS|FAIL|WARN) \[$2\]" "$T/$1.out" | head -1 | cut -d' ' -f1
}

# Records a failure when a check does not answer the expected status.
expect() {
    local got; got=$(status "$1" "$2")
    [ "$got" = "$3" ] || { echo "FAIL: $2 on $1 expected $3, got ${got:-nothing}"; fails=$((fails + 1)); }
}

# Commits the current state of a fixture as its HEAD.
commit() {
    ( cd "$T/$1" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}

CORE=$(dep fr.paris.lutece lutece-core '[8.0.0,)')
XMLT=$(dep fr.paris.lutece.plugins plugin-xmltransformer '[1.0.0,)')

plugin_pom pm06-801 8.0.1 1.0.0 "$(deps "$CORE")"
plugin_pom pm06-snap 8.0.2-SNAPSHOT 1.0.0 "$(deps "$CORE")"
plugin_pom pm06-floor 8.0.2 1.0.0 "$(deps "$CORE")"
plugin_pom pm06-810 8.0.10 1.0.0 "$(deps "$CORE")"
expect pm06-801 PM06 FAIL
expect pm06-snap PM06 FAIL
expect pm06-floor PM06 PASS
expect pm06-810 PM06 PASS
for v in 8.0.3 8.0.4; do
    pom "pm06-site-$v" "<project><modelVersion>4.0.0</modelVersion><parent><artifactId>lutece-site-pom</artifactId><groupId>fr.paris.lutece.tools</groupId><version>$v</version></parent><artifactId>site-x</artifactId><packaging>lutece-site</packaging><version>1.0.0</version></project>"
done
expect pm06-site-8.0.3 PM06 FAIL
expect pm06-site-8.0.4 PM06 PASS

plugin_pom pm09-bounded 8.0.2 1.0.0 "$(deps "$(dep fr.paris.lutece lutece-core '[7.0.0,8.0.0)')")"
expect pm09-bounded PM09 WARN
expect pm06-floor PM09 PASS

plugin_pom pm10-el 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.glassfish jakarta.el 5.0.0-M1 test)")"
plugin_pom pm10-expressly 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.glassfish.expressly expressly '' test)
$(dep jakarta.el jakarta.el-api '' test)")"
expect pm10-el PM10 FAIL
expect pm10-expressly PM10 PASS
expect pm10-expressly PM11 PASS

plugin_pom pm11-pinned 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.hibernate.validator hibernate-validator 8.0.1.Final test)")"
plugin_pom pm11-managed 8.0.2 1.0.0 "    <dependencyManagement>
$(deps "$(dep org.glassfish.jaxb jaxb-runtime 4.0.5)")
    </dependencyManagement>
$(deps "$CORE
$(dep org.glassfish.jaxb jaxb-runtime '' test)
$(dep fr.paris.lutece.plugins library-lutece-unit-testing-extra 1.0.0 test)")"
expect pm11-pinned PM11 WARN
expect pm11-managed PM11 PASS

plugin_pom pm12-ee11 8.0.2 1.0.0 "$(deps "$CORE
$(dep jakarta.annotation jakarta.annotation-api 3.0.0)")"
plugin_pom pm12-weld6 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.jboss.weld weld-junit5 5.0.0.Final test)")"
plugin_pom pm12-ee10 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.jboss.weld weld-junit5 4.0.5.Final test)
$(dep jakarta.el jakarta.el-api 5.0.1 test)")"
expect pm12-ee11 PM12 FAIL
expect pm12-weld6 PM12 FAIL
expect pm12-ee10 PM12 PASS

D=webapp/WEB-INF/plugins/myplugin.xml
for k in differ same prop; do plugin_pom "pv-$k" 8.0.2 2.0.0-SNAPSHOT "$(deps "$CORE")"; done
put pv-differ $D '<plug-in><name>myplugin</name><version>1.0.0</version></plug-in>'
put pv-same $D '<plug-in><name>myplugin</name><version>2.0.0-SNAPSHOT</version><min-core-version>8.0.0</min-core-version></plug-in>'
put pv-prop $D '<plug-in><name>myplugin</name><version>${project.version}</version></plug-in>'
expect pv-differ PV01 FAIL
expect pv-same PV01 PASS
expect pv-prop PV01 PASS

C=src/sql/plugins/myplugin/plugin/create_db_myplugin.sql
U=src/sql/plugins/myplugin/upgrade/update_db_myplugin-1.0.0-2.0.0.sql
OLD_TABLE='-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
DROP TABLE IF EXISTS myplugin_item;
CREATE TABLE myplugin_item (
id_item int AUTO_INCREMENT,
title varchar(255) default '"''"' NOT NULL,
PRIMARY KEY (id_item)
);'
NEW_TABLE='-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
DROP TABLE IF EXISTS myplugin_item;
CREATE TABLE myplugin_item (
id_item int AUTO_INCREMENT,
title varchar(255) default '"''"' NOT NULL,
status int default 0 NOT NULL,
PRIMARY KEY (id_item)
);'
for k in bare alter recreate stale reformat; do put "sq02-$k" $C "$OLD_TABLE"; commit "sq02-$k"; put "sq02-$k" $C "$NEW_TABLE"; done
put sq02-alter $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
ALTER TABLE myplugin_item ADD COLUMN status int default 0 NOT NULL;'
put sq02-recreate $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
CREATE TABLE IF NOT EXISTS myplugin_item (
id_item int AUTO_INCREMENT,
status int default 0 NOT NULL,
PRIMARY KEY (id_item)
);'
put sq02-stale src/sql/plugins/myplugin/upgrade/update_db_myplugin-0.9.0-1.0.0.sql '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-0.9.0-1.0.0.sql
CREATE TABLE myplugin_item (
id_item int AUTO_INCREMENT,
PRIMARY KEY (id_item)
);'
put sq02-reformat $C '-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
DROP TABLE IF EXISTS myplugin_item;
CREATE TABLE `myplugin_item` (
`ID_ITEM` int AUTO_INCREMENT,
`title` varchar(255) default '"''"' NOT NULL,
PRIMARY KEY (id_item)
);'
put sq02-nogit $C "$NEW_TABLE"
expect sq02-bare SQ02 FAIL
expect sq02-stale SQ02 FAIL
expect sq02-alter SQ02 PASS
expect sq02-recreate SQ02 PASS
expect sq02-reformat SQ02 PASS
expect sq02-nogit SQ02 PASS
ITEM_OLD='-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
CREATE TABLE myplugin_entry (
code varchar(255),
date_creation timestamp,
id_item int,
PRIMARY KEY (id_item)
);'
put sq02-locale $C "$ITEM_OLD"
commit sq02-locale
put sq02-locale $C "$ITEM_OLD
-- changeset myplugin:create_db_myplugin-rev1.sql
CREATE TABLE myplugin_entry_attribute (
id int,
PRIMARY KEY (id)
);"
put sq02-locale $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
CREATE TABLE IF NOT EXISTS myplugin_entry_attribute (
id int,
PRIMARY KEY (id)
);'
( export LC_ALL=fr_FR.UTF-8; status sq02-locale SQ02 > /dev/null 2>&1 )
expect sq02-locale SQ02 PASS

I=src/sql/plugins/myplugin/plugin/init_db_myplugin.sql
ALTER_AI='ALTER TABLE myplugin_item MODIFY COLUMN id_item int AUTO_INCREMENT;'
put sq03-bare $U "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
$ALTER_AI"
put sq03-zero $U "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
$ALTER_AI"
put sq03-zero $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item (id_item, title) VALUES (0,'none');"
put sq03-other $U "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-a.sql dbms:mariadb,mysql
SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-b.sql
$ALTER_AI"
put sq03-guarded $U "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-mariaDB-mySQL.sql dbms:mariadb,mysql
SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
$ALTER_AI
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-postgresql.sql dbms:postgresql
ALTER TABLE myplugin_item ALTER COLUMN id_item ADD GENERATED BY DEFAULT AS IDENTITY;"
put sq03-guarded $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item (id_item, title) VALUES (0,'none');"
put sq03-install $C "$NEW_TABLE"
expect sq03-bare SQ03 WARN
expect sq03-zero SQ03 FAIL
expect sq03-other SQ03 WARN
expect sq03-guarded SQ03 PASS
expect sq03-install SQ03 PASS

P=src/java/fr/paris/lutece/plugins/myplugin/business/portlet
put xs-xsl $P/MyPortlet.java 'public class MyPortlet extends Portlet
{
    @Override
    public String getXml( HttpServletRequest request )
    {
        return "<portlet/>";
    }
}'
put xs-sql src/sql/plugins/myplugin/core/init_core_myplugin.sql "-- liquibase formatted sql
-- changeset myplugin:init_core_myplugin.sql
INSERT INTO core_style (id_style, description_style, id_portlet_type, id_operation_mode) VALUES (100,'My style','MY_PORTLET',0);"
put xs-html $P/MyPortlet.java 'public class MyPortlet extends PortletHtmlContent
{
    @Override
    public String getHtmlContent( HttpServletRequest request )
    {
        return "";
    }
}'
put xs-bean src/java/fr/paris/lutece/plugins/myplugin/web/portlet/MyPortletJspBean.java 'public class MyPortletJspBean extends PortletJspBean
{
    public String getPreview( HttpServletRequest request )
    {
        return _portlet.getXmlDocument( request );
    }
}'
for k in doc other; do
    plugin_pom "xs-$k" 8.0.2 1.0.0 "$(deps "$CORE
$XMLT")"
    put "xs-$k" $P/DocPortlet.java 'public class DocPortlet extends Portlet
{
    public String getXml( HttpServletRequest request )
    {
        return "<portlet/>";
    }
}'
done
put xs-doc webapp/WEB-INF/plugins/myplugin.xml "<plug-in><portlets><portlet><portlet-class>fr.paris.lutece.plugins.myplugin.business.portlet.DocPortletHome</portlet-class>
<portlet-type-id>DOCUMENT_PORTLET</portlet-type-id></portlet></portlets></plug-in>"
put xs-other webapp/WEB-INF/plugins/myplugin.xml "<plug-in><portlets><portlet><portlet-class>fr.paris.lutece.plugins.myplugin.business.portlet.DocPortletHome</portlet-class>
<portlet-type-id>MY_PORTLET</portlet-type-id></portlet></portlets></plug-in>"
expect xs-doc XS01 PASS
expect xs-other XS01 FAIL
expect xs-xsl XS01 FAIL
expect xs-sql XS01 PASS
expect xs-sql XT01 FAIL
expect xs-html XS01 PASS
pom xs-core "<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>fr.paris.lutece</groupId>
    <artifactId>lutece-core</artifactId>
    <packaging>lutece-core</packaging>
    <version>8.0.2</version>
</project>"
put xs-core src/java/fr/paris/lutece/portal/business/portlet/AliasPortlet.java 'public class AliasPortlet extends Portlet
{
    public String getXml( HttpServletRequest request )
    {
        return "<portlet/>";
    }
}'
expect xs-core XS01 PASS
expect xs-bean XS01 PASS

J=src/java/fr/paris/lutece/plugins/myplugin/service/MyRenderer.java
XSL_USE='import fr.paris.lutece.portal.service.html.XmlTransformerService;
class MyRenderer { String r( ) { return XmlTransformerService.transformBySourceWithXslCache( "", null, null, null ); } }'
plugin_pom xt01-java 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-java $J "$XSL_USE"
plugin_pom xt01-sql 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-sql src/sql/plugins/myplugin/plugin/init_db_myplugin.sql "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
UPDATE core_style SET description_style='x' WHERE id_style=100;"
plugin_pom xt01-dep 8.0.2 1.0.0 "$(deps "$CORE
$XMLT")"
put xt01-dep $J "$XSL_USE"
plugin_pom xt01-legacy 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-legacy src/sql/plugins/myplugin/plugin/create_db_myplugin.sql '-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
-- Dumping data for table core_style
CREATE TABLE myplugin_item ( id_item int NOT NULL );'
put xt01-legacy src/sql/plugins/myplugin/upgrade/update_db_myplugin-1.0.0-2.0.0.sql "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
-- preconditions onFail:MARK_RAN onError:MARK_RAN
-- precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM information_schema.tables WHERE table_name='core_style'
DELETE FROM core_style WHERE id_portlet_type='MY_PORTLET';"
expect xt01-java XT01 FAIL
expect xt01-sql XT01 FAIL
expect xt01-dep XT01 PASS
expect xt01-legacy XT01 PASS

STYLE_INSERT="INSERT INTO core_style (id_style, description_style, id_portlet_type, id_operation_mode) VALUES (100,'My style','MY_PORTLET',0);"
for k in bare header upgrade nodep; do plugin_pom "xt02-$k" 8.0.2 1.0.0 "$(deps "$CORE
$XMLT")"; done
plugin_pom xt02-nodep 8.0.2 1.0.0 "$(deps "$CORE")"
put xt02-bare $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
put xt02-header $I "-- liquibase formatted sql
-- lutece runAfter:xmltransformer
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
put xt02-upgrade $U "-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
$STYLE_INSERT"
put xt02-nodep $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
plugin_pom xt02-archive 8.0.2 1.0.0 "$(deps "$CORE
$XMLT")"
put xt02-archive $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
put xt02-archive src/sql/plugins/myplugin/old-upgrade/update_db_myplugin-0.1.0-0.2.0.sql "-- liquibase formatted sql
-- lutece runAfter:xmltransformer
-- changeset myplugin:old"
expect xt02-archive XT02 FAIL
expect xt02-bare XT02 FAIL
expect xt02-header XT02 PASS
expect xt02-upgrade XT02 PASS
expect xt02-nodep XT02 PASS

EXCL_EL=$(printf '        <dependency>\n            <groupId>fr.paris.lutece.plugins</groupId>\n            <artifactId>plugin-other</artifactId>\n            <version>[1.0.0,)</version>\n            <exclusions>\n                <exclusion><groupId>org.glassfish</groupId><artifactId>jakarta.el</artifactId></exclusion>\n                <exclusion><groupId>org.hibernate.validator</groupId><artifactId>hibernate-validator</artifactId></exclusion>\n            </exclusions>\n        </dependency>')
REAL_EL=$(printf '        <dependency>\n            <groupId>org.glassfish</groupId>\n            <artifactId>jakarta.el</artifactId>\n            <version>5.0.0-M1</version>\n            <exclusions>\n                <exclusion><groupId>x</groupId><artifactId>y</artifactId></exclusion>\n            </exclusions>\n        </dependency>')
plugin_pom pm-excl 8.0.2 1.0.0 "$(deps "$CORE
$EXCL_EL")"
plugin_pom pm-excl-real 8.0.2 1.0.0 "$(deps "$CORE
$REAL_EL")"
expect pm-excl PM10 PASS
expect pm-excl PM11 PASS
expect pm-excl-real PM10 FAIL

plugin_pom pm-comment 8.0.2 1.0.0 "    <!-- <dependency><groupId>org.glassfish</groupId><artifactId>jakarta.el</artifactId><version>5.0.0-M1</version></dependency> -->
    <!-- lutece-core was <version>[7.0.0,8.0.0)</version> -->
$(deps "$CORE")"
pom pm06-comment '<project>
    <modelVersion>4.0.0</modelVersion>
    <!-- was <parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-global-pom</artifactId><version>7.0.0</version></parent> -->
    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>8.0.2</version>
    </parent>
    <artifactId>plugin-myplugin</artifactId>
    <version>1.0.0</version>
</project>'
pom pm06-oneline '<project><parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-global-pom</artifactId><version>8.0.2</version></parent><artifactId>plugin-myplugin</artifactId><version>1.0.0</version></project>'
pom pm06-oneline-old '<project><parent><groupId>fr.paris.lutece.tools</groupId><artifactId>lutece-global-pom</artifactId><version>8.0.1</version></parent><artifactId>plugin-myplugin</artifactId><version>8.0.2</version></project>'
expect pm-comment PM10 PASS
expect pm-comment PM09 PASS
expect pm06-comment PM06 PASS
expect pm06-oneline PM06 PASS
expect pm06-oneline-old PM06 FAIL
grep -q 'WARN \[PM09\].*(1 matches)' "$T/pm09-bounded.out" || { echo "FAIL: PM09 does not report its match count"; fails=$((fails + 1)); }

plugin_pom pm11-lang3 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.apache.commons commons-lang3 3.14.0)")"
plugin_pom pm11-oldgroup 8.0.2 1.0.0 "$(deps "$CORE
$(dep org.hibernate hibernate-validator 5.4.3.Final test)
$(dep org.apache.commons commons-lang3 '')")"
plugin_pom pm11-parentprop 8.0.2 1.0.0 "$(deps "$CORE
$(dep fr.paris.lutece.plugins library-lutece-unit-testing '${library-lutece-unit-testing.version}' test)")"
plugin_pom pm11-ownprop 8.0.2 1.0.0 "    <properties>
        <my.io.version>2.16.1</my.io.version>
    </properties>
$(deps "$CORE
$(dep commons-io commons-io '${my.io.version}')")"
expect pm11-lang3 PM11 WARN
expect pm11-oldgroup PM11 PASS
expect pm11-parentprop PM11 PASS
expect pm11-ownprop PM11 WARN

pom pv-comment '<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>8.0.2</version>
    </parent>
    <artifactId>plugin-myplugin</artifactId>
    <!-- <version>1.0.0</version> -->
    <version>2.0.0-SNAPSHOT</version>
</project>'
put pv-comment $D '<plug-in><!-- <version>1.0.0</version> --><name>myplugin</name><version>2.0.0-SNAPSHOT</version></plug-in>'
pom pv-late '<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>8.0.2</version>
    </parent>
    <artifactId>plugin-myplugin</artifactId>
    <dependencies>
        <dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>2.0.0-SNAPSHOT</version></dependency>
    </dependencies>
    <version>3.0.0-SNAPSHOT</version>
</project>'
put pv-late $D '<plug-in><name>myplugin</name><version>2.0.0-SNAPSHOT</version></plug-in>'
pom pv-inherit '<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <artifactId>lutece-global-pom</artifactId>
        <groupId>fr.paris.lutece.tools</groupId>
        <version>8.0.2</version>
    </parent>
    <artifactId>plugin-myplugin</artifactId>
    <dependencies>
        <dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>[8.0.0,)</version></dependency>
    </dependencies>
</project>'
put pv-inherit $D '<plug-in><name>myplugin</name><version>8.0.2</version></plug-in>'
expect pv-comment PV01 PASS
expect pv-late PV01 FAIL
expect pv-inherit PV01 PASS

COMMENTED_TABLE='-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
DROP TABLE IF EXISTS myplugin_item;
CREATE TABLE myplugin_item (
-- the item of the plugin
id_item int AUTO_INCREMENT,
title varchar(255) default '"''"' NOT NULL,
PRIMARY KEY (id_item)
);'
for k in ifne multiline multiadd prefix comment commented; do put "sq02-$k" $C "$OLD_TABLE"; commit "sq02-$k"; put "sq02-$k" $C "$NEW_TABLE"; done
put sq02-comment $C "$COMMENTED_TABLE"
put sq02-ifne $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
ALTER TABLE myplugin_item ADD COLUMN IF NOT EXISTS status int default 0 NOT NULL;'
put sq02-multiline $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
ALTER TABLE myplugin_item
    ADD COLUMN status int default 0 NOT NULL;'
put sq02-multiadd $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
ALTER TABLE myplugin_item ADD label varchar(50) NULL,
    ADD status int default 0 NOT NULL;'
put sq02-prefix $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
ALTER TABLE myplugin_item_history ADD COLUMN status int default 0 NOT NULL;'
put sq02-commented $U '-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
-- ALTER TABLE myplugin_item ADD COLUMN status int default 0 NOT NULL;
SELECT 1;'
expect sq02-ifne SQ02 PASS
expect sq02-multiline SQ02 PASS
expect sq02-multiadd SQ02 PASS
expect sq02-comment SQ02 PASS
expect sq02-prefix SQ02 FAIL
expect sq02-commented SQ02 FAIL

HDR='-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql'
put sq03-parent0 $U "$HDR
$ALTER_AI"
put sq03-parent0 $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item (id_parent, title) VALUES (0,'root');"
put sq03-spaced $U "$HDR
$ALTER_AI"
put sq03-spaced $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item ( id_item, title ) VALUES ( 0, 'none' );"
put sq03-nocols $U "$HDR
$ALTER_AI"
put sq03-nocols $C "$OLD_TABLE"
put sq03-nocols $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item VALUES (0,'none');"
put sq03-nocols-other $U "$HDR
ALTER TABLE myplugin_item MODIFY COLUMN title varchar(255) AUTO_INCREMENT;"
put sq03-nocols-other $C "$OLD_TABLE"
put sq03-nocols-other $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item VALUES (0,'none');"
put sq03-addcol $U "$HDR
ALTER TABLE myplugin_item ADD COLUMN id_new int AUTO_INCREMENT UNIQUE;"
put sq03-backtick $U "$HDR
ALTER TABLE \`myplugin_item\` MODIFY COLUMN \`id_item\` int AUTO_INCREMENT;"
put sq03-commentguard $U "$HDR
-- NO_AUTO_VALUE_ON_ZERO is not needed here
$ALTER_AI"
put sq03-default $U "$HDR
$ALTER_AI"
put sq03-default $C "-- liquibase formatted sql
-- changeset myplugin:create_db_myplugin.sql
CREATE TABLE myplugin_item ( id_item int NOT NULL, title varchar(255) default '' NOT NULL, status int, PRIMARY KEY (id_item) );"
put sq03-default $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
INSERT INTO myplugin_item VALUES (0,'none',1);"
expect sq03-default SQ03 FAIL
expect sq03-parent0 SQ03 WARN
expect sq03-spaced SQ03 FAIL
expect sq03-nocols SQ03 FAIL
expect sq03-nocols-other SQ03 WARN
expect sq03-addcol SQ03 PASS
expect sq03-backtick SQ03 WARN
expect sq03-commentguard SQ03 WARN

plugin_pom xt01-core 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-core $J 'import fr.paris.lutece.util.xml.XmlTransformer;
class MyRenderer { String r( ) { return new XmlTransformer( ).transform( null, null, null, null, null ); } }'
plugin_pom xt01-doc 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-doc $J '/**
 * Rendered by XmlTransformerService in v7, by a template since.
 */
class MyRenderer { }'
plugin_pom xt01-archive 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-archive src/sql/plugins/myplugin/old-upgrade/update_db_myplugin-0.1.0-0.2.0.sql "$STYLE_INSERT"
plugin_pom xt01-upgrade 8.0.2 1.0.0 "$(deps "$CORE")"
put xt01-upgrade $U "$HDR
$STYLE_INSERT"
expect xt01-core XT01 PASS
expect xt01-doc XT01 PASS
expect xt01-archive XT01 PASS
expect xt01-upgrade XT01 FAIL

for k in elsewhere late far; do plugin_pom "xt02-$k" 8.0.2 1.0.0 "$(deps "$CORE
$XMLT")"; done
put xt02-elsewhere $C '-- liquibase formatted sql
-- lutece runAfter:xmltransformer
-- changeset myplugin:create_db_myplugin.sql
CREATE TABLE myplugin_item ( id_item int NOT NULL );'
put xt02-elsewhere $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
put xt02-late $I "-- liquibase formatted sql
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT
-- lutece runAfter:xmltransformer"
put xt02-far $I "-- liquibase formatted sql
$(for n in $(seq 1 20); do echo "-- note $n"; done)
-- lutece runAfter:xmltransformer
-- changeset myplugin:init_db_myplugin.sql
$STYLE_INSERT"
expect xt02-elsewhere XT02 PASS
expect xt02-late XT02 FAIL
expect xt02-far XT02 FAIL

put xs-guarded $U "$HDR
-- preconditions onFail:MARK_RAN onError:WARN
-- precondition-sql-check expectedResult:3 SELECT COUNT(1) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=database() AND TABLE_NAME IN ('core_style_mode_stylesheet','core_stylesheet','core_style')
$STYLE_INSERT"
put xs-unguarded $U "$HDR
$STYLE_INSERT"
put xs-archive src/sql/plugins/myplugin/old-upgrade/update_db_myplugin-0.1.0-0.2.0.sql "$STYLE_INSERT"
put xs-test src/test/java/fr/paris/lutece/plugins/myplugin/business/portlet/MyPortletTest.java 'public class MyPortletTest extends LuteceTestCase
{
    class FakePortlet extends Portlet
    {
        public String getXml( HttpServletRequest request ) { return ""; }
    }
}'
expect xs-guarded XS01 PASS
expect xs-guarded XT01 PASS
expect xs-unguarded XT01 FAIL
expect xs-archive XS01 PASS
expect xs-archive XT01 PASS
expect xs-test XS01 PASS

[ "$fails" -eq 0 ] && { echo "PASS: PM06, PM09, PM10, PM11, PM12, PV01, SQ02, SQ03, XS01, XT01 and XT02 fire on the defect and stay quiet on the v8 form"; exit 0; }
exit 1
