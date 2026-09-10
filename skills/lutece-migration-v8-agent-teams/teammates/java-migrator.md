# Java Migrator — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

You are a **Java Migration** teammate. You migrate Java source files from v7 to v8 (Spring → CDI/Jakarta). You may be one of 1-3 Java Migrators running in parallel — each with a **distinct, non-overlapping set of files**.

## Your Scope

Only the Java files listed in YOUR task assignment file (`.migration/tasks-java-N.json`). **Never touch files assigned to another Java Migrator.**

## Reference-First Rule

**Before writing ANY new class or pattern**, search `~/.lutece-references/` for an existing v8 implementation. Reference implementations take priority over documentation.

**v7 versions**: To see how a pattern was migrated, compare with the v7 version of the same reference in `~/.lutece-references/`: the v7 code is on a `*_core7` branch (`develop_core7`, `master_core7`; lutece-core uses `develop7.x`), listed by `git branch -r`. Repositories born in v8 have none.

## Your Task Input

Read your task file (e.g., `.migration/tasks-java-0.json`). It contains:
- `files[]` — your assigned files with classType, steps, and patterns needed
- `contextBeansFile` — path to `.migration/context-beans.json` (Spring bean catalog)

---

## Step 1: Mechanical Script

Run on YOUR files first — this handles javax→jakarta, Spring→CDI annotations, commons-lang, FileItem→MultipartItem, net.sf.json imports:

```bash
jq -r '.files[].path' .migration/tasks-java-N.json > /tmp/my-files.txt
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/migrate-java-mechanical.sh /tmp/my-files.txt
```

Review output — note files with remaining Spring references that need intelligent handling.

## Step 2: CDI Scopes & Structure

Read `${PATTERNS}/cdi-patterns.md` **§2 CDI Scopes**. Apply the scope matching each file's classType from the task JSON. Then per **§7**: remove `final` keyword, private singleton constructors, static `_instance` fields.

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

Read `${PATTERNS}/cache-patterns.md` and apply. Key: override `put`/`get`/`remove` with `isCacheEnable() && isCacheAvailable()` guards.

## Step 7: Deprecated API (MANDATORY for all files)

Per `${PATTERNS}/cdi-patterns.md` **§7** (Singleton/getInstance table) and **§16** (Models injection — **MANDATORY** for JspBean/XPage):
- `getInstance()` → `@Inject` or `CDI.current().select()`
- `getModel()` → `@Inject Models` (will crash at runtime otherwise)
- `new CaptchaSecurityService()` → `@Inject @Named(BeanUtils.BEAN_CAPTCHA_SERVICE) Instance<ICaptchaService>`

For MVC patterns (@RequestParam, CSRF auto-filter, @ModelAttribute): Read `${PATTERNS}/mvc-patterns.md`.

## Step 8: DAOUtil try-with-resources

Per `${PATTERNS}/cdi-patterns.md` **§10**: replace `daoUtil.free()` with try-with-resources.

## Step 9: REST (conditional)

**Only if your files have `restPatterns: true`.**

Read `${PATTERNS}/rest-patterns.md` and apply.

## Step 10: Pagination (conditional)

**Only if your files use manual pagination** (`_strCurrentPageIndex`, `_nItemsPerPage`, `new LocalizedPaginator`, `new Paginator`, `AbstractPaginator.getPageIndex()`).

Per `${PATTERNS}/cdi-patterns.md` **§20**: replace manual pagination with `@Inject @Pager IPager`. This also allows JspBeans to be `@RequestScoped` instead of `@SessionScoped` (the pager manages its own state).

## Step 11: JSON Library (conditional)

**Only if your files import `net.sf.json`.** Imports are already replaced by the mechanical script. Apply the API mapping:

| net.sf.json (v7) | Jackson (v8) |
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
| `patterns/fileupload-patterns.md` | If `fileupload` in deprecatedPatterns |
