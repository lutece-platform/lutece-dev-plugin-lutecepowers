#!/usr/bin/env python3
"""Server-side observability, reduced to a few numbers.

  metrics.py snapshot before|after   -> artifacts/metrics-<tag>.json (Liberty /metrics: JVM, servlet, pool, threads)
  metrics.py perf                    -> artifacts/perf.json: per-url server timings from the access log (p50/p95/max),
                                        top SQL digests by total time (performance_schema), slow queries, k6 summary,
                                        JFR text views, and the before/after metrics delta.
Stdlib + pymysql only. Runs in the tests container or on the host (RUNNER=local)."""
import json
import os
import pathlib
import re
import statistics
import sys
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tests"))
import lutece  # noqa: E402

METRICS_URL = lutece.BASE.rsplit("/", 1)[0] + "/metrics"
ACCESS_LOG = lutece.ARTIFACTS / "logs" / "http_access.log"
KEEP = ("jvm_uptime", "memory_usedHeap", "memory_maxHeap", "gc_total", "gc_time", "cpu_processCpuTime", "thread_count",
        "thread_max", "connectionpool_", "servlet_request", "servlet_response", "threadpool_", "session_")


def scrape():
    """Prometheus text of Liberty /metrics reduced to the interesting families {name{labels}: value}."""
    out = {}
    try:
        text = urllib.request.urlopen(METRICS_URL, timeout=10).read().decode()
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)[:200]}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        m = re.match(r"([\w:]+)(\{[^}]*\})?\s+([-\d.eE+NaInf]+)", line)
        if m and any(k in m.group(1) for k in KEEP):
            out[m.group(1) + (m.group(2) or "")] = float(m.group(3))
    return out


def access_log():
    """Per path server timings from the Liberty access log: '%t %m %U%q %s %b %D'."""
    if not ACCESS_LOG.exists():
        return {"error": "no access log"}
    per, statuses = {}, {}
    for line in ACCESS_LOG.read_text(errors="replace").splitlines():
        m = re.match(r"\[[^\]]+\] (\w+) (\S+) (\d{3}) (\S+) (\d+)", line)
        if not m:
            continue
        path = re.sub(r"\?.*", "", m.group(2)).rstrip("-")
        path = re.sub(r"/[0-9]+(?=/|$)", "/{id}", path)
        per.setdefault(path, []).append(int(m.group(5)) / 1000.0)
        statuses[m.group(3)] = statuses.get(m.group(3), 0) + 1
    rows = []
    for path, ms in per.items():
        ms.sort()
        rows.append({"path": path, "n": len(ms), "p50_ms": round(statistics.median(ms), 1),
                     "p95_ms": round(ms[int(len(ms) * 0.95) - 1] if len(ms) >= 20 else ms[-1], 1), "max_ms": round(ms[-1], 1)})
    rows.sort(key=lambda r: -r["p95_ms"])
    return {"requests": sum(len(v) for v in per.values()), "statuses": statuses, "slowest": rows[:25]}


def db_digests():
    """Top statements by total time since the last reset, and the slow-log tail."""
    try:
        rows = lutece.sql("""SELECT DIGEST_TEXT, COUNT_STAR, ROUND(SUM_TIMER_WAIT/1e9,1) total_ms, ROUND(AVG_TIMER_WAIT/1e9,2) avg_ms,
                                    ROUND(MAX_TIMER_WAIT/1e9,1) max_ms, SUM_ROWS_EXAMINED, SUM_ROWS_SENT, SUM_NO_INDEX_USED, SUM_CREATED_TMP_DISK_TABLES
                             FROM performance_schema.events_statements_summary_by_digest
                             WHERE SCHEMA_NAME = %s AND DIGEST_TEXT NOT LIKE 'SHOW%%' AND DIGEST_TEXT NOT LIKE 'SET%%'
                             ORDER BY SUM_TIMER_WAIT DESC LIMIT 20""", (lutece.DB["database"],))
        top = [{"sql": r[0][:200], "count": r[1], "total_ms": float(r[2]), "avg_ms": float(r[3]), "max_ms": float(r[4]),
                "rows_examined": r[5], "rows_sent": r[6], "no_index": r[7], "tmp_disk": r[8]} for r in rows]
        full_scans = [t for t in top if t["no_index"] and t["rows_examined"] > 10000]
        slow = lutece.sql("SELECT COUNT(*) FROM mysql.slow_log") if False else []
        return {"top": top, "full_scans_over_10k_rows": full_scans, "slow_log_note": "see artifacts/logs/db-slow.log"}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)[:200]}


LOG_ENTRY = re.compile(r"^\[\d")
"""Start of a Liberty log entry: anything else is a continuation line of the entry above (stack frames)."""


def _allow_patterns():
    """Regexes of server-log exceptions that are expected for this bench (CSRF-refusal tests, rights tests, known core
    noise): harness/server-errors-allow.txt, one per line. Everything else is an unexpected server error."""
    f = lutece.E2E / "harness" / "server-errors-allow.txt"
    pats = []
    if f.exists():
        for ln in f.read_text().splitlines():
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                try:
                    pats.append(re.compile(ln))
                except re.error:
                    pass
    return pats


def server_errors():
    """Server-side errors of the run in messages.log, counted and split into expected (allowlist) and unexpected.
    Unexpected exceptions gate the run (a real 500, an IllegalStateException, a plugin NPE that the browser hid)."""
    log = lutece.ARTIFACTS / "logs" / "messages.log"
    if not log.exists():
        return {"error": "no messages.log"}
    surf = lutece.load_json("artifacts/inventory.json", {}).get("surface") or {}
    pkg = surf.get("package")
    marks = surf.get("markers") or ([pkg] if pkg else [])
    lines = log.read_text(errors="replace").splitlines()
    counts, total, mine = {}, 0, {}
    for i, line in enumerate(lines):
        m = re.match(r"\[[^\]]+\] \w+ (\S+)\s+[EW] (.*)", line)
        if not (m and " E " in line[:120]):
            continue
        key = re.sub(r"\d+", "N", m.group(2))[:160]
        counts[key] = counts.get(key, 0) + 1
        total += 1
        # The artefact owns the exception only when its own classes appear in the stack that follows; everything
        # else is the platform it runs inside (a plugin bench must not report the core's exceptions as its defects).
        # The artefact owns the exception when it is named in the message line or in the stack that belongs to it.
        # The block is the entry itself: the message plus its continuation lines, stopping at the next timestamped
        # log entry — a fixed window would attribute an unrelated exception to whatever request logged next.
        block = [line]
        for nxt in lines[i + 1:]:
            if LOG_ENTRY.match(nxt):
                break
            block.append(nxt)
        joined = "\n".join(block)
        if marks and any(m in joined for m in marks):
            mine[key] = mine.get(key, 0) + 1
    allow = _allow_patterns()
    scoped = mine if marks else counts
    unexpected = {k: n for k, n in scoped.items() if not any(p.search(k) for p in allow)}
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:20]
    return {"errors": total, "distinct": len(counts), "package": pkg, "markers": len(marks),
            "from_artefact": sum(mine.values()),
            "top": [{"n": n, "msg": k} for k, n in top],
            "unexpected": [{"n": n, "msg": k} for k, n in sorted(unexpected.items(), key=lambda kv: -kv[1])],
            "unexpected_total": sum(unexpected.values())}


def reset_digests():
    try:
        lutece.sql("TRUNCATE performance_schema.events_statements_summary_by_digest")
    except Exception:  # noqa: BLE001 - not granted: digests then cover the whole uptime
        pass


def delta(before, after):
    out = {}
    for k, v in after.items():
        if isinstance(v, float) and isinstance(before.get(k), float):
            d = v - before[k]
            if d:
                out[k] = round(d, 3)
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "perf"
    lutece.ARTIFACTS.mkdir(exist_ok=True)
    if cmd == "snapshot":
        tag = sys.argv[2]
        if tag == "before":
            reset_digests()
        (lutece.ARTIFACTS / ("metrics-%s.json" % tag)).write_text(json.dumps(scrape(), indent=1))
        print("metrics snapshot %s written" % tag)
        return
    before = lutece.load_json("artifacts/metrics-before.json", {})
    after = lutece.load_json("artifacts/metrics-after.json", {}) or scrape()
    k6 = lutece.load_json("artifacts/k6-summary.json")
    perf = {"access_log": access_log(), "db": db_digests(), "server_errors": server_errors(), "metrics_delta": delta(before, after),
            "metrics_after": {k: v for k, v in after.items() if "connectionpool" in k or "usedHeap" in k or "thread_count" in k},
            "k6": {m: {k: v for k, v in d.items() if k in ("avg", "p(95)", "max", "rate", "passes", "fails", "count")}
                   for m, d in (k6 or {}).get("metrics", {}).items() if m in ("http_req_duration", "http_req_failed", "http_reqs", "checks")} if k6 else None}
    jfr = lutece.ARTIFACTS / "jfr.txt"
    perf["jfr"] = jfr.read_text(errors="replace")[:6000] if jfr.exists() else None
    (lutece.ARTIFACTS / "perf.json").write_text(json.dumps(perf, indent=1, ensure_ascii=False, default=str))
    print("perf.json: %d requests logged, %d digests" % (perf["access_log"].get("requests", 0), len(perf["db"].get("top", []))))


if __name__ == "__main__":
    main()
