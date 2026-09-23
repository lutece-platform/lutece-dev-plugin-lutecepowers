# Bench — scope of a plugin bench, front-office coverage, and how the mechanics measure

Read when deciding what a plugin's bench must cover, and when interpreting what the report measured.

## Contents
- Plugin benches — scope, rules and probes
- Front-office coverage
- How the mechanics measure the target

## Plugin benches — scope, rules and probes

- **Ports**: `init-e2e.sh` takes the first free slot and shifts every port by 100 (app 18080, db 13306, mail
  18025, then 18180/13406/18125…). Benches stay up with `KEEP=1`, so a second bench on a fixed default would
  fail to bind. `--port` forces a slot.
- **SQL order across plugins**: the site installs every plugin's SQL in one Liquibase run at first boot, in
  alphabetical order, unless `plugin-liquibase` is recent enough to honour the `--lutece runAfter:<plugin>`
  directive (`LuteceRunAfterComparator`, present from 2.0.2; 2.0.0 and 2.0.1 ignore it). A plugin whose `init_db`
  script depends on another plugin's tables carries that directive; under an older plugin-liquibase its inserts run
  before the tables exist, the install dies at boot, the site answers 500 on every page and the container never
  turns healthy. The harness pins 2.0.2-SNAPSHOT; `E2E_LIQUIBASE_VERSION` overrides it. Symptom to recognise in the container log:
  `Table 'lutece.<x>' doesn't exist [Failed SQL: INSERT INTO <x>]` followed by
  `AdminAuthenticationService._authentication is null` on every request.
- **Core version**: `tools/gen-site.sh` resolves the lutece-core the plugin's pom really depends on
  (`mvn dependency:list`), never the parent global-pom version. Pin another one with `E2E_CORE_VERSION` in `e2e.conf`.
- **Scope**: every inventory element carries `origin` (`target` = the artefact scanned, `env` = the core and the
  other plugins of the assembled site). `summary.md` reports coverage and defects for the target; the environment's
  reds are counted in one separate section. The screens suite still opens everything (a broken core screen is still
  worth knowing), so read the target sections first.
- **Per-bench screen rules**: `scenarios/screens.yaml` extends the generic regexes: `fragment` (popups, modal
  bodies and front-office standalone documents: `AnswerSelection\.jsp`), `console_allow` (console noise the
  deployment owns, such as a third-party host the site's CSP has to allow — never an error of the artefact),
  `confirm`, `protected` (never fuzzed: the reference rows the scenarios rely on,
  e.g. `faq_id=9001`), `deny` (never posted). No Python change for a new plugin.
- **A screen behind an RBAC permission needs the role in the seed.** The bench's admin holds the functional
  right (`core_user_right`) but not the resource permissions, so the artefact answers "access denied" and every
  scenario on that screen reads as a defect. Give the admin the role the artefact ships for its resource type
  (`core_user_role`), guarded by an `EXISTS` on the role so a site without it is left alone.
- **A seed never writes an id it did not create.** Its own rows carry fixed ids in the 9000s, but a foreign key
  into a table the application filled (an entry type, a workflow state, a portlet type) is read back by its
  business key: `( SELECT MIN( id ) FROM <table> WHERE <business key> = '...' )`, with an `EXISTS` guard so the
  row is not written at all when the reference is missing. The two legs of a comparison number those tables
  differently, and a literal id leaves the row pointing at nothing on one of them: the artefact then fails on
  data the bench itself created, which reads as a defect of the artefact.
- **Reference rows**: `harness/db/seed-<plugin>.sql` inserts fixed-id rows guarded by `WHERE NOT EXISTS`
  (ids in the 9000s so they never collide with the DAO's max+1), re-applied by every full `run.sh test`. Scenarios read
  them, create their own `{{rand}}` rows for mutations, and protect them from the fuzzer with `protected`.
- **A probe asserts behaviour, never identity.** `CdiHelper.getReference( IService.class, name )` and
  `CDI.current( ).select( IService.class ).get( )` hand back a **Weld client proxy generated on the interface**:
  its class name is `iservice$...$weldclientproxy` and `instanceof TheImplementation` is false, always, migration
  or not. Assert what the service answers — an id, a description, a computed value — not what it is.
- **A plugin's PageInclude is invisible to the stock theme.** `page_frameset.html` renders exactly one include
  mark, `${contextinclude_2!}`; a plugin putting its html under its own mark (`myplugin_include`) shows nothing
  unless the site's theme names it. Prove the include with a probe that calls `fillTemplate` the way a theme
  would and prints what it put in the model — not by looking for it on a front-office page.
- **Library plugins (no screen, no XPage)**: ship a probe JSP in `harness/site/webapp/jsp/e2e/` (it lands in the
  assembled war): EL static calls on the service (`${ Service.method(param.id) }`), admin session required,
  result in elements with ids so `expect_dom` can read it. `templates/probe.jsp.example` is the model. **Never
  import a servlet class in a probe** (`javax` in v7, `jakarta` in v8): the same page is copied to the v7 site by
  `run.sh compare` and must compile there too — JSP already provides `request`, `response` and `pageContext`.
  Rebuild (`run.sh build`) after adding or editing a probe. When the probe needs a v8 API the older version does
  not have, the scenarios that go through it stop on the v7 leg with a written reason instead of failing: a probe
  is bench code, and a bench tool that cannot run says nothing about the artefact. On the version the bench
  targets the same broken probe stays red — there it is a defect of the bench, to fix before reading anything.
- **Rich text**: `fill` on a textarea driven by TinyMCE sets the editor content too (otherwise the editor's
  empty content overwrites the value at submit).
- **Front office**: `expect_kind: fo` after a `goto`. Two different URLs, do not mix them: an
  **XPage** is `jsp/site/Portal.jsp?page=<xpage id>`, a **portal page carrying a portlet** is
  `jsp/site/Portal.jsp?page_id=<page id>`. `?page=` on a portal page is routed to the XPage
  resolver in v8 and silently renders the wrong thing; the FO form posts to
  `Portal.jsp` (`submit: 'form[action*="Portal.jsp"]'`), the oracle is SQL. Anonymous scenarios need
  `anonymous: true`.
- **A plugin bench tests the plugin, not the core**: the core's tests never belong in a plugin
  bench. `E2E_SCOPE=target` (default) restricts the crawl, the screens suite, the forms fuzzer and the k6
  entry screens to the artefact's inventory paths, its `jsp/admin/plugins/<name>/` tree and its `page=<name>` front
  office; the core's public screens (login, lost password, contact) are skipped. `E2E_SCOPE=all` reopens the whole
  site on purpose. The core bench is unaffected (no `env` element in its inventory).
- **Mail**: the stack ships a Mailpit sink (`mail` service, UI on `E2E_MAIL_PORT`); the application is pointed at it
  through MicroProfile Config environment overrides (`MAIL_SERVER`, `MAIL_SERVER_PORT`). Without it every flow that
  sends a mail synchronously dies with `MailConnectException` before writing its row. Scenario oracle:
  `mail: {to: addr, min: 1, subject: text}` (polls up to 15 s, the Lutece mail daemon is asynchronous).
- **A plugin bench must not carry the core's own tests.** Two rules follow: (1) `E2E_SCOPE=target`
  already restricts crawl/suites/k6 to the artefact; (2) a *scenario* about a core concern (a level-3 admin refused
  the plugin-management screen, the login flow, cache toggles) belongs to the core bench, not the plugin's — do not
  write it in a plugin's `-negative.yaml`. Negative scenarios of a plugin test the plugin's own refusals (its RBAC on
  its entities, its validation, its unknown-id handling).
- **Ordering actions (Do*Up / Do*Down / Do*In / Do*Out)**: never assert against a shared reference row — moving your
  element past it drifts the reference and breaks idempotence. Create **two** of your own siblings, assert their
  relative order flips, and remove both. The ordering block of `templates/scenarios-example.yaml` is the model.
- **A step blocked by a real plugin defect goes in its own scenario** so the rest of the lifecycle stays green and the
  defect is reported once (one scenario red on the migration NPE of a getter; the CRUD lifecycle beside it
  stays green).

## Front-office coverage

A plugin with a front office is covered too, automatically:
- **Inventory** (`tools/inventory.py`): each `<application-id>` in plugin.xml and each `@Controller(xpageName=...)`
  MVC XPage becomes a FO element `jsp/site/Portal.jsp?page=<id>` with `surface: "fo"` (BO elements are `surface: "bo"`).
- **Discovery** (`tools/discover.py::crawl_fo`): an **anonymous** crawl (the FO is public) starts at every inventory FO
  page and follows front-office links only (`jsp/site/`, `Portal.jsp`), never a Do*/action url. Output: `fo_screens`
  in `discovered.json`.
- **Suite** (`tests/test_fo.py`, `--suite fo`): opens every discovered FO page in the anonymous context, asserts it
  renders as `fo`/`public-form` with a clean console (no JS error, no failed sub-request, no error page).
- **Coverage/report**: `summary.md` gets a "Front-office" sub-table (proven / defect / robustness / to do), separate
  from the back office; the `fo` suite has its own screenshot gallery in `report.html`.
- **Legacy XPages** (`implements XPageApplication`) expose only the page id declaratively; their
  parameter-driven sub-pages (a contact form, a filtered list) are reached by the crawl and proven by hand-written
  scenarios (`expect_kind: fo`, `expect_html` for content in collapsed accordions, the mail sink for notifications).
- A plugin with no front office (no `<application-id>`, no skin/) yields an empty FO section — nothing
  to do, no false gap.
- **Fresh slate every run**: `run.sh up` drops the database volume (the schema is recreated from scratch by the
  app's Liquibase at boot) and wipes `artifacts/logs/` before starting, so each run's results and its
  server-error analysis reflect only that run — never data or exceptions carried over from a previous one.

## How the mechanics measure the target

The detection rules are the ones lutecedata uses over the whole estate; the obvious proxies are wrong:
- **An admin JSP is an entry point, not a screen** (it over-counts screens several fold). A **back-office screen**
  is an `admin/` template **named from a Java string literal** (falling back to the back controllers' `@View`); a
  **front-office screen** is a front controller's `@View`, else a declared XPage.
- **`@View` / `@Action` count only when the file imports the platform MVC annotations** — a plugin declaring its
  own `@Action` would otherwise inject phantom actions — and front/back are split by `xpageName` vs
  `controllerJsp` before anything is summed.
- The **MVC framework's own sources and the test roots are excluded**, or a core bench reports the framework as
  its own surface.
- v8 XPages registered through CDI (`@Named("<plugin>.xpage.<id>")`) are detected alongside `<application-id>`.

`./run.sh inventory` writes `artifacts/inventory.md`: the screen/action surface, the declared socle (menu entries,
applications, RBAC resources, dashboards, portlets, daemons, servlets, filters, page includes, macro and asset
files), the code counts, the admin templates **no Java names** (macros, includes — or a dead screen), and the
testable URLs. Read it first: it tells the agent what this target actually exposes, so the scenarios aim at it.

**Server-side exceptions are attributed to the artefact, never to the platform it runs inside.** An exception
counts only when the artefact is named in its own log entry (message + stack, never a fixed window): its Java
package, one of its plugin names, its template directories or one of the tables its SQL creates — the fingerprint
in `surface.markers`. So a plugin that breaks the core through a direct call, its own template or its own SQL is
caught, while the core's own noise (LTPA, dashboard servlet…) never reddens a plugin bench. What remains and is
genuinely expected — a refusal the bench's own negative scenarios provoke — goes in
`harness/server-errors-allow.txt` with the scenario that provokes it. Anything left makes the run exit 5.

**Each scenario is also judged on the server log it leaves.** Scenarios run one after the other, so an error entry
logged while one runs comes from what it did, whatever its stack names: a download written through a JSP that
still flushes its writer (`SRVE0199E: OutputStream already obtained`) leaves only container frames, which the
package fingerprint misses, and the file still reaches the browser. Such an entry fails the scenario. The core
errors every 8.0.2 bench logs are left out (`CORE_LOG_NOISE` in tests/lutece.py, reported upstream), then the
patterns of `harness/server-errors-allow.txt`, then the scenario's own `server_log_allow`.

**k6 authenticates for real**: it reads the CSRF token from the login page and logs in **every iteration** (k6
resets the cookie jar between iterations, so a session never survives one). Without this the load test measures
authentication-failure pages and its checks pass falsely.

## What report.html contains

- `report.html` is written for the person who reviews the bench without having run it: the
  verdict and one tile per suite; the failures first, each with its readable title, its suite, its reason and the
  confirmed server-side cause; the scenarios by title, right and description with **their steps in plain words**
  (the failed step highlighted, the following ones greyed) plus screenshots and the pages traversed; the screens
  grouped by family (`ManageX · vue y`, bean and method from the inventory, the variants as chips); the forms by
  the action they post; the environment and the technical material (summary, coverage, console, perf) under folds.
  `summary.md` is unchanged and remains what scripts and the gate read. Rendering lives in `tools/report_page.py`;
  `tools/report.py` keeps the loading and the markdown summary.
  No Allure, no Node on agents; the runner is the pinned Playwright container.

## Assembling what the artefact needs to run

`E2E_PLUGINS` adds artefacts to the site (`groupId:artifactId:version:type`), `E2E_ENABLE` marks them installed.
The inventory also scans the exploded webapp of the assembled site (`--extra`), so an artefact pulled from Maven
without local sources still yields its screens, actions and rights. **What to assemble is a property of the target,
not of this skill**: a plugin needs its runtime dependencies (mylutece, workflow, genericattributes…), and a core
needs the features that left it in v8 and that every site still carries. Decide it per bench, in `e2e.conf`.
