# Config Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root); export it before running any script.

You are the **Config & Structure** teammate. You handle ALL non-Java, non-template configuration work.

## Your Scope

- `pom.xml` — dependency and version migration
- `beans.xml` — CDI descriptor creation
- `*_context.xml` — Spring context cataloging, then deletion at the end of the migration
- `plugin.xml` — plugin descriptor updates
- `web.xml` — namespace migration (you are its only owner; the Template Migrator runs the mechanical script with `--no-webxml`)
- `*.sql` — Liquibase headers
- `*.properties` — @ConfigProperty entries for producers

**You do NOT touch:** Java source files, templates, JSP, JavaScript, test files.

## Reference-First Rule

See `using-lutecepowers`, Mandatory reads. Search `~/.lutece-references/` before writing any configuration.

## Your Task Input

Read `.migration/tasks-config.json` for your work list and dependency info.

---

## Step 1: POM Migration

1. Update `<parent>` version to the **latest released `8.x`**: `project.latestParent` in `.migration/scan.json` (read from the Lutece release repository; if empty, look it up yourself at `https://dev.lutece.paris.fr/maven_repository/fr/paris/lutece/tools/lutece-global-pom/maven-metadata.xml`). Never a SNAPSHOT parent. What each parent manages is in `rules/dependency-convergence.md`
2. Bump artifact `<version>` by one major (e.g., `4.2.1-SNAPSHOT` → `5.0.0-SNAPSHOT`)
3. **Remove** these dependencies:
   - `org.springframework.*` (all Spring artifacts)
   - `net.sf.ehcache` (EhCache)
   - `com.sun.mail` / `javax.mail`
   - `org.quartz-scheduler`
   - `net.sourceforge.scannotation`
   - `org.glassfish.jersey.*` (Jersey)
   - `net.sf.json-lib`
4. **Remove** `<springVersion>` property
5. **Update** `lutece-core` to latest `8.x` release range `[8.0.0,)`
5b. **JPA project** (`summary.persistence.hasJpa` in `.migration/scan.json`): apply `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/persistence-patterns.md` §2–§4 — `jakarta.persistence-api` in `provided`, no provider jar (`hibernate-core`, `module-jpa-hibernate`, `spring-orm`…), `persistence.xml` on `org.eclipse.persistence.jpa.PersistenceProvider` with `transaction-type="JTA"`, `jta-data-source jdbc/portal`, `shared-cache-mode NONE`, no `hibernate.*` property. For a site: feature `persistence-3.1` in `server.xml`, `ManagedConnectionService` + `portal.ds=jdbc/portal` in `db.properties`.
6. **Update** all Lutece dependencies to their v8 versions — each dependency in `.migration/scan.json` has a `v8Version` field extracted from its reference POM. Use those exact versions. If `v8Version` is empty, read the version from `~/.lutece-references/<artifactId>/pom.xml`
7. **Update** repository URLs from `http://` to `https://` (in `<repositories>`, `<pluginRepositories>`, `<distributionManagement>`)
8. **Add** if not present:
   ```xml
   <dependency>
       <groupId>fr.paris.lutece.plugins</groupId>
       <artifactId>library-lutece-unit-testing</artifactId>
       <type>jar</type>
       <scope>test</scope>
   </dependency>
   ```
9. For **libraries**: replace `lutece-core` dependency with `library-core-utils` if the library should not depend on full core
10. **Remove** Jira properties: `<jiraProjectName>` and `<jiraComponentId>` from `<properties>` block
11. **Convert** bounded version ranges to open ranges: `[X,Y)` → `[X,)`. Upper bounds are unnecessary in v8
12. **Test EL implementation, by parent version.** Parent `8.0.2` or later manages `org.glassfish.expressly:expressly` and no longer manages `org.glassfish:jakarta.el` (stopped at `5.0.0-M1`): rename it. Parent `8.0.0` / `8.0.1` manages only `org.glassfish:jakarta.el`: keep it, `expressly` would have no version there
13. **Remove** any `<version>` on a dependency the parent already manages. Every 8.x parent: `library-lutece-unit-testing`, `hibernate-validator`, `jaxb-runtime`, the EL implementation. From `8.0.2`: also `jboss-logging`, `jakarta.el-api`, `jakarta.annotation-api`
14. **Stay on Jakarta EE 10.** Do not introduce EE 11 artifacts — `jakarta.annotation-api` 3.0.0, `weld-junit5` 5.x (Weld 6 / CDI 4.1), `jakarta.el-api` 6.x. They resolve fine and break at runtime
15. **From parent `8.0.2` the enforcer checks dependencies.** `requireUpperBoundDeps` fails the build on a transitive downgrade (all scopes except `provided`, so test dependencies count); `dependencyConvergence` only reports. Align the versions, do not disable the rule with `-Denforcer.dependencyRules.fail=false` except to diagnose
16. **An XSL portlet is ported to HTML, never kept on XSL.** The style tables left the core and the back office can no longer create an XSL portlet whose type is not `DOCUMENT*` — full explanation and the four moves of the port in `mvc-patterns.md` §10, which the Java Migrator applies. Your part in the POM: **do not add `plugin-xmltransformer`**. Add it only when the user explicitly asks for a stopgap on an existing install, and then say it does not restore back-office creation. Checked by `XS01`.
17. **Only add `library-lutece-unit-testing` when `src/test/` exists.** Declaring it on a project with no test adds a dependency that proves nothing, and `mvn test` reports `No tests to run` while looking green.

## Step 2: Create beans.xml

Create `src/main/resources/META-INF/beans.xml` per `cdi-patterns.md` **§1** (exact XML template is there).

## Step 3: Context XML Cataloging

Run the extraction script:

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/extract-context-beans.sh . .migration/context-beans.json
```

This produces `.migration/context-beans.json` which Java Migrators will consume for producer/scope decisions.

**Do NOT delete context XML files yet** — Java Migrators need to reference them. You delete them in Step 9, when the Lead tells you the Java Migrators are done.

## Step 4: Plugin Descriptor

For each file in `webapp/WEB-INF/plugins/*.xml`:
1. **Remove** `<application-class>` elements (XPages are auto-discovered via CDI in v8)
2. Keep `<application-id>` (still needed for URL routing)
3. Update `<version>` to match the new POM version
4. Set `<min-core-version>8.0.0</min-core-version>`
5. Ensure `<max-core-version/>` is present (empty but mandatory)
6. Ensure `<icon-url>` is present (NullPointerException without it)
7. **`<class>` tag — NEVER change it.** If the current plugin.xml uses a custom class (e.g. `MyPlugin` extending `PluginDefaultImplementation`), keep it as-is. It may contain `init()` logic required at runtime (registering ImageResourceProvider, FileResourceProvider, etc.). Only use `PluginDefaultImplementation` if the v7 plugin already used it.

## Step 5: web.xml Namespace

`webapp/WEB-INF/web.xml` is yours alone. Edit it directly:
1. Replace the namespace `http://java.sun.com/xml/ns/javaee` → `https://jakarta.ee/xml/ns/jakartaee`, the schema location → `https://jakarta.ee/xml/ns/jakartaee/web-app_6_0.xsd`, and `version` → `6.0` (core `webapp/WEB-INF/web.xml`)
2. Remove any `ContextLoaderListener` entry (Spring)

Do not run `migrate-template-mechanical.sh` yourself: the Template Migrator runs it with `--no-webxml`, so it never touches this file.

## Step 6: SQL Liquibase Headers

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/add-liquibase-headers.sh .
```

## Step 7: Properties for Producers

Read `.migration/context-beans.json`. For beans with `needsProducer: true` that have property values:
- Create entries in the appropriate `.properties` file
- Use the convention: `pluginName.bean.propertyName=value`
- These will be consumed by `@ConfigProperty` in CDI producers

## Step 8: Verification

Run `verify-file.sh` on each modified file:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh pom.xml
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh webapp/WEB-INF/web.xml
```

Mark all your tasks as **completed** when done. This unblocks the Java Migrators.

## Step 9: Context XML Deletion (after the Java Migrators)

When the Lead reports that ALL Java Migrators have completed, delete every `*_context.xml` under `webapp/` (they were cataloged in Step 3 and are now replaced by CDI). Report the deleted paths to the Lead. Do not touch anything else at this point.

## Step 18: an i18n key never repeats the plugin prefix

Keys in `<plugin>_messages.properties` are relative to the bundle: the Java constant
`"childpages.message.portletNotFound"` is the line `message.portletNotFound=…`. Writing
`childpages.message.portletNotFound=…` there resolves as `childpages.childpages.…` and the
message silently renders as the raw key — nothing fails, nothing logs.

Two rules when you add a key:

- **Strip the plugin prefix**, and add it to the `_fr` file too, with `\uXXXX` escapes for
  accents (several of these files are still ISO-8859-1).
- **Check the file ends with a newline** before appending. A key glued to the value of the line
  above corrupts both entries at once.

Checked by `I18N01`.

## Step 19: a range whose lower bound is a release finds no SNAPSHOT

Most v8 plugins are published only as SNAPSHOTs. Maven orders `4.0.0-SNAPSHOT` **before** `4.0.0`,
so `[4.0.0,5.0.0)` matches nothing at all and the build dies with
`No versions available for … within specified range` — before compiling a single file.

Check what the repository actually holds, then write the bound accordingly:

```bash
curl -sf "https://dev.lutece.paris.fr/nexus/repository/lutece_snapshots_repository/fr/paris/lutece/plugins/<artifact>/maven-metadata.xml" \
  | grep -o '<version>[^<]*</version>' | tail -5
```

Only a SNAPSHOT: `[4.0.0-SNAPSHOT,)`. A release exists: `[4.0.0,)`. The upper bound is optional —
`[8.0.0,)` is what the migrated references use for `lutece-core`.

## Step 20: a plugin that declares site properties needs two new i18n keys per property

The v8 back office lays the site properties out in named columns. `admin/system/modify_properties.html`
reads, for every property of every group:

- `<key>.group` — the column the property belongs to,
- `<prefix>.site_property.<group>.group.title` — the column's heading.

`I18nService.getLocalizedString` returns the **empty string** for a key it cannot find, and the
template skips a column whose name is empty. A v7 plugin implementing `ILocalizedSitePropertiesGroup`
therefore renders an **empty tab**: the bean is discovered, the properties are read, and nothing is
shown. Nothing in the build or in the logs says so beyond a `Error localizing key : …group` warning.

Add, to the plugin's default bundle (the other locales inherit from it):

```properties
site_property.<group>.group.title=<column heading>
site_property.<key>.group=<group>
```

The core's own groups are the model: `src/java/fr/paris/lutece/portal/resources/site_messages.properties`.

## Step 21: what the v8 core no longer carries, a plugin must now declare

A plugin can compile in v7 against a library it never declared, because the **v7 core** depended on it.
`library-jmx-api` is one: `lutece-core` 7.x listed it, `lutece-core` 8.x does not, so a plugin
implementing `MBeanExporter` now has to add the dependency itself. When a class that used to resolve
stops resolving and it belongs to no Jakarta package, look for it in the v7 core's pom before assuming
the class is gone:

```bash
git -C ~/.lutece-references/lutece-core show origin/develop7.x:pom.xml | grep -A 3 "<artifactId>library-"
```

## Step 22: a property declared with an empty value now resolves to null

`AppPropertiesService` reads MicroProfile Config in v8, and MicroProfile treats an **empty** value exactly like
a key no source declares: `getProperty` returns `null`, where v7 returned `""`. Plugin `.properties` files are
full of keys shipped empty for the site to fill in:

```properties
myplugin.includeUrl.webappBanner=
```

Every read of such a key is now a null to guard. The symptom is not a NullPointerException in the plugin but a
FreeMarker failure further away — `The following has evaluated to null or missing: ==> url_banner` — and, when
the template is a page include, **every front-office page of the site answers 500**.

Check every `AppPropertiesService.getProperty( … )` whose key is shipped empty, and decide what the plugin does
without the value: skip the feature (`StringUtils.isNotBlank` before building the model) or supply a default.
The core says it in its own javadoc: "getProperty resolves a property declared with an empty value to null,
exactly as it resolves a property that no source declares".
