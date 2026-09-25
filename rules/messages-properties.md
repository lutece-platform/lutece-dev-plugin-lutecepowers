---
description: "Lutece 8 i18n constraints: no prefix in .properties, prefix in Java/templates, key naming"
---

# i18n — messages.properties Rules

## The Golden Rule

**The prefix is NEVER in messages.properties, ALWAYS in Java/templates.**

```properties
# CORRECT — in myplugin_messages.properties
adminFeature.manageEntities.name=Manage Entities
manage_entity.pageTitle=Manage Entities
message.confirmRemoveEntity=Are you sure?

# WRONG — prefix included
# myplugin.adminFeature.manageEntities.name=Manage Entities
```

## Prefix by Project Type

| Type | Prefix in Java/templates | Properties location |
|------|--------------------------|---------------------|
| **Plugin** | `pluginName.` | `resources/pluginName_messages.properties` |
| **Module** | `module.pluginName.moduleName.` | `resources/moduleName_messages.properties` |
| **Core** | `portal.<element>.` | `portal/resources/<element>_messages.properties` (one bundle per element: `users`, `site`, `theme`, `security`… 23 of them, there is no `portal_messages.properties`) |

## Key Naming

- `plugin.description` / `plugin.provider` — plugin metadata
- `adminFeature.xxx.name` / `.description` — admin menu
- `manage_xxx.pageTitle` / `.buttonAdd` / `.noData` — list pages
- `create_xxx.pageTitle` / `modify_xxx.pageTitle` — form pages
- `model.entity.xxx.attribute.yyy` — entity field labels
- `message.confirmRemoveXxx` — delete confirmation
- `message.error.*` / `message.success.*` — user messages
- `permission.resourceType.xxx.*` — RBAC labels

## A missing key is invisible, not loud

`I18nService.getLocalizedString` catches the lookup failure, logs a WARN `Error localizing key : <key>` and returns
an **empty string**. A key no bundle answers therefore shows nothing on screen: no error page, no raw key — just a
label that is not there, and a WARN line easy to miss in the log.

`check-i18n-keys.sh` resolves every `#i18n` key of a project against the bundles of the assembled webapp and
names those that answer nothing. It reads templates, `.js`, `.java`, `.xml` and `.sql`, follows a Java constant
to its literal, and sorts what it cannot settle apart: a key built from a variable, and a key whose bundle
belongs to a plugin this webapp does not carry.

## Editing a bundle

- **Both languages, always.** A key added to `x_messages.properties` and forgotten in `x_messages_fr.properties`
  falls back to the English text, which reads as a bug to a French user.
- **Follow each file's own conventions**, they differ from one bundle to the next in the same directory: some are
  CRLF and some LF, some escape accents as `\u00e9` and some carry them raw in UTF-8. A tool that rewrites a file
  in the other convention turns two added lines into a diff of the whole file.

## Common errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| The label is simply absent from the page | No bundle answers the key | Add it, or point the call at the key that already exists |
| Empty label, WARN `Error localizing key : myplugin.label.name` in the log | Prefix included in `.properties` file (`myplugin.label.name=` instead of `label.name=`) | Remove prefix — keep only `label.name=Value` |
| The label is there but a screen reader says nothing | The text sits in a `d-none` span | `display:none` leaves the accessibility tree; `visually-hidden` does not |
