#!/usr/bin/env bash
# Checks the v7_witness step of the scenario engine (tests/test_scenarios.py) on a stubbed database: exactly 1 on a
# database born in v7 (the core changeset 7.9.9-8.0.0 played), exactly 0 on a fresh install, a query without a value
# written in it refused, and under lpe2e upgrade from v7 the changeset required.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
TESTS="$HERE/../../skills/lutece-e2e/tests"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scenarios" "$T/artifacts/logs"
out=$(E2E_DIR="$T" python3 - "$TESTS" "$T" <<'PY'
import json, pathlib, sys, types
sys.path.insert(0, sys.argv[1])
if "playwright" not in sys.modules:
    pw, api = types.ModuleType("playwright"), types.ModuleType("playwright.sync_api")
    api.expect = None
    sys.modules.update({"playwright": pw, "playwright.sync_api": api})
import lutece
lutece.ARTIFACTS = pathlib.Path(sys.argv[2]) / "artifacts"
import test_scenarios as ts
db = {}
lutece.sql = lambda q: [[db["born"]]] if "DATABASECHANGELOG" in q else [[db["witness"]]]
W = "SELECT COUNT(*) FROM core_datastore WHERE entity_key='x.witness' AND entity_value='site v7'"
def run(born, witness, query=W):
    db.update(born=born, witness=witness)
    vars_ = {}
    try:
        ts.run_step(None, {"v7_witness": query}, vars_, {})
        return "pass v7=%s" % vars_["v7"]
    except AssertionError as e:
        return "red"
print(run(1, 1), run(0, 0), run(1, 0), run(0, 1), run(1, 2))
print(run(0, 0, "SELECT COUNT(*) FROM core_datastore WHERE entity_key LIKE 'x%'"))
(lutece.ARTIFACTS / "logs/upgrade.json").write_text(json.dumps({"status": "ok", "mode": "v7"}))
print(run(0, 0), run(1, 1))
PY
)
expected="pass v7=1 pass v7=0 red red red
red
red pass v7=1"
if [ "$out" = "$expected" ]; then echo "PASS: v7_witness expects the witness exactly when the database was born in v7"; exit 0; fi
echo "FAIL: v7_witness"; echo "$out"; exit 1
