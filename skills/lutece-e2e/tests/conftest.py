"""pytest wiring: one browser per worker, one authenticated back-office session reused by every test
(storage state), observability collectors on every page, and one record per test in artifacts/results/<worker>.jsonl (status,
duration, server timing, console, screenshot) that tools/report.py turns into the reports."""
import json
import os
import pathlib
import time

import pytest
from playwright.sync_api import sync_playwright

import lutece

RESULTS = lutece.ARTIFACTS / "results"
STATE = lutece.ARTIFACTS / "state"


def pytest_addoption(parser):
    parser.addoption("--suite", default=None, help="suite label written in results (default: from the test file name)")


def pytest_configure(config):
    config.addinivalue_line("markers", "serial: scenario changing global settings, run alone after the parallel pass")


@pytest.fixture(scope="session")
def browser():
    """Headless Chromium for the whole session (per xdist worker)."""
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=lutece.chromium_args())
        yield b
        b.close()


@pytest.fixture(scope="session")
def bo_state(browser):
    """Authenticated storage state, logged in once per worker and kept on disk."""
    STATE.mkdir(parents=True, exist_ok=True)
    path = STATE / ("bo-%s.json" % os.environ.get("PYTEST_XDIST_WORKER", "main"))
    ctx = browser.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR")
    page = ctx.new_page()
    assert lutece.bo_login(page), "back-office login failed: %s" % page.url
    ctx.storage_state(path=str(path))
    ctx.close()
    return str(path)


@pytest.fixture
def bo(browser, bo_state, request):
    """A fresh page inside the authenticated back-office session, with collectors attached."""
    ctx = browser.new_context(storage_state=bo_state, viewport={"width": 1440, "height": 1000}, locale="fr-FR",
                              accept_downloads=True)
    ctx.set_default_timeout(20000)
    page = ctx.new_page()
    lutece.observe(page)
    request.node.page = page
    yield page
    ctx.close()


@pytest.fixture(scope="session")
def fo_theme_baseline(browser):
    """The console/JS-error signatures the assembled site's default front-office theme emits on its own, captured
    once on the bare portal home. A plugin FO page is judged against this baseline: only noise the plugin adds
    counts as its defect; the shared theme's own errors (e.g. an unescaped datastore value in an inline script) are
    environment, reported apart, never charged to the plugin."""
    ctx = browser.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR")
    page = ctx.new_page()
    lutece.observe(page)
    base = {"errors": set(), "console": set(), "requests": set(), "render": set()}
    try:
        page.goto(lutece.url("jsp/site/Portal.jsp"), wait_until="load", timeout=20000)
        page.wait_for_timeout(500)
        base["errors"] = {e for e in page.obs["errors"]}
        base["console"] = {c["text"] for c in page.obs["console"]}
        base["requests"] = {r["url"] for r in page.obs["requests"] if r.get("status", 0) != 0 or "error" in r}
        base["render"] = set(lutece.render_check(page, "fo"))
    except Exception:  # noqa: BLE001 - no baseline is a strict baseline (nothing subtracted)
        pass
    ctx.close()
    return base


@pytest.fixture
def anon(browser, request):
    """A page without any session (login screens, session-less JSPs)."""
    ctx = browser.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR")
    ctx.set_default_timeout(20000)
    page = ctx.new_page()
    lutece.observe(page)
    request.node.page = page
    yield page
    ctx.close()


@pytest.fixture
def record(request):
    """Free-form facts a test attaches to its result (server_ms, screenshot, aria diff...)."""
    request.node.record = {}
    return request.node.record


def _mvc_query(u):
    """Keeps the significant routing parameters of a Lutece url (page= for a front-office XPage, view=/action= for
    an MVC screen) so coverage can match a visit to an inventory element without collapsing every XPage sub-url."""
    import urllib.parse
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(u).query)
    parts = ["%s=%s" % (k, q[k][0]) for k in ("page", "view", "action") if k in q]
    return "&".join(parts)


def _reason(rep):
    """One line explaining a failure: the assertion message when there is one, else the crash line."""
    if not rep.failed:
        return ""
    crash = getattr(rep.longrepr, "reprcrash", None)
    text = crash.message if crash is not None else str(rep.longrepr)
    text = text.replace("\n", " ").strip()
    text = text.split(" assert ", 1)[0] if text.startswith("AssertionError: ") and " assert " in text else text
    return text[:300]


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Writes one JSON line per finished test into artifacts/results/<worker>.jsonl."""
    outcome = yield
    rep = outcome.get_result()
    if rep.when != "call" and not (rep.when == "setup" and rep.skipped):
        return
    # Under xdist the hook fires on every worker AND on the controller that replays their reports; let only the
    # worker write, or each result lands twice (once in gwN.jsonl, once in main.jsonl).
    if getattr(item.config.option, "numprocesses", None) and not os.environ.get("PYTEST_XDIST_WORKER"):
        return
    t_end = time.time()
    t_start = getattr(call, "start", t_end - rep.duration)
    RESULTS.mkdir(parents=True, exist_ok=True)
    page = getattr(item, "page", None)
    obs = getattr(page, "obs", {}) if page else {}
    rec = getattr(item, "record", {}) or {}
    if page is not None and "kind" not in rec:
        try:
            rec["kind"] = lutece.classify(page)
        except Exception:  # noqa: BLE001 - page already closed
            rec["kind"] = None
    if page is not None:
        try:
            rec["text_hash"] = lutece.text_hash(page)
        except Exception:  # noqa: BLE001
            rec["text_hash"] = None
    row = {"id": item.nodeid.split("::", 1)[1] if "::" in item.nodeid else item.nodeid, "t_start": round(t_start, 3), "t_end": round(t_end, 3),
           "file": item.nodeid.split("::", 1)[0], "suite": item.config.getoption("--suite") or item.nodeid.split("::", 1)[0].rsplit("/", 1)[-1][5:-3],
           "status": rep.outcome, "duration_ms": round(rep.duration * 1000),
           "reason": _reason(rep) if not rep.skipped else (str(rep.longrepr[2]) if isinstance(rep.longrepr, tuple) else str(rep.longrepr))[:200],
           "console": obs.get("console", [])[:20], "js_errors": obs.get("errors", [])[:20],
           "bad_requests": obs.get("requests", [])[:20], "nav": obs.get("nav", [])[-5:],
           "visited": sorted({lutece.normalize(n["url"]).split("?")[0] + ("?" + q if q else "")
                              for n in obs.get("nav", []) + obs.get("xhr", []) for q in [_mvc_query(n["url"]) or n.get("mvc", "")] if n["status"] < 400}
                             | {lutece.normalize(u).split("?")[0] for u in obs.get("subs", [])}), **rec}
    with open(RESULTS / ("%s.jsonl" % os.environ.get("PYTEST_XDIST_WORKER", "main")), "a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
