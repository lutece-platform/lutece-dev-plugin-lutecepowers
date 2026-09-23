#!/bin/sh
# First start of this container: create the schema the v7 way, with the Ant build assembled under WEB-INF/sql
# (`ant all` = core scripts, then every plugin's create/init scripts). A marker keeps a `docker restart` from
# running it again — `drop_and_create_db` is the first thing that build does.
set -eu
APP=/usr/local/tomcat/webapps/lutece
MARK=/usr/local/tomcat/.dbinit-done
if [ "${E2E_V7_INIT_DB:-1}" = 1 ] && [ ! -f "$MARK" ]; then
  JAR=$(ls "$APP"/WEB-INF/lib/mysql-connector-*.jar 2>/dev/null | head -1)
  echo ">> v7 schema: ant all (connector: ${JAR:-none})"
  ( cd "$APP/WEB-INF/sql" && ant -q -f build.xml all -Dmysql.connector.jar.path="$JAR" ) 2>&1 | tee /logs/ant-dbinit.log
  # `ant all` runs the plugins in alphabetical order, core scripts first: a plugin whose init fills a table another
  # plugin creates later (appointment's entry types in genericattributes' genatt_entry_type) loses those rows,
  # which a real v7 site installed over the years does carry. Replay the init scripts once every table exists;
  # the rows already there fail on their key and change nothing.
  if grep -q "doesn't exist" /logs/ant-dbinit.log; then
    DBP="$APP/WEB-INF/conf/db.properties"
    prop() { sed -n "s/^portal\.$1=//p" "$DBP" | head -1; }
    cat > /tmp/replay-init.xml <<XML
<project name="replay" default="replay">
  <target name="replay">
    <sql driver="$(prop driver)" url="$(prop url | sed 's/&/\&amp;/g')" userid="$(prop user)" password="$(prop password)"
         autocommit="true" onerror="continue" encoding="UTF-8">
      <fileset dir="$APP/WEB-INF/sql/plugins" includes="*/core/init*.sql,*/plugin/init*.sql"/>
      <classpath><fileset dir="$APP/WEB-INF/lib" includes="mysql-connector-*.jar"/></classpath>
    </sql>
  </target>
</project>
XML
    echo ">> v7 schema: init scripts replayed once every plugin table exists"
    ant -q -f /tmp/replay-init.xml 2>&1 | grep -v "Failed to execute\|Duplicate entry\|SQLIntegrityConstraintViolation" | tee -a /logs/ant-dbinit.log
  fi
  touch "$MARK"
fi
exec catalina.sh run
