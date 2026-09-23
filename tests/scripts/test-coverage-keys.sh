#!/usr/bin/env bash
# Checks the coverage keys the e2e bench credits (lutece.mvc_names, nav_keys): every MVC name a form body carries,
# urlencoded or multipart, the body name winning over the routing of the form's action url, and the @View name read
# whatever the order of its attributes (tools/inventory.py).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
out=$(python3 - "$HERE/../../skills/lutece-e2e/tests" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import lutece
print(lutece.mvc_names("id=1&view_manage=&action_copy=&name=x"))
print(lutece.mvc_names('--b\r\nContent-Disposition: form-data; name="action_save"\r\n\r\n\r\n--b--'))
print(lutece.nav_keys({"url": "http://h/lutece/jsp/admin/plugins/p/Manage.jsp?view=manage", "mvcs": ["action=copy"]}))
sys.path.insert(0, sys.argv[1] + "/../tools")
import inventory
print(inventory.annotation_name(" defaultView = true, value = VIEW_MANAGE "), inventory.annotation_name("VIEW_X"))
PY
)
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
check "urlencoded names in body order" 'echo "$out" | sed -n 1p | grep -qF "['"'"'view=manage'"'"', '"'"'action=copy'"'"']"'
check "multipart button name" 'echo "$out" | sed -n 2p | grep -qF "action=save"'
check "body name replaces the url routing" 'echo "$out" | sed -n 3p | grep -qF "Manage.jsp?action=copy"'
check "@View name whatever the attribute order" '[ "$(echo "$out" | sed -n 4p)" = "VIEW_MANAGE VIEW_X" ]'
check "url key kept" 'echo "$out" | sed -n 3p | grep -qF "Manage.jsp?view=manage"'
if [ $fail = 0 ]; then echo "PASS: coverage keys credit every MVC name of a form body"; else echo "$out"; exit 1; fi
