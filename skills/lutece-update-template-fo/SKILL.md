---
name: lutece-update-template-fo
description: "Converts a Lutece Front Office (skin) template to the FO FreeMarker macros of lutece-core. Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the rules that are not readable from the macro files: the FO macros are never the Back Office ones, the FreeMarker syntax to use, Bootstrap 5 classes, and the jQuery that must become vanilla JS. Takes the template path as argument. Triggers on 'migrer un template FO', 'convertir un template skin', 'macros FO', 'front office template', 'update skin template'."
allowed-tools: Bash(ls *) Bash(grep *) Bash(sed *) Bash(find *)
---

# Updating a Lutece FO template

Replace raw HTML with the skin FreeMarker macros. **This skill does not list the macros** — the core
sources do, and they are the only current version. Read them.

## Step 0 — Discover the macros

Root: `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/skin/themes/macros/`
(reference clones are synced at session start; see `using-lutecepowers`).

One file per macro, the filename is the macro name, grouped by domain. **Every FO macro name starts
with `c`** — `cForm`, `cBtn`, `cAlert`, `cCard`, `cSelect`. A name without that prefix is almost always
a Back Office macro, which does not exist here.

```bash
cd ~/.lutece-references/lutece-core/webapp/WEB-INF/templates/skin/themes/macros
ls -d */*/                                # every domain: components/…, forms/…, elements/…, layout/…
grep -rh '^<#macro' forms/inputs/         # every signature of one domain, with all its parameters
grep -rl '^<#macro  *cBtn\b' .            # which file defines one macro
sed -n '1,25p' components/card/cCard.ftl  # its documented parameters and a snippet
```

Every `.ftl` opens with a header block — `Macro:`, `Description:`, `Parameters:` with type and whether
optional. That header is the contract.

**Read a macro's file before using it for the first time in a session.** A wrong parameter name renders
an empty element without raising an error.

If the clone is missing, the theme also ships in any assembled site under
`target/lutece/WEB-INF/templates/skin/themes/macros/`.

## Steps

1. Read the target template.
2. For each block of raw HTML, find the domain that covers it (step 0) and read the signatures.
3. Rewrite using only macros.
4. Do not touch the i18n files unless asked.

## Additional resources

- Per-macro and situational rules — inputs, selects, checkboxes, steps, cards, figures, lists, tables,
  jQuery to vanilla JS: [reference/patterns.md](reference/patterns.md)
- Complete page examples to copy from: [reference/examples.md](reference/examples.md)
- Front-office conventions: `rules/template-front-office.md`

## Cross-cutting conventions

### Global structure
- **Always** wrap the template in `<@cTpl>...</@cTpl>`
- `<@cContainer>` is optional, use it only if the content requires a centered container
- You can go directly from `<@cTpl>` to `<@cCol>`, `<@cRow>`, or `<@cCard>` as needed
- For full-page forms: `<@cTpl>` → `<@cCol>` → `<@cForm>` → `<@cRow>` → `<@cCol>` → content

### Bootstrap 3 → Bootstrap 5 classes
- `help-block` → `form-text` (help text under a field)
- `control-label` → remove (handled by the macro)
- `col-xs-*` → `col-*` (the `xs` breakpoint no longer exists in BS5)
- `has-error` → `is-invalid` (validation)
- `btn-default` → `btn-secondary`

### FreeMarker HTML entities
- **Replace `&gt;`** with `gt` in FreeMarker conditions: `<#if list?size gt 0>` (not `&gt;`)
- **Replace `&lt;`** with `lt` in FreeMarker conditions: `<#if value lt 10>` (not `&lt;`)

### FreeMarker ternary operator
- **FreeMarker does NOT support** the C-style ternary operator `condition ? a : b`
- **Always use** `condition?then(a, b)`:
  ```freemarker
  <#-- INCORRECT — causes a ParseException -->
  <#assign myClass = 'base' + (hasError ? ' error' : '')>

  <#-- CORRECT -->
  <#assign myClass = 'base' + hasError?then(' error', '')>
  ```
- For boolean expressions, put the condition in parentheses if necessary: `(x != '')?then('a', 'b')`

### cForm - Forms
- Attributes not covered by the parameters via `params`: `params='name="createAccount"'`

### i18n
- All displayed text must use `#i18n{plugin.key}`
- Do not write hardcoded text in the template

### Code readability
- **Expand the `<#list>` with conditional logic** across multiple lines, do not leave compact inline blocks when they contain nested `<#if>`

### BO vs FO macros - Do not mix
- **Never use BO macros** (admin/Tabler) in an FO (skin) template. BO macros such as `<@messages>`, `<@aButton>`, `<@button>`, `<@box>`, `<@formGroup>`, `<@tform>`, `<@select>`, `<@option>` are **not** available in the FO context
- BO → FO equivalents:
  - `<@messages infos=infos errors=errors />` →
    ```freemarker
    <#list (infos![]) as info><@cAlert type='info' title=info /></#list>
    <#list (warnings![]) as warning><@cAlert type='warning' title=warning /></#list>
    <#list (errors![]) as error><@cAlert type='danger' title=error.message! /></#list>
    ```
    `infos` and `warnings` are `Set<String>` (`${info.message}` throws), `errors` are `MVCMessage`/`ParamError` objects: `rules/template-front-office.md` § Model Messages.
  - `<@aButton href='...' size='sm'>` → `<@cBtn href='...' class='outline-secondary btn-sm'>` (choose the color according to the context: `outline-primary`, `outline-secondary`, etc.)
  - `<@button>` → `<@cBtn>`
  - `<@tform>` → `<@cForm>`
  - `<@formGroup>` → `<@cField>` or `<@cBlock>`
  - `<@select>` / `<@option>` → `<@cSelect>` / `<@cOption>`

### style attribute on macros
- **Do not use `style='...'`** directly as a macro parameter — it is not a valid parameter of `<@cCol>`, `<@cTitle>`, `<@cTd>`, etc.
- Use `params='style="..."'` if absolutely necessary, or **prefer a CSS class**:
  ```freemarker
  <#-- INCORRECT -->
  <@cTitle level=2 style='margin-bottom:30px'>
  <@cTd style='vertical-align: middle'>

  <#-- CORRECT -->
  <@cTitle level=2 class='mb-4'>
  <@cTd class='align-middle'>
  ```

### FreeMarker conditions - Empty if branch
- **Never** leave an empty `<#if>` branch with all the content in `<#else>` — invert the condition:
  ```freemarker
  <#-- INCORRECT — empty if branch -->
  <#if modifDateAppointment?? && modifDateAppointment>
  <#else>
      ...content...
  </#if>

  <#-- CORRECT — inverted condition -->
  <#if !(modifDateAppointment?? && modifDateAppointment)>
      ...content...
  </#if>
  ```

### FreeMarker - Modern syntax (`??` vs `?exists`)
- **Always use `??`** instead of `?exists` — `?exists` is obsolete in FreeMarker 2.3+
  ```freemarker
  <#-- INCORRECT -->
  <#if entry.helpMessage?exists && entry.helpMessage != ''>

  <#-- CORRECT -->
  <#if entry.helpMessage?? && entry.helpMessage != ''>
  ```
- Applies everywhere: variables, object properties, optional parameters

### Dynamic classes (conditional concatenation)
- **Always pre-build** the `class` string with `<#assign>` rather than inline FreeMarker in the `class` parameter
  ```freemarker
  <#-- INCORRECT — inline FreeMarker in class -->
  <@cBlock class='bl-body<#if !blog.displayToc> bl-body-one-col</#if>'>

  <#-- CORRECT — assign before the macro -->
  <#assign bodyClass = 'bl-body'>
  <#if !blog.displayToc><#assign bodyClass = bodyClass + ' bl-body-one-col'></#if>
  <@cBlock class=bodyClass>
  ```
- The `?then(a, b)` pattern is also acceptable for only 1 or 2 classes:
  ```freemarker
  <#assign cardClass = 'bl-card' + isActive?then(' is-active', '')>
  ```

### Dead / duplicated code
- During a migration, **always re-read the result** to detect any buggy copy-paste (e.g. a duplicated `<#assign breadcrumbItems...>` in another container without use)
- Remove commented-out HTML blocks (`<!-- ... -->`) that are not genuinely useful as documentation
- Remove `<!-- TOC -->`, `<!-- BODY -->` etc. comments whose intent is obvious in the structured FreeMarker code

### What NOT to do
- Do not add JavaScript unless requested or required by a macro
- Do not use deprecated macro parameters
- Do not wrap a `<@cAlert>` in an unnecessary `<@cBlock>` or `<@cCard>`
- Do not duplicate the `btn btn-` prefix in the class of `<@cBtn>`
- Do not leave orphan `<li>` without a parent `<@chList>`
- Do not wrap each `<@chItem>` in a `<@cRow>`/`<@cCol>` — list items go directly inside `<@chList>`
- **Do not leave raw HTML tags** (`<br>`, `<hr>`, `<b>`, `<i>`, etc.) when a macro exists or when they are unnecessary — remove formatting `<br>`
- **Do not use `<@cCol cols='xs-12'>`** — simply use `<@cCol>` (full-width column by default)
- **Do not use `&nbsp;`** — replace with a normal space or remove if unnecessary
- **Do not use `style='...'`** on macros — use `class` with Bootstrap utilities or `params='style="..."'` as a last resort
- **Do not mix BO and FO macros** — check that all the macros used exist in the skin/FO context
- **Do not use `&gt;` / `&lt;`** in FreeMarker conditions — use `gt` / `lt`
- **Do not self-close `<@cInline>`** — always `</@cInline>`, even when the content is empty
- **Do not inline FreeMarker in the `class` parameter of a macro** — pre-build the string with `<#assign>` (also applies to `href`, `id`, etc.)
- **Do not inline `?string('yyyy-MM-dd')` directly in `params='datetime="..."'`** — nested quotes break the FreeMarker parser. Pre-build with `<#assign>`.
- **Do not keep a separate `<figcaption>`** — use the `caption` parameter of `<@cFigure>`
- **Do not use `<@cBtn>` for clickable cards** — use `<@cLink class='ma-card' label=''>` when it is a clickable area not styled as a button
- **Do not keep duplicated/dead code** during the migration — re-read the result to spot buggy copy-paste and unnecessary `<!-- ... -->` comments
- **NEVER keep jQuery** in a migrated template (`$(...)`, `jQuery(...)`, `.on()`, `.addClass()`, `.animate()`, `$(document).ready()`, etc.) — the jQuery lib is no longer loaded by the theme, the code would crash at runtime. Always rewrite in vanilla JS (see the dedicated section)

