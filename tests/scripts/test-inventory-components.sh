#!/usr/bin/env bash
# Checks that the e2e inventory (tools/inventory.py) lists the elements without a screen of their own with the page that
# shows them, apart from the screens: each page include of a descriptor with the home page, each group of site
# properties with ManageProperties.jsp, counted in the declared socle; and that the coverage judges them on that page.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS="$HERE/../../skills/lutece-e2e/tools"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p/webapp/WEB-INF/plugins" "$T/p/src/java/a/service" "$T/e2e/artifacts/results"
cat > "$T/p/webapp/WEB-INF/plugins/a.xml" <<'XML'
<plug-in><name>a</name>
<page-include-services>
  <page-include-service><page-include-service-id>a.include.one</page-include-service-id>
    <page-include-service-class>a.web.OneInclude</page-include-service-class></page-include-service>
  <!-- <page-include-service><page-include-service-id>a.include.off</page-include-service-id></page-include-service> -->
</page-include-services>
</plug-in>
XML
echo 'public class AGroup implements ILocalizedSitePropertiesGroup { }' > "$T/p/src/java/a/service/AGroup.java"
python3 "$TOOLS/inventory.py" "$T/p" > "$T/e2e/artifacts/inventory.json"
echo '{"id": "s1", "suite": "scenarios", "status": "passed", "visited": ["jsp/admin/ManageProperties.jsp"], "proven": ["jsp/admin/ManageProperties.jsp"]}' > "$T/e2e/artifacts/results/r.jsonl"
(cd "$T/e2e" && E2E_DIR="$T/e2e" python3 "$TOOLS/coverage.py" --gate > /dev/null); RC=$?
out=$(python3 -c '
import json, sys
i = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2]))
print([(x["id"], x["url"]) for x in i["components"]], len(i["screens"]))
print(i["surface"]["page_includes"], i["surface"]["properties_groups"])
print([(x["id"], x["status"]) for x in c["components"]])' "$T/e2e/artifacts/inventory.json" "$T/e2e/artifacts/coverage.json")
expected="[('include.a.include.one', 'jsp/site/Portal.jsp?page_id=1'), ('properties.AGroup', 'jsp/admin/ManageProperties.jsp')] 0
1 1
[('include.a.include.one', 'todo'), ('properties.AGroup', 'proven')]"
if [ "$out" = "$expected" ] && [ "$RC" = 0 ]; then echo "PASS: inventory lists page includes and site properties groups, coverage judges them outside the gate"; exit 0; fi
echo "FAIL: inventory components (gate rc=$RC)"; echo "$out"; exit 1
