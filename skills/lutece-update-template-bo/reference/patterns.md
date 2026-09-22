# BO templates — situational patterns

Patterns for cases you meet only in some templates. The rules that apply to every
template are in SKILL.md.

## Contents
- @manageFeature - Bulk actions
- @manageFeature - Simplified bulk actions (single action)
- Actions dropdown in lists (manageFeature, adminDashboardWidget)
- @pageHeader - Search in a modal
- @pageHeader - Multi-filter search (text, date, selection)
- @pageHeader - Direct action buttons (Import, Export, etc.)
- @pageHeader - Order of the header actions
- @pageHeader - Editor toolbar (editor pattern)
- Modals and links

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
- Two containers work: `<@button dropdownMenu=true>` is the native Bootstrap 5 form (`data-bs-toggle`, items wrapped in `<ul class="dropdown-menu">`, so each item is a `<@li>` holding a `<@link>`; forms `manage_forms.html`); `<@aButton dropdownMenu=true>` emits Bootstrap 4 `data-toggle="dropdown"` that `webapp/themes/admin/tabler/js/admin.js` shims (core `admin/user/manage_users.html`). The pattern below uses `@aButton`; with `@button`, wrap each `@link` in `<@li>`
- Convert each action `<@aButton>` into a `<@link>` with `class='dropdown-item'`
- A selection checkbox in a row: `<@checkBox orientation='switch' labelKey=<entity label> labelClass='visually-hidden' />`; `checkBox.ftl` copies `params` on both the `<label>` and the `<input>`, so `params='aria-label="..."'` would be emitted twice
- A hierarchy of entities (parents and children in one list): one flat `<@manageFeature>`, each item showing its depth with an indent class on the first `<@manageFeatureItemColumn>` (`class='ps-3'`, `'ps-5'`...), never a `<@table>` or a `<@manageFeature>` nested in an item
- Reorder arrows (up, down, in, out) are not actions for the dropdown: keep them visible in a `<@btnGroup size='sm' ariaLabel='#i18n{portal.util.labelActions}'>`, the dropdown takes modify, copy, export and, last with `text-danger`, delete
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

### @pageHeader - Search in a modal
- When the list contains more than one element, offer a search button in the `<@pageHeader>` that opens a `<@modal>`
- Place the `<@modal>` right after the `<@pageHeader>`, not inside it
- Use `method='get'` on the search `<@tform>`: the search parameters appear in the URL, which allows bookmarking/sharing/back navigation
- The submit button sits in `<@modalFooter>` and targets the form with `formId`
- Minimal pattern (simple text search):
  ```freemarker
  <@pageHeader title='#i18n{...title}'>
      <#if list?has_content && list?size gt 1>
          <@button type='button' title='#i18n{portal.util.labelSearch}' buttonIcon='search' class='me-1' params='data-bs-toggle="modal" data-bs-target="#searchModal"' />
      </#if>
  </@pageHeader>
  <#if list?has_content && list?size gt 1>
      <@modal id='searchModal'>
          <@modalHeader modalTitle='#i18n{portal.util.labelSearch}' />
          <@modalBody>
              <@tform id='form-search' method='get' action='jsp/admin/plugins/.../ManageXxx.jsp'>
                  <@formGroup labelFor='search_text' labelKey='#i18n{portal.util.labelSearch}'>
                      <@input type='text' id='search_text' name='search_text' value='${search_text!}' />
                  </@formGroup>
              </@tform>
          </@modalBody>
          <@modalFooter>
              <@button type='submit' formId='form-search' buttonIcon='search' title='#i18n{portal.util.labelSearch}' color='primary' />
          </@modalFooter>
      </@modal>
  </#if>
  ```

### @pageHeader - Multi-filter search (text, date, selection)
- For a search form with several criteria, use one `<@formGroup>` per field, one field per row
- Standard input types: `type='text'` for the name, `type='date'` for a date, `<@select>` for a status/category
- Add a **Reset** button in `color='light'` next to the Search button `color='primary'` — the back-end clears the search values when `search_reset=1`
- **Always** reinject the current values into the inputs via `value='${search_xxx!}'` so the form re-displays with the active filters after submission
- Pattern (the header button is the one of the previous section, with `data-bs-target="#item-search"`):
  ```freemarker
  <@modal id='item-search'>
      <@modalHeader modalTitle='#i18n{portal.util.labelSearch}' />
      <@modalBody>
          <@tform id='form-item-search' method='get' action='jsp/admin/plugins/.../ManageItems.jsp'>
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
          </@tform>
      </@modalBody>
      <@modalFooter>
          <@button type='submit' formId='form-item-search' name='search_reset' value='1' buttonIcon='x' title='#i18n{portal.util.labelReset}' color='light' />
          <@button type='submit' formId='form-item-search' buttonIcon='search' title='#i18n{portal.util.labelSearch}' color='primary' />
      </@modalFooter>
  </@modal>
  ```

### @pageHeader - Direct action buttons (Import, Export, etc.)
- Some actions triggered from the header do not require a form to fill in (importing a file, Export, Clean subscribers, etc.): the click directly submits a hidden form
- Use `<@tform type='inline'>` with an `<@input type='hidden'>` for the identifier, and a single `<@button type='submit'>` — **no modal**. This single-button form is the only `type='inline'` allowed
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
- Place these buttons **after** Properties/Search/Create — they are secondary actions
- Destructive actions like "Import+Delete" (replace the whole list) use `color='danger'` but remain a direct button

### @pageHeader - Order of the header actions
When the `<@pageHeader>` holds several actions (configuration, search, creation), order them from **left to right**:
1. **Configuration / Properties** (`buttonIcon='cog'`, `color=''`) — a link to the properties page, optional
2. **Search / Filter** (`buttonIcon='search'`, `color=''`) — opens the search modal, conditional on `list?size gt 1`
3. **Creation** (`buttonIcon='plus'`, `color='primary'`) — a link to the creation page, always last (on the right)

The primary button (creation) stays visually the rightmost. The secondary buttons use `class='me-1'` for spacing.

```freemarker
<@pageHeader title='#i18n{...title}'>
    <#if right_manage_properties?? && right_manage_properties>
        <@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=manageProperties' title='...' buttonIcon='cog' color='' class='me-1' />
    </#if>
    <#if list?has_content && list?size gt 1>
        <@button type='button' title='#i18n{portal.util.labelSearch}' buttonIcon='search' class='me-1' params='data-bs-toggle="modal" data-bs-target="#item-search"' />
    </#if>
    <#if creation_allowed>
        <@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp?view=createItem' title='...' buttonIcon='plus' color='primary' />
    </#if>
</@pageHeader>
<#if list?has_content && list?size gt 1>
    <@modal id='item-search'>...</@modal>
</#if>
```

### @pageHeader - Editor toolbar (editor pattern)
- For editor pages (create/modify with rich content), the `<@tform>` wraps the `<@pageHeader>` and the content
- The toolbar is in the `<@pageHeader>` via `<@row>` + `<@columns class='d-flex justify-content-end align-items-center'>`
- The additional properties (tags, files, URL, comment) are in a `<@modal>` placed inside the `<@tform>`, after the `<@pageHeader>`, so its fields are submitted with the form; a toolbar button opens it
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
                          <@button type='button' class='me-1' buttonIcon='cog me-2' title='#i18n{...properties}' hideTitle=['xs','sm', 'md', 'lg'] params='data-bs-toggle="modal" data-bs-target="#properties"' />
                      </@columns>
                  </@row>
              </@pageHeader>
              <@modal id='properties' size='lg'>
                  <@modalHeader modalTitle='#i18n{...properties}' />
                  <@modalBody>
                      <@box>...</@box>
                  </@modalBody>
              </@modal>
              <@messages errors=errors />
              ...editable fields...
              <@button class='my-3 action' type='submit' buttonIcon='check me-2' title='#i18n{...save}' />
          </@tform>
      </@pageColumn>
  </@pageContainer>
  ```

## Modals and links

No `<@offcanvas>` (blocking: `verify-migration.sh` TM10, scanner TD48). Two replacements:

- **Content written in the page** (search, filters, a short creation form, editor properties) → a `<@modal>` with
  `<@modalHeader>`, `<@modalBody>`, `<@modalFooter>`, opened by
  `<@button type='button' params='data-bs-toggle="modal" data-bs-target="#id"' />`. The `id` is unique per page,
  suffixed with the entity identifier inside a list. A collapse button (`buttonTargetId='#...'`) that shows a
  search form becomes the same search modal.
- **Another page** (a create, modify, manage or properties screen) → a plain link to that page:
  `<@aButton href='…' />` in a header or an actions column, `<@link class='dropdown-item' href='…' label='…' />`
  inside a dropdown. The destination is a full page (see below).

```freemarker
<@manageFeatureItemColumn align='end'>
    <@aButton href='jsp/admin/.../Modify.jsp?key=${item.key}' title='#i18n{portal.util.labelModify}' buttonIcon='edit' color='' class='me-1' hideTitle=['xs','sm'] />
    <@aButton href='jsp/admin/.../ManageUsers.jsp?key=${item.key}' title='#i18n{...labelManageUsers}' buttonIcon='users' color='' class='me-1' hideTitle=['xs','sm'] />
    <@aButton href='jsp/admin/.../Remove.jsp?key=${item.key}' title='#i18n{...labelRemove}' hideTitle=['all'] buttonIcon='trash' color='danger' />
</@manageFeatureItemColumn>
```

## Icon vocabulary

Every name below exists in `webapp/themes/shared/css/tabler-icons.min.css` of the assembled webapp; check a new one
there before using it, because an unknown name renders an empty glyph without an error.

| Action | Icon |
|---|---|
| save | `device-floppy` |
| create | `plus` |
| modify | `edit` (button), `pencil` (inline) |
| delete | `trash` |
| back | `arrow-left` |
| cancel | `x` |
| search | `search` |
| import / export | `upload` / `download` |
| actions menu | `dots-vertical` |
| move | `chevron-up`, `chevron-down`, `chevron-left`, `chevron-right` |
| reorder handle | `arrows-vertical` |
| status | `info-circle`, `circle-check`, `circle-x` |
| external link | `external-link` |
| empty state | contextual: `message-off`, `folder-off`, `tags-off`, `archive-off`, `help-hexagon`, `search-off`, default `inbox-off` |

`components/icon/icon.ftl` aliases 40 FontAwesome names (`times`, `cog`, `envelope`, `remove`…), so those still
render. These do **not**, and are the ones found in the wild: `close`, `save`, `arrows-v`, `circle-info`,
`check-circle`, `times-circle`, `exclamation-triangle`, `user-times`, `external-link-alt`, `minus-square`, `disk`.

## @empty - The subtitle is never empty

With no `subtitle`, the macro prints the generic `#i18n{portal.util.message.emptySubTitle}` ("Add a first
element"). Pass a contextual subtitle, or `subtitle=' '` to show none.

## Recursive trees

A tree of entities is `<@div id='tree' class='lutece-tree'>` > `<@ul>` > `<@li class='lutece-tree-node'
params='data-tree-icon="..."'>`, driven by `webapp/themes/shared/modules/luteceTree.js`. Select the current node
with `selectTreeNode('#node-${id}')`, and guard the script with `if (tree)` so a page without the tree does not
throw.

## A create or modify screen is a full page

It keeps `@pageContainer > @pageColumn > @pageHeader` and a back link to the page it comes from:

```freemarker
<@pageHeader title='#i18n{...modifyTitle}'>
    <@aButton href='jsp/admin/plugins/myplugin/ManageItems.jsp' buttonIcon='arrow-left' title='#i18n{portal.util.labelBack}' color='' />
</@pageHeader>
```

## The destructive action of a detail box

Put it in `<@boxFooter>`, not in the body.

## Models to copy

forms `admin/plugins/forms/manage_forms.html`, core `admin/role/manage_roles.html` and `admin/user/manage_users.html`
(actions dropdown). The core is not flawless: `admin/rbac/manage_roles.html` wraps `@empty` in `@box` and tests
`?size gt 1`, so a single role shows the empty state. The rule above wins over the model.
