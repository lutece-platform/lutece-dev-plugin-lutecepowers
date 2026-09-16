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

Canonical rules: `rules/jsp-admin.md`, `rules/template-back-office.md`, `rules/template-front-office.md`. Macro signatures: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/template-macros.md`, and always the `.ftl` sources under `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/` (BO) and `skin/themes/macros/` (FO).

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

## Step 3: Admin Template Rewrite

**Every admin template MUST use v8 Freemarker macros.** Layout, list layout choice (`@manageFeature` vs `@table`), `@messages`, null-safety and i18n keys: `rules/template-back-office.md` (its List Page and Form Page patterns are the templates to copy). Macro signatures: `template-macros.md`.

### Key transformation rules
- `<div class="panel">` → `<@pageContainer>` + `<@pageColumn>` + `<@pageHeader>`
- `<form>` → `<@tform>`; remove `<input type="hidden" name="token">` (core injects `_csrftoken`)
- `<div class="form-group">` → `<@formGroup labelKey= labelFor= mandatory=>`
- `<input>` → `<@input>`; `<textarea>` → `<@input type='textarea'>`
- `<select>` → `<@select items=>` (ReferenceList) or nested `<@option>`
- `<button>` / `<a class="btn">` → `<@button>` / `<@aButton buttonIcon= title=>`
- entity list `<table>` with edit/delete buttons → `<@manageFeature>`; data grid `<table>` → `<@table>`
- error/info blocks → `<@messages errors=errors![] infos=infos![] warnings=warnings![] />`
- Bootstrap 3 classes → Bootstrap 5 (BS5 is loaded by core)
- `glyphicon glyphicon-*` → `buttonIcon='<name>'` / `ti ti-*` (Tabler icons)
- BO upload macros need `<#include "/admin/plugins/asynchronousupload/upload_commons.html" />` + `<@addRequiredBOJsFiles />` (see `fileupload-patterns.md`)

## Step 4: Skin Template Wrapping

Follow `rules/template-front-office.md`. Wrap front-office templates with `<@cTpl>`:

```html
<@cTpl>
    <@cContainer>
        <@cTitle level=1>#i18n{myplugin.xpage.title}</@cTitle>
        <!-- content -->
    </@cContainer>
</@cTpl>
```

- Use FO macros (`cAlert`, `cBtn`, `cForm`, `cField`, `cInput`, `cCard`, `cTable`, `cFooter`…) and Bootstrap 5 utilities (already loaded by core)
- Messages: `<#list (errors![]) as error>` with `${error.message}`; `${info}` / `${warning}` are strings
- No jQuery — use vanilla JavaScript
- No CDN links — use local assets only

## Step 5: JavaScript Migration

Replace jQuery with vanilla ES6 JS. Conversion table: `${LUTECEPOWERS_ROOT}/skills/lutece-update-template-fo/SKILL.md` § jQuery → Vanilla JS. Code depending on a jQuery plugin (DataTables, Select2, jQuery UI…) cannot be converted mechanically: report it as WARN with a manual port proposal, never leave it as-is (jQuery is not loaded by the theme).

## Step 6: SuggestPOI Migration (conditional)

**Only if tasks-template.json shows files with `old_suggestpoi` flag.**

Replace jQuery autocomplete with LuteceAutoComplete:
- `autocomplete-js.jsp` → `@setupSuggestPOI` macro
- `createAutocomplete()` → `@suggestPOIInput` macro + `new SuggestPOI()` JS class

Search `~/.lutece-references/lutece-tech-module-address-autocomplete/` for the v8 implementation.

## Step 7: Per-File Verification

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
