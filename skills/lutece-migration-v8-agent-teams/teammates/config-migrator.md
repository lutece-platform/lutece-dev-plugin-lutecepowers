# Config Migrator — Teammate Instructions

You are the **Config & Structure** teammate. You handle ALL non-Java, non-template configuration work.

## Your Scope

- `pom.xml` — dependency and version migration
- `beans.xml` — CDI descriptor creation
- `*_context.xml` — Spring context cataloging and cleanup
- `plugin.xml` — plugin descriptor updates
- `web.xml` — namespace migration
- `*.sql` — Liquibase headers
- `*.properties` — @ConfigProperty entries for producers

**You do NOT touch:** Java source files, templates, JSP, JavaScript, test files.

## Reference-First Rule

Before writing any configuration, **search `~/.lutece-references/`** for existing examples. Reference implementations take priority over documentation.

## Your Task Input

Read `.migration/tasks-config.json` for your work list and dependency info.

---

## Step 1: POM Migration

1. Update `<parent>` version to **`8.0.2`** — the version that makes the test classpath converge (see `rules/dependency-convergence.md`). Use the release version, NOT a SNAPSHOT
2. Bump artifact `<version>` by one major (e.g., `4.2.1-SNAPSHOT` → `5.0.0-SNAPSHOT`)
3. **Remove** these dependencies:
   - `org.springframework.*` (all Spring artifacts)
   - `net.sf.ehcache` (EhCache)
   - `com.sun.mail` / `javax.mail`
   - `javax.persistence`
   - `org.quartz-scheduler`
   - `net.sourceforge.scannotation`
   - `org.glassfish.jersey.*` (Jersey)
   - `net.sf.json-lib`
4. **Remove** `<springVersion>` property
5. **Update** `lutece-core` to latest `8.x` release range `[8.0.0,)`
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
12. **Rename** the test EL implementation if present: `org.glassfish:jakarta.el` → `org.glassfish.expressly:expressly`. The old artifact stopped at the `5.0.0-M1` milestone and is no longer managed by the parent — leaving it produces a dependency with no version and fails the build
13. **Remove** any `<version>` on a dependency the parent already manages: `library-lutece-unit-testing`, `hibernate-validator`, `expressly`, `jaxb-runtime`, `jboss-logging`, `jakarta.el-api`, `jakarta.annotation-api`
14. **Stay on Jakarta EE 10.** Do not introduce EE 11 artifacts — `jakarta.annotation-api` 3.0.0, `weld-junit5` 5.x (Weld 6 / CDI 4.1), `jakarta.el-api` 6.x. They resolve fine and break at runtime
15. **Expect the enforcer to check the test scope.** `requireUpperBoundDeps` and `dependencyConvergence` only exclude the `provided` scope. A conflict between test dependencies fails the build — align the versions, do not widen `excludedScopes`

## Step 2: Create beans.xml

Create `src/main/resources/META-INF/beans.xml` per `cdi-patterns.md` **§1** (exact XML template is there).

## Step 3: Context XML Cataloging

Run the extraction script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/extract-context-beans.sh . .migration/context-beans.json
```

This produces `.migration/context-beans.json` which Java Migrators will consume for producer/scope decisions.

**Do NOT delete context XML files yet** — Java Migrators need to reference them. Mark them for deletion after all Java migration is complete.

## Step 4: Plugin Descriptor

For each file in `webapp/WEB-INF/plugins/*.xml`:
1. **Remove** `<application-class>` elements (XPages are auto-discovered via CDI in v8)
2. Keep `<application-id>` (still needed for URL routing)
3. Update `<version>` to match the new POM version
4. Set `<min-core-version>8.0.0</min-core-version>`
5. Ensure `<max-core-version/>` is present (empty but mandatory)
6. Ensure `<icon-url>` is present (NullPointerException without it)
7. **`<class>` tag — NEVER change it.** If the v7 plugin.xml uses a custom class (e.g. `MyPlugin` extending `PluginDefaultImplementation`), keep it as-is. It may contain `init()` logic required at runtime (registering ImageResourceProvider, FileResourceProvider, etc.). Only use `PluginDefaultImplementation` if the v7 plugin already used it.

## Step 5: web.xml Namespace

Run the template mechanical script (it handles web.xml too):
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-template-mechanical.sh .
```

Or manually: replace `java.sun.com/xml/ns/javaee` → `jakarta.ee/xml/ns/jakartaee` in `webapp/WEB-INF/web.xml`.

Also remove any `ContextLoaderListener` entries (Spring).

## Step 6: SQL Liquibase Headers

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/add-liquibase-headers.sh .
```

## Step 7: Properties for Producers

Read `.migration/context-beans.json`. For beans with `needsProducer: true` that have property values:
- Create entries in the appropriate `.properties` file
- Use the convention: `pluginName.bean.propertyName=value`
- These will be consumed by `@ConfigProperty` in CDI producers

## Step 8: Verification

Run `verify-file.sh` on each modified file:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh pom.xml
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh webapp/WEB-INF/web.xml
```

Mark all your tasks as **completed** when done. This unblocks the Java Migrators.
