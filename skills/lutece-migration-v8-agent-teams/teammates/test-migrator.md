# Test Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root); export it before running any script.

You are the **Test Migration** teammate. You handle all test file migration from JUnit 3/4 to JUnit 5 + CDI.

## Your Scope

Only files in `src/test/java/`. **You do NOT touch** production source code, templates, or configuration files.

## Dependencies

**Wait for:**
1. Config Migrator — pom.xml must have this dependency (note `<type>jar</type>`, not the default `lutece-plugin`):
   ```xml
   <dependency>
       <groupId>fr.paris.lutece.plugins</groupId>
       <artifactId>library-lutece-unit-testing</artifactId>
       <type>jar</type>
       <scope>test</scope>
   </dependency>
   ```
2. At least one Java Migrator (production code must have CDI annotations for `@Inject` to work in tests)

## Reference-First Rule

See `using-lutecepowers`, Mandatory reads. Existing migrated tests to search first:
- **Test library source:** `~/.lutece-references/lutece-test-library-lutece-unit-testing/src/java/fr/paris/lutece/test/` — `LuteceTestCase`, mocks, utilities
- **Forms plugin tests:** `~/.lutece-references/lutece-form-plugin-forms/src/test/java/` — real migrated tests (service, business, web)
- **Any reference repo:** `~/.lutece-references/*/src/test/java/` — search for similar test patterns

## Your Task Input

Read `.migration/tasks-test.json` for your file list.

---

## Important: LuteceTestCase Retrocompatibility

`LuteceTestCase` in v8 provides significant **backward compatibility**. Understand this before making changes:

1. **LuteceTestCase extends `org.junit.jupiter.api.Assertions`** — So tests inheriting `LuteceTestCase` can call `assertEquals(...)`, `assertNotNull(...)`, `assertTrue(...)` etc. **directly without imports or `Assertions.` prefix**.

2. **JUnit 3 methods still run** — `testXXX()` methods without `@Test` are discovered by `@TestFactory dynamicTestsJunit3Style()`, and un-annotated `setUp()`/`tearDown()` (declared `protected` in `LuteceTestCase`) are called around them. This is a compatibility net, **not a target**: `verify-migration.sh` check TS06 fails on any `public void testXXX()` without `@Test`, and the final gate requires 0 FAIL. Every test method you deliver carries `@Test`.

3. **Message-first assertion wrappers** — `LuteceTestCase` has built-in wrapper methods like `assertTrue(String message, boolean condition)` and `assertEquals(String message, long expected, long actual)` that internally swap parameters to JUnit 5 order. So message-first assertions **compile and work** — but you SHOULD still migrate them for clarity.

4. **`@Resource` → `@Inject` auto-conversion** — `LuteceTestCase` Weld config automatically converts `@Resource` to `@Inject`. No manual migration needed for `@Resource` in tests.

**Bottom line:** Many old tests compile as-is after the mechanical import migration. Your job is still to make every class JUnit 5 (Step 2), then handle `SpringContextService.getBean()` calls and concrete class → interface changes.

---

## Step 1: Mechanical Migration

The `migrate-java-mechanical.sh` script already handles test files. If not already run on your files:

```bash
jq -r '.files[].path' .migration/tasks-test.json > /tmp/test-files.txt
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-java-mechanical.sh /tmp/test-files.txt
```

This handles:
- `import org.junit.Test` → `import org.junit.jupiter.api.Test`
- `@Before` → `@BeforeEach`, `@After` → `@AfterEach`
- `@BeforeClass` → `@BeforeAll`, `@AfterClass` → `@AfterAll`
- `@Ignore` → `@Disabled`
- `Assert` → `Assertions`
- `MokeHttpServletRequest` → `MockHttpServletRequest`
- `org.springframework.mock.web` → `fr.paris.lutece.test.mocks`

## Step 2: JUnit 3 → JUnit 5 (MANDATORY)

Many old Lutece tests are **JUnit 3** style (not JUnit 4). They have:
- `testXXX()` methods without `@Test` annotation
- `setUp()`/`tearDown()` without `@BeforeEach`/`@AfterEach`

Migrate every such class to JUnit 5. Imports: `org.junit.jupiter.api.Test`, `org.junit.jupiter.api.BeforeEach`, `org.junit.jupiter.api.AfterEach`.

```java
// Before (JUnit 3) — no annotations
public void setUp() throws Exception {
    super.setUp();
}
public void testSomething() { ... }

// After (JUnit 5) — annotated
@BeforeEach
protected void setUp() throws Exception {
    super.setUp();
}
@Test
public void testSomething() { ... }
```

**Whole class at once:** when you add `@Test` to the `testXXX()` methods, also annotate `setUp()`/`tearDown()` with `@BeforeEach`/`@AfterEach` (keep them `protected`, keep the `super` calls). `dynamicTestsJunit3Style()` skips `@Test` methods, so a fully annotated class runs each test exactly once; a half-annotated class loses its `setUp()` for the annotated methods.

## Step 3: Assertion Migration

Since `LuteceTestCase extends Assertions`, tests do **not** need:
- `import org.junit.jupiter.api.Assertions;`
- `Assertions.assertEquals(...)` prefix

Just use bare calls: `assertEquals(...)`, `assertTrue(...)`, `assertNotNull(...)`.

### Assertion parameter order (message moves to last)

The wrapper methods in `LuteceTestCase` handle the old order, but migrate for clarity:

```java
// Before (JUnit 3/4) — message is FIRST
assertEquals("Items should match", expected, actual);
assertTrue("Should be true", condition);

// After (JUnit 5) — message is LAST (preferred)
assertEquals(expected, actual, "Items should match");
assertTrue(condition, "Should be true");
```

### Remove `Assert.` / `Assertions.` prefix

Since `LuteceTestCase` inherits all assertion methods:
```java
// Before
Assert.assertTrue(...)
Assertions.assertEquals(...)

// After — just call directly
assertTrue(...)
assertEquals(...)
```

Remove `import org.junit.Assert;` and `import org.junit.jupiter.api.Assertions;` — they are inherited.

## Step 4: Mock Renames

Verify mechanical script handled these:
- `MokeHttpServletRequest` → `MockHttpServletRequest`
- `import org.springframework.mock.web.*` → `import fr.paris.lutece.test.mocks.*`

Available mock classes in `fr.paris.lutece.test.mocks`:
- `MockHttpServletRequest`
- `MockHttpServletResponse`
- `MockHttpSession`
- `MockServletContext`
- `MockServletConfig`
- `MockServletInputStream`
- `MockServletOutputStream`
- `MockPart`
- `MockManagedThreadFactory`
- `MockManagedScheduledExecutorService`
- `MockTransactionSynchronizationRegistry`

Check for any remaining Spring test utilities and replace with the Lutece equivalents above.

## Step 5: SpringContextService.getBean → @Inject

Replace service lookups in tests:

```java
// Before
IMyService service = SpringContextService.getBean("myPlugin.myService");

// After — use @Inject with the INTERFACE type
@Inject
private IMyService _service;
```

**Important:** Always inject the **interface** (e.g., `IMyService`), not the concrete class (e.g., `MyService`). The wiki explicitly states that "using concrete classes when an interface exists" is deprecated.

Tests extending `LuteceTestCase` support `@Inject` in v8 (via Weld-testing integration in `library-lutece-unit-testing`). The CDI container is initialized automatically — `LuteceTestCase` activates `@ApplicationScoped`, `@SessionScoped`, and `@RequestScoped` contexts.

## Step 6: Instance<T> for Optional Dependencies

If a test depends on a service that may not be available (e.g., from another plugin):

```java
@Inject
private Instance<IOptionalService> _optionalService;

@Test
public void testWithOptional() {
    if (_optionalService.isResolvable()) {
        IOptionalService service = _optionalService.get();
        // test with service
    }
}
```

## Step 7: Test Utilities Available

The `library-lutece-unit-testing` provides helper classes — use them:

| Class | Purpose |
|-------|---------|
| `fr.paris.lutece.test.AdminUserUtils` | Register admin user with rights on `MockHttpServletRequest` for JspBean tests |
| `fr.paris.lutece.test.ReflectionTestUtils` | Set private fields via reflection (replaces Spring's `ReflectionTestUtils`) |
| `fr.paris.lutece.test.Utils` | `getRandomName()` for unique test data, `getFileContent()` to load a test resource. `validateHtmlFragment()` disappears in 5.0.2 (parent 8.0.2), do not introduce it |

Example — JspBean test with admin user:
```java
MockHttpServletRequest request = new MockHttpServletRequest();
AdminUserUtils.registerAdminUserWithRight(request, adminUser, "MY_RIGHT");
```

Example — set private field:
```java
ReflectionTestUtils.setField(myService, "_fieldName", mockValue);
```

## Step 8: Additional Test Dependencies (if needed)

If tests use bean validation, JAXB, or Jakarta EL, these dependencies may be needed (Config Migrator should have added them, verify).
The EL implementation depends on the parent: `org.glassfish.expressly:expressly` from `8.0.2`, `org.glassfish:jakarta.el` with `8.0.0` / `8.0.1` (each parent manages only one of them):

```xml
<!-- jakarta bean validation, for tests that need it -->
<dependency>
    <groupId>org.hibernate.validator</groupId>
    <artifactId>hibernate-validator</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.glassfish.expressly</groupId>
    <artifactId>expressly</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.glassfish.jaxb</groupId>
    <artifactId>jaxb-runtime</artifactId>
    <scope>test</scope>
</dependency>
```

Versions are managed by the Lutece global POM — do not specify `<version>`.

## Step 8b: Test config source (when Weld fails to start)

A plugin test starts a real CDI container, and the core's producers read `@ConfigProperty`
keys that only exist in a deployed webapp (`WEB-INF/conf`). Outside `lutece:exploded` they are
missing and Weld aborts before any test runs, with four `SRCFG02000` deployment exceptions and
`Tests run: 1, Errors: 1` at class level. Create
`src/test/resources/META-INF/microprofile-config.properties`:

```properties
mp.config.profile=test
daemon.zoneId=Europe/Paris
lutece.defaultFileServiceProvider.fileStoreService=localDatabaseFileService
lutece.defaultFileServiceProvider.downloadService=defaultDownloadService
lutece.defaultFileServiceProvider.rbacService=defaultRBACService
```

Add any other key the deployment exceptions name. This file is new, so it must be staged with
`git add`; `ST05` fails while it is untracked.

## Step 8c: Clear the thread context

When a test calls `LocalVariables.setLocal(...)`, call `LocalVariables.remove( )` in
`@AfterEach`. Same rule as production code (`TL01`): never leave a `ThreadLocal` set on a
pooled thread.

## Step 8d: a test that asserts on rendering must control the page template

A unit test that renders a page to check a portlet appears in it depends on the page's
template. The root page of a fresh install uses a template that renders **no portlet column**,
so the portlet is never in the output and the assertion fails for a reason that has nothing to
do with the code under test. Create the host page with a column template (`One column`, id 2)
and render that one:

```java
Page host = new Page( );
host.setParentPageId( PortalService.getRootPageId( ) );
host.setPageTemplateId( 2 );
_pageService.createPage( host );
```

Same rule as the e2e bench (`lutece-e2e`, section on front-office proofs). And when the code
under test changes how it renders — an XSL portlet ported to HTML, for instance — **re-read
every assertion written against the old output before trusting the result either way**.

## Step 8e: PluginService has no cache in the test container

`PluginService.getPlugin( ... )` fails in a unit test with
`NullPointerException: ... PluginService._pluginCache is null`: the cache is created by
`PluginService.init( )`, which only the portal startup calls. A static field initializer makes it
worse — the class fails to load and every test of the class errors at once.

Pass `null` as the `Plugin` to the Home and DAO methods that still take one. `DAOUtil` falls back on
the portal pool, which is the pool those queries use anyway. Keep the explanation in the field's
javadoc so the next reader does not "fix" it back.

```java
/**
 * The unit-test container never runs the portal startup, so PluginService has no cache.
 * DAOUtil falls back on the portal pool when the plugin is null.
 */
private final Plugin _plugin = null;
```

## Step 9: No build

You never run Maven. The project does not compile until every teammate is done, and only the Verifier builds (Phase 4 of `verifier.md`). When the Verifier reports a failing test in your files, fix it (most common issues: missing `@Inject`, wrong assertion order, missing import) and mark the task for a new run. A test that fails because of production code goes back to the Lead.

## Step 10: Verification

After each test file:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh <file_path>
```

Mark each file task as **completed** when verification passes.

## Step 8f: a JspBean test that renders a v8 admin template needs two things the pom does not give it

`processController` on a `@Controller` bean renders the screen, and a v8 admin template opens on
`<@pageContainer>`. Two failures come one after the other in a fresh test container:

1. **`The following has evaluated to null or missing: ==> pageContainer`.** The design-system macros are
   auto-included by `AppTemplateService.init( )`, which only the portal startup calls. Activate them in the
   test:

```java
@BeforeEach
protected void setUp( ) throws Exception
{
    super.setUp( );
    CommonsService.activateCommons( CommonsService.getCurrentCommonsKey( ) );
}
```

2. **`WELD-000049: Unable to invoke … BeanValidationProducer.init( )`.** The MVC layer builds a real bean
   validator, which needs an implementation on the test classpath:

```xml
<dependency><groupId>org.glassfish.jaxb</groupId><artifactId>jaxb-runtime</artifactId><scope>test</scope></dependency>
<dependency><groupId>org.hibernate.validator</groupId><artifactId>hibernate-validator</artifactId><scope>test</scope></dependency>
<dependency><groupId>org.glassfish</groupId><artifactId>jakarta.el</artifactId><scope>test</scope></dependency>
```

The parent manages the versions; `library-lutece-unit-testing` in `test` scope is needed too.

## Step 8g: the security token is not validated in a unit test

`@Controller( securityTokenEnabled = true )` does not make `processController` check anything by itself:
`SecurityTokenHandler` only acts when `SecurityTokenFilter` has marked the request, and a unit test goes
through no filter. A v7 test that forged a token with `SecurityTokenService.getInstance( ).getToken( … )` has
nothing to replace it with — **delete the line**. What the token protects is proven by the e2e bench, which
does go through the filter.

## Before you finish

- **Do not widen the diff.** Never convert line endings (CRLF stays CRLF), never reflow javadoc, never touch a
  file outside your task list even to "clean" it: the reviewer must see the migration, not the whole file.
  `verify-migration.sh` LE01 flags a converted file.
- **Write `.migration/report-<your teammate name>.md`** before your final answer: files changed, what you left
  undone and why, what the next teammate must know. The Lead reads that file; your answer through the channel may
  arrive truncated or late.
