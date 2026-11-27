# Step 1 — Build and configuration

`pom.xml`, `beans.xml`, the Spring context files, `webapp/WEB-INF/plugins/*.xml`, `webapp/WEB-INF/web.xml`, `src/sql`,
`*.properties`.

`lutece-check.sh` reports every POM, descriptor, web.xml, SQL and i18n rule a script can see (PM*, WB*, ST01, SQ*,
I18N*), each finding with what to do: the Liquibase header of each SQL script (SQ01, `rules/sql-liquibase.md`), the
Jakarta namespace of `web.xml` (WB01).

## pom.xml

- Parent: the latest released `lutece-global-pom` 8.x (PM06); `lutece-core`: an open range, `[8.0.0,)`, or `[X,)`
  when the code uses an API that core X brought; never a pinned version, the site or its BOM chooses it (PM14);
  version: the next major from a pre-v8 start (PV02), the same in the descriptor (PV01), `min-core-version` 8.0.0
  (WB04). What each parent manages: `rules/dependency-convergence.md`.
- Lutece dependencies: the `v8Version` of each dependency in `.migration/scan.json`, else the version of
  `~/.lutece-references/<artifactId>/pom.xml`. `check-v8-floor.sh` proves the build resolves the supported core.
- A bound's lower end must exist in the repository: most v8 plugins are published as SNAPSHOT only, and Maven orders
  `4.0.0-SNAPSHOT` before `4.0.0`, so `[4.0.0,)` finds nothing. Look before writing it:
  `curl -sf https://dev.lutece.paris.fr/nexus/repository/lutece_snapshots_repository/fr/paris/lutece/plugins/<artifact>/maven-metadata.xml | grep -o '<version>[^<]*' | tail -5`.
- `library-lutece-unit-testing` (test scope) only when `src/test/` exists.
- A library that should not carry the whole core depends on `library-core-utils` instead of `lutece-core`.
- JPA (`summary.persistence.hasJpa`): `patterns/persistence-patterns.md` §2–§4.
- XSL: a portlet is ported to HTML in step 2, never kept on `plugin-xmltransformer`; any other use of the XSL services
  declares `plugin-xmltransformer` (`patterns/core-8x-moves.md`).
- A class that stops resolving and belongs to no Jakarta package may come from a library the v7 core carried and the
  v8 core dropped (`library-jmx-api`): `git -C ~/.lutece-references/lutece-core show origin/develop7.x:pom.xml | grep -A3 "<artifactId>library-"`.

## Spring context and beans.xml

- `beans.xml`: `patterns/cdi-patterns.md` §1.
- Catalog the context before step 2 reads it: `bash ${LUTECEPOWERS_ROOT}/tools/extract-context-beans.sh . .migration/context-beans.json`.
  Delete every Spring context file (the `*_context.xml` and the files they import; SP03 lists them) at the end of
  step 2, once no Java file needs the catalog.
- Beans with `needsProducer: true` and property values: one `pluginName.bean.propertyName=value` entry each, read by
  `@ConfigProperty` in the producer.

## Plugin descriptor

- Remove `<application-class>` (WB02): v8 discovers XPages through CDI.
- Keep `<class>` as it is: a custom `PluginDefaultImplementation` subclass may register resource providers in `init()`.
- Keep `<application-id>`; `<version>` follows the pom.

## Properties that behave differently in v8

- A key shipped with an empty value now resolves to `null` (MicroProfile Config), where v7 returned `""`. For each
  `AppPropertiesService.getProperty( … )` of such a key, decide what the plugin does without it (skip the feature or
  supply a default); the symptom is otherwise a FreeMarker "null or missing" far away, a 500 on every page when the
  template is a page include.
- A plugin implementing `ILocalizedSitePropertiesGroup` needs, per property, `site_property.<key>.group=<group>` and
  `site_property.<group>.group.title=<heading>` in its default bundle, or the v8 back office shows an empty tab. Model:
  the core's `site_messages.properties`.

## i18n bundles

- `tools/fix-i18n-bundles.py` (run through `tools/py.sh`, like every toolkit Python script) repairs the I18N findings it names, `--drop <file>` removes dead keys in every language,
  and `--add <file>` sets keys (`<bundle>[_<lang>]:<key>=<value>`, UTF-8): it writes `\uXXXX` escapes and keeps each
  file's line endings. Add or change bundle keys through it, not by hand or with an ad hoc script.
