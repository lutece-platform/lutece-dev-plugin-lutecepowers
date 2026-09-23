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

---

## POM Dependencies (PM)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| PM01 | FAIL | Spring dependencies in pom.xml | `org\.springframework` | pom.xml |
| PM02 | FAIL | EhCache dependencies in pom.xml | `net\.sf\.ehcache` | pom.xml |
| PM03 | FAIL | javax.mail dependency | `com\.sun\.mail` | pom.xml |
| PM04 | FAIL | Jersey dependencies | `org\.glassfish\.jersey` | pom.xml |
| PM05 | FAIL | json-lib (use Jackson) | `net\.sf\.json-lib` | pom.xml |
| PM06 | FAIL | Parent version must start with `8.` | (custom check) | pom.xml |
| PM07 | FAIL | springVersion property | `<springVersion>` | pom.xml |
| PM08 | WARN | Jira properties (remove) | `<jiraProjectName>\|<jiraComponentId>` | pom.xml |
| PM09 | WARN | Bounded version range (use open) | `,[0-9].*)</version>` | pom.xml |
| PM10 | FAIL | EL implementation not managed by the parent: `org.glassfish:jakarta.el` with parent ≥ 8.0.2, or `org.glassfish.expressly:expressly` with parent 8.0.0 / 8.0.1 | (custom check, parent-aware) | pom.xml |
| PM11 | WARN | Explicit `<version>` on a parent-managed dependency (`jboss-logging`, `jakarta.el-api`, `jakarta.annotation-api` only from parent 8.0.2) | (custom check, ignores `<dependencyManagement>`) | pom.xml |
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

## Spring Residues (SP)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| SP01 | FAIL | SpringContextService | `SpringContextService` | *.java |
| SP02 | FAIL | Spring imports | `org\.springframework` | *.java |
| SP03 | FAIL | Spring context XML files | `_context\.xml` | webapp/*.xml |
| SP04 | FAIL | @Autowired | `@Autowired` | *.java |
| SP05 | FAIL | InitializingBean | `implements.*InitializingBean` | *.java |
| SP06 | FAIL | Named @Component | `@Component(` | *.java |
| SP07 | FAIL | Named @Service | `@Service(` | *.java |
| SP08 | FAIL | Named @Repository | `@Repository(` | *.java |

## Deprecated Libraries (DL)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DL01 | FAIL | net.sf.json (use Jackson) | `net\.sf\.json` | *.java |

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
| CA03 | FAIL | Raw AbstractCacheableService | `extends AbstractCacheableService[^<]` | *.java |
| CA04 | WARN | Missing isCacheEnable guard | (cross-file check) | *.java |

## Deprecated API (DP)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DP01 | FAIL | getInstance() calls | (long pattern for known services) | *.java |
| DP02 | FAIL | Deprecated init() calls | `FileImagePublicService\.init\|FileImageService\.init` | *.java |
| DP03 | FAIL | getModel() usage | `getModel( )` | *.java |

## DAO (DA)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DA02 | FAIL | `new DAOUtil(` outside a try-with-resources: the connection leaks on an exception | line without `try (`, except a method returning the DAOUtil it built | *.java |
| SQ05 | FAIL | value concatenated into a SQL literal in a DAO (`"… LIKE '%" + str`): injection point | `'\" +` in *DAO.java | *DAO.java |
| DA01 | FAIL | daoUtil.free() | `daoUtil\.free( )` | *.java |

## JPA (JP)

Rules in `patterns/persistence-patterns.md`: the API only, the provider of the container (EclipseLink, `persistence-3.1`).

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JP01 | FAIL | Hibernate imports | `import org\.hibernate\.[^v]` (hibernate-validator excluded) | *.java |
| JP02 | FAIL | JPA provider in pom.xml | `hibernate-core\|hibernate-entitymanager\|module-jpa-hibernate\|spring-orm\|spring-data-jpa` | pom.xml |
| JP03 | FAIL | Hibernate settings in persistence.xml | `hibernate\.\|HibernatePersistenceProvider` | persistence.xml |
| JP04 | FAIL | Parenthesised collection parameter | `IN (:\|IN (?\|IN(:\|IN(?` | *.java |
| JP05 | WARN | Named parameters in native SQL | `:name` inside string literals of files calling `createNativeQuery` (heuristic) | *.java |
| JP06 | WARN | shared-cache-mode missing | `<shared-cache-mode>` absent | persistence.xml |
| JP07 | WARN | persistenceContainer-3.1 feature | `persistenceContainer-3\.1` | server.xml |

## CDI Patterns (CD)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| CD01 | FAIL | Static _instance on CDI classes | (cross-file check) | *.java |
| CD02 | FAIL | new CaptchaSecurityService() | `new CaptchaSecurityService()` | *.java |
| CD03 | WARN | CompletableFuture.runAsync | `CompletableFuture\.runAsync` | *.java |
| CD04 | FAIL | commons.fileupload | `org\.apache\.commons\.fileupload` | *.java |
| CD05 | WARN | Constructor self-registration (lazy CDI bean) | `registerIndexer\|registerCacheableService\|registerProvider` in files without `@Observes @Initialized` | *.java |

## MVC / New Patterns (MV) — v2 additions

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| MV01 | FAIL | new HashMap in JspBean/XPage | `new HashMap` in MVCAdminJspBean/MVCApplication files | *.java |
| MV02 | FAIL | AbstractPaginatorJspBean | `AbstractPaginatorJspBean` | *.java |
| MV03 | WARN | CSRF token carried by hand inside an MVC bean, or `securityTokenEnabled = false` | `SecurityTokenService\.MARK_TOKEN` in a file that has `@Controller` / `MVCAdminJspBean` / `MVCApplication` | *.java |
| MV04 | FAIL | FileItem (not MultipartItem) | `import.*FileItem[^P]` | *.java |
| MV05 | WARN | `@View` calling an `@Action` method of its bean: the write runs on a GET, which the token filter never checks | body of each `@View` method naming an `@Action` method of the same file | *.java |

## Web / Config (WB)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| WB01 | FAIL | Old Java EE namespace | `java\.sun\.com/xml/ns/javaee` | webapp/*.xml |
| WB02 | FAIL | application-class | `<application-class>` | plugins/*.xml |
| WB03 | FAIL | ContextLoaderListener | `ContextLoaderListener` | web.xml |
| WB04 | WARN | min-core-version not 8.0.0 | (custom check) | plugins/*.xml |
| WB05 | FAIL | descriptor filter under /rest/ | (custom check) | plugins/*.xml |

**WB05** — a `<filters>` entry of the plugin descriptor whose `<url-pattern>` is deeper than `/rest/*`. It cannot
fire in v8: `MainFilter.matchMapping` compares the pattern to `request.getServletPath( )`, which is `/rest` for
every call routed to the application mounted by `@ApplicationPath( "/rest/" )`, the rest of the url being in
`getPathInfo( )`. The filter is still read, instantiated and registered — the log even says
`New Filter registered` — and it simply never runs. Measured on one bench, same module and same descriptor: an
unsigned call answers **401** on the v7 leg and **200** on the v8 one.

FAIL rather than WARN because the failure is silent and it opens whatever the filter protected. Removing the block
is only half the fix: replace it with the `@NameBinding` `ContainerRequestFilter` of `rest-patterns.md` §3, with
the same parameters, so the contract holds even though the mechanism changed. Declaring a REST filter in the
descriptor is over — the core is not going back to it, so there is nothing to wait for. `/rest/*` itself still matches and is
not reported, nor is any pattern outside `/rest/` — a filter on `/jsp/site/*` works as before.

## Structure (ST)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| ST01 | FAIL | beans.xml exists | (file existence check) | META-INF/beans.xml |
| ST02 | FAIL | final on a CDI class resolved by its concrete type | (cross-file check) | *.java |
| ST03 | FAIL | DAO without CDI scope | (cross-file check) | *.java |
| ST04 | FAIL | Service without CDI scope | (cross-file check) | *.java |
| ST05 | FAIL | files created by the migration excluded by .gitignore (they would never be committed) | `git check-ignore` | beans.xml, test microprofile-config |
| LE01 | FAIL | line endings converted in a changed file (diff widened to the whole file) | carriage returns in HEAD vs the work tree | changed files |

**MV03** — an MVC bean gets its token from the framework, so a token put in the model or validated by hand
there means the framework's own is off or duplicated. A bean that is not MVC — a portlet admin bean, a servlet —
has no framework token and must carry it by hand: that is the pattern, not a finding, and the check leaves it
alone. `securityTokenEnabled = false` is always a finding.

**XT02 / XT03** — a plugin that keeps XSL rendering depends on plugin-xmltransformer, so its install scripts
must run after that plugin (`runAfter`) and its old upgrade scripts must not fail where the style tables are gone
(a guarded changeset). A plugin that ported its portlet to HTML removes the statements instead (XT01). Recipe and
exact syntax in `sql-liquibase.md`.

**SQ03** — MariaDB renumbers an id 0 when the column becomes AUTO_INCREMENT and fails on the duplicate. The
ALTER belongs in a `dbms:mariadb,mysql` changeset after `SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO'`.
A WARN says the guard is missing; a FAIL says the install data really ships a 0, so every existing site breaks.

**LE01** — the fix is `scripts/restore-line-endings.sh`: it puts back the endings HEAD has on every changed file
whose endings moved, whatever else changed in it, and touches nothing else. A file that carries real changes on
top of the conversion is the one where this matters most: its migration is buried under a rewrite of every line.
Run it before the final gate, then verify again: a review that has to read a whole rewritten file does not happen.

**ST02** — `final` is legal and is the core's own pattern when the bean is resolved only
through its interface (`@ApplicationScoped public final class XDAO implements IXDAO`, twelve
such classes in lutece-core). The check only fails when the code injects or selects the
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

**SQ02** — a fresh install runs the creation script and is green; an existing site runs only the
`update_db_*` scripts newer than its recorded version. An older upgrade that (re)creates the table
without the column does not count. Rules and model in `rules/sql-liquibase.md`.

## v8 core changes (XS, TL)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| XS01 | FAIL | portlet still rendered by XSL | (cross-file check) | *.java, src/sql, *.xsl |
| XT01 | FAIL | XSL services or `core_style*` tables used without `plugin-xmltransformer` declared | (cross-file check) | *.java, src/sql, pom.xml |
| XT02 | FAIL | install script writing `core_style*` without `-- lutece runAfter:xmltransformer`, when the pom declares plugin-xmltransformer | header grep | src/sql (not upgrade) |
| XT03 | FAIL | upgrade statement on `core_style*` in a changeset without `precondition-sql-check` | per-changeset scan | src/sql/**/upgrade |
| CS02 | FAIL | content service calling the cache methods v8 removed from `ContentService` | `extends ContentService` + `initCache\|getFromCache\|putInCache` | *.java |
| TL01 | FAIL | ThreadLocal not cleared with remove() | (cross-file check) | *.java |
| CS01 | FAIL | portlet JspBean mutations without a CSRF token | (cross-file check) | *.java |
| I18N01 | FAIL | i18n key repeating the plugin prefix | (cross-file check) | *_messages*.properties |
| I18N03 | FAIL | i18n key in the default bundle and not in `_fr`, or the reverse (the two languages the core ships) | (cross-file check) | *_messages*.properties |
| I18N04 | WARN | the other languages of a bundle lack keys of the default bundle | (cross-file check) | *_messages_*.properties |
| I18N05 | FAIL | bundle suffixed with a country code (`_cz`, `_dk`, `_se`…) where Java expects a language code (`_cs`, `_da`, `_sv`): never loaded | file names | *_messages_*.properties |
| I18N06 | FAIL | bundle line without `=`/`:` separator (`key>value`): read as a key with an empty value | line scan | *_messages*.properties |
| I18N09 | WARN | translation key the default bundle does not declare (translated key name, key renamed or removed since): never shown | (cross-file check) | *_messages_*.properties |
| I18N07 | WARN | French value with a common spelling error (`Etes vous`, `sur de vouloir`) or a leftover Java class name after an article (`un PollFormQuestion`) | decoded `_fr` values | `*_messages_fr.properties` |
| I18N08 | WARN | Bundle key nothing uses (`i18n_unused.py`): no project file names `<prefix>.<key>` or `"<key>"`, no literal or `${` stem builds it, no reference repository names it; runtime families (`model.entity.*`, `validation.*`, `site_property.*`) are kept | default bundles vs every tracked text file | `*_messages.properties` |
| I18N02 | WARN | i18n key asked for by a template, a message constant, a label tag of the plugin descriptor or a `core_admin_right`/`core_portlet_type` row, declared in no bundle | (cross-file check) | webapp, src/java |
| I18N10 | WARN | key declared twice in the same bundle: `java.util.Properties` keeps the last value, the first never shows | (cross-file check) | *_messages*.properties |

**XS01** — **An XSL portlet must be ported to HTML during the migration; there is no second
option.** `core_style`, `core_style_mode_stylesheet` and `core_stylesheet` left the core for
`plugin-xmltransformer`, the core's `PortletStyleDAO` is a stub returning `null` and an empty
`ReferenceList`, and since `LUT-32172` the back office cannot even create an XSL portlet whose
type is not `DOCUMENT*`: the style select is rendered under
`<#if portletType.id?starts_with('DOCUMENT')>` so no `style` is posted, and
`setPortletCommonData` returns `MANDATORY_FIELDS` — the `return` is outside the test for the
xmltransformer plugin, so installing it changes nothing but a log line. Symptoms when nothing
is done: the portlet renders an empty string with no error, the install fails on missing
tables, and creating one from the back office is impossible. The check fails on a portlet class
that still defines `getXml`/`getXmlDocument` without extending `PortletHtmlContent`, and on any
`INSERT INTO core_style*` left in `src/sql`. The port is in `mvc-patterns.md` §10.

**TL01** — always `ThreadLocal.remove()` in a `finally`, never a reassignment such as
`set(false)`. A reassignment keeps one entry per pooled thread for the whole application
lifetime (LUT-31201). The rule already existed in the scalability skill, which does not run
during a migration, so it is enforced here too.

**CS01** — the v8 automatic token filter only covers MVC controllers (`@Action` / `@View`), and
the core's `create_portlet.html` / `modify_portlet.html` emit no token, so every `do*` of a
`PortletJspBean` accepts a forged call. The plugin closes it alone: its `create_specific`
template is included *inside* the core form and `getCreateTemplate` / `getModifyTemplate` take a
model. The check fails on a class extending `PortletJspBean` that never calls
`getSecurityTokenService( ).validate( request, … )`. Recipe and traps in `mvc-patterns.md` §11.

**I18N01** — keys in `<plugin>_messages.properties` are relative to the bundle, so
`<plugin>.message.x` written there resolves as `<plugin>.<plugin>.message.x` and renders
as the raw key: nothing fails and nothing logs. The same grep catches a key appended without a
trailing newline, glued to the value of the line above, which corrupts both entries.
`scripts/fix-i18n-bundles.py <project>` repairs I18N01, I18N05, I18N06, I18N09 and I18N10 in place (`--dry-run` to list).

**I18N02** — a `#i18n{...}` of a template, or a `MESSAGE_*` / `INFO_*` / `ERROR_*` / `TITLE_*` constant, naming a
key no bundle declares: Lutece prints the raw key on the screen and nothing fails at build time. WARN, because
most of these predate the migration. Only the plugin's own prefix is checked, and only those two sources — bean
names and CSRF action names are strings of the same shape and are not keys. Every grep of the check passes `-a`:
a bundle saved in ISO-8859 counts as binary for grep, which then reports nothing at all — the same trap turns a
manual search in those files into a false "the key is missing".

**A sweep that finds nothing has to be trusted, so do not sweep with a bare `grep -r`.** In an interactive shell
`grep` is often a function or an alias over ripgrep or ugrep, which skip dotted files and directories and honour
`.gitignore` by default: `.migration/`, `.settings/` and anything the project ignores are searched silently past.
The scripts are safe — a shell function is not exported to `bash script.sh` — but a teammate checking its own work
is not. When the answer "nothing left" is the point of the search, run it as
`find . -type f -print0 | xargs -0 grep -an <pattern>`.

## JSP (JS)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JS01 | FAIL | jsp:useBean | `jsp:useBean` | *.jsp |
| JS02 | FAIL | JSP scriptlets | `<%[^@-]` | *.jsp |
| SQ04 | FAIL | `INSERT INTO core_x VALUES (…)` without a column list: fails as soon as the core adds a column (core_portlet.id_template in 8.0.2) | `INSERT +INTO +core_[a-z0-9_]+ +VALUES` | src/sql |
| JS06 | FAIL | JSP streaming a file (download, export) that leaves template text, a newline between its directives included (`trimDirectiveWhitespaces` does not remove it on Liberty): "OutputStream already obtained" on every download | (cross-file check) | *.jsp |
| JS07 | FAIL | static script of the plugin that does not parse (`node --check`): the browser drops the whole file | node --check | webapp/**/*.js (outside WEB-INF, not *.min.js) |
| JS05 | FAIL | admin JSP writing its own HTML (`<form>`, `<table>`, `<div>`…): the screen belongs in a template rendered by a `@View` | markup tags in webapp/jsp/admin | *.jsp |
| WB06 | FAIL | `<admin-feature>` whose `<feature-group>` differs from the group its install SQL gives: a reinstall rebuilds the right from the descriptor and moves it | (cross-file check) | plugins/*.xml |
| WB07 | WARN | admin feature icon in `<feature-icon-url>`, which the core digester ignores (it reads `<icon-url>`): a reinstall loses the icon | (cross-file check) | plugins/*.xml |
| ST07 | FAIL | production class named like a test (`Test*`, `*Test`, `*Tests`, `*TestCase`) under src/java: surefire collects it from WEB-INF/classes | file names | src/java |
| PV01 | FAIL | pom version and plugin descriptor `<version>` differ | (cross-file check) | pom.xml, plugins/*.xml |
| PV02 | FAIL | version not above the last released git tag: an upgraded site never runs the new upgrade scripts | `git tag` | pom.xml |
| JS04 | FAIL | admin JSP driving a bean that is not a `@Controller` (legacy `DoXxx.jsp`, portlets excepted): no v8 dispatch, no automatic CSRF | (cross-file check) | *.jsp, *.java |

## Templates (TM)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| TM01 | FAIL | Old Bootstrap panels | `class="panel` | admin/*.html |
| TM02 | FAIL | jQuery in a template with no `library-theme-jquery` in the pom (WARN when declared): nothing loads it, the script dies | `jQuery\|\$(` | templates |
| VL01 | FAIL | a copy of jQuery, of a jQuery plugin (a `.js` defining `$.fn.x`) or of a jQuery-era upload widget under `webapp/` | file names, `$.fn.` in *.js | webapp/ |
| TM10 | FAIL | offcanvas (`@offcanvas`, `@cOffcanvas`, offcanvas markup): the content of the page goes in a `@modal` / `@cModal`, another page is reached by a plain link | `template_rules.py offcanvas` | admin, skin |
| TM11 | FAIL | front-office form that is not a `@cForm` (raw `<form>`, `@tform`) or `foValidation=false`: no core form validation | `template_rules.py fo-forms` | skin |
| TM12 | FAIL | inline form: three visible fields or more side by side (`@tform type` inline/flex, `form-inline`/`d-flex` on the form, `formStyle='inline'`, a row of three field columns); two columns are fine | `template_rules.py inline-forms` | admin, skin |
| TM13 | FAIL | back-office form field named `page`: the core takes its XPage branch and skips the CSRF check on every post | `name='page'` | admin/*.html |
| TM03 | FAIL | Old upload macros | (custom check) | *.html |
| TM04 | FAIL | Unsafe errors/infos/warnings | (custom check) | *.html |
| TM05 | FAIL | Old SuggestPOI | `autocomplete-js\.jsp\|createAutocomplete` | *.html, *.jsp |
| TM06 | FAIL | @addRequiredJsFiles (not BO) | (custom check) | admin/*.html |
| TM07 | FAIL | MVCMessage `${error}` without `.message` | `${error}` not followed by `.` or `!` | *.html |
| TM08 | WARN | Design rules a macro-written template still breaks (entity list in `@table`, list without `@empty`, `@checkBox` without switch or without an explicit value, raw HTML, undeclared or repeated macro parameter, a script looking up an element the template only emits under a condition, a link to a JSP the webapp does not carry, a jQuery-era upload widget, a vendored copy of jQuery, Bootstrap 3/4 or Font Awesome markup, an unstyled btn-default button, BO macro in skin, image icon in `core_admin_right`, jQuery without a `library-theme-jquery` dependency, offcanvas, a front-office form without `@cForm`, an inline form) | `scan-template-design.py --flat --warn-only` (codes TD01…TD55 in its header; needs the assembled webapp, see `ensure-exploded.sh`) | admin/*.html, skin/*.html, src/sql |
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
| TS06 | FAIL | Test methods without @Test | (cross-line check) | *.java (test) |
| TS07 | FAIL | SpringContextService in tests | `SpringContextService\.getBean` | *.java (test) |
| TS08 | FAIL | Spring mock imports | `org\.springframework\.mock\.web` | *.java (test) |
| TS09 | FAIL | Failing tests in the surefire reports (the parent POM sets `testFailureIgnore=true`, so `BUILD SUCCESS` proves nothing; FAIL too when no report: the tests were never run; the command is `mvn lutece:exploded antrun:run -Dlutece-test-hsql test`) | `target/surefire-reports/*.txt` | test results |

---

## Summary

The counts come from `verify-migration.sh --json` (`.migration/verify-latest.json`, field `total`).

## verify-file.sh Check Mapping

| File type | Checks applied |
|-----------|---------------|
| `*.java` (main) | JX01-09, JP01, JP04, SP01-02, SP04, CD04, DA01, LG01, DP03, MV01 (if JspBean/XPage) |
| `*.java` (test) | Above + TS01-08 |
| `*.html` (admin) | TM01, TM02, TM04, TM06, TM09 |
| `*.html` (skin) | TM02, TM04, TM09 |
| `*.jsp` | JS01, JS02 |
| `*.xml` (plugins) | WB02, WB04, WB05 |
| `web.xml` | WB01, WB03 |
| `pom.xml` | PM01-PM12 |
