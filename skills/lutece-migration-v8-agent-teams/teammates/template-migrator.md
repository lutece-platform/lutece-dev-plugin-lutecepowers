# Template Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

You are the **Template & UI** teammate. You handle JSP files, admin templates, skin templates, and JavaScript.

## Your Scope

- Admin Freemarker templates (`webapp/WEB-INF/templates/admin/**/*.html`)
- Skin Freemarker templates (`webapp/WEB-INF/templates/skin/**/*.html`)
- JSP files (`webapp/**/*.jsp`)
- JavaScript files referenced in templates

**You do NOT touch:** Java source files, pom.xml, configuration files (including `web.xml`, owned by the Config Migrator), test files.

## Dependencies

**Wait for Java Migrators to complete** before starting JSP migration — you need to know the `@Named` bean names they assigned to JspBeans and XPages, and whether each bean is a `@Controller` MVC bean.

## Reference-First Rule

Canonical rules: `rules/jsp-admin.md`, `rules/template-back-office.md`, `rules/template-front-office.md`. Macro signatures are read from the `.ftl` sources of the **assembled** webapp, never from a copy: the design pass (Step 3) assembles the project and the two `lutece-update-template-*` skills say where to look. BO upload templates: `patterns/fileupload-patterns.md`.

## Your Task Input

Read `.migration/tasks-template.json` for your file lists.

---

## Step 1: Mechanical Script

Run template mechanical migrations first, without touching `web.xml`:

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-template-mechanical.sh --no-webxml .
```

This handles: BO upload macro renames, null-safety for errors/infos/warnings, `${error}` → `${error.message}` inside `<#list errors as error>` blocks.

## Step 2: JSP Migration

Follow `rules/jsp-admin.md`. Two cases:

### Pattern A: `@Controller` MVC bean (views and actions)
One JSP per bean. Every former `ManageX.jsp`, `CreateX.jsp`, `DoCreateX.jsp`… collapses into the controller JSP; links become `ManageX.jsp?view=createX` / forms post `action=createX`.

```jsp
<%-- Before --%>
<jsp:useBean id="myJspBean" scope="session" class="...MyJspBean" />
<%= myJspBean.getManageItems(request) %>

<%-- After: webapp/jsp/admin/plugins/myplugin/ManageItems.jsp --%>
<%@ page errorPage="../../ErrorPage.jsp" %>

${ pageContext.setAttribute( 'strContent', myJspBean.processController( pageContext.request , pageContext.response ) ) }

<jsp:include page="../../AdminHeader.jsp" />

${ pageContext.getAttribute( 'strContent' ) }

<%@ include file="../../AdminFooter.jsp" %>
```

Reference: core `jsp/admin/templates/ManageThemes.jsp`, forms `jsp/admin/plugins/forms/ManageForms.jsp`.

### Pattern B: Download in an MVC bean
No dedicated JSP. The download is an `@Action` of the controller bean that calls the inherited `download( data, fileName, contentType )` (`MVCAdminJspBean.java:740`, `:768`) and returns `null`; the link is `ManageItems.jsp?action=downloadItem&id=…`. Delete the former `DownloadX.jsp`.

### Pattern C: non-MVC bean (portlet JspBean, no `@Controller`)
Only here does the JSP call `init()`, with the right constant taken from the class (EL cannot read a static constant through an instance):
```jsp
<%@ page errorPage="../../ErrorPage.jsp" %>
<%@ page import="fr.paris.lutece.plugins.myplugin.web.MyPortletJspBean" %>
${ myPortletJspBean.init( pageContext.request, MyPortletJspBean.RIGHT_MANAGE_ITEMS ) }
${ pageContext.setAttribute( 'strContent', myPortletJspBean.getManageItems( pageContext.request ) ) }
<jsp:include page="../../AdminHeader.jsp" />
${ pageContext.getAttribute( 'strContent' ) }
<%@ include file="../../AdminFooter.jsp" %>
```

**Key rules:**
1. **Remove** all `<jsp:useBean>` tags and scriptlets (`<% %>`, `<%= %>`)
2. **Never** call `init()` for a `@Controller` bean: `processController()` does it with `@Controller.right`
3. The bean name in EL must match the `@Named` value from the Java class (camelCase class name by default)
4. Delete the former per-action JSPs once their views/actions exist in the controller bean; update `<feature-url>` in plugin.xml if the JSP name changed (Config Migrator)

## Step 3: Design pass

The mechanical work above makes the templates load. This step makes them look and behave like the templates the
Lutece front-end team writes today. Same files, same owner: you.

### 3.1 Assemble the project — the precondition

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/ensure-exploded.sh .
```

`mvn lutece:exploded-lite` unpacks the core, every declared dependency and the project itself under `target`, so the
macro signatures, the icon font and the templates this project includes from its dependencies are the ones it really
resolves. A reference clone is another checkout, possibly another version of the core: reading signatures from it is
how an analysis lies. The lite goal declares no lifecycle phase, so it assembles without compiling and works while
the Java migration is still in flight. The script also names the trap that invalidates everything silently: an
assembly whose core carries no `admin/themes/tabler`, which means a locally installed core artifact is shadowing the
remote one.

### 3.2 Frame the work

```bash
python3 ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/scan-template-design.py . --json > .migration/template-design-before.json
```

The header of that script documents every code. **WARN** means fix it or justify it in your report; **INFO** means
decide and say why. The scan is a floor, not a ceiling: a template can pass it and still be far from the models.
It assembles the project itself when needed, and refuses to run rather than read a reference clone.

### 3.3 Two rule sets, never mixed

| | Back-office (`templates/admin/**`) | Front-office (`templates/skin/**`) |
|---|---|---|
| Load | skill `lutece-update-template-bo` + `rules/template-back-office.md` | skill `lutece-update-template-fo` + `rules/template-front-office.md` |
| Macros | `target/**/WEB-INF/templates/admin/themes/tabler/**/*.ftl` of the assembly | `.../skin/themes/macros/**/*.ftl` of the assembly |

Read a macro's `.ftl` before its first use in the session: a parameter the macro does not declare renders nothing and
raises nothing, because the core macros collect wrong arguments in a `deprecated` catch-all and print an HTML comment.

A back-office macro in a skin template, or the reverse, is a defect — with one exception, the **cross-context
fragment**: a `templates/skin/**` file whose caller is an admin template, possibly of another plugin. It keeps the
`c*` macros but drops `cTpl`, `cContainer` and `cForm`. The FO skill says why.

### 3.4 Classify before touching

Confirm the `kind` the scan guessed (`list`, `form`, `page`, `fragment`, `email`, `fo`, `js`, `sql`) by reading the
file and its caller. An e-mail body stays byte-identical: an `<html>` root, `@portal_url@` placeholders, a `send_*`
or `notification_*` name, or a caller passing it to `MailService` are each enough to tell one. A `.js` file under
`WEB-INF/templates` **is** a template, `AppTemplateService` renders it. A fragment included elsewhere keeps no page
container. The `skin/` folder is not only pages: a rule applied to "every skin template" is how damage gets in — the
core pass that wrapped every skin template in `<@cTpl>` (LUT-31677) also wrapped three mail bodies and left one
unparseable.

For a skin template, check whether the core theme overrides it (`render-template.sh` prints an `OVERRIDE` line): a
site on that theme never renders the plugin file. A plugin template that is a byte-for-byte copy of that override is
a wholesale theme copy — rewrite it from the skill's model, keep every functional branch, drop the decorative copy.

### 3.5 Prove each file

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/check-template-parse.sh <file>
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/render-template.sh . <path relative to templates/>
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/check-i18n-keys.sh .
```

The render uses the real macros and a lenient model: every variable the template reads is empty unless
`.migration/render/<path with / as _>.json` defines it. It proves the macro calls, their arguments (a wrong one is
counted as `wrongArguments`) and the empty branches. Write a small JSON model for the list and form templates so the
populated branch renders too, and read the produced HTML. The render also resolves the `#i18n` keys of the output
against the bundles of the assembled webapp and names those that answer nothing: a key that does not exist renders
as an empty string, so the label vanishes without a trace. Prefer property access to getter calls in a template
(`item.pageUrl`, not `item.getPageUrl()`): both work on a bean, only the first works on a JSON hash.

At the end, re-run the scan into `.migration/template-design-after.json` and compare.

### 3.6 Report

Add to `.migration/report-template-migrator.md`: the scan counts before and after, the parse and render results, one
line per file changed, one line per finding kept with the reason, what needs a Java or pom change and for whom, and
the gaps you found in the skills or the rules. A gap is worth a change in the plugin repository, not a workaround
here.

## Step 4: SuggestPOI Migration (conditional)

**Only if tasks-template.json shows files with `old_suggestpoi` flag.** (jQuery in general is the Polisher's Step 6: it cross-checks the pom for `library-theme-jquery` before deciding to port or to keep.)

Replace jQuery autocomplete with LuteceAutoComplete:
- `autocomplete-js.jsp` → `@setupSuggestPOI` macro
- `createAutocomplete()` → `@suggestPOIInput` macro + `new SuggestPOI()` JS class

Search `~/.lutece-references/lutece-tech-module-address-autocomplete/` for the v8 implementation.

## Step 5: Per-File Verification

After each file:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh <file_path>
```

Mark each file task as **completed** when verification passes.

## A JSP calling a bean in EL needs a CDI name, not a class name

`${ MyJspBean.method( pageContext.request ) }` with a `<%@page import%>` resolves through
`StaticFieldELResolver`, which only finds **static** methods. On an instance method it fails at
runtime with `jakarta.el.MethodNotFoundException: No matching public static method named [...]`,
and the screen answers an internal error while everything compiled.

A JspBean called from a JSP therefore carries `@Named` and is called by its **bean name**, the
decapitalized class name:

```jsp
<%@page import="fr.paris.lutece.plugins.myplugin.web.MyJspBean"%>
${ myJspBean.getSelectorUI( pageContext.request ) }
```

Pick the scope from the state: a bean whose public methods each start with `init( request )` holds
per-call state, so `@RequestScoped`. Being instantiated elsewhere by reflection (insert services are)
does not prevent it from also being a CDI bean.

**And check the reference before copying it.** `lutece-cms-plugin-blog` ships two JSPs calling
`BlogUrlInsertServiceJspBean.doInsertBlogLink(...)` and `.doSearchBlogLink(...)` — by class name, and
neither method exists in that class. A reference shows what was done, not that it works: verify the
symbol exists and that the mechanism can resolve it.

## Before you finish

- **Do not widen the diff.** Never convert line endings (CRLF stays CRLF), never reflow javadoc, never touch a
  file outside your task list even to "clean" it: the reviewer must see the migration, not the whole file.
  `verify-migration.sh` LE01 flags a converted file.
- **Write `.migration/report-<your teammate name>.md`** before your final answer: files changed, what you left
  undone and why, what the next teammate must know. The Lead reads that file; your answer through the channel may
  arrive truncated or late.
