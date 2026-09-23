"""Lutece-specific helpers shared by every suite: base url, back-office login, error-page detection,
browser observability (console, page errors, failed requests, server timing), generic form filling."""
import json
import os
import pathlib
import re
import time
import urllib.parse

E2E = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = E2E / "artifacts"
BASE = os.environ.get("E2E_BASE", "http://localhost:18080/lutece").rstrip("/")
BENCH_HOSTS = sorted({"localhost", urllib.parse.urlsplit(BASE).hostname,
                      "lutece", "lutece7", "mail", "fakes", "oauth2", "solr", "elastic"})
"""Hosts the browser may reach: the application and the bench services (CAS and PayFiP pages of the fakes, the
OIDC provider, Mailpit, the search engines). Everything else is third party and fails to resolve at once."""
ADMIN = (os.environ.get("E2E_ADMIN", "admin"), os.environ.get("E2E_ADMIN_PASSWORD", "adminadmin"))
DB = {"host": os.environ.get("E2E_DB_HOST", "localhost"), "port": int(os.environ.get("E2E_DB_PORT", "3306")),
      "user": os.environ.get("E2E_DB_USER", "lutece"), "password": os.environ.get("E2E_DB_PASSWORD", "lutece"),
      "database": os.environ.get("E2E_DB_NAME", "lutece")}

ERROR_MARKERS = ("erreur technique", "une erreur est survenue", "technical error", "internal error", "erreur interne",
                 "contacter immédiatement l'administrateur", "please contact the administrator", "error 500", "error 404",
                 "http status 500", "context root not found", "srve0", "page introuvable", "ressource demandée est introuvable",
                 "état http 4", "état http 5", "erreur d'exécution", "stack trace", "an error occurred")
"""Substrings that identify a Lutece or Liberty error screen (French and English), wherever it is rendered."""
AUTH_MARKERS = ("veuillez vous identifier", "veuillez vous authentifier", "please authenticate", "vous devez vous authentifier",
                "session a expiré", "session has expired", "authentifiez-vous")
"""Wording of the AdminMessage shown when the session no longer carries an admin user."""

CONSOLE_ALLOW = tuple(re.compile(p) for p in (
    r"favicon\.ico",
    r"\[Deprecation\]",
    r"DevTools",
))
"""Console lines that never count as defects."""


def chromium_args():
    """Chromium flags of every suite. The bench must be reached as localhost (host port, or the runner
    sharing the application's network namespace): on any other plain-HTTP host Chromium honours the core's
    CSP `upgrade-insecure-requests` and fetches every asset over https. Every host but the bench's own fails to
    resolve at once: a page that loads a third-party script (translation widget, CDN, analytics) would otherwise
    wait for the network until the navigation timeout on an offline machine. Certificate errors are ignored: only the
    bench hosts resolve, and the fakes answer https with a test certificate (the core CSP upgrades a page's http calls)."""
    return ["--no-sandbox", "--disable-dev-shm-usage", "--disable-features=Translate,TranslateUI,OptimizationHints",
            "--no-first-run", "--no-default-browser-check", "--ignore-certificate-errors",
            "--host-resolver-rules=MAP * ~NOTFOUND, " + ", ".join("EXCLUDE %s" % h for h in BENCH_HOSTS)]


def offsite(u):
    """True for a url outside the bench: the browser never reaches it, so its failure is not a finding."""
    return urllib.parse.urlsplit(u).hostname not in BENCH_HOSTS


def url(path):
    """Absolute url of a webapp-relative path (jsp/admin/...)."""
    if path.startswith("http"):
        return path
    return BASE + "/" + path.lstrip("/")


def observe(page):
    """Attaches the observability collectors to a page: console errors and warnings, uncaught exceptions,
    failed or 4xx/5xx requests, and server timing of navigations. Read them in page.obs."""
    obs = {"console": [], "errors": [], "requests": [], "nav": [], "subs": []}
    page.obs = obs

    def on_console(msg):
        where = (msg.location or {}).get("url", "")
        if msg.type in ("error", "warning") and not any(a.search(msg.text) for a in CONSOLE_ALLOW) and not (where and offsite(where)):
            obs["console"].append({"type": msg.type, "text": msg.text[:300], "url": where[:200]})

    def on_response(resp):
        if resp.status >= 400:
            obs["requests"].append({"status": resp.status, "url": resp.url[:200]})
        req = resp.request
        if not req.is_navigation_request() and "/jsp/" in resp.url and resp.status < 400 and len(obs["subs"]) < 200:
            obs["subs"].append(resp.url[:200])
        if req.is_navigation_request() and req.frame == page.main_frame:
            t = req.timing
            mvc = ""
            try:
                raw = req.post_data_buffer
                body = raw.decode("latin-1") if raw else ""
                m = (re.search(r"(?:^|&)(action|view)=([^&]+)", body) or re.search(r"(?:^|&)(action|view)_([^=&]+)=", body)
                     or re.search(r'name="(action|view)(?:_([^"]+))?"\r?\n\r?\n([^\r\n]*)', body))
                if m:
                    mvc = "%s=%s" % (m.group(1), (m.group(2) or (m.group(3) if m.lastindex >= 3 else "")).strip())
            except Exception:  # noqa: BLE001 - binary body
                pass
            obs["nav"].append({"url": resp.url[:200], "status": resp.status, "mvc": mvc,
                               "ttfb_ms": round(t["responseStart"] - t["requestStart"], 1) if t["responseStart"] >= 0 else None,
                               "server_us": _server_us(resp)})

    page.on("console", on_console)
    page.on("pageerror", lambda e: obs["errors"].append(str(e)[:300]))
    page.on("requestfailed", lambda r: offsite(r.url) or obs["requests"].append({"status": 0, "url": r.url[:200], "error": (r.failure or "")[:120]}))
    page.on("response", on_response)
    return obs


def _server_us(resp):
    """Server elapsed time when the server exposes it (Server-Timing header), else None."""
    st = resp.headers.get("server-timing", "")
    m = re.search(r"dur=([\d.]+)", st)
    return float(m.group(1)) * 1000 if m else None


def reset_obs(page):
    """Empties the per-step collectors (console, errors, requests); navigations keep accumulating so the
    coverage tool sees every url a test reached."""
    for k in ("console", "errors", "requests"):
        page.obs[k].clear()


def bo_login(page, user=ADMIN[0], password=ADMIN[1]):
    """Signs in on the back office; returns True when the admin home is reached."""
    page.goto(url("jsp/admin/AdminLogin.jsp"), wait_until="domcontentloaded")
    page.fill('input[name="access_code"]', user)
    page.fill('input[name="password"]', password)
    with page.expect_navigation(wait_until="domcontentloaded"):
        page.click('button[type="submit"], input[type="submit"]')
    return "AdminLogin" not in page.url and "AdminMessage" not in page.url


def page_text(page):
    """Visible text of the page, whitespace-normalised."""
    try:
        return re.sub(r"\s+", " ", page.evaluate("() => document.body ? document.body.innerText : ''"))
    except Exception:  # noqa: BLE001 - context destroyed by a navigation: read again once settled
        page.wait_for_load_state("domcontentloaded")
        return re.sub(r"\s+", " ", page.evaluate("() => document.body ? document.body.innerText : ''"))


def text_hash(page):
    """Short hash of the visible text without digits: two different urls showing the same page (a message, an
    error) share it. The report flags groups of passed tests with one hash: the alarm against a blind oracle."""
    import hashlib
    txt = re.sub(r"\d+", "", page_text(page).lower())[:600]
    return hashlib.sha1(txt.encode()).hexdigest()[:10]


def classify(page, status=None):
    """Positive classification of what the browser shows, from the DOM, never from the url alone:
      'screen'        an authenticated back-office screen (admin menu bar rendered, no error wording)
      'confirmation'  a Lutece AdminMessage question (validate + cancel forms)
      'error' / 'warning' / 'info'   the other AdminMessage kinds (red card, orange card, blue card)
      'auth'          the "please authenticate" message: the session lost its admin user
      'login'         the login form
      'error-page'    Lutece/Liberty error wording (also when rendered inside the admin layout)
      'fo'            a front-office page (site layout: the preview, or a redirect to the portal)
      'truncated'     the admin header rendered but no footer: the response was cut by an error raised after the
                      buffer was flushed (a defect: the user sees an empty page instead of a message)
      'fragment'      an HTML fragment without layout (ajax/offcanvas content such as the site map)
      'public-form'   a session-less public page with a form (lost login/password, contact) or its inline answer
      front-office SiteMessage pages classify as 'error' / 'warning' / 'info' like their admin counterparts
      'http-NNN'      a 4xx/5xx status, 'blank' an empty body, 'unknown' none of the above."""
    if status and status >= 400:
        return "http-%d" % status
    info = page.evaluate("""() => ({
        menu: !!document.querySelector('#main-menu, #main-nav'),
        footer: !!document.querySelector('footer, .footer, #footer'),
        login: !!document.querySelector('form input[name="access_code"]') && !!document.querySelector('form input[name="password"]'),
        danger: !!document.querySelector('.card-status-start.bg-danger, .card-stamp-icon.bg-danger'),
        warning: !!document.querySelector('.card-status-start.bg-warning, .card-stamp-icon.bg-warning'),
        card: !!document.querySelector('.card-status-start, .card-stamp-icon'),
        forms: [...document.forms].filter(f => f.querySelector('button[type=submit], input[type=submit]')).length,
        fo: !!document.querySelector('body[id^=body-page], #main-banner-1, .lutece-portal, #portal-header, header[role=banner]'),
        foAlert: (() => { const t = document.querySelector('.alert .alert-title'); const box = t && t.closest('.alert');
                          return box && document.querySelector('.btn-back, form button[type=submit]') ? box.className : ''; })(),
        layout: !!document.querySelector('html > head > link[rel=stylesheet], html > head > script'),
        text: (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').trim().slice(0, 4000)})""")
    # header[role=banner] is the front-office page of a v7 site, where none of the v8 markers exist: without it
    # every front-office page of the older leg reads as a bare form and the comparison shows a rendering change
    # on pages nothing touched.
    low = info["text"].lower()
    if not low:
        return "blank"
    if info["login"] and not info["menu"]:
        return "login"
    # The lost-session message is an AdminMessage too, and it has to keep its own kind: read it before the card.
    if any(m in low for m in AUTH_MARKERS):
        return "auth"
    # A Lutece AdminMessage carries a card, and the card says which kind it is. Its wording belongs to the plugin:
    # a message that merely contains "une erreur est survenue" is not an error page, and reading the text first
    # made every such message unassertable — `expect_message: error` could never match.
    if info["card"]:
        if info["danger"]:
            return "error"
        if info["forms"] >= 2 or ( info["warning"] and info["forms"] >= 1 ):
            return "confirmation"
        if info["warning"]:
            return "warning"
        return "info"
    if any(m in low for m in ERROR_MARKERS):
        return "error-page"
    if info["menu"] and not info["footer"]:
        return "truncated"
    if info["menu"]:
        return "screen"
    if info["fo"] and not info["card"]:
        return "fo"
    if info["danger"]:
        return "error"
    if info["forms"] >= 2 or (info["warning"] and info["forms"] >= 1):
        return "confirmation"
    if info["warning"]:
        return "warning"
    if info["card"] or "AdminMessage.jsp" in page.url:
        return "info"
    if info["fo"]:
        return "fo"
    # A front-office SiteMessage has neither the admin layout nor the portal markers: it is the site_message
    # template alone, an <@cAlert> plus a back link. Without this it lands in 'unknown' and every front-office
    # robustness scenario fails while the application behaved exactly as intended.
    if info["foAlert"]:
        if "alert-danger" in info["foAlert"]:
            return "error"
        if "alert-warning" in info["foAlert"]:
            return "warning"
        return "info"
    if not info["layout"] and len(low) > 20:
        return "fragment"
    if info["forms"] >= 1 or "AdminForgot" in page.url or "AdminFormContact" in page.url or "AdminResetPassword" in page.url:
        return "public-form"
    return "unknown"


def error_kind(page, status=None):
    """None when the page is a normal screen or a Lutece message, else the classify() kind."""
    kind = classify(page, status)
    return None if kind in ("screen", "confirmation", "warning", "info") else kind


def admin_message(page):
    """The Lutece AdminMessage kind on the page ('error', 'confirmation', 'warning', 'info', 'auth') or None
    when the page is a screen, a login form or an error page."""
    kind = classify(page)
    return kind if kind in ("error", "confirmation", "warning", "info", "auth") else None


def admin_links(page):
    """Every admin link (href to jsp/admin) and every form action reachable on the page, absolute, unique."""
    return page.evaluate("""() => {
        const out = new Set();
        for (const a of document.querySelectorAll('a[href]')) { if (a.href.includes('/jsp/admin/')) out.add(a.href); }
        for (const f of document.querySelectorAll('form[action]')) {
            const a = typeof f.action === 'string' ? f.action : new URL(f.getAttribute('action'), document.baseURI).href;
            if (a.includes('/jsp/admin/')) out.add('FORM ' + a);
        }
        return [...out];
    }""")


def fo_links(page):
    """Every front-office link (href to jsp/site or Portal.jsp) and every form action on the page, absolute, unique.
    A relative skin link resolves against the page base; only same-site FO urls are kept."""
    return page.evaluate("""() => {
        const out = new Set();
        const isFo = u => u.includes('/jsp/site/') || u.includes('Portal.jsp');
        for (const a of document.querySelectorAll('a[href]')) { if (isFo(a.href)) out.add(a.href); }
        for (const f of document.querySelectorAll('form[action]')) {
            const a = typeof f.action === 'string' ? f.action : new URL(f.getAttribute('action'), document.baseURI).href;
            if (isFo(a)) out.add('FORM ' + a);
        }
        return [...out];
    }""")


def get_form_urls(page):
    """Urls a GET form would open when submitted with its current values (search, sort and filter forms): the
    parametrised listings the link crawl never reaches."""
    return page.evaluate("""() => [...document.forms].filter(f => (f.method || 'get').toLowerCase() === 'get').map(f => {
        const a = typeof f.action === 'string' ? f.action : new URL(f.getAttribute('action') || '', document.baseURI).href;
        if (!a.includes('/jsp/admin/')) return null;
        const q = new URLSearchParams(new FormData(f)).toString();
        return a.split('?')[0] + (q ? '?' + q : '');
    }).filter(u => u)""")


def nav_key(u, mvc=""):
    """Coverage key of a navigated url: the path plus its routing parameters (page=, view=, action=) only; a form that
    posts its action in a field instead of the url is keyed on that field (mvc, recorded from the request body)."""
    import urllib.parse
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(u).query)
    parts = ["%s=%s" % (k, q[k][0]) for k in ("page", "view", "action") if k in q]
    if mvc and not any(p.startswith(("view=", "action=")) for p in parts):
        parts.append(mvc)
    return normalize(u).split("?")[0] + ("?" + "&".join(parts) if parts else "")


def normalize(u):
    """Webapp-relative form of an admin url with its query, without the session and cache-busting noise."""
    u = u.split("#")[0]
    if u.startswith(BASE):
        u = u[len(BASE) + 1:]
    p = urllib.parse.urlsplit(u)
    q = [(k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True) if k not in ("token", "_", "ts")]
    return urllib.parse.urlunsplit(("", "", p.path, urllib.parse.urlencode(q), ""))


def shot(page, name, kind="png", full_page=True):
    """Screenshot into artifacts/shots/<name>.<kind>, full page unless told otherwise, returns the relative path.
    A full-page capture makes Chromium resize the viewport, which fires resize events a responsive widget reacts to;
    a scenario driving such a widget captures the viewport only (viewport_shots)."""
    d = ARTIFACTS / "shots"
    d.mkdir(parents=True, exist_ok=True)
    path = d / ("%s.%s" % (name, kind))
    try:
        page.screenshot(path=str(path), full_page=full_page, type="jpeg" if kind == "jpg" else kind, **({"quality": 70} if kind in ("jpg", "webp") else {}))
    except Exception as e:  # noqa: BLE001 - a screenshot never fails a test
        return "screenshot failed: %s" % str(e)[:80]
    return str(path.relative_to(ARTIFACTS))


def aria(page):
    """Aria snapshot (YAML of the accessibility tree) of the main content, a cheap structural fingerprint
    of the screen: stable across data changes when scoped to the layout, diff-able as text."""
    for sel in ("main", "#main", ".page-body", ".container-fluid", "body"):
        loc = page.locator(sel).first
        try:
            if loc.count():
                return loc.aria_snapshot()
        except Exception:  # noqa: BLE001
            continue
    return ""


def fill_form(page, form, values=None, seed="e2e"):
    """Fills every visible field of a form with plausible values (overridable with values={name: value}), date and
    time pickers (flatpickr, whose own input is hidden) through their API,
    returns the names filled. Hidden fields, submit buttons and CSRF tokens are left untouched."""
    values = values or {}
    loc = page.locator(form).first
    assert loc.count(), "no form matches %s on %s" % (form, normalize(page.url))
    return loc.evaluate("""(form, [values, seed]) => {
        const done = [];
        const stamp = seed + '_' + Date.now().toString(36);
        const password = 'E2e-Passw0rd!' + stamp;
        for (const el of form.elements) {
            if (el.name && !el.disabled && el._flatpickr) {
                const fp = el._flatpickr, v = values[el.name];
                if (v !== undefined) { fp.setDate(v, true); }
                else if (!el.value) { fp.setDate(fp.config.noCalendar ? '09:00' : (fp.config.enableTime ? '2030-01-15 09:00' : '2030-01-15'), true); }
                done.push(el.name);
                continue;
            }
            if (!el.name || el.disabled || el.type === 'hidden' || el.type === 'submit' || el.type === 'button') continue;
            if (el.offsetParent === null && el.type !== 'checkbox' && el.type !== 'radio') continue;
            const v = values[el.name];
            if (el.tagName === 'SELECT') {
                if (v !== undefined) el.value = v;
                else { const o = [...el.options].find(o => o.value && !o.disabled); if (o) el.value = o.value; }
            } else if (el.type === 'checkbox') { el.checked = v !== undefined ? !!v : true; }
            else if (el.type === 'radio') { if (v !== undefined ? el.value == v : !form.querySelector('input[name="' + el.name + '"]:checked')) el.checked = true; }
            else if (el.type === 'file') { continue; }
            else if (v !== undefined) { el.value = v; }
            else if (el.type === 'email' || /mail/i.test(el.name)) { el.value = stamp + '@e2e.local'; }
            else if (el.type === 'number' || /(^|_)(id|nb|order|level|size|max|min|width|height|interval|port|length|count|max_size_enter)(_|$)/i.test(el.name)) { el.value = el.min || '1'; }
            else if (el.type === 'date') { el.value = '2030-01-15'; }
            else if (el.type === 'password' || /password/i.test(el.name)) { el.value = password; }
            else if (/(key|code|name|login|access)/i.test(el.name)) { el.value = stamp.replace(/[^a-z0-9_]/gi, '').slice(0, 20); }
            else if (el.tagName === 'TEXTAREA') { el.value = 'Description ' + stamp; }
            else { el.value = 'E2E ' + stamp; }
            el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true}));
            done.push(el.name);
        }
        return done;
    }""", [values, seed])


def submit(page, form, button=None):
    """Submits a form (the given submit control, else its first one, else form.submit) and waits for the
    navigation. A missing form is an assertion failure, never a silent no-op."""
    loc = page.locator(form).first
    assert loc.count(), "no form matches %s on %s" % (form, normalize(page.url))
    if button:
        assert page.locator(form + " " + button).count(), "no control %s in %s" % (button, form)
    try:
        with page.expect_navigation(wait_until="domcontentloaded", timeout=30000):
            loc.evaluate("""(f, btn) => {
                const b = btn ? f.querySelector(btn) : f.querySelector('button[type=submit], input[type=submit], button:not([type])');
                if (b) b.click(); else f.requestSubmit ? f.requestSubmit() : f.submit(); }""", button)
        return True
    except Exception as e:  # noqa: BLE001 - a form answering in place (ajax, HTML5 validation) is not a failure
        if "navigation" in str(e).lower() or "Timeout" in str(e):
            return False
        raise


def sql(query, params=None):
    """Runs a query on the bench database, returns the rows (tuples). Source of truth for the scenarios."""
    import pymysql  # local import: the runner image installs it, the static tools do not need it
    conn = pymysql.connect(**DB, autocommit=True, charset="utf8mb4")
    try:
        with conn.cursor() as cur:
            if params:
                cur.execute(query, params)
            else:
                cur.execute(query)
            return cur.fetchall() if cur.description else []
    finally:
        conn.close()


def scope():
    """Predicate telling whether an admin url belongs to the bench scope. A plugin bench (inventory with `env`
    elements) tests only the artefact under test: its inventory paths, its `jsp/admin/plugins/<name>/` tree and its
    front-office page. E2E_SCOPE=all opens the whole site (the core bench, or a deliberate full crawl)."""
    inv = load_json("artifacts/inventory.json", {"screens": [], "actions": [], "features": []})
    scoped = os.environ.get("E2E_SCOPE", "target") != "all" and any(
        e.get("origin") == "env" for k in ("screens", "actions") for e in inv.get(k, []))
    if not scoped:
        return lambda u: True
    target = [e for k in ("screens", "actions") for e in inv.get(k, []) if e.get("origin", "target") == "target"]
    # Portal.jsp is every front office's path: an XPage is in scope by its page= name, never by the path alone,
    # or the bench's own mylutece pages would be judged as the artefact's. A portal page (page_id=) hosting a
    # portlet stays in scope: that is how a portlet is proven.
    paths = {e["url"].split("?")[0] for e in target if "Portal.jsp" not in e["url"]}
    pages = {re.search(r"[?&]page=([\w-]+)", e["url"]).group(1) for e in target if re.search(r"[?&]page=([\w-]+)", e["url"])}
    names = {f.get("plugin") for f in inv.get("features", []) if f.get("origin", "target") == "target"} - {None, "core"}
    marks = ["/plugins/%s/" % n for n in names]

    def in_scope(u):
        if not u:
            return False
        if "Portal.jsp" in u or "jsp/site/" in u:
            m = re.search(r"[?&]page=([\w-]+)", u)
            return (m.group(1) in pages | names) if m else ("page_id=" in u)
        return u.split("?")[0] in paths or any(m in u for m in marks)
    return in_scope


def render_check(page, kind=None):
    """Rendering defects a machine can see, so the visual review is left with what only eyes can judge: an
    unresolved template expression or i18n key shown to the user, a page served without its stylesheet, a broken
    image, a horizontal overflow, an empty content area. Returns a list of short findings, empty when the page
    renders cleanly. `kind` is the DOM classification: a fragment carries no layout of its own, so the stylesheet
    and empty-content rules do not apply to it."""
    findings = page.evaluate("""(kind) => {
        const out = [];
        const body = document.body;
        if (!body) { return ['no body']; }
        const txt = (body.innerText || '');
        // A marker shown as code (the list of ${...} a mail template accepts, a copy-to-clipboard snippet) is content.
        const code = [...body.querySelectorAll('code, pre, kbd, samp, textarea, .copy-content')].map(e => e.textContent || '').join('\\n');
        const count = (s, m) => s.split(m).length - 1;
        const raw = (txt.match(/#i18n\\{[^}]{0,60}\\}|\\$\\{[^}]{0,60}\\}|<#[a-z][^>]{0,40}>/g) || []).filter(m => count(txt, m) > count(code, m));
        if (raw.length) { out.push('unresolved template expression: ' + [...new Set(raw)].slice(0, 3).join(' ')); }
        const keys = (txt.match(/(?:^|\\s)[a-z][a-z0-9]*(?:\\.[a-z0-9_]+){2,}(?=\\s|$)/g) || [])
            .map(k => k.trim()).filter(k => !/\\.(jsp|html|js|css|png|jpg|xml|java)$/.test(k));
        if (keys.length) { out.push('i18n key shown raw: ' + [...new Set(keys)].slice(0, 3).join(' ')); }
        const standalone = kind !== 'fragment';
        if (standalone && (!document.styleSheets || document.styleSheets.length === 0)) { out.push('no stylesheet applied'); }
        const broken = [...document.images].filter(i => i.complete && i.naturalWidth === 0);
        if (broken.length) { out.push('broken image x' + broken.length + ': ' + broken.slice(0, 2).map(i => i.getAttribute('src')).join(' ')); }
        const de = document.documentElement;
        if (de.scrollWidth > de.clientWidth + 8) { out.push('horizontal overflow: ' + de.scrollWidth + '>' + de.clientWidth); }
        // Only structural roles name a page's content area: the v8 skin renders `<main id="main" role="main">`.
        // A bare `.content` class is what widget libraries give a collapsed panel body (a Swagger UI operation,
        // an accordion), and matching it reported a fully rendered viewer as an empty page. When a layout does
        // carry several candidates, the page is empty only when every one of them is.
        const mains = [...document.querySelectorAll('main, [role=main], #main, #content, .page-body')];
        const tallest = mains.length ? Math.max(...mains.map(m => m.getBoundingClientRect().height)) : null;
        if (standalone && tallest !== null && tallest < 40) { out.push('content area is empty'); }
        return out;
    }""", kind)
    return [f for f in findings if not _render_allowed(f)]


def _render_allowed(finding):
    """True when the bench declared this rendering finding as expected (`render_allow` in scenarios/screens.yaml).

    For a screen that shows a template expression on purpose — a plugin telling the user which tag to paste into
    a template, for instance. A declaration is a regex and carries its reason in the yaml comment beside it."""
    for pattern in (bench_rules().get("render_allow") or []):
        try:
            if re.search(pattern, finding):
                return True
        except re.error:
            continue
    return False


_RULES = {}


def console_allowed(text):
    """True when the bench declared this console message as expected (`console_allow` in scenarios/screens.yaml).

    For noise the artefact cannot remove and the migration did not introduce: a third-party asset the deployment
    has to allow in the site's Content-Security-Policy, a host unreachable from an offline bench. A declaration is
    a regex and carries its reason in the yaml comment beside it, so the finding stays visible instead of being
    silently dropped. Never use it for an error the artefact is responsible for."""
    for pattern in (bench_rules().get("console_allow") or []):
        try:
            if re.search(pattern, text or ""):
                return True
        except re.error:
            continue
    return False


# The v7 leg of run.sh compare runs the artefact inside a Lutece 7 site: its theme, its jQuery, its assets are
# the environment of that run, not the artefact under test, and their console noise says nothing about the
# migration. Failing a v7 screen on it turns every such screen into a false "corrigé" in the comparison.
V7_ENV_NOISE = tuple(re.compile(p, re.I) for p in (
    r"Refused to apply style", r"MIME type \('text/html'\)", r"jquery", r"\$ is not defined",
    r"Failed to load resource", r"favicon",
    # A v7 template asking for an empty asset path resolves to the site root, which the browser aborts. It is the
    # v7 theme's own markup, not a request the artefact makes.
    r"^https?://[^/]+/[^/]*/?$", r"ERR_ABORTED",
    # Assets and jQuery plugins the Lutece 7 theme used to ship and the site under test does not: a plugin
    # template written for v7 legitimately calls them, and their absence says nothing about the migration.
    r"bootstrap[\w.-]*\.(css|js)", r"\.tooltip is not a function", r"is not a function",
    r"images/poweredby\.svg", r"/images/[\w.-]+\.(svg|png|gif)$",
))


# The core's own assets, missing from the core itself: every bench of every artefact sees them, and no artefact
# can fix them. `page_template_styles_admin.min.css` imports `tabler-icons-filled.min.css`, which the core's
# webapp does not ship. Reported upstream; kept here so 25 benches do not each rediscover it as a defect.
CORE_ASSET_NOISE = tuple(re.compile(p, re.I) for p in (
    r"themes/shared/css/tabler-icons-filled\.min\.css",
))


FAILED_RESOURCE_ECHO = re.compile(r"Failed to load resource", re.I)
"""The console line the browser writes for a failed sub-request: it names no url, so it is judged with the requests."""


def console_noise(page, baseline=None):
    """Console messages and JS errors worth failing on: everything the bench did not declare, minus a baseline.
    On the v7 leg, the surrounding site's own noise is excluded (see V7_ENV_NOISE)."""
    base = baseline or {}
    core_asset = lambda t: any(p.search(t or "") for p in CORE_ASSET_NOISE)
    if os.environ.get("E2E_VERSION") == "v7":
        allowed = lambda t: console_allowed(t) or core_asset(t) or any(p.search(t or "") for p in V7_ENV_NOISE)
    else:
        allowed = lambda t: console_allowed(t) or core_asset(t)
    errs = [e for e in page.obs["errors"] if e not in (base.get("errors") or []) and not allowed(e)]
    noise = [c["text"] for c in page.obs["console"]
             if c["text"] not in (base.get("console") or []) and not allowed(c["text"])]
    bad = [r for r in page.obs["requests"]
           if (r["status"] != 0 or "error" in r) and r["url"] not in (base.get("requests") or [])
           and not allowed(r["url"])]
    # The browser echoes every failed sub-request in the console as a line that names no url. Once every failed
    # request of the page is accounted for, that echo adds nothing and must not fail the screen on its own —
    # otherwise an asset the bench declared is reported twice, once by name and once anonymously.
    if not bad:
        noise = [n for n in noise if not FAILED_RESOURCE_ECHO.search(n or "")]
    return errs, noise, bad


def bench_rules():
    """Per-bench screen lists from scenarios/screens.yaml (fragment, confirm, protected, deny, sessionless):
    regex fragments added to the generic defaults, so a plugin declares its popups without touching the tests."""
    if "r" not in _RULES:
        f = E2E / "scenarios" / "screens.yaml"
        if f.exists():
            import yaml
            _RULES["r"] = yaml.safe_load(f.read_text()) or {}
        else:
            _RULES["r"] = {}
    return _RULES["r"]


DECLARED_SKIP = "declared exclusion: "
"""Prefix of a skip the bench wrote down on purpose, as opposed to one the run caused (data consumed, state missing).

A suite where every test is skipped proves nothing, so the run fails on it (run.sh, `skipped_suites`). That gate must
not fire on exclusions the bench declared and justified: it exists to catch a suite that went silent by accident. The
prefix is the only thing that tells the two apart in the junit report, so every deliberate skip carries it."""


def screen_skip(url):
    """Reason the bench declares for not opening a screen standalone, or "" when it should be opened.

    `scenarios/screens.yaml`, key `skip`: a list of `{match: <regex on the url>, reason: <why>, versions: [...]}`. For
    a screen that is a step inside another artefact's flow and carries no standalone entry point — an XPage reached
    from a calendar with the chosen slot in its parameters, for instance. A reason is mandatory: the summary prints
    it, so a skipped screen stays visible instead of quietly disappearing from the coverage. `versions` restricts the
    rule to the versions listed, for a screen only one leg of the comparison cannot open: excluding it everywhere
    would drop a screen the other leg proves."""
    version = os.environ.get("E2E_VERSION", "v8")
    for rule in (bench_rules().get("skip") or []):
        vs = rule.get("versions")
        if vs and version not in vs:
            continue
        try:
            if rule.get("match") and re.search(rule["match"], url, re.I):
                return rule.get("reason") or "declared in screens.yaml without a reason"
        except re.error:
            continue
    return ""


def rule_re(name, default):
    """Compiled regex: the generic default alternation extended with the bench's own patterns for that rule."""
    extra = [p for p in (bench_rules().get(name) or []) if p]
    return re.compile("|".join([default] + extra), re.I)


FRAGMENT_DEFAULT = r"AdminMap\.jsp|AdminPagePreview\.jsp|GetAvailableInsertServices|DisplayInsertService|AdminThemePreview"
"""Screens that answer without the surrounding layout, extended per bench in scenarios/screens.yaml, key `fragment`."""

NOT_NORMAL = ("error-page", "blank", "auth", "login", "truncated")
"""Kinds no answer may ever have, whatever the surface: the assertion that survives a missing layout."""


def is_fragment(url):
    """True when the bench declared this url as answering without the surrounding layout.

    Two shapes do: a back-office popup body (offcanvas, insert service) and a front-office page the artefact
    serves as its own complete document — XPage.setStandalone, an embedded viewer, a print view. Neither carries
    the chrome classify() keys on, so their kind depends on what the page happens to contain (a widget that
    injects a form reads as 'public-form', the same page before the widget ran reads as 'unknown'). What stays
    provable is the negative: it must not be an error page, a blank body, a lost session or an HTTP error."""
    return bool(rule_re("fragment", FRAGMENT_DEFAULT).search(url or ""))



def screen_query(url):
    """Query string the bench declares for a screen that cannot be opened bare.

    `scenarios/screens.yaml`, key `params`: a list of `{match: <regex on the url>, query: "a=1&b=2"}`. A screen whose
    bean reads request parameters answers with an internal error when opened without them, and the suite would record
    a broken screen instead of testing it. `inventory.json` names those parameters per screen in `needs_params`."""
    for rule in (bench_rules().get("params") or []):
        try:
            if rule.get("match") and re.search(rule["match"], url, re.I):
                return rule.get("query") or ""
        except re.error:
            continue
    return ""

def mail_count(to, subject=None, wait_s=15, contains=None):
    """Number of messages in the Mailpit sink addressed to `to` (optionally with `subject` in the subject and
    `contains` anywhere in the message, Mailpit's free-text search), polling a few seconds because the Lutece mail
    daemon delivers asynchronously."""
    import urllib.request
    api = os.environ.get("E2E_MAIL_API", "http://localhost:18025")
    q = 'to:"%s"' % to + (' subject:"%s"' % subject if subject else "") + (' "%s"' % contains if contains else "")
    deadline = time.time() + wait_s
    n = 0
    while True:
        try:
            with urllib.request.urlopen(api + "/api/v1/search?" + urllib.parse.urlencode({"query": q}), timeout=5) as r:
                d = json.loads(r.read().decode())
                n = d.get("messages_count", d.get("total", len(d.get("messages", []))))
        except Exception:  # noqa: BLE001
            n = 0
        if n or time.time() > deadline:
            return n
        time.sleep(1)


def _fake_haystack(raw):
    """The log line plus its payload decoded, so a fragment matches the JSON the artefact really sent.

    The fakes log the request body as a JSON string, so `"demand_id": 42` appears escaped in the raw line and a
    literal search for it finds nothing."""
    out = raw
    try:
        body = json.loads(raw).get("body")
        if isinstance(body, str):
            out += "\n" + body
    except Exception:  # noqa: BLE001
        pass
    return out


def fake_log_lines(channel, contains=None, wait_s=15):
    """Lines of artifacts/fakes/<channel>.log that contain every fragment of `contains`.

    The fakes container appends one JSON line per request it received, so this is the oracle surface for
    everything the artefact sends outside: a notification, a CRM push, a payment call. Polls like mail_count
    because a Lutece daemon often sends after the response is already rendered."""
    p = E2E / "artifacts" / "fakes" / ("%s.log" % channel)
    wanted = [contains] if isinstance(contains, str) else list(contains or [])
    deadline = time.time() + wait_s
    while True:
        lines = []
        if p.exists():
            for raw in p.read_text(errors="replace").splitlines():
                if all(w in _fake_haystack(raw) for w in wanted):
                    lines.append(raw)
        if lines or time.time() > deadline:
            return lines
        time.sleep(1)


def load_json(rel, default=None):
    """Reads a JSON artifact (relative to e2e/) or returns default."""
    p = E2E / rel
    if not p.exists():
        return default
    return json.loads(p.read_text())


def now_ms():
    """Monotonic milliseconds."""
    return time.perf_counter() * 1000


def confirm(page):
    """Clicks the validate button of a Lutece confirmation message (the first form's submit) and waits."""
    with page.expect_navigation(wait_until="domcontentloaded", timeout=30000):
        page.locator("form button[type=submit], form input[type=submit]").first.click()
