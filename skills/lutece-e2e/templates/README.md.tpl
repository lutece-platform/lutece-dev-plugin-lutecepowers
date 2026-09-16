# e2e — banc de test du back office @@NAME@@

Un seul point d'entrée :

```bash
./run.sh            # tout : build si besoin, pile Docker, seed, inventaire, découverte, tests, perf, rapport, arrêt
KEEP=1 ./run.sh     # idem, la pile reste montée (itération)
./run.sh test       # les trois suites sur une pile déjà montée
./run.sh report     # régénère summary.md / report.html depuis les artefacts
./run.sh down       # arrêt + suppression du volume base
```

Lire ensuite **`artifacts/summary.md`** (≈ 200 lignes) : couverture de l'inventaire (**prouvée** par un scénario avec
oracle / seulement atteinte / exclue avec raison / à couvrir), dette visible, ce que montrent les tests réussis (types
d'écrans), alarme de contenu identique, échecs en trois sections (fonctionnels, front, robustesse) avec leur cause
serveur, temps, SQL, JFR. Captures et détails dans `artifacts/report.html`, JUnit dans `artifacts/junit-*.xml`.

Un échec est un constat sur l'application jusqu'à preuve du contraire : le banc a trouvé sur le core develop des
JSP qui ne compilent plus, des liens morts, des erreurs JS, des écrans en « Internal error » et un formulaire de
confirmation sans jeton CSRF. Les exclusions de couverture (`scenarios/coverage-exclusions.yaml`) documentent
ce que le banc ne peut pas atteindre et pourquoi.

## Ce que le banc vérifie

| Suite | Source | Vérification par élément |
|---|---|---|
| `screens` | inventaire statique (`tools/inventory.py`) + découverte dynamique (`tools/discover.py`) | HTTP 200, pas de page d'erreur Lutece/Liberty, pas de perte de session, **console navigateur vide** (erreurs, warnings, exceptions JS), aucune sous-requête en échec, temps de navigation, capture JPEG, empreinte aria (diff avec `baselines/aria/` si présent) |
| `scenarios` | `scenarios/*.yaml` (cycles CRUD métier, scénarios négatifs et de droits) | **règle mécanique** : chaque mutation est suivie d'un oracle d'état (SQL, datastore, DOM) sinon le scénario est rejeté à la collecte ; un compte de niveau 3 (`e2e_level3`) sert aux refus de droits |
| `forms` | formulaires découverts sur les écrans | soumission avec valeurs générées : jamais d'erreur serveur ; liste `DENY` pour les actions qui verrouilleraient le banc |
| `harness` | `tests/test_harness.py` | l'oracle lui-même : reconnaît un écran, une confirmation, une session perdue, le login, un 404 ; bloque le run sinon |
| `perf` | access log Liberty, `/metrics`, `performance_schema`, JFR, k6 | p50/p95 par chemin, top SQL par temps cumulé et lignes lues, méthodes chaudes, pool JDBC, seuils de charge |

## Arborescence

```
e2e.conf              cible (core|plugin), plugins, ports, volume
run.sh                orchestrateur
harness/              docker-compose.yml, Dockerfile.app (Temurin 21 + Open Liberty), liberty/, db/ (my.cnf, seed), site/ (pom généré)
tools/                inventory.py, discover.py, coverage.py, causes.py, forms.sh, ears.py, metrics.py, report.py, load.js, gen-site.sh
tests/                lutece.py (bibliothèque), conftest.py, test_screens.py, test_scenarios.py, test_forms.py
scenarios/            core.yaml, core-admin.yaml (scénarios métier), coverage-exclusions.yaml (inatteignable, avec raison)
baselines/aria/       empreintes de référence (copier depuis artifacts/aria pour figer)
artifacts/            sortie d'un run (ignoré par git)
```

## Comptes et accès

| Quoi | Valeur |
|---|---|
| Back office | http://localhost:18080/lutece/jsp/admin/AdminLogin.jsp — `admin` / `adminadmin` |
| MariaDB | localhost:13306 — `lutece` / `lutece`, base `lutece` |
| Métriques Liberty | http://localhost:18080/metrics |
| Logs, access log, JFR | `artifacts/logs/` |

## Volume synthétique

`E2E_VOLUME=small` (défaut : 2 000 utilisateurs, 200 pages) ou `large` (100 000 utilisateurs, 500 groupes,
…) — `harness/db/seed-<cible>.sql`, écrit pour les tables que cet artefact lit vraiment, généré côté serveur
par le moteur SEQUENCE, idempotent. Le harnais générique ne seede rien.
Un plugin ajoute ses propres tables dans `harness/db/seed-<plugin>.sql` (même contrat : variables `@users`…, garde d'idempotence).

## Ajouter un scénario

Dans `scenarios/<feature>.yaml` :

```yaml
  - id: workgroup_crud
    title: Groupes de travail — créer, modifier, supprimer
    req: CORE_WORKGROUPS_MANAGEMENT        # exigence EARS (droit Lutece)
    steps:
      - goto: jsp/admin/workgroup/CreateWorkgroup.jsp
      - fill: {'input[name="workgroup_key"]': 'E2E_{{rand}}', 'input[name="workgroup_description"]': 'Groupe {{rand}}'}
      - submit: 'form[action*="DoCreateWorkgroup"]'
      - expect_ok:
      - sql: {query: "SELECT COUNT(*) FROM core_admin_workgroup WHERE workgroup_key='E2E_{{rand}}'", expect: 1}
      - goto: jsp/admin/workgroup/RemoveWorkgroup.jsp?workgroup_key=E2E_{{rand}}
      - expect_message: confirmation
      - confirm:
```

Vocabulaire complet en tête de `tests/test_scenarios.py`. Drapeaux : `isolated: true` (session propre :
déconnexion, mot de passe), `anonymous: true` (écrans publics), `serial: true` (réglages globaux, joué seul après
la passe parallèle).

## Jenkins

Le runner est un conteneur : l'agent n'a besoin que de Docker et Maven. Pipeline minimal :

```groovy
sh './e2e/run.sh'
junit 'e2e/artifacts/junit-*.xml'
publishHTML(target: [reportDir: 'e2e/artifacts', reportFiles: 'report.html', reportName: 'e2e'])
archiveArtifacts 'e2e/artifacts/summary.md, e2e/artifacts/perf.json'
```

Allure n'est pas requis (voir `DESIGN.md`) ; `allure-pytest` s'ajoute en une ligne si un projet l'exige.
