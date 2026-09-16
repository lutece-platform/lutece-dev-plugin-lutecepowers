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
- Code that depends on a jQuery plugin (DataTables, Select2, jQuery UI…) cannot be converted mechanically: port it manually or add `library-theme-jquery` as an explicit, documented dependency.

## Third-Party Libraries — No CDN

- **NEVER** use CDN links. All third-party JS/CSS must be downloaded and placed locally.
- JS files go in `webapp/js/{pluginName}/`
- CSS files go in `webapp/css/{pluginName}/`

## Common Patterns

- Icons: `@cIcon` or Tabler icon classes (`ti ti-*`)
- Null safety in Freemarker: always `${value!}`
- i18n: `#i18n{prefix.key}` — reuse `portal.util.*` keys from `~/.lutece-references/lutece-core` when possible (see `rules/template-back-office.md` for the list of existing keys)
- Forms: no `_csrftoken` hidden field, the core injects it into every `<form>` when the XPage `@Controller` has `securityTokenEnabled = true` (see `rules/web-bean.md`)

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
