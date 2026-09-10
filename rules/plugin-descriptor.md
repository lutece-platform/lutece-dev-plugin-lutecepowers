---
description: "Lutece 8 plugin.xml constraints: structure, icon-url, core-version-dependency, admin-feature and application declaration"
paths:
  - "**/plugins/*.xml"
---

# plugin.xml — Lutece 8

## Mandatory Structure (new plugin template)

This is a template for **new plugins only**. During migration, do NOT overwrite `<class>` — see the section below.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plug-in>
    <name>myplugin</name>
    <!-- For new plugins. During migration: KEEP the existing <class> value unchanged -->
    <class>fr.paris.lutece.portal.service.plugin.PluginDefaultImplementation</class>
    <version>1.0.0-SNAPSHOT</version>
    <documentation/>
    <installation/>
    <changes/>
    <user-guide/>
    <description>myplugin.plugin.description</description>
    <provider>myplugin.plugin.provider</provider>
    <provider-url>http://lutece.paris.fr</provider-url>
    <icon-url>images/admin/skin/feature_default_icon.png</icon-url>
    <copyright>Copyright (c) <current year></copyright>
    <db-pool-required>1</db-pool-required>

    <core-version-dependency>
        <min-core-version>8.0.0</min-core-version>
        <max-core-version/>
    </core-version-dependency>
</plug-in>
```

## `<class>` Tag — PluginDefaultImplementation vs Custom Plugin Class

Most plugins use `PluginDefaultImplementation`. However, **preserve the existing custom class** when the plugin has initialization logic in `init()`:

| `<class>` value | When to use | Examples |
|---|---|---|
| `PluginDefaultImplementation` | No custom `init()` logic needed. Plugin only declares rights, XPages, daemons, services. | workflow-forms, mylutece, rest, elasticdata, asynchronousupload |
| Custom `XxxPlugin` | Plugin registers providers (ImageResourceProvider, FileResourceProvider) or runs setup logic in `init()`. | forms, genericattributes, workflow, announce |

**MIGRATION RULE: During migration to v8, NEVER replace an existing custom `XxxPlugin` class with `PluginDefaultImplementation`. If the current plugin.xml has a custom class, keep it — it likely has `init()` logic that is required at runtime (e.g. registering image/file providers via CDI).**

## Recommended Tags

- `<icon-url>` — recommended; every reference plugin declares it. An empty value falls back to the default icon (`Plugin.java`: `pluginFile.getIconUrl( ).equals( "" ) ? strDefaultIconUrl : ...`).
- `<max-core-version/>` — recommended as an empty tag; every reference plugin declares it (forms.xml, appointment.xml, asynchronousupload.xml).
- `<description>` / `<provider>` — i18n keys WITH plugin prefix (e.g. `myplugin.plugin.description`)

## Admin Feature Declaration

```xml
<admin-features>
    <admin-feature>
        <feature-id>MYPLUGIN_MANAGEMENT</feature-id>
        <feature-title>myplugin.adminFeature.manageEntities.name</feature-title>
        <feature-description>myplugin.adminFeature.manageEntities.description</feature-description>
        <feature-level>3</feature-level>
        <feature-url>jsp/admin/plugins/myplugin/ManageEntities.jsp</feature-url>
        <feature-icon-url/>
        <feature-page-order>1</feature-page-order>
        <feature-group>APPLICATIONS</feature-group>
    </admin-feature>
</admin-features>
```

`<feature-url>` is the full webapp-relative path (`jsp/admin/plugins/<plugin>/Manage….jsp`), never a bare file name — reference: forms.xml:36, appointment.xml:28.

## XPage Declaration

```xml
<applications>
    <application>
        <application-id>tasks</application-id>
    </application>
</applications>
```

No `<application-class>`: the core resolves the CDI bean named `<plugin>.xpage.<application-id>` (`XPageAppService.registerXPageApplication`). The XPage class carries `@Named("myplugin.xpage.tasks")` — see `rules/web-bean.md`. Reference: forms.xml:58-60, FormXPage.java:101-104.

## Common Errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Could not find bean named <plugin>.xpage.<id>` at startup | `@Named` value does not match `<plugin>.xpage.<application-id>` | Align the two |
| Feature not in admin menu | Missing `<admin-feature>` block | Add the declaration |
| Feature link 404 | Relative `<feature-url>` | Use the full `jsp/admin/plugins/...` path |
| i18n keys displayed raw | Prefix missing in feature-title/description | Use `pluginName.key` format |
