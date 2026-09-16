#!/usr/bin/env python3
"""Server-side cause of each failed test: the exception lines logged in artifacts/logs/messages.log during the
test's time window (workers run in parallel, so a cause is a candidate, not a proof; the JSP name, when
present in the block, confirms it). Prints one line per failed test and writes artifacts/causes.json."""
import datetime
import json
import pathlib
import re

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"
EXC = re.compile(r"((?:[a-zA-Z_$][\w$]*\.)+[A-Z]\w*(?:Exception|Error)\b[^\n]{0,160}|Error \d{3} : [^\n]{0,160})")
TS = re.compile(r"^\[(\d+)/(\d+)/(\d+), (\d+):(\d+):(\d+):(\d+) UTC\]")


def block_time(b):
    """Epoch seconds of a messages.log block ([M/D/YY, H:MM:SS:mmm UTC])."""
    m = TS.match(b)
    if not m:
        return None
    mo, d, y, h, mi, se, ms = map(int, m.groups())
    return datetime.datetime(2000 + y, mo, d, h, mi, se, ms * 1000, tzinfo=datetime.timezone.utc).timestamp()


def main():
    log = (A / "logs" / "messages.log").read_text(errors="replace") if (A / "logs" / "messages.log").exists() else ""
    blocks = [(block_time(b), b) for b in re.split(r"\n(?=\[\d+/\d+/\d+, )", log)]
    blocks = [(t, b) for t, b in blocks if t and (" E " in b[:140] or "Exception" in b[:400])]
    rows = []
    for f in sorted((A / "results").glob("*.jsonl")) if (A / "results").exists() else []:
        rows += [json.loads(l) for l in f.read_text().splitlines() if l.strip()]
    inv = json.loads((A / "inventory.json").read_text()) if (A / "inventory.json").exists() else {"screens": [], "actions": []}
    beans = {}
    for e in inv["screens"] + inv["actions"]:
        beans[e["url"].split("?")[0].split("/")[-1]] = (e.get("bean") or "", e.get("method") or "")
    out = {}
    for r in rows:
        if r["status"] == "passed":
            continue
        url = r.get("url") or r.get("final") or r.get("action") or ""
        jsps = set(re.findall(r"([A-Z]\w+\.jsp)", url + " " + r["id"]))
        marks = set()
        for j in jsps:
            marks.add("_" + j[:-4] + ".java")
            bean, method = beans.get(j, ("", ""))
            if bean:
                marks.add(bean + "." + method if method else bean)
        t0, t1 = r.get("t_start", 0) - 1, r.get("t_end", 0) + 1
        causes = []
        for t, b in blocks:
            if t0 <= t <= t1:
                m = EXC.search(b)
                if m:
                    causes.append(("[confirmed] " if any(k in b for k in marks) else "[candidate] ") + m.group(1).strip())
        causes.sort(key=lambda c: not c.startswith("[confirmed]"))
        uniq = []
        for c in causes:
            if c not in uniq:
                uniq.append(c)
        out[r["id"]] = {"kind": r.get("kind"), "reason": r.get("reason", "")[:160], "causes": uniq[:3]}
        print("%-70s %-14s %s" % (r["id"][:70], r.get("kind"), (uniq[0][:150] if uniq else "")))
    (A / "causes.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
