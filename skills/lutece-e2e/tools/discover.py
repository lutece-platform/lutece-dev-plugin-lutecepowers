#!/usr/bin/env python3
"""Dynamic discovery: logs in the back office and walks display links from the admin menu and every
feature entry screen, collecting the concrete parameterised urls (ids from the seeded data) that the
static inventory cannot know. Follows GET links only, never a Do*/action url. Output: artifacts/discovered.json
{screens: [{url, from, title}], forms: [{url, action, screen}], skipped: [...]} — the screens suite is
parametrised on it."""
import json
import re
import sys
import time
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tests"))
import lutece  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402

MUTATING = re.compile(r"/(Do|do)[A-Z]\w*\.jsp|[?&]action=|DoAdminLogout|DoChangeLanguage|DoModifyAccessibilityMode", re.I)
"""Urls that mutate state: never followed by the crawl (the scenarios cover them)."""
NOISE = re.compile(r"AdminDocumentation|AdminPagePreview\.jsp|Portal\.jsp|jsp/site/|\.pdf$|DoDownload|DoExport", re.I)
MAX_PER_PATH = 25
"""Concrete urls kept per screen (JSP path, or MVC view); the seed holds thousands of rows, a screen needs a sample."""
MAX_SCREENS = 2000
DEPTH = 8


def crawl(base):
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=lutece.chromium_args())
        ctx = b.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR")
        page = ctx.new_page()
        page.set_default_timeout(20000)
        lutece.observe(page)
        assert lutece.bo_login(page), "login failed"
        seen, queue, out, forms, skipped = {}, [], [], [], []
        per_path = {}

        in_scope = lutece.scope()

        def push(u, src, depth):
            n = lutece.normalize(u)
            if not n.startswith("jsp/admin/") or n in seen or not in_scope(n):
                return
            if MUTATING.search(n) or NOISE.search(n):
                skipped.append(n); seen[n] = True
                return
            # The sample is per screen, and on an MVC bean every view shares one JSP path: the view is part of
            # the key, or the twenty views of ManageX.jsp would split one quota that a v7 JSP-per-view gets each.
            path = n.split("?")[0] + "|" + (re.search(r"[?&]view=([\w-]*)", n).group(1) if "view=" in n else "")
            if per_path.get(path, 0) >= MAX_PER_PATH:
                seen[n] = True
                return
            per_path[path] = per_path.get(path, 0) + 1
            seen[n] = True
            queue.append((n, src, depth))

        inv = lutece.load_json("artifacts/inventory.json", {"features": [], "screens": []})
        if in_scope("jsp/admin/AdminMenu.jsp"):
            push("jsp/admin/AdminMenu.jsp", "root", 0)
        for f in inv["features"]:
            if f.get("url"):
                push(f["url"], "feature:" + f["right"], 0)
        for s in inv["screens"]:
            if "?" not in s["url"] and s["kind"] == "jsp" and not s["url"].endswith(("AdminLogin.jsp", "AdminMenu.jsp")):
                push(s["url"], "inventory", 1)
        while queue and len(out) < MAX_SCREENS:
            n, src, depth = queue.pop(0)
            t0 = time.perf_counter()
            try:
                resp = page.goto(lutece.url(n), wait_until="domcontentloaded")
            except Exception as e:  # noqa: BLE001
                out.append({"url": n, "from": src, "status": 0, "error": str(e)[:120]})
                continue
            status = resp.status if resp else 0
            kind = lutece.error_kind(page, status)
            if kind == "auth":
                out.append({"url": n, "from": src, "status": status, "kind": "auth", "note": "session lost after %s; re-login" % (out[-1]["url"] if out else "?")})
                lutece.bo_login(page)
                resp = page.goto(lutece.url(n), wait_until="domcontentloaded")
                status = resp.status if resp else 0
                kind = lutece.error_kind(page, status)
            title = page.title()[:80]
            out.append({"url": n, "from": src, "status": status, "kind": kind, "title": title,
                        "ms": round((time.perf_counter() - t0) * 1000), "final": lutece.normalize(page.url)})
            if kind:
                continue
            for link in lutece.admin_links(page):
                if link.startswith("FORM "):
                    forms.append({"screen": n, "action": lutece.normalize(link[5:])})
                elif depth < DEPTH:
                    push(link, n, depth + 1)
            for u in lutece.get_form_urls(page):
                if depth < DEPTH:
                    push(u, n + " [form GET]", depth + 1)
        b.close()
    return {"screens": out, "forms": sorted({(f["screen"], f["action"]) for f in forms}), "skipped": sorted(set(skipped)),
            "stats": {"screens": len(out), "forms": len({f["action"] for f in forms}), "skipped": len(set(skipped))}}


def crawl_fo(base):
    """Anonymous walk of the front office: starts at each inventory FO page (jsp/site/Portal.jsp?page=<id>) and
    follows front-office links only. No login: the FO is public. Do*/action urls are not followed (scenarios own
    the mutations). Output mirrors crawl(): {screens, forms, skipped}."""
    inv = lutece.load_json("artifacts/inventory.json", {"screens": []})
    in_scope = lutece.scope()
    starts = [s["url"] for s in inv.get("screens", []) if s.get("surface") == "fo" and in_scope(s["url"])]
    if not starts:
        return {"screens": [], "forms": [], "skipped": [], "stats": {"screens": 0, "forms": 0, "skipped": 0}}
    app_ids = {re.search(r"page=([\w-]+)", u).group(1) for u in starts if "page=" in u}
    """The XPage ids of the artefact under test: the FO crawl stays on them and their parameter sub-navigation, never
    wandering into the site's core CMS pages (page_id=N) or another plugin's XPage."""
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, args=lutece.chromium_args())
        page = b.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR").new_page()
        page.set_default_timeout(20000)
        lutece.observe(page)
        seen, queue, out, forms, skipped, per_path = {}, [], [], [], [], {}

        def push(u, src, depth):
            n = lutece.normalize(u)
            if not ("jsp/site/" in n or "Portal.jsp" in n) or n in seen:
                return
            m = re.search(r"[?&]page=([\w-]+)", n)
            if not m or m.group(1) not in app_ids:
                seen[n] = True; return
            if re.search(r"/(Do|do)[A-Z]\w*\.jsp|[?&]action=|logout|deconnexion", n, re.I):
                skipped.append(n); seen[n] = True; return
            path = n.split("?")[0] + "|" + (re.search(r"page=([\w-]+)", n).group(1) if "page=" in n else "")
            if per_path.get(path, 0) >= MAX_PER_PATH:
                seen[n] = True; return
            per_path[path] = per_path.get(path, 0) + 1
            seen[n] = True; queue.append((n, src, depth))

        for u in starts:
            push(u, "inventory", 0)
        while queue and len(out) < MAX_SCREENS:
            n, src, depth = queue.pop(0)
            t0 = time.perf_counter()
            try:
                resp = page.goto(lutece.url(n), wait_until="domcontentloaded")
            except Exception as e:  # noqa: BLE001
                out.append({"url": n, "from": src, "status": 0, "error": str(e)[:120]}); continue
            status = resp.status if resp else 0
            kind = lutece.classify(page, status)
            out.append({"url": n, "from": src, "status": status, "kind": kind, "title": page.title()[:80],
                        "ms": round((time.perf_counter() - t0) * 1000), "final": lutece.normalize(page.url), "surface": "fo"})
            for link in lutece.fo_links(page):
                if link.startswith("FORM "):
                    forms.append({"screen": n, "action": lutece.normalize(link[5:])})
                elif depth < DEPTH:
                    push(link, n, depth + 1)
        b.close()
    return {"screens": out, "forms": sorted({(f["screen"], f["action"]) for f in forms}), "skipped": sorted(set(skipped)),
            "stats": {"screens": len(out), "forms": len({f["action"] for f in forms}), "skipped": len(set(skipped))}}


def main():
    res = crawl(lutece.BASE)
    res["forms"] = [{"screen": s, "action": a} for s, a in res["forms"]]
    fo = crawl_fo(lutece.BASE)
    res["fo_screens"] = fo["screens"]
    res["fo_forms"] = [{"screen": s, "action": a} for s, a in fo["forms"]]
    res["stats"]["fo_screens"] = fo["stats"]["screens"]
    res["stats"]["fo_forms"] = fo["stats"]["forms"]
    (lutece.ARTIFACTS / "discovered.json").write_text(json.dumps(res, indent=1, ensure_ascii=False))
    print(json.dumps(res["stats"]))
    bad = [s for s in res["screens"] if s.get("kind") or s["status"] >= 400]
    for s in bad[:30]:
        print("  KO %s %s %s" % (s["status"], s.get("kind"), s["url"]))


if __name__ == "__main__":
    main()
