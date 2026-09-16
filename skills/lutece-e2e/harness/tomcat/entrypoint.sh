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
  touch "$MARK"
fi
exec catalina.sh run
