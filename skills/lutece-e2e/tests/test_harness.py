"""Self-checks of the bench's own oracle: the classifier must recognise a real screen, a confirmation, a
lost session, a login form and a missing page. Runs first; when one of these fails, no other verdict of
the run can be trusted: a "please authenticate" page renders in HTTP 200 and would pass as a success."""
import lutece


def test_classifier_screen(bo):
    bo.goto(lutece.url("jsp/admin/user/ManageUsers.jsp"), wait_until="load")
    assert lutece.classify(bo) == "screen"


def test_classifier_confirmation(bo):
    bo.goto(lutece.url("jsp/admin/workgroup/RemoveWorkgroup.jsp?workgroup_key=WG_0001"), wait_until="load")
    assert lutece.classify(bo) == "confirmation"


def test_classifier_auth_and_login(anon):
    resp = anon.goto(lutece.url("jsp/admin/user/ManageUsers.jsp"), wait_until="load")
    assert lutece.classify(anon, resp.status) in ("auth", "login"), lutece.page_text(anon)[:120]
    anon.goto(lutece.url("jsp/admin/AdminLogin.jsp"), wait_until="load")
    assert lutece.classify(anon) == "login"


def test_classifier_http_404(bo):
    resp = bo.goto(lutece.url("jsp/admin/NoSuchScreen.jsp"), wait_until="load")
    assert lutece.classify(bo, resp.status) == "http-404"


def test_classifier_error_page(bo):
    bo.goto(lutece.url("jsp/admin/user/attribute/CreateAttribute.jsp"), wait_until="load")
    assert lutece.classify(bo) in ("error-page", "screen"), lutece.page_text(bo)[:120]


def test_scenario_rule_rejects_unproven_mutation():
    """The collection rule must reject a submit that is only followed by expect_ok, and accept one followed by sql; it
    must reject an oracle on the markup that hides an element, and accept visible: or a style that hides nothing."""
    import test_scenarios
    bad = {"id": "x", "steps": [{"goto": "a"}, {"submit": "form"}, {"expect_ok": None}, {"goto": "b"}]}
    weak = {"id": "w", "steps": [{"submit": "form"}, {"expect_message": "error"}]}
    urlish = {"id": "u", "steps": [{"goto": "a"}, {"expect_text": "AdminMessage.jsp"}]}
    late = {"id": "l", "steps": [{"submit": "form"}, {"sql_exec": "UPDATE t SET x=1"}, {"sql": {"query": "SELECT 1", "expect": 1}}]}
    hiding = {"id": "h", "steps": [{"goto": "a"}, {"expect_dom": {"selector": {"v7": "#b[style*=\"none\"]", "v8": "#b[hidden]"}, "count": 1}}]}
    seen = {"id": "s", "steps": [{"goto": "a"}, {"expect_dom": {"selector": "#b", "visible": False}},
                                 {"expect_dom": {"selector": "img[style*=\"rotate(45deg)\"]", "count": 1}}]}
    good = {"id": "y", "steps": [{"submit": "form"}, {"expect_ok": None}, {"sql": {"query": "SELECT 1", "expect": 1}}]}
    refusal = {"id": "r", "steps": [{"submit_novalidate": "form"}, {"expect_message": "error"}, {"sql": {"query": "SELECT COUNT(*) FROM t", "expect": 0}}]}
    assert test_scenarios.validate(bad), "unproven mutation accepted"
    assert test_scenarios.validate(weak), "a screen-only oracle after a mutation accepted"
    assert test_scenarios.validate(urlish), "expect_text on a JSP name accepted"
    assert test_scenarios.validate(late), "sql_exec after a mutation accepted"
    assert test_scenarios.validate(hiding), "an oracle on the markup that hides accepted"
    assert not test_scenarios.validate(seen), test_scenarios.validate(seen)
    assert not test_scenarios.validate(good), test_scenarios.validate(good)
    assert not test_scenarios.validate(refusal), test_scenarios.validate(refusal)
    js_proof = {"id": "j", "steps": [{"click": "button[type=submit]"}, {"js": {"script": "localStorage.k", "expect": "v"}}]}
    js_arrange = {"id": "k", "steps": [{"click": "button[type=submit]"}, {"js": "localStorage.k = 1"}]}
    assert not test_scenarios.validate(js_proof), test_scenarios.validate(js_proof)
    assert test_scenarios.validate(js_arrange), "a js step without expect accepted as a proof"


def test_classifier_requires_footer(bo):
    """A normal screen carries the theme footer; a header-only page must never be classified as a screen."""
    bo.goto(lutece.url("jsp/admin/user/ManageUsers.jsp"), wait_until="load")
    assert bo.locator("footer, .footer, #footer").count() >= 1, "footer marker changed: update classify()"
    bo.evaluate("() => document.querySelectorAll('footer, .footer, #footer').forEach(e => e.remove())")
    assert lutece.classify(bo) == "truncated"


def test_screen_skip_is_scoped_to_the_versions_it_declares():
    """A skip rule carrying `versions` applies on those versions only: the other leg still has to open the screen."""
    import os
    saved = lutece._RULES.get("r")
    before = os.environ.get("E2E_VERSION")
    lutece._RULES["r"] = {"skip": [{"match": "page=one", "versions": ["v7"], "reason": "one leg only"},
                                   {"match": "page=two", "reason": "every leg"}]}
    try:
        os.environ["E2E_VERSION"] = "v7"
        assert lutece.screen_skip("jsp/site/Portal.jsp?page=one")
        os.environ["E2E_VERSION"] = "v8"
        assert not lutece.screen_skip("jsp/site/Portal.jsp?page=one"), "a version-scoped skip leaked to the other leg"
        assert lutece.screen_skip("jsp/site/Portal.jsp?page=two")
    finally:
        if saved is None:
            lutece._RULES.pop("r", None)
        else:
            lutece._RULES["r"] = saved
        os.environ.pop("E2E_VERSION", None)
        if before is not None:
            os.environ["E2E_VERSION"] = before


def test_scenario_variables_expand_in_selectors():
    """{{var}} placeholders must expand in dict keys (fill selectors) as well as in values."""
    import test_scenarios
    out = test_scenarios._expand({"#row-{{id}} input": "v-{{id}}"}, {"id": "42"})
    assert out == {"#row-42 input": "v-42"}, out


def test_classifier_front_office(anon):
    """A portal page (several forms: search, contact) is a front-office page, never an admin confirmation.
    `public-form` is a front-office page too: a home page carrying a search or login form classifies that way —
    the v7 core's does — and the point of this test is that it is never read as an admin screen or a message."""
    anon.goto(lutece.url("jsp/site/Portal.jsp"), wait_until="load")
    assert lutece.classify(anon) in ("fo", "public-form"), lutece.page_text(anon)[:120]

