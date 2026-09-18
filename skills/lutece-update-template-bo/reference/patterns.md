# BO templates — situational patterns

Patterns for cases you meet only in some templates. The rules that apply to every
template are in SKILL.md.

## Contents
- @manageFeature - Bulk actions
- @manageFeature - Simplified bulk actions (single action)
- Actions dropdown in lists (manageFeature, adminDashboardWidget)
- @pageHeader - Search in an offcanvas
- @pageHeader - Multi-filter search (text, date, selection)
- @pageHeader - Direct action buttons (Import, Export, etc.)
- @pageHeader - Recommended order of offcanvas
- @pageHeader - Editor toolbar (editor pattern)
- @offcanvas - Side panels
- @offcanvas - Replacing links in a dropdown menu
- @offcanvas - Replacing action buttons in a list
- @offcanvas - Replacing a collapse button with a standard offcanvas

## Bulk actions in a list

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

## Actions dropdown

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

## Page header — search, filters, toolbars

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
                          <@option value='1' label='#i18n{portal.util.labelEnabled}' />
                          <@option value='0' label='#i18n{portal.util.labelDisabled}' />
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

## Offcanvas — the four placements

### @offcanvas - Side panels
- Used for inline editing: `<@offcanvas targetUrl="..." targetElement="..." btnIcon="edit" />`
- Used for creation forms: `<@offcanvas id="..." btnTitle="..." position="end">...</@offcanvas>`
- Used for search/filters: `<@offcanvas id="..." btnIcon="search" position="end" size="sm">...</@offcanvas>`
- Used for the properties of an editor: `<@offcanvas id="..." btnIcon="cog me-2" position="end" btnClass="me-1 rounded-end">...</@offcanvas>`
- `position='end'` for panels on the right (recommended default)
- `targetUrl` loads the content via AJAX
- `useIframe=true`: loads the content of `targetUrl` in an iframe instead of an AJAX call. This is how create/modify pages are opened from a manage page in the references (forms `manage_categories.html`, 19 uses in core and forms); it is the default for the navigation buttons converted below. Pattern:
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

