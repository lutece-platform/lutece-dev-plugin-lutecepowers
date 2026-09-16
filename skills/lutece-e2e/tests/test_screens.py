"""Every back-office screen (static inventory + dynamic discovery) opens as a normal screen: HTTP 200,
no Lutece/Liberty error page, no session loss, clean browser console, no failed sub-request. Each screen
leaves a screenshot, an aria snapshot (structural fingerprint compared to baselines/aria when present)
and its timing in results.json."""
import difflib
import json
import re

import pytest

import lutece

BASELINES = lutece.E2E / "baselines" / "aria"
ARIA_OUT = lutece.ARTIFACTS / "aria"
SESSIONLESS = re.compile(r"AdminLogin|AdminForgot|AdminResetPassword|AdminFormContact|ReactivateAccount", re.I)
"""Public screens: visiting them inside the admin session destroys it, they have their own anonymous tests."""
CONFIRM_SCREENS = lutece.rule_re("confirm", r"/(Remove|Confirm|DoConfirm|Anonymize|GetChangeUse)\w*\.jsp|view=confirm")
"""Screens whose normal answer is a Lutece confirmation question, not a menu-bearing screen."""
"""Screens that answer with a fragment (offcanvas, insert service popup) or a front-office preview are declared
per bench in scenarios/screens.yaml, key `fragment`, and read through lutece.is_fragment."""


def _screens():
    """Concrete urls to open: discovered screens first (they carry real ids), then inventory screens
    without parameters that discovery did not reach. Login and session-less screens are separate tests."""
    seen, out = set(), []
    in_scope = lutece.scope()
    disc = lutece.load_json("artifacts/discovered.json", {"screens": []})
    for s in disc["screens"]:
        u = s["url"]
        if u not in seen and not SESSIONLESS.search(u) and in_scope(u):
            seen.add(u); out.append(u)
    inv = lutece.load_json("artifacts/inventory.json", {"screens": []})
    for s in inv["screens"]:
        u = s["url"]
        if u not in seen and "?" not in u and not re.search(r"AdminLogin|AdminForgot|AdminResetPassword|AdminFormContact", u) and in_scope(u):
            seen.add(u); out.append(u)
    return out


def _slug(u):
    return re.sub(r"[^A-Za-z0-9]+", "_", u.replace("jsp/admin/", "").replace(".jsp", "")).strip("_")[:120]


@pytest.mark.parametrize("target", _screens(), ids=_slug)
def test_screen(bo, record, target):
    slug = _slug(target)
    reason = lutece.screen_skip(target)
    if reason:
        record["url"] = target
        pytest.skip("not opened standalone: " + reason)
    t0 = lutece.now_ms()
    q = lutece.screen_query(target)
    opened = target if not q or "?" in target else target + "?" + q
    resp = bo.goto(lutece.url(opened), wait_until="load")
    record["ms"] = round(lutece.now_ms() - t0)
    status = resp.status if resp else 0
    record["http_status"] = status
    record["url"] = opened
    record["final"] = lutece.normalize(bo.url)
    record["title"] = bo.title()[:100]
    kind = lutece.classify(bo, status)
    if kind == "auth":
        record["relogin"] = True
        assert lutece.bo_login(bo), "re-login failed"
        resp = bo.goto(lutece.url(target), wait_until="load")
        status = resp.status if resp else 0
        kind = lutece.classify(bo, status)
    record["screenshot"] = lutece.shot(bo, slug, "jpg")
    record["kind"] = kind
    snap = lutece.aria(bo)
    ARIA_OUT.mkdir(parents=True, exist_ok=True)
    (ARIA_OUT / (slug + ".yaml")).write_text(snap)
    base = BASELINES / (slug + ".yaml")
    if base.exists():
        diff = list(difflib.unified_diff(base.read_text().splitlines(), snap.splitlines(), lineterm="", n=0))
        record["aria_changed"] = len(diff) > 0
        record["aria_diff_lines"] = len(diff)
    bare = "?" not in target
    record["bare"] = bare
    if CONFIRM_SCREENS.search(target):
        expected = ("confirmation", "error", "warning", "info")
    elif lutece.is_fragment(target):
        # A popup body has no menu bar and its shape depends on what it contains: a selector carrying a validate
        # and a cancel form classifies as a confirmation, a read-only one as a fragment. Declaring it a fragment
        # is the bench saying "this is a popup, not a menu-bearing screen", so the assertion that keeps its value
        # is the negative one: it must not be an error page, a blank body or a lost session.
        expected = None
        assert kind not in lutece.NOT_NORMAL and not kind.startswith("http-"), \
            "fragment answered %s: %s (final url %s)" % (kind, lutece.page_text(bo)[:160], record["final"])
    else:
        expected = ("screen", "error") if bare else ("screen",)
    if expected is not None:
        assert kind in expected, "expected %s, got %s: %s (final url %s)" % ("/".join(expected), kind, lutece.page_text(bo)[:160], record["final"])
    record["render"] = lutece.render_check(bo, kind)
    hard = [x for x in record["render"] if x.startswith(("unresolved", "i18n key", "no stylesheet"))]
    assert not hard, "rendering: %s" % hard
    errs, noise, bad = lutece.console_noise(bo)
    assert not errs, "uncaught JS errors: %s" % errs[:3]
    assert not noise, "console not clean: %s" % noise[:3]
    assert not bad, "failed sub-requests: %s" % bad[:3]


SCOPED = not lutece.scope()("jsp/admin/AdminLogin.jsp")
"""True on a plugin bench: the core's public screens (login, lost password, contact) belong to the core bench."""


@pytest.mark.skipif(SCOPED, reason="core public screen, out of the plugin scope")
def test_login_screen(anon, record):
    """The login screen renders and rejects a wrong password with a Lutece message, not an error page."""
    resp = anon.goto(lutece.url("jsp/admin/AdminLogin.jsp"), wait_until="load")
    record["screenshot"] = lutece.shot(anon, "AdminLogin", "jpg")
    assert resp.status == 200, resp.status
    assert anon.locator('input[name="access_code"]').count() == 1, "login form not rendered"
    assert not anon.obs["errors"] and not anon.obs["console"], (anon.obs["errors"], anon.obs["console"])
    assert not lutece.bo_login(anon, "admin", "wrong-password"), "wrong password accepted"
    assert "AdminLogin.jsp" in anon.url or lutece.admin_message(anon) in ("error", "stop", "message"), anon.url


@pytest.mark.skipif(SCOPED, reason="core public screen, out of the plugin scope")
@pytest.mark.parametrize("target", ["jsp/admin/AdminForgotLogin.jsp", "jsp/admin/AdminForgotPassword.jsp",
                                    "jsp/admin/AdminFormContact.jsp"])
def test_sessionless_screen(anon, record, target):
    """Public admin screens (lost login / password, contact) render cleanly without a session."""
    resp = anon.goto(lutece.url(target), wait_until="load")
    record["screenshot"] = lutece.shot(anon, _slug(target), "jpg")
    kind = lutece.classify(anon, resp.status)
    record["kind"] = kind
    assert kind == "public-form", "expected public-form, got %s: %s" % (kind, lutece.page_text(anon)[:160])
    assert not anon.obs["errors"] and not anon.obs["console"], (anon.obs["errors"], anon.obs["console"])
