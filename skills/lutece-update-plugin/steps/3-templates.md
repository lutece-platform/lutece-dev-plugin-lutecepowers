# Step 3 — JSP, templates, JavaScript

After step 2: the JSP need the `@Named` of each bean and whether it is a `@Controller`.

`lutece-check.sh`, `verify-file.sh` and `scan-template-design.py` report what a script can see, each finding with what
to do: the back-office upload macros (TM03, TM06), `errors` / `infos` / `warnings` (TM04, TM07), the button colours
(TD51, TD56: `bash ${LUTECEPOWERS_ROOT}/tools/py.sh ${LUTECEPOWERS_ROOT}/tools/fix-button-colours.py <project>` sets them all). Canonical rules: `rules/jsp-admin.md`, `rules/template-back-office.md`, `rules/template-front-office.md`.

## 1. JSP

`rules/jsp-admin.md`. Three shapes:

- **`@Controller` MVC bean**: one JSP per bean; every former `CreateX.jsp`, `DoCreateX.jsp`… collapses into it
  (`ManageX.jsp?view=createX`, forms post `action=createX`); delete the per-action JSPs and update `<feature-url>`
  when the name changes. Never call `init()`: `processController()` does it.
- **Download**: no JSP, an `@Action` calling the inherited `download( data, fileName, contentType )` and returning `null`.
- **Non-MVC bean** (portlet JspBean): the JSP calls `init()` with the right constant read from the class
  (`<%@ page import %>`), never through the instance.

A bean called from EL is reached by its CDI name (`${ myJspBean.method( … ) }`, the decapitalised class name, `@Named`
on the class): a class name in EL only resolves static methods, and fails at runtime with `MethodNotFoundException`.
A reference JSP shows what was done, not that it works: check the method exists.

## 2. Design pass

```bash
bash ${LUTECEPOWERS_ROOT}/tools/ensure-exploded.sh .
bash ${LUTECEPOWERS_ROOT}/tools/py.sh ${LUTECEPOWERS_ROOT}/tools/scan-template-design.py . --json > .migration/template-design-before.json
```

Read macro signatures from the `.ftl` of the assembled webapp (`target/**/WEB-INF/templates/admin/themes/tabler/**` for
the back office, `…/skin/themes/macros/**` for the front office), never from a reference clone: a parameter a macro does
not declare renders nothing and raises nothing. Load `lutece-update-template-bo` for `templates/admin/**`,
`lutece-update-template-fo` for `templates/skin/**`; the two rule sets never mix, except a skin fragment rendered inside
an admin page (it keeps the `c*` macros, drops `cTpl`, `cContainer`, `cForm`).

Classify each file before touching it (list, form, page, fragment, email, fo, js, sql): an e-mail body stays
byte-identical, a `.js` under `WEB-INF/templates` is a template, a fragment keeps no page container. A skin template
the core theme overrides (`render-template.sh` prints `OVERRIDE`) is never rendered on that theme; a byte copy of the
override is rewritten from the skill's model.

## 3. Prove each file

```bash
bash ${LUTECEPOWERS_ROOT}/tools/check-template-parse.sh <file>
bash ${LUTECEPOWERS_ROOT}/tools/render-template.sh . <path relative to templates/>
```

The render uses the real macros and an empty model unless `.migration/render/<path with / as _>.json` defines one:
write one for the list and form templates so the populated branch renders too, and read the produced HTML. Prefer
property access (`item.pageUrl`) to getter calls: only the first works on a JSON hash. At the end re-run the scan into
`.migration/template-design-after.json`.

## Conditional

- **Upload widget** (`upload_widget` flag, TD45): replace it with `plugin-asynchronousupload`, never revive it with
  `library-theme-jquery` (`patterns/fileupload-patterns.md`).
- **SuggestPOI** (`old_suggestpoi` flag): `@setupSuggestPOI` and `@suggestPOIInput`, from
  `~/.lutece-references/lutece-tech-module-address-autocomplete/`.
