---
description: "Lutece 8 Freemarker constraints: layout macros, list layout (@manageFeature / @table), form components, messages, i18n, vanilla JS"
paths:
  - "**/templates/admin/**/*.html"
---

# Freemarker Templates — Lutece 8

## Reference Sources — MANDATORY

Before writing or modifying a template, ALWAYS consult:
- macro definitions (signatures): `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/{components,elements,forms,layout,utilities}/**/*.ftl`
- template examples: `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/<feature>/*.html` (e.g. `rbac/manage_roles.html`, `mailinglist/manage_mailinglists.html`) and `~/.lutece-references/lutece-form-plugin-forms/webapp/WEB-INF/templates/admin/plugins/forms/*.html`

Read the `.ftl` signature before using a macro parameter. Frequent mistakes: `@alert` takes `color` (not `type`); `@aButton`/`@button` take `buttonIcon` + `title` (not `iconClass`/`labelKey`); `@formGroup`/`@input` take `mandatory` (not `required`); `@select` takes `items` (a `ReferenceList`) + `default_value`; `@radioButton`/`@checkBox` take `labelKey` (not `label`); `@input` takes `placeHolder` (not `placeholder`); there is no `@input type='richtext'` (use `type='textarea' richtext=true`).

## Back-office macro bugs to work around (report upstream, do not copy the workaround into the FO)

- **`@input pattern=` and `accept=` are emitted unquoted and with no leading space**: `forms/input/input.ftl` contains `<#if pattern!=''>pattern=${pattern}</#if>` and `<#if accept!='' && type='file'>accept=${accept}</#if>`, so the attribute is glued to the previous one and cannot carry a space, `"`, `'`, `` ` ``, `=` or `>`. A pattern with a space-bearing quantifier or any `accept` list breaks the tag. Pass them through `params='pattern="…"'` until the core is fixed. The front-office twin `skin/themes/macros/forms/inputs/cInput.ftl` emits ` pattern="${pattern}"` correctly.
- **The neutral back-office button is `color='light'`, not `color='secondary'`**: `components/button/aButton.ftl` and `button.ftl` map `color='secondary'`, `color='default'`, `color='btn-secondary'` **and `cancel=true`** to the class `btn-default`, which no admin stylesheet defines — `.btn-default` exists only in the *site* theme (`themes/skin/lutece/css/themes/dark-theme.css`), while `tabler.min.css` and `bootstrap.min.css` define `.btn-secondary` and `.btn-light`. A back or cancel button written `color='secondary'` renders with no colour variant.
- **The parameter is `placeHolder`, not `placeholder`** (the emitted attribute is lowercase; the macro parameter is camelCase).

## Bootstrap 5 & Tabler Icons — Already Loaded

BS5 (CSS + JS) and Tabler Icons are globally loaded by the admin theme. Do NOT add `<link>` or `<script>` imports for these resources. Use BS5 classes and Tabler icons (`ti ti-*`) **only as a last resort** — when no Freemarker macro exists for the need AND no existing admin template in `~/.lutece-references/lutece-core/` already demonstrates the desired layout. Always prefer macros over raw HTML/BS5.

## Layout Structure (MANDATORY)

Every admin template MUST use: `@pageContainer` > `@pageColumn` > `@pageHeader`. Do NOT use `@row` / `@columns` / `@pageColumn` together. @row and @columns can be used only inside @pageColumn.

## List Layout — `@manageFeature` by default, `@table` for tabular data

- **Entity lists with CRUD actions** (manage pages): `@manageFeature` > `@manageFeatureItem` > `@manageFeatureItemColumn`. This is the layout of every core manage page (`rbac/manage_roles.html`, `mailinglist/manage_mailinglists.html`, 25 core templates) and of the forms manage pages (`manage_forms.html`, `manage_categories.html`, `manage_steps.html`). Items render as cards, so no `@box` around the list.
- **Tabular data** (several data columns per row, reports, grids, child-entity tables): `@table` with `<tr>/<th>/<td>`. Forms uses it in 9 templates. Never replace an existing well-formed `@table` "systematically": switch to `@manageFeature` only when the rows are entities with edit/delete actions.
- **Empty state**: test the list before iterating and render `@empty` otherwise.
- **Pagination**: `@paginationAdmin paginator=paginator combo=1` after the list (server-side, `IPager`). `@paginationAjax` (JSON endpoint + `@ResponseBody`, see `/lutece-patterns` §5) is an option for large datasets; no core or forms template uses it today.

## Navigation, dialogs and forms (blocking)

- **No offcanvas** (`verify-migration.sh` TM10, `scan-template-design.py` TD48). Content written in the page (search, a short creation form, editor properties) goes in `@modal` > `@modalHeader modalTitle` / `@modalBody` / `@modalFooter`, opened by `<@button type='button' params='data-bs-toggle="modal" data-bs-target="#id"' />`. Another page (create, modify, properties screen) is a plain link `<@aButton href>` (`<@link class='dropdown-item' href>` in a dropdown) to a full page with its own back link.
- **Required fields carry `mandatory=true`**: the BO `@tform` loads no validation module (the `@cForm` rule, TM11 / TD49, is front office only).
- **No inline form** (TM12, TD50): no `@tform type='inline'` / `'flex'`, no `form-inline` / `d-flex` on a form, no two `formStyle='inline'` fields in a form, no `@row` whose `@columns` each carry a text field (X/Y/width/height side by side, fields left and image right). One field per row; a grid of checkboxes or switches is allowed. A hidden form with a single submit button (Import, Export) may keep `type='inline'`.

## Messages — `@messages`

Render model messages with the core macro, once per page, right after `@pageHeader`:

```html
<@messages infos=infos![] errors=errors![] warnings=warnings![] />
```

`![]` is required: the three variables are absent from the model until `addError()`/`addInfo()`/`addWarning()` is called. The macro handles the two value types (`errors` are `MVCMessage`/`ParamError` objects read via `.message`; `infos` and `warnings` are `Set<String>`). When writing a loop by hand instead, follow the Null Safety section below.

## i18n Format
`#i18n{prefix.key.subkey}` — always reuse existing portal i18n utility keys instead of creating new ones whenever possible. Existing keys (`lutece-core/.../portal/resources/util_messages.properties`): `portal.util.labelActions`, `labelModify`, `labelDelete`, `labelCreate`, `labelBack`, `labelValidate`, `labelCancel`, `labelClose`, `labelYes`, `labelNo`, `labelEnabled`, `labelDisabled`, `labelSearch`, `labelNoItem`. Keys that do NOT exist: `portal.util.labelActive`, `labelInactive`, `labelSave`, `labelAdd` (use `labelEnabled`/`labelDisabled`/`labelValidate`/`labelCreate`).


**`#i18n{}`, the CSRF token and the datastore keys are resolved on the rendered output**, not during FreeMarker: `AppTemplateService` calls `I18nService.localize( template.getHtml( ), locale )` (`:272`, `:304`, `:334`), then `SecurityTokenHandler.addSecurityToken( template.getHtml( ), model )` (`:277`, `:309`, `:339`), then `DatastoreService.replaceKeys( template.getHtml( ) )` (`:343`). Two consequences:
- **A dynamic key works**: `#i18n{myplugin.label.${item.code}}` resolves, so N near-identical fields become one `<#list>` over a `<#assign>` descriptor sequence instead of N copied blocks. The core does exactly this in `commons_site.html:199` (`#i18n{${column.titleKey}}`) and `:216`, `:222`.
- **A template never writes `_csrftoken` itself**: the token is injected into the rendered `<form>`.

## Null Safety

Always use `${value!}` (with `!`) to handle null values in Freemarker expressions.

**Model variables `errors`, `infos`, `warnings`** are NOT pre-initialized — they only exist after `addError()`/`addInfo()`/`addWarning()` is called. Always use null-safe access:
- `<#if (errors!)?size gt 0>` NOT `<#if errors?size gt 0>`
- `<#list (errors![]) as error>` NOT `<#list errors as error>`
- Same for `infos` and `warnings`

**Value types** (`MVCAdminJspBean.addError/addMessage`, `MVCApplication` idem):
- `errors`: objects (`MVCMessage`, or `ParamError` from `BindingResult`) → `${error.message}`. `${error}` prints `toString()`.
- `infos`, `warnings`: `Set<String>` → `${info}`, `${warning}`. `${info.message}` throws.

# Examples :

## List Page Pattern

```html
<@pageContainer>
    <@pageColumn>
        <@pageHeader title='#i18n{myplugin.manage_tasks.pageTitle}'>
            <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=createTask' buttonIcon='plus' title='#i18n{myplugin.manage_tasks.buttonAdd}' color='primary' />
        </@pageHeader>
        <@messages infos=infos![] errors=errors![] warnings=warnings![] />
        <#if task_list?has_content>
            <@manageFeature>
                <#list task_list as task>
                <@manageFeatureItem>
                    <@manageFeatureItemColumn auto=true flex=false>${task.title!}</@manageFeatureItemColumn>
                    <@manageFeatureItemColumn align='end'>
                        <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=modifyTask&id=${task.idTask}' buttonIcon='edit' title='#i18n{portal.util.labelModify}' />
                        <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=confirmRemoveTask&id=${task.idTask}' buttonIcon='trash' color='danger' title='#i18n{portal.util.labelDelete}' />
                    </@manageFeatureItemColumn>
                </@manageFeatureItem>
                </#list>
            </@manageFeature>
            <@paginationAdmin paginator=paginator combo=1 />
        <#else>
            <@empty title='#i18n{portal.util.labelNoItem}' />
        </#if>
    </@pageColumn>
</@pageContainer>
```

Tabular variant (data grid, no per-row CRUD):

```html
<@table>
    <tr>
        <th>#i18n{myplugin.model.entity.task.attribute.title}</th>
        <th>#i18n{myplugin.model.entity.task.attribute.completed}</th>
    </tr>
    <#list task_list as task>
    <tr>
        <td>${task.title!}</td>
        <td><#if task.completed>#i18n{portal.util.labelYes}<#else>#i18n{portal.util.labelNo}</#if></td>
    </tr>
    </#list>
</@table>
```

## Form Page Pattern

```html
<@pageContainer>
    <@pageColumn>
        <@pageHeader title='#i18n{myplugin.create_task.pageTitle}'>
            <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=manageTasks' buttonIcon='arrow-left' title='#i18n{portal.util.labelBack}' />
        </@pageHeader>
        <@messages errors=errors![] />
        <@tform method='post' name='create_task' action='jsp/admin/plugins/myplugin/ManageTasks.jsp' boxed=true>
            <@input type='hidden' name='action' value='createTask' />
            <@formGroup labelFor='title' labelKey='#i18n{myplugin.model.entity.task.attribute.title}' mandatory=true rows=2>
                <@input type='text' name='title' id='title' value='${task.title!}' mandatory=true />
            </@formGroup>
            <@formGroup labelFor='description' labelKey='#i18n{myplugin.model.entity.task.attribute.description}' rows=2>
                <@input type='textarea' name='description' id='description'>${task.description!}</@input>
            </@formGroup>
            <@formGroup labelFor='id_category' labelKey='#i18n{myplugin.model.entity.task.attribute.category}' rows=2>
                <@select name='id_category' id='id_category' items=category_list default_value='${task.idCategory!}' />
            </@formGroup>
            <@formGroup labelFor='completed' labelKey='#i18n{myplugin.model.entity.task.attribute.completed}' rows=2>
                <@checkBox orientation='switch' labelKey='#i18n{myplugin.model.entity.task.attribute.completed}' name='completed' id='completed' value='true' checked=task.completed!false />
            </@formGroup>
            <@formGroup rows=2>
                <@button type='submit' buttonIcon='check' title='#i18n{portal.util.labelValidate}' color='primary' />
                <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=manageTasks' buttonIcon='x' title='#i18n{portal.util.labelCancel}' color='light' />
            </@formGroup>
        </@tform>
    </@pageColumn>
</@pageContainer>
```

No `_csrftoken` hidden field: with `securityTokenEnabled = true` on the `@Controller`, the core injects it into every `<form>` at render time (see `rules/web-bean.md`). `category_list` is a `ReferenceList` put in the model by the bean.

## JavaScript — Vanilla Only, No jQuery

- The admin theme does NOT load jQuery (`adminHeader.ftl` only includes it when the optional `library-theme-jquery` is present). Any `$`/`jQuery` call fails at runtime.
- **NEVER** use jQuery (`$`, `jQuery`, `$.ajax`, `.click()`, `.on()`, etc.)
- Use native DOM APIs: `document.querySelector`, `addEventListener`, `fetch`, `classList`, `dataset`
- Use ES6+: `const`/`let`, arrow functions, template literals, destructuring, `async`/`await`
- Code that depends on a jQuery plugin (DataTables, Select2, jQuery UI, Cropper, suggestPOI…) cannot be converted mechanically. Decide mechanically instead:
  1. Grep the project's `pom.xml` for `library-theme-jquery`. **Declared**: the theme loads jQuery (`adminHeader.ftl` includes `<@jqueryHeader />` when `jqueryHeader??`, `page_frameset.html` loads `commons_theme_jquery.html` when it exists), the calls run, keep them and name in the report the widget that justifies the dependency.
  2. **Not declared**: the calls fail silently at runtime. Port them with the conversion table (`skills/lutece-update-template-fo/reference/patterns.md` § jQuery → Vanilla JS) when they are plain DOM work, which is the usual case for show/hide/val/append.
  3. Not declared **and** the code drives a jQuery plugin that has no vanilla equivalent: the fix is a `pom.xml` dependency, not a template edit. Report it to the owner of the build; never leave the calls unflagged.
  The scanner does this cross-check (`TD12`): WARN when jQuery appears and the pom does not declare the library, INFO when it does.

## Third-Party Libraries — No CDN

- **NEVER** use CDN links. All third-party JS/CSS must be downloaded and placed locally.
- JS files go in `webapp/js/{pluginName}/`
- CSS files go in `webapp/css/{pluginName}/`

## Auto-escaping — write templates that render the same in both modes (LUT-33153, upstream in progress)

The core carries `service.freemarker.templateAutoEscape` (default `false`). A branch of `lutece-core`
(`LUT-33153-autoescape-bicompat`; check `git branch -r` of the core reference to know whether it has merged) makes the whole rendering pass with the property
at `true`, ships codemods (`tools/autoescape/`) and a guide, and states the order of work: core first as a
compatibility pass, then every plugin, then the property. A plugin template written today has to survive both
values, and four built-ins do not: `?html` and `?xhtml` are a **ParseException** when the property is `true`,
`?no_esc` and `?esc` when it is `false` — the template does not load at all.

| Goal | Do not write | Write |
|---|---|---|
| Print HTML unescaped | `${x?no_esc}` | `<#noautoesc>${x}</#noautoesc>` |
| Escape explicitly | `${x?html}`, `${x?esc}` | `<#outputformat "HTML">${x}</#outputformat>` |
| Escape inside a macro argument (a directive cannot sit in a string) | `params='title="${x?html}"'` | capture first: `<#assign p><#outputformat "HTML">title="${x}"</#outputformat></#assign>` then `params=p` |
| URL-encode a value | `${x?url}` — **throws at render time**: the Lutece FreeMarker configuration sets no `url_escaping_charset` nor `output_encoding` (`AbstractFreeMarkerTemplateService` calls `setNumberFormat`, `setOutputFormat`, `setAutoEscapingPolicy`… and neither of those two) | `${x?url('UTF-8')}` |
| Interpolate a value into JavaScript (string literal or identifier inside `<script>`) | `${x}` — HTML escaping does not protect a JS context | `${x?js_string}` |
| Test a captured block | `c != ''`, `c = ''` | `c?has_content`, `!c?has_content` |
| Pass a bundle of attributes to a macro | `<#assign p = 'title="x"'>` | `<#assign p>title="x"</#assign>` |

Why the capture: under auto-escaping a block capture is *markup* (already-safe HTML) and a string literal is
not — a string holding HTML gets escaped a second time when a macro prints it. Escaping through a captured
`<#outputformat "HTML">` block is what `?html` did, and it parses under both settings.

HTML built on the Java side cannot be told apart from text by the template: on the branch the model carries it
as `HtmlMarkup.of( html )` and the template prints a plain `${x}`. Until that reaches develop, skin templates
run with an undefined output format and print the value as it is — do not add `?no_esc` there, it is refused.

Do **not** put `<#ftl output_format="HTML" auto_esc=true>` at the top of plugin templates as a migration
vehicle: a non-migrated caller feeding a migrated macro double-escapes, and nothing catches it.
