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
| PM05 | WARN | json-lib (use Jackson) | `net\.sf\.json-lib` | pom.xml |
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
| CA04 | WARN | Missing isCacheAvailable guard | (cross-file check) | *.java |

## Deprecated API (DP)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DP01 | FAIL | getInstance() calls | (long pattern for known services) | *.java |
| DP02 | FAIL | Deprecated init() calls | `FileImagePublicService\.init\|FileImageService\.init` | *.java |
| DP03 | FAIL | getModel() usage | `getModel( )` | *.java |

## DAO (DA)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| DA01 | WARN | daoUtil.free() | `daoUtil\.free( )` | *.java |

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
| CD01 | WARN | Static _instance on CDI classes | (cross-file check) | *.java |
| CD02 | FAIL | new CaptchaSecurityService() | `new CaptchaSecurityService()` | *.java |
| CD03 | WARN | CompletableFuture.runAsync | `CompletableFuture\.runAsync` | *.java |
| CD04 | FAIL | commons.fileupload | `org\.apache\.commons\.fileupload` | *.java |
| CD05 | WARN | Constructor self-registration (lazy CDI bean) | `registerIndexer\|registerCacheableService\|registerProvider` in files without `@Observes @Initialized` | *.java |

## MVC / New Patterns (MV) — v2 additions

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| MV01 | FAIL | new HashMap in JspBean/XPage | `new HashMap` in MVCAdminJspBean/MVCApplication files | *.java |
| MV02 | WARN | AbstractPaginatorJspBean | `AbstractPaginatorJspBean` | *.java |
| MV03 | WARN | Explicit CSRF token | `SecurityTokenService\.MARK_TOKEN` | *.java |
| MV04 | FAIL | FileItem (not MultipartItem) | `import.*FileItem[^P]` | *.java |

## Web / Config (WB)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| WB01 | FAIL | Old Java EE namespace | `java\.sun\.com/xml/ns/javaee` | webapp/*.xml |
| WB02 | FAIL | application-class | `<application-class>` | plugins/*.xml |
| WB03 | FAIL | ContextLoaderListener | `ContextLoaderListener` | web.xml |
| WB04 | WARN | min-core-version not 8.0.0 | (custom check) | plugins/*.xml |

## Structure (ST)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| ST01 | FAIL | beans.xml exists | (file existence check) | META-INF/beans.xml |
| ST02 | WARN | final on CDI classes | (cross-file check) | *.java |
| ST03 | WARN | DAO without CDI scope | (cross-file check) | *.java |
| ST04 | WARN | Service without CDI scope | (cross-file check) | *.java |

## JSP (JS)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| JS01 | FAIL | jsp:useBean | `jsp:useBean` | *.jsp |
| JS02 | WARN | JSP scriptlets | `<%[^@-]` | *.jsp |

## Templates (TM)

| ID | Severity | Description | Pattern | Files |
|----|----------|-------------|---------|-------|
| TM01 | WARN | Old Bootstrap panels | `class="panel` | admin/*.html |
| TM02 | WARN | jQuery usage | `jQuery\|\$(` | *.html |
| TM03 | WARN | Old upload macros | (custom check) | *.html |
| TM04 | FAIL | Unsafe errors/infos/warnings | (custom check) | *.html |
| TM05 | FAIL | Old SuggestPOI | `autocomplete-js\.jsp\|createAutocomplete` | *.html, *.jsp |
| TM06 | FAIL | @addRequiredJsFiles (not BO) | (custom check) | admin/*.html |
| TM07 | FAIL | MVCMessage `${error}` without `.message` | `${error}` not followed by `.` or `!` | *.html |

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

---

## Summary

| Severity | Count |
|----------|-------|
| FAIL | 63 |
| WARN | 23 |
| **Total** | **86** |

Counts taken from a `verify-migration.sh --json` run (`.migration/verify-latest.json`, field `total`).

## verify-file.sh Check Mapping

| File type | Checks applied |
|-----------|---------------|
| `*.java` (main) | JX01-09, JP01, JP04, SP01-02, SP04, CD04, DA01, LG01, DP03, MV01 (if JspBean/XPage) |
| `*.java` (test) | Above + TS01-08 |
| `*.html` (admin) | TM01, TM02, TM04, TM06 |
| `*.html` (skin) | TM02, TM04 |
| `*.jsp` | JS01, JS02 |
| `*.xml` (plugins) | WB02, WB04 |
| `web.xml` | WB01, WB03 |
| `pom.xml` | PM01-PM12 |
