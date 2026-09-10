---
name: lutece-update-template-bo
description: "Use when the user asks to migrate, convert or update a Lutece Back Office (admin) template to the BO FreeMarker macros from lutece-core (Tabler theme). Takes the template path as argument."
---

# Updating Lutece BO templates (admin)

You must update a Lutece BO (Back Office) template by replacing all raw HTML with the admin FreeMarker macros defined in `lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/`.

## Steps

1. **Read the target template** provided by the user
2. **Identify** all raw HTML elements that can be replaced by BO macros
3. **Consult the macros** if needed by reading the `.ftl` definition files in the tabler theme
4. **Rewrite** the template using exclusively the BO macros
5. **Do not modify** the i18n files unless necessary and requested

## HTML → BO Macros mapping table

### Page structure (Layout)

| HTML | Macro BO | Notes |
|---|---|---|
| Page container | `<@pageContainer>` | Main container, params: `id`, `height`, `class`, `actions` |
| Page column | `<@pageColumn>` | Responsive column, params: `width`, `height`, `responsiveMenuSize` |
| Page header | `<@pageHeader title='...'>` | Title + actions area nested, params: `description`, `titleClass` |
| `<div class="row">` | `<@row>` | Params: `class`, `id`, `align` |
| `<div class="col-...">` | `<@columns>` | Params: `xs`, `sm`, `md`, `lg`, `xl`, `offsetMd`, etc. |

### Box / Card (containers)

| HTML | Macro BO | Notes |
|---|---|---|
| `<div class="card">` | `<@box>` | Params: `color`, `id`, `class`, `title`, `collapsed` |
| Box header | `<@boxHeader>` | Params: `title`, `i18nTitleKey`, `titleLevel`, `boxTools` |
| Box body | `<@boxBody>` | Params: `class`, `collapsed`, `align`, `id` |
| Box footer | `<@boxFooter>` | |
| Bootstrap card | `<@card>` | Params: `headerTitle`, `headerClass`, `headerIcon`, `status`, `ribbon` |

### Tables

| HTML | Macro BO | Notes |
|---|---|---|
| `<table>` | `<@table>` | Params: `headBody`, `responsive`, `condensed`, `hover`, `striped`, `bordered` |
| `<thead>` | `<@tableHead>` | |
| `<tbody>` | `<@tableBody>` | |
| thead→tbody transition | `<@tableHeadBodySeparator />` | Used with `headBody=true` |
| `<tr>` | `<@tr>` | Params: `id`, `class`, `hide` |
| `<th>` | `<@th>` | Params: `scope`, `colspan`, `rowspan`, `align`, `cols` |
| `<td>` | `<@td>` | Params: `id`, `class`, `colspan`, `rowspan`, `align` |

### Feature list (card-based, replaces tables for entity lists)

| HTML | Macro BO | Notes |
|---|---|---|
| List container | `<@manageFeature>` | Params: `class`, `colClass`, `listClass`, `id` |
| List item | `<@manageFeatureItem>` | Params: `class`, `align`, `valign`, `bodyClass` |
| Item column | `<@manageFeatureItemColumn>` | Params: `auto`, `flex`, `cols`, `valign`, `align`, `class` |

### Pagination

| HTML | Macro BO | Notes |
|---|---|---|
| Standard pagination | `<@paginationAdmin paginator=paginator>` | Params: `combo`, `showcount`, `showall`, `nb_items_per_page` |
| AJAX pagination | `<@paginationAjax>` | Params: `paginator`, `columns`, `ajaxUrl`, `tableId`, `actions` |

### Forms

| HTML | Macro BO | Notes |
|---|---|---|
| `<form>` | `<@tform>` | Params: `type` ('horizontal','inline','flex'), `action`, `method`, `name`, `enctype` |
| label+input group | `<@formGroup>` | Params: `labelKey`, `labelFor`, `helpKey`, `mandatory`, `formStyle` |
| `<input>` | `<@input>` | Params: `type`, `name`, `value`, `size`, `maxlength`, `placeHolder`, `mandatory`, `readonly`, `disabled` |
| `<select>` | `<@select>` | Params: `name`, `items`, `default_value`, `multiple`, `sort`, `mandatory` |
| `<input type="checkbox">` | `<@checkBox>` | Params: `name`, `labelKey`, `value`, `checked`, `orientation` ('vertical','switch') |
| `<input type="radio">` | `<@radioButton>` | Params: `name`, `labelKey`, `value`, `checked`, `orientation` ('vertical','inline') |
| Search box | `<@searchBox id='...'>` | Search with auto submit |

### Buttons

| HTML | Macro BO | Notes |
|---|---|---|
| `<button>` | `<@button>` | Params: `type`, `name`, `title`, `color`, `size`, `buttonIcon`, `hideTitle`, `cancel`, `disabled` |
| `<a class="btn">` | `<@aButton>` | Params: `href`, `title`, `color`, `size`, `buttonIcon`, `hideTitle`, `target` |
| Validate/Cancel pair | `<@actionButtons>` | Params: `button1Name`, `button2Name`, `url1`, `url2`, `icon1`, `icon2` |
| Button group | `<@btnGroup>` | Params: `class`, `ariaLabel` |

### Messages, alerts and empty states

| HTML | Macro BO | Notes |
|---|---|---|
| Info/error messages | `<@messages>` | Params: `infos`, `errors`, `warnings` |
| `<div class="alert">` | `<@alert>` | Params: `color`, `title`, `dismissible`, `iconTitle` |
| Callout | `<@callOut>` | |
| Empty state (list with no result) | `<@empty>` | Params: `title`, `iconName`, `subtitle`, `actionTitle`, `actionUrl`, `actionBtn`, `actionIcon` |

### Offcanvas (side panels)

| HTML | Macro BO | Notes |
|---|---|---|
| Offcanvas panel | `<@offcanvas>` | Params: `id`, `position`, `title`, `btnColor`, `btnTitle`, `btnIcon`, `btnClass`, `btnDisabled`, `btnDropdown`, `btnDropdownContent`, `hideTitle`, `bodyClass`, `badgeContent`, `badgeColor`, `backdrop`, `size`, `btnSize`, `targetUrl`, `targetElement`, `useIframe`, `redirectForm`, `reloadOnClose`, `params` |

### Modal

| HTML | Macro BO | Notes |
|---|---|---|
| `<div class="modal">` | `<@modal>` | Params: `id`, `size`, `fullScreen`, `vCentered` |
| Modal body | `<@modalBody>` | |
| Modal header | `<@modalHeader>` | |
| Modal footer | `<@modalFooter>` | |

### Text and inline elements

| HTML | Macro BO | Notes |
|---|---|---|
| `<h1>` to `<h6>` | `<@h level=N>` | N = 1 to 6 |
| `<p>` | `<@p>` | Params: `class`, `align`, `hide` |
| `<span>` | `<@span>` | Params: `class`, `id`, `hide` |
| `<a href>` | `<@link href='...'>` | Params: `label`, `title`, `target`, `class` |
| generic `<div>` | `<@div>` | Params: `class`, `id`, `align`, `collapsed`, `hide` |
| `<pre>` | `<@pre>` | |
| `<pre><code>` | `<@code>` | |

### Icons and badges

| HTML | Macro BO | Notes |
|---|---|---|
| `<i class="ti ti-xxx">` | `<@icon style='xxx' />` | `ti ti-` prefix automatic. Params: `prefix`, `style`, `class`, `title` |
| `<span class="badge">` | `<@tag>` | Params: `color`, `title`, `tagIcon`, `size` |

### Images

| HTML | Macro BO | Notes |
|---|---|---|
| `<img>` | `<@img url='...' alt='...' />` | `class='img-fluid'` by default |
| `<figure>` | `<@figure>` | Params: `caption`, `captionPos` |

### Lists

| HTML | Macro BO | Notes |
|---|---|---|
| `<ul>` | `<@ul>` | Params: `class`, `id` |
| `<li>` | `<@li>` | Params: `class`, `id` |
| List group | `<@listGroup>` | Bootstrap list-group |
| List group item | `<@listGroupItem>` | |

### Tabs

| HTML | Macro BO | Notes |
|---|---|---|
| Tabs container | `<@tabs>` | Params: `id`, `color`, `style`, `class` |
| Tab list | `<@tabList>` | Params: `style`, `vertical`, `id`, `class`, `color` |
| Tab link | `<@tabLink>` | Params: `active`, `href` (e.g.: `'#tab1'`), `title`, `tabLabel`, `tabIcon`, `id`, `class`, `hide` |
| Tabs content | `<@tabContent>` | Params: `class`, `id` |
| Tab panel | `<@tabPanel>` | Params: `id` (required, must match the tabLink href without #), `active`, `class` |

### Accordion

| HTML | Macro BO | Notes |
|---|---|---|
| Container | `<@accordion>` | |
| Panel | `<@accordionPanel>` | |
| Header | `<@accordionHeader>` | |
| Body | `<@accordionBody>` | |

### Progress bar

| HTML | Macro BO | Notes |
|---|---|---|
| `<div class="progress">` | `<@progress>` | |
| Bar | `<@progressBar>` | |

## Mandatory conventions

### Detect and ignore email templates
Some `.html` files present in `webapp/WEB-INF/templates/admin/plugins/<plugin>/` are **not** BO templates — they are **email body** templates rendered by Java code (e.g. `NewsLetterRegistrationService.java`, `NewsletterJspBean.sendNewsletter`) and sent to end users. These templates must remain **pure table-based HTML** for compatibility with mail clients (Outlook, Gmail, Apple Mail, etc.) — **never migrate them to the BO macros**.

**Signs to detect an email template**:
- The file contains `<table cellpadding="0" cellspacing="0">`, `<td>` with inline `style="..."`, comments `<!--[if mso]>` or `<!--[if gte mso 9]>`
- Presence of a `<meta name="x-apple-disable-message-reformatting">`, of classes like `email-bg`, `darkmode-bg`, `email-container`
- Variables like `${content_1}`, `${content_2}`, `${newsletter_content}`, `${unsubscribe_key}`, `${subscriber_email}`
- The file name contains `model_`, `send_`, `confirm_mail`, `notification_`
- Loaded from Java via `AppTemplateService.getTemplate(TEMPLATE_XXX, ...)` then sent via `MailService.sendMail*`

**Action**: leave the file **strictly unchanged** and report it to the user as "out of BO migration scope". Common examples:
- `confirm_mail.html`, `confirm_mail_css.html` — subscription confirmation email
- `send_newsletter.html` — sent newsletter email body
- `templates/model_newsletter.html`, `templates/model_blogs.html` — email fragments (sections)

### Overall structure of a BO page
- **Always** structure: `<@pageContainer>` → `<@pageColumn>` → `<@pageHeader>` → content
- The `<@pageHeader>` contains the page title and the main action buttons nested (create, filter, etc.)
- The main content is in a `<@box>` + `<@boxBody>` or directly in a `<@manageFeature>`
- **Never** use a `<@box>` as the root container of a full page (recap, confirmation, dedicated form). A template that starts with `<@box>` instead of `<@pageContainer>` must be restructured with the standard hierarchy `<@pageContainer>` → `<@pageColumn>` → `<@pageHeader>`, the `<@box>` becoming a content container under the header
- **Editor page exception**: the `<@tform>` may wrap the `<@pageHeader>` and the content (see editor pattern below)
- **Embedded panels/fragments exception**: templates loaded as tab content or fragments included in a parent page do **not** use `<@pageContainer>` / `<@pageColumn>` / `<@pageHeader>`. They structure their content directly with `<@box>` / `<@boxHeader>` / `<@boxBody>`. Each logical section is a separate `<@box>` with a title in `<@boxHeader>` and the action buttons via `boxTools=true`.

### When to use @table vs @manageFeature
- **`@manageFeature`**: **always use by default** for entity lists. This is the mandatory standard pattern for any BO management page. Systematically replaces `@table` when updating templates.
- **`@table`**: reserved only for purely tabular data (statistical reports, data grids without CRUD actions, exports). Do not use for entity lists with edit/delete buttons.

### @manageFeature - Entity lists
- Each item is a card with flexible columns
- Main column (name/title): `<@manageFeatureItemColumn auto=true flex=false>` (with `flex=false` for multi-line content)
- Secondary columns with label: `<@manageFeatureItemColumn auto=true flex=false valign='top'>` with a `<@p class='fw-bold fs-3'>` as column title
- Actions column: `<@manageFeatureItemColumn align='end'>` (right-aligned)
- Checkbox column (selection): `<@manageFeatureItemColumn auto=true>` with `<@checkBox orientation='switch' />`
- No need for `<@box>` / `<@boxBody>` around it, `@manageFeatureItem` generates its own cards

### @manageFeature - Bulk actions
- Wrap the `<@manageFeature>` in a `<@tform>` with `boxed=true`
- Actions bar above the list with `<@row class='justify-content-end align-items-center'>`
- Use `<@columns>` to organize the action select + submit button + "Select all" checkbox
- Multi-action pattern (with `@select` to choose the action):
  ```freemarker
  <@tform id='form_action' method='post' action='...' boxed=true>
      <@row class='justify-content-end align-items-center'>
          <@columns md=2 offsetMd=5>
              <@inputGroup>
                  <@select id='action_select' name='action_select' disabled=true>
                      <@option value=0 label='#i18n{...}' />
                  </@select>
                  <@button type='submit' buttonIcon='check' hideTitle=['all'] disabled=true />
              </@inputGroup>
          </@columns>
          <@columns md=3>
              <@checkBox orientation='switch' name='select_all' id='select_all' labelKey='#i18n{...selectAll}' />
          </@columns>
      </@row>
      <@manageFeature>...</@manageFeature>
  </@tform>
  ```

### @manageFeature - Simplified bulk actions (single action)
- When there is only **one** bulk action (typically "Delete selection"), no need for `@select`: just a submit button + the "select all" checkbox
- The button is `disabled=true` as long as no item is checked (handled by JS)
- Pattern:
  ```freemarker
  <@tform id='form_bulk_delete' method='post' action='...' boxed=true>
      <@input type='hidden' name='entity_id' value='${entity_id}' />
      <@row class='justify-content-end align-items-center'>
          <@columns md=3>
              <@checkBox orientation='switch' id='select_all' name='select_all' labelKey='#i18n{portal.users.modify_user_rights.buttonLabelSelectAll}' />
          </@columns>
          <@columns md=2>
              <@button id='delete-all' type='submit' color='danger' buttonIcon='trash' title='#i18n{portal.util.labelDelete}' hideTitle=['all'] disabled=true />
          </@columns>
      </@row>
      <@manageFeature id='items-list'>
          <#list items as item>
              <@manageFeatureItem>
                  <@manageFeatureItemColumn auto=true>
                      <@checkBox orientation='switch' id='item_selection_${item.id}' name='item_selection' value='${item.id}' />
                  </@manageFeatureItemColumn>
                  <@manageFeatureItemColumn auto=true flex=false>
                      <strong>${item.name}</strong>
                  </@manageFeatureItemColumn>
                  <@manageFeatureItemColumn align='end'>
                      <@aButton href='...?action=remove&id=${item.id}' buttonIcon='trash' color='danger' hideTitle=['all'] title='#i18n{portal.util.labelDelete}' />
                  </@manageFeatureItemColumn>
              </@manageFeatureItem>
          </#list>
      </@manageFeature>
  </@tform>
  ```
- **Standard JS** to place at the end of the template to enable/disable the bulk button:
  ```javascript
  <script>
  document.addEventListener('DOMContentLoaded', function() {
      const btnDeleteAll = document.getElementById('delete-all');
      const selectAll = document.getElementById('select_all');
      const checkboxes = document.querySelectorAll('#items-list input[name="item_selection"]');

      function updateDeleteButton() {
          const anyChecked = Array.from(checkboxes).some(cb => cb.checked);
          if (anyChecked) { btnDeleteAll.removeAttribute('disabled'); } else { btnDeleteAll.setAttribute('disabled', ''); }
      }

      if (selectAll) {
          selectAll.addEventListener('change', function() {
              checkboxes.forEach(cb => { cb.checked = selectAll.checked; });
              updateDeleteButton();
          });
      }
      checkboxes.forEach(cb => cb.addEventListener('change', updateDeleteButton));
  });
  </script>
  ```
- Adapt `#items-list` and `name="item_selection"` to each context (e.g.: `#subscribers-list` + `subscriber_selection`, `#archive-list` + `newsletter_selection`)

### @tform boxed=true - Replacing @box
- When a `<@box>` / `<@boxBody>` only contains a `<@tform>` or a `<@manageFeature>`, remove the `<@box>` and add `boxed=true` to the `<@tform>`
- Same when a `<@box>` only contains a `<@table>`: the table comes out of the box and the box is removed

### @empty - Empty state (MANDATORY)
- **Always** test whether the list is empty before displaying a `<@manageFeature>` or a `<@table>` with iterated data
- When the list is empty, display a message with `<@empty>` in a `<@card>`
- Params: `title`, `iconName`, `subtitle`, `actionTitle`, `actionUrl`, `actionBtn`, `actionIcon`
- Choose an `iconName` relevant to the business context (e.g.: `calendar-off` for appointments, `users-minus` for users, `inbox-off` by default)
- Standard pattern (full page):
  ```freemarker
  <#if list?has_content>
      <@manageFeature>...</@manageFeature>
  <#else>
      <@card>
          <@empty title='#i18n{...noResult}' iconName='inbox-off' subtitle='#i18n{...help}' actionTitle='#i18n{...buttonCreate}' actionUrl='...' />
      </@card>
  </#if>
  ```
- Simplified pattern (widget/dashboard, without action button):
  ```freemarker
  <#if list?has_content>
      <@manageFeature>...</@manageFeature>
  <#else>
      <@empty title='#i18n{...empty}' iconName='inbox-off' />
  </#if>
  ```

### Actions dropdown in lists (manageFeature, adminDashboardWidget)
- In a `<@manageFeature>` or a `<@adminDashboardWidget>`, when a list item has **more than 2 action buttons**, group the actions in a dropdown menu
- Use `<@aButton dropdownMenu=true>` as the container, then convert each `<@aButton>` into a `<@link>` with `class='dropdown-item'`
- When converting to `<@link>`: remove the `buttonIcon`, `color`, `size` and `hideTitle` parameters (not applicable to dropdown links)
- Keep `href` and use `label` instead of `title` for the link text
- For the delete action, add `text-danger` to the `<@link>` class for visual signaling
- In a `<@manageFeature>`, place the dropdown in a `<@manageFeatureItemColumn align='end'>` and give a unique `id` per item (suffix with the entity identifier)
- Pattern (inside `@manageFeature`):
  ```freemarker
  <@manageFeatureItemColumn align='end'>
      <@aButton class='dropdown-toggle' id='item-actions-${item.id}' dropdownMenu=true href='#' title='#i18n{portal.util.labelActions}' color='' hideTitle=['all'] buttonIcon='dots-vertical'>
          <@link class='dropdown-item' href='jsp/admin/.../Modify.jsp?id=${item.id}' label='#i18n{...labelModify}' />
          <@link class='dropdown-item' href='jsp/admin/.../Compose.jsp?id=${item.id}' label='#i18n{...labelCompose}' />
          <@link class='dropdown-item' href='jsp/admin/.../Copy.jsp?id=${item.id}' label='#i18n{...labelCopy}' />
          <@link class='dropdown-item text-danger' href='jsp/admin/.../Remove.jsp?id=${item.id}' label='#i18n{portal.util.labelDelete}' />
      </@aButton>
  </@manageFeatureItemColumn>
  ```

### @pageHeader - Actions
- The button to create an entity must be in the `<@pageHeader>` nested
- Use an `<@offcanvas>` in the header for the creation/filtering forms
- Standard pattern:
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <@offcanvas id="create" title="..." btnTitle="..." btnIcon="plus" btnColor="primary" position="end">
          <@tform ...>...</@tform>
      </@offcanvas>
  </@pageHeader>
  ```

### @pageHeader - Search in an offcanvas
- When the list contains more than one element, offer a search offcanvas in the `<@pageHeader>`
- The search button uses `btnIcon='search'` and `size='sm'` for a compact panel
- Use `method='get'` on the search `<@tform>`: the search parameters appear in the URL, which allows bookmarking/sharing/back navigation
- Minimal pattern (simple text search):
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <#if list?has_content && list?size gt 1>
          <@offcanvas id='offcanvasSearch' title='#i18n{portal.util.labelSearch}' btnTitle='#i18n{portal.util.labelSearch}' btnIcon='search' btnClass='me-1' position='end' size='sm'>
              <@tform method='get' action='jsp/admin/plugins/.../ManageXxx.jsp'>
                  <@formGroup labelFor='search_text' labelKey='#i18n{portal.util.labelSearch}'>
                      <@inputGroup>
                          <@input type='text' id='search_text' name='search_text' value='${search_text!}' />
                          <@button type='submit' buttonIcon='search' hideTitle=['all'] />
                      </@inputGroup>
                  </@formGroup>
              </@tform>
          </@offcanvas>
      </#if>
  </@pageHeader>
  ```

### @pageHeader - Multi-filter search (text, date, selection)
- For a search form with several criteria, use one `<@formGroup>` per field (no nested `<@inputGroup>`)
- Standard input types: `type='text'` for the name, `type='date'` for a date, `<@select>` for a status/category
- Add a **Reset** button in `color='secondary'` next to the Search button `color='primary'` — the back-end clears the search values when `search_reset=1`
- **Always** reinject the current values into the inputs via `value='${search_xxx!}'` so the form re-displays with the active filters after submission
- Pattern:
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <#if list?has_content && list?size gt 1>
          <@offcanvas id='item-search' title='#i18n{portal.util.labelSearch}' btnTitle='#i18n{portal.util.labelSearch}' btnIcon='search' btnClass='me-1' position='end' size='sm'>
              <@tform method='get' action='jsp/admin/plugins/.../ManageItems.jsp'>
                  <@formGroup labelFor='search_name' labelKey='#i18n{...columnTitleName}'>
                      <@input type='text' id='search_name' name='search_name' value='${search_name!}' />
                  </@formGroup>
                  <@formGroup labelFor='search_date' labelKey='#i18n{...columnTitleDate}'>
                      <@input type='date' id='search_date' name='search_date' value='${search_date!}' />
                  </@formGroup>
                  <@formGroup labelFor='search_status' labelKey='#i18n{...columnTitleStatus}'>
                      <@select id='search_status' name='search_status' default_value='${search_status!}'>
                          <@option value='' label='#i18n{portal.util.labelAll}' />
                          <@option value='1' label='#i18n{portal.util.labelActive}' />
                          <@option value='0' label='#i18n{portal.util.labelInactive}' />
                      </@select>
                  </@formGroup>
                  <@formGroup>
                      <@button type='submit' buttonIcon='search' title='#i18n{portal.util.labelSearch}' color='primary' />
                      <@button type='submit' name='search_reset' value='1' buttonIcon='x' title='#i18n{portal.util.labelReset}' color='secondary' />
                  </@formGroup>
              </@tform>
          </@offcanvas>
      </#if>
  </@pageHeader>
  ```

### @pageHeader - Direct action buttons (Import, Export, etc.)
- Some actions triggered from the header do not require a form to fill in (importing a file, Export, Clean subscribers, etc.): the click directly submits a hidden form
- Use `<@tform type='inline'>` with an `<@input type='hidden'>` for the identifier, and a single `<@button type='submit'>` — **no offcanvas**
- Apply `class='me-1'` for spacing and `hideTitle=['xs','sm']` to only show the icon on mobile
- Pattern:
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <#if is_import_right>
          <@tform type='inline' method='post' action='jsp/admin/plugins/myplugin/ImportItems.jsp'>
              <@input type='hidden' name='parent_id' value='${parent.id}' />
              <@button type='submit' buttonIcon='upload' title='#i18n{...buttonImport}' hideTitle=['xs','sm'] class='me-1' />
          </@tform>
      </#if>
      <#if items?has_content && is_export_right>
          <@tform type='inline' method='post' action='jsp/admin/plugins/myplugin/ExportItems.jsp'>
              <@input type='hidden' name='parent_id' value='${parent.id}' />
              <@button type='submit' buttonIcon='download' title='#i18n{...buttonExport}' hideTitle=['xs','sm'] />
          </@tform>
      </#if>
  </@pageHeader>
  ```
- Place these buttons **after** the offcanvas (Properties/Search/Create) — they are secondary actions
- Destructive actions like "Import+Delete" (replace the whole list) use `color='danger'` but remain a direct button (no offcanvas)

### @pageHeader - Recommended order of offcanvas
When the `<@pageHeader>` contains several offcanvas (configuration, search, creation), order them from **left to right** following the logic:
1. **Configuration / Properties** (`btnIcon='cog'`, `btnColor=''` by default) — general configuration of the feature, optional
2. **Search / Filter** (`btnIcon='search'`, `btnColor=''` by default) — conditional on `list?size gt 1`
3. **Creation** (`btnIcon='plus'`, `btnColor='primary'`) — main action, always last (on the right)

The primary button (creation) stays visually the rightmost. The secondary buttons (properties, search) use `btnClass='me-1'` for spacing.

```freemarker
<@pageHeader title='#i18n{...title}'>
    <#if right_manage_properties?? && right_manage_properties>
        <@offcanvas id='item-properties' targetUrl='...' useIframe=true title='...' btnTitle='...' btnIcon='cog' btnClass='me-1' position='end' size='half' />
    </#if>
    <#if list?has_content && list?size gt 1>
        <@offcanvas id='item-search' title='...' btnTitle='...' btnIcon='search' btnClass='me-1' position='end' size='sm'>
            <@tform method='get' action='...'>...</@tform>
        </@offcanvas>
    </#if>
    <#if creation_allowed>
        <@offcanvas id='item-create' targetUrl='...' useIframe=true title='...' btnTitle='...' btnIcon='plus' btnColor='primary' position='end' size='half' />
    </#if>
</@pageHeader>
```

### @pageHeader - Editor toolbar (editor pattern)
- For editor pages (create/modify with rich content), the `<@tform>` wraps the `<@pageHeader>` and the content
- The toolbar is in the `<@pageHeader>` via `<@row>` + `<@columns class='d-flex justify-content-end align-items-center'>`
- The additional properties (tags, files, URL, comment) are in an `<@offcanvas>` in the toolbar
- Toolbar buttons with `hideTitle=['xs','sm', 'md', 'lg']` to only show the icons
- A submit button duplicated at the bottom of the content for easier access
- Pattern:
  ```freemarker
  <@pageContainer>
      <@pageColumn>
          <@tform name='...' id='form-editor' enctype='multipart/form-data' action='...'>
              <@pageHeader title='#i18n{...pageTitle}'>
                  <@input type='hidden' name='action' value='...' />
                  <@row id='toolbar-wrapper'>
                      <@columns id='toolbar' class='d-flex justify-content-end align-items-center'>
                          <@button class='me-1 action' type='submit' buttonIcon='check me-2' title='#i18n{...save}' hideTitle=['xs','sm', 'md', 'lg'] />
                          <@offcanvas id='properties' title='#i18n{...properties}' position='end' btnIcon='cog me-2' btnClass='me-1 rounded-end' hideTitle=['xs','sm', 'md', 'lg']>
                              <@box>...</@box>
                          </@offcanvas>
                      </@columns>
                  </@row>
              </@pageHeader>
              <@messages errors=errors />
              ...editable fields...
              <@button class='my-3 action' type='submit' buttonIcon='check me-2' title='#i18n{...save}' />
          </@tform>
      </@pageColumn>
  </@pageContainer>
  ```

### @offcanvas - Side panels
- Used for inline editing: `<@offcanvas targetUrl="..." targetElement="..." btnIcon="edit" />`
- Used for creation forms: `<@offcanvas id="..." btnTitle="..." position="end">...</@offcanvas>`
- Used for search/filters: `<@offcanvas id="..." btnIcon="search" placement="end" size="sm">...</@offcanvas>`
- Used for the properties of an editor: `<@offcanvas id="..." btnIcon="cog me-2" position="end" btnClass="me-1 rounded-end">...</@offcanvas>`
- `position='end'` for panels on the right (recommended default)
- `targetUrl` loads the content via AJAX
- **Optional** — `useIframe=true`: loads the content of `targetUrl` in an iframe instead of an AJAX call. Useful when the target page is a full standalone page (e.g.: publication, history). Do not apply systematically, only on explicit user request. Pattern:
  ```freemarker
  <@offcanvas id='my-panel' targetUrl='jsp/admin/...' useIframe=true title='#i18n{...}' btnTitle='#i18n{...}' btnIcon='globe' btnClass='me-1' position='end' size='full' />
  ```
- **Optional** — `reloadOnClose=true`: reloads the parent page when the offcanvas closes. Useful when the offcanvas content modifies data displayed on the page (e.g.: publication, unpublication). Default: `false`. Do not apply systematically, only when necessary. Pattern:
  ```freemarker
  <@offcanvas id='my-panel' targetUrl='jsp/admin/...' useIframe=true reloadOnClose=true title='#i18n{...}' btnTitle='#i18n{...}' btnIcon='globe' position='end' size='full' />
  ```

### @offcanvas - Replacing links in a dropdown menu
- When replacing `<@link>` inside a `<@aButton dropdownMenu=true>`, use `<@offcanvas>` with `btnClass='dropdown-item portlet-type-ref'` and `btnColor=''` to keep the dropdown style
- The `id` must be unique per list item (suffix with the entity identifier)
- `btnIcon=''` to not show an icon (consistent with the dropdown links)
- Pattern:
  ```freemarker
  <@aButton class='dropdown-toggle' id='portlet-type' dropdownMenu=true href='#' title='#i18n{portal.util.labelActions}' color=''>
      <@offcanvas id='offcanvasModify-${item.id}' targetUrl='jsp/admin/...' useIframe=true title='#i18n{...labelModify}' btnTitle='#i18n{...labelModify}' btnIcon='' btnColor='' btnClass='dropdown-item portlet-type-ref' position='end' size='half' />
      <@offcanvas id='offcanvasManage-${item.id}' targetUrl='jsp/admin/...' useIframe=true title='#i18n{...labelManage}' btnTitle='#i18n{...labelManage}' btnIcon='' btnColor='' btnClass='dropdown-item portlet-type-ref' position='end' size='half' />
      <@link class='dropdown-item portlet-type-ref' href='jsp/admin/.../Remove.jsp?id=${item.id}' label='#i18n{...labelRemove}' />
  </@aButton>
  ```

### @offcanvas - Replacing action buttons in a list
- When replacing `<@aButton>` in an actions column `<@manageFeatureItemColumn align='end'>`, use `<@offcanvas>` with `btnColor=''` and `btnClass='me-1'` to keep the spacing
- The `id` must be unique per list item (suffix with the entity identifier)
- Keep the delete/remove actions as `<@aButton>` (not relevant in offcanvas)
- Pattern:
  ```freemarker
  <@manageFeatureItemColumn align='end'>
      <@offcanvas id='offcanvasModify-${item.key}' targetUrl='jsp/admin/.../Modify.jsp?key=${item.key}' useIframe=true title='#i18n{portal.util.labelModify}' btnTitle='#i18n{portal.util.labelModify}' btnIcon='edit' btnColor='' btnClass='me-1' hideTitle=['xs','sm'] position='end' size='half' />
      <@offcanvas id='offcanvasManageUsers-${item.key}' targetUrl='jsp/admin/.../ManageUsers.jsp?key=${item.key}' useIframe=true title='#i18n{...labelManageUsers}' btnTitle='#i18n{...labelManageUsers}' btnIcon='users' btnColor='' btnClass='me-1' hideTitle=['xs','sm'] position='end' size='half' />
      <@aButton href='jsp/admin/.../Remove.jsp?key=${item.key}' title='#i18n{...labelRemove}' hideTitle=['all'] buttonIcon='trash' color='danger' />
  </@manageFeatureItemColumn>
  ```

### @offcanvas - Replacing a collapse button with a standard offcanvas
- When a `<@button>` of collapse type (`style='card-control collapse'` / `buttonTargetId='#...'`) controls a `<@div>` containing a search form, replace the whole thing with a standard `<@offcanvas>` that embeds the form directly
- Remove the wrapper `<@div>` and move its content (the `<@tform>`) inside the `<@offcanvas>`
- The `<@tform>` embedded in the offcanvas does not require `boxed=true`
- Pattern:
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <@offcanvas id='offcanvasSearch' title='#i18n{...buttonSearch}' btnTitle='#i18n{...buttonSearch}' btnIcon='search' btnClass='me-1' position='end' size='sm'>
          <@tform method='post' name='search_form' id='search_form' action='jsp/admin/...'>
              <@formGroup labelFor='field' labelKey='#i18n{...labelField}'>
                  <@input type='text' id='field' name='search_field' value='${filter.field}' />
              </@formGroup>
              <@formGroup>
                  <@button type='submit' name='search_submit' title='#i18n{...buttonSearch}' buttonIcon='search' />
              </@formGroup>
          </@tform>
      </@offcanvas>
      <@offcanvas id='create' targetUrl='jsp/admin/.../Create.jsp' useIframe=true title='#i18n{...buttonCreate}' btnTitle='#i18n{...buttonCreate}' btnIcon='plus' btnColor='primary' position='end' size='half' />
  </@pageHeader>
  ```

### @tform - Forms
- `type='horizontal'` for standard forms (label on the left, input on the right)
- `type='inline'` for inline forms (action buttons)
- `boxed=true` when the form replaces a `<@box>` wrapper (see convention above)
- Use `<@formGroup>` to group label + input with `labelKey`, `helpKey`, `mandatory`

### @messages - Info/error messages
- Place `<@messages infos=infos />` at the top of the main content (after `<@pageHeader>`)
- Place `<@messages errors=errors />` in the relevant form (after `<@pageHeader>` in the editor pattern)
- `<@messages warnings=warnings />` for warnings
- Do not duplicate `<@messages>`: a single call per type

### @alert - Contextual alerts
- Use `<@alert color='...' title=... />` (self-closing with `title`) for simple messages
- When the alert content is **conditional** (e.g.: validation error message), precompute the text in a variable then pass it via `title`:
  ```freemarker
  <#if error.mandatoryError>
      <#assign errorMsg = error.errorMessage>
  <#else>
      <#assign errorMsg = '#i18n{plugin.message.mandatory.entry}'>
  </#if>
  <@alert color='danger' title=errorMsg />
  ```
- Do **not** use `<@alert>content</@alert>` when a simple `title` is enough — prefer the self-closing form
- `color`: `'danger'`, `'warning'`, `'info'`, `'success'`
- `iconTitle` to add an icon: `<@alert color='warning' iconTitle='exclamation-circle'>`
- `dismissible=true` to allow manual closing

### @checkBox - Checkboxes
- **Always** add `orientation='switch'` on all `<@checkBox>` to use the standard switch (toggle) style of the Tabler theme
- Do not use the `labelFor` parameter on `<@checkBox>` when an `id` is already present (redundant)

### @button / @aButton - Buttons
- `<@button>` for form actions (submit)
- `<@aButton>` for links styled as buttons (navigation)
- `buttonIcon` uses the Tabler icons (without prefix): `'edit'`, `'trash'`, `'plus'`, `'check'`, `'times'`
- `hideTitle=['all']` for icon-only buttons in lists
- `hideTitle=['xs','sm', 'md', 'lg']` for toolbar buttons (icon-only except on large screens)
- `cancel=true` on the Cancel button of a form
- `color`: `'primary'`, `'secondary'`, `'success'`, `'danger'`, `'warning'`, `'info'`

### @paginationAdmin - Pagination
- Always place after the `<@table>` or `<@manageFeature>`
- `combo=1` to show the selector of the number of items per page
- Condition the display on the number of items: `<#if list?size gte 10><@paginationAdmin ... /></#if>`

### @columns - Responsive grid
- Use the named parameters: `<@columns sm=9>`, `<@columns md=6 lg=4>`
- For an auto column: `<@columns>` without a size parameter
- `offsetMd` for the offset: `<@columns md=2 offsetMd=5>`

### @icon - Tabler icons
- The `ti ti-` prefix is added automatically
- `<@icon style='edit' />` → `<i class="ti ti-edit">`
- Additional classes via `class`: `<@icon style='check' class='me-1' />`

### i18n
- All displayed texts must use `#i18n{plugin.key}`
- Do not write hardcoded text in the template

### @aButton → @offcanvas - Converting navigation buttons
- **Always** convert the navigation `<@aButton>` to creation or modification pages into `<@offcanvas>` with `useIframe=true`
- This includes: the "Add" button in the `<@pageHeader>`, the "Modify" button in the actions columns
- **Do not convert** the delete/confirmation buttons (they remain `<@aButton>` because they require a real navigation with confirmation)
- "Add" button pattern in the header:
  ```freemarker
  <@offcanvas id='offcanvasCreate' targetUrl='jsp/admin/.../Create.jsp' useIframe=true title='#i18n{...buttonCreate}' btnTitle='#i18n{...buttonCreate}' btnIcon='plus' btnColor='primary' position='end' size='half' />
  ```
- "Modify" button pattern in a list:
  ```freemarker
  <@offcanvas id='offcanvasModify-${item.id}' targetUrl='jsp/admin/.../Modify.jsp?id=${item.id}' useIframe=true title='#i18n{portal.util.labelModify}' btnTitle='#i18n{portal.util.labelModify}' btnIcon='edit' btnColor='' btnClass='me-1' hideTitle=['all'] position='end' size='half' />
  ```

### What NOT to do
- Do not use raw HTML when a macro exists
- Do not add JavaScript unless requested
- Do not wrap a `<@manageFeature>` in a `<@box>` (the items are already cards)
- NEVER use `<@table>` for an entity list with CRUD actions → always convert to `<@manageFeature>`. Existing `@table` in the templates to update must be systematically replaced by `@manageFeature`
- Do not put the creation form in a separate column → prefer an `<@offcanvas>` in the `<@pageHeader>`
- Do not use `<@aButton>` to navigate to a creation or modification page → use `<@offcanvas>` with `useIframe=true` instead
- Do not duplicate `<@messages>` (a single call per message type)
- Do not wrap a `<@tform>` in a `<@box>` when the box only serves to contain the form → use `boxed=true`
- NEVER iterate a list (`<#list>`) without first testing whether it is non-empty (`?has_content`) and displaying a `<@empty>` otherwise

## Macro files reference

The definitions are located in:
- **Components**: `lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/components/`
  - `accordion/`, `alert/`, `box/`, `button/`, `card/`, `features/`, `icon/`, `list/`, `modal/`, `navbar/`, `offcanvas/`, `pagination/`, `progress/`, `table/`, `tabs/`, `tags/`
- **Elements**: `lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/elements/`
  - `code/`, `div/`, `image/`, `link/`, `paragraph/`, `preformatted/`, `span/`, `title/`
- **Forms**: `lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/forms/`
  - `checkbox/`, `form/`, `input/`, `radio/`, `search/`, `select/`
- **Layout**: `lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/layout/`
  - `columns/`, `page/`, `row/`

If in doubt about a macro's parameters, **read the corresponding .ftl file** to consult the signature.

## Reference examples

### Management page with @manageFeature (list + creation offcanvas)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_items.title}'>
			<@offcanvas id="offcanvasCreate" title="#i18n{plugin.create_item.title}" btnTitle="#i18n{plugin.create_item.title}" btnIcon="plus" btnColor="primary" position="end">
				<@tform name='create_item' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
					<@messages errors=errors />
					<@formGroup labelFor='name' labelKey='#i18n{plugin.create_item.labelName}' helpKey='#i18n{plugin.create_item.labelName.help}' mandatory=true>
						<@input type='text' name='name' value='' />
					</@formGroup>
					<@formGroup>
						<@button type='submit' name='action_createItem' buttonIcon='check' title='#i18n{portal.admin.message.buttonValidate}' />
						<@button type='submit' name='view_manageItems' buttonIcon='times' title='#i18n{portal.admin.message.buttonCancel}' color='secondary' cancel=true />
					</@formGroup>
				</@tform>
			</@offcanvas>
		</@pageHeader>
		<@messages infos=infos />
		<@manageFeature>
			<#list item_list as item>
			<@manageFeatureItem>
				<@manageFeatureItemColumn>
					<strong>${item.name}</strong>
				</@manageFeatureItemColumn>
				<@manageFeatureItemColumn auto=true align='end'>
					<@offcanvas targetUrl="jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&id=${item.id}" targetElement="#edit_item" id="item-edit-${item.id}" btnIcon="edit" btnColor="primary" position="end" title="#i18n{portal.util.labelModify}" />
					<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?action=confirmRemoveItem&id=${item.id}' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' color='danger' size='' hideTitle=['all'] />
				</@manageFeatureItemColumn>
			</@manageFeatureItem>
			</#list>
		</@manageFeature>
		<@paginationAdmin paginator=paginator combo=1 />
	</@pageColumn>
</@pageContainer>
```

### Management page with @table (tabular data)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_data.title}'>
			<@aButton href='jsp/admin/plugins/myplugin/CreateData.jsp' buttonIcon='plus' color='primary' title='#i18n{plugin.manage_data.buttonCreate}' />
		</@pageHeader>
		<@messages infos=infos />
		<@box>
			<@boxBody>
				<@table headBody=true>
					<@tr>
						<@th>#i18n{plugin.manage_data.columnName}</@th>
						<@th>#i18n{plugin.manage_data.columnStatus}</@th>
						<@th>#i18n{plugin.manage_data.columnDate}</@th>
						<@th>#i18n{portal.util.labelActions}</@th>
					</@tr>
					<@tableHeadBodySeparator />
					<#list data_list as data>
					<@tr>
						<@td>${data.name}</@td>
						<@td><@tag color='${data.active?then("success","danger")}'>${data.active?then("Actif","Inactif")}</@tag></@td>
						<@td>${data.date}</@td>
						<@td>
							<@aButton href='jsp/admin/plugins/myplugin/ModifyData.jsp?id=${data.id}' buttonIcon='edit' color='primary' title='#i18n{portal.util.labelModify}' size='' hideTitle=['all'] />
							<@aButton href='jsp/admin/plugins/myplugin/ManageData.jsp?action=confirmRemoveData&id=${data.id}' buttonIcon='trash' color='danger' title='#i18n{portal.util.labelDelete}' size='' hideTitle=['all'] />
						</@td>
					</@tr>
					</#list>
				</@table>
				<@paginationAdmin paginator=paginator combo=1 />
			</@boxBody>
		</@box>
	</@pageColumn>
</@pageContainer>
```

### Edit form (dedicated page)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.modify_item.title}' />
		<@box>
			<@boxBody>
				<@messages errors=errors />
				<@tform name='modify_item' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
					<@input type='hidden' name='id' value='${item.id}' />
					<@formGroup labelFor='name' labelKey='#i18n{plugin.modify_item.labelName}' mandatory=true>
						<@input type='text' name='name' value='${item.name!}' />
					</@formGroup>
					<@formGroup labelFor='description' labelKey='#i18n{plugin.modify_item.labelDescription}'>
						<@input type='textarea' name='description' value='${item.description!}' />
					</@formGroup>
					<@formGroup labelFor='status' labelKey='#i18n{plugin.modify_item.labelStatus}'>
						<@select name='status' items=status_list default_value='${item.status}' />
					</@formGroup>
					<@actionButtons button1Name='action_modifyItem' button2Name='view_manageItems' />
				</@tform>
			</@boxBody>
		</@box>
	</@pageColumn>
</@pageContainer>
```

### Page with tabs (internal)

Internal tabs: `href='#panelId'` with `data-bs-toggle="tab"` added automatically.

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.detail_item.title}' />
		<@tabs id="item-tabs">
			<@tabList>
				<@tabLink active=true href='#general' title='#i18n{plugin.detail_item.tabGeneral}' />
				<@tabLink href='#advanced' title='#i18n{plugin.detail_item.tabAdvanced}' />
			</@tabList>
			<@tabContent>
				<@tabPanel id='general' active=true>
					<@box>
						<@boxBody>
							...
						</@boxBody>
					</@box>
				</@tabPanel>
				<@tabPanel id='advanced'>
					<@box>
						<@boxBody>
							...
						</@boxBody>
					</@box>
				</@tabPanel>
			</@tabContent>
		</@tabs>
	</@pageColumn>
</@pageContainer>
```

### Page with tabs (URL navigation)

Tabs that navigate to JSPs: `href='jsp/admin/...'` (no `#`, no `@tabPanel`).

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_item.title}' />
		<@tabs>
			<@tabList>
				<@tabLink active=true href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=list' title='#i18n{plugin.tab.list}' />
				<@tabLink href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=settings' title='#i18n{plugin.tab.settings}' />
			</@tabList>
		</@tabs>
		...current page content...
	</@pageColumn>
</@pageContainer>
```

### Advanced management page (search offcanvas + bulk actions + empty state)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@pageHeader title='#i18n{plugin.manage_items.title}' toolsClass='d-flex'>
			<#if permission_create>
				<@tform action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
					<@button type='submit' name='view_createItem' buttonIcon='plus' class='me-1' title='#i18n{plugin.manage_items.buttonAdd}' hideTitle=['xs'] />
				</@tform>
			</#if>
			<#if item_list?has_content && item_list?size gt 1>
				<@offcanvas id='offcanvasSearch' title='#i18n{plugin.manage_items.search}' btnTitle='#i18n{plugin.manage_items.search}' placement='end' btnIcon='search' size='sm'>
					<@tform id='form-search' action='jsp/admin/plugins/myplugin/ManageItems.jsp?search='>
						<@formGroup labelFor='search_text' labelKey='#i18n{plugin.manage_items.search}'>
							<@inputGroup>
								<@input type='text' id='search_text' name='search_text' value='${search_text!\'\'}' />
								<@button type='submit' buttonIcon='search' hideTitle=['all'] />
							</@inputGroup>
						</@formGroup>
						<@formGroup labelFor='status' labelKey='#i18n{plugin.manage_items.labelStatus}'>
							<@select id='status' name='status'>
								<@option value="0" label='#i18n{plugin.manage_items.labelAll}' />
								<@option value="1" label='#i18n{plugin.manage_items.labelActive}' />
								<@option value="2" label='#i18n{plugin.manage_items.labelInactive}' />
							</@select>
						</@formGroup>
						<@columns>
							<@button type='submit' buttonIcon='search me-1' title='#i18n{plugin.manage_items.search}' />
							<@button type='submit' color='danger' buttonIcon='x me-1' name='button_reset' title='#i18n{plugin.manage_items.reset}' />
						</@columns>
					</@tform>
				</@offcanvas>
			</#if>
		</@pageHeader>
		<@messages infos=infos />
		<#if item_list?has_content && item_list?size gt 0>
			<@tform id='form_bulk_action' method='post' action='jsp/admin/plugins/myplugin/ManageItems.jsp' boxed=true>
				<@input type='hidden' id='action' name='action' value='bulk_action' />
				<#if permission_archive || permission_delete>
					<@row class='justify-content-end align-items-center'>
						<@columns md=2 offsetMd=5>
							<@inputGroup>
								<@select id='select_action' name='select_action' disabled=true>
									<@option value=0 selected=true label='#i18n{plugin.manage_items.labelArchive}' />
									<@option value=1 label='#i18n{plugin.manage_items.labelDelete}' />
								</@select>
								<@button type='submit' id='btn_apply' buttonIcon='check' hideTitle=['all'] disabled=true />
							</@inputGroup>
						</@columns>
						<@columns md=3>
							<@checkBox orientation='switch' name='select_all' id='select_all' labelKey='#i18n{plugin.manage_items.selectAll}' />
						</@columns>
					</@row>
				</#if>
				<@manageFeature>
					<#list item_list as item>
					<@manageFeatureItem>
						<#if permission_archive || permission_delete>
							<@manageFeatureItemColumn auto=true>
								<@checkBox orientation='switch' id='selected_${item.id}' name='select_id' value='${item.id}' />
							</@manageFeatureItemColumn>
						</#if>
						<@manageFeatureItemColumn auto=true flex=false>
							<@link href="jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&amp;id=${item.id}" title="#i18n{portal.util.labelModify}">
								<strong>${item.name!}</strong>
							</@link>
							<@p class='my-1'><small>#i18n{plugin.manage_items.labelCreatedBy} <strong>${item.author!}</strong> ${item.creationDate!}</small></@p>
						</@manageFeatureItemColumn>
						<@manageFeatureItemColumn auto=true flex=false valign='top'>
							<@p class='fw-bold fs-3'>#i18n{plugin.manage_items.labelTags}</@p>
							<#if item.tags?size gt 0>
								<#list item.tags as tag><@tag color='info'>${tag.name!}</@tag></#list>
							<#else>
								<@tag color='info'>#i18n{plugin.manage_items.noTag}</@tag>
							</#if>
						</@manageFeatureItemColumn>
						<@manageFeatureItemColumn align='end'>
							<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=modifyItem&amp;id=${item.id}' title='#i18n{portal.util.labelModify}' buttonIcon='pencil' hideTitle=['all'] />
							<@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?action=confirmRemoveItem&amp;id=${item.id}' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' hideTitle=['all'] color='danger' />
						</@manageFeatureItemColumn>
					</@manageFeatureItem>
					</#list>
				</@manageFeature>
			</@tform>
			<#if item_list?size gte 10><@paginationAdmin paginator=paginator combo=1 /></#if>
		<#else>
			<@card>
				<#if permission_create>
					<@empty title='#i18n{plugin.manage_items.noResult}' iconName='inbox-off' subtitle='#i18n{plugin.manage_items.help}' actionTitle='#i18n{plugin.manage_items.buttonAdd}' actionUrl='jsp/admin/plugins/myplugin/ManageItems.jsp?view=createItem' />
				<#else>
					<@empty title='#i18n{plugin.manage_items.noResult}' iconName='inbox-off' subtitle='#i18n{plugin.manage_items.help}' />
				</#if>
			</@card>
		</#if>
	</@pageColumn>
</@pageContainer>
```

### Editor page (create/modify with toolbar, properties offcanvas, rich content)

```freemarker
<@pageContainer>
	<@pageColumn>
		<@tform name='modify_item' class='position-relative' id='form-editor' enctype='multipart/form-data' action='jsp/admin/plugins/myplugin/ManageItems.jsp'>
			<@pageHeader title='#i18n{plugin.modify_item.pageTitle}'>
				<@input type='hidden' id='id' name='id' value=item.id />
				<@input type='hidden' id='action' name='action' value='modifyItem' />
				<@row id='toolbar-wrapper'>
					<@columns id='toolbar' class='d-flex justify-content-end align-items-center'>
						<@button class='me-1 action' type='submit' size='' buttonIcon='check me-2' title='#i18n{plugin.modify_item.labelSave}' id='action_save' name='action_save' hideTitle=['xs','sm', 'md', 'lg'] />
						<@aButton class='me-1' href='jsp/admin/plugins/myplugin/ManageItems.jsp?action=confirmRemoveItem&amp;id=${item.id}' color='danger' title='#i18n{portal.util.labelDelete}' buttonIcon='trash' hideTitle=['xs','sm', 'md', 'lg'] size='' />
						<@aButton class='me-1' href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=previewItem&id=${item.id}' title='#i18n{plugin.modify_item.labelPreview}' hideTitle=['xs','sm', 'md', 'lg'] color='default' size='' buttonIcon='eye' />
						<@offcanvas id='item-properties' title='#i18n{plugin.modify_item.labelProperties}' btnTitle='#i18n{plugin.modify_item.labelProperties}' position='end' btnIcon='cog me-2' btnClass='me-1 rounded-end' hideTitle=['xs','sm', 'md', 'lg']>
							<@box>
								<@boxHeader title='#i18n{plugin.modify_item.labelTags}'>
									<@icon style='tags' />
								</@boxHeader>
								<@boxBody>
									<@formGroup labelFor='addTag' labelKey='#i18n{plugin.manage_tags.buttonAdd}' rows=2>
										<@inputGroup>
											<@select name='tag_doc' default_value='' items=list_tag size='' />
											<@inputGroupItem type='btn'>
												<@button type='button' id='addTag' name='addTag' buttonIcon='bookmark-plus' size='' />
											</@inputGroupItem>
										</@inputGroup>
									</@formGroup>
									<@listGroup id='tag-list'>
										...dynamic tags...
									</@listGroup>
								</@boxBody>
							</@box>
							<@box>
								<@boxHeader title='#i18n{plugin.modify_item.labelAttachments}' boxTools=true>
									<@button title="#i18n{plugin.modify_item.labelAddFile}" id='btn-add-files' color='outline-primary' buttonIcon='plus' size='xs' />
								</@boxHeader>
								<@boxBody>
									<@input class='visually-hidden' name='attachment' id='attachment' type='file' />
									<@div class="resources">
										<@listGroup id='content-list'>
											...existing files...
										</@listGroup>
									</@div>
								</@boxBody>
							</@box>
						</@offcanvas>
					</@columns>
				</@row>
			</@pageHeader>
			<@messages errors=errors />
			<@formGroup labelFor='title' labelKey='#i18n{plugin.create_item.labelTitle}' hideLabel=['all'] rows=2>
				<@input name='title' id='title' value='${item.title!?trim}' class='visually-hidden' />
				<@div id='div_title' class='content-head font-bold main-color lutece-charcounter' params='data-lutece-counter-max="75" contenteditable="true"'>${item.title!?trim}</@div>
			</@formGroup>
			<@formGroup labelFor='description' labelKey='#i18n{plugin.create_item.labelDescription}' hideLabel=['all'] rows=2>
				<@input name='description' id='description' value='${item.description!}' class='visually-hidden' />
				<@div id='div_description' class='content-desc lutece-charcounter' params='data-lutece-counter-max="300" contenteditable="true"'>${item.description!}</@div>
			</@formGroup>
			<@formGroup labelFor='html_content' labelKey='#i18n{plugin.create_item.labelContent}' hideLabel=['all'] rows=2>
				<@input type='textarea' name='html_content' id='html_content' value='${item.htmlContent!}' class='visually-hidden' />
				<@div id='div_html_content' class='content-body' params='contenteditable="true"'>${item.htmlContent!}</@div>
				<@button class='my-3 me-1 action' type='submit' size='' buttonIcon='check me-2' title='#i18n{plugin.modify_item.labelSave}' id='action_save_bottom' name='action_save' hideTitle=['xs','sm'] />
			</@formGroup>
		</@tform>
	</@pageColumn>
</@pageContainer>
```

### Embedded panel / fragment (tab content, without page structure)

Template included in a tab or a parent page. No `@pageContainer` / `@pageColumn` / `@pageHeader`. Each logical section is a `@box` with `@boxHeader boxTools=true` for the actions.

```freemarker
<@box>
	<@boxHeader title='#i18n{plugin.panel.titleSection1}' boxTools=true>
		<@tform action='jsp/admin/plugins/myplugin/DoAction.jsp' method='post'>
			<@button type='submit' color='primary' buttonIcon='sync' title='#i18n{plugin.panel.buttonAction}' hideTitle=['xs','sm','md'] size='' />
		</@tform>
	</@boxHeader>
	<@boxBody>
		<@p>#i18n{plugin.panel.explainSection1}</@p>
		<#if feature_enabled>
			<@p><@tag color='success' tagIcon='check-circle'>#i18n{portal.util.labelEnabled}</@tag> #i18n{plugin.panel.labelEnabled}</@p>
		<#else>
			<@p><@tag color='danger' tagIcon='times-circle'>#i18n{portal.util.labelDisabled}</@tag> #i18n{plugin.panel.labelDisabled}</@p>
		</#if>
	</@boxBody>
</@box>
<@box>
	<@boxHeader title='#i18n{plugin.panel.titleSection2}' boxTools=true>
		<@tform method='post' action='jsp/admin/plugins/myplugin/DoToggle.jsp'>
			<@input type='hidden' name='toggle' value='feature_key' />
			<#if feature_enabled>
				<@button type='submit' color='danger' buttonIcon='stop' title='#i18n{plugin.panel.buttonDisable}' hideTitle=['xs','sm','md'] size='' />
			<#else>
				<@button type='submit' color='success' buttonIcon='play' title='#i18n{plugin.panel.buttonEnable}' hideTitle=['xs','sm','md'] size='' />
			</#if>
		</@tform>
	</@boxHeader>
	<@boxBody>
		<@p>#i18n{plugin.panel.explainSection2}</@p>
		<@alert color='warning' iconTitle='exclamation-circle fa-2x'>
			#i18n{plugin.panel.warningMessage}
		</@alert>
	</@boxBody>
</@box>
```
