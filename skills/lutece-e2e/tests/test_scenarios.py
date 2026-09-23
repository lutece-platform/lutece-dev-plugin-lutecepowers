"""Business scenarios described in scenarios/*.yaml and executed by a small step interpreter, so a new
feature costs a few YAML lines, never Python. Each scenario is one test; each step is checked and the
database is the source of truth for the assertions.

Step vocabulary (one key per step):
  goto: <path>                     open a webapp-relative url
  click: <selector|text=...>       click and wait for the navigation when one happens
  fill: {selector: value, ...}     set fields (selectors are CSS; {{var}} placeholders expanded)
  fill_form: <form selector>       auto-fill every visible field of a form (values: {name: v} overrides)
  submit: <form selector>          submit a form and wait for the navigation; {form: ..., button: <selector>} names the
                                   submit control when the form has several (reset buttons, per-row actions)
  submit_novalidate: <form>        same, bypassing the HTML5 client validation (to exercise the server-side checks)
  expect_url: <substring|[..]>     the current url must contain it (one of the list)
  confirm:                         click the validate button of a Lutece confirmation message
  confirm_if:                      same, only when a confirmation is displayed (some toggles ask only one way)
  expect_text: <substring>         the visible text must contain it (case-insensitive)
  expect_not_text: <substring>
  expect_message: <kind>           Lutece AdminMessage of that kind (confirmation, error, warning, info)
  expect_kind: <kind>              the DOM classification must be exactly this kind (auth, login, fo, fragment...)
  expect_ok:                       a real screen or Lutece message (never error/auth/login/error-page); console noise is
                                   recorded in the result (front_noise) and judged by the screens suite, once per screen
  sql: {query: ..., expect: v}     the first cell must equal expect; variants: not_expect: v, expect_var: name (equals a
                                   stored variable), not_expect_var: name, min: n (numeric lower bound),
                                   contains/not_contains: text (a substring of the stored value)
  expect_dom: {selector: ..., count: n | min: n | contains: text | not_contains: text | attr: name, var: v | not_var: v}
                                   state read on the screen (attr compares an attribute of the first match with a variable)
  dom_set: {var: name, selector: ..., attr: name | text}   store an attribute (or the text) of the first match
  mail: {to: addr, min: n}         at least n mails to that address reached the bench's SMTP sink (Mailpit);
                                   {subject: text} restricts to a subject; state that lives in the mail queue
  http: {url: path, accept: type, method: GET, expect_status: n, contains: text|[text], not_contains: ...,
         (an http call proves an endpoint, not an admin screen or action: those are proven through the browser)
         poll: seconds, multipart: {field: value|path}, capture: var,
         sign: {elements: [...], private_key: ...}}
                                   `capture` stores the answer's body in a variable, which chains two REST calls.
                                   `multipart` sends a multipart/form-data body — a value naming a file under
                                   e2e/ is sent as that file, anything else as a text field — which is how an
                                   upload endpoint is called.
                                   `sign` adds a Lutece signrequest signature — sha1 of the named parameters'
                                   values in order, then the private key, then the timestamp, in the
                                   Lutece-Request-Signature and Lutece-Request-Timestamp headers. Without it a
                                   protected REST endpoint answers 401 and the scenario proves nothing; with a
                                   deliberately wrong key it proves the refusal.
         poll: seconds}          `poll` repeats the call until the assertions hold (an asynchronous action:
                                   a daemon, an @Asynchronous task); without it one call, one verdict
                                   call an endpoint as a client would, not as a browser: the Accept header is yours,
                                   the answer is asserted on its status and its body. For a REST api, whose consumers
                                   are programs; `body` and `headers` complete a POST. {fresh: true} calls as a
                                   brand-new visitor (own cookie jar, so the server opens a new session) and
                                   {repeat: n} calls n times, asserting on the last answer: what a per-session
                                   counter or a rate limit needs. {follow: false} stops at the redirect, which
                                   {location_contains: text} then asserts on
  fake_log: {channel: name, contains: text|[text], min: n}
                                   at least n requests reached that fake (E2E_FAKES=1): cas, crm, tipi, notifygru,
                                   identitystore, ants, and the channels of harness/fakes/extra/. `contains`
                                   filters on the logged JSON line, payload included, so it proves WHAT was sent;
                                   {absent: true} asserts nothing matching was sent
  sql_set: {var: name, query: ...} store the first cell of the query in a variable
  sql_exec: <statement>            arrange data directly in the database (only for what the UI cannot create)
  set: {var: value}                define variables; {{rand}} is a per-scenario random token
  shot: <name>                     screenshot
  upload: {selector: ..., file: ...}   set a file input (path relative to e2e/)
  download: <form selector>        submit a form that answers with a file; records its name and size
  login: {user: ..., password: ...}    log out then sign in as another admin (use with isolated: true)
  login_fo: {user: ..., password: ..., provider: mylutece-database}
                                   sign a front-office user in through mylutece (use with anonymous: true); the
                                   step fails when the login form is still there afterwards
  click_if: <selector>             click when the element exists, else no-op (optional links)
  wait: <selector>                 wait for an element (off-canvas / ajax-loaded form) before filling it
Scenario keys: id, title (shown by the report), description (optional, `>-` block), req (Lutece right), anonymous, versions (optional, e.g. [v8]: skipped on the v7 leg of run.sh compare), ends_on (blank | error-page | truncated: the last screen is that on purpose, say why in description; otherwise such an ending fails the scenario), steps.
Any step value may be a per-version mapping, {v7: ..., v8: ...}: the value for E2E_VERSION is used. Preferred over
`versions:` when the function exists on both sides and only its url or selector changed (a JSP turned MVC view).
Variables: {{rand}} (6 lowercase alphanumerics), {{rand_int}} (5-6 digits, for numeric keys), {{base}} and anything set by set/sql_set/dom_set.
A scenario with `serial: true` changes global settings and runs alone after the parallel pass. A scenario with `anonymous: true` runs without any session (public screens). A scenario with `isolated: true` logs in on its own session (mandatory when it logs out or changes the password),
so it never invalidates the session shared by the other tests of the worker.

Mechanical rule (checked at collection, before any browser starts): every mutation step (submit, confirm,
download, a click on a Do*/action/button control) must be followed, within the next two non-navigation steps,
by a state oracle: sql, expect_dom, expect_text, expect_not_text or expect_message. A scenario that breaks the
rule is collected as a failing test that names the step: "the screen looked normal" is never a proof.
"""
import os
import pathlib
import random
import hashlib
import re
import urllib.parse
import time
import string

import pytest
import yaml

import lutece

SCENARIOS = lutece.E2E / "scenarios"


MUTATION = ("submit", "submit_novalidate", "confirm", "confirm_if")
"""download proves itself (non-empty file), so it is not listed."""
STATE_ORACLE = ("sql", "expect_dom", "mail", "fake_log", "http", "download")
"""Reads the state the mutation was meant to change: a row, the DOM of the listing, a mail, a call, a file."""
WEAK_ORACLE = ("expect_text", "expect_not_text", "expect_html", "expect_message", "expect_kind")
"""Reads the screen that followed: it says the application answered, not what it did. Never enough alone after a mutation."""
ORACLE = STATE_ORACLE + WEAK_ORACLE
NEUTRAL = ("goto", "expect_ok", "shot", "expect_url", "sql_set", "set", "wait", "dom_set")
CLICK_MUTATION = re.compile(r"Do[A-Z]|action|button|submit|Unassign|Remove|Move", re.I)
URL_LIKE = re.compile(r"\.jsp\b|https?://|[?&][a-z_]+=", re.I)


def validate(sc):
    """Returns the list of rule violations of a scenario (empty when it is acceptable)."""
    steps = [(list(st)[0], st[list(st)[0]]) for st in sc.get("steps", [])]
    errors = []
    unproven = False
    for i, (k, arg) in enumerate(steps):
        if k == "expect_text" and isinstance(arg, str) and URL_LIKE.search(arg):
            errors.append("step %d expect_text asserts on a url or a JSP name (%r): assert on what the page says, not where it is" % (i, arg))
        if k in STATE_ORACLE:
            unproven = False
        if k == "sql_exec" and unproven:
            errors.append("step %d sql_exec between a mutation and its proof: arrange data before the mutation or after its state oracle, never in between" % i)
        is_mut = k in MUTATION or (k in ("click", "click_if") and isinstance(arg, str) and CLICK_MUTATION.search(arg))
        if not is_mut:
            continue
        unproven = True
        window, j = [], i + 1
        while j < len(steps) and len(window) < 3:
            if steps[j][0] not in NEUTRAL:
                window.append(steps[j][0])
            j += 1
        if not any(w in STATE_ORACLE for w in window):
            what = "only a weak oracle (%s)" % "/".join(w for w in window if w in WEAK_ORACLE) if any(w in WEAK_ORACLE for w in window) else "no oracle"
            errors.append("step %d %s: %s within the next steps; a mutation is proven by its state (%s)" % (i, k, what, "/".join(STATE_ORACLE)))
    return errors


def _load():
    out = []
    for f in sorted(SCENARIOS.glob("*.yaml")):
        if f.name.startswith("coverage-"):
            continue
        doc = yaml.safe_load(f.read_text()) or {}
        for sc in doc.get("scenarios", []):
            sc["_file"] = f.stem
            sc["_invalid"] = validate(sc)
            out.append(sc)
    return out


def _body(resp):
    """The answer as text, even when its bytes are not the utf-8 the response claims.

    A response served in one encoding and declared in another is a defect the scenario should be able to assert
    on; `resp.text()` raising UnicodeDecodeError only hides it behind a broken step."""
    try:
        return resp.text()
    except Exception:
        return resp.body().decode("utf-8", errors="replace")


VERSIONS = ("v7", "v8")


def _expand(value, vars_):
    """Substitutes {{vars}} and resolves per-version values: a mapping whose keys are all versions
    ({v7: <url>, v8: <url>}) becomes the value for E2E_VERSION, so one scenario plays the same functional
    path on both legs of run.sh compare even where the migration changed the urls or the selectors."""
    if isinstance(value, str):
        return re.sub(r"\{\{(\w+)\}\}", lambda m: str(vars_.get(m.group(1), m.group(0))), value)
    if isinstance(value, dict):
        if value and all(str(k) in VERSIONS for k in value):
            version = os.environ.get("E2E_VERSION", "v8")
            assert version in value, "step has no value for %s (has %s)" % (version, ", ".join(value))
            return _expand(value[version], vars_)
        return {_expand(k, vars_): _expand(v, vars_) for k, v in value.items()}
    if isinstance(value, list):
        return [_expand(v, vars_) for v in value]
    return value


def _click(page, target):
    """Clicks the first match; a missing element is a failure, a click without navigation is not."""
    loc = page.get_by_text(target[5:], exact=False).first if target.startswith("text=") else page.locator(target).first
    assert loc.count(), "nothing matches %s on %s" % (target, lutece.normalize(page.url))
    try:
        with page.expect_navigation(wait_until="domcontentloaded", timeout=15000):
            if loc.is_visible():
                loc.click()
            else:
                loc.evaluate("e => e.click()")
    except Exception as e:  # noqa: BLE001 - in-page action without navigation
        if "navigation" not in str(e).lower():
            raise


def _dom_value(loc, attr):
    """Text, live value (form controls) or attribute of an element."""
    if attr == "text":
        return loc.inner_text().strip()
    if attr == "value":
        return loc.evaluate("e => 'value' in e ? e.value : e.getAttribute('value')")
    return loc.get_attribute(attr)


PROBE_PATH = "jsp/e2e/"
"""Where a bench puts its own probe pages: they belong to the bench, never to the artefact under test."""

PROBE_BROKEN = re.compile(r"org\.apache\.jasper|Unable to compile|cannot be resolved|PWC6033|JSPG0049E", re.I)
"""A JSP the container could not compile. On the v7 leg a probe written against the v8 APIs ends here."""


def _probe_guard(page, target, resp):
    """Stops the scenario when the bench's own probe page did not compile on this leg.

    A probe is bench code, not the artefact: when it does not run, the scenario proves nothing about the artefact,
    and letting it fail would read in the comparison as a defect this version has and the other fixed. A probe
    written with the v8 APIs cannot compile on a v7 site, which is a bench limit, so the scenario is declared out
    of that leg instead of being counted red. On the version the bench is written for, the same broken probe is a
    defect of the bench and stays red: a silent skip there would hide that nothing was judged at all."""
    if PROBE_PATH not in (target or ""):
        return
    status = resp.status if resp else 0
    if status < 500 and not PROBE_BROKEN.search(page.content()[:4000]):
        return
    if os.environ.get("E2E_VERSION", "v8") == "v7":
        pytest.skip(lutece.DECLARED_SKIP + "the bench's probe page does not run on the v7 leg (HTTP %s): a probe "
                    "written with the v8 APIs cannot compile there. Give the bench a probe v7 compiles, or accept "
                    "that this scenario is judged on v8 only" % (status or "compile error"))
    raise AssertionError("the bench's own probe page did not run (HTTP %s): fix the probe, it is bench code and "
                         "nothing about the artefact can be read from this" % (status or "compile error"))


def run_step(page, step, vars_, record):
    """Executes one step; raises AssertionError with a readable message on failure."""
    (key, arg), = step.items() if len(step) == 1 else [(k, v) for k, v in step.items() if k != "name"][:1]
    arg = _expand(arg, vars_)
    if key == "goto":
        resp = page.goto(lutece.url(arg), wait_until="domcontentloaded")
        _probe_guard(page, arg, resp)
    elif key == "click":
        _click(page, arg)
    elif key == "fill":
        for sel, val in arg.items():
            loc = page.locator(sel).first
            assert loc.count(), "nothing matches %s on %s" % (sel, lutece.normalize(page.url))
            tag = loc.evaluate("e => e.tagName + ':' + (e.type || '')")
            visible = loc.is_visible()
            if tag.startswith("SELECT"):
                if visible:
                    loc.select_option(str(val))
                else:
                    loc.evaluate("(e, v) => { e.value = v; e.dispatchEvent(new Event('change', {bubbles: true})); }", str(val))
                    assert loc.evaluate("e => e.value") == str(val), "option %r not available in %s" % (val, sel)
            elif tag.endswith(":checkbox") or tag.endswith(":radio"):
                if visible:
                    loc.set_checked(bool(val))
                else:
                    loc.evaluate("(e, v) => { e.checked = !!v; e.dispatchEvent(new Event('change', {bubbles: true})); }", bool(val))
            elif visible:
                loc.fill(str(val))
            else:
                loc.evaluate("""(e, v) => {
                    const ed = e.tagName === 'TEXTAREA' && window.tinymce && e.id ? tinymce.get(e.id) : null;
                    if (ed) { ed.setContent(v); ed.save(); }
                    e.value = v; e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true})); }""", str(val))
    elif key == "http":
        # A REST endpoint is called by a client, not by a browser: the browser's Accept header makes the server
        # negotiate a representation nobody asked for. This step issues the request the client would.
        method = (arg.get("method") or "GET").upper()
        headers = dict(arg.get("headers") or {})
        if arg.get("accept"):
            headers["Accept"] = arg["accept"]
        # `fresh` issues the request as a brand-new visitor: its own cookie jar, so the server opens a new
        # session instead of reusing the scenario's. `repeat` issues it n times, which is what a test of a
        # per-session counter or of a rate limit needs; only the last answer is asserted on.
        times = int(arg.get("repeat", 1))
        # `follow: false` stops at the redirect itself, so the bench can assert WHERE the application sends the
        # client without leaving the bench — a target outside it would simply not answer.
        # `sign` makes the call carry a Lutece signrequest signature, which is the only way a bench can drive an
        # endpoint its plugin protects. The scheme is the library's: sha1 of the values of the signature elements
        # in the declared order, then the private key, then the timestamp in epoch milliseconds, lowercase hex,
        # carried by Lutece-Request-Signature and Lutece-Request-Timestamp. An element the request does not carry
        # contributes nothing, exactly as HeaderHashAuthenticator drops a null parameter — so the values come from
        # the query string and, for a urlencoded body, from that body; a multipart part is never a signature value.
        if arg.get("sign"):
            sign = arg["sign"]
            params = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(arg["url"]).query, keep_blank_values=True))
            if isinstance(arg.get("body"), str) and "multipart/" not in str(headers.get("Content-Type", "")):
                params.update(dict(urllib.parse.parse_qsl(arg["body"], keep_blank_values=True)))
            stamp = str(int(time.time() * 1000))
            raw = "".join(params[e] for e in (sign.get("elements") or []) if e in params)
            headers["Lutece-Request-Timestamp"] = stamp
            headers["Lutece-Request-Signature"] = hashlib.sha1(
                (raw + str(sign.get("private_key", "")) + stamp).encode("utf-8")).hexdigest()

        fetch = {"method": method, "headers": headers, "data": arg.get("body")}
        # `multipart` sends a multipart/form-data body, which is how an upload endpoint is called. A value that
        # names a file under e2e/ is read and sent as that part; anything else is sent as a text field. The
        # container builds the boundary, so no Content-Type is set here.
        if arg.get("multipart"):
            parts = {}
            for name, value in arg["multipart"].items():
                path = lutece.E2E / str(value)
                parts[name] = ({"name": path.name, "mimeType": "application/octet-stream",
                                "buffer": path.read_bytes()} if path.is_file() else str(value))
            fetch["multipart"] = parts
            fetch.pop("data", None)
        if arg.get("follow") is False:
            fetch["max_redirects"] = 0
        def call():
            body = status = location = None
            for _ in range(times):
                if arg.get("fresh"):
                    ctx = page.context.browser.new_context()
                    try:
                        resp = ctx.request.fetch(lutece.url(arg["url"]), **fetch)
                        body, status, location = _body(resp), resp.status, resp.headers.get("location", "")
                    finally:
                        ctx.close()
                else:
                    resp = page.request.fetch(lutece.url(arg["url"]), **fetch)
                    body, status, location = _body(resp), resp.status, resp.headers.get("location", "")
            return body, status, location

        def check(body, status, location):
            if arg.get("location_contains"):
                assert arg["location_contains"] in location, "http %s %s: redirected to %r, expected it to contain %r" % (
                    method, arg["url"], location, arg["location_contains"])
            if arg.get("expect_status"):
                assert status == int(arg["expect_status"]), "http %s %s: status %d, expected %s\n%s" % (
                    method, arg["url"], status, arg["expect_status"], body[:300])
            for needle in ([arg["contains"]] if isinstance(arg.get("contains"), str) else (arg.get("contains") or [])):
                assert needle in body, "http %s %s: %r absent from the answer\n%s" % (method, arg["url"], needle, body[:300])
            for needle in ([arg["not_contains"]] if isinstance(arg.get("not_contains"), str) else (arg.get("not_contains") or [])):
                assert needle not in body, "http %s %s: %r present in the answer\n%s" % (method, arg["url"], needle, body[:300])

        # `poll`: an asynchronous effect (a daemon pass, an @Asynchronous task) is proven by asking until it shows,
        # within a bound; the last failure is the one reported.
        deadline = time.time() + float(arg.get("poll", 0))
        while True:
            body, status, location = call()
            record["http_status"] = status
            try:
                check(body, status, location)
                # `capture` stores the answer's body in a variable, which is what chains two REST calls: an
                # endpoint that returns the key of what it just created, then the endpoint that reads or deletes
                # it. Whitespace is stripped, because a plain-text answer often carries a trailing newline.
                if arg.get("capture"):
                    vars_[arg["capture"]] = body.strip()
                record.setdefault("rest_calls", []).append({"verb": method, "path": urllib.parse.urlsplit(arg["url"]).path.lstrip("/"),
                                                            "asserted": bool(arg.get("expect_status") or arg.get("contains") or arg.get("not_contains") or arg.get("location_contains"))})
                break
            except AssertionError:
                if time.time() >= deadline:
                    raise
                time.sleep(2)
    elif key == "fake_log":
        lines = lutece.fake_log_lines(arg["channel"], arg.get("contains"))
        if arg.get("absent"):
            assert not lines, "fake_log %s: %d request(s) matched %r, expected none:\n%s" % (
                arg["channel"], len(lines), arg.get("contains"), "\n".join(lines[:3]))
        else:
            assert len(lines) >= int(arg.get("min", 1)), (
                "fake_log %s: %d request(s) matching %r, expected at least %s (is E2E_FAKES=1 and is the "
                "artefact pointed at http://fakes:9030/%s ?)" % (
                    arg["channel"], len(lines), arg.get("contains"), arg.get("min", 1), arg["channel"]))
    elif key == "mail":
        n = lutece.mail_count(arg["to"], arg.get("subject"))
        assert n >= int(arg.get("min", 1)), "mail: %d message(s) to %s (subject %r), expected at least %s" % (
            n, arg["to"], arg.get("subject"), arg.get("min", 1))
    elif key == "fill_form":
        form = arg if isinstance(arg, str) else arg["form"]
        filled = lutece.fill_form(page, form, arg.get("values") if isinstance(arg, dict) else None, seed=vars_["rand"])
        record.setdefault("filled", []).append(filled)
    elif key == "submit":
        if isinstance(arg, dict):
            lutece.submit(page, arg["form"], arg.get("button"))
        else:
            lutece.submit(page, arg)
    elif key == "submit_novalidate":
        page.evaluate("(sel) => { const f = document.querySelector(sel); if (f) f.noValidate = true; }", arg)
        lutece.submit(page, arg)
    elif key == "expect_url":
        wanted = arg if isinstance(arg, list) else [arg]
        assert any(w in page.url for w in wanted), "url %s contains none of %s" % (page.url, wanted)
    elif key == "confirm":
        lutece.confirm(page)
    elif key == "confirm_if":
        if lutece.admin_message(page) == "confirmation":
            lutece.confirm(page)
    elif key == "expect_text":
        txt = lutece.page_text(page)
        assert str(arg).lower() in txt.lower(), "text %r not on screen (%s)" % (arg, txt[:200])
    elif key == "expect_not_text":
        assert str(arg).lower() not in lutece.page_text(page).lower(), "text %r present" % arg
    elif key == "expect_html":
        assert str(arg).lower() in page.content().lower(), "html substring %r absent from the rendered page" % arg
    elif key == "expect_message":
        got = lutece.admin_message(page)
        assert got == arg, "AdminMessage %s expected, got %s (%s)" % (arg, got, lutece.page_text(page)[:200])
    elif key == "expect_kind":
        got = lutece.classify(page)
        # `fo` names the front office as a family: a public page that carries a form (search, login) classifies
        # as `public-form` and is the same kind of page — the v7 core's home does, the v8 one does not.
        family = {"fo": ("fo", "public-form")}.get(arg, (arg,))
        assert got in family, "kind %s expected, got %s (%s)" % (arg, got, lutece.page_text(page)[:160])
    elif key == "expect_ok":
        kind = lutece.classify(page)
        # A page the bench declared as answering without the surrounding layout has no stable kind: judge it on
        # the negative, exactly as the screens and fo suites do, instead of forcing the scenario to guess which
        # of 'public-form' or 'unknown' the embedded widget will have produced by the time the step runs.
        if lutece.is_fragment(lutece.normalize(page.url)):
            assert kind not in lutece.NOT_NORMAL and not kind.startswith("http-"), \
                "standalone document answered %s (%s)" % (kind, lutece.page_text(page)[:200])
        else:
            assert kind in ("screen", "confirmation", "warning", "info", "fo", "fragment", "public-form"), "not a normal screen: %s (%s)" % (kind, lutece.page_text(page)[:200])
        if page.obs["errors"] or page.obs["console"]:
            record.setdefault("front_noise", []).append({"url": lutece.normalize(page.url), "js": page.obs["errors"][:2], "console": [c["text"][:100] for c in page.obs["console"]][:2]})
    elif key == "sql":
        rows = lutece.sql(arg["query"])
        got = rows[0][0] if rows else None
        if "expect" in arg:
            assert str(got) == str(arg["expect"]), "sql %s -> %r, expected %r" % (arg["query"], got, arg["expect"])
        if "not_expect" in arg:
            assert str(got) != str(arg["not_expect"]), "sql %s -> %r, expected a change" % (arg["query"], got)
        if "expect_var" in arg:
            assert str(got) == str(vars_.get(arg["expect_var"])), "sql %s -> %r, expected %r" % (arg["query"], got, vars_.get(arg["expect_var"]))
        if "not_expect_var" in arg:
            assert str(got) != str(vars_.get(arg["not_expect_var"])), "sql %s -> %r, expected a change from that value" % (arg["query"], got)
        # A stored value whose exact form the bench must not pin — a url built from the request, a timestamp —
        # is still worth asserting on: what matters is the part the feature decided.
        if "contains" in arg:
            assert str(arg["contains"]) in str(got), "sql %s -> %r, expected it to contain %r" % (arg["query"], got, arg["contains"])
        if "not_contains" in arg:
            assert str(arg["not_contains"]) not in str(got), "sql %s -> %r, expected it not to contain %r" % (arg["query"], got, arg["not_contains"])
        if "min" in arg:
            assert got is not None and float(got) >= float(arg["min"]), "sql %s -> %r, expected >= %s" % (arg["query"], got, arg["min"])
    elif key == "expect_dom":
        loc = page.locator(arg["selector"])
        n = loc.count()
        if "count" in arg:
            assert n == int(arg["count"]), "%s: %d element(s), expected %s" % (arg["selector"], n, arg["count"])
        if "min" in arg:
            assert n >= int(arg["min"]), "%s: %d element(s), expected at least %s" % (arg["selector"], n, arg["min"])
        if "attr" in arg:
            assert n, "%s: no element" % arg["selector"]
            got = _dom_value(loc.first, arg["attr"])
            if "var" in arg:
                assert str(got) == str(vars_.get(arg["var"])), "%s@%s = %r, expected %r" % (arg["selector"], arg["attr"], got, vars_.get(arg["var"]))
            if "not_var" in arg:
                assert str(got) != str(vars_.get(arg["not_var"])), "%s@%s still %r" % (arg["selector"], arg["attr"], got)
            if "equals" in arg:
                assert str(got) == str(arg["equals"]), "%s@%s = %r, expected %r" % (arg["selector"], arg["attr"], got, arg["equals"])
        if "contains" in arg or "not_contains" in arg:
            assert n, "%s: no element" % arg["selector"]
            txt = " ".join(loc.all_inner_texts()).lower()
            if "contains" in arg:
                assert str(arg["contains"]).lower() in txt, "%s does not contain %r (%s)" % (arg["selector"], arg["contains"], txt[:160])
            if "not_contains" in arg:
                assert str(arg["not_contains"]).lower() not in txt, "%s contains %r" % (arg["selector"], arg["not_contains"])
    elif key == "dom_set":
        loc = page.locator(arg["selector"]).first
        assert loc.count(), "%s: no element" % arg["selector"]
        vars_[arg["var"]] = _dom_value(loc, arg.get("attr", "text"))
    elif key == "sql_exec":
        lutece.sql(arg)
    elif key == "sql_set":
        rows = lutece.sql(arg["query"])
        vars_[arg["var"]] = rows[0][0] if rows else None
    elif key == "set":
        vars_.update(arg)
    elif key == "shot":
        record.setdefault("screenshots", []).append(lutece.shot(page, arg, "jpg"))
    elif key == "upload":
        page.locator(arg["selector"]).first.set_input_files(str(lutece.E2E / arg["file"]))
    elif key == "download":
        with page.expect_download(timeout=30000) as dl:
            page.evaluate("""(sel) => { const f = document.querySelector(sel);
                const b = f.querySelector('button[type=submit], input[type=submit]'); if (b) b.click(); else f.submit(); }""", arg)
        d = dl.value
        path = lutece.ARTIFACTS / "downloads" / (vars_["rand"] + "_" + d.suggested_filename)
        path.parent.mkdir(parents=True, exist_ok=True)
        d.save_as(str(path))
        record.setdefault("downloads", []).append({"name": d.suggested_filename, "bytes": path.stat().st_size})
        assert path.stat().st_size > 0, "empty download %s" % d.suggested_filename
    elif key == "login_fo":
        provider = arg.get("provider", "mylutece-database")
        page.goto(lutece.url("jsp/site/Portal.jsp?page=mylutece&action=login&auth_provider=" + provider), wait_until="domcontentloaded")
        assert page.locator('input[name="username"]').count(), "no mylutece login form for provider %s on %s" % (provider, lutece.normalize(page.url))
        page.fill('input[name="username"]', str(arg["user"]))
        page.fill('input[name="password"]', str(arg["password"]))
        with page.expect_navigation(wait_until="domcontentloaded"):
            page.locator('form:has(input[name="username"]) button[type="submit"], form:has(input[name="username"]) input[type="submit"]').first.click()
        txt = lutece.page_text(page)
        assert not page.locator('input[name="username"]').count(), "front-office login as %s refused: %s" % (arg["user"], txt[:160])
    elif key == "login":
        page.goto(lutece.url("jsp/admin/DoAdminLogout.jsp"), wait_until="domcontentloaded")
        ok = lutece.bo_login(page, arg["user"], arg["password"])
        txt = lutece.page_text(page).lower()
        assert ok or "ModifyDefaultUserPassword" in page.url or "password" in txt or "mot de passe" in txt, "login as %s failed: %s %s" % (arg["user"], page.url, txt[:120])
    elif key == "wait":
        page.wait_for_selector(arg, state="attached", timeout=15000)
    elif key == "click_if":
        if page.locator(arg).count():
            _click(page, arg)
    else:
        raise AssertionError("unknown step %s" % key)


def _params():
    """One pytest param per scenario; scenarios flagged `serial: true` carry the marker run.sh executes alone
    (they change settings shared by every session: security parameters, e-mail pattern, feature groups...)."""
    out = []
    for sc in _load():
        marks = [pytest.mark.serial] if sc.get("serial") else []
        out.append(pytest.param(sc, id="%s.%s" % (sc["_file"], sc["id"]), marks=marks))
    return out


@pytest.mark.parametrize("sc", _params())
def test_scenario(bo, browser, request, record, sc):
    if sc.get("isolated") or sc.get("anonymous"):
        ctx = browser.new_context(viewport={"width": 1440, "height": 1000}, locale="fr-FR")
        bo = ctx.new_page()
        lutece.observe(bo)
        request.node.page = bo
        if not sc.get("anonymous"):
            assert lutece.bo_login(bo), "login failed"
    # `versions: [v8]` on a scenario written against screens the migration introduced (MVC views, new urls): on
    # the v7 leg of `run.sh compare` it is skipped and reported as such, instead of failing at its first step
    # and reading as a regression fixed by v8.
    record["scenario"] = sc["id"]
    record["title"] = sc.get("title", sc["id"])
    record["requirement"] = sc.get("req", "")
    record["description"] = sc.get("description", "")
    version = os.environ.get("E2E_VERSION", "v8")
    if sc.get("versions") and version not in [str(v) for v in sc["versions"]]:
        pytest.skip(lutece.DECLARED_SKIP + "not for %s: scenario declares versions %s" % (version, sc["versions"]))
    assert not sc.get("_invalid"), "scenario rejected by the oracle rule: " + "; ".join(sc["_invalid"])
    vars_ = {"rand": "".join(random.choices(string.ascii_lowercase + string.digits, k=6)), "rand_int": str(random.randint(10000, 999999)),
             "base": lutece.BASE}
    # Every page the scenario lands on is photographed: the before/after report puts the v7 and v8 pictures of
    # the same parcours side by side, and a green scenario without a picture proves nothing to a reader.
    # Coverage counts as proven only the pages an oracle stood behind: the navigations made since the last
    # oracle are credited when the next one passes, the ones after the last oracle never are.
    pending = []
    for i, step in enumerate(sc["steps"]):
        lutece.reset_obs(bo)
        try:
            run_step(bo, step, vars_, record)
            pending += [lutece.nav_key(n["url"], n.get("mvc", "")) for n in bo.obs.get("nav", []) if n["status"] < 400]
            if list(step)[0] in ORACLE:
                record.setdefault("proven", []).extend(pending)
                pending = []
            if list(step)[0] in ("goto", "submit", "submit_novalidate", "confirm", "click"):
                record.setdefault("screenshots", []).append(lutece.shot(bo, "%s_%d" % (sc["id"], i), "jpg"))
        except AssertionError as e:
            record["screenshot"] = lutece.shot(bo, "fail_%s_%d" % (sc["id"], i), "jpg")
            record["failed_step"] = i
            raise AssertionError("step %d %s: %s" % (i, list(step)[0], e)) from None
    final = lutece.classify(bo)
    record["kind"] = final
    navigated = any(list(st)[0] in ("goto", "submit", "submit_novalidate", "confirm", "confirm_if", "click", "click_if", "login", "login_fo") for st in sc["steps"])
    if navigated and final in ("blank", "error-page", "truncated") and sc.get("ends_on") != final:
        record["screenshot"] = lutece.shot(bo, "fail_%s_end" % sc["id"], "jpg")
        raise AssertionError("the scenario ends on a %s page: its last screen shows nothing a user can read. Fix the flow, "
                             "or declare `ends_on: %s` with a description saying why that is the screen's normal answer" % (final, final))
