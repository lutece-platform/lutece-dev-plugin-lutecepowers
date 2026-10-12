#!/usr/bin/env bash
# Checks how lpe2e upgrade judges the settings the takeover changed (server/upgrade.py settings_diff): a value an upgrade
# script replaces on purpose, or the previous install value turned into the new install value, is an expected default;
# a value no script explains and a key gone are losses; an unchanged value is neither.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
SERVER="$HERE/../../skills/lutece-e2e/server"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/v7/WEB-INF/sql" "$T/v8/WEB-INF/sql/upgrade"
cat > "$T/v7/WEB-INF/sql/init_db_lutece_core.sql" <<'SQL'
INSERT INTO core_datastore VALUES ('a.duration', '120');
INSERT INTO core_datastore VALUES ('a.text', '&lt;credits&gt;');
INSERT INTO core_datastore VALUES ('a.kept', 'x');
SQL
cat > "$T/v8/WEB-INF/sql/init_db_lutece_core.sql" <<'SQL'
INSERT INTO core_datastore VALUES ('a.duration', '');
INSERT INTO core_datastore VALUES ('a.text', '<credits>');
INSERT INTO core_datastore VALUES ('a.kept', 'x');
SQL
cat > "$T/v8/WEB-INF/sql/upgrade/update_db_lutece_core-7.9.9-8.0.0.sql" <<'SQL'
UPDATE core_datastore SET entity_value = '0' WHERE entity_key = 'a.show' AND entity_value = '1';
SQL
out=$(cd "$SERVER" && python3 - "$T" <<'PY'
import pathlib, sys
sys.argv = sys.argv[:2]
import upgrade
t = pathlib.Path(sys.argv[1])
before = ["a.duration = 120", "a.text = &lt;credits&gt;", "a.kept = x", "a.show = 1", "a.custom = mine", "a.gone = y"]
after = ["a.duration = ", "a.text = <credits>", "a.kept = x", "a.show = 0", "a.custom = reset"]
expected, lost = upgrade.settings_diff(before, after, t / "v8", t / "v7")
print(" | ".join(expected)); print(" | ".join(lost))
print(" | ".join(upgrade.settings_diff(["a.duration = 120"], ["a.duration = "], t / "v8", None)[1]))
PY
)
expected="a.duration = 120 ->  | a.show = 1 -> 0 | a.text = &lt;credits&gt; -> <credits>
a.custom = mine -> reset | a.gone = y (gone)
a.duration = 120 -> "
if [ "$out" = "$expected" ]; then echo "PASS: upgrade tells the defaults the new version changes from the settings lost"; exit 0; fi
echo "FAIL: upgrade settings"; echo "$out"; exit 1
