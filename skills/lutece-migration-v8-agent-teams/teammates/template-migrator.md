# Template Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

You are the **Template & UI** teammate. You handle JSP files, admin templates, skin templates, and JavaScript.

## Your Scope

- Admin Freemarker templates (`webapp/WEB-INF/templates/admin/**/*.html`)
- Skin Freemarker templates (`webapp/WEB-INF/templates/skin/**/*.html`)
- JSP files (`webapp/**/*.jsp`)
- JavaScript files referenced in templates

**You do NOT touch:** Java source files, pom.xml, configuration files, test files.

## Dependencies

**Wait for Java Migrators to complete** before starting JSP migration — you need to know the `@Named` bean names they assigned to JspBeans and XPages.

## Reference-First Rule

**Always consult** `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/` for macro definitions and usage examples.

## Your Task Input

Read `.migration/tasks-template.json` for your file lists.

---

## Step 1: Mechanical Script

Run template mechanical migrations first:

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-template-mechanical.sh .
```

This handles: BO macro renames, null-safety for errors/infos/warnings, web.xml namespace.

## Step 2: JSP Migration

For each JSP file, apply one of 4 patterns:

### Pattern A: View JSP (most common)
```jsp
<%-- Before --%>
<jsp:useBean id="myJspBean" scope="session" class="...MyJspBean" />
<%= myJspBean.getManageItems(request) %>

<%-- After --%>
<%@ page errorPage="../../ErrorPage.jsp" %>
${myJspBean.init(pageContext.request, myJspBean.RIGHT_MANAGE_ITEMS)}
${myJspBean.processController(pageContext.request, pageContext.response)}
```

### Pattern B: Action/Do JSP
```jsp
<%-- After --%>
${myJspBean.init(pageContext.request, myJspBean.RIGHT_MANAGE_ITEMS)}
${myJspBean.processController(pageContext.request, pageContext.response)}
```

### Pattern C: ProcessController JSP (MVC)
```jsp
${myJspBean.init(pageContext.request, myJspBean.RIGHT_MANAGE_ITEMS)}
${myJspBean.processController(pageContext.request, pageContext.response)}
```

### Pattern D: Download JSP
```jsp
${myJspBean.init(pageContext.request, myJspBean.RIGHT_MANAGE_ITEMS)}
${myJspBean.download(pageContext.request, pageContext.response)}
```

**Key rules:**
1. **Remove** all `<jsp:useBean>` tags
2. **Replace** `request` with `pageContext.request` in EL expressions
3. **Replace** scriptlets `<%= %>` and `<% %>` with `${}` EL expressions
4. The bean name in EL must match the `@Named` value from the Java class (camelCase class name by default)
5. Add `<%@ page import="..." %>` if needed for constants like `RIGHT_MANAGE_ITEMS`

## Step 3: Admin Template Rewrite

**Every admin template MUST use v8 Freemarker macros.** This is the most significant UI change.

Load quick reference: Read `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/template-macros.md`

### List page pattern
```html
<@pageContainer>
    <@pageColumn>
        <@pageHeader title="#i18n{myplugin.manage.pageTitle}" description="" />

        <#if (errors!)?has_content>
            <@alert type="danger"><#list (errors![]) as error>${error.message}</#list></@alert>
        </#if>
        <#if (infos!)?has_content>
            <@alert type="info"><#list (infos![]) as info>${info}</#list></@alert>
        </#if>

        <@aButton href="..." color="success" iconClass="ti ti-plus" labelKey="#i18n{myplugin.action.create}" />

        <@table>
            <tr>
                <th>#i18n{myplugin.column.name}</th>
                <th>#i18n{portal.util.labelActions}</th>
            </tr>
            <#list items_list as item>
            <tr>
                <td>${item.name!}</td>
                <td>
                    <@aButton href="...?view=modifyItem&id=${item.id}" title="#i18n{portal.util.labelModify}" color="primary" size="sm" iconClass="ti ti-pencil" />
                    <@aButton href="...?action=confirmRemoveItem&id=${item.id}" title="#i18n{portal.util.labelDelete}" color="danger" size="sm" iconClass="ti ti-trash" />
                </td>
            </tr>
            </#list>
        </@table>
    </@pageColumn>
</@pageContainer>
```

### Form page pattern
```html
<@pageContainer>
    <@pageColumn>
        <@pageHeader title="#i18n{myplugin.create.pageTitle}" />

        <@tform action="jsp/admin/plugins/myplugin/ManageItems.jsp" method="post">
            <input type="hidden" name="action" value="createItem" />

            <@formGroup labelKey="#i18n{myplugin.label.name}" required=true>
                <@input type="text" name="name" id="name" value="${item.name!}" required=true />
            </@formGroup>

            <@button type="submit" color="primary" labelKey="#i18n{portal.util.labelValidate}" />
            <@aButton href="..." color="default" labelKey="#i18n{portal.util.labelCancel}" />
        </@tform>
    </@pageColumn>
</@pageContainer>
```

### Key transformation rules
- `<div class="panel">` → `<@pageContainer>` + `<@pageColumn>`
- `<form>` → `<@tform>`
- `<div class="form-group">` → `<@formGroup>`
- `<input>` → `<@input>`
- `<select>` → `<@select>`
- `<button>` → `<@button>` or `<@aButton>`
- `<table>` → `<@table>`
- Bootstrap 3 classes → Bootstrap 5 (BS5 is loaded by core)
- `glyphicon glyphicon-*` → `ti ti-*` (Tabler icons)

## Step 4: Skin Template Wrapping

Wrap front-office templates with `<@cTpl>`:

```html
<@cTpl>
    <@cContainer>
        <h1>#i18n{myplugin.xpage.title}</h1>
        <!-- content -->
    </@cContainer>
</@cTpl>
```

- Use Bootstrap 5 utilities (already loaded by core)
- No jQuery — use vanilla JavaScript
- No CDN links — use local assets only
- Tabler icons: `ti ti-*`

## Step 5: JavaScript Migration

Replace jQuery with vanilla ES6 JS. See `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/template-macros.md` **§ JavaScript Migration** for the full conversion table.

## Step 6: SuggestPOI Migration (conditional)

**Only if tasks-template.json shows files with `old_suggestpoi` flag.**

Replace jQuery autocomplete with LuteceAutoComplete:
- `autocomplete-js.jsp` → `@setupSuggestPOI` macro
- `createAutocomplete()` → `@suggestPOIInput` macro + `new SuggestPOI()` JS class

Search `~/.lutece-references/module-address-autocomplete/` for the v8 implementation.

## Step 7: Per-File Verification

After each file:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh <file_path>
```

Mark each file task as **completed** when verification passes.
