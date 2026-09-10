---
name: lutece-update-template-fo
description: "Use when the user asks to migrate, convert or update a Lutece Front Office (skin) template to the FO FreeMarker macros from lutece-core. Takes the template path as argument."
---

# Updating Lutece FO templates

You must update a Lutece FO template by replacing all raw HTML with the FO FreeMarker macros defined in `lutece-core/webapp/WEB-INF/templates/skin/themes/`.

## Steps

1. **Read the template** target provided by the user
2. **Identify** all raw HTML elements replaceable by FO macros
3. **Consult the macros** if needed by reading the definition files in `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/{components,elements,forms,layout,utilities}/` (one `.ftl` per macro; `@cTpl` is in `skin/themes/global_theme_commons.ftl`)
4. **Rewrite** the template using FO macros exclusively
5. **Do not modify** i18n files unless necessary and requested

## HTML → FO Macros mapping table

### Structure and Layout

| HTML | Macro FO | Notes |
|---|---|---|
| `<div class="container">` | `<@cContainer>` | Can take `class`, `type` |
| `<div class="row">` | `<@cRow>` | Can take `class`, `id` |
| `<div class="col-...">` | `<@cCol>` | Use `cols='12 col-md-X'` |
| generic `<div>` | `<@cBlock>` | `type='div'` by default |
| `<section>` | `<@cSection>` | Dedicated macro. `<@cBlock type='section'>` also possible |
| `<article>` | `<@cArticle>` | Dedicated macro |
| `<header>` | `<@cHeader>` | Dedicated macro |
| `<aside>` | `<@cBlock type='aside'>` | No dedicated macro — use `cBlock` with `type` |
| `<footer>` | `<@cFooter>` | `elements/footer/cFooter.ftl`: `title titleLevel class id params` |
| `<main>` | `<@cBlock type='main'>` | No dedicated macro — use `cBlock` with `type` |

### Text and Titles

| HTML | Macro FO | Notes |
|---|---|---|
| `<h1>` to `<h6>` | `<@cTitle level=N>` | N = 1 to 6 |
| `<p>` | `<@cText>` | `type='p'` by default |
| `<span>` | `<@cInline>` | `type='span'` by default; `<@cInline ... />` is valid when there is no content |
| `<em>`, `<strong>`, `<small>` | `<@cInline type='em'>`, etc. | Via the `type` parameter |
| `<time datetime="...">` | `<@cInline type='time' params='datetime="..."'>` | No dedicated macro — pre-build the date with `<#assign>` |
| `<i class="ti ti-xxx">` | `<@cIcon name='xxx' />` | **Prefer `<@cIcon>`** — shortcut with automatic `ti ti-` prefix |

### Lists

| HTML | Macro FO | Notes |
|---|---|---|
| `<ul>` | `<@chList>` | `type='u'` by default, `type='o'` for ordered |
| `<ol>` | `<@chList type='o'>` | |
| `<li>` | `<@chItem>` | |

### Components
Also available (one `.ftl` each under `skin/themes/macros/components/`): `cEmpty` (empty state), `cOffcanvas`, `cPagination paginator`, `cTabs`/`cTab`/`cTabPane`, `cDropdown`, `cBadge`, `cInputDate` (`forms/inputs/`). Read the signature before use.

| HTML | Macro FO | Notes |
|---|---|---|
| `<div class="alert ...">` | `<@cAlert>` | Use `type='warning'`, `type='danger'`, etc. |
| `<div class="card ...">` | `<@cCard>` | Parameters: `title`, `header`, `headerLevel`, `headerLabelClass`, `class`, `titleLevel`, etc. |
| `<div class="modal ...">` | `<@cModal>` | |
| `<div class="accordion ...">` | `<@cAccordion>` | |
| `<div class="progress">` | `<@cProgress>` | Parameters: `label`, `progressId`, `color`, `value`, `min`, `max`, `text` |

### Links and Buttons

| HTML | Macro FO | Notes |
|---|---|---|
| `<a href="...">` | `<@cLink href='...' label='...'>` | Standard link |
| `<a class="btn ...">` | `<@cBtn href='...' class='...'>` | Link styled as a button |
| `<button>` | `<@cBtn>` | `type='submit'` by default |
| inline SVG/icon inside a button | Use `<@cIcon>` nested inside `<@cBtn>` | `nestedPos='before'` (default) or `'after'` |

### Images

| HTML | Macro FO | Notes |
|---|---|---|
| `<img>` | `<@cImg src='...' alt='...'>` | `class='img-fluid'` by default |
| `<figure>` + `<figcaption>` | `<@cFigure caption='...'>` + `<@cImg>` nested | The macro handles the `<figcaption>` via the `caption` parameter |

### Forms

| HTML | Macro FO | Notes |
|---|---|---|
| `<form>` | `<@cForm>` | `method='post'`, `action` |
| `<input>` | `<@cInput>` | |
| `<input type="hidden">` | `<@cInput type='hidden' class='' />` | **Always add `class=''`** |
| `<input type="password">` | `<@cInput type='password'>` or `<@cInputPassword>` | cInputPassword for the full version with toggle |
| `<label>` | `<@cLabel>` | |
| Label + Input grouped | `<@cField label='...' required=true>` | **Prefer cField**, use `required=true` instead of appending ` *` to the label |
| `<input type="radio">` | `<@cRadio>` | `name`, `label`, `value`, `checked` |
| `<input type="checkbox">` | `<@cCheckbox>` | Params: `name`, `label`, `value`, `checked`, `inline`, `required`, `disabled`, `params` |
| `<select>` | `<@cSelect>` | With `<@cOption>` nested. Supports `errorMsg` and `helpMsg`. Class: `form-select` (Bootstrap 5), do not use `form-control` |
| `<textarea>` | `<@cTextArea>` | |
| `<fieldset>` | `<@cFieldset>` | |
| `<div class="input-group">` | `<@cInputGroup>` | Can take `class`, `size` (`lg` or `sm`). The `<@cBtn>` go **directly** nested, **no** `<@cInputGroupAddonText>` |

### Tables

| HTML | Macro FO | Notes |
|---|---|---|
| `<table>` | `<@cTable>` | |
| `<thead>` | `<@cThead>` | |
| `<tbody>` | `<@cTbody>` | |
| `<tr>` | `<@cTr>` | |
| `<th>` | `<@cTh>` | |
| `<td>` | `<@cTd>` | |

### cTable → chList + cCard (optional, on request)

A table listing entities can be replaced by a list of cards **only if the user explicitly requests it**. Do not apply it systematically during a template update.

Pattern: `<@cTable>` → `<@chList>` + `<@chItem>` + `<@cCard title=entityTitle>`

```freemarker
<#if list_items?? && list_items?size gt 0>
    <@chList>
        <#list list_items as item>
            <@chItem>
                <@cCard title=item.title>
                    <@chList>
                        <@chItem><@cIcon name='calendar' /> ${item.date!}</@chItem>
                        <@chItem><@cIcon name='info' /> ${item.description!}</@chItem>
                    </@chList>
                    <#if item.actions?? && item.actions?size gt 0>
                        <@cRow class='mt-3'>
                            <@cCol>
                                <#list item.actions as action>
                                    <@cBtn href='...' class='outline-secondary btn-sm me-1'>
                                        ...
                                    </@cBtn>
                                </#list>
                            </@cCol>
                        </@cRow>
                    </#if>
                </@cCard>
            </@chItem>
        </#list>
    </@chList>
<#else>
    <@cAlert type='warning' title='#i18n{portal.util.labelNoItem}' />
</#if>
```

### Steps (multi-step forms)

| HTML | Macro FO | Notes |
|---|---|---|
| Completed step | `<@cStepDone>` | Params: `step` (required), `title` (required), `idx` (required), `actionName`, `actionHref`, `actionLabel` |
| Current step | `<@cStepCurrent>` | Params: `step` (required), `title` (required), `showPrevStep`, `actionNextStep`, `actionPrevStep`, `hasMandatory`, `hasSteps` |
| Upcoming step | `<@cStepNext>` | Params: `step` (required), `title` (required). Self-closing: `<@cStepNext step='3' title='...' />` |

## Mandatory conventions

### Global structure
- **Always** wrap the template in `<@cTpl>...</@cTpl>`
- `<@cContainer>` is optional, use it only if the content requires a centered container
- You can go directly from `<@cTpl>` to `<@cCol>`, `<@cRow>`, or `<@cCard>` as needed
- For full-page forms: `<@cTpl>` → `<@cCol>` → `<@cForm>` → `<@cRow>` → `<@cCol>` → content

### cCol - Column format
- Use the format `cols='12 col-md-X'` (not `cols='xs-12 col-md-X'` — the `xs-` prefix no longer exists in Bootstrap 5)
- **Replace `cols='xs-12 ...'` with `cols='12 ...'`** systematically
- **Replace `<@cCol cols='12'>` with `<@cCol>`** — full-width column by default, no need for `cols`
- For class only: `<@cCol class='12 col-md-6'>`
- Extra utility classes go in `class`: `<@cCol cols='12 col-md-6' class='pt-5 mt-5'>`

### cAlert - Alerts
- Use the `type` parameter: `<@cAlert type='warning'>`, `<@cAlert type='danger'>`
- Inline icon SVGs are unnecessary, the macro handles the display
- The `title` parameter lets you add a title to the alert

### cInput - Hidden fields
- **Always** add `class=''` on hidden inputs: `<@cInput type='hidden' name='x' value='y' class='' />`

### cIcon - Tabler icons
- **Prefer `<@cIcon>`** over `<@cInline type='i' class='ti ti-xxx' />`
- The `ti ti-` prefix is added automatically: `<@cIcon name='eye' />` → `<span class="ti ti-eye">`
- Extra classes via `class`: `<@cIcon name='settings' class='me-1' />`
- By default `name='check'`: `<@cIcon />` displays the check icon

### cLabel - Labels
- **Remove obsolete Bootstrap 3 classes**: `col-xs-12`, `col-sm-*`, `control-label`
- If the only class is `control-label` or `col-xs-12 control-label`, remove the `class` parameter entirely: `<@cLabel for='...'>`
- The macro handles the label styling itself

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

### cField - Fields with label
- **Prefer `<@cField>`** to group a label and an input rather than cBlock + cLabel + cInput manually
- Use `required=true` for mandatory fields — **do not append ` *` manually to the label**
- `for='<input id>'` links the label to the nested input (`cField.ftl` passes it to `cLabel`); give it whenever the input has an `id`
- Can contain a nested `<@cInputGroup>` for fields with addons (password toggle, generator, etc.)

### cInputGroup - Input groups
- Replaces `<div class="input-group">`
- Contains a `<@cInput>` and one or more `<@cBtn>` **directly** nested
- **Do not use `<@cInputGroupAddonText>`** to wrap the buttons

### cProgress - Progress bar
- `label` (required): text displayed above the bar
- `progressId`: ID of the bar (used by JS for DOM manipulation)
- `color`: Bootstrap color (`'primary'`, `'danger'`, `'warning'`, etc.)
- `value`: initial value (0 by default)

### cBtn - Buttons
- The class is prefixed automatically with `btn btn-`: `class='primary'` → `class="btn btn-primary"`
- **`label` is a mandatory parameter** — always specify it, even when the content is nested:
  - With nested content (icon + text): `label=''`
  - With text only: `label='My text'`
- For a link-button: add `href='...'`
- For sizes: include in class: `class='outline-primary btn-lg'`
- For icon + text nested: `label=''` with icon and text nested
- For a discreet link without border: `class='link border-0'` (not `outline-dark`)
- **Self-closing** when there is no nested content: `<@cBtn label='My text' ... />` (no `</@cBtn>`)

### cCard - Cards
- Use `header` for the header text, `headerLevel` for its heading level (0 = span, >0 = hN)
- `headerLabelClass` to style the header: e.g. `'text-danger fw-bold h2'`
- `title` for the main title (rendered in card-body), `titleLevel` and `titleClass` for styling
- Add `class='border border-danger'` for colored borders

### cInput - errorMsg and helpMsg
- **`errorMsg`**: error message displayed under the field — automatically adds the `is-invalid` class and `aria-invalid`. Pass an empty string if no error.
- **`helpMsg`**: help text displayed under the field. Use `?then()` to show the help only if there is no error:
  ```freemarker
  <@cInput ... errorMsg=formGroupError helpMsg=(formGroupError != '')?then('', formMessages.fieldHelp!) />
  ```
- **Replace** the patterns `<#if formGroupError != ''>${formGroupError}<#elseif ...><@cInline class='form-text'>...</@cInline></#if>` with these parameters
- **Adapt `formGroupError`**: store the raw error text (not the HTML span) so it can be passed to `errorMsg`:
  ```freemarker
  <#-- INCORRECT -->
  <#assign formGroupError = '<span class="form-text text-danger">${form_error.errorMessage}</span>' />

  <#-- CORRECT -->
  <#assign formGroupError = form_error.errorMessage />
  ```

### cInput - Native size and validation parameters
- **`maxlength`**: number (not string) — `maxlength=255` and not `maxlength='255'`
- **`min`** and **`max`**: native parameters for `type='number'` — do not put them in `params`
  ```freemarker
  <#-- INCORRECT -->
  <@cInput type='number' params='min="1" max="${nbplaces}"' />

  <#-- CORRECT -->
  <@cInput type='number' min=1 max=nbplaces />
  ```
- Other attributes not covered (e.g. `onkeypress`) stay in `params`

### cInput - Extra HTML attributes
- Use `params` for attributes not covered by the macro parameters: `params='onkeypress="return fn(event);"'`
- Dynamic validation classes: **always include `form-control`**: `class='form-control ${classPassword?if_exists}'`

### Macro parameters - Complex dynamic values
- **Never** inline FreeMarker logic (`<#if>`, `<#list>`, complex interpolations) directly in a macro parameter — **this applies to all parameters**, not only `params`
- **Use `<#assign>`** (block syntax or directive) to pre-build the value before the call:
  ```freemarker
  <#-- INCORRECT — inline FreeMarker in actionHref -->
  <@cStepDone actionHref='jsp/site/Portal.jsp?id=${form.id}<#if condition>&ref=${ref}</#if>' ...>

  <#-- CORRECT — block assign before the macro -->
  <#assign stepTwoHref>jsp/site/Portal.jsp?id=${form.id}<#if condition>&ref=${ref}</#if></#assign>
  <@cStepDone actionHref=stepTwoHref ...>
  ```
- For HTML attributes via `params`, same rule:
  ```freemarker
  <#assign btnTitle = '#i18n{label.lastLogin} : '>
  <#if user.getLastLogin()?has_content>
      <#assign btnTitle = btnTitle + user.getLastLogin()>
  <#else>
      <#assign btnTitle = btnTitle + '#i18n{label.never}'>
  </#if>
  <@cBtn params='title="${btnTitle}"' ... />
  ```
- This avoids quote-escaping problems (`&apos;`) and ParseExceptions

### cImg - Images
- `class='img-fluid'` is applied by default, no need to specify it
- Extra HTML attributes via `params`: `params='width="72"'`

### chList / chItem - Styled lists
- For Bootstrap lists: `<@chList class='list-group'>` + `<@chItem class='list-group-item'>`
- For navs: `<@chList class='nav ms-auto'>`

### cCheckbox - Checkboxes
- Main params: `name` (required), `label` (required), `value`, `id`, `checked` (boolean), `inline` (boolean), `required` (boolean), `disabled` (boolean), `params`
- `label` is **required**: if the field has no visible title, use `label='&nbsp;'`
- **No `title` parameter**: pass the title in `params`: `params='title="my tooltip"'`
- **Pre-build dynamic values** with `<#assign>` before calling the macro:
  ```freemarker
  <#assign isChecked = false>
  <#if someCondition><#assign isChecked = true></#if>
  <#assign cbParams = ''>
  <#if field.comment?? && field.comment != ''>
      <#assign cbParams = 'title="${field.comment}"'>
  </#if>
  <#assign cbLabel><#if !field.noDisplayTitle>${field.title}<#else>&nbsp;</#if></#assign>
  <@cCheckbox name='myField' id='myField_${field.id}' value='${field.id}' checked=isChecked label=cbLabel params=cbParams inline=isInline />
  ```
- For checkboxes grouped in a vertical list, do not wrap them in a `<@cBlock class='checkbox'>` — the macro handles its own container

### cStepDone / cStepCurrent / cStepNext - Multi-step forms
- Replace the `<div class="row nextStepTitleRow">`, `<div class="row currentStepTitleRow">` and `<div class="row currentStepContentRow">`
- **`<@cStepDone>`**: completed step, displays a check and a summary. The nested content is the step summary.
  ```freemarker
  <@cStepDone step='1' title='Step 1 title' idx=0>
      Summary of the completed step
  </@cStepDone>
  ```
- **`<@cStepCurrent>`**: current step, contains the active form/content nested.
  ```freemarker
  <@cStepCurrent step='2' title='Step 2 title' showPrevStep=false hasMandatory=false>
      ...step content (alerts, form, picker, etc.)...
  </@cStepCurrent>
  ```
- **`<@cStepNext>`**: upcoming step, self-closing, no nested content.
  ```freemarker
  <@cStepNext step='3' title='#i18n{...}' />
  ```
- **Never** inline a FreeMarker condition in the `title` parameter of the `cStep*` macros — use an `<#assign>` variable defined **inside `<@cTpl>`** (just after line 1) and pass it without quotes:
  ```freemarker
  <@cTpl>
  <#assign stepFormTitle><#if form.title != "">${form.title}<#else>#i18n{...default}</#if></#assign>
  <@cStepDone step='1' title=stepFormTitle idx=0>
      ...
  </@cStepDone>
  ```
- **The `<#assign>` always go inside `<@cTpl>`**, never before — `<@cTpl>` must be on line 1 of the file, the assigns on the following lines

### cForm - Forms
- Attributes not covered by the parameters via `params`: `params='name="createAccount"'`

### i18n
- All displayed text must use `#i18n{plugin.key}`
- Do not write hardcoded text in the template

### Code readability
- **Expand the `<#list>` with conditional logic** across multiple lines, do not leave compact inline blocks when they contain nested `<#if>`

### chList / chItem - Replacing orphan `<li>`
- **Never** leave a `<li>` without a parent `<ul>` — always wrap in `<@chList>` + `<@chItem>`
- When `<li>` are scattered across `<@cRow>`/`<@cCol>`, remove the unnecessary row/col wrappers and group them into a single `<@chList>`:
  ```freemarker
  <#-- BEFORE (incorrect) -->
  <@cRow><@cCol><li>Name: ${name}</li></@cCol></@cRow>
  <@cRow><@cCol><li>Email: ${email}</li></@cCol></@cRow>

  <#-- AFTER (correct) -->
  <@chList>
      <@chItem>Name: ${name}</@chItem>
      <@chItem>Email: ${email}</@chItem>
  </@chList>
  ```

### cInput hidden - Mandatory empty class
- **Always** add `class=''` on hidden inputs to prevent the macro from adding the default `form-control` class:
  ```freemarker
  <@cInput type='hidden' name='token' value='${token}' class='' />
  ```

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

### cFieldset - Replacing fieldset/legend
- `<fieldset>` + `<legend>` → `<@cFieldset legend='...'>` — the macro handles the legend rendering
  ```freemarker
  <#-- BEFORE -->
  <fieldset>
      <legend>My title</legend>
      ...content...
  </fieldset>

  <#-- AFTER -->
  <@cFieldset legend='My title'>
      ...content...
  </@cFieldset>
  ```

### form-group → cRow/cCol
- **Replace `<@cBlock class='form-group'>`** with `<@cRow>` / `<@cCol>` for form button groups
- Add `class='mt-3'` on the `<@cRow>` for vertical spacing
  ```freemarker
  <#-- BEFORE -->
  <@cBlock class='form-group'>
      <@cBtn .../>
  </@cBlock>

  <#-- AFTER -->
  <@cRow class='mt-3'>
      <@cCol>
          <@cBtn .../>
      </@cCol>
  </@cRow>
  ```

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

### cols - Invalid formats
- `cols='xs-12 sm-12'` → `<@cCol>` (full width by default, no need for cols)
- `cols='xs-12 col-sm-6'` → `cols='12 col-sm-6'`
- `cols='12'` alone → remove the parameter, use `<@cCol>`
- The `xs-` prefix does not exist in Bootstrap 5, always use the prefix-less form for mobile

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

### cSelect - Class and errorMsg/helpMsg parameters
- **Never add `class='form-control'`** on `<@cSelect>` — Bootstrap 5 uses `form-select`, but the macro handles the base class automatically
- For extra classes (validation), use `class='form-select ${entry.CSSClass!}' + (errorMsg != '')?then(' is-invalid', '')`
- **`<@cSelect>` supports `errorMsg` and `helpMsg`** exactly like `<@cInput>` — pass the messages directly, **no need for a separate `<@cAlert>`**
  ```freemarker
  <#-- INCORRECT — class='form-control' + separate @cAlert -->
  <@cSelect name='myField' class='form-control'>...</@cSelect>
  <#if errorMsg != ''>
      <@cAlert type='danger' title=errorMsg />
  </#if>

  <#-- CORRECT — form-select + errorMsg/helpMsg directly on the macro -->
  <#assign selectClass = 'form-select ${entry.CSSClass!}' + (errorMsg != '')?then(' is-invalid', '')>
  <@cSelect name='myField' class=selectClass errorMsg=errorMsg helpMsg=helpMsg>...</@cSelect>
  ```

### cOption - selected parameter
- **Pass a direct boolean** to the `selected` parameter — do not inline `<#if isSelected>selected='selected'</#if>` in the macro parameters
- Pre-compute the value in an `<#assign>` if necessary:
  ```freemarker
  <#-- INCORRECT — inline FreeMarker in parameter -->
  <@cOption value='${field.id}' <#if isSelected>selected='selected'</#if>>${field.title}</@cOption>

  <#-- CORRECT — direct boolean -->
  <#assign isSelected = false>
  <#if response.field.idField == field.idField>
      <#assign isSelected = true>
  </#if>
  <@cOption value='${field.id}' selected=isSelected>${field.title}</@cOption>
  ```

### cAlert - Message list
- For alerts displaying a **list of messages** (several `infos` or `errors`), use a block `<#assign>` to concatenate the messages, then pass the result to the `title` parameter:
  ```freemarker
  <#-- INCORRECT — nested content with <#list> -->
  <@cAlert type='danger' id='messages_errors_div'>
      <#list errors as error>
          <@cIcon name='alert-circle' /> ${error.message}
      </#list>
  </@cAlert>

  <#-- CORRECT — assign + title -->
  <#assign errorMsg><#list errors as error>${error.message}</#list></#assign>
  <@cAlert type='danger' id='messages_errors_div' title=errorMsg />
  ```
- The `<@cAlert>` macro handles its own icon according to the `type` — no need to add `<@cIcon>` manually

### cInline - Span / em / time / strong and other inlines
- `type` selects the tag (`span` default, `em`, `strong`, `small`, `time`, `i`…); extra attributes go in `params`
- FreeMarker accepts `<@cInline ... />` for an empty element, no closing tag required:
  ```freemarker
  <@cInline class='bl-marker' params='data-id="1"' />
  <@cInline type='time' params='datetime="${updateDateIso}"'>${blog.updateDate?string('d MMMM yyyy')}</@cInline>
  ```

### cFigure - Figures with caption
- Replaces `<figure>` + `<figcaption>` in a single call via the `caption` parameter
  ```freemarker
  <#-- BEFORE -->
  <figure class="hero-img">
      <img src="..." alt="..." />
      <figcaption class="hero-img__label">My caption</figcaption>
  </figure>

  <#-- AFTER -->
  <@cFigure class='hero-img' caption='My caption'>
      <@cImg src='...' alt='...' />
  </@cFigure>
  ```
- When the caption comes from a variable (title, dynamic label), pass the variable directly: `caption=blog.contentLabel`

### Semantic HTML5 elements (article / header / section / aside)
- **`<article>`** → `<@cArticle>` (dedicated macro)
- **`<header>`** → `<@cHeader>` (dedicated macro)
- **`<section>`** → `<@cSection>` (dedicated macro) — `<@cBlock type='section'>` also remains valid
- **`<aside>`, `<footer>`, `<main>`, `<nav>`** → `<@cBlock type='aside'>` (no dedicated macro, but `cBlock` accepts any `type`)
- All these macros accept `class`, `id`, `params` like `cBlock`

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

### Clickable links styled as a card (not as a button)
- For a **clickable card** (the whole area is a link, not a button-styled element), use `<@cLink>` and **not** `<@cBtn>`:
  ```freemarker
  <#assign cardUrl>jsp/site/Portal.jsp?page=blog&id=${item.id}<#if portletId??>&portlet_id=${portletId}</#if></#assign>
  <@cLink href=cardUrl class='bl-rcard' label=''>
      <@cBlock class='bl-rcard__img'>...</@cBlock>
      <@cBlock class='bl-rcard__body'>...</@cBlock>
  </@cLink>
  ```
- The `label=''` parameter is mandatory; the card content goes nested.

### Empty lists filled by JS
- For a `<ul>` that will be populated on the JS side (TOC, autocomplete, etc.), use `<@chList>` with an `id` and empty nested content:
  ```freemarker
  <@chList id='bl-toc'></@chList>
  ```
- The JS can then do `document.getElementById('bl-toc')` and `appendChild(li)` normally.

### Dead / duplicated code
- During a migration, **always re-read the result** to detect any buggy copy-paste (e.g. a duplicated `<#assign breadcrumbItems...>` in another container without use)
- Remove commented-out HTML blocks (`<!-- ... -->`) that are not genuinely useful as documentation
- Remove `<!-- TOC -->`, `<!-- BODY -->` etc. comments whose intent is obvious in the structured FreeMarker code

### jQuery → Vanilla JS - Mandatory conversion
**The jQuery library is no longer loaded by the theme** (`page_frameset.html`, optional `library-theme-jquery` only). Any JavaScript using `$(...)`, `jQuery(...)` or jQuery plugins must be **systematically** rewritten in vanilla JS when migrating a template — it is non-negotiable, otherwise the code breaks at runtime. Code depending on a jQuery plugin (DataTables, Select2, jQuery UI…) needs a manual port to a vanilla equivalent or a core macro; flag it to the user.

Standard mapping of the most common jQuery operations:

| jQuery | Vanilla JS |
|---|---|
| `$('#foo')`, `$('.bar')` | `document.querySelector('#foo')`, `document.querySelector('.bar')` (1st match) |
| `$('.bar')` (collection) | `document.querySelectorAll('.bar')` |
| `$el.find('.x')` | `el.querySelector('.x')` or `el.querySelectorAll('.x')` |
| `$el.children('.x')` | `el.querySelectorAll(':scope > .x')` |
| `$el.parent()` | `el.parentElement` |
| `$el.closest('.x')` | `el.closest('.x')` (already native) |
| `$el.each(fn)` | `nodeList.forEach(fn)` (on `NodeList` or `Array.from(htmlCollection)`) |
| `$el.addClass('x')`, `.removeClass('x')`, `.toggleClass('x')` | `el.classList.add('x')`, `.remove('x')`, `.toggle('x')` |
| `$el.hasClass('x')` | `el.classList.contains('x')` |
| `$el.attr('foo', 'bar')` | `el.setAttribute('foo', 'bar')` |
| `$el.attr('foo')` (read) | `el.getAttribute('foo')` |
| `$el.removeAttr('foo')` | `el.removeAttribute('foo')` |
| `$el.data('foo')` | `el.dataset.foo` |
| `$el.text()`, `$el.text('...')` | `el.textContent` (read/write) |
| `$el.html()`, `$el.html('...')` | `el.innerHTML` (read/write) |
| `$el.val()`, `$el.val('...')` | `el.value` (read/write) |
| `$el.width()`, `$el.height()` | `el.offsetWidth`, `el.offsetHeight` |
| `$el.css('color')` (read) | `getComputedStyle(el).color` |
| `$el.css('color', 'red')` (write) | `el.style.color = 'red'` |
| `$el.show()`, `$el.hide()` | `el.style.display = ''` / `'none'` (or utility class `d-none`) |
| `$el.append(child)` | `el.appendChild(child)` or `el.append(child)` |
| `$el.prepend(child)` | `el.prepend(child)` |
| `$el.remove()` | `el.remove()` (already native) |
| `$el.empty()` | `el.replaceChildren()` or `el.innerHTML = ''` |
| `$el.on('click', fn)` | `el.addEventListener('click', fn)` |
| `$el.off('click', fn)` | `el.removeEventListener('click', fn)` |
| `$el.click(fn)`, `.keydown(fn)`, `.submit(fn)` | `el.addEventListener('click', fn)`, `'keydown'`, `'submit'` |
| `event.which` (key) | `event.key` (`' '`, `'Enter'`, `'Escape'`...) or `event.code` |
| `$(this)` in handler | `this` (the handler receives `this` = the triggering element) or `event.currentTarget` |
| `$el.animate({ scrollLeft: '+=305' }, 'slow')` | `el.scrollBy({ left: 305, behavior: 'smooth' })` |
| `$el.animate({ scrollTop: 0 }, 'slow')` | `window.scrollTo({ top: 0, behavior: 'smooth' })` |
| `$.ajax(...)` / `$.get(...)` / `$.post(...)` | `fetch(url, { method, headers, body }).then(r => r.json())` |
| `$(document).ready(fn)` | `document.addEventListener('DOMContentLoaded', fn)` (already the standard practice) |
| `$.trim(s)` | `s.trim()` |
| `$.each(arr, fn)` | `arr.forEach(fn)` |

**Recurring patterns to factor out into helpers** when used several times in the same `<script>`:
```javascript
// Helper to toggle disabled (class + attribute)
function setDisabled(btn, value) {
    if (!btn) return;
    if (value) {
        btn.classList.add('disabled');
        btn.setAttribute('disabled', 'disabled');
    } else {
        btn.classList.remove('disabled');
        btn.removeAttribute('disabled');
    }
}
```

**Mandatory safeguards**:
- **Always** check the existence of the element after `querySelector`: `if (!el) return;` or `if (el) { ... }` — `querySelector` returns `null` if not found, `el.classList.add(...)` then crashes whereas `$el.addClass(...)` was silent on an empty collection.
- **Prefer `event.key`** over `event.which` (deprecated) or `event.keyCode` (deprecated).
- **Catch dead jQuery code**: some jQuery selectors are poorly written (e.g. `$el.children('.a .b')` which never matches — `.children()` filters direct children with a simple selector). When converting, **flag the presumed intent** to the user rather than literally translating a no-op.

### cText - Correct usage
- `<@cText>` renders a `<p>` tag — **do not use it as a layout container** (flex, grid, columns)
- For layout wrappers with Bootstrap utility classes, use `<@cBlock>`, `<@cRow>` or `<@cCol>`:
  ```freemarker
  <#-- INCORRECT -->
  <@cText class='d-flex justify-content-end mt-5'>
      <@cBtn .../>
  </@cText>

  <#-- CORRECT -->
  <@cRow class='mt-5'>
      <@cCol class='d-flex justify-content-end'>
          <@cBtn .../>
      </@cCol>
  </@cRow>
  ```

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

## Macro files reference

The definitions are located in:
- **Components**: `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/components/`
- **Elements**: `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/elements/`
- **Forms**: `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/forms/`
- **Layout**: `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/layout/`
- **Utilities**: `lutece-core/webapp/WEB-INF/templates/skin/themes/macros/utilities/`

If in doubt about a macro's parameters, **read the corresponding .ftl file** to check the signature and documentation.

## Reference examples

### Typical error page

```freemarker
<#include "minimal_header.html" />
<@cTpl>
<@cContainer class='vh-80 pt-5'>
    <@cRow class='pt-5 mt-5'>
        <@cCol cols='12 col-md-3' class='pt-5 mt-5'>
            <@cImg src='themes/skin/shared/images/500.png' alt='#i18n{portal.util.error500.title}' id='error500-img' />
        </@cCol>
        <@cCol cols='12 col-md-6' class='pt-5 mt-5'>
            <@cCard class='border border-danger mt-5' header='Error 500' headerLevel=1 headerLabelClass='text-danger fw-bold h2' title='#i18n{portal.util.error500.title}' titleClass='h2' titleLevel=2>
                <@cText class='my-5 fs-2'>#i18n{portal.util.error500.text}</@cText>
                <#if error_cause??>
                <@cAlert type='danger' class='fs-3'>${error_cause}</@cAlert>
                </#if>
                <@cText class='text-center mt-5'>
                    <@cBtn href='./' label='#i18n{portal.util.labelBackHome}'>
                        <@cIcon name='home' />
                    </@cBtn>
                </@cText>
            </@cCard>
        </@cCol>
    </@cRow>
</@cContainer>
</@cTpl>
<#include "minimal_footer.html" />
```

### Typical choice list

```freemarker
<@cTpl>
<@cRow>
    <@cCol>
        <@cTitle level=2>#i18n{mylutece.xpage.create_account.pageTitle}</@cTitle>
        <#if list_authentications?has_content>
            <@cText>#i18n{mylutece.xpage.create_account.contentMessage}</@cText>
            <@chList class='list-group'>
            <#list list_authentications as authentication>
                <@chItem class='list-group-item'>
                    <@cLink href='${authentication.newAccountPageUrl}' label='${authentication.authServiceName!}' title='${authentication.authServiceName!}' nestedPos='before'>
                        <@cImg src='${authentication.iconUrl!}' alt='${authentication.authServiceName!}' />
                    </@cLink>
                </@chItem>
            </#list>
            </@chList>
        </#if>
        <@cAlert type='warning' title='#i18n{mylutece.xpage.create_account.noAuthentication}' />
    </@cCol>
</@cRow>
</@cTpl>
```

### Typical registration form (with input-group and progress)

```freemarker
<@cTpl>
<@cRow>
    <@cCol cols='12 col-md-4 offset-md-4'>
        <#if error_code?has_content>
            <@cAlert type='danger'>#i18n{...errorMessage}</@cAlert>
        </#if>
        <@cTitle level=2>#i18n{...pageTitle}</@cTitle>
        <@cForm id='createAccount' action='...' method='post' params='name="createAccount"'>
            <@cInput type='hidden' name='plugin_name' value='${plugin_name}' class='' />
            <@cField label='#i18n{...email}' required=true>
                <@cInput type='text' name='email' id='email' class='form-control ${classEmail?if_exists}' params='maxlength="100"' value='${(user.email)?if_exists}' />
            </@cField>
            <@cField label='#i18n{...password}' required=true>
                <@cInputGroup>
                    <@cInput type='password' id='password' name='password' class='form-control ${classPassword?if_exists}' params='maxlength="100"' />
                    <@cBtn href='#' class='secondary btn-sm p-2' id='lutece-password-toggler' label='' params='title="Show / hide the password"'>
                        <@cIcon name='eye' />
                    </@cBtn>
                    <@cBtn href='#' class='secondary btn-sm p-2' id='generate_password' label='' params='title="Generate a password"'>
                        <@cIcon name='settings' class='me-1' />
                        <@cInline class='d-none'>Generate a password</@cInline>
                    </@cBtn>
                </@cInputGroup>
            </@cField>
            <@cBlock class='py-3'>
                <@cProgress label='#i18n{...passwordComplexity}' progressId='progress_bar_first_password' color='danger' value=0 />
            </@cBlock>
            <@cRow>
                <@cCol>
                    <@cBtn class='primary' type='submit' label='' params='name="createAccountBtn"'>
                        <@cIcon name='user-check' /> #i18n{...btnCreateAccount}
                    </@cBtn>
                    <@cBtn class='secondary' type='button' label='' params='name="back" onclick="javascript:history.go(-1)"'>
                        <@cIcon name='circle-x' /> #i18n{...btnBack}
                    </@cBtn>
                </@cCol>
            </@cRow>
        </@cForm>
    </@cCol>
</@cRow>
</@cTpl>
```

### Typical login form

```freemarker
<@cTpl>
<@cCol>
    <@cForm method='post' action='${url_dologin}'>
    <@cInput type='hidden' name='page' value='mylutece' class='' />
    <@cInput type='hidden' name='action' value='doLogin' class='' />
    <@cInput type='hidden' name='token' value='${token}' class='' />
    <@cRow class='mt-xxl'>
        <@cCol cols='12 col-md-6' class='mt-xxl'>
            <#if error_message?? && error_message != ''>
                <@cAlert type='warning' title='${error_message!}' />
            </#if>
            <@cCard title='#i18n{mylutece.xpage.login_form.pageTitle}' class='my-l'>
                <@cField label='#i18n{mylutece.xpage.login_form.labelAccessCode}' for='username'>
                    <@cInput type='text' name='username' id='username' placeholder='name@example.com' />
                </@cField>
                <@cField label='#i18n{mylutece.xpage.login_form.labelPassword}' for='password'>
                    <@cInput type='password' name='password' id='password' placeholder='#i18n{mylutece.xpage.login_form.labelPassword}' />
                </@cField>
                <@cBtn class='primary w-100 py-m mt-l' type='submit' label='#i18n{mylutece.xpage.login_form.labelButton}' />
                <@cRow class='justify-content-center mt-l'>
                    <@cCol class='d-flex justify-content-end'>
                        <@cBtn href='${lostPasswordUrl!}' label='' params='title="..."'>
                            <@cIcon name='password-user' /> #i18n{...labelButtonLostPassword}
                        </@cBtn>
                    </@cCol>
                </@cRow>
            </@cCard>
        </@cCol>
        <@cCol cols='12 col-md-3' class='mt-xxl'>
            <@cImg src='themes/skin/lutece/images/signin.png' alt='#i18n{mylutece.xpage.login_form.labelButton}' />
        </@cCol>
    </@cRow>
    </@cForm>
</@cCol>
</@cTpl>
```

### Typical multi-step recap page (with cStepDone, cStepCurrent, cStepNext)

```freemarker
<@cStepDone step='1' title='#i18n{...stepOneTitle}' idx=0>
    ${form.description!}
</@cStepDone>
<@cStepDone step='2' title='#i18n{...stepTwoTitle}' idx=1 actionHref='jsp/site/Portal.jsp?page=appointment&view=getViewAppointmentCalendar&id_form=${form.idForm}' actionLabel='#i18n{portal.util.labelModify}'>
    <@chList>
        <@chItem>#i18n{...labelDate} ${appointment.dateOfTheAppointment}</@chItem>
    </@chList>
</@cStepDone>
<@cStepDone step='3' title='#i18n{...stepThreeTitle}' idx=2 actionHref='javascript:history.back()' actionLabel='#i18n{portal.util.labelModify}'>
    <@chList>
        <@chItem>${formMessages.fieldLastNameTitle!} : ${appointment.lastName}</@chItem>
        <@chItem>${formMessages.fieldFirstNameTitle!} : ${appointment.firstName}</@chItem>
        <@chItem>${formMessages.fieldEmailTitle!} : ${appointment.email}</@chItem>
        <#list listResponseRecapDTO as response>
            <#if response.recapValue?? && response.recapValue?has_content>
            <@chItem>${response.entry.title} : ${response.recapValue}</@chItem>
            </#if>
        </#list>
    </@chList>
</@cStepDone>
<@cStepCurrent step='4' title='#i18n{...validationTitle}' hasMandatory=false>
    <@cForm action='jsp/site/Portal.jsp' method='post'>
        <@cInput type='hidden' name='page' value='appointment' class='' />
        <@cInput type='hidden' name='action' value='doMakeAppointment' class='' />
        <@cInput type='hidden' name='token' value='${token}' class='' />
        <@cText>#i18n{...validationText}</@cText>
        <@cBtn type='submit' class='primary'>
            <@cIcon name='check' /> #i18n{...labelValidate}
        </@cBtn>
    </@cForm>
</@cStepCurrent>
<@cStepNext step='5' title='#i18n{...confirmationTitle}' />
```

### Article / rich content page (semantic HTML5 + dynamic breadcrumb)

Recommended pattern for an article detail page (blog, news, etc.) with:
- Breadcrumb built dynamically from URL parameters
- Header with metadata (tags, date, reading time)
- Hero image via `<@cFigure caption=...>`
- Aside with table of contents (TOC)
- Related articles section at the bottom

```freemarker
<@cTpl>
<#assign readingTimeLabel = "#i18n{plugin.readingTime.label}">
<@cContainer>
    <@cRow>
        <@cCol>
            <@cArticle class='bg-light'>
                <#-- Dynamic breadcrumb built from the received params -->
                <#assign breadcrumbItems = []>
                <#if from_page_name?? && from_page_name != ''>
                    <#assign fromPageUrl = ''>
                    <#if from_page_id??><#assign fromPageUrl = 'jsp/site/Portal.jsp?page_id=' + from_page_id?c></#if>
                    <#assign breadcrumbItems = breadcrumbItems + [{ 'title': from_page_name, 'url': fromPageUrl }]>
                </#if>
                <@cBreadCrumb home='Home' type='fluid' items=breadcrumbItems />

                <@cHeader class='hero'>
                    <@cBlock>
                        <@cBlock class='hero__meta'>
                            <#if blog.tag?has_content>
                                <#list blog.tag as tg>
                                    <@cInline class='tag'>${tg.name}</@cInline>
                                </#list>
                            </#if>
                            <@cInline>·</@cInline>
                            <#if blog.updateDate??>
                                <#assign dateIso = blog.updateDate?string('yyyy-MM-dd')>
                                <@cInline type='time' params='datetime="${dateIso}"'>${blog.updateDate?string('d MMMM yyyy')}</@cInline>
                            </#if>
                            <@cInline>·</@cInline>
                            <@cInline class='reading-time' params='data-reading-time-label="${readingTimeLabel}"'></@cInline>
                        </@cBlock>
                        <@cTitle level=1 class='hero__title'>${blog.contentLabel}</@cTitle>
                        <@cText class='hero__lede'>${blog.description!}</@cText>
                    </@cBlock>
                    <#if blog.docContent?? && blog.docContent?size != 0>
                        <#list blog.docContent?sort_by('priority') as doc>
                            <#if doc.contentType.idContentType == 1>
                                <@cFigure class='hero__img' caption=blog.contentLabel>
                                    <@cImg src='servlet/plugins/blogs/file?id_file=${doc.id!}' alt=blog.contentLabel />
                                </@cFigure>
                                <#break>
                            </#if>
                        </#list>
                    </#if>
                </@cHeader>

                <#assign bodyClass = 'body'>
                <#if !blog.displayToc><#assign bodyClass = bodyClass + ' body--one-col'></#if>
                <@cBlock class=bodyClass>
                    <#if blog.displayToc>
                        <@cBlock type='aside' class='toc'>
                            <@cBlock class='toc__title'>#i18n{plugin.tocTitle}</@cBlock>
                            <@chList id='toc-list'></@chList>
                        </@cBlock>
                    </#if>
                    <@cBlock class='article-content'>
                        ${blog.htmlContent}
                    </@cBlock>
                </@cBlock>
            </@cArticle>

            <#if blog.displayRelated && related_blogs?? && related_blogs?size gt 0>
                <@cSection class='related'>
                    <@cBlock class='related__title'>#i18n{plugin.relatedTitle}</@cBlock>
                    <@cBlock class='cards'>
                        <#list related_blogs as relBlog>
                            <#assign relUrl>jsp/site/Portal.jsp?page=blog&id=${relBlog.id}<#if blog.attachedPortletId gt 0>&portlet_id=${blog.attachedPortletId}</#if></#assign>
                            <@cLink href=relUrl class='card' label=''>
                                <@cBlock class='card__body'>
                                    <@cTitle level=3>${relBlog.contentLabel}</@cTitle>
                                    <@cText>${relBlog.description!}</@cText>
                                </@cBlock>
                            </@cLink>
                        </#list>
                    </@cBlock>
                </@cSection>
            </#if>
        </@cCol>
    </@cRow>
</@cContainer>
</@cTpl>
```

**Key points of this pattern**:
- `<@cArticle>`, `<@cHeader>`, `<@cSection>`, `<@cBlock type='aside'>` for HTML5 semantics
- `<#assign>` blocks to pre-build URLs, ISO dates and dynamic class names (never inline FreeMarker in macro parameters)
- `<@cInline type='time'>` for the `<time>` tag (no dedicated macro)
- `<@cFigure caption=...>` rather than separate `<figure>` + `<figcaption>`
- `<@cLink class='card' label=''>` for clickable cards (not `<@cBtn>`)
- `<@chList id='...'></@chList>` for an empty list to fill on the JS side
