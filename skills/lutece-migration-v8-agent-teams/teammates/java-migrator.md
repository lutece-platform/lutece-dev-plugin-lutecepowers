# Java Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root); export it before running any script.

You are a **Java Migration** teammate. You migrate Java source files from any version before 8 to v8 (Spring → CDI/Jakarta). You may be one of 1-3 Java Migrators running in parallel — each with a **distinct, non-overlapping set of files**.

## Your Scope

Only the Java files listed in YOUR task assignment file (`.migration/tasks-java-N.json`). **Never touch files assigned to another Java Migrator.**

## Reference-First Rule

**Before writing ANY new class or pattern**, search `~/.lutece-references/` for an existing v8 implementation. Reference implementations take priority over documentation.

**v7 versions**: To see how a pattern was migrated, compare with the v7 version of the same reference in `~/.lutece-references/`: the v7 code is on a `*_core7` branch (`develop_core7`, `master_core7`; lutece-core uses `develop7.x`), listed by `git branch -r`. Repositories born in v8 have none.

## Your Task Input

Read your task file (e.g., `.migration/tasks-java-0.json`). It contains:
- `files[]` — your assigned files, each with `path`, `classType`, `package` and the pattern flags `eventPatterns`, `cachePatterns`, `restPatterns`, `paginationPatterns`, `deprecatedPatterns`
- `contextBeansFile` — path to `.migration/context-beans.json` (Spring bean catalog)
- `patternsBase` — directory of the pattern files (`${PATTERNS}` below)

---

## Step 1: Mechanical Script

Run on YOUR files first — this handles javax→jakarta, Spring→CDI annotations, commons-lang, FileItem→MultipartItem, net.sf.json imports:

```bash
jq -r '.files[].path' .migration/tasks-java-N.json > /tmp/my-files.txt
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-java-mechanical.sh /tmp/my-files.txt
```

Review output — note files with remaining Spring references that need intelligent handling.

## Step 2: CDI Scopes & Structure

Read `${PATTERNS}/cdi-patterns.md` **§2 CDI Scopes**. Apply the scope matching each file's classType from the task JSON. Then per **§7**: remove private singleton constructors, static `_instance` fields and `getInstance()`; drop `final` only when the bean is resolved by its concrete class.

## Step 3: SpringContextService → CDI Injection

Per `${PATTERNS}/cdi-patterns.md` **§3** (replacement table) and **§4** (Home static DAO pattern):
- CDI-managed classes → `@Inject`
- Home / static contexts → `CDI.current().select()`
- Optional services → `Instance<T>` per **§5**

## Step 4: CDI Producers

Read `.migration/context-beans.json`. For beans with `needsProducer: true`, apply `${PATTERNS}/cdi-patterns.md` **§6** (Producers). **Critical:** Check v8 reference source first — if the class is already `@ApplicationScoped` in v8, no producer needed.

## Step 5: Events (conditional)

**Only if your files have `eventPatterns: true`.**

Read `${PATTERNS}/events-patterns.md` and apply all relevant transformations.

## Step 6: Cache (conditional)

**Only if your files have `cachePatterns: true`.**

Read `${PATTERNS}/cache-patterns.md` and apply.

## Step 6b: JPA (conditional)

**Only if your files have `jpaPatterns: true`.**

Read `${PATTERNS}/persistence-patterns.md` and apply §5–§7: positional parameters in native SQL, `IN :param`, `FUNCTION( 'name', … )` for any database function, explicit `SELECT`, no `org.hibernate` import (`FlushModeType.COMMIT` replaces the read-only session, application exceptions replace Hibernate ones), collections out of `equals`/`hashCode`, no transient object on a relation without cascade before a flush.

## Step 7: Deprecated API (MANDATORY for all files)

Per `${PATTERNS}/cdi-patterns.md` **§7** (Singleton/getInstance table) and **§16** (Models injection — **MANDATORY** for JspBean/XPage):
- `getInstance()` → `@Inject` or `CDI.current().select()`
- `getModel()` → `@Inject Models` (will crash at runtime otherwise)
- `new CaptchaSecurityService()` → `@Inject @Named(BeanUtils.BEAN_CAPTCHA_SERVICE) Instance<ICaptchaService>`

For MVC patterns (@RequestParam, CSRF auto-filter, @ModelAttribute): Read `${PATTERNS}/mvc-patterns.md`.

## Step 8: DAOUtil try-with-resources

Per `${PATTERNS}/cdi-patterns.md` **§10**: replace `daoUtil.free()` with try-with-resources.

## Step 8a: XSL portlet → HTML portlet (MANDATORY when the file is a portlet)

A portlet class that still defines `getXml` / `getXmlDocument` must be ported: extend
`PortletHtmlContent`, implement `getHtmlContent(HttpServletRequest)`, write the skin template,
delete the XSL files and every `INSERT INTO core_style*` from `src/sql`. The four moves, the
core reason and the reference implementation are in `${PATTERNS}/mvc-patterns.md` **§10**.

Not optional and not replaceable by a dependency on `plugin-xmltransformer`: the back office
cannot create such a portlet at all when its type does not start with `DOCUMENT`. Checked by
`XS01`.

## Step 8a-bis: a catch block only guards what v8 still throws

v7 code often detects a missing row by catching an exception the v8 core no longer raises, so the guard silently
stops working and the plugin accepts what it used to refuse. Check every `catch` in the files you touch against the
current core source, and replace the ones that are now dead with the explicit test.

```java
// Before — PageHome.getPage threw AppException in v7
try { PageHome.getPage( nId ); } catch ( AppException e ) { return errorMessage; }
// After — v8 returns the row, or nothing
if ( !PageHome.checkPageExist( nId ) ) { return errorMessage; }
```

The opposite trap exists too: `PortletHome.findByPrimaryKey` dereferences the row it loaded without checking it
exists, so an **unknown identifier raises a NullPointerException inside the core** instead of returning null. Any
lookup driven by a request parameter needs its own guard, and an e2e bench will find it on the first unknown id.

## Step 8a-ter: a portlet JspBean has no CSRF protection until you add it (MANDATORY)

The v8 automatic token filter only covers MVC controllers, and the core's portlet forms emit no
token, so every `do*` of a `PortletJspBean` accepts a forged call. The plugin closes it alone:
its specific template sits inside the core form and `getCreateTemplate` / `getModifyTemplate`
take a model. Recipe, traps and the GET-that-writes case: `${PATTERNS}/mvc-patterns.md` **§11**.
Checked by `CS01`.

## Step 8b: ThreadLocal cleanup (MANDATORY when the file has a ThreadLocal)

Clear every `ThreadLocal` with `remove()` in a `finally`, never with a reassignment
(`set(false)`, `set(null)`). A reassignment keeps one entry per pooled thread for the whole
application lifetime. Checked by `TL01`.

```java
finally { reentrancyGuard.remove( ); }   // not reentrancyGuard.set( Boolean.FALSE );
```

Same rule in tests: call `LocalVariables.remove( )` in `@AfterEach` when the test calls
`LocalVariables.setLocal(...)`.

## Step 8c: Do not widen the diff

The migration diff is read by a human. Change what v8 requires, nothing else.

- **Never convert line endings.** Converting some files and not others multiplies the diff and makes it
  unreviewable.
- **Never rewrite javadoc or delete comments** that the migration does not invalidate.
- **Do not "modernize" what compiles.** `XmlUtil.beginElement`/`addElement` take a
  `StringBuffer`: turning it into `StringBuilder` breaks the build. Raw types and
  `new Integer(...)` are worth fixing, wording is not.
- Check yourself with `git diff --ignore-cr-at-eol --shortstat` against `git diff --shortstat`:
  a large gap means the diff carries noise.

## Step 9: REST (conditional)

**Only if your files have `restPatterns: true`.**

Read `${PATTERNS}/rest-patterns.md` and apply.

## Step 10: Pagination (conditional)

**Only if your files use manual pagination** (`_strCurrentPageIndex`, `_nItemsPerPage`, `new LocalizedPaginator`, `new Paginator`, `AbstractPaginator.getPageIndex()`).

Per `${PATTERNS}/cdi-patterns.md` **§20**: replace manual pagination with `@Inject @Pager IPager`. This also allows JspBeans to be `@RequestScoped` instead of `@SessionScoped` (the pager manages its own state).

**A bean with two paginated lists must give each `@Pager` a distinct `name`** — an unnamed pager takes the name of its declaring class and `PaginatorHandler` caches one per name for the whole session, so the two share an instance and the second list lands under the first one's bookmark. Details and the scenario that catches it: §20.

## Step 11: JSON Library (conditional)

**Only if your files import `net.sf.json`.** Imports are already replaced by the mechanical script. Apply the API mapping:

| net.sf.json (pre-v8) | Jackson (v8) |
|---|---|
| `new JSONObject()` | `ObjectMapper mapper = new ObjectMapper(); mapper.createObjectNode()` |
| `json.element("key", "value")` | `json.put("key", "value")` |
| `json.getString("key")` | `json.get("key").asText()` |
| `json.getInt("key")` | `json.get("key").asInt()` |
| `json.accumulate("key", obj)` | Build `ArrayNode`, add to it, then `json.set("key", arrayNode)` |
| `json.accumulateAll(other)` | `json.setAll(otherObjectNode)` |
| `new JSONArray()` | `mapper.createArrayNode()` |
| `jsonArray.getString(i)` | `jsonArray.get(i).asText()` |
| `JSONSerializer.toJSON(obj)` | `mapper.valueToTree(obj)` |
| `json.toString()` | `mapper.writeValueAsString(json)` |

**Tip:** Lutece core provides `fr.paris.lutece.util.json.JsonUtil` with static `serialize()` / `deserialize()` methods.

Full before/after examples: `${PATTERNS}/json-patterns.md`.

## Step 12: Per-File Verification

After completing each file:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-file.sh <file_path>
```

Fix any FAIL results before moving to the next file. Mark each file task as **completed** when verification passes.

---

## Path shorthand

`${PATTERNS}` = `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns`

## Pattern Files (load on demand only)

| File | Load when |
|------|-----------|
| `patterns/cdi-patterns.md` | Always (scopes, injection, producers, Models, Pager) |
| `patterns/events-patterns.md` | If `eventPatterns: true` on any file |
| `patterns/cache-patterns.md` | If `cachePatterns: true` on any file |
| `patterns/rest-patterns.md` | If `restPatterns: true` on any file |
| `patterns/mvc-patterns.md` | If migrating JspBeans or XPages |
| `patterns/fileupload-patterns.md` | If `fileupload` in deprecatedPatterns, or a template carries the `upload_widget` flag |
| `patterns/json-patterns.md` | If a file imports `net.sf.json` (Step 11) |
| `patterns/persistence-patterns.md` | If `jpaPatterns: true` on any file (Step 6b) |

## Step 8h: zero compiler warning

`patterns/deprecation-fixes.md` lists what each deprecated API is replaced by — read it before fixing by hand,
several have a trap (the RBAC and workgroup overloads need an explicit `(User)` cast, or the compiler keeps
picking the deprecated one).

Every file you own compiles **without a warning** when it leaves your hands: `@Deprecated` API replaced by
its successor, generics declared (no raw types, no unchecked casts left to the reader), `serialVersionUID`
on `Serializable` classes, unused imports and variables removed, `@Override` where it applies. The migration is
the one moment somebody reads these files; a warning left now stays for years and hides the next real one.
You never run Maven: the Verifier reports the warnings of its compile build, file by file, and the final gate
fails on any warning in `src/`.

## Before you finish

- **Do not widen the diff.** Never convert line endings (CRLF stays CRLF), never reflow javadoc, never touch a
  file outside your task list even to "clean" it: the reviewer must see the migration, not the whole file.
  `verify-migration.sh` LE01 flags a converted file.
- **Write `.migration/report-<your teammate name>.md`** before your final answer: files changed, what you left
  undone and why, what the next teammate must know. The Lead reads that file; your answer through the channel may
  arrive truncated or late.
