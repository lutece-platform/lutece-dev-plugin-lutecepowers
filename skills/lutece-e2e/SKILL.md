---
name: lutece-e2e
description: "Use to give any Lutece 8 core, plugin, module or site an e2e/ bench that runs with one command: isolated Docker stack (Open Liberty HotSpot, MariaDB instrumented), synthetic volume, static + dynamic inventory of every back-office screen and action, Playwright suites (screens, YAML scenarios, forms) with a clean-console rule, server timings, SQL digests, JFR, k6, and a compact report. Also proves a migration's upgrade path: `run.sh compare` builds the artefact before its migration on a v7 site, then the v8 one on that same database, so a missing update_db script is caught instead of hidden by a fresh install. Triggers on 'e2e', 'tests de bout en bout', 'Playwright', 'tester tous les écrans', 'banc de test', 'non-régression BO', 'prouver la migration', 'chemin de mise à jour'."
---

# Lutece e2e — one bench, every screen, one command

## What this produces, and who writes what

A self-contained `e2e/` folder in the project under test, whose `./run.sh` builds the artefact, mounts an
isolated stack (Open Liberty + MariaDB + a mail sink), lets the application's own Liquibase create the schema,
seeds a synthetic volume, inventories **every** back-office screen and action, runs the suites in parallel,
profiles the server and writes `artifacts/summary.md`.

The harness is a **starter kit and presumes nothing about the target**: it seeds no reference row, no account,
no volume, and ships no scenario. Everything target-specific is **written by the agent** — the seed rows its
screens need, the accounts its rights tests require, the volume for the tables it reads, and the scenarios.
On lutece-core that yields a core bench; on a FAQ plugin, FAQ rows and FAQ scenarios. Never hard-code either:
the idioms live in `templates/scenarios-example.yaml` and `templates/scenarios-negative-example.yaml`.

The agent writes only `e2e.conf` and the YAML scenarios. Everything else is a script shipped here.

**`e2e/` is never committed.** It is a local test tool, not a deliverable of the plugin: `init-e2e.sh` adds it
to the project's `.gitignore`. Hand over what it produced (`summary.md`, `compare.md`, `review.md`) as
attachments to the report, never as files of the repository.

Prerequisites: Docker + Compose v2, Maven with the Lutece repositories, JDK 17+ on the host (to run `mvn` and
`jar`), network access to Maven Central once.

**`run.sh build` installs the artefact under test in `~/.m2`.** That is how the bench proves a fix before it is
published, but the patched build then shadows the published snapshot for **every other project on the machine**,
silently and until someone notices. On a plugin it is usually harmless; on `lutece-core` it changes what every
plugin resolves. After a bench on the core, put the published build back:

```bash
V=lutece-core-8.0.2-<timestamp>-<build>   # the latest of maven-metadata.xml on the snapshots repository
curl -sO "<snapshots-repo>/fr/paris/lutece/lutece-core/8.0.2-SNAPSHOT/$V.jar"   # and .pom, and -webapp.zip
mvn install:install-file -Dfile=$V.jar -DpomFile=$V.pom \
  -DgroupId=fr.paris.lutece -DartifactId=lutece-core -Dversion=8.0.2-SNAPSHOT -Dpackaging=jar
```

Check with `md5sum` that the local `lutece-core-8.0.2-SNAPSHOT.jar` matches the downloaded one.

## Additional resources

Read these only when the case applies — none is needed for a plain bench.

- **The traps that fake a green run** — screens opened without their parameters, a front-office assertion that
  passes on the site menu, a seed that lands after the cache froze, REST endpoints, scenario ordering:
  [reference/traps.md](reference/traps.md). Read at PHASE 2.
- **External systems** — CAS, OIDC, identity store, notifygru, ANTS, CRM, TIPI, and the real Solr and
  Elasticsearch: [reference/external-systems.md](reference/external-systems.md). Only if the artefact calls one.
- **Proving a migration** (`compare`) and **running against a deployed instance** (`external`):
  [reference/compare.md](reference/compare.md). An artefact written for v8 never runs `compare`.
- **Scope of a plugin bench** — what extra artefacts to assemble (`E2E_PLUGINS`, `E2E_ENABLE`), front-office
  coverage, how the mechanics measure: [reference/scope.md](reference/scope.md). Read at PHASE 1.
- **Why each tool was chosen, and what was rejected**: [reference/DESIGN.md](reference/DESIGN.md). Read before
  changing a tool choice. Its § Pièges lists the platform traps the scripts already work around (Liberty image
  and JFR, OpenJ9, JDBC driver location, `/logs` ownership, `form.action` shadowing, session-killing public
  forms) — do not re-diagnose them; fix the script if one resurfaces.

## What you can run, and when

`./e2e/run.sh` with no argument runs the whole chain and ends on `artifacts/summary.md`. That is the command
for almost every bench. The others are the same steps taken one at a time, to iterate without paying for a
full run.

| Command | What it does | When |
|---|---|---|
| *(none)*, `all` | build, stack, inventory, crawl, smoke, suites, perf, report, visual review | every bench |
| `build` | assembles the artefact and the site into a war | after a source change |
| `up` | starts the stack on an empty database, waits for health, seeds | to work step by step |
| `inventory` | reads the sources: every screen, action, right and REST endpoint | to see what there is to cover |
| `discover` | crawls the running site and completes the inventory | after `up` |
| `test [args]` | the Playwright suites; takes pytest arguments, so one scenario at a time | while writing scenarios |
| `perf` | server timings, SQL digests, JFR, k6 | after the suites |
| `report` | rebuilds `summary.md` and `report.html` from the artefacts already there | free, anytime |
| `review` | the screen-by-screen visual gate | before handing over |
| `logs`, `status`, `sh` | the application log, the containers, a shell inside the application | while diagnosing |
| `down` | stops the stack and drops its volumes | when done |
| `compare` | the artefact **before** its migration on a v7 site, then the v8 one on that same database | migration only |
| `external` | the suites against a site deployed elsewhere, from `E2E_BASE_URL` | recette, preprod |

The last two are conditional and documented apart: [reference/compare.md](reference/compare.md). Everything
above them applies to any artefact.

## PHASE 1 — Materialise the bench (2 minutes)

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-e2e/scripts/init-e2e.sh <project-dir>      # infers core|plugin from the pom
```

Then edit `e2e/e2e.conf`:
- `E2E_TARGET` core | plugin. A **site** builds with its own pom: set `E2E_TARGET=site`, replace
  `harness/site` by a symlink to the site and keep `tools/gen-site.sh` out of the flow (run `mvn ... lutece:site-assembly` yourself, then `jar -cf harness/site/target/lutece.war`).
- `E2E_PLUGINS` extra artefacts to assemble (`groupId:artifactId:version:type`, comma-separated) — the
  plugin's runtime dependencies that are not pulled transitively (mylutece, workflow, genericattributes…).
- `E2E_ENABLE` plugin names to mark installed in `plugins.dat` (v8 default is *not installed*).
- Ports when several benches run on the same machine.

**Front-office authentication comes with the bench.** `plugin-mylutece` and `module-mylutece-database` are
assembled and enabled by default (`E2E_MYLUTECE=1`; 5.0.1-SNAPSHOT / 7.0.1-SNAPSHOT, because the 5.0.0 release
still installs `core_style*` rows the v8 core has no table for and the site never turns healthy; the v7 side of
`compare` gets the last v7 releases), the plugin's own `mylutece.properties` turns authentication on without making the
site private, and `harness/db/post-init-mylutece.sql` seeds the account **test / testtest** (role `e2e_user`).
A scenario signs in with one step, `login_fo: {user: test, password: testtest, provider: mylutece-database}`
(it fails when the login form is still there afterwards), under `anonymous: true`. A bench that needs another
version names it in `E2E_PLUGINS` and keeps it; `E2E_MYLUTECE=0` leaves authentication out. The module brings its own
XPage `page=mylutecedatabase`, which answers its "access denied" site message to an anonymous visitor: declare it
under `skip` with that reason, it is the module's behaviour and not the artefact's.

## The oracle is positive, and it is tested first

`tests/lutece.py::classify` says what the browser shows from the DOM: `screen` (admin menu bar present,
no error wording), `confirmation`, `error`, `warning`, `info`, `auth` (session lost), `login`, `error-page`,
`fo`, `fragment`, `http-NNN`. A screen test passes only when the kind matches what that screen must show.
`tests/test_harness.py` checks the classifier on a real screen, a confirmation, a lost session, a login form
and a 404 before anything else; `run.sh` stops with code 3 when it fails. Never weaken it: the absence of an
error marker is not a success — "please authenticate" and "Internal error" render in HTTP 200.

`summary.md` carries three guardrails to read on every run: the count of kinds among **passed** tests
(`auth` or `error-page` there means the oracle is blind), the duplicate-content alarm (different parametrised
urls, same page text), and the inventory coverage (covered / excluded with a reason / to do). Open at least
three random screenshots in `report.html` before calling a run green.

## PHASE 2 — First run, read the summary (5–8 minutes)

```bash
KEEP=1 ./e2e/run.sh          # keep the stack up while iterating
cat e2e/artifacts/summary.md
```

Read in this order: the suite table, the failures, the console section, the server errors, the slowest
paths. **A failing test is a finding, not a harness bug, until proven otherwise**: the core itself shows
JSP that no longer compile, JS errors, dead links, a CSRF token missing on a confirmation form. Before
touching the harness, confirm the cause in `artifacts/logs/messages.log` (stack traces) and in the
screenshot referenced by the failure (`artifacts/report.html`).

Harness-side causes (fix them in the bench, not in the app):
- a screen needs a parameter the crawl did not find → add a scenario that reaches it, or a seed row;
- a form needs a value the generic filler cannot guess → `values:` in a `fill_form` step;
- a scenario logs out or changes the password → `isolated: true`;
- a session-less public screen → it is already routed to the anonymous context (`SESSIONLESS`).

## PHASE 3 — Scenarios (the only code the agent writes)

**Mechanical rule, enforced at collection:** every mutation (`submit`, `submit_novalidate`, `confirm`,
`confirm_if`, a `click` on a Do*/action control) must be followed, within the next three steps, by a **state**
oracle — `sql` (`expect`, `not_expect`, `expect_var`, `not_expect_var`, `min`), `expect_dom`, `mail`, `fake_log`,
`http`, `download`. `expect_text`, `expect_message`, `expect_kind` and `expect_html` read the screen that
followed, not what the application did: alone after a mutation they are a *weak* oracle and the scenario is
rejected. A refusal is written `expect_message: error` **then** `sql` counting that nothing was created.
`expect_text` on a url or a JSP name is rejected too (assert on what the page says, not where it is), and
`sql_exec` is allowed before the first mutation or after the last oracle, never in between. "The next screen
looked normal" (`expect_ok`) is navigation, not proof. Prefer deterministic values (a named group, a fixed
column) so the oracle can state the expected value; use `sql_set` before and `not_expect_var` after when the
value cannot be chosen. State that lives outside the database (a badge, a datastore key) is read where it is.

Coverage counts two things, and only the first is reported as achieved: **proven** — the pages a passing
oracle stood behind (the navigations since the previous oracle are credited when the next one passes; what
comes after the last oracle is never proven) — and merely **reached** (a GET by the screens suite, a fuzzed
form, a page a scenario crossed without asserting). Reached but not proven is listed as debt in `summary.md`.

Flags: `isolated: true` (own session: logout, own password), `anonymous: true` (public screens, no session),
`serial: true` (changes settings shared by every session — security parameters, e-mail pattern, feature groups,
plugin install; run alone after the parallel pass, so it cannot break a user creation running elsewhere).
Before calling an "Internal error" a defect, drive the flow the way the interface does (`tools/forms.sh`, the
links of the previous screen): a screen called without a parameter it expects is a robustness finding, not a
functional one — the two are reported apart.

**The artefact's own actions are the point of the bench, and a run does not end green without them.** A plugin
exists for one or two workflows — files2docs imports files, a form plugin submits a form — and a bench that opens its
listings and stops has proved the menu, not the plugin. `run.sh all` fails with **rc=9** while an action of the
artefact (`Do*`, an MVC `action=`, an upload endpoint) is neither proven by a green scenario, tested red, nor
excluded with a written reason; `COVERAGE=skip` bypasses it to iterate, never to hand over. Start the scenarios
from the artefact's main workflow, played end to end the way a user plays it (upload a real file from
`fixtures/`, submit the wizard, read the created rows), before the CRUD of its settings screens.

Work the "à couvrir" list of `summary.md` down to zero: every inventory element ends up covered by a test, or
listed in `scenarios/coverage-exclusions.yaml` with a written reason (a defect found by the suites, a plugin
not on the bench, a dead template). Exclusions stay visible in the report as debt; they never lower the totals. **A defect of the artefact itself is never an exclusion**, in `coverage-exclusions.yaml` or under `skip` in `screens.yaml`: a screen that dies on load ("jQuery is not defined") is opened and fails red, and the defect is fixed or reported, not written down as a reason to look away. `python3 tools/coverage.py` prints the to-do list; `python3 tools/causes.py`
prints the server exception behind each failure; `bash tools/forms.sh <src> <feature>` prints the forms and
field names of a feature's templates. When a real defect blocks the middle of a lifecycle, split the scenario
so the actions after the defect stay covered. `sql_exec` arranges data the UI cannot create (a broken create screen), never asserts.

One YAML per feature in `e2e/scenarios/`. Aim for one CRUD lifecycle per admin feature of the artefact
(create through the real form → read back on the listing → modify → remove), with the database as the
oracle. The step vocabulary is documented at the top of `tests/test_scenarios.py`. Find field names with:

```bash
grep -oE "name=['\"][a-z_]+" webapp/WEB-INF/templates/admin/<feature>/*.html | sort -u
python3 e2e/tools/inventory.py . --markdown | head -60          # features, screens, actions
```

Rules:
- `req:` = the Lutece right of the feature (`CORE_USERS_MANAGEMENT`…). EARS requirements are generated from it.
- `title:` is what the report shows in place of the id, `description:` (optional) the paragraph under it: why this
  scenario exists, what defect it pins, what a reader should know before the steps. Write it as a `>-` block — a
  bare scalar containing `: ` is not valid YAML and silently invalidates the whole file.
- Never assert on wording that comes from i18n when a `sql:` check is possible.
- Confirmation screens: `expect_message: confirmation` then `confirm:`; refusals: `expect_message: error`.
- Keep `{{rand}}` in every created key so scenarios are re-runnable and parallel-safe.

## PHASE 3b — Negative scenarios (mandatory)

A `<artefact>-negative.yaml` file must exist, covering **what this artefact must refuse**: a mutation called
without its CSRF token refused and the row unchanged, one duplicate-key refusal and one empty-mandatory-field
refusal per main entity (`submit_novalidate` bypasses the HTML5 check to reach the server-side validation), and an
unknown-id call answered gracefully. If the artefact enforces rights of its own, add a restricted account **in this
bench's own** `harness/db/seed-<target>.sql` and prove the refusal with it — the generic harness seeds no such
account, because who is restricted from what is a property of the target. `templates/scenarios-negative-example.yaml`
is the model.

**The CSRF one is not waivable, and "the platform does not protect this path" is not a reason to skip it.** It is
a reason to write it: a legacy path outside the automatic filter is exactly where the hole lives. A portlet
JspBean is the known case — the plugin closes it itself (`lutece-migration-v8-agent-teams`,
`patterns/mvc-patterns.md` §11). Cover **every** mutation, including the ones reached by a link: a delete behind
`<a href="…Do…?id=1">` is a GET that writes.

**Drive mutations through the real form, never a forged URL.** `goto: …DoSomething.jsp?a=1&b=2` is convenient and
it stops proving anything the day the action becomes token-protected: the call is refused, and a scenario whose
only oracle is `expect_message: error` stays green while the behaviour it claimed to test is never reached. Open
the screen, `fill`, `submit` the form — that is the user's path, and it is the one that carries the token. Keep
`goto` for what has no form: an unknown id, a missing parameter, a call without a token.

## PHASE 4 — Volume and bottlenecks

**The k6 load is off by default** (`E2E_PERF=1` turns it on). It costs minutes on every run and a migration is
judged on behaviour; performance is this phase's question, not every run's. The rest of the perf step still runs:
it writes `artifacts/perf.json`, which the server-error gate reads.

```bash
E2E_VOLUME=large ./e2e/run.sh down && E2E_VOLUME=large KEEP=1 ./e2e/run.sh
```

**The generic harness seeds nothing.** Bottlenecks are hunted in the tables *the artefact under test* actually
reads, so the agent writes `harness/db/seed-<target>.sql` for them — a core fills `core_page`/`core_admin_user`,
a FAQ plugin fills its questions and subjects. `seed.sh` applies every `seed-*.sql` of the bench and exposes
`@users`/`@groups`/`@roles`/`@lists`/`@pages` sized by `E2E_VOLUME` (`none` by default, `small`, `large`) so a
generated seed can scale itself; `reference/seed-volume-example.sql` shows the technique (MariaDB SEQUENCE engine,
idempotent marker row). Then read, in `summary.md`: server p95 per path, SQL digests with `no_index` and
`rows_examined`, JFR hot methods, pool wait. A listing screen that slows with
volume plus a digest reading the whole table = the bottleneck to report (paginate in SQL, add the index).

## PHASE 4b — Visual review, screen by screen (mandatory)

The suites prove behaviour and `lutece.render_check` catches what a machine can see. Neither judges the
**look**. A screen can pass every assertion and still show an unresolved icon, an internal id in a badge, an
untranslated label, a fragment with no design system applied. Only eyes catch those, so the run does not end
until the agent has looked at every screen.

`./run.sh all` runs `tools/review.py todo`, which deduplicates the captures into groups — one group per
(url path, DOM kind), whatever the data — and writes `artifacts/review-todo.md`. The gate then calls
`tools/review.py check` and **fails with rc=7** until `artifacts/review.md` carries a verdict for every group.
`REVIEW=skip ./run.sh all` bypasses it; use that only to iterate, never to hand over.

How the agent does it:

- Open the representative capture of **every** group with the Read tool. Not a sample, not the flagged ones
  only: a defect that a mechanical check could see would already have been reported.
- Judge against the five points printed in `review-todo.md`: charte, mise en page, contenu, cohérence,
  lisibilité.
- Write one line per group in `artifacts/review.md`: `- [x] G012 ok` or `- [x] G012 defect: …`, then a short
  synthesis ordering the plugin's own defects by impact.
- **Attribute**, exactly like the server-error gate. A broken footer image or a mislabelled core dialog belongs
  to the site theme or the core, not to the artefact under test. Say so in the verdict and keep it out of the
  synthesis.

Before naming a rendering defect, check its cause in the source: how to do that, and the two groups this step
exposes, are in [reference/traps.md](reference/traps.md) § Naming a rendering defect.

## PHASE 5 — Freeze and hand over

- `baselines/aria/` is seeded from the first run at delivery scope (`run.sh report` copies the aria snapshots
  when it is empty and `E2E_SCOPE` is not `all`), so later runs on the same workstation diff against it. The
  visual review (`review.py`) judges the artefact's own screen families; a widened run's core screens are the
  environment's and are not listed.
- `artifacts/fingerprint.json` (also on the first line of `summary.md`) names what was tested: sources commit,
  war hash, image digests — a green run with no fingerprint is a green run of nothing in particular.
- CI: `junit 'e2e/artifacts/junit-*.xml'`, publish `report.html`, archive `summary.md`, `compare.md`,
  `fingerprint.json`; `run.sh` exit codes tell the cause apart (see its header).
- **A skip is not a proof.** A suite with something to prove (the fo suite when the inventory has a front
  office, the scenarios, the screens) whose every test is skipped fails the run with code 8. An exclusion the bench
  declared and justified is not that silence: when every skip of the suite comes from a rule written in
  `scenarios/screens.yaml` or from a scenario's `versions`, the run stays green and the summary names the reason.

