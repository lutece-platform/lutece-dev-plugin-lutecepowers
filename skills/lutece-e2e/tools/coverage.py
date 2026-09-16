#!/usr/bin/env python3
"""Coverage of the static inventory by the tests: which screens and actions were reached by at least one
test navigation (results/*.jsonl `visited`, non-error status), and which were not. Writes
artifacts/coverage.json and prints the uncovered elements: the to-do list for the scenarios. Elements of the artefact
under test (origin target) are the scope; the core and the other plugins of the site (origin env) are counted apart."""
import json
import pathlib
import re
import sys

import urllib.parse

import yaml

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"


def main():
    inv = json.loads((A / "inventory.json").read_text())
    rows = []
    for f in sorted((A / "results").glob("*.jsonl")) if (A / "results").exists() else []:
        rows += [json.loads(l) for l in f.read_text().splitlines() if l.strip()]
    hits, proven_hits, red_hits, bare_hits = {}, {}, {}, {}
    for r in rows:
        for v in r.get("visited", []):
            hits.setdefault(v, set()).add(r["id"])
            # A scenario proves the pages an oracle stood behind (record.proven); a record without that list
            # (older run) falls back on every page it visited.
            if r["status"] == "passed" and r["suite"] == "scenarios" and "proven" not in r:
                proven_hits.setdefault(v, set()).add(r["id"])
        if r["status"] == "passed" and r["suite"] == "scenarios":
            for v in r.get("proven", []):
                proven_hits.setdefault(v, set()).add(r["id"])
            if r["status"] != "passed" and not r.get("bare"):
                red_hits.setdefault(v, set()).add(r["id"])
            if r["status"] != "passed" and r.get("bare"):
                bare_hits.setdefault(v, set()).add(r["id"])

    def key(u):
        base = u.split("?")[0]
        q = urllib.parse.parse_qs(u.split("?", 1)[1]) if "?" in u else {}
        parts = ["%s=%s" % (k, q[k][0]) for k in ("page", "view", "action") if k in q]
        return base + ("?" + "&".join(parts) if parts else "")

    excl = []
    xf = E2E / "scenarios" / "coverage-exclusions.yaml"
    if xf.exists():
        excl = (yaml.safe_load(xf.read_text()) or {}).get("exclusions", [])
    by_path, proven_by_path, red_by_path = {}, {}, {}
    for v, t in hits.items():
        by_path.setdefault(v.split("?")[0], set()).update(t)
    for v, t in proven_hits.items():
        proven_by_path.setdefault(v.split("?")[0], set()).update(t)
    for v, t in red_hits.items():
        red_by_path.setdefault(v.split("?")[0], set()).update(t)
    bare_by_path = {}
    for v, t in bare_hits.items():
        bare_by_path.setdefault(v.split("?")[0], set()).update(t)
    out = {"screens": [], "actions": []}
    for kind in ("screens", "actions"):
        for e in inv[kind]:
            k = key(e["url"])
            tests = sorted(hits.get(k, set()) if e.get("kind") == "mvc" else by_path.get(k.split("?")[0], set()) | hits.get(k, set()))
            proven = sorted(proven_hits.get(k, set()) if e.get("kind") == "mvc" else proven_by_path.get(k.split("?")[0], set()) | proven_hits.get(k, set()))
            red = sorted(red_hits.get(k, set()) if e.get("kind") == "mvc" else red_by_path.get(k.split("?")[0], set()) | red_hits.get(k, set()))
            bare_red = sorted(bare_hits.get(k, set()) if e.get("kind") == "mvc" else bare_by_path.get(k.split("?")[0], set()) | bare_hits.get(k, set()))
            rule = next((x for x in excl if x["pattern"] in e["url"]), None)
            if proven:
                status = "proven"
            elif red:
                status = "defect"
            elif bare_red:
                status = "robustness"
            elif tests:
                status = "reached"
            elif rule and rule.get("blocked_by"):
                status = "blocked"
            elif rule:
                status = "unreachable"
            else:
                status = "todo"
            out[kind].append({"id": e["id"], "url": e["url"], "origin": e.get("origin", "target"), "surface": e.get("surface", "bo"), "status": status, "covered": bool(tests), "proven": bool(proven),
                              "tests": (tests or [])[:5], "n_tests": len(tests), "excluded": rule["reason"] if rule and not tests else None,
                              "blocked_by": rule.get("blocked_by") if rule else None})
    def count(v):
        st = {"total": len(v), "covered": sum(1 for x in v if x["covered"]), "proven": sum(1 for x in v if x["proven"]),
              "excluded": sum(1 for x in v if x["excluded"])}
        for name in ("proven", "defect", "robustness", "reached", "blocked", "unreachable", "todo"):
            st["n_" + name] = sum(1 for x in v if x["status"] == name)
        return st

    out["stats"] = {k: count(v) for k, v in out.items()}
    tgt = lambda x: x["origin"] == "target"
    out["stats_target"] = {k: count([x for x in v if tgt(x) and x.get("surface", "bo") == "bo"]) for k, v in out.items() if k in ("screens", "actions")}
    out["stats_fo"] = {k: count([x for x in v if tgt(x) and x.get("surface") == "fo"]) for k, v in out.items() if k in ("screens", "actions")}
    out["stats_env"] = {k: count([x for x in v if x["origin"] == "env"]) for k, v in out.items() if k in ("screens", "actions")}
    stats = {k: count([x for x in v if tgt(x)]) for k, v in out.items() if k in ("screens", "actions")}
    (A / "coverage.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    for kind in ("screens", "actions"):
        s = stats[kind]
        print("%s: %d total - proven %d, defect %d, robustness only %d, reached only %d, blocked %d, unreachable %d, to do %d" % (
            kind, s["total"], s["n_proven"], s["n_defect"], s["n_robustness"], s["n_reached"], s["n_blocked"], s["n_unreachable"], s["n_todo"]))
        for x in out[kind]:
            if x["origin"] != "target":
                continue
            if x["status"] == "todo":
                print("  - to do: %s" % x["url"])
            elif x["status"] == "reached" and kind == "actions":
                print("  ~ reached, not proven: %s" % x["url"])
        env_todo = [x for x in out[kind] if x["origin"] == "env" and x["status"] == "todo"]
        if env_todo:
            print("  (environment: %d %s to do, listed in coverage.json)" % (len(env_todo), kind))


if __name__ == "__main__":
    main()
