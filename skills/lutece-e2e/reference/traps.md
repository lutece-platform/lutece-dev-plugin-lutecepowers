# Bench — the traps that turn a green run into a false positive

Read at PHASE 2, when a screen fails or a suite is green too easily. Each of these produces a run that proves nothing while looking fine.

## Contents
- A screen is never opened without what it requires
- A front-office proof targets the portlet, on a page that renders portlets
- The seed lands on a running application
- REST resources are inventoried, and a browser does not test them
- An artefact with no screen of its own
- Order between scenarios, and state they share
- The bench protects itself

## A screen is never opened without what it requires

The inventory lists a back-office JSP as `jsp/admin/plugins/<plugin>/<Screen>.jsp`, with no query string. Many of
those screens cannot answer without parameters: a portlet creation screen reads `page_id` and `portlet_type_id`, a
modification screen reads `portlet_id`. Opened bare they return an internal error, and the suite then records a
broken screen — a false defect that hides the real coverage.

`inventory.py` therefore reports, for every JSP screen, the request parameters its bean method actually reads, in
`needs_params`. **Before the first full run, read them and declare a query for each one** in
`scenarios/screens.yaml`:

```yaml
params:
  - match: 'CreatePortlet[A-Za-z]*\.jsp'
    query: 'page_id=1&portlet_type_id=<THE PORTLET TYPE OF THE ARTEFACT>'
  - match: 'ModifyPortlet[A-Za-z]*\.jsp'
    query: 'portlet_id=9001'
```

The values must exist in the seed: page 1 is the root page of any install, and the portlet id is the one
`harness/db/seed-<plugin>.sql` creates. Check what is left:

```bash
python3 -c "import json;[print(s['id'], s.get('needs_params')) for s in json.load(open('e2e/artifacts/inventory.json'))['screens'] if s.get('needs_params')]"
```

Portlet screens are a second, related trap: they are included through `PortletAdminHeader.jsp` and therefore render
without the admin menu bar, so the classifier reads them as fragments, not screens. Declare them under `fragment` in
the same file:

```yaml
fragment:
  - 'Portlet[A-Za-z]*\.jsp'
```

The same key covers the **front office**: a page the artefact serves as its own complete document — an
`XPage.setStandalone( true )` answer, an embedded viewer, a print view — carries neither the portal chrome nor
the admin bar, and its kind then depends on what its widgets happened to inject by the time the step ran
(`public-form` once the widget built a form, `unknown` before). Declare it and the fo suite, the screens suite
and `expect_ok` all judge it on the negative: it must not be an error page, a blank body, a lost session or an
HTTP error. Its behaviour is then proven by the scenario's own DOM assertions, which is where it belongs.

```yaml
fragment:
  - 'view=swaggeriframe'
```

A screen that still fails **with** its parameters is a real defect of the plugin, and that is exactly what the bench
is for: an unguarded `Integer.parseInt` or a missing null check answering 500 instead of a message. Report it, do not
paper over it with an allowlist entry.

## A front-office proof targets the portlet, on a page that renders portlets

Two traps that turn a front-office scenario into a false positive:

**The page template decides whether a portlet is rendered at all.** Page 1 of a fresh install uses the `Demo`
template (`skin/site/page_demo.html`), which renders no portlet column. A portlet seeded there is never shown, and
nothing says so: no error, no empty block, just a page without it. Seed a host page with a template that has
columns (`One column`, id 2) and put the portlet there:

```sql
INSERT INTO core_page (id_page, id_parent, name, description, status, page_order, id_template, role, code_theme, node_status)
SELECT 9003, 1, 'E2E Host', 'Host page rendering the portlet', 1, 9003, 2, 'none', 'default', 0
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM core_page WHERE id_page = 9003);
```

**The oracle must target the portlet's own markup.** `expect_text` on the name of a linked page passes on the site
menu, which lists every published page, whether or not the portlet rendered. Assert on a selector the portlet alone
produces:

```yaml
- expect_dom: {selector: 'div.portlet-content a[href*="page_id=9002"]', min: 1}
```

Checked by hand once per bench: open the front-office page and look for the portlet's CSS class in the HTML. A
`grep -c portlet` returning zero on the page that is supposed to carry it means the bench is proving nothing, even
when every scenario is green.

## The seed lands on a running application

`run.sh up` waits for the application to be **healthy**, then seeds. So anything the artefact cached from the
tables while booting holds the state of an **empty** database — and a Lutece cache lives 24 h by default, which
means for the whole run. It bites in a specific shape: a daemon that makes one pass shortly after boot, reading
a list the cache has already frozen.

`plugin-forms` is such a case: it warms `formsCacheService` with its form list at boot, its indexer daemon
makes its single full pass 20 s later, and its multiview reads a Lucene index rather than the tables — the
bench is green or empty depending on whether the seed landed inside those 20 s.

```
E2E_RESTART_AFTER_SEED=1
```

`run.sh up` then restarts the application once on the seeded database and waits for it to be healthy again.
Set it whenever the target reads something cached at boot — a form list, a type registry, a reference list —
instead of chasing a race whose outcome depends on how fast the seed ran.

## REST resources are inventoried, and a browser does not test them

`inventory.py` reads the artefact's JAX-RS resources: every class importing `jakarta.ws.rs.Path`, its class-level
`@Path` and each method's verb and sub-path, with the constants resolved recursively (a Lutece path is usually
`RestConstants.BASE_PATH + PLUGIN_NAME + SOME_CONST`, and a constant is often itself a concatenation). They land
in the inventory with `surface: "rest"`, are counted in `surface.rest_endpoints`, and `inventory.md` lists them
with their url and their **authentication binding**.

That last column is the point. A v8 REST resource is protected by a `@NameBinding` `ContainerRequestFilter` of
its own plugin, and a class that carries no such annotation is served unauthenticated with nothing in the build
to report it — `surface.rest_unbound` names those classes. Treat it as a question, not a verdict: the plugin may
never have protected anything, or its protection may have fallen during the migration. The descriptor filter that
used to do the job no longer runs under `/rest/` (`rules/rest-resource.md`), so a module that had one and lost it
looks exactly like a module that never had one.

**A REST endpoint is tested with the `http` step, never with the screens suite**: a browser negotiates a
representation nobody asked for and judges markup that does not exist. Write scenarios that call it as a client
does, assert the **body and the state** rather than the status — an endpoint whose parameters did not arrive
answers 200 with an empty body — and use `sign` when the plugin protects it:

```yaml
- http: {url: 'rest/myplugin/delete', method: POST, body: 'id=42', expect_status: 401}
- http:
    url: 'rest/myplugin/delete'
    method: POST
    body: 'id=42'
    headers: {Content-Type: 'application/x-www-form-urlencoded'}
    sign: {elements: [id], private_key: 'change me'}
    expect_status: 200
- sql: {query: "SELECT COUNT(*) FROM myplugin_thing WHERE id=42", expect: 0}
```

`sign` reproduces the library's scheme — sha1 of the named parameters' values in order, then the private key,
then the timestamp, in `Lutece-Request-Signature` and `Lutece-Request-Timestamp`. Values come from the query
string and from a urlencoded body; a multipart part is never one, which is the server's rule too. The three
calls together are the proof: refused without, refused with a wrong key, accepted and effective with the right
one.

## An artefact with no screen of its own

Some artefacts expose neither a back-office screen, nor an XPage, nor a library API a probe could call: a
`ContentService`, an indexer, a component registered by the descriptor (`*-class` tags) or discovered by CDI.
The inventory sees nothing, the screens/fo/forms suites have nothing to open, and `summary.md` says so
("surface mécanique nulle"). The proof is then **scenarios only**, on the component's observable effects:

- what it renders when the site calls it (the `Portal.jsp` parameters that route to a content service, a
  portlet page that embeds it), asserted on the DOM it produces;
- what it writes or indexes, read back where it lands (`sql`, `http` on the engine's own API with `poll`
  for an asynchronous pass, an admin screen of the host plugin that lists the result);
- what it refuses (unknown ids, non-numeric parameters, a call without its trigger) answered by a message,
  never an internal error.

A component with **no mutation at all** (no form, no action, no SQL write) has no CSRF scenario to write:
record the proof of absence in `scenarios/coverage-exclusions.yaml` as prose (no `Do*`, no web bean, no
write in its DAOs) instead of forcing one. The "0 à faire" of the coverage table is then a statement about the
inventory, not about the artefact — read the scenarios.

## Order between scenarios, and state they share

Scenarios of the parallel pass run in any order, on several workers; `serial: true` ones run **after** the
whole parallel pass, one at a time. A scenario never relies on the declaration order or on what another
scenario created: it arranges its own state (`sql_exec` before its first mutation, `{{rand}}` keys) and
carries its own proof. The application caches too: two scenarios sending the **same request parameters**
share one cache entry, and the second asserts on what the first made the application render — give each
scenario its own discriminating value (a different term, id or key).

## The bench protects itself

`run.sh test` re-seeds before running (the forms fuzzer consumes keyed reference rows; the seed restores them),
the fuzzer never touches the bench accounts nor plugin/cache toggles (`PROTECTED_SCREEN`, `DENY`), and
`run.sh` checks after the tests that the admin account it authenticates with (id 1) is intact — otherwise the
report opens on the alert and the exit code is 4. Accounts a bench seeds for its own target are that bench's
business: assert them in its scenarios, and shield them from the fuzzer with `scenarios/screens.yaml` (`protected`). A finding observed on a row another test may have consumed
(a "duplicate key accepted" that was actually a fresh insert) is not a finding: check the row exists first.


## Naming a rendering defect (PHASE 4b)

Before naming a rendering defect, **check its cause in the source**. A visual symptom is not a diagnosis, and
this step is where a report earns or loses its credibility. Two misreadings to avoid:

- a button showing a bare `?` is not a missing icon when the Tabler glyph the icon name maps to **is** a question
  mark — the defect is the choice of icon, not a broken asset;
- a form control with no styling is not "the plugin ignores the design system" when the plugin calls the core
  macro correctly and that macro's branch emits Bootstrap 4 classes — the defect belongs to the core.

Grep the template, follow the macro, read the icon set. Then write the finding, and attribute it.

Two traps this step exposes, each worth reporting on its own:

- **Captures that are all the same page.** A screen called without its identifiers usually redirects to a guard
  page, so its capture shows something else. `review.py` prefers a parameterised call as the representative
  and flags any group whose capture is byte-identical to another's with *capture identique à Gxxx (probable
  redirection)*. Such a group is **not judgeable**: report it as a coverage gap, not as a passing screen.
- **Fragments.** A template loaded standalone carries no layout of its own; `render_check` already skips the
  stylesheet test for `kind == "fragment"`. The eye still has to ask whether the markup uses the design system
  once embedded.


## A full-page capture resizes the page under a responsive widget

Every `goto`, `submit` and `click` of a scenario is photographed full page, and Chromium does it by resizing the
viewport: resize events fire in the middle of the scenario. A widget that follows its container (an image cropper,
a chart, a map) rescales on them, sometimes to zero, and the next step fails with nothing pointing at the
screenshot. A scenario driving such a widget declares `viewport_shots: true`.

## A mail sent by a workflow task waits for the next daemon run

A workflow action runs inside a transaction (core `WorkflowService.doProcessAction`), and `MailService.enqueue`
wakes the mail daemon before that transaction commits: the daemon finds an empty queue, and the mail waits for the
next scheduled run (`daemon.mailSender.interval`, a day by default). A `mail:` step after a workflow action is then
red while the application is right. Run the mailSender daemon from the daemons screen (`ManageDaemons.jsp`, action
run) in the scenario before the `mail:` step, and report the ordering as a core defect.

## Seeding plugin-forms for a front-office bench

A form row the front office cannot render answers 500 or "unavailable" with nothing pointing at the seed:
`breadcrumb_name` must name an existing bean (`forms.horizontalBreadcrumb`, `forms.verticalBreadcrumb`),
`composite_type` is lower case (`question`, `group`), `css_class` must not be NULL (the geolocation entry reads
`entry.CSSClass`), and the availability dates must frame the run, or the form shows as unavailable.
