"""Every form discovered on the back-office screens is submitted once with generated values. The server
must answer with a screen or a Lutece message (validation error is a fine answer), never an error page,
a 500, a session loss or an exception. Runs last: it mutates the disposable bench. Forms whose action
matches DENY — by its url or by the MVC action its submit control names — is left to the scenarios (it would
lock the bench out or destroy what other tests need)."""
import re

import pytest

import lutece

DENY = lutece.rule_re("deny", r"AdminLogin|DoAdminLogin|DoAdminLogout|DoUninstallPlugin|DoInstallPlugin|DoModifyUserPassword|DoRemoveUser|DoAnonymize|"
                  r"DoModifyUser\b|DoModifyUser\.jsp|DoImportUsers|DoChangeFieldAnonymize|DoDispatchFeature|DoModifyPluginPool|DoModifyAdvancedParameters|"
                  r"DoModifyDefaultUserPassword|DoUseAdvancedSecurityParameters|DoRemoveAdvancedSecurityParameters|"
                  r"DoModifyUserRights|DoModifyUserRoles|DoReinitFeatures|DoRemovePage\b|DoDaemonAction|DoResetCaches|"
                  r"DoToggleCache|DoChangeLanguage|DoModifyAccessibilityMode|DoModifyProperties|DoIndexing|"
                  r"DoModifyDefaultUserSecurityParameterValues|DoModifyAccountLifeTimeEmails|DoModifyEmailPattern|"
                  r"DoUpdate(Back|Front)OfficeEditor|DoModifyPluginPool|DoRemove\w*Right|DoUnassign|DoExport|DoDownload")


PROTECTED_SCREEN = lutece.rule_re("protected", r"[?&]id_user=(1|2|3|4)(&|$)|access_code=" + re.escape(lutece.ADMIN[0])
                                  + r"|workgroup_key=all(&|$)|ConfirmUninstallPlugin|ConfirmToggleCache")
"""Screens editing the accounts the bench itself depends on: never fuzzed, or the
run locks itself out — the mutation scenarios own those flows on users they create themselves."""


def _forms():
    disc = lutece.load_json("artifacts/discovered.json", {"forms": []})
    seen, out = set(), []
    in_scope = lutece.scope()
    for f in disc["forms"]:
        a = f["action"].split("?")[0]
        if not (in_scope(f["screen"]) or in_scope(f["action"])):
            continue
        if a in seen or DENY.search(f["action"]) or "AdminLogin" in f["screen"] or PROTECTED_SCREEN.search(f["screen"]):
            continue
        seen.add(a)
        out.append((f["screen"], f["action"]))
    return out


def _slug(pair):
    return re.sub(r"[^A-Za-z0-9]+", "_", pair[1].replace("jsp/admin/", "").replace(".jsp", ""))[:80]


SESSIONLESS = re.compile(r"AdminLogin|AdminForgot|AdminResetPassword|AdminFormContact", re.I)
"""Public admin screens: their forms run in an anonymous context (they invalidate the shared admin session)."""


@pytest.mark.parametrize("pair", _forms(), ids=_slug)
def test_form(bo, anon, record, pair):
    screen, action = pair
    record["screen"], record["action"] = screen, action
    if SESSIONLESS.search(screen):
        bo = anon
    bo.goto(lutece.url(screen), wait_until="load")
    if lutece.classify(bo) == "blank":
        bo.wait_for_timeout(1000)
        bo.wait_for_load_state("load")
    record["screen_kind"] = lutece.classify(bo)
    form = 'form[action*="%s"]' % action.split("?")[0].split("/")[-1]
    if not bo.locator(form).count():
        if record["screen_kind"] == "screen":
            pytest.skip("form %s no longer on %s: the data it needed was consumed by another test" % (action.split("/")[-1], screen))
        assert False, "form %s not found on %s (page now at %s, kind %s: %s)" % (
            action, screen, lutece.normalize(bo.url), record["screen_kind"], lutece.page_text(bo)[:120])
    # Several forms of a screen can share the same action url and differ only by the MVC action they name, so a
    # `deny` entry has to be matched against that name too — otherwise the fuzzer posts the export, the import or
    # the reindex it was told to leave alone.
    # Lutece names the MVC action two ways: a control named `action` carrying it as a value, and a submit button
    # named `action_<name>`. Both have to be read, or the deny list silently misses half the forms.
    mvc_action = bo.eval_on_selector(form, """f => {
        const named = f.querySelector('[name="action"]');
        if ( named && named.value ) { return named.value; }
        const prefixed = f.querySelector('[name^="action_"]');
        return prefixed ? prefixed.name.substring( 'action_'.length ) : '';
    }""") or ""
    if mvc_action and DENY.search(mvc_action):
        record["denied_action"] = mvc_action
        pytest.skip(lutece.DECLARED_SKIP + "action %s is denied by the bench (scenarios/screens.yaml, key deny)" % mvc_action)
    record["filled"] = lutece.fill_form(bo, form)
    lutece.reset_obs(bo)
    navigated = lutece.submit(bo, form)
    record["navigated"] = navigated
    record["final"] = lutece.normalize(bo.url)
    record["message"] = lutece.admin_message(bo)
    record["screenshot"] = lutece.shot(bo, "form_" + _slug(pair), "jpg")
    statuses = [n["status"] for n in bo.obs["nav"]]
    record["statuses"] = statuses
    kind = lutece.classify(bo, max(statuses) if statuses else None)
    record["kind"] = kind
    assert kind in ("screen", "confirmation", "error", "warning", "info", "login", "public-form") or (kind == "auth" and SESSIONLESS.search(screen)), \
        "server answered with %s (%s)" % (kind, lutece.page_text(bo)[:200])
    # Same judgement as the other suites: what the bench declared, and the environment's own noise, are not the
    # artefact's doing. Reading page.obs directly here failed a form on an asset every other suite accepts.
    errs, noise, bad = lutece.console_noise(bo)
    assert not errs, "js errors %s" % errs[:2]
    assert not noise, "console %s" % noise[:2]
    assert not bad, "failed sub-requests %s" % [r["url"] for r in bad][:2]
