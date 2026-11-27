# FO templates — per-macro and situational patterns

Rules that apply to one macro or one situation. The cross-cutting rules are in SKILL.md.

## Contents
- cCol - Column format
- cAlert - Alerts
- cInput - Hidden fields
- cIcon - Tabler icons
- cLabel - Labels
- cField - Fields with label
- cInputGroup - Input groups
- cInputPassword - Password fields
- cBreadCrumb - Page path
- cRadio / cImg - Generated ids
- Model access
- cProgress - Progress bar
- cBtn - Buttons
- cCard - Cards
- cTile / cEmpty / cErrorMessage / cAccordion / noScriptMessage - Component macros the theme registers
- cForm - Validation and encoding
- cInput - errorMsg and helpMsg
- cInput - Native size and validation parameters
- cInput - Extra HTML attributes
- Macro parameters - Complex dynamic values
- cImg - Images
- chList / chItem - Styled lists
- cCheckbox - Checkboxes
- cStepDone / cStepCurrent / cStepNext - Multi-step forms
- chList / chItem - Replacing orphan `<li>`
- cInput hidden - Empty class
- cFieldset - Replacing fieldset/legend
- form-group → cRow/cCol
- cols - Invalid formats
- cSelect - Class and errorMsg/helpMsg parameters
- cOption - selected parameter
- cAlert - Message list
- cInline - Span / em / time / strong and other inlines
- cFigure - Figures with caption
- Semantic HTML5 elements (article / header / section / aside)
- Clickable links styled as a card (not as a button)
- Empty lists filled by JS
- jQuery → Vanilla JS - Mandatory conversion
- cText - Correct usage

### cCol - Column format
- Use the format `cols='12 col-md-X'` (not `cols='xs-12 col-md-X'` — the `xs-` prefix does not exist in Bootstrap 5)
- **Replace `cols='xs-12 ...'` with `cols='12 ...'`** systematically
- **Replace `<@cCol cols='12'>` with `<@cCol>`** — full-width column by default, no need for `cols`
- The size always goes in `cols`, never in `class`: `<@cCol class='12 col-md-6'>` renders `class="col 12 col-md-6"` (`cCol.ftl:33`, signature `cols='' default='col' class=''`)
- Extra utility classes go in `class`: `<@cCol cols='12 col-md-6' class='pt-5 mt-5'>`

### cAlert - Alerts
- Signature (`components/alert/cAlert.ftl`): `id title isHtmlTitle=false htmlTitleLevel=3 type='primary' iconType='informative' class classText dismissible=false params`
- `title` is the main message; nested content is secondary (`alert-content`). Self-closing when there is no body: `<@cAlert type='warning' title=msg />`
- `type` sets the class `alert-${type}`, and `cAlert.ftl` gives `danger`, `warning` and `success` their own icon and ARIA role; any other value (`primary`, `info`) keeps the `info-circle` icon and `role="status"`. The theme's `components/alert.css` styles `alert-primary` and `alert-info`. A first class token among `warning`, `primary`, `danger`, `success` in `class` (`class='danger'`) overrides `type`; both work, prefer `type`
- `isHtmlTitle=true` when the message carries markup; `dismissible=true` for a closable alert
- Inline icon SVGs are unnecessary, the macro handles the icon (`iconType`)
- The DOM is `alert > alert-header (alert-icon, alert-text) + alert-content`: CSS written for a flat `.alert > .alert-title` does not apply

### cInput - Hidden fields
- `class=''` on hidden inputs drops the default `form-control`; no visual effect, optional

### cIcon - Tabler icons
- **Prefer `<@cIcon>`** over `<@cInline type='i' class='ti ti-xxx' />`; `@parisIcon` does not exist in the core
- The `ti ti-` prefix is added automatically: `<@cIcon name='eye' />` → `<span class="ti ti-eye">`
- `name` must be a Tabler name (`webapp/themes/shared/css/tabler-icons.min.css`): `cIcon` has no alias table, unlike the BO `@icon`. Not Tabler: `envelope`, `times`, `agenda`, `cog`, `eye-slash`, `comment`, `close`, `save`
- `name` is the glyph, never a label: `<@cIcon name='#i18n{...}' />` is wrong
- Vocabulary in use: submit `check`, send `mail`, search `search`, reset `refresh`, edit `edit`, view `eye`, delete `trash`, top `chevron-up`, back `arrow-left`, forward/login `arrow-right`
- Extra classes via `class`: `<@cIcon name='settings' class='me-1' />`
- By default `name='check'`: `<@cIcon />` displays the check icon

### cLabel - Labels
- **Remove obsolete Bootstrap 3 classes**: `col-xs-12`, `col-sm-*`, `control-label`
- If the only class is `control-label` or `col-xs-12 control-label`, remove the `class` parameter entirely: `<@cLabel for='...'>`
- The macro handles the label styling itself

### cField - Fields with label
- **Prefer `<@cField>`** to group a label and an input rather than cBlock + cLabel + cInput manually
- Use `required=true` for mandatory fields — **do not append ` *` manually to the label**
- `for='<input id>'` links the label to the nested input (`cField.ftl` passes it to `cLabel`); give it whenever the input has an `id`
- The header of `cField.ftl` says `class` defaults to `mb-3`; the signature says `class=''`. Pass `class='mb-3'` yourself or the fields touch
- Can contain a nested `<@cInputGroup>` for fields with addons (password toggle, generator, etc.)

### cInputGroup - Input groups
- Replaces `<div class="input-group">`
- Contains a `<@cInput>` and, directly nested, `<@cBtn>` buttons or a prefix icon. `<@cInputGroupAddon addonText='...'>` wraps a text addon; with nested content only it prints `<#nested>` bare (`cInputGroupAddon.ftl`), so a bare `<@cIcon name='user' />` gives the same HTML, which is what `cInputPassword.ftl` itself does:
  ```freemarker
  <@cInputGroup>
      <@cIcon name='user' />
      <@cInput name='username' id='username' />
  </@cInputGroup>
  ```
- **Do not use `<@cInputGroupAddonText>`** to wrap the buttons

### cInputPassword - Password fields
- Replaces the hand-rolled pattern (cInputGroup + eye `cBtn` + `cProgress` + `LutecePassword` module): `forms/inputs/cInputPassword.ftl`
  ```freemarker
  <@cInputPassword label='#i18n{...password}' name='password' id='password' icon='lock' passwordMeter=true pmConfirmFieldId='confirmation_password' helpMsg='#i18n{portal.theme.labelPasswordHelp}' />
  ```
- `btnShowPassword=true` and `required=true` by default (pass `required=false` for an optional field); `passwordMeter=true` renders the strength bar; `pmConfirmFieldId` pairs the confirmation field
- `helpMsg='#i18n{portal.theme.labelPasswordHelp}'` is the *new password* rule text (8 characters...): registration and change-password forms only, never a login form. On a login form pass `autocomplete='current-password'`
- The strength-meter script and the toggler script are emitted by the first `cInputPassword` call of the page (`isTogglePasswordLoaded` guard): when the first field is an old password without meter, the next field with `passwordMeter=true` has no script. Put the field that needs the meter first, or say so in the report
- A feature the old JS had and the macro lacks (a "generate password" button) is a judgment call: say so, do not keep both

### cProgress - Progress bar
- `label` (required): text displayed above the bar
- `progressId`: ID of the bar (used by JS for DOM manipulation)
- `color`: Bootstrap color (`'primary'`, `'danger'`, `'warning'`, etc.)
- `value`: initial value (0 by default)
- Not for password strength any more: `cInputPassword passwordMeter=true` carries its own

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
- Signature (`components/card/cCard.ftl`): `title titleClass titleLevel=3 titleUrl titleUrlTitle subtitle ... class id img imgType imgClass imgAlt header headerLevel=0 headerClass headerLabelClass headerImg subHeader footer footerClass orientation='v' ...`
- Use `header` for the header text, `headerLevel` for its heading level (0 = span, >0 = hN)
- `headerLabelClass` to style the header: e.g. `'text-danger fw-bold h2'`
- `title` for the main title (rendered in card-body), `titleLevel` and `titleClass` for styling, `titleUrl` to make it a link
- An image or an inline svg goes in `img=` with `imgType='svg'` (`cCard.ftl:69-77`). `imgTitle=` is not a parameter: the svg is silently dropped
- `orientation='h'` for an image beside the body
- Add `class='border border-danger'` for colored borders
- A grid of cards: `<@cCardLayout type='deck' rowCols='md-2 row-cols-lg-3'>` around `<@cCol><@cCard .../></@cCol>` items (`cCardLayout.ftl:41`)

### cBreadCrumb - Page path
- Never pass `home=`: the default is `#i18n{portal.theme.home}`, a literal (`home='Home'`, `home='Accueil'`) is untranslated copy
- On an XPage the frameset already prints the page path (`page.setPathLabel`); a `cBreadCrumb` in the template is a second navigation landmark. Use it only on pages the frameset does not path (standalone pages, `minimal_header`)
- `items=` is a list of `{title, url}` built with `<#assign items = items + [{...}]>`; the last item is the current page

### cRadio / cImg - Generated ids
- `cRadio` without `id`: several radios sharing a `name` get the same id from `cFormCheck`; give each an `id`
- `cImg` derives its `id` from `alt` when `id` is empty: two images with the same `alt` collide; pass `id`

### Model access
- Prefer property access to getter calls: `authentication.lostPasswordPageUrl`, not `authentication.getLostPasswordPageUrl()`. Both work on a bean, only the first works on a hash (JSON model of the offline renderer, `Map` put in the model)

### cTile / cEmpty / cErrorMessage / cAccordion / noScriptMessage - Component macros the theme registers
- `<@cTile title url level=3 imgName badge horizontal=false />` — clickable tile (`components/tile/cTile.ftl`, registered in `theme_commons_macros.ftl`)
- `<@cEmpty title subtitle iconName='mood-empty' actionTitle actionUrl actionIcon='plus' />` — empty state of a list (`components/empty/cEmpty.ftl`, class `lutece-ds-empty`)
- `<@cErrorMessage title text linkUrl linkLabelUrl>` — error pages; nested content for the technical cause (`components/error/cErrorMessage.ftl`, see examples.md)
- `<@cAccordion id title titleLevel=3 state=true hasCollapse=true class border=false>` — collapsible block; `state=false` starts collapsed (`components/accordion/cAccordion.ftl`)
- `<@noScriptMessage id='myForm' linkUrl='...' />` — `<noscript>` fallback with an alert and a reload link (`components/javascript/noScriptMessage.ftl`)
- `<@cBlock type='blockquote'|'aside'|'section' class=...>` — semantic wrapper, the tag is `type` (`elements/text/cBlock.ftl`)

### cForm - Validation and encoding
- Signature (`forms/layout/cForm.ftl`): `class id params name method='post' role action enctype foValidation=true`
- `foValidation=true` (default) loads `theme-form-validation.js` and `theme-form-observer.js` and exposes `window.__formValidationConfig`; never set `foValidation=false` (blocking: `verify-migration.sh` TM11)
- Uploads: `enctype='multipart/form-data'` is a parameter, no need for `params`
- Do not copy the BO `class='form-validation'` on buttons: it belongs to the admin theme and has no meaning in a skin template

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
- Dynamic validation classes: **always include `form-control`**: `class='form-control ${classPassword!}'`

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
- `label` is **required**: if the field has no visible title, keep the real text and hide it with `labelClass='visually-hidden'` (`cFormCheck.ftl` handles that class), never `label='&nbsp;'`
- **No `title` parameter**: pass the title in `params`: `params='title="my tooltip"'`
- **Pre-build dynamic values** with `<#assign>` before calling the macro:
  ```freemarker
  <#assign isChecked = false>
  <#if someCondition><#assign isChecked = true></#if>
  <#assign cbParams = ''>
  <#if field.comment?? && field.comment != ''>
      <#assign cbParams = 'title="${field.comment}"'>
  </#if>
  <#assign cbLabelClass><#if field.noDisplayTitle>visually-hidden</#if></#assign>
  <@cCheckbox name='myField' id='myField_${field.id}' value='${field.id}' checked=isChecked label=field.title labelClass=cbLabelClass params=cbParams inline=isInline />
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
- **The `<#assign>` go inside `<@cTpl>`**, never before: `<@cTpl>` wraps the whole output, so it opens the file. Whether `<#macro>` definitions sit before or after the `<#assign>` is style (FreeMarker hoists them)

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

### cInput hidden - Empty class
- `class=''` on hidden inputs prevents the default `form-control` class; a hidden input is not displayed, so this is cosmetic and optional:
  ```freemarker
  <@cInput type='hidden' name='token' value='${token}' class='' />
  ```

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

### cols - Invalid formats
- `cols='xs-12 sm-12'` → `<@cCol>` (full width by default, no need for cols)
- `cols='xs-12 col-sm-6'` → `cols='12 col-sm-6'`
- `cols='12'` alone → remove the parameter, use `<@cCol>`
- The `xs-` prefix does not exist in Bootstrap 5, always use the prefix-less form for mobile

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
      <#list (errors![]) as error>
          <@cIcon name='alert-circle' /> ${error.message}
      </#list>
  </@cAlert>

  <#-- CORRECT — assign + title -->
  <#assign errorMsg><#list (errors![]) as error>${error.message!}</#list></#assign>
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

### jQuery → Vanilla JS - Mandatory conversion
**The theme does not load jQuery** (`page_frameset.html`, optional `library-theme-jquery` only). Any JavaScript using `$(...)`, `jQuery(...)` or jQuery plugins must be **systematically** rewritten in vanilla JS when migrating a template — it is non-negotiable, otherwise the code breaks at runtime. Code depending on a jQuery plugin (DataTables, Select2, jQuery UI…) needs a manual port to a vanilla equivalent or a core macro; flag it to the user.

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

