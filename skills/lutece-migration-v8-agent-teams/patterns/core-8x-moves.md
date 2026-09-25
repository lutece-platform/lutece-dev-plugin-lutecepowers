# Core APIs that moved or shrank between 7.x and 8.x

A plugin compiles in v7 against classes the core carried and does not carry any more, or carries
differently. The compiler catches the missing ones; the ones that still resolve but from another
artefact, or that lost methods, are found at runtime or not at all. Check every item against the
sources the pom **really** resolves (`mvn dependency:tree`, the jar in `~/.m2`), not against a
reference clone: an open range `[8.0.0,)` resolves the latest core available.

| What | Where it went | What to do |
|---|---|---|
| `XmlTransformerService`, `XslExportService`, the XSL rendering of portlets, tables `core_style`, `core_stylesheet`, `core_style_mode_stylesheet` | `plugin-xmltransformer` | A portlet is ported to HTML (`mvc-patterns.md` §10) and the SQL writing `core_style*` is removed. A plugin that keeps XSL declares `plugin-xmltransformer` (same package, same `new XmlTransformerService( )`), puts `-- lutece runAfter:xmltransformer` on the install scripts that write those tables, and guards the old upgrade statements with a precondition. `rules/sql-liquibase.md`; checks `XT01`, `XT02`, `XT03`. |
| `ContentService extends AbstractCacheableService` | `ContentService` is a plain abstract class in v8: `initCache`, `getFromCache`, `putInCache`, `isCacheEnable` are gone | Drop the cache, or move it to a cache service of its own (`lutece-cache` skill). Check `CS02`. |
| `fr.paris.lutece.portal.service.parser.Parser` and `ParserException` | `library-core-utils` (a transitive dependency of the core; the package name still says `portal`) | Resolves as before; know where it lives before reporting it missing. Resolve implementations through `Instance<Parser>` and test `isResolvable()`: a site without a parsing plugin has none. |
| `library-jmx-api` | No longer a dependency of the core | A plugin implementing `MBeanExporter` declares it (`config-migrator.md` step 13). |
| `net.sf.opencsv:opencsv` 2.3, package `au.com.bytecode.opencsv` | `com.opencsv:opencsv` 5.12.0, package `com.opencsv` (core 8.0.2) | Move to `com.opencsv`: the coordinates, the package and the 5.x API all change. Re-adding 2.3 puts two CSV libraries on the classpath and keeps the plugin on a version the core no longer carries. |
| Spring (`SpringContextService`, `*_context.xml`) | Gone | CDI (`cdi-patterns.md`). |
| EhCache API | JCache through `AbstractCacheableService` | `cache-patterns.md`. |

**Reflection-instantiated classes** (`*-class` tags of the plugin descriptor: `content-service-class`,
`search-indexer-class`, `daemon-class`, `filter-class`, `servlet-class`, `listener-class`,
`page-include-service-class`, `dashboard-component-class`, `rbac-resource-type-class`) are created by the core
with `Class.forName`: they take **no CDI scope** (`cdi-patterns.md` §2) and reach beans through
`CDI.current()`. The scan marks them `classType: reflection`; a name or a parent class suggesting otherwise
does not change that.

**Verify against the resolved core.** Before reporting a class as missing or moved:

```bash
mvn -q dependency:build-classpath -Dmdep.outputFile=/dev/stdout | tr ':' '\n' | grep -E 'lutece-core|library-core-utils'
unzip -l <that jar> | grep -i <ClassName>
```
