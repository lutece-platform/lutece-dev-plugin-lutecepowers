# Mode incrémental (delta) — projet de tests déjà existant

Quand une suite e2e **existe déjà** (le dossier cible contient `playwright.config.ts` + `tests/`), on ne
ré-échafaude pas et on ne régénère pas tout : on couvre **seulement ce qui a changé**, en s'appuyant sur
les tests présents. Le mode delta produit une **liste de travail** à partir d'un diff git.

## Ce qu'il fait

1. Calcule les **fichiers changés** (`git diff` vs une base **paramétrable**, défaut `develop`).
2. Croise avec le **graphe de fonctionnalités** → **nœuds impactés**.
3. Sépare les impactés **non couverts** (→ à générer) des **déjà couverts** (→ à vérifier).
4. Signale les **tests existants possiblement caducs** : ceux qui référencent une JSP / un `@View`/`@Action` /
   un `name="…"` **supprimé** par le diff. Ils ne sont **jamais modifiés** — juste listés pour revue manuelle.

## Prérequis

- Un projet de tests existant (on se place **dedans** — c'est le CWD, comme aux phases 4-6).
- Accès au dépôt du **code** modifié (site ou plugin) et à sa base de comparaison
  (au besoin : `git -C <repo> fetch origin develop`).

## Enchaînement

```bash
SKILL=<...>/.claude/skills/lutece-e2e
cd <projet-tests-existant>

# 1) graphe du code COURANT (le/les plugin(s) touché(s))
node "$SKILL/scripts/graph/build-graph.mjs" <repo-du-code> [<repo2> ...]

# 2) delta : diff vs base (défaut develop ; accepte une réf, un SHA, ou une plage A...B)
node "$SKILL/scripts/delta/changed-features.mjs" <repo-du-code> develop        # ou : origin/main, HEAD, A...B
#    → report/delta-coverage.md
```

## Suite à donner au rapport `report/delta-coverage.md`

- **À générer** : pour chaque nœud impacté non couvert, écrire un test en suivant
  `scripts/discover-features.md` (entités → un des 2 gabarits CRUD ; vues/actions → spec ciblé).
  **Écrire dans le style des tests existants** (nommage, helpers `lib/`, storageState).
  `changed-features.mjs` a écrit `.artifacts/to-generate.json` : **≥ 4 nœuds → déléguer au workflow**
  `Workflow({ scriptPath: "$SKILL/workflows/generate-tests.js", args: <.artifacts/to-generate.json> })`
  (fan-out génération + vérification adversariale), puis une passe de revue de code (agent code-reviewer si disponible).
- **À vérifier** : un test existe déjà pour la feature changée → le relire et confirmer qu'il exerce bien
  le **nouveau** comportement (au besoin, l'étendre — décision humaine, pas automatique).
- **Caducs** : revoir manuellement chaque spec signalé (le token qu'il utilise a disparu du code).
- **Non mappés** (DAO/business/config) : pas de nœud IHM → envisager un test unitaire côté projet.

## Garde-fous (inchangés)

- **Ne jamais écraser / modifier** un test existant depuis ce mode (on ajoute et on signale).
- CRUD **réversible**, clé de test préfixée **`E2E`** (sans tiret), nettoyage `afterAll`.
- Le mapping diff→nœud et la couverture sont **approximatifs** (suffixe de chemin + sous-chaîne) : le
  rapport est un point de départ, à recouper avec JaCoCo (Phase 3) pour l'exercice réel.
