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

- **The neutral back-office button is `color='light'`, not `color='secondary'`**: `components/button/aButton.ftl` and `button.ftl` map `color='secondary'`, `color='default'`, `color='btn-secondary'` **and `cancel=true`** to the class `btn-default`, which no admin stylesheet defines — `.btn-default` exists only in the *site* theme (`themes/skin/lutece/css/themes/dark-theme.css`), while `tabler.min.css` and `bootstrap.min.css` define `.btn-secondary` and `.btn-light`. A back or cancel button written `color='secondary'` renders with no colour variant.
- **The parameter is `placeHolder`, not `placeholder`** (the emitted attribute is lowercase; the macro parameter is camelCase).

## Bootstrap 5 & Tabler Icons — Already Loaded

BS5 (CSS + JS) and Tabler Icons are globally loaded by the admin theme. Do NOT add `<link>` or `<script>` imports for these resources. Use BS5 classes and Tabler icons (`ti ti-*`) **only as a last resort** — when no Freemarker macro exists for the need AND no existing admin template in `~/.lutece-references/lutece-core/` already demonstrates the desired layout. Always prefer macros over raw HTML/BS5.

## Layout Structure (MANDATORY)

Every admin template MUST use: `@pageContainer` > `@pageColumn` > `@pageHeader`. `@row` / `@columns` only inside `@pageColumn`.

Headings: `@pageHeader` writes the `h1` of the page, `@boxHeader` an `h2` by default, the alert titles of `@messages` an `h2` styled as `h4`. Never force `titleLevel='h3'` or `'h4'` on them: a heading level would be skipped.

## List Layout — `@manageFeature` by default, `@table` for tabular data

- **Entity lists with CRUD actions** (manage pages): `@manageFeature` > `@manageFeatureItem` > `@manageFeatureItemColumn`. This is the layout of every core manage page (`rbac/manage_roles.html`, `mailinglist/manage_mailinglists.html`) and of the forms manage pages (`manage_forms.html`, `manage_categories.html`, `manage_steps.html`). Items render as cards, so no `@box` around the list. Copy them whole: their create and modify screens are pages, their `@empty` sits in a `@card`.
- **Tabular data** (several data columns per row, reports, grids, child-entity tables): `@table` with `<tr>/<th>/<td>`. Never replace an existing well-formed `@table` "systematically": switch to `@manageFeature` only when the rows are entities with edit/delete actions.
- **Empty state**: test the list before iterating and render `@empty` otherwise.
- **Pagination**: `@paginationAdmin paginator=paginator combo=1` after the list (server-side, `IPager`). `@paginationAjax` (JSON endpoint + `@ResponseBody`, macro in core `webapp/WEB-INF/templates/admin/themes/tabler/components/pagination/paginationAdmin.ftl`) is an option for large datasets.

## Navigation, dialogs and forms (blocking)

- **No offcanvas** (`verify-migration.sh` TM10, `scan-template-design.py` TD48). Content written in the page (search, a short creation form, editor properties) goes in `@modal` > `@modalHeader modalTitle` / `@modalBody` / `@modalFooter`, opened by `<@button type='button' params={'data-bs-toggle': 'modal', 'data-bs-target': '#id'} />`. Another page (create, modify, properties screen) is a plain link `<@aButton href>` (`<@link class='dropdown-item' href>` in a dropdown) to a full page with its own back link. A view that was the body of an offcanvas becomes that full page: `@pageContainer` > `@pageColumn` > `@pageHeader` with its title and a back button to the list, the `getPage( title, template )` of its controller, no `target="_top"` left on its links and forms, and none of the offcanvas markup (`data-bs-dismiss="offcanvas"`, `offcanvas-*` classes) left in the calling page.
- **Required fields carry `mandatory=true`**: the BO `@tform` loads no validation module (the `@cForm` rule, TM11 / TD49, is front office only).
- **No inline form** (TM12, TD50): never three fields or more side by side: no `@tform type='inline'` / `'flex'`, `form-inline` / `d-flex` on a form holding three fields, no two `formStyle='inline'` fields in a form, no `@row` with three `@columns` or more that each carry a text field (X/Y/width/height in a row). Two columns are fine (fields and an image, first and last name); a grid of checkboxes or switches is allowed. A hidden form with a single submit button (Import, Export) may keep `type='inline'`.

## Rich text editor

- A rich field is `<@input type='textarea' name='x' richtext=true />` (the macro adds the class `richtext`), then, once per page, `<#include "/admin/util/editor/editor.html" />` and `<@initEditor />`, which targets `.richtext` (core `admin/system/modify_properties.html`). The front office is the same with `/util/editor/editor.html`.
- **No editor without a rich field** (TD59): `@initEditor` on a page with no `.richtext` loads TinyMCE for nothing and the core init throws on the empty selection.
- **The JspBean puts `webapp_url`** (`AppPathService.getBaseUrl( request )`) in the model of every page with an editor, as the core's own JspBeans do: the editor passes it as `document_base_url`, and without it TinyMCE resolves its content stylesheets against its own folder (four 404 per page).
- A rich field in a Bootstrap modal needs TinyMCE's documented `focusin` guard, otherwise the modal steals the focus of the editor's dialogs.

## Messages — `@messages`

Render model messages with the core macro, once per page, right after `@pageHeader`:

```html
<@messages infos=infos![] errors=errors![] warnings=warnings![] />
```

`![]` is required: the three variables are absent from the model until `addError()`/`addInfo()`/`addWarning()` is called. The macro handles the two value types (`errors` are `MVCMessage`/`ParamError` objects read via `.message`; `infos` and `warnings` are `Set<String>`). When writing a loop by hand instead, follow the Null Safety section below.

## i18n Format
`#i18n{prefix.key.subkey}` — always reuse existing portal i18n utility keys instead of creating new ones whenever possible. Existing keys (`lutece-core/.../portal/resources/util_messages.properties`): `portal.util.labelActions`, `labelModify`, `labelDelete`, `labelCreate`, `labelBack`, `labelValidate`, `labelCancel`, `labelClose`, `labelYes`, `labelNo`, `labelEnabled`, `labelDisabled`, `labelSearch`, `labelNoItem`. Keys that do NOT exist: `portal.util.labelActive`, `labelInactive`, `labelSave`, `labelAdd` (use `labelEnabled`/`labelDisabled`/`labelValidate`/`labelCreate`).

**`#i18n{}`, the CSRF token and the datastore keys are resolved on the rendered output**, not during FreeMarker: `AppTemplateService` calls `I18nService.localize( template.getHtml( ), locale )`, then `SecurityTokenHandler.addSecurityToken( template.getHtml( ), model )`, then `DatastoreService.replaceKeys( template.getHtml( ) )`. Two consequences:
- **A dynamic key works**: `#i18n{myplugin.label.${item.code}}` resolves, so N near-identical fields become one `<#list>` over a `<#assign>` descriptor sequence instead of N copied blocks. The core does exactly this in `commons_site.html` (`#i18n{${column.titleKey}}`).
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
            <@aButton href='jsp/admin/plugins/myplugin/ManageTasks.jsp?view=manageTasks' buttonIcon='arrow-left' title='#i18n{portal.util.labelBack}' color='light' />
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
  1. Search the project's `pom.xml` for `library-theme-jquery`. **Declared**: the theme loads jQuery (`adminHeader.ftl` includes `<@jqueryHeader />` when `jqueryHeader??`, `page_frameset.html` loads `commons_theme_jquery.html` when it exists), the calls run, keep them and name in the report the widget that justifies the dependency.
  2. **Not declared**: the calls fail silently at runtime. Port them with the conversion table (`skills/lutece-update-template-fo/reference/patterns.md` § jQuery → Vanilla JS) when they are plain DOM work, which is the usual case for show/hide/val/append.
  3. Not declared **and** the code drives a jQuery plugin that has no vanilla equivalent: the fix is a `pom.xml` dependency, not a template edit. Report it to the owner of the build; never leave the calls unflagged.
  The scanner does this cross-check (`TD12`): WARN when jQuery appears and the pom does not declare the library, INFO when it does.

## Third-Party Libraries — No CDN

- **NEVER** use CDN links. All third-party JS/CSS must be downloaded and placed locally.
- JS files go in `webapp/js/{pluginName}/`
- CSS files go in `webapp/css/{pluginName}/`
- The admin theme loads Bootstrap inside `tabler.min.js` (`commons_bs5_tabler.html`), the Tabler icons from `themes/shared/css/vendor/tabler/` and slimselect from `themes/shared/lib/slimselect/`. It does not ship Bootstrap Icons (`bi bi-*`: use Tabler `ti ti-*`), bootstrap-table (`themes/admin/shared/js/lib/table`), toastr, bootstrap-colorpicker, a separate `bootstrap.bundle.min.js` nor Popper. A plugin that needs one ships it in its own webapp or uses a core equivalent.

## Auto-escaping (always on)

Every template renders with the HTML output format and auto-escaping (`AbstractFreeMarkerTemplateService` of
library-freemarker), whatever its extension: `.html`, `.ftl`, `.txt`, `.xml` (a text mail, a CSV) alike. Only `.js`,
`.json` and `.css` templates get their own output format and escape their values themselves (`?js_string`,
`?json_string`). A template whose output is not HTML starts with `<#ftl output_format="plainText">` (core
`admin/user/export/export_csv.ftl`). `service.freemarker.templateAutoEscape=false` is ignored with an error in the log
(`FreeMarkerTemplateService`). Back office and skin alike: `${x}` prints `x` escaped.

| Goal | Do not write | Write |
|---|---|---|
| Attributes of a macro element | `params='data-x="1"'`, a captured block, a string variable (TM14: the rendering fails) | a map: `params={'data-x': '1', 'aria-label': label}` |
| A class, a style, an event handler, a URL, an attribute the macro writes itself, on a macro element | `params={'class': …}`, `{'style': …}`, `{'onclick': …}`, `{'href'/'src'/'formaction': …}`, `{'id': …}` beside `id=` (TM15: refused) | `class=` of the macro; a theme class; the macro parameter; a raw element (`<span style="width:${w}%">`, `<button formaction="${url}">`), whose `${…}` is escaped |
| A behaviour (`onclick`, `onchange`, `onerror`, `href="javascript:…"`) | an event handler attribute or a `javascript:` URL, in raw HTML or in `params` | `data-lutece-action`: `back`, `close`, `hide-parent`, `skip` on a link or a button, `submit` on a field (submits its form on change); `data-lutece-confirm="message"`; `data-lutece-fallback-src="url"` on an image (`themes/{admin,skin}/shared/js/util/lutece-actions.js`, loaded by both themes). Anything else: `addEventListener` in the page script |
| A URL that comes from data (a site property, a stored link) | `href="${url}"`: escaping does not stop a `javascript:` URL (TM21) | `href="${safeUrl(url)}"` (relative, http, https, mailto, tel; `'#'` otherwise, or `safeUrl(url, fallback)`); in CSS `url('${cssUrl(url)}')` |
| A conditional attribute | `cond?then('aria-current="true"', '')` | `cond?then({'aria-current': 'true'}, {})` |
| HTML the application renders (a sub-template, a captcha, a list of rows) | `model.put( MARK_X, strHtml )` (AE01: shown as text); `<#noautoesc>` | `model.put( MARK_X, HtmlMarkup.of( strHtml ) )`, `HtmlMarkup.ofAll( list )`; in the template, `${x?no_esc}` (core `admin/features/assign_users_right.html`: `${attribute.getHtmlFormSearchAttribute( … )?no_esc}`) |
| Rich text stored by a user or an admin (editor, BBCode rendered to HTML) | `${x?no_esc}` on a value nobody cleaned; `${page.htmlContent}` (TM19: the tags show as text) | `${richText(x!)}` (sanitized markup) in the template, or `HtmlMarkup.ofSanitized( x )` in Java |
| Print markup a template captured | `${p?no_esc}` | `${p}`: a capture is markup already |
| Read a captured block as text | `p?trim`, `p == ''`, `default_value=p` (TM16: fails) | `p?markup_string?trim`, `p?has_content`, or assign the string itself: `<#assign v = cond?then(a?c, '-1')>` |
| Escape explicitly | `${x?html}`, `${x?esc}` (`?html` is a ParseException in the HTML output format) | `${x}` |
| A value in JavaScript (string literal inside `<script>`) | `${x}` (HTML escaping is not JS escaping); `${x?js_string}` (HTML-escaped on top: the script reads `\&#39;`) | `${x?js_string?no_esc}`, inside a `<script>` only |
| An i18n message inside `<script>` | `'#i18n{key}'` (TM20: replaced after the rendering, as is; an apostrophe of the translation ends the string) | `'${i18n('key')?js_string?no_esc}'`; `i18n('key', arg)` for a message with arguments |
| A value in a `<textarea>` or an input being edited | `${x?no_esc}` | `${x}`: escaped is right there |
| A special character in a string literal | `href='a?x=1&amp;y=2'`, `label='&#8722;'` (TM18: escaped once more, the page shows the entity) | the character itself: `href='a?x=1&y=2'`, `label='−'` |
| A text turned to markup in Java (`HtmlMarkup.of`, `richText`) read by a string built-in | `x?contains('…')`, `x?replace(…)` (fails: markup) | `x?markup_string?contains('…')` |

A refused attribute is left out with a warning in the log under `portal.template.params.strict=false` (the default of
the core `config.properties`), and fails the rendering under `true`, the value the core gives its own tests
(`%test.portal.template.params.strict=true`) and recommends for continuous integration. A page that looks right may
have lost an attribute: read the log.

A parameter of a project macro never takes the name of a macro its body calls (`icon=` beside `<@icon>`): inside the
body the parameter hides the macro (TM17). A macro parameter is not the attribute it sounds like: read the macro
(the `role` of `cForm` writes `aria-label`; a real `role` goes in `params={'role': 'search'}`). After a template change
on a running bench, the template cache keeps the old version for `service.freemarker.templateUpdateDelay` seconds:
check the rendered page, not the source.

## A project on core 8.0.2

Auto-escaping is off by default and `htmlAttributes`, `HtmlMarkup`, `richText`, `safeUrl`, `cssUrl` and
`data-lutece-action` do not exist: `params` is a string written as is
(`params='data-bs-toggle="modal" data-bs-target="#id"'`), `${x?url}` needs `${x?url('UTF-8')}`, and `@input` writes
`pattern=` and `accept=` unquoted: pass them through `params='pattern="…"'`. `?no_esc` does not parse there: a value
in JavaScript is `${x?js_string}`, an i18n message `${i18n('key')?js_string}`.
