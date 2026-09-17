# Bench configuration, sourced by run.sh and tools/gen-site.sh.
# Target under test: core | plugin | site
E2E_TARGET=@@TARGET@@
# Source root of the artefact under test, relative to this file.
E2E_SRC=..
# Compose project name (also prefixes container and volume names).
E2E_NAME=@@NAME@@
# Servlet context and host ports.
E2E_CONTEXT=lutece
# plugin-liquibase runs the plugins' SQL at first boot. Before 2.0.2-SNAPSHOT it sorts the files alphabetically and
# ignores `--lutece runAfter:<plugin>`, so a plugin whose SQL feeds another plugin's tables installs too early.
E2E_LIQUIBASE_VERSION=

E2E_PORT=@@PORT@@
E2E_DB_PORT=@@DBPORT@@
# Extra artefacts to assemble, as groupId:artifactId:version:type, comma-separated (runtime deps not pulled transitively).
E2E_PLUGINS=
# Core the site runs on (plugin target): default = the version the plugin's pom resolves (mvn dependency:list).
#E2E_CORE_VERSION=
# Plugin names to mark installed in plugins.dat (comma-separated; the plugin under test is added automatically).
E2E_ENABLE=
# Front-office authentication: plugin-mylutece + module-mylutece-database are assembled and enabled, with the
# account test/testtest (harness/db/post-init-mylutece.sql). 0 leaves them out. Versions: v8 side, and v7 side for compare.
E2E_MYLUTECE=1
#E2E_MYLUTECE_VERSION=5.0.1-SNAPSHOT  E2E_MYLUTECE_DATABASE_VERSION=7.0.1-SNAPSHOT  E2E_V7_MYLUTECE_VERSION=4.0.8  E2E_V7_MYLUTECE_DATABASE_VERSION=6.0.5
# Scope of the screens/forms suites and of the crawl: target (the artefact under test only, default) | all (whole site).
E2E_SCOPE=target
# Mailpit UI (every mail sent by the application): http://localhost:<port>
E2E_MAIL_PORT=@@MAILPORT@@
# Stand-ins for the external systems (CAS, Mon compte, identitystore, notifygru, CRM, API Particulier, TIPI/PayFiP,
# OpenID Connect for a citizen account and FranceConnect, an organisation's own under harness/fakes/extra/): 1 starts them, the site reaches them as
# http://fakes:9030/<service> and http://oauth2:8080/<issuer>. Empty = off. See SKILL.md § Fakes.
E2E_FAKES=
# Host ports of the stand-ins, for a look from the browser (fakes: /health, /cas/login ; oauth2: /<issuer>/debugger).
E2E_FAKES_PORT=@@FAKESPORT@@
E2E_OAUTH2_PORT=@@OAUTH2PORT@@
# Search engines (real ones, not stand-ins): 1 starts solr and elasticsearch, the site reaches them as
# http://solr:8983/solr/<core> and http://elastic:9200. Empty = off. See SKILL.md § Search engines.
E2E_SEARCH=
E2E_SOLR_PORT=@@SOLRPORT@@
E2E_ES_PORT=@@ESPORT@@
# Solr core created at startup. Its schema is taken from the search plugin inside the assembled site
# (WEB-INF/plugins/solr/conf) when it is there; E2E_SOLR_CONF (a directory holding solrconfig.xml and schema.xml,
# path relative to harness/) overrides it; without either the `_default` configset is used.
E2E_SOLR_CORE=lutece
#E2E_SOLR_CONF=
# Restart the application once after the seed. The seed runs on a healthy application, so whatever the target
# cached from the tables at boot holds the state of an empty database for the whole run. Set to 1 when the
# artefact reads such a cache (a form list, a type registry, a reference list).
E2E_RESTART_AFTER_SEED=
# Before/after (run.sh compare): the artefact before its migration on a Lutece 7 site (Tomcat 9), then the v8 site
# on the same database. E2E_V7_REF is the git ref of the v7 sources (HEAD while the migration is only staged);
# E2E_V7_PLUGINS lists extra artefacts at their v7 versions (the v8 E2E_PLUGINS list does not apply).
E2E_V7_REF=HEAD
E2E_V7_SITE_POM=7.0.8
E2E_V7_CORE=7.1.9
E2E_V7_PLUGINS=
# A v7 pom often declares a dependency as a range whose top has moved on: the sources no longer compile
# against what Maven resolves today and the v7 leg cannot be built. Pin them here, groupId:artifactId:version
# separated by commas (the v7 sources are built in a disposable worktree, the migrated tree is untouched).
E2E_V7_DEP_PINS=
E2E_PORT7=18081
# Instance already deployed (run.sh external): its url, and its database when the sql oracles may reach it.
# The forms fuzzer never runs there; the scenarios do, and they create rows.
#E2E_BASE_URL=https://recette.example.org/lutece
#E2E_DB_HOST= E2E_DB_USER= E2E_DB_PASSWORD= E2E_DB_NAME=
# Synthetic volume loaded by dbinit: small (fast) | large (bottleneck hunting).
E2E_VOLUME=none
# pytest workers.
E2E_WORKERS=4
