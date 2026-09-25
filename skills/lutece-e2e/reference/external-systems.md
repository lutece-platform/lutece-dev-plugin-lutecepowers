# Bench — external systems and search engines

Read when the artefact under test calls an outside system, or indexes into Solr or Elasticsearch. A bench whose artefact calls nothing needs none of this.

## Contents
- Fakes — the external systems as stand-ins
- Search engines — the real ones

## Fakes — the external systems as stand-ins

Many Lutece artefacts call systems the bench does not have: CAS, an OIDC provider, the identity store, notifygru,
the CRM, TIPI/PayFiP, ANTS, and an organisation's own APIs. Without them a
flow dies at the first call and the scenario proves nothing. The harness ships stand-ins for the systems whose client code is public, and loads an
organisation's own from `harness/fakes/extra/` (ignored by git, see its README); all off by default: set `E2E_FAKES=1` in `e2e.conf` when the artefact under test reaches one of these systems,
leave it empty otherwise (a core bench never needs them).

**Two containers, compose profile `fakes`** (`./run.sh` adds the profile when `E2E_FAKES=1`):

- `fakes` — `harness/fakes/app.py`, one Python process on port 9030, one URL prefix per system. Every request
  is appended as a JSON line to `artifacts/fakes/<channel>.log` (`cas`, `crm`, `tipi`, `notifygru`,
  `identitystore`, `ants`, plus the channels the extra modules log): that file is the oracle surface, and the `fake_log`
  step reads it — `fake_log: {channel: notifygru, contains: '"demand_id": 42', min: 1}`, with `contains` matching
  inside the logged payload, so the scenario proves **what** was sent and not merely that something was. It polls
  like `mail`, because a Lutece daemon usually sends after the response is rendered, and `{absent: true}` asserts
  the opposite: nothing left. `/health` answers 200.

  **Check first whether the artefact calls anything at all.** A module named after an external system is often a
  *provider*: it computes the markers another plugin's task will send (addresses, texts, urls) and issues no
  request of its own. Its bench needs the consuming plugin installed, not a fake.
- `oauth2` — `ghcr.io/navikt/mock-oauth2-server`, an OpenID Connect provider with an interactive login page and
  two issuers configured in `harness/fakes/oauth2.json`: `paris` (a citizen account through mylutece-oauth2) and
  `franceconnect`. Any username logs in; the claims are fixed (`e2e-citoyen`, `citoyen@e2e.local`, born
  1980-01-01). Discovery: `http://oauth2:8080/<issuer>/.well-known/openid-configuration`. The browser reaches it
  too: the runner shares the application's network namespace, so `http://oauth2:8080/...` resolves there.

**Pointing the application at them.** Properties go in the assembled site,
`harness/site/webapp/WEB-INF/conf/override/plugins/<plugin>.properties` (kept across `gen-site.sh` runs), or as
environment of the `lutece` service when the property is read through MicroProfile Config. Check the artefact's own
`.properties` for its exact keys.

**Proving a fix of an upstream plugin before it is published.** Build the fixed clone with `mvn install`, then
run the bench with `E2E_MVN_OFFLINE=1`: the v8 legs resolve snapshots from the local repository, where the
patched build now sits, instead of the remote copy Maven prefers when it is newer. The v7 leg keeps downloading
its own artefacts. Check the war afterwards: `unzip -p harness/site/target/lutece.war WEB-INF/classes/sql/...`
must show the change, otherwise the run proved the old build. List the fixed plugin on both legs (`E2E_PLUGINS`
and `E2E_V7_PLUGINS`) so the upgrade path runs; `run.sh compare` is the proof, a fresh install never runs an
upgrade script.

**On the v7 leg, a Spring literal reaches nothing.** The v7 core reads its `.properties` through MicroProfile
Config (`AppPropertiesService`), so the environment the v8 leg is configured with reaches those values too. An
endpoint written as a literal in a Spring context XML reads nothing: the v7 leg then calls the real outside system,
the v8 leg calls the stand-in, and the comparison reads the difference as a fix the migration did not make. The
way out is bench-side: `harness/v7-overlay/`, laid over the assembled v7 webapp after assembly — same paths as the
webapp, for what only a file can change, a `<plugin>_context.xml` whose endpoint is written in the bean
definition. The property override directory above is copied to the v7 site too. Check the key the artefact really reads: a module may read
`oauth2.issuer` in v7 and `oauth2.server.issuer` in v8, and setting the wrong one changes nothing.

**The v7 leg builds against today's repositories, not against 2020's.** An artefact whose pom carries an open
range (`[1.0.0,3.9.9)`) resolves the newest matching artefact, which may be years past anything it ever ran on —
and the leg then fails to compile, or compiles and takes the whole v7 site down at boot. That is not the v7 to
compare against: deployed sites run the artefact's last release with the dependency it was built for. Reproduce
**that** one. `harness/src7-overlay/` is laid over the disposable worktree *before* the build (so it can change
`pom.xml`, unlike `harness/v7-overlay/` which lands on the assembled webapp), and `E2E_V7_PLUGINS` assembles the
matching version. Pin the version exactly rather than capping the range: Maven orders `3.3.0-SNAPSHOT` **below**
`3.3.0`, so `[1.0.0,3.3.0)` still admits the snapshot you were trying to exclude.

Two rules follow. **Never overlay the sources to make the v7 leg compile** — changing an import to the newer
library's package hides exactly the incompatibility the leg exists to reveal, and the result is a v7 that never
existed. Overlay the pom instead, so the artefact meets the platform it was written against. And **say in the
overlay's README what was pinned and why**: the reader of a comparison has to know which v7 it is.

| System | Property → URL |
| :-- | :-- |
| CAS (mylutece-cas) | server URL `http://fakes:9030/cas` — login `/cas/login?service=…`, `serviceValidate`, `proxyValidate`, `logout`. Accounts `admin` and `pro` (GUID `E2E_PRO_GUID`); any other name logs in with `pro`'s profile and that name as GUID |
| Citizen account / OIDC | `oauth2.server.issuer=http://oauth2:8080/paris`, `oauth2.server.authorizationEndpointUri=http://oauth2:8080/paris/authorize`, `oauth2.server.tokenEndpointUri=http://oauth2:8080/paris/token`, `oauth2.client.clientId` and `clientSecret` free (`TMMA` / `e2e-secret` in the reference bench) |
| Identity store | `identitystoremyluteceprovider.apiManagerEndPoint=http://fakes:9030/identitystore/token`, `identitystoremyluteceprovider.identityStoreEndPoint=http://fakes:9030/identitystore/identity` — one identity, `family_name`/`first_name`/`email`, `connection_id` echoed from the query |
| notifygru | `<plugin>.notifygru.api.manager.endpoint=http://fakes:9030/notifygru/token`, `<plugin>.notifygru.notification.endpoint=http://fakes:9030/notifygru/notification/v1/send` — every notification is accepted and logged |
| ANTS (module workflow-appointmentants) | `ants.api.url.base=http://fakes:9030/ants`, the paths keep their defaults (`/api/appointments`, `/api/status`). **Stateful**: a POST records the appointment, so `/api/status` returns it keyed by application number (`{"AB123": {"status": "validated", "appointments": [...]}}`) and DELETE answers a real `rowcount`. An application number starting with `E2EKO` is refused everywhere (`status: in_progress`, `success: false`), which is how the plugin's failure branch is reached. The `x-rdv-opt-auth-token` header is logged, so a scenario can prove the token was sent |
| BAN address search (module address-autocomplete, suggestPOI in the browser) | `address-autocomplete.suggestPOI.ws.url=https://fakes:9443/ban/search/` (https: the core CSP carries `upgrade-insecure-requests`, so a page's plain-http fetch is rewritten; the fakes answer https on 9443 with a test certificate the bench browser accepts; the site's CSP must list the host in `connect-src`, as a real site lists the BAN) — `?q=&limit=` answers the BAN GeoJSON (`features[].properties.label`, `geometry.coordinates` lon/lat) for three fixed Paris addresses (`4 Rue de Rivoli`, `Place de l'Hôtel de Ville`, `8 Boulevard du Palais`) whose label holds every word of the query; CORS open, each call logged in `ban.log` |
| CRM (library-crmclient, crm-formengine) | `crmclient.crm.rest.webapp.url=http://fakes:9030/crm` (also `.part`, `.pro`), `crm-formengine.webapp.crm.rest.url=http://fakes:9030/crm` — `createByUserGuid`/`createByIdCRMUser` return a fresh id, `user_guid` returns `E2E_PRO_GUID` |
| TIPI / PayFiP | `<plugin>.tipi.urlwsdl=http://fakes:9030/tipi/services/securite` (SOAP `creerPaiementSecurise` → `idop`, `recupererDetailPaiementSecurise` → `resultrans`, `A` until paid). The payment page is `http://fakes:9030/payfip/?idop=…`: the browser posts `resultrans=P`, the stand-in calls the application's `urlnotif` then redirects to `urlredirect`. `E2E_FAKES_PORT` exposes it to a host browser |

**Fixtures live in `app.py`**: CAS accounts (`CAS_USERS`), the pro GUID (`E2E_PRO_GUID` in `e2e.conf`). Add a case
there when a scenario needs another user; state is in memory (tickets, payments) and starts empty at each `up`.
A look from the host: `http://localhost:19030/cas/login`, `http://localhost:19030/health`,
`http://localhost:19085/paris/debugger` (`E2E_FAKES_PORT`, `E2E_OAUTH2_PORT`, the values of `e2e.conf`).

## Search engines — the real ones

A stand-in cannot answer a query the way an index does: relevance, facets, highlighting and the indexer's own
mapping are exactly what a search bench measures. So these two are real engines, not fakes, in the compose
profile `search` (`E2E_SEARCH=1`). They start empty; the application's own indexer fills them, which is the
behaviour under test.

| Service | Image | Reached as | Host port |
|---|---|---|---|
| Solr | `solr:9.10.1-slim` (the version of the `solr-solrj` `plugin-solr` depends on) | `http://solr:8983/solr/${E2E_SOLR_CORE}` → `search-solr.properties` `solr.server.address` | `E2E_SOLR_PORT` (18983) |
| Elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:9.5.3`, single node, security off | `http://elastic:9200` → `elasticdata.properties` `elasticdata.elastic_server.url` | `E2E_ES_PORT` (19200) |

Both legs get the address written for them: `gen-site.sh` and `gen-site7.sh` drop an override
(`WEB-INF/conf/override/plugins/search-solr.properties`, `elasticdata.properties`) into the assembled site when
the plugin is there and the bench ships none of its own. Without it the plugin keeps its packaged default
(`localhost:8983`, `localhost:9200`), the indexer writes nowhere, and nothing fails on screen: the index is
simply empty, which a scenario only catches when it reads the engine back.

The core is created at startup. `plugin-solr` ships its own `solrconfig.xml` and `schema.xml` in
`webapp/WEB-INF/plugins/solr/conf`: point `E2E_SOLR_CONF` at that directory (path relative to `harness/`) or the
core is built from the `_default` configset — enough to prove the site boots and connects, not enough to index.
Both containers are health-gated, so `run.sh up` waits for them like it waits for the database.

