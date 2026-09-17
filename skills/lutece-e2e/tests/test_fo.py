"""Front-office coverage: every front-office page discovered by the anonymous crawl (tools/discover.py, key
`fo_screens`) plus the inventory FO pages it did not reach. Each must render as a real front-office page with a
clean browser console — no JS error, no failed sub-request, no server error page. Front-office mutations (a
contact form, a subscription) are proven by the hand-written scenarios, not here."""
import re

import pytest

import lutece

FO_OK = ("fo", "public-form")
"""A front-office response is the portal page or a public inline form; never a back-office screen or an error page."""


def _with_params(u):
    """Adds the query the bench declares for that screen (scenarios/screens.yaml, key `params`).

    A front-office XPage whose view requires a parameter answers a Lutece message when opened bare, and the suite
    would record a broken page instead of testing it. Same rule as the screens suite."""
    q = lutece.screen_query(u)
    return (u + ("&" if "?" in u else "?") + q) if q and q not in u else u


def _fo_targets():
    """The front-office pages of the artefact under test: the site's other XPages (the bench's own mylutece login
    and account pages, for instance) belong to the environment and are not this bench's to judge."""
    in_scope = lutece.scope()
    seen, out = set(), []
    disc = lutece.load_json("artifacts/discovered.json", {})
    for s in disc.get("fo_screens", []):
        u = _with_params(s["url"])
        if u not in seen and in_scope(u):
            seen.add(u); out.append(u)
    inv = lutece.load_json("artifacts/inventory.json", {"screens": []})
    for s in inv.get("screens", []):
        u = _with_params(s.get("url", ""))
        if s.get("surface") == "fo" and u not in seen and in_scope(u):
            seen.add(u); out.append(u)
    return out


def _slug(u):
    return re.sub(r"[^A-Za-z0-9]+", "_", u.replace("jsp/site/", "").replace(".jsp", "")).strip("_")[:120] or "fo"


@pytest.mark.parametrize("target", _fo_targets(), ids=_slug)
def test_fo_screen(anon, record, fo_theme_baseline, target):
    """A front-office page renders cleanly for an anonymous visitor (the front office is public)."""
    reason = lutece.screen_skip(target)
    if reason:
        record["url"] = target
        pytest.skip(lutece.DECLARED_SKIP + "not opened standalone: " + reason)
    t0 = lutece.now_ms()
    resp = anon.goto(lutece.url(target), wait_until="load")
    record["ms"] = round(lutece.now_ms() - t0)
    record["url"] = target
    record["surface"] = "fo"
    record["http_status"] = resp.status if resp else 0
    record["final"] = lutece.normalize(anon.url)
    kind = lutece.classify(anon, resp.status if resp else 0)
    record["kind"] = kind
    record["screenshot"] = lutece.shot(anon, "fo_" + _slug(target), "jpg")
    if lutece.is_fragment(target):
        assert kind not in lutece.NOT_NORMAL and not kind.startswith("http-"), \
            "standalone document answered %s: %s" % (kind, lutece.page_text(anon)[:160])
    else:
        assert kind in FO_OK, "expected a front-office page, got %s: %s" % (kind, lutece.page_text(anon)[:160])
    record["render"] = lutece.render_check(anon, kind)
    # A rendering defect the bare portal already shows belongs to the site theme, not to this artefact.
    own = [x for x in record["render"] if x not in fo_theme_baseline["render"]]
    # `render_own` is what the visual review must judge: the theme's own defects are not this artefact's, and
    # sending the reviewer after the site footer's broken logo buries the findings that do belong to it.
    record["render_own"] = own
    record["render_theme"] = len(record["render"]) - len(own)
    hard = [x for x in own if x.startswith(("unresolved", "i18n key", "no stylesheet"))]
    assert not hard, "rendering: %s" % hard
    errs, noise, bad = lutece.console_noise(anon, fo_theme_baseline)
    record["theme_noise"] = len(anon.obs["errors"]) - len(errs) + len([c for c in anon.obs["console"] if c["text"] in fo_theme_baseline["console"]])
    assert not errs, "JS errors introduced by the plugin FO (theme baseline subtracted): %s" % errs[:3]
    assert not noise, "console not clean (plugin FO, theme baseline subtracted): %s" % noise[:3]
    assert not bad, "failed sub-requests (plugin FO): %s" % bad[:3]
