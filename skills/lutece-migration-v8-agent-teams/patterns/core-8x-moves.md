# Core APIs that moved or shrank between 7.x and 8.x

A plugin compiles in v7 against classes the core carried and does not carry any more, or carries
differently. The compiler catches the missing ones; the ones that still resolve but from another
artefact, or that lost methods, are found at runtime or not at all. Check every item against the
sources the pom **really** resolves (`mvn dependency:tree`, the jar in `~/.m2`), not against a
reference clone: an open range `[8.0.0,)` resolves the latest snapshot.

| What | Where it went | What to do |
|---|---|---|
| `XmlTransformerService`, `XslExportService`, the XSL rendering of portlets, tables `core_style`, `core_stylesheet`, `core_style_mode_stylesheet` (LUT-32172, core 8.0.2) | `plugin-xmltransformer` | A portlet is ported to HTML (`mvc-patterns.md` §10), never kept on XSL. Code that transforms XML for its own needs declares `plugin-xmltransformer`. SQL that writes `core_style*` is removed. Check `XT01`. |
| `ContentService extends AbstractCacheableService` | `ContentService` is a plain abstract class in v8: `initCache`, `getFromCache`, `putInCache`, `isCacheEnable` are gone | Drop the cache, or move it to a cache service of its own (`lutece-cache` skill). Check `CS02`. |
| `fr.paris.lutece.portal.service.parser.Parser` and `ParserException` | `library-core-utils` (a transitive dependency of the core; the package name still says `portal`) | Resolves as before; know where it lives before reporting it missing. Resolve implementations through `Instance<Parser>` and test `isResolvable()`: a site without a parsing plugin has none. |
| `library-jmx-api` | No longer a dependency of the core | A plugin implementing `MBeanExporter` declares it (`config-migrator.md` step 21). |
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
