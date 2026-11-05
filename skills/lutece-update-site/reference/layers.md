# The layers a v8 site stands on

```
lutece-global-pom 8.x  <-  lutece-site-pom 8.x (parent)
site (packaging lutece-site)
  dependencyManagement: import fr.paris.lutece.starters:lutece-bom:<v>:pom
  dependencies:  a pack (type lutece-site)  or  <family>-starter:<v>
                 + plugins the layer does not bring, without version when the BOM manages them
                 + artefacts outside the BOM with a fixed version (a configuration library, a theme, a site-specific plugin)
```

| Layer | Provides | The site must not |
|---|---|---|
| `lutece-global-pom` 8.x | Java 17, Jakarta EE 10 and MicroProfile provided, enforcer (`requireUpperBoundDeps`, `banDuplicatePomDependencyVersions`), lutece-maven-plugin, the Lutece liberty-maven-plugin fork (`liberty:dev`) | redeclare plugin versions, the JDK, the enforcer |
| `lutece-site-pom` 8.x | `build-config` (provided, mandatory for site-assembly), profile `container-runtime` (logs to JUL) | recreate `dev`/`rec`/`prod` profiles: `src/conf/<env>` is not copied (SI09) |
| `lutece-bom` | the managed version and `<type>` of every Lutece artefact of the catalogue | declare a version for a managed artefact (SI04) |
| `<family>-starter` | a flattened pom listing the plugins of a family; no webapp file, no configuration | redeclare what it brings |
| pack (an organisation's layer, packaging `lutece-site`) | starter + BOM + common plugins, the theme, a configuration library, a `db.properties` on `jdbc/portal` | redeclare what it brings |
| configuration library | a MicroProfile ConfigSource in a jar, at the ordinal its `getOrdinal( )` returns (180 for the one measured): organisation-wide values, an authentication wiring, the XSS filter, a proxy | copy its keys into `WEB-INF/conf`; ignore what it imposes (SI80, SI28) |
| `library-configsource-vault` | a ConfigSource at ordinal 500 whose values come from Vault at run time: above the site's `conf/override` | count on `conf/override` for a key Vault serves: Vault wins (SI29) |

## Rules of the pom (tested with Maven)

1. Parent `lutece-site-pom` at the level of `tools/v8-floor.conf` or later (SI01).
2. One `lutece-bom` import, scope import, type pom, at the version of the starter (SI02): a transitive version comes
   from the BOM, not from the starter. Without it, each transitive version comes from a plugin's range: the site
   pins what those ranges would pull, `lutece-core` included.
3. A managed artefact has no version and the `<type>` the BOM gives: without the type, Maven looks for the jar
   coordinates, finds no managed version and fails (`'dependencies.dependency.version' … is missing`) (SI05).
4. A property `lutece.<artifact>.version` in the site pom does not change the imported BOM's version (SI08). To
   override one version: a `dependencyManagement` entry placed before the import, or a version on the dependency.
5. An artefact outside the BOM carries a fixed version (`x` or the hard pin `[x]`), not a range: `[x,)` resolves past
   the BOM (SI06, SI07).
6. With a BOM, no `lutece-core` dependency (SI03): the starter or the pack brings the core the BOM manages.
7. A pack or a theme is declared with `<type>lutece-site</type>`; its webapp zip is unpacked after the plugins and
   before the site's own `webapp/`.

## Overlay order of `lutece:site-assembly` (the last one wins)

core, plugins (in an unspecified order: a `HashSet`), lutece-site dependencies (packs, themes), third-party jars
(one version per artefact), `build-config` SQL, the site's `webapp/`, `src/sql`, `src/conf/default`, then
`~/lutece/conf/<artifactId>`. A stale `target/<finalName>` skips the core and the plugins: always `clean`
(`tools/site-assemble.sh` does). The war excludes `**/fr/paris/lutece/**/(business|web|service|util|utils)/**` and the
lutece-site lifecycle compiles no Java (SI10). The plugin deletes and rewrites
`WEB-INF/classes/META-INF/microprofile-config.properties` (SI11).

## Starters and what they no longer bring

Compare the plugins of the before war with those of the after war (SI81), never the declared lists: the v8 starters
dropped plugins the v7 starters carried (the address modules of `appointment-starter`, for instance), and a v7 site
used them through the starter without declaring them.
