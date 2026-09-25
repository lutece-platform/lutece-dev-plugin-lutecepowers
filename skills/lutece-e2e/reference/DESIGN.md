# Lutece e2e bench — design decisions

A self-contained `e2e/` folder, produced by a generic skill: an isolated environment, an inventory of **every**
screen and action, fast tests, a report a human and an agent both read in a few hundred tokens.
Read before changing a tool choice.

## What is kept, and why

| Part | Choice | Reason |
|---|---|---|
| Browser driver | **Playwright Python 1.62** (`sync_api`) + pytest 9 + pytest-xdist | Process-level parallelism, native JUnit XML for Jenkins. The tests are parametrised by JSON: the language matters little, the stability of the runner matters. |
| Runner | Official image `mcr.microsoft.com/playwright/python:v1.62.0-noble`, pinned | No dependency on the Jenkins agent; `RUNNER=local` to iterate on the workstation. |
| Environment | **Docker Compose v2** (db, lutece, mail, dbinit, tests, k6) | An e2e stack is a full stack mounted once; Testcontainers targets per-test isolation (Java integration), out of scope here. |
| Application server | **Open Liberty 26.0.0.9 on Temurin 21 (HotSpot)**, Maven Central zip | The ICR images are OpenJ9 only; OpenJ9 0.61 **crashes** (assertion `VMAccess.cpp:133`) under JFR sampling and refuses `dumponexit`. HotSpot gives full JFR, live `jcmd JFR.dump`, `jfr view`. The JIT difference is accepted: the bottlenecks (SQL, N+1, locks) are the same. |
| Database | **MariaDB 11.8** in memory (`tmpfs`) + `performance_schema` | Native digests (top statements by total time, rows read, no index), no external tool. `pt-query-digest`/PMM rejected: one more image for the same information. |
| Schema | plugin-liquibase at first boot, as in v8 production | Generic for any plugin or site: each jar brings its SQL; no script collected by hand. |
| Synthetic volume | Plain SQL, MariaDB **SEQUENCE** engine (`seq_1_to_N`) | 100,000 users in a few seconds server-side, idempotent, no external generator (Datafaker, Misata…: a dependency and slowness for no gain on reference tables). |
| Server timings | **Liberty access log** (`%D` µs per request) + `/metrics` (mpMetrics / monitor-1.0: JDBC pool, servlets, GC) | Server-side measure without application instrumentation; p50/p95 per path derived by `tools/metrics.py`. |
| JVM profile | **JFR** on demand (`E2E_JFR=1`, `settings=profile`), dumped live, summarised by `jfr view hot-methods / allocation-by-class / gc-pauses / contention-by-site` | Compact text an agent reads. Off by default: it costs CPU over the whole run. |
| Load | **k6 1.5** (`grafana/k6` container) on the entry screens, p95 / error-rate thresholds | Single binary, thresholds = exit code. Gatling rejected (JVM, heavy HTML report): load is only a short phase of the bench. |
| Screen fingerprint | **Aria snapshot** (YAML of the accessibility tree) + JPEG capture | The structural diff is textual, stable across machines, and costs a few lines; pixels are for humans, not for assertions. |
| Browser console | `console` (error/warning), `pageerror`, `requestfailed`, responses ≥ 400 on every page | "Console 100 % clean" is an assertion, not an option. |
| Requirements | **EARS** generated from the inventory + scenarios (`requirements.ears.md`) | One testable sentence per screen or action; coverage reads per requirement. Generated, never maintained by hand. |
| Report | `summary.md` (compact) + `report.html` (gallery) + `junit-*.xml` | The markdown is what the agent reads; JUnit is what Jenkins reads; the HTML is what the project manager looks at. |

## What is rejected, and why

- **Playwright Agents (planner / generator / healer), Playwright MCP**: LLM test generation from VS Code. High token cost, non-deterministic, the opposite of the goal (tests derived from the inventory by script). The skill generates the structure, the agent writes only YAML.
- **Allure** (2 Java / 3 Node): asked for Jenkins. Allure 3 needs Node + `allure` in the agents' PATH; Allure 2 is a Java "global tool". The Jenkins JUnit plugin reads `junit-*.xml` with nothing to install, HTML Publisher shows `report.html`. Allure brings history and trends: add it only when a project asks (`allure-pytest` writes `allure-results`, one line in `run.sh`).
- **Grafana otel-lgtm / Prometheus**: great for interactive exploration, useless for a bench that must produce a text report and shut down.
- **Pixel captures as an oracle**: dependent on fonts, antialiasing, OS; guaranteed false positives in CI.
- **Testcontainers**: per-test isolation, Java, not an e2e stack.
- **ICR OpenJ9 images** for the bench: see above (JFR). They remain the reference for production.
- **A single PDF report of everything**: `report.html` with `content-visibility:auto` is enough; a PDF can be derived by Chromium if a project requires one.

## `run.sh` flow

```
build      floor check → mvn install (target) → e2e site (generated pom) → war → app image
up         compose up db+lutece → healthcheck → dbinit (post-init + seed)
inventory  inventory.py (SQL rights, plugin.xml, JSP, @Controller/@View/@Action, templates) → EARS
discover   authenticated crawl: GET links from the menu and the entry points (never Do*/action=) → concrete urls
test       harness → screens → fo → scenarios → forms; /metrics before/after; one runner container (docker exec)
perf       [k6] → [JFR] → access log → SQL digests → perf.json
report     summary.md + report.html + results.json
down       compose down -v
```

## Harness invariants

What the scripts enforce, and no change may loosen:

1. **Positive oracle** (`lutece.classify`): a screen passes only when the DOM carries the admin menu bar
   (`#main-menu`) with no error wording; any other page is classified (`confirmation`, `error`, `auth`, `login`,
   `error-page`, `fo`, `fragment`, `http-NNN`) and the expected kind is explicit per screen type. The absence of an
   error marker is never a success: "please authenticate" and "Internal error" render in HTTP 200.
2. **Oracle self-tests** (`tests/test_harness.py`) run first; when they fail no other suite runs and `run.sh` ends
   with code 3.
3. **Visible classification**: the report counts the page kinds of the *passed* tests (`auth ×40` stands out).
4. **Duplicate-content alarm**: different urls passing with the same page text are flagged.
5. **Session guard**: a screen classified `auth` triggers a new login and a second try; the public screens
   (AdminForgot*, AdminFormContact, AdminResetPassword) run in an anonymous context because they invalidate the session.
6. **No no-op**: `fill_form`, `submit`, `click`, `fill` fail on a missing element and resolve the element through
   the Playwright locator (never `document.querySelector` with `:has()` / `:text-is()`).
7. **Coverage per inventory element** (`tools/coverage.py`): each screen or action is reached, excluded with a
   written reason (`scenarios/coverage-exclusions.yaml`), or listed "to cover". Proven ≠ reached: only the pages a
   passing oracle covered are proven (`record.proven`); the rest is listed debt, never subtracted.
8. **Server cause per failure** (`tools/causes.py`): exceptions of `messages.log` correlated by time window and
   confirmed by the name of the JSP or bean.
9. **Bare vs parametrised**: a screen called without its parameters may answer a Lutece message, never an internal
   error; the report separates the two populations.
10. **A mutation without a state oracle** in the next three steps makes the scenario invalid (a red test naming the
    step). State oracles: `sql`, `expect_dom`, `mail`, `fake_log`, `http`, `download`; `expect_text`, `expect_message`,
    `expect_kind`, `expect_html` read the screen, not the state: weak, never enough alone after a mutation.
    `expect_text` on a url or a JSP name is refused; `sql_exec` is refused between a mutation and its state oracle.
11. **Negative and rights scenarios are mandatory**: access refusal, CSRF without token, duplicates, empty mandatory
    fields (`submit_novalidate` bypasses HTML5 to reach the server-side check).
12. **Three failure populations**: functional (parametrised screen, scenario, form), front (JS, console) and
    robustness (screen called without parameters). Console cleanliness is judged by the screens suite, once per screen.
13. **Discovery**: depth 8, 25 variants per screen (path + `view`), forms collected at every depth, GET forms followed.
14. **Bench invariants**: the fuzzer never touches the bench accounts (`PROTECTED_SCREEN`, `protected`); after the
    tests `run.sh` checks that the admin account still exists, otherwise code 4 and an alert at the top of the report.
15. **Isolation of parallel scenarios**: anything that changes a shared form (attributes, parameters) picks neutral
    values or goes `serial`.
16. **A finding must survive a clean database**: the reference seed is replayed before every `test`, and a finding
    on seeded data is kept only after checking the data is there.
17. **A skip proves nothing**: a suite that had something to prove and whose every test is skipped fails the run
    (code 8); the summary marks it. Exception: an exclusion written and justified in the bench (`screens.yaml` key
    `skip`, or a scenario's `versions`) stays green, with its reason in the summary.
18. **The report says what was tested** (`artifacts/fingerprint.json`): source commit, war hash, image digests. The
    exit codes tell the causes apart: 1 stack, 2 usage, 3 oracle, 4 invariant (the admin account altered, or a
    security key switched off in `conf/override` and not named in `E2E_ALLOW_SECURITY_OFF`), 5 server errors,
    6 smoke, 7 review, 8 suite skipped, 9 an action of the artefact proven by no scenario, 10 lutece-core below the
    supported Lutece 8 level; `compare` returns the v8 leg's code, else the comparison's.

## Traps (kept in the skill)

- The Liberty image's `configure.sh` fails (code 22) when `jvm.options` holds `-XX:StartFlightRecording` (populate_scc).
- OpenJ9: `dumponexit` invalid; the dump happens at JVM stop; VM assertion under sampling → HotSpot.
- The Liberty `dataSource` is resolved **before** the war expands: the JDBC driver is extracted at image build (`shared/resources/jdbc`), not read from `apps/expanded`.
- Bind mount `/logs`: created root by Docker → `chmod 777` before `up`, and the app runs with the host uid (`user:`) so logs and access log stay readable.
- `form.action` is not a string when a field is named `action`: read `getAttribute('action')`.
- `plugins.dat.tpl` placed in `webapp/` ends up in the war: keep templates outside the copied tree.
- The healthcheck on `AdminLogin.jsp` passes before the end of the Lutece init when Liquibase fails: read `messages.log`, not only the `healthy` state.
- Never name the Compose service `app`: `.app` is a TLD of Chromium's preloaded HSTS list, `http://app:9090` is rewritten to https → `ERR_SSL_PROTOCOL_ERROR` in the runner (the IP and `localhost` work, which points the diagnosis at the core's HSTS header, which plays no part: an HSTS header received over HTTP is ignored). The service is named `lutece`.
- The core sends a CSP with `upgrade-insecure-requests`: on an origin that is not "potentially trustworthy" (anything but localhost/https) Chromium rewrites every sub-resource to https. `--unsafely-treat-insecure-origin-as-secure` is not enough in the headless shell; the robust answer: the runner (and k6) share the application container's network namespace (`network_mode: service:lutece`) and talk to `http://localhost:9090`, a trusted origin for Chromium, exactly as from the workstation.
- The public "forgotten login" form invalidates the session: session-less screens run in an anonymous context, otherwise the rest of the worker's suite falls back to `AdminMessage.jsp`.
- `DoCreateWorkgroup` assigns the creator to the group: removal is refused until the creator is unassigned (realistic scenario: refusal expected, then unassignment, then removal).
- Never pass a Playwright selector (`:has()`, `:text-is()`) to `document.querySelector` inside an `evaluate`: it throws, a broad `except` swallows it, and the submission becomes a silent no-op. Resolve the element through `locator(...).evaluate(...)`, and catch only the navigation timeout.
- `expect_message`: the theme exposes only the card colour (`bg-danger`/`bg-warning`); a confirmation is recognised by its two forms (validate / cancel).

### Traps of plugin benches
- A plugin assembled on the v8 side but absent from the v7 leg arrives on a database where its tables already
  exist, with no version recorded for it: it is installed as new, its creation script is marked applied and its
  upgrades never run. The schema stays in v7 shape and the site fails on a column the upgrade would have added —
  which reads as a migration defect. Both legs list the same plugins.
- A bench probe written with the v8 APIs does not compile on the v7 leg: the scenarios that go through it stop with
  a written reason instead of turning red, otherwise the comparison reads "corrigé" on bench code. On the version
  the bench targets, the same broken probe stays red.
- The v7 core reads its `.properties` through MicroProfile Config, so the environment reaches them; a literal in a
  Spring context reaches nothing. `harness/v7-overlay/` is laid over the assembled v7 webapp for those literals, to
  point it at the stand-ins.
- Proving a plugin fixed locally: `mvn install` in its clone, then `E2E_MVN_OFFLINE=1` so the v8 legs take the local
  repository rather than the newer remote snapshot. Offline must not reach the v7 leg, which downloads its own
  artefacts; check afterwards that the change is in the war, otherwise the run proved the old build.
- A v7 pom often declares its dependencies as open ranges whose top has moved: the leg no longer compiles.
  `E2E_V7_DEP_PINS` freezes those versions in the disposable worktree, as a one-value range (a plain version loses
  against a range).
- A bench's port slot is recorded, not chosen from the ports free at the moment: otherwise every bench initialised on
  a quiet machine takes slot 0 and two of them can never run together.
- `gen-site.sh` resolves the core with `mvn dependency:list`: `project.parent.version` is the global-pom version, not
  the core's.
- A plugin bench also scans the site's exploded webapp: every element carries `origin`, otherwise the core's reds
  drown the plugin's in the report.
- TinyMCE copies the editor content into the textarea at submit: a DOM `fill` on the hidden textarea is overwritten.
  The `fill` step feeds the editor too.
- A plugin's sample data (`init_db_<p>_data_sample.sql`) is consumed by the fuzzer from the first run: scenarios never
  rely on it, they read `seed-<plugin>.sql`.
- Without an SMTP sink, `MailService.sendMailHtml` throws `MailConnectException` (localhost:25) and the business flow
  that calls it before writing to the database fails: Mailpit in the stack, addressed by environment variables
  (MicroProfile Config reads `MAIL_SERVER` for `mail.server`).
- A plugin bench opens only the plugin's screens: `E2E_SCOPE=target` filters discovery, suites and k6 on the
  `origin=target` inventory.
- Under pytest-xdist, `pytest_runtest_makereport` fires on every worker and on the controller: without a guard each
  result is written twice (gwN.jsonl + main.jsonl) and the report doubles the counters. Guard: write only on a worker
  (numprocesses set ⇒ require PYTEST_XDIST_WORKER).
