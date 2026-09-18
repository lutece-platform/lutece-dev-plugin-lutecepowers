---
name: lutece-update-template-bo
description: "Converts a Lutece Back Office (admin) template to the BO FreeMarker macros of lutece-core (Tabler theme). Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the house rules that are not readable from the macro files: manageFeature versus table, the mandatory empty state, the page hierarchy, the offcanvas navigation rule, and the e-mail templates that must never be converted. Takes the template path as argument. Triggers on 'migrer un template BO', 'convertir un template admin', 'macros BO', 'thème tabler', 'update back office template'."
allowed-tools: Bash(ls *) Bash(grep *) Bash(sed *) Bash(find *)
---

# Updating a Lutece BO template

Replace raw HTML with the admin FreeMarker macros. **This skill does not list the macros** — the core
sources do, and they are the only current version. Read them.

## Step 0 — Discover the macros

Root: `~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler/`
(reference clones are synced at session start; see `using-lutecepowers`).

One file per macro, the filename is the macro name, grouped by domain. Start here:

```bash
cd ~/.lutece-references/lutece-core/webapp/WEB-INF/templates/admin/themes/tabler
ls -d */*/                                     # every domain: components, forms, layout, elements, pages, utilities...
grep -rh '^<#macro' components/table/          # every signature of one domain, with all its parameters
grep -rl '^<#macro  *offcanvas\b' .            # which file defines one macro
sed -n '1,25p' components/box/box.ftl          # its documented parameters and a snippet
```

Every `.ftl` opens with a header block — `Macro:`, `Description:`, `Parameters:` with type and whether
optional. That header is the contract.

**Read a macro's file before using it for the first time in a session.** A wrong parameter name renders
an empty element without raising an error.

If the clone is missing, the theme also ships in any assembled site under
`target/lutece/WEB-INF/templates/admin/themes/tabler/`.

## Steps

1. Read the target template.
2. For each block of raw HTML, find the domain that covers it (step 0) and read the signatures.
3. Rewrite using only macros.
4. Do not touch the i18n files unless asked.

## Additional resources

- Situational patterns — bulk actions, search and filter headers, editor toolbars, the four offcanvas
  placements: [reference/patterns.md](reference/patterns.md)
- Complete page examples to copy from: [reference/examples.md](reference/examples.md)
- List layout, messages and i18n keys that exist: `rules/template-back-office.md`

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
- **Editor page exception**: the `<@tform>` may wrap the `<@pageHeader>` and the content (see the editor toolbar pattern in [reference/patterns.md](reference/patterns.md))
- **Embedded panels/fragments exception**: templates loaded as tab content or fragments included in a parent page do **not** use `<@pageContainer>` / `<@pageColumn>` / `<@pageHeader>`. They structure their content directly with `<@box>` / `<@boxHeader>` / `<@boxBody>`. Each logical section is a separate `<@box>` with a title in `<@boxHeader>` and the action buttons via `boxTools=true`.

### When to use @table vs @manageFeature
Rule: `rules/template-back-office.md` § List Layout. `@manageFeature` for entity lists with CRUD actions (core and forms manage pages), `@table` for tabular data (several data columns, reports, child-entity tables). Convert an existing `@table` to `@manageFeature` only when its rows are entities with edit/delete actions.

### @manageFeature - Entity lists
- Each item is a card with flexible columns
- Main column (name/title): `<@manageFeatureItemColumn auto=true flex=false>` (with `flex=false` for multi-line content)
- Secondary columns with label: `<@manageFeatureItemColumn auto=true flex=false valign='top'>` with a `<@p class='fw-bold fs-3'>` as column title
- Actions column: `<@manageFeatureItemColumn align='end'>` (right-aligned)
- Checkbox column (selection): `<@manageFeatureItemColumn auto=true>` with `<@checkBox orientation='switch' />`
- No need for `<@box>` / `<@boxBody>` around it, `@manageFeatureItem` generates its own cards

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

### @tform - Forms
- `type='horizontal'` for standard forms (label on the left, input on the right)
- `type='inline'` for inline forms (action buttons)
- `boxed=true` when the form replaces a `<@box>` wrapper (see convention above)
- Use `<@formGroup>` to group label + input with `labelKey`, `helpKey`, `mandatory`

### @messages - Info/error messages
- Place `<@messages infos=infos![] errors=errors![] warnings=warnings![] />` at the top of the main content (after `<@pageHeader>`); in the editor pattern the errors call goes in the relevant form
- `![]` is mandatory: the variables are absent until a message is added (`rules/template-back-office.md` § Messages)
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
- Reuse existing `portal.util.*` keys; the list of existing keys and of the ones that do NOT exist (`labelActive`, `labelInactive`, `labelSave`, `labelAdd`): `rules/template-back-office.md` § i18n

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
- Do not use `<@table>` for an entity list with CRUD actions → convert to `<@manageFeature>`; keep `@table` for tabular data (`rules/template-back-office.md` § List Layout)
- Do not put the creation form in a separate column → prefer an `<@offcanvas>` in the `<@pageHeader>`
- Do not use `<@aButton>` to navigate to a creation or modification page → use `<@offcanvas>` with `useIframe=true` instead
- Do not duplicate `<@messages>` (a single call per message type)
- Do not wrap a `<@tform>` in a `<@box>` when the box only serves to contain the form → use `boxed=true`
- NEVER iterate a list (`<#list>`) without first testing whether it is non-empty (`?has_content`) and displaying a `<@empty>` otherwise

