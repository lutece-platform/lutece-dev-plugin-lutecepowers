# Construction du graphe de fonctionnalités (orchestration)

## Petite échelle (1 à quelques plugins)
```bash
node scripts/graph/build-graph.mjs <plugin-dir> [<plugin-dir>...]
# → .artifacts/graph.json (merge des 3 extracteurs sur chaque dossier)
```
Les `<plugin-dir>` sont les sources des plugins de la cible : soit `~/.lutece-references/<repo>`,
soit les modules du projet. Un dossier doit contenir `webapp/WEB-INF/plugins/*.xml`, `src/`, et
`webapp/WEB-INF/templates/`.

## Grande échelle (site complet, N plugins) — sous-agents parallèles

Quand la cible a beaucoup de plugins, le SKILL dispatche **un sous-agent par plugin** (Agent tool) :

1. Lister les plugins de la cible (via le `war.xml` de la loose-app ou `pom.xml`).
2. Pour chaque plugin, un sous-agent exécute `build-graph.mjs <ce-plugin>` et **renvoie son sous-graphe**
   (le JSON de `.artifacts/graph.json` qu'il a produit dans son espace).
3. L'orchestrateur **fusionne** tous les sous-graphes avec `mergeGraphs` (cf. `tests/lib/graph-schema.ts`)
   → un `.artifacts/graph.json` global.
4. Journaliser le nombre de nœuds **par type** et par plugin (pas de troncature silencieuse).

Les extracteurs étant déterministes et sans réseau, les sous-agents ne servent qu'à **paralléliser**
la passe sur de nombreux plugins ; le résultat est identique à une exécution séquentielle.

## Ensuite
- `node scripts/graph/coverage-map.mjs` → `report/graph-coverage.md` (nœuds couverts / NON couverts).
- Générer les tests des nœuds `action`/`entity` non couverts et atteignables par l'IHM (gabarits Phase 1
  + `discover-features.md`). Les nœuds non atteignables par l'IHM → tests unitaires (hors e2e).
- JaCoCo (Phase 3) confronte la carte du graphe à la couverture de branches **réelle**.
