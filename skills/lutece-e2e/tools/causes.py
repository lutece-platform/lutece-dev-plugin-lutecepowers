#!/usr/bin/env python3
"""Server-side cause of each failed test: the exception lines logged in artifacts/logs/messages.log (on the v7 leg
of a comparison, E2E_VERSION=v7: the Tomcat log artifacts/logs7/catalina.out) during the failed step's time window (the whole test's for a suite that does not record its steps) (workers run in parallel, so a cause is a candidate, not a proof; the JSP name, when
present in the block, confirms it). Prints one line per failed test and writes artifacts/causes.json."""
import datetime
import json
import os
import pathlib
import re

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"
EXC = re.compile(r"((?:[a-zA-Z_$][\w$]*\.)+[A-Z]\w*(?:Exception|Error)\b[^\n]{0,160}|Error \d{3} : [^\n]{0,160})")
TS = re.compile(r"^\[(\d+)/(\d+)/(\d+), (\d+):(\d+):(\d+):(\d+) UTC\]")
ROOT = re.compile(r"root cause: ([^\n]{0,200})")
"""The root cause the v7 core writes in the header of a Critical AppException, more telling than the wrapper."""
TS7 = re.compile(r"^ ?(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) ")


def block_time(b):
    """Epoch seconds of a messages.log block ([M/D/YY, H:MM:SS:mmm UTC])."""
    m = TS.match(b)
    if not m:
        return None
    mo, d, y, h, mi, se, ms = map(int, m.groups())
    return datetime.datetime(2000 + y, mo, d, h, mi, se, ms * 1000, tzinfo=datetime.timezone.utc).timestamp()


def block_time7(b):
    """Epoch seconds of a catalina.out block of the v7 site (YYYY-MM-DD HH:MM:SS, the container's UTC clock)."""
    m = TS7.match(b)
    if not m:
        return None
    return datetime.datetime(*map(int, m.groups()), tzinfo=datetime.timezone.utc).timestamp()


def server_blocks():
    """(epoch, text) of each error block of the log of the server the suites just ran against."""
    if os.environ.get("E2E_VERSION") == "v7":
        f = A / "logs7" / "catalina.out"
        log = f.read_text(errors="replace") if f.exists() else ""
        blocks = [(block_time7(b), b) for b in re.split(r"\n(?= ?\d{4}-\d\d-\d\d \d\d:\d\d:\d\d )", log)]
        return [(t, b) for t, b in blocks if t and (" ERROR " in b[:80] or "Exception" in b[:400])]
    log = (A / "logs" / "messages.log").read_text(errors="replace") if (A / "logs" / "messages.log").exists() else ""
    blocks = [(block_time(b), b) for b in re.split(r"\n(?=\[\d+/\d+/\d+, )", log)]
    return [(t, b) for t, b in blocks if t and (" E " in b[:140] or "Exception" in b[:400])]


def main():
    blocks = server_blocks()
    rows = []
    for f in sorted((A / "results").glob("*.jsonl")) if (A / "results").exists() else []:
        rows += [json.loads(l) for l in f.read_text().splitlines() if l.strip()]
    inv = json.loads((A / "inventory.json").read_text()) if (A / "inventory.json").exists() else {"screens": [], "actions": []}
    # An exception that names nothing of the artefact — its package, its plugin names, its tables — is the
    # platform's noise in the same time window, never this test's cause: say so instead of offering it.
    art = (inv.get("surface") or {}).get("markers") or []
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
        if r.get("failed_step_window"):
            t0, t1 = r["failed_step_window"][0] - 1, r["failed_step_window"][1] + 1
        causes = []
        for t, b in blocks:
            if t0 <= t <= t1:
                m = ROOT.search(b[:600]) or EXC.search(b)
                if m:
                    tag = "[confirmed] " if any(k in b for k in marks) else ("[candidate] " if (not art or any(a in b for a in art)) else "[hors périmètre] ")
                    causes.append(tag + m.group(1).strip())
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
