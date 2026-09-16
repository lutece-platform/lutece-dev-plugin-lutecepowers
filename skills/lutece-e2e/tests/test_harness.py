"""Self-checks of the bench's own oracle: the classifier must recognise a real screen, a confirmation, a
lost session, a login form and a missing page. Runs first; when one of these fails, no other verdict of
the run can be trusted (that is how a "please authenticate" page once passed as a success)."""
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
    """The collection rule must reject a submit that is only followed by expect_ok, and accept one followed by sql."""
    import test_scenarios
    bad = {"id": "x", "steps": [{"goto": "a"}, {"submit": "form"}, {"expect_ok": None}, {"goto": "b"}]}
    good = {"id": "y", "steps": [{"submit": "form"}, {"expect_ok": None}, {"sql": {"query": "SELECT 1", "expect": 1}}]}
    assert test_scenarios.validate(bad), "unproven mutation accepted"
    assert not test_scenarios.validate(good), test_scenarios.validate(good)


def test_classifier_requires_footer(bo):
    """A normal screen carries the theme footer; a header-only page must never be classified as a screen."""
    bo.goto(lutece.url("jsp/admin/user/ManageUsers.jsp"), wait_until="load")
    assert bo.locator("footer, .footer, #footer").count() >= 1, "footer marker changed: update classify()"
    bo.evaluate("() => document.querySelectorAll('footer, .footer, #footer').forEach(e => e.remove())")
    assert lutece.classify(bo) == "truncated"


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

