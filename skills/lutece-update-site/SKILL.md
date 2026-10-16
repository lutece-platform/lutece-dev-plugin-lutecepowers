---
name: lutece-update-site
description: "Use when bringing a Lutece site (packaging lutece-site: a site, a pack or a theme) to the Lutece 8 level lutecepowers supports, whatever its starting point: migrating a v7 or older site, or updating a v8 site (parent, BOM, starter, pack). Checks first that every artefact the site ships has a Lutece 8 version and hands the missing ones to lutece-update-plugin; then proves that nothing the site configured, shipped or overrode is lost, by comparing the assembled site before and after and by running it. Triggers when the user asks to migrate or update the whole site: 'migrer un site', 'passer le site en v8', 'mettre à jour le site', 'montée de version du site', 'monter le pack', 'site v8', 'migrate site', 'update site'."
metadata:
  summary: "Update a site, pack or theme to Lutece 8, from any version."
---

# Lutece update — site

A site owns almost no code. What it owns is a composition (parent, BOM, starter, pack, plugins) and a configuration
layered over its dependencies, and that is what an update breaks without any error: a key deleted "because the pack
provides it", a plugin a starter no longer brings, a Spring context v8 ignores, a per-environment directory the v8
parent no longer copies, a library that imposes its own values. So nothing here is judged on the sources or on a
commit message: the site is its assembled war, before and after, and the configuration the running site resolves.

One tool carries every check and every conversion a script can make: `tools/site_check.py` (`gate`, `check`,
`config`, and the converters `envconf`, `spring`, `rebase`, `plugins-dat`; the codes are in `tools/checks.md`,
section Site). `tools/site-assemble.sh` builds the war the checks read, `tools/site-bench-war.sh`
the war the bench runs. Show the user the outcome of every phase before starting the next one: an update of a site
is a series of decisions that belong to its owner, not a script.

## PHASE A — Where the site starts, and its before state

```bash
mkdir -p .migration
for p in 'target/' '.migration/' 'e2e/'; do grep -qxF "$p" .gitignore 2>/dev/null || echo "$p" >> .gitignore; done
```

1. **Identify** the parent (`lutece-site-pom` version), the resolved core, the layer the site stands on (a pack, a
   starter, a theme, or an explicit list of plugins) and the archetype (`reference/archetypes.md`).
2. **Ask the user for a dump of the recette database** (the environment closest to production, anonymised when it
   holds personal data), before any change: it is the only way to prove the upgrade of the data the environments
   hold (phase F). Keep it outside every repository, never commit it, delete it when the update is delivered.
   Without one, go on, and the hand-over says in its first lines that the database upgrade is not proven.
3. **The before ref** is the state the environments run, not the fork point of a v8 branch: for a v7 site the tip
   of its v7 branch (`develop_core7`, `master_core7`) or the tag in production; for a v8 site the tag or the commit
   the environments run (then no `--profile` and no `--as-profile`: a v8 war already holds every profile). Ask the
   user when it is not certain. `check` later reports every commit of another branch after the ref (SI86).
4. **Assemble the before state**, one war per environment when the site has `src/conf/<env>/`, and one without any
   environment profile for the bench of phase F:

```bash
bash ${LUTECEPOWERS_ROOT}/tools/site-assemble.sh . --ref <before_ref> [--profile <env>] \
     --out .migration/before[-<env>] --repo .migration/m2 [--settings <settings.xml>]
```

   A v7 pom resolves its ranges today, not on the day the environments' war was built: a range can reach a Lutece 8
   artefact (a Java 17 jar), and the before state is then not what runs. The gate reports it (`DRIFT`); rebuild with
   `--pin <group>:<artifact>:<the v7 version>` (the worktree pom only) until it reports none.
   A private artefact (a pack, a theme, a configuration library) that no repository the build reaches serves is
   built from its source tag into the same `--repo`; never install into `~/.m2` (it would shadow the published
   snapshot for every project of the machine). A v7 build that cannot resolve its v7 parent through the user's mirror gets its own
   settings file (`reference/archetypes.md`, Build).

## PHASE B — Every artefact has a Lutece 8 version (blocking)

```bash
python3 ${LUTECEPOWERS_ROOT}/tools/site_check.py gate .migration/before --site . --bom <lutece-bom-8.x.pom> \
        --m2 .migration/m2 [--repo-url <a private repository the user gives>]
```

`--m2` reads the artefacts built into the isolated repository first (a private pack rebuilt from its tag shows as
`LOCAL`); `--repo-url` adds a repository the user names for this run (an organisation's private one). Never write
such a url into a file of the toolkit or of the site. `.migration/before.tree` (written by `site-assemble.sh`) lets
the gate say which direct dependency brings each blocker: an artefact only a replaced layer brought is a plugin
decision, not a blocker.

The target BOM is the one the site will import (the latest released `lutece-bom` 8, or the one the user names).
Each Lutece artefact the before war ships, and each lutece-site dependency of the pom (theme, pack), gets a status:

| Status | Meaning | What to do |
|---|---|---|
| `BOM` | managed by the target BOM | nothing: the site declares it without version |
| `STARTER` | a starter | the version of the target BOM |
| `PUBLISHED` | a release with a Lutece 8 parent, outside the BOM | the site pins that version |
| `LOCAL` | a Lutece 8 version found only in the isolated repository (a private artefact rebuilt from its tag) | the site pins it; the release needs it published where the build looks |
| `SNAPSHOT` | a Lutece 8 snapshot only, or the snapshot the target BOM manages | tell the user: a site released on it changes under its feet; pin the last release when there is one |
| `NO-V8` | no published version with a Lutece 8 parent | blocker |
| `DRIFT` | a jar of the v7 before war built for Java 17 | the before state is polluted: pin and assemble it again (phase A) |

For each `NO-V8`, in this order: its successor, which the gate prints from `tools/site-successors.tsv` (public
artefacts) and from the organisation's own file (`$LUTECEPOWERS_SITE_SUCCESSORS`, else
`~/.config/lutecepowers/site-successors.tsv`: its private themes and packs, kept out of this toolkit); its v8 branch
in its repository on GitHub or GitLab (`develop`, with a Lutece 8 parent); otherwise it has to be migrated first. **Stop and show the user the list**, the dependency order, and propose to migrate each
missing artefact with the `lutece-update-plugin` skill, one at a time, in its own clone, then to build it into
`.migration/m2`. Resume the site only when the gate has no `NO-V8` left, or when the user decides that an artefact
leaves the site (then it is a plugin decision of phase C, never a silent drop).

## PHASE C — The target composition

Pick the layer (`reference/layers.md`): the organisation's pack of the family when there is one, else the starter
of the family, else an explicit list. Then map every plugin of the before war, in `.migration/site-decisions.md`,
one line each:

```
- plugin <name>: <provided by the pack | declared by the site | dropped because ...>
```

A plugin the before war ships and the new layer does not bring (a starter that dropped the address modules, a
module moved out of the BOM) is declared by the site or dropped with the owner's agreement. Show the plan.

## PHASE D — The steps

| Step | File (`steps/`) | Scope |
|---|---|---|
| 1 | `1-pom.md` | parent, BOM import, starter or pack, versions, types, profiles |
| 2 | `2-configuration.md` | overrides, per-environment conf to MicroProfile profiles, Spring contexts, database, secrets |
| 3 | `3-webapp.md` | `plugins.dat`, template and JSP overrides, `web.xml`, static files |
| 4 | `4-database.md` | SQL of the site, an existing database, the settings the takeover changes |
| 5 | `5-runtime.md` | Liberty `server.xml`, `server.env`, `jvm.options`, the JDBC driver |

After each step: `site-assemble.sh .` into `target/`, then `site_check.py check` (phase E). Change what the level
requires, nothing else.

## PHASE E — Nothing lost (the gate)

```bash
bash ${LUTECEPOWERS_ROOT}/tools/site-assemble.sh . --out .migration/after --repo .migration/m2
python3 ${LUTECEPOWERS_ROOT}/tools/site_check.py check . --war .migration/after \
        --before .migration/before[-<env>] --before-ref <before_ref> [--as-profile <env>] --m2 .migration/m2
bash ${LUTECEPOWERS_ROOT}/tools/lutece-check.sh .
```

`--as-profile <env>` compares the war of one v7 environment with the v8 war read under that profile: run it once
per environment. Every difference is a FAIL until `.migration/site-decisions.md` answers it (`- key|plugin|file|profile
<id>: <reason>`): an effective value the site set, or an artefact it added or removed, changed (SI80); a plugin no
longer shipped (SI81); a file of the site overlay no longer shipped or no longer the site's (SI82); a profile the
site names that appears or disappears (SI84). A key the site sets that the war no longer reads while it reads the
same key under a new name, with another default, is a setting lost (SI27 FAIL): carry it under the new name. A
reason states the evidence ("same value in the pack, read in its
war", "no form uses the address field: SELECT … returned 0"), never "provided elsewhere". Values of the core and of
the plugins that change by themselves between versions are listed apart (SI85, a file), for reading, not decisions.

Fix every FAIL at its source and every WARN, or write its reason in the hand-over. The runtime dump of phase F
(SI87) settles what the static model cannot see: the values a remote ConfigSource serves (Vault, at 500, above the
site's `conf/override`), the environment, the Liberty variables.

## PHASE F — Run it

Dispatch one subagent: "invoke the `lutece-e2e` skill on this site (`init-e2e.sh <site> --target site`, then `lpe2e`)
and follow it; report the startup exceptions, the back-office login, the front-office home, the screens of every
plugin the site ships, the configuration dump and the Lutece versions the bench forced over the site's BOM". The
bench assembles the site with its own pom (`E2E_SITE_PROFILE` names a profile without the environments' remote
configuration source, Vault), with the latest Lutece 8 snapshots of the core and of plugin-liquibase forced over the
BOM, and tests every screen of the site. It writes `artifacts/site-drift.txt` when the site ships an older core than
the one tested: an older core in the BOM is a finding. The configuration probe is in the bench site:
`curl "http://localhost:$(lpe2e port)/<context>/site-config-dump.jsp?token=$(cat e2e/artifacts/site-config-dump.token)"`
on a running bench (`KEEP=1 lpe2e`). While it runs, edit nothing. Then, with the dump and the container environment
it brings back (`docker exec <app> env`):

```bash
python3 ${LUTECEPOWERS_ROOT}/tools/site_check.py config .migration/after --against <dump> --env <env file> [--profile <p>]
```

It must report no disagreement: the model of phase E is trusted only where the container agrees with it. The bench
runs without the profiles of the environments: it never reaches their systems (identity provider, search cluster,
notification gateway). A fresh install proves nothing about an upgrade: a v7 site writes the scripts of its takeover
(`site_check.py takeover .migration/before-default .migration/after --out .migration/takeover`, SI13-SI14), then runs
`lpe2e upgrade` with `E2E_V7_WAR` (its v7 war, assembled without profile, carrying plugin-liquibase of the v7 line), `E2E_V7_DUMP` (the recette dump of phase
A) and `E2E_TAKEOVER` (`.migration/takeover`): the v7 site starts once on the dump with plugin-liquibase, the v8 site takes it over the way
`reference/database.md` §1 describes (core first, then the components), and `artifacts/datastore-lost.txt` lists the
settings the takeover changed or removed, to set again (§2). The takeover scripts are not a bench device: they set what
plugin-liquibase cannot read on a v7 database installed with Ant (the version of a component it could not resolve,
the former identity of a renamed one), and an environment that starts without them can lose tables. Hand them over;
`E2E_TAKEOVER` on a directory of two empty files shows the start without them (`reference/upgrade.md` of lutece-e2e). A v8 site runs `lpe2e upgrade` with `E2E_BEFORE_WAR` (the war
`site-bench-war.sh .migration/before <file>` writes): the version the environments run creates its database, the
new one takes it over; every plugin `artifacts/upgrade-disabled.txt` lists is disabled after the deployment (a
renamed plugin still listed in `plugins.dat` under its former name, SI43), every name `upgrade-orphans.txt` lists
has status keys nothing reads any more.

## PHASE G — Hand over

Give the user, copied from the tools and never summarised from memory: whether the database upgrade was proven on
a recette dump (and the settings `datastore-lost.txt` lists), the two takeover scripts the environments' databases
need, the gate table, the `check` result with the
decisions file, the runtime comparison, the bench result with each failure attributed (site, plugin, core), the
profile each environment must set, the secrets to put in Vault (SI30), and `git status --porcelain`. **Never
commit.** A commit message the user writes from this is true by construction: it lists what the tools listed.

An example of a v8 site on the BOM and a starter, with its Open Liberty configuration and Kubernetes manifests: the
`mono-instance` branch of https://github.com/lutece-platform/lutece-guide-kubernetes-lutece.

A site that must then run as several replicas: `lutece-site-multi-instance` (example: the `multi-instance` branch of the
same repository).

## Rules the tools cannot enforce

- Never delete a key, a file or a dependency because "the pack, the starter or a configuration library provides
  it" before `check` proves the effective value, the plugin or the file is the same after (SI80-SI82).
- Never rename a MicroProfile profile, or introduce one, without the user confirming the profile each environment
  sets (`mp.config.profile` / `MP_CONFIG_PROFILE`, often outside the repository): SI84.
- Never write a secret into the repository, even as a draft: `envconf` leaves secrets out, and so does every file
  you write. List them for Vault or the environment.
- A library that imposes configuration (a ConfigSource in a jar) is a set of decisions: each key it changes appears
  in SI80 and is kept or overridden in `conf/override`, deliberately.
- Never convert what never applied: a file of `src/conf/<env>/` placed where v7 read nothing (SI32), a context v7
  never loaded. Carrying it would change the environment's behaviour; list it for the owner instead.
- The site's `webapp/` wins over every dependency, but two dependencies shipping the same file land in an unspecified
  order (SI57): the site ships its own copy when it matters.
