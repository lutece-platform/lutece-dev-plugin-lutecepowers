---
description: "Lutece 8 front-office (skin/site) templates: FO macros (c*), Bootstrap 5, vanilla JS, messages null-safety"
paths:
  - "**/templates/skin/**/*.html"
---

# Front-Office Templates — Lutece 8

## Reference Sources — MANDATORY

- Macro definitions: `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/skin/themes/macros/{components,elements,forms,layout,utilities}/**/*.ftl` (one file per macro, e.g. `components/alert/cAlert.ftl`, `forms/inputs/cField.ftl`, `elements/footer/cFooter.ftl`).
- `@cTpl` is defined in `skin/themes/global_theme_commons.ftl`: it lets a site theme override the whole template; wrap every FO template in it.
- Template examples: `~/.lutece-references/lutece-form-plugin-forms/webapp/WEB-INF/templates/skin/plugins/forms/*.html`.

Read the `.ftl` signature before using a macro parameter. FreeMarker allows `<@m />` for any macro, so a macro without nested content may be self-closing.

## Already Loaded by the Core — No Import Needed

Bootstrap 5 (CSS + JS), Tabler Icons and core JS modules are globally loaded by the site frameset. Do NOT add `<link>`, `<script>` or `import` tags for these resources.

## CSS — Bootstrap 5 Only

Use exclusively Bootstrap 5 utility classes and components. No custom CSS unless strictly necessary. Refer to BS5 docs for class names (`container`, `row`, `col-*`, `card`, `btn`, `form-control`, `d-flex`, `gap-*`, etc.).

## JavaScript — Vanilla Only, No jQuery

- The site frameset does NOT load jQuery (`page_frameset.html`: "jQuery JS is no more included", loaded only when the optional `library-theme-jquery` provides `commons_theme_jquery.html`). Any `$`/`jQuery` call fails at runtime.
- **NEVER** use jQuery (`$`, `jQuery`, `$.ajax`, `.click()`, `.on()`, etc.)
- Use native DOM APIs: `document.querySelector`, `addEventListener`, `fetch`, `classList`, `dataset`
- Use ES6+: `const`/`let`, arrow functions, template literals, destructuring, `async`/`await`
- Code that depends on a jQuery plugin (DataTables, Select2, jQuery UI, Cropper, suggestPOI…) cannot be converted mechanically. Decide mechanically instead:
  1. Search the project's `pom.xml` for `library-theme-jquery`. **Declared**: the theme loads jQuery (`page_frameset.html` loads `commons_theme_jquery.html` when it exists), the calls run, keep them and name in the report the widget that justifies the dependency.
  2. **Not declared**: the calls fail silently at runtime. Port them with the conversion table (`skills/lutece-update-template-fo/reference/patterns.md` § jQuery → Vanilla JS) when they are plain DOM work, which is the usual case for show/hide/val/append.
  3. Not declared **and** the code drives a jQuery plugin that has no vanilla equivalent: the fix is a `pom.xml` dependency, not a template edit. Report it to the owner of the build; never leave the calls unflagged.
  The scanner does this cross-check (`TD12`): WARN when jQuery appears and the pom does not declare the library, INFO when it does.

## Third-Party Libraries — No CDN

- **NEVER** use CDN links. All third-party JS/CSS must be downloaded and placed locally.
- JS files go in `webapp/js/{pluginName}/`
- CSS files go in `webapp/css/{pluginName}/`
- The skin theme loads the Tabler icons from `themes/shared/css/vendor/tabler/`, not Bootstrap Icons (`bi bi-*`: use Tabler `ti ti-*`). It does not ship `js/plugins/asynchronousupload`, `js/plugins/forms` (Sortable) nor `js/plugins/genericattributes/modules/openstreetmap` (Leaflet) under `themes/skin/lutece/`. A plugin that needs one ships it in its own webapp or uses a core equivalent.

## Common Patterns

- Icons: `@cIcon` or Tabler icon classes (`ti ti-*`)
- Null safety in Freemarker: always `${value!}`
- i18n: `#i18n{prefix.key}` — reuse `portal.util.*` keys from `~/.lutece-references/lutece-core` when possible (see `rules/template-back-office.md` for the list of existing keys)
- Forms: no `_csrftoken` hidden field, the core injects it into every `<form>` when the XPage `@Controller` has `securityTokenEnabled = true` (see `rules/web-bean.md`)

## Forms and dialogs (blocking)

- **Every form is `<@cForm>`** (`verify-migration.sh` TM11, `scan-template-design.py` TD49): it loads the core `theme-form-validation` by default. Never `foValidation=false`, never a raw `<form>`.
- **No offcanvas** (TM10, TD48): content of the page goes in `<@cModal title id>`; the macro suffixes the id, so `id='search'` is opened by `data-bs-toggle="modal" data-bs-target="#searchModal"`. Another page is reached by a plain link (`@cLink`, `@cBtn href`).
- **No inline form** (TM12, TD50): never three visible fields or more side by side (`form-inline`, `d-flex` on a form, a `@cRow` with three `@cCol` or more that each carry a text field). Two columns are fine.

## Model Messages — Null-Safety and Value Types (MANDATORY)

`errors`, `infos`, `warnings` are **NOT pre-initialized** in the model — they only exist after `addError()`/`addInfo()`/`addWarning()` is called (`MVCApplication.addMessage`). Value types differ:
- `errors`: objects (`MVCMessage`, or `ParamError` from `BindingResult`) → `${error.message}`
- `infos`, `warnings`: `Set<String>` → `${info}`, `${warning}`. `${info.message}` throws `NonHashException`.

```html
<#list (errors![]) as error><@cAlert type='danger' title=error.message! /></#list>
<#list (infos![]) as info><@cAlert type='info' title=info /></#list>
<#list (warnings![]) as warning><@cAlert type='warning' title=warning /></#list>
```

Never `<#if errors?size gt 0>` or `<#list errors as error>` without the `!` default.

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
| A URL that comes from data (a site property, a stored link) | `href="${url}"`: escaping does not stop a `javascript:` URL | `href="${safeUrl(url)}"` (relative, http, https, mailto, tel; `'#'` otherwise, or `safeUrl(url, fallback)`); in CSS `url('${cssUrl(url)}')` |
| A conditional attribute | `cond?then('aria-current="true"', '')` | `cond?then({'aria-current': 'true'}, {})` |
| HTML the application renders (a sub-template, a captcha, a list of rows) | `model.put( MARK_X, strHtml )` (AE01: shown as text); `<#noautoesc>` | `model.put( MARK_X, HtmlMarkup.of( strHtml ) )`, `HtmlMarkup.ofAll( list )`; in the template, `${x?no_esc}` (core `admin/features/assign_users_right.html`: `${attribute.getHtmlFormSearchAttribute( … )?no_esc}`) |
| Rich text stored by a user or an admin (editor, BBCode rendered to HTML) | `${x?no_esc}` on a value nobody cleaned; `${page.htmlContent}` (TM19: the tags show as text) | `${richText(x!)}` (sanitized markup) in the template, or `HtmlMarkup.ofSanitized( x )` in Java |
| Print markup a template captured | `${p?no_esc}` | `${p}`: a capture is markup already |
| Read a captured block as text | `p?trim`, `p == ''`, `default_value=p` (TM16: fails) | `p?markup_string?trim`, `p?has_content`, or assign the string itself: `<#assign v = cond?then(a?c, '-1')>` |
| Escape explicitly | `${x?html}`, `${x?esc}` (`?html` is a ParseException in the HTML output format) | `${x}` |
| A value in JavaScript (string literal inside `<script>`) | `${x}` (HTML escaping is not JS escaping); `${x?js_string}` (HTML-escaped on top: the script reads `\&#39;`) | `${x?js_string?no_esc}`, inside a `<script>` only |
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

## i18n resolution order

**`#i18n{}`, the CSRF token and the datastore keys are resolved on the rendered output**, not during FreeMarker: `AppTemplateService` calls `I18nService.localize( template.getHtml( ), locale )`, then `SecurityTokenHandler.addSecurityToken( template.getHtml( ), model )`, then `DatastoreService.replaceKeys( template.getHtml( ) )`. Two consequences:
- **A dynamic key works**: `#i18n{myplugin.label.${item.code}}` resolves, so N near-identical fields become one `<#list>` over a `<#assign>` descriptor sequence instead of N copied blocks. The core does exactly this in `commons_site.html` (`#i18n{${column.titleKey}}`).
- **A template never writes `_csrftoken` itself**: the token is injected into the rendered `<form>`.

## A project on core 8.0.2

Auto-escaping is off by default and `htmlAttributes`, `HtmlMarkup`, `richText`, `safeUrl`, `cssUrl` and
`data-lutece-action` do not exist: `params` is a string written as is (`params='data-x="1"'`) and `${x?url}` needs
`${x?url('UTF-8')}`.
