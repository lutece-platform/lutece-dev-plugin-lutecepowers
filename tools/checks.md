# Migration Verification Checks — Catalog

> Used by `verify-migration.sh` (full project) and `verify-file.sh` (per-file subset)

## Check Format

| Column | Description |
|--------|-------------|
| ID | Unique identifier |
| Severity | FAIL (must fix) or WARN (recommended) |
| Description | What the check detects |
| Pattern | grep pattern used |
| File Types | Which file types this check applies to |

A check whose Python dies on an exception has not run: it reports FAIL `NOT EVALUATED, the check crashed: <error>`, never PASS. Files are read as UTF-8 with undecodable bytes replaced, so an ISO-8859-1 file is checked like any other.

---

## POM Dependencies (PM)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| PM01 | FAIL | Spring dependencies in pom.xml | `org\.springframework` | pom.xml |
| PM02 | FAIL | EhCache dependencies in pom.xml, test scope aside | `net\.sf\.ehcache` | pom.xml |
| PM03 | FAIL | javax.mail dependency, test scope aside | `com\.sun\.mail` | pom.xml |
| PM04 | FAIL | Jersey dependencies, test scope aside (Liberty provides JAX-RS) | `org\.glassfish\.jersey` | pom.xml |
| PM05 | FAIL | json-lib (use Jackson), test scope aside | `net\.sf\.json-lib` | pom.xml |
| PM06 | FAIL | Parent below the latest released lutece-global-pom 8.x, or for a site lutece-site-pom 8.x (`V8_FLOOR_PARENT`, `V8_FLOOR_SITE_PARENT` of `tools/v8-floor.conf`, read in the release repository) | (custom check) | pom.xml |
| PM07 | WARN | springVersion property, read by nothing (remove) | `<springVersion>` | pom.xml |
| PM08 | WARN | Jira properties (remove) | `<jiraProjectName>\|<jiraComponentId>` | pom.xml |
| PM09 | WARN | Bounded version range (use open) | `,[0-9].*)</version>` | pom.xml |
| PM10 | FAIL | `org.glassfish:jakarta.el` declared: the EL implementation is `org.glassfish.expressly:expressly`, the one the parent manages | (custom check) | pom.xml |
| PM11 | WARN | Explicit `<version>` on a parent-managed dependency (`library-lutece-unit-testing`, `hibernate-validator`, `jaxb-runtime`, `expressly`, `jboss-logging`, `jakarta.el-api`, `jakarta.annotation-api`) | (custom check, ignores `<dependencyManagement>`) | pom.xml |
| PM13 | WARN | web-layer test without the test implementation it needs: a JspBean/XPage test needs `jaxb-runtime` (else AppInit stops before the macros load and the page fails on `@pageContainer`), a `processController` test also needs `hibernate-validator` and `expressly`; business-only tests need none | test sources vs `<artifactId>` in pom.xml | pom.xml, src/test |
| PM12 | FAIL | Jakarta EE 11 artifact on an EE 10 baseline (`jakarta.annotation-api` 3.x, `weld-junit5` 5.x, `jakarta.el-api` 6.x) | (custom check) | pom.xml |

## javax Residues (JX)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JX01 | FAIL | javax.servlet | `javax\.servlet` | *.java |
| JX02 | FAIL | javax.validation | `javax\.validation` | *.java |
| JX03 | FAIL | javax.annotation lifecycle | `javax\.annotation\.PostConstruct\|javax\.annotation\.PreDestroy` | *.java |
| JX04 | FAIL | javax.inject | `javax\.inject` | *.java |
| JX05 | FAIL | javax.enterprise | `javax\.enterprise` | *.java |
| JX06 | FAIL | javax.ws.rs | `javax\.ws\.rs` | *.java |
| JX07 | FAIL | javax.xml.bind | `javax\.xml\.bind` | *.java |
| JX08 | FAIL | javax.transaction | `javax\.transaction` (non-cache) | *.java |
| JX09 | FAIL | javax.persistence | `javax\.persistence` | *.java |
| JX10 | WARN | JAX-RS answer relying on Jackson annotations: the v8 server writes it with JSON-B, which ignores `@JsonProperty`/`@JsonFormat` (api field names and dates change, a non-public nested class 500s) | a `@GET/@POST...` method returning, or a `Response.ok( x )`/`.entity( x )` of, a type whose class imports `com.fasterxml.jackson.annotation`; none when a Jackson provider is registered | *.java |

## Spring Residues (SP)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| SP01 | FAIL | SpringContextService | `SpringContextService` | *.java |
| SP02 | FAIL | Spring imports | `org\.springframework` | *.java |
| SP03 | FAIL | Spring context XML file left, or named | file `*_context.xml`, text `_context\.xml` | webapp/ |
| SP04 | FAIL | @Autowired | `@Autowired` | *.java |
| SP05 | FAIL | InitializingBean | `implements.*InitializingBean` | *.java |
| SP06 | FAIL | Named @Component | `@Component(` | *.java |
| SP07 | FAIL | Named @Service | `@Service(` | *.java |
| SP08 | FAIL | Named @Repository | `@Repository(` | *.java |

## Deprecated Libraries (DL)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DL01 | FAIL | net.sf.json (use Jackson) | `net\.sf\.json` | *.java |
| DL02 | FAIL | `au.com.bytecode.opencsv` imported without `net.sf.opencsv` declared: opencsv 2 came with the v7 core, the v8 core ships `com.opencsv` 5 | `^import au\.com\.bytecode\.opencsv` | *.java, pom.xml |

## Event Residues (EV)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| EV01 | FAIL | ResourceEventManager | `ResourceEventManager` | *.java |
| EV02 | FAIL | EventRessourceListener | `EventRessourceListener` | *.java |
| EV03 | FAIL | LuteceUserEventManager | `LuteceUserEventManager` | *.java |
| EV04 | FAIL | QueryListenersService | `QueryListenersService` | *.java |
| EV05 | FAIL | AbstractEventManager | `AbstractEventManager` | *.java |

## Cache Residues (CA)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| CA01 | FAIL | EhCache direct usage | `net\.sf\.ehcache` | *.java |
| CA02 | FAIL | Deprecated cache methods | `putInCache\|getFromCache\|removeKey` | *.java |
| CA03 | FAIL | Raw AbstractCacheableService (no type arguments, spaces before `<` allowed) | `extends AbstractCacheableService` not followed by `<` | *.java |

## Deprecated API (DP)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DP01 | FAIL | Call to a lutece-core `getInstance()` deprecated for removal, read in the core of the references; a project class of the same name is not reported | (custom check) | *.java |
| DP02 | FAIL | `FileImageService.init( )`: the core registers FileImageService at startup (`AppInit`), a second call registers the provider twice. `FileImagePublicService.init( )` is not concerned: the core never registers it | `[^A-Za-z]FileImageService\.init` | *.java |
| DP03 | FAIL | getModel() usage | `getModel( )` | *.java |
| DP04 | FAIL | an import of a lutece-core type deprecated for removal (`@Deprecated( forRemoval = true )` on the type, read in the core of `~/.lutece-references`): the replacement its `@deprecated` javadoc gives, the type's or else its deprecated member's (`CaptchaSecurityService` → `@Inject @Named( BeanUtils.BEAN_CAPTCHA_SERVICE ) Instance<ICaptchaService>`; the event managers → CDI events and `@Observes`; `WorkgroupRemovalListenerService.getService( )` and the other `*RemovalListenerService` → `@Inject @Named( BeanUtils.BEAN_WORKGROUP_REMOVAL_SERVICE ) RemovalListenerService`, `BEAN_ROLE_REMOVAL_SERVICE`…) | java_checks.py dp04 | *.java |
| DP05 | FAIL | an import of a lutece-core type the v7 core had (`develop7.x` of the references) and the v8 core does not: moved (the v8 core types of the same simple name are given) or removed (`BreadcrumbItem`); `SpringContextService` is left to SP01 | java_checks.py dp05 | *.java |
| DP06 | WARN | a lutece-core type, method or `core_*` table the project uses that the core's `develop` has and its last published tag does not: the build passes on the snapshot, a site on the published core fails | java_checks.py dp06 | *.java, src/sql |
| PI01 | FAIL | a `PluginDefaultImplementation.init( )` that initialises a service (a CDI lookup or a `getInstance( )` then a call, a static `XService.init( )`, a `registerListener` or `registerProvider`): the work moves into a `@Observes @Initialized( ApplicationScoped.class ) ServletContext` method, the service's own when the project has it, else an own bean's with the service injected (`patterns/cdi-patterns.md`, Startup initialisation); the plugin class keeps only what the descriptor needs | java_checks.py pi01 | *.java |
| RL01 | FAIL | a removal listener registered outside a startup observer, a producer or an `@Inject` method (a static `init( )` of an entity, a service `init( )` called by the plugin): it registers in a `@Observes @Initialized( ApplicationScoped.class )` method, on the core's `RemovalListenerService` injected by name (`patterns/cdi-patterns.md` §23) | java_checks.py rl01 | *.java |
| PD02 | FAIL | a `PluginDefaultImplementation` subclass whose `init( )` does something while no plugin descriptor names it in `<class>` (the descriptor names `PluginDefaultImplementation` or another class): the core never instantiates it and that `init( )` never runs; what it does moves into a startup observer (`patterns/cdi-patterns.md` §23), the class goes (a constant it held moves to the service) | java_checks.py pd02 | *.java, plugins/*.xml |
| PD03 | WARN | a class extending `PluginDefaultImplementation` that declares no method (only constants such as `PLUGIN_NAME`): name `PluginDefaultImplementation` in the descriptor's `<class>` and move the constants to the plugin's service (`rules/plugin-descriptor.md`) | java_checks.py pd03 | *.java |
| GI01 | FAIL | a static `getInstance( )` on a CDI bean of the project: a call inside the project (inject the bean; `CDI.current( ).select( X.class ).get( )` in a static context), or the accessor declared without `@Deprecated( since = "…", forRemoval = true )` (remove it; keep it deprecated only for the artefacts that call it) | java_checks.py gi01 | *.java |

## DAO (DA)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DA02 | FAIL | `new DAOUtil(` outside a try-with-resources: the connection leaks on an exception | line without `try (`, except a method returning the DAOUtil it built | *.java |
| DA03 | WARN | a DAO reading with `getInt`/`getLong` a column the create scripts declare `char`/`varchar`/`text`, or comparing one with a number in a `where` (`setInt`/`setLong`): the MariaDB driver throws `cannot be decoded as Integer` on a non-numeric value, and the comparison casts every row (no index, `''` equals 0); a number assigned by an insert or a `set` is stored as its digits and not reported. Align the type with an upgrade script or use `get/setString` | java_checks.py da03 | *DAO.java, src/sql |
| DA01 | FAIL | daoUtil.free() | `daoUtil\.free( )` | *.java |

## JPA (JP)

Rules in `patterns/persistence-patterns.md`: the API only, the provider of the container (EclipseLink, `persistence-3.1`).

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JP01 | FAIL | Hibernate imports | `import org\.hibernate\.[^v]` (hibernate-validator excluded) | *.java |
| JP02 | FAIL | JPA provider in pom.xml | `hibernate-core\|hibernate-entitymanager\|module-jpa-hibernate\|spring-orm\|spring-data-jpa` | pom.xml |
| JP03 | FAIL | Hibernate settings in persistence.xml | `hibernate\.\|HibernatePersistenceProvider` | persistence.xml |
| JP04 | FAIL | Parenthesised JPQL collection parameter, in a file using JPA (`jakarta.persistence`, `createQuery`, `@NamedQuery`, `@Query`); the JDBC `IN ( ?, ?` a DAOUtil query builds is left alone | `IN (:\|IN (?\|IN(:\|IN(?` | *.java |
| JP05 | WARN | Named parameters in native SQL | `:name` inside string literals of files calling `createNativeQuery` (heuristic) | *.java |
| JP06 | WARN | shared cache left on: no `<shared-cache-mode>` nor `eclipselink.cache.shared.default=false` outside comments | (custom check) | persistence.xml |
| JP07 | WARN | persistenceContainer-3.1 feature | `persistenceContainer-3\.1` | server.xml |

## CDI Patterns (CD)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| CD01 | FAIL | Static _instance on CDI classes | (cross-file check) | *.java |
| CD02 | FAIL | new CaptchaSecurityService() | `new CaptchaSecurityService()` | *.java |
| CD03 | WARN | CompletableFuture.runAsync | `CompletableFuture\.runAsync` | *.java |
| CD04 | FAIL | commons.fileupload -> MultipartItem (MemoryFileItem from library-httpaccess in memory) | `org\.apache\.commons\.fileupload` | *.java |
| CD05 | WARN | CDI bean registering itself (`registerIndexer`, `registerCacheableService`, `registerProvider`) in its constructor or `@PostConstruct` with no `@Observes @Initialized` method: the bean is created on first use | java_checks.py cd05 | *.java |
| CD06 | FAIL | `@Observes` on an event the publishers fire only with `fireAsync()`: the observer is never called | firing sites (`select( X.class ).fireAsync(`, `Event<X>` fields) in the project and the reference clones vs `@Observes X` | *.java |
| CD07 | FAIL | `@Inject` of a library interface whose only implementation is in a plugin the pom does not declare (workflowcore services → plugin-workflow): v8 resolves it at deployment, the site does not start (WELD-001408) | `import fr.paris.lutece.plugins.workflowcore.service.*` + `@Inject` of that type, no `plugin-workflow`/`module-workflow-*` in pom.xml | *.java |
| CD08 | WARN | a `CDI.current( )` lookup inside an instance method of a CDI bean: the bean injects it: `@Inject`; `@Inject @Any Instance<X>` for an extension point, an optional bean or a name known at run time (`CdiHelper.resolve( instance, name )`); `@Inject Event<X>` for an event (`rules/service-layer.md`, Injection). Static contexts keep `CDI.current( )` | java_checks.py cd08 | *.java |
| CD09 | FAIL | a captcha tested through the `jcaptcha` plugin (`isPluginEnable( "jcaptcha" )`): v8 has no such plugin (plugin-captcha is named `captcha`), so the captcha never shows; test the injected `Instance<ICaptchaService>` (`@Named( BeanUtils.BEAN_CAPTCHA_SERVICE )`) with `isResolvable( )` alone | `"jcaptcha"` | *.java |

## MVC (MV)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| MV01 | FAIL | Admin page rendered from a new HashMap without the security token its controller enables | `java_checks.py mv01` | *.java |
| MV02 | FAIL | AbstractPaginatorJspBean | `AbstractPaginatorJspBean` | *.java |
| MV03 | WARN | CSRF token carried by hand inside an MVC bean, or `securityTokenEnabled` false or unset; names first the template lines where that token rides a GET action link or a script (keep it until they are POST, TD71) | `SecurityTokenService\.MARK_TOKEN` in a file that has `@Controller` / `MVCAdminJspBean` / `MVCApplication`; a Lutece `@Controller( … )` without `securityTokenEnabled` | *.java |
| MV05 | WARN | `@View` calling an `@Action` method of its bean: the write runs on a GET, which the token filter never checks | body of each `@View` method naming an `@Action` method of the same file | *.java |
| MV06 | WARN | `addError` then a redirect from an admin `@View`: the message is lost on the next page | body of each `@View` of an `MVCAdminJspBean`: `addError(` followed by `redirect(`/`redirectView(` | *.java |
| MV07 | FAIL | `@Controller` `controllerPath` without its trailing slash: the core joins it to `controllerJsp` as is (urls, CSRF registry) | `controllerPath = "…"` not ending with `/` | *.java |
| MV08 | WARN | an `@Pager` whose `defaultItemsPerPage` names a property key (literal or constant) that no properties file of `webapp/WEB-INF/conf` (the project's, the core's) declares: `PagerProducer` reads it with `getOptionalValue( ).orElse( 50 )`, so the configured value never applies; declare the key, or name the one the project declares | java_checks.py mv08 | *.java |

**MV03** — an MVC bean gets its token from the framework, so a token put in the model or validated by hand
there means the framework's own is off or duplicated. A bean that is not MVC — a portlet admin bean, a servlet —
has no framework token and must carry it by hand: that is the pattern, not a finding, and the check leaves it
alone. `securityTokenEnabled = false` is always a finding, and so is a `@Controller` that omits it: the default is
`false`, so the XPage or JspBean runs its actions without any token.

When the manual token also rides a GET link to an action (`?action=…&token=${token}`, a `Do….jsp` link, a
`data-query` URL) or a script, MV03 names those template lines first: the core exempts GET from its token check
(`SecurityTokenHandler.ALLOWED_METHODS`) and still runs the `@Action`, so that manual check is the only protection
left. Move each such mutation to a POST form first (TD71), then leave the token to the framework; never remove the
manual check while the action stays reachable by GET. A link to a view carries no mutation and is not named.

## Web / Config (WB)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| WB01 | FAIL | Old Java EE namespace | `java\.sun\.com/xml/ns/javaee` | webapp/*.xml |
| WB02 | FAIL | application-class | `<application-class>` | plugins/*.xml |
| WB03 | FAIL | ContextLoaderListener | `ContextLoaderListener` | web.xml |
| WB04 | WARN | `<min-core-version>` below `8.0.0`, or not plain digits | (custom check, reads `tools/v8-floor.conf`) | plugins/*.xml |
| WB05 | FAIL | descriptor filter under /rest/ | (custom check) | plugins/*.xml |
| WB06 | FAIL | `<admin-feature>` whose `<feature-group>` differs from the group its install SQL gives: a reinstall rebuilds the right from the descriptor and moves it | (cross-file check) | plugins/*.xml |
| WB07 | WARN | admin feature icon value in `<feature-icon-url>`, which the core digester ignores (it reads `<icon-url>`): a reinstall loses the icon | (cross-file check) | plugins/*.xml |
| WB08 | WARN | descriptor `<icon-url>` naming a path no webapp carries while the project ships that image elsewhere (a typo such as `iamges/`): the plugin shows the generic icon | (cross-file check) | plugins/*.xml |
| WB09 | WARN | plugin admin right named `CORE_*`: it shares the id with the core, so a core upgrade that deletes its own right deletes the plugin's | `<feature-id>CORE_` in a plugin descriptor | webapp/WEB-INF/plugins/*.xml |
| WB10 | FAIL | a `@RequestScoped` admin bean calling the inherited `getPlugin( )`: `PluginAdminPageJspBean.init` reads `plugin_name` only, so it is null on every request without it; override `getPlugin( )` with `PluginService.getPlugin( PLUGIN_NAME )` | java_checks.py wb10 | *.java |
| WB11 | WARN | a JspBean or XPage HTML-escaping a request parameter (`escapeHtml4`, `replaceAll( "&", "&amp;" )`…): the core XSS filter (`sanitizeFilterMode`, `/jsp/admin/*` and `/jsp/site/*`) already escapes it, so it is stored escaped twice; a servlet or REST resource is outside the filter | java_checks.py wb11 | *.java |
| WB12 | FAIL | an admin feature url with a query string (`<feature-url>`, `core_admin_right.admin_url`): the core admin menu links it as `url?plugin_name=…`, so the url gets two `?` and loses its parameters (an MVC view: "No method found to process view"); point the feature at the bare JSP and make that view the `defaultView` | `<feature-url>…?`, `admin_url` with `?` | plugins/*.xml, *.sql |
| WB13 | FAIL | the install SQL (`core_admin_right.admin_url`, `icon_url`) and the descriptor (`<feature-url>`, `<icon-url>`) differ for one admin feature: a fresh install shows the SQL row, a reinstall from the Plugins screen rebuilds it from the descriptor; align both, and give upgraded sites an `UPDATE` | install `INSERT INTO core_admin_right` vs `<admin-feature>` | plugins/*.xml, *.sql |
| WB14 | FAIL | an admin feature icon written as Tabler classes (`ti ti-x`) that `tabler-icons.min.css` of the core does not define: the menu shows an empty glyph | `icon_url`, `<icon-url>` vs the core css | plugins/*.xml, *.sql |
| WG01 | WARN | in a project that filters by workgroup (`AdminWorkgroupService.getAuthorizedCollection` / `isAuthorized`), an admin JspBean method that loads a workgroup resource (`AdminWorkgroupResource`) by its id without `AdminWorkgroupService.isAuthorized( resource, (User) getUser( ) )`, in the method or in a helper of the project it calls: the listing hides the row, the id typed in the url opens it; check it and refuse (AccessDeniedException or an AdminMessage), or say why the resource needs none | java_checks.py wg01 | *.java |

**WB05** — a `<filters>` entry of the plugin descriptor whose `<url-pattern>` is deeper than `/rest/*`. It cannot
fire in v8: `MainFilter.matchMapping` compares the pattern to `request.getServletPath( )`, which is `/rest` for
every call routed to the application mounted by `@ApplicationPath( "/rest/" )`, the rest of the url being in
`getPathInfo( )`. The filter is still read, instantiated and registered — the log even says
`New Filter registered` — and it simply never runs.

FAIL rather than WARN because the failure is silent and it opens whatever the filter protected. Removing the block
is only half the fix: replace it with the `@NameBinding` `ContainerRequestFilter` of `rest-patterns.md` §3, with
the same parameters, so the contract holds even though the mechanism changed. `/rest/*` itself still matches and is
not reported, nor is any pattern outside `/rest/` — a filter on `/jsp/site/*` works as before.

## Structure (ST)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| ST01 | FAIL | beans.xml missing in a project that declares CDI beans | (file existence check, when CDI annotations are present) | META-INF/beans.xml |
| ST02 | FAIL | final on a normal-scoped CDI class (application, request, session: proxied) injected, selected or looked up through `Instance` by its concrete type; `@Dependent` beans are not proxied | (cross-file check) | *.java |
| ST03 | FAIL | concrete DAO class without CDI scope (an abstract DAO base is skipped: its subclasses carry the scope) | (cross-file check) | *.java |
| ST04 | FAIL | Project type resolved by CDI (`@Inject`, `select( X.class ).get( )`) with no bean and no producer; libraries skipped | `java_checks.py st04` | *.java |
| HM01 | FAIL | Home not in the v8 form: a plain Home with `getInstance( )`; a portlet home the core cannot create or use (it builds it by reflection): no public no-arg constructor, an `@Inject` field (never injected), or a CDI bean declared `final`. A hand-made singleton works | java_checks.py hm01 | *Home.java |
| HM02 | WARN | Portlet home in the older form (not `@ApplicationScoped`, hand-made singleton, `getInstance( )` without CDI): it works, the modern form is the CDI bean of `rules/dao-patterns.md` | java_checks.py hm02 | 
| ST05 | FAIL | files created by the migration excluded by .gitignore (they would never be committed) | `git check-ignore` | beans.xml, test microprofile-config |
| ST07 | FAIL | production class named like a test (`Test*`, `*Test`, `*Tests`, `*TestCase`) under src/java: surefire collects it from WEB-INF/classes | file names | src/java |
| ST08 | FAIL | `src/site/*.xml` that `maven-site-plugin` cannot read: an HTML entity such as `&egrave;` in the root `<project>` tag, or an unclosed tag (entities elsewhere are read) | XML parse | src/site/*.xml |

**ST02** — `final` is legal and is the core's own pattern when the bean is resolved only
through its interface (`@ApplicationScoped public final class XDAO implements IXDAO`, as
in many lutece-core DAOs). The check only fails when the code injects or selects the
**concrete** type, which is the case CDI cannot proxy. See `cdi-patterns.md` §1.

**ST05** — ST01 only proves the file sits on disk. A file `.gitignore` excludes never reaches the
repository, so the plugin ships without its CDI descriptor; at the next clone the Home static
initializer dies with `UnsatisfiedResolutionException` and every portlet call fails with
`NoClassDefFoundError` — and the build still prints `BUILD SUCCESS` because the parent pom sets
`testFailureIgnore`. Untracked-but-not-ignored is not a finding: the skill stages with `git add -A`
after the gate.

## SQL (SQ)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| SQ01 | FAIL | SQL file without the Liquibase header (v8 installs only Liquibase changesets) | first non-empty line ≠ `-- liquibase formatted sql` | src/sql/**/*.sql |
| SQ02 | FAIL | column or table gained by `create_db_*.sql` since the last commit with no upgrade script adding it | (cross-file check against `git show HEAD:`) | src/sql |
| SQ03 | FAIL / WARN | `AUTO_INCREMENT` added to a column without `NO_AUTO_VALUE_ON_ZERO` in the changeset; FAIL when the install data ships an id 0 for that table | per-changeset scan + init data | src/sql/**/upgrade |
| SQ04 | FAIL | `INSERT INTO core_x VALUES (…)` without a column list: fails as soon as the core adds a column. An upgrade script already committed is released and left as it is (roll forward) | `INSERT +INTO +core_[a-z0-9_]+ +VALUES` | src/sql |
| SQ05 | FAIL | value concatenated into a SQL literal in a DAO (`"… LIKE '%" + str`): injection point | `'\" +` in *DAO.java | *DAO.java |
| SQ06 | FAIL | Liquibase-headed SQL file absent from `WEB-INF/classes/sql` of the assembled webapp: the lutece-maven-plugin copies only a name it parses (`update_db_<plugin>-<from>-<to>.sql`, digits and dots) and the `prerun_db_*` scripts, plugin-liquibase reads nothing else | (assembly check) | src/sql |
| SQ07 | WARN | `-- validCheckSum:` in a script other than `prerun_db_*`: the body of a shipped changeset was edited. Keep the directive: a site that replays the file (a creation script on a site without its version key, an upgrade at an equal unstable version) fails its checksum without it. The next change appends a changeset | `^--\s*validCheckSum` outside `prerun_db_*` | src/sql |
| SQ08 | FAIL | install script `plugins/<p>/(plugin\|core)/(create\|init)_*.sql` under `webapp/WEB-INF/sql` without the Liquibase header: the war ships it and plugin-liquibase refuses to start in `safeRun` | first non-empty line ≠ `-- liquibase formatted sql` | webapp/WEB-INF/sql |
| SQ09 | FAIL | `src/sql/plugins/<name>/` (or `<plugin>/modules/<module>/`, read as `<plugin>-<module>`) named after no `<name>` of the project descriptors: plugin-liquibase versions its scripts as that other component's (LUT-33232) and aborts the startup in `safeRun` on a site that does not carry it; the scripts go in the project's own directory, and `-- lutece runAfter:<plugin>` in their leading comments orders them after another plugin's | directory names vs `webapp/WEB-INF/plugins/*.xml` `<name>` | src/sql |
| SQ10 | FAIL | Liquibase changeset without any SQL statement: validation fails (`'sql' is required`) and no changeset of the site runs, whatever `failOnError` | changeset header followed by comments or blank lines only | src/sql |
| SQ11 | FAIL | Changeset identity (`author:id`) declared twice in one upgrade script: Liquibase refuses the changelog | changeset headers | src/sql/**/update_*.sql |
| SQ12 | WARN | Changeset of an upgrade script whose body differs from the last tag or the last commit (an id taken over in a rebase, an edited release): a base that ran it never gets the new body, a replay fails its checksum; allowed only for damage that cannot be undone afterwards, said in the changeset comment | `git show <tag>:` / `HEAD:` | src/sql/**/update_*.sql |

**SQ02** — a fresh install runs the creation script and is green; an existing site runs only the
`update_db_*` scripts newer than its recorded version. An older upgrade that (re)creates the table
without the column does not count. Rules and model in `rules/sql-liquibase.md`.

**SQ03** — MariaDB renumbers an id 0 when the column becomes AUTO_INCREMENT and fails on the duplicate. The
ALTER belongs in a `dbms:mariadb,mysql` changeset after `SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO'`.
A WARN says the guard is missing; a FAIL says the install data really ships a 0 in that column, so every site installed with it breaks.

## v8 core changes (XS, XT, CS, TL)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| XS01 | FAIL | portlet still rendered by XSL (a `DOCUMENT*` type excepted with plugin-xmltransformer) | (cross-file check) | *.java |
| PT01 | FAIL | portlet type of `plugin.xml` not inserted into `core_portlet_type` by an install script (the core registers it only on a UI install) | cross-file check | webapp/WEB-INF/plugins/*.xml, src/sql |
| XT01 | FAIL | XSL services or `core_style*` tables used without `plugin-xmltransformer` declared | (cross-file check) | *.java, src/sql, pom.xml |
| XT02 | FAIL | install script writing `core_style*` without `-- lutece runAfter:xmltransformer`, when the pom declares plugin-xmltransformer | header grep | src/sql (not upgrade) |
| XT03 | FAIL | upgrade statement on `core_style*` in a changeset without `precondition-sql-check` | per-changeset scan | src/sql/**/upgrade |
| CS02 | FAIL | content service calling the cache methods v8 removed from `ContentService` | `extends ContentService` + `initCache\|getFromCache\|putInCache` | *.java |
| TL01 | FAIL | ThreadLocal not cleared with remove() | (cross-file check) | *.java |
| CS01 | FAIL | portlet JspBean mutations without a CSRF token | (cross-file check) | *.java |
| CS03 | WARN | a `@Controller` comparing the request method with `POST`: a plugin guard around the core defect that runs an `@Action` on GET without its token (`SecurityTokenHandler` exempts GET); remove it, the e2e scenario carries `core_defect` | java_checks.py cs03 | *.java |

**XS01** — **An XSL portlet must be ported to HTML during the migration; there is no second
option.** `core_style`, `core_style_mode_stylesheet` and `core_stylesheet` left the core for
`plugin-xmltransformer`, the core's `PortletStyleDAO` is a stub returning `null` and an empty
`ReferenceList`, and the back office cannot even create an XSL portlet whose
type is not `DOCUMENT*`: the style select is rendered under
`<#if portletType.id?starts_with('DOCUMENT')>` so no `style` is posted, and
`setPortletCommonData` returns `MANDATORY_FIELDS` — the `return` is outside the test for the
xmltransformer plugin, so installing it changes nothing but a log line. Symptoms when nothing
is done: the portlet renders an empty string with no error, the install fails on missing
tables, and creating one from the back office is impossible. The check fails on a portlet class
that still defines `getXml`/`getXmlDocument` without extending `PortletHtmlContent` (a `DOCUMENT*` portlet type
excepted when the pom declares plugin-xmltransformer: that type keeps its style select). The `core_style*`
statements are XT01's. The port is in `mvc-patterns.md` §10.

**XT02 / XT03** — a plugin that keeps XSL rendering depends on plugin-xmltransformer, so its install scripts
must run after that plugin (`runAfter`) and its old upgrade scripts must not fail where the style tables are gone
(a guarded changeset). A plugin that ported its portlet to HTML removes the statements instead (XT01). Recipe and
exact syntax in `rules/sql-liquibase.md`.

**TL01** — always `ThreadLocal.remove()` in a `finally`, never a reassignment such as
`set(false)`. A reassignment keeps one entry per pooled thread for the whole application
lifetime.

**CS01** — the v8 automatic token filter only covers MVC controllers (`@Action` / `@View`), and
the core's `create_portlet.html` / `modify_portlet.html` emit no token, so every `do*` of a
`PortletJspBean` accepts a forged call. The plugin closes it alone: its `create_specific`
template is included *inside* the core form and `getCreateTemplate` / `getModifyTemplate` take a
model. The check fails on a class extending `PortletJspBean` that never calls
`getSecurityTokenService( ).validate( request, … )`. Recipe and traps in `mvc-patterns.md` §11.

## i18n (I18N)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| I18N01 | FAIL | i18n key repeating the plugin prefix that the project asks for as written (`#i18n{agenda.x}` while the bundle declares `agenda.x`, read `agenda.agenda.x`), or a key glued to the line above; a prefixed key nothing asks for is dead and left to I18N08 (`fix-i18n-bundles.py`) | (cross-file check) | *_messages*.properties |
| I18N03 | FAIL | i18n key in the default bundle and not in `_fr`, or the reverse (the two languages the core ships); a key nothing uses is left to I18N08 (remove it, do not translate it) | (cross-file check) | *_messages*.properties |
| I18N04 | WARN | the other languages of a bundle lack keys of the default bundle | (cross-file check) | *_messages_*.properties |
| I18N05 | FAIL | bundle suffixed with a country code (`_cz`, `_dk`, `_se`…) where Java expects a language code (`_cs`, `_da`, `_sv`): never loaded | file names | *_messages_*.properties |
| I18N06 | FAIL | bundle line without `=`/`:` separator (`key>value`): read as a key with an empty value | line scan | *_messages*.properties |
| I18N09 | WARN | translation key the default bundle does not declare (translated key name, key renamed or removed since): never shown | (cross-file check) | *_messages_*.properties |
| I18N07 | WARN | French value with a common spelling error (`Etes vous`, `sur de vouloir`) or a leftover Java class name after an article (`un PollFormQuestion`) | decoded `_fr` values | `*_messages_fr.properties` |
| I18N08 | WARN | Bundle key nothing uses (`i18n_unused.py`): no project file names `<prefix>.<key>` or `"<key>"`, no literal or `${` stem builds it, no reference repository names it; runtime families (`model.entity.*`, `validation.*`, `site_property.*`) are kept | default bundles vs every tracked text file | `*_messages.properties` |
| I18N02 | WARN | i18n key asked for by a template, a message constant, a label tag of the plugin descriptor or a `core_admin_right`/`core_portlet_type` row, declared in no bundle | (cross-file check) | webapp, src/java |
| I18N10 | WARN | key declared twice in the same bundle: `java.util.Properties` keeps the last value, the first never shows | (cross-file check) | *_messages*.properties |

**I18N01** — keys in `<plugin>_messages.properties` are relative to the bundle, so
`<plugin>.message.x` written there resolves as `<plugin>.<plugin>.message.x` and renders
as an empty label (and a WARN in the log): nothing fails. The same grep catches a key appended without a
trailing newline, glued to the value of the line above, which corrupts both entries.
`tools/fix-i18n-bundles.py <project>` repairs I18N01, I18N05, I18N06, I18N09 and I18N10 in place (`--dry-run` to list).

**I18N02** — a `#i18n{...}` of a template, or a `MESSAGE_*` / `INFO_*` / `ERROR_*` / `TITLE_*` constant, naming a
key no bundle declares: Lutece prints an empty label (and a WARN in the log) and nothing fails at build time. WARN, because
most of these predate the migration. Only the plugin's own prefix is checked, and only those two sources — bean
names and CSRF action names are strings of the same shape and are not keys. Every grep of the check passes `-a`:
a bundle saved in ISO-8859 counts as binary for grep, which then reports nothing at all — the same trap turns a
manual search in those files into a false "the key is missing".

**A sweep that finds nothing has to be trusted, so do not sweep with a bare `grep -r`.** In an interactive shell
`grep` is often a function or an alias over ripgrep or ugrep, which skip dotted files and directories and honour
`.gitignore` by default: `.migration/`, `.settings/` and anything the project ignores are searched silently past.
The scripts are safe — a shell function is not exported to `bash script.sh` — but an agent checking its own work
in an interactive shell is not. When the answer "nothing left" is the point of the search, run it as
`find . -type f -print0 | xargs -0 grep -an <pattern>`.

## JSP (JS)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JS01 | FAIL | jsp:useBean | `jsp:useBean` | *.jsp |
| JS02 | FAIL | JSP scriptlets | `<%[^@-]` | *.jsp |
| JS03 | FAIL | EL call written with the class name (`${MyJspBean.method( … )}`): EL resolves only static methods that way, an instance method fails at runtime with `MethodNotFoundException`; call the `@Named` bean by its name | `\$\{…[A-Z]…(JspBean\|Bean)\.[a-z]…\(` | *.jsp |
| JS06 | FAIL | JSP streaming a file (download, export) that leaves template text, a newline between its directives included (`trimDirectiveWhitespaces` does not remove it on Liberty): "OutputStream already obtained" on every download | (cross-file check) | *.jsp |
| JS07 | FAIL / WARN | static script of the plugin that does not parse (`node --check`): the browser drops the whole file; WARN NOT EVALUATED when node is not installed | node --check | webapp/**/*.js (outside WEB-INF, not *.min.js) |
| JS05 | FAIL | admin JSP writing its own HTML (`<form>`, `<table>`, `<div>`…): the screen belongs in a template rendered by a `@View` | markup tags in webapp/jsp/admin | *.jsp |
| JS04 | FAIL | admin JSP driving a bean that is not a `@Controller` (legacy `DoXxx.jsp`, portlets excepted), or calling a `@Controller` outside `processController` (a method that is no `@View`): no v8 dispatch, no automatic CSRF; the method becomes a `@View` (the `defaultView` of the menu entry) | (cross-file check) | *.jsp, *.java |

## Diff and versions (LE, PV)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| LE01 | FAIL | line endings converted in a changed file (diff widened to the whole file) | carriage returns in HEAD vs the work tree | changed files |
| PV01 | FAIL | pom version and plugin descriptor `<version>` differ | (cross-file check) | pom.xml, plugins/*.xml |
| PV02 | FAIL | version not above the last released git tag while upgrade scripts changed since (WARN, not evaluated, in a shallow clone without tags or outside git): an upgraded site never runs the new upgrade scripts. The numbers only count, as plugin-liquibase compares them (`PluginVersion` of library-sql-utils): `4.0.2-SNAPSHOT` after a `4.0.2-beta-03` release is the same version. A script ending at the installed version runs only with `liquibase.accept.unstable.versions` (or `accept.snapshot.versions`) and an upgrade as the plugin's last run, never on a site installed fresh at that release: put the changes in a script ending above the release (`update_db_x-4.0.2-4.0.3.sql`) and raise the version to `4.0.3-SNAPSHOT` | `git tag` | pom.xml |
| PV03 | WARN | version below the last released git tag, or equal to a final release, no upgrade script since: raise it before adding one (equal to a pre-release's numbers: PASS with the reminder) | (git tags) | pom.xml |

**LE01** — the fix is `tools/restore-line-endings.sh`: it puts back the endings HEAD has on every changed file
whose endings moved, whatever else changed in it, and touches nothing else. A file that carries real changes on
top of the conversion is the one where this matters most: its migration is buried under a rewrite of every line.
Run it before the final gate, then verify again: a review that has to read a whole rewritten file does not happen.

## Templates (TM)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| TM01 | FAIL | Old Bootstrap panels | `class="panel` | admin/*.html |
| TM02 | FAIL | jQuery in a template, or in a plugin script outside vendored libraries, with no `library-theme-jquery` in the pom (WARN when declared): nothing loads it, the script dies | `template_rules.py jquery` + `jQuery(\|\$(` in webapp *.js | templates, webapp *.js |
| VL01 | FAIL | a copy of jQuery, of a jQuery plugin (a `.js` defining `$.fn.x`) or of a jQuery-era upload widget under `webapp/` | file names, `$.fn.` in *.js | webapp/ |
| TM10 | FAIL | offcanvas (`@offcanvas`, `@cOffcanvas`, offcanvas markup): the content of the page goes in a `@modal` / `@cModal`, another page is reached by a plain link | `template_rules.py offcanvas` | admin, skin |
| TM11 | FAIL | front-office form that is not a `@cForm` (raw `<form>`, `@tform`) or `foValidation=false`: no core form validation | `template_rules.py fo-forms` | skin |
| TM12 | FAIL | inline form: three visible fields or more side by side (`@tform type` inline/flex, `form-inline`/`d-flex` on the form, `formStyle='inline'`, a row of three field columns); two columns are fine | `template_rules.py inline-forms` | admin, skin |
| TM03 | FAIL | Front-office upload macros (`addFileInput`, `addUploadedFilesBox`, `addFileInputAndfilesBox`) in a back-office template | `template_rules.py fo-upload` | admin *.html, *.ftl |
| TM04 | FAIL | `errors` / `infos` / `warnings` read with `?size` / `?has_content`, no default nor `??` guard: the MVC model holds them only when there is one | `template_rules.py unsafe-messages` | *.html, *.ftl |
| TM05 | FAIL | Old jQuery autocomplete (SuggestPOI `autocomplete-js.jsp`, `createAutocomplete`, `.autocomplete(`) | `template_rules.py suggestpoi` | webapp *.html, *.ftl, *.jsp |
| TM06 | FAIL | `@addRequiredJsFiles` in a back-office template (not BO) | `template_rules.py fo-required-js` | admin *.html, *.ftl |
| TM07 | FAIL | Loop variable of a list over `errors` printed as `${x}`, not `${x.message}` (an MVCMessage); over `infos` / `warnings` printed as `${x.message}` (a string: the page throws) unless the body tests `x.message??` / `?is_string`, or the project fills that list with `MVCMessage` objects itself | `template_rules.py mvc-message` | *.html, *.ftl |
| TM13 | WARN | `${x.message}` over `infos` / `warnings` the project fills with `MVCMessage` objects itself: it works, the modern form is the core's `addInfo( )` / `addWarning( )` and `${x}` | `template_rules.py own-messages` | *.html, *.ftl |
| TM08 | WARN / FAIL | Design rules a macro-written template still breaks (entity list in `@table`, list without `@empty`, `@checkBox` without switch or without an explicit value, raw HTML, undeclared or repeated macro parameter, a script looking up an element the template only emits under a condition, a link to a JSP the webapp does not carry, a jQuery-era upload widget, a vendored copy of jQuery, Bootstrap 3/4 or Font Awesome markup, an unstyled btn-default button, BO macro in skin, image icon in `core_admin_right`, jQuery without a `library-theme-jquery` dependency, offcanvas, a front-office form without `@cForm`, an inline form) | `scan-template-design.py --flat --warn-only` (codes in its header; needs the assembled webapp, see `ensure-exploded.sh`). WARN on a finding; FAIL when the scan could not run although the project assembled | admin/*.html, skin/*.html, src/sql |
| TM09 | FAIL | Template FreeMarker cannot parse (answers 500) | `check-template-parse.sh` (FreeMarker `Template` constructor on every file) | *.html |

## Logging (LG)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| LG01 | FAIL | String concat in logging | `AppLogService\..*+ ` | *.java |
| LG02 | WARN | Unnecessary isDebugEnabled | `isDebugEnabled\|isInfoEnabled` | *.java |

## Tests (TS)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| TS01 | FAIL | JUnit 4 @Test | `import org\.junit\.Test\b` | *.java (test) |
| TS02 | FAIL | JUnit 4 @Before/@After | `import org\.junit\.Before\b\|import org\.junit\.After\b` | *.java (test) |
| TS03 | FAIL | JUnit 4 Assert | `import org\.junit\.Assert` | *.java (test) |
| TS04 | FAIL | MokeHttpServletRequest | `MokeHttpServletRequest` | *.java (test) |
| TS05 | FAIL | JUnit 4 @BeforeClass/@AfterClass | `import org\.junit\.BeforeClass\|import org\.junit\.AfterClass` | *.java (test) |
| TS06 | FAIL | Test methods without @Test (or another JUnit 5 test annotation) in the annotation block above them | (cross-line check) | *.java (test) |
| TS07 | FAIL | SpringContextService in tests | `SpringContextService\.getBean` | *.java (test) |
| TS08 | FAIL | Spring mock imports | `org\.springframework\.mock\.web` | *.java (test) |
| TS09 | FAIL / WARN | Failing tests in the surefire reports (the parent POM sets `testFailureIgnore=true`, so `BUILD SUCCESS` proves nothing). FAIL on a failure or an error, and when `src/test/` exists with no report (the tests were never run; the command is `mvn lutece:exploded antrun:run -Dlutece-test-hsql test`). WARN when the project has Java and no `src/test/`, or when the reports record no test run | `target/surefire-reports/*.txt` | test results |
| TS10 | WARN | No test file names a class of the project (a placeholder such as `assertTrue( true )`): the tests pass and prove nothing | class names of src/java in src/test | *.java (test) |

## Site (SI)

Checks of a site, a pack or a theme (packaging `lutece-site`), made by `site_check.py check <site> [--war DIR]
[--before DIR --before-ref REF] [--as-profile ENV]`. The war is the directory `lutece:site-assembly` explodes
(`site-assemble.sh`). SI80-SI86 compare two assembled states and fail until `.migration/site-decisions.md` answers
each difference (`- key|plugin|file|profile <id>: <reason>`). Rules and evidence: `skills/lutece-update-site/reference/`.

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| SI01 | FAIL | Parent other than `lutece-site-pom` at `V8_FLOOR_SITE_PARENT` or later | (custom check) | pom.xml |
| SI02 | FAIL / WARN | Not exactly one `lutece-bom` import (FAIL); BOM and starter on different versions (WARN) | (custom check) | pom.xml |
| SI03 | WARN | `lutece-core` declared by the site | (custom check) | pom.xml |
| SI04 | WARN | Version written for an artefact the BOM manages | (custom check, needs the BOM pom) | pom.xml |
| SI05 | FAIL | Artefact declared with a `<type>` other than the BOM's: no managed version is found | (custom check) | pom.xml |
| SI06 | FAIL / WARN | Artefact without version that neither the BOM nor the parent poms manage, in the dependencies or a profile, whatever the scope: the pom does not load (WARN for a provided or test one when the parent poms are not in the local repository) | (custom check, parents read in --m2) | pom.xml |
| SI07 | WARN | Version range on a dependency | `[`, `(` | pom.xml |
| SI08 | WARN | `lutece.*.version` property: it does not change the version the imported BOM manages | (custom check) | pom.xml |
| SI09 | FAIL | `src/conf/<env>/` or a profile with `defaultConfDirectory`: not copied by `lutece-site-pom` | (custom check) | src/conf, pom.xml |
| SI10 | FAIL | `src/java` (the lutece-site lifecycle compiles none) or classes under the packages the war excludes | (custom check) | src/java, webapp/WEB-INF/classes |
| SI11 | FAIL | `webapp/WEB-INF/classes/META-INF/microprofile-config.properties`: site-assembly deletes and rewrites it | (custom check) | webapp |
| SI12 | FAIL | SQL of the site Liquibase never runs: path `SqlPathInfo` does not parse, or no `-- liquibase formatted sql` first line | `sql_paths.py` | src/sql |
| SI13 | WARN / FAIL | Takeover of the before database (needs --before): a component script inserting, without deleting it first, a key the core upgrade inserts (WARN: duplicate key); a script using a table the core upgrade drops (FAIL: a v7 upgrade to apply first) | `site_check.py takeover` | the two wars |
| SI14 | WARN / FAIL | Component the before war does not declare whose create script creates tables of the before site: renamed (WARN: installed as new, its upgrades never run; its keys and version move to the new name) or sharing them with a component still shipped (FAIL: its create script runs on them) | create scripts of both wars | the two wars |
| SI20 | FAIL / WARN | Spring `*_context.xml`: v8 reads none (FAIL with a bean, WARN when empty) | `<bean` | webapp/WEB-INF/conf |
| SI21 | WARN | `log.properties`: v8 reads none | (file name) | webapp/WEB-INF/conf |
| SI22 | FAIL / WARN | Pool service C3p0 (gone, FAIL) or other than `ManagedConnectionService` (WARN) | (custom check) | db.properties |
| SI23 | FAIL | Pool without `<pool>.ds`, or `.ds` without `<dataSource jndiName>` in `server.xml` | (custom check) | db.properties, server.xml |
| SI24 | WARN | Pool password in `db.properties` | (custom check) | db.properties |
| SI25 | FAIL | `server.xml` fileset matching no jar of the war (the JDBC driver) | (custom check, needs --war) | server.xml |
| SI26 | WARN | Same key, different values, in two files of the override source: in v8 the last file loaded wins (override/plugins after override/, then alphabetical) | (custom check) | conf/override |
| SI27 | FAIL / WARN | Override key no default declares and no class of the war names: read by nothing (WARN); FAIL when the war reads a key ending with it whose default differs from the site's value: a renamed key, the site's value lost | class-file constants, defaults | conf/override |
| SI28 | FAIL / WARN | Configuration value naming a class the war does not ship (FAIL when the site or a library ConfigSource sets it) | (custom check, needs --war) | effective configuration |
| SI29 | WARN / INFO | Profile name used without `%`; ConfigSource of unknown ordinal; profiles the site names (INFO) | (custom check) | conf/override |
| SI30 | WARN | Secret written in the overlay (properties or bean property) | key name | webapp/WEB-INF/conf |
| SI31 | WARN | Liberty `<variable>` named like a key of the site configuration: it wins at ordinal 500 | (custom check) | server.xml |
| SI32 | WARN | Properties file of the overlay (webapp or `src/conf/<env>`) under `WEB-INF/` where the core reads none: its keys apply nowhere | (path) | webapp, src/conf |
| SI40 | WARN | Plugin descriptor without `<name>.installed=1`: disabled on a new database | (custom check) | plugins.dat |
| SI41 | WARN | `plugins.dat` line naming no descriptor of the war | (custom check) | plugins.dat |
| SI42 | WARN | Plugins requiring a pool without `<name>.pool` | (custom check) | plugins.dat |
| SI43 | FAIL | `plugins.dat` line naming a renamed plugin by its former name (the plugin's SQL files still carry it) while the new name has no line: the plugin stays disabled, on a new database and on an updated one | SQL file names of the war | plugins.dat |
| SI44 | FAIL | No `plugins.dat` in the war while it ships plugins | (custom check) | plugins.dat |
| SI50 | WARN | Site file replacing a file of a dependency: to re-read against that dependency's version | dependency webapp zips | webapp |
| SI52 | FAIL | `?new` or `?api` in a template | `\?new\s*\(\|\?api\b` | templates |
| SI53 | FAIL | Macro or parameter removed from the v8 core (`initXssBypass`, `NbItemsPerPageSelector*`, `bypassXssFilter`) | (list) | templates |
| SI54 | FAIL | Copy of a core `commons*.html` or of the corporate theme | (path) | templates |
| SI55 | FAIL | `jsp:useBean` in a JSP of the site | `jsp:useBean` | jsp |
| SI56 | FAIL | v7 `web.xml` (javaee namespace, `AppInitListener`, Spring listener) | (custom check) | web.xml |
| SI57 | WARN | Same path shipped by two dependencies and not by the site: the unzip order between them is unspecified | dependency webapp zips | webapp |
| SI58 | FAIL | `plugins.dat` coming from a dependency, not from the site | dependency webapp zips | plugins.dat |
| SI60 | FAIL / INFO | A site set up for several replicas whose HTTP session is not shared (no sessionCache-1.0 nor sessionDatabase-1.0), or sessionCache-1.0 configured for Hazelcast without the hazelcast dependency; INFO for sessions in a database (the Hazelcast checks then do not apply) | (custom check) | server.xml, cluster.xml, pom.xml |
| SI61 | FAIL | httpSessionCache whose library is not every jar of the war (the members cannot migrate the partitions of the Lutece caches) or whose writeContents is not GET_AND_SET_ATTRIBUTES (a @SessionScoped bean modified in place is lost on a node switch) | (custom check) | cluster.xml |
| SI62 | FAIL | No `lutece.cache.jcache.cachingprovider`: the Lutece caches stay local to each replica | (custom check) | cluster.xml, server.xml, conf/override |
| SI63 | FAIL / WARN | Hazelcast member and client: a member `cache:` section (creates caches disabled in database), different cluster names (FAIL); graceful shutdown, JVM hook off, immediate invalidations, fixed port, Kubernetes discovery, near cache, client on its own pod member missing (WARN) | (custom check) | hazelcast-*-api-mode.yaml |
| SI64 | FAIL / WARN | jvm.options without `-Dhazelcast.jcache.provider.type=member` (no member starts, FAIL), without `hz.service-name` or the Hazelcast `--add-opens` (WARN) | (custom check) | jvm.options |
| SI65 | WARN | server.xml: persistTimeout not above the 60 s keep-alive of the load balancer, no `<remoteIp/>`, no bounded executor, no `maxPoolSize` on the data source | (custom check) | server.xml |
| SI66 | FAIL / WARN / INFO | No plugin-quartz-scheduler or no `quartzscheduler.cluster.enable=true` (the daemons run on every replica, FAIL); no exclusive daemon, or one no descriptor of the war declares (WARN); the daemons of the war left on every replica (INFO) | (custom check, the war for the daemon ids) | pom.xml, conf/override |
| SI67 | WARN | Packaging: Ehcache shipped next to Hazelcast, cluster.xml not included through the cluster.config variable, sessionCache-1.0 outside cluster.xml, Dockerfile without configure.sh | (custom check) | pom.xml, server.xml, Dockerfile |
| SI68 | WARN | Forms without `forms.index.writer.ms.timeout.lock`: a lock left by a stopped replica blocks the indexing 15 min | (custom check) | conf/override |
| SI70 | WARN | Kubernetes (--k8s): grace period below preStop + 45 s, no preStop, no startupProbe, liveness on /health/ready, Liquibase not disabled on the replicas, Forms index path or ReadWriteMany volume missing | text of the manifests | --k8s DIR |
| SI71 | WARN | Kubernetes (--k8s): no Role on endpoints, pods, services, or no Service on 5701, for the Hazelcast discovery | text of the manifests | --k8s DIR |
| SI72 | FAIL / WARN | Ingress (--k8s): affinity cookie named JSESSIONID, `non_idempotent` replay (FAIL); no `proxy-next-upstream` (WARN) | text of the manifests | --k8s DIR |
| SI80 | FAIL / INFO | Effective value the site set, or an artefact it added or removed, changed, or a key an added ConfigSource introduces that the war reads; the log4j keys of a `log.properties`, one decision per file; keys gone with a removed artefact (INFO) | two assembled states | effective configuration |
| SI81 | FAIL | Plugin shipped before, not after | two assembled states | WEB-INF/plugins |
| SI82 | FAIL | File of the site overlay no longer shipped, or no longer the site's | `--before-ref` | webapp |
| SI83 | WARN | Plugin shipped in a lower version after | two assembled states | WEB-INF/plugins |
| SI84 | FAIL | Profile named by the site before and not after, or the reverse | two assembled states | conf/override |
| SI85 | INFO | Defaults of the core or of the plugins that changed by themselves (listed in a file) | two assembled states | effective configuration |
| SI86 | WARN | Commits of another branch (a v7 branch) after the compared ref | `git rev-list` | git |
| SI87 | WARN | Key the static model resolves otherwise than the running site (`config --against`) | runtime dump | effective configuration |
| SI88 | FAIL | Two plain CDI beans of the war under one name (`@Named` without value on classes of the same simple name in two plugins): the site does not deploy, WELD-001414 | class-file annotations (needs --war) | jars of the war |
| SI89 | FAIL | Install script of the war (theme, site, pack) inserting a `core_datastore` key the core's `init_db_lutece_core.sql` already inserts, without a `DELETE` first: a new database fails on the duplicate key | `INSERT INTO core_datastore` (needs --war) | WEB-INF/classes/sql/**/init_*.sql |

---

## Summary

The counts come from `verify-migration.sh --json` (`.migration/verify-latest.json`, field `total`).

## verify-file.sh Check Mapping

| File type | Checks applied |
|-----------|---------------|
| `*.java` (main) | JX01-06, JX09, JP01, JP04, SP01-02, SP04, CD04, DA01, LG01; DP03, MV01 when the class is an `MVCAdminJspBean` / `MVCApplication` |
| `*.java` (test, under `src/test/`) | Above + TS01-04, TS08 |
| `*.html`, `*.ftl` (admin) | TM01, TM03, TM06 + the skin list |
| `*.html`, `*.ftl` (skin) | TM02 (FAIL without `library-theme-jquery` in the nearest `pom.xml`), TM04, TM07, TM10, TM11, TM12, TM09 |
| `*.jsp` | JS01, JS02 |
| `*.xml` (plugins) | WB02, WB04 |
| `web.xml` | WB01, WB03 |
| `pom.xml` | none: run `verify-migration.sh` and read the PM* lines |
