# Découverte des entités d'un plugin (mode plugin) — procédure d'inspection live

Objectif : générer, pour chaque entité CRUD d'un plugin, un spec à partir de
`templates/tests/_entity-crud.spec.ts.tmpl`, avec des sélecteurs et une table vérifiés en vrai.

Prérequis : le plugin est déployé sur un site hôte **running**, et `storageState.json` contient
une session admin valide (le `global-setup` l'a produite et vérifiée via `assertAuthenticated`).

## Deux patterns d'entité (choisir le bon gabarit)

Le BO Lutèce mêle deux patterns — identifier lequel avant de générer :

- **Legacy** : JSP séparées `Create<E>.jsp` / `Remove<E>.jsp`, **clé texte** (`role_key`, `workgroup_key`).
  → gabarit `_entity-crud.spec.ts.tmpl`. Ex. validés : rôle de page (`core_role`), rôle RBAC (`core_admin_role`).
- **MVC** (`@Controller`) : une seule `Manage<E>.jsp` avec `?view=`/`?action=`, **id auto-incrément**,
  formulaire de création dans une **offcanvas** (ouverte par un bouton `data-bs-toggle="offcanvas"` titré
  « Créer/Ajouter »), champs parfois chargés en AJAX. Suppression via `?action=confirmRemove<E>&id=N`.
  → gabarit `_entity-crud-mvc.spec.ts.tmpl` (ouvre l'offcanvas, récupère l'**id en base**, supprime par id).
  Ex. validé : tag de blog (`blog_tag`, id `id_tag`, form `create_tag`, champ `name`, action `confirmRemoveTag`).

## 1. Énumérer les entités (statique, convention Lutèce)

- Lister les JSP admin du plugin : `webapp/jsp/admin/plugins/<plugin>/Manage<Entité>.jsp`,
  `Create<Entité>.jsp`, `Modify<Entité>.jsp`, `Remove<Entité>.jsp`.
- Recouper avec `plugin.xml` (`<admin-features>` → right/url) et les JspBeans `@Controller`
  (`@View("manage…")`, `@Action("create…"/"remove…")`).
- Ignorer les handlers d'action `Do<Verbe>.jsp` (POST, non affichables).

## 2. Fiabiliser par inspection live (avec la session admin)

Pour chaque entité, avec le cookie de `storageState.json` :

- **Champ clé** : GET `Create<Entité>.jsp` → relever le `name=` du champ identifiant
  (souvent `<entity>` ou `<entity>_key`) et l'`action` du formulaire (`DoCreate…`).
- **Lien de suppression** : après une création test, GET `Manage<Entité>.jsp` → relever le href
  du lien poubelle (`…Remove<Entité>.jsp?<clé>=<valeur>`). La confirmation est une page
  `AdminMessage` avec un bouton **OK** dans un `form[action*="DoRemove"]`.
- **Tables écrites par la suppression** — et non « la » table : énumérer **toutes** les tables que le
  chemin de suppression écrit (DAO parent + DAO enfants + tables `workflow_*` si l'entité est une
  ressource de workflow). Renseigner la mère dans `{{DB_TABLE}}`/`{{DB_COLUMN}}` et les filles dans
  `{{DB_CHILD_TABLES}}` (JSON `[{"table","column"}]`) : elles sont supprimées **avant** la mère.
  Si la table mère est introuvable, laisser `{{DB_TABLE}}`/`{{DB_COLUMN}}` **vides** → le gabarit
  **legacy** se rabat sur la vérification par la liste UI (sans assertion en base). Le gabarit **MVC**
  exige la table (il récupère l'id auto en base) : sans elle, préférer le gabarit legacy.
- **Lire le moteur de stockage AVANT d'écrire le teardown** : les tables de plugins Lutèce sont
  fréquemment en **MyISAM**, donc **sans clé étrangère et sans cascade**. Supprimer la ligne mère laisse
  des orphelins silencieux (constaté : 16 lignes accumulées avant d'être remarquées, puis 118 paires
  orphelines de lignes de workflow). Le gabarit journalise le moteur en `beforeAll` ; `assertNoResidue`
  contrôle mère **et** filles.
  > Le contrôle de résidu se dérive de ce que la fonction **écrit**, pas de ce que le test croit avoir créé.
- **Choisir le mode de nettoyage** (`{{CLEANUP_MODE}}`) selon le type de table : `'exact'` (défaut) pour
  une table portant des données réelles — suppression de la seule valeur de test, sûre quand plusieurs
  specs travaillent en parallèle sur la même base ; `'prefix'` **uniquement** pour une table de travail.
  Sur une table de **référentiel**, ne rien supprimer : modifier puis restaurer (`withRestore`).

## 3. Générer le spec

Copier le **bon gabarit** (cf. « Deux patterns » ci-dessus) en `tests/bo-<plugin>-<entité>-crud.spec.ts` :

- **Legacy** → `_entity-crud.spec.ts.tmpl`, placeholders : `{{ENTITY}}`, `{{MANAGE_URL}}`, `{{CREATE_URL}}`,
  `{{KEY_FIELD}}`, `{{KEY_VALUE}}`, `{{DB_TABLE}}`, `{{DB_COLUMN}}`, `{{DB_CHILD_TABLES}}`, `{{CLEANUP_MODE}}`.
- **MVC** → `_entity-crud-mvc.spec.ts.tmpl`, placeholders : `{{ENTITY}}`, `{{MANAGE_URL}}`, `{{CREATE_FORM}}`,
  `{{CREATE_FIELD}}`, `{{REMOVE_ACTION}}`, `{{KEY_VALUE}}`, `{{DB_TABLE}}`, `{{DB_KEY_COL}}`, `{{DB_ID_COL}}`,
  `{{DB_CHILD_TABLES}}`, `{{CLEANUP_MODE}}`.

**Tous** les placeholders doivent être substitués, y compris les deux derniers — ils sont interpolés dans du
code TypeScript, donc un jeton laissé en place produit un fichier qui **ne compile pas** :
- `{{DB_CHILD_TABLES}}` : JSON des tables filles, **`[]`** si aucune (jamais vide).
- `{{CLEANUP_MODE}}` : **`exact`** par défaut (table portant des données réelles), `prefix` uniquement pour
  une table de travail.

`{{KEY_VALUE}}` : valeur préfixée **`E2E`** — **alphanumérique, SANS tiret** (certaines validations Lutèce
refusent le `-`).
Lancer : `npx playwright test bo-<plugin>-<entité>-crud`.

> **À l'échelle (≥ 4 entités/nœuds)** : ne pas générer un par un à la main → déléguer au workflow
> `Workflow({ scriptPath: "$SKILL/workflows/generate-tests.js", args: <liste> })` (un agent par item :
> inspection live + écriture du spec, puis vérification adversariale), suivi d'une passe de revue de code (agent code-reviewer si disponible).

## Entités à contrainte d'association (ex. groupe de travail)

Certaines entités **ne se suppriment pas tant qu'elles sont référencées**. Le **groupe de travail**
(`core_admin_workgroup`) auto-rattache l'**admin créateur** à la création → la suppression est refusée
(« this workgroup is associated with users »). Ajouter une **étape de désassignation** avant delete :
- Aller sur `AssignUsersWorkgroup.jsp?workgroup_key=KEY`.
- Soumettre chaque `form[action*="DoUnassignUser"]` (un par utilisateur rattaché) jusqu'à ce qu'il n'en
  reste plus (vérifier `core_admin_workgroup_user` vide en base).
- Puis `RemoveWorkgroup.jsp?workgroup_key=KEY` → confirmation OK.
Exemple validé : `tests/bo-workgroup-crud.spec.ts`. Généraliser : détecter la contrainte (message
« associated with… » au delete) et insérer l'étape de désassignation correspondante.

## Garde-fous (obligatoires)

- Clé de test préfixée `E2E` (**sans tiret**) ; `afterAll` nettoie selon `{{CLEANUP_MODE}}` —
  `deleteExact` par défaut, `cleanupByPrefix` **uniquement** sur une table de travail (cf. la règle des
  trois niveaux de données dans `SKILL.md`). Les tables filles sont supprimées **avant** la mère.
- Ne jamais générer d'action à effet de bord non réversible (envoi mail, publication).
- Choisir une entité **supprimable sans contrainte** (ex. rôle de page). Éviter les entités liées
  à un utilisateur/état (ex. groupe de travail = l'admin créateur y est rattaché → suppression refusée).

## Exemple validé (rôle de page, core)

| Placeholder | Valeur |
|---|---|
| `{{ENTITY}}` | rôle de page |
| `{{MANAGE_URL}}` | `jsp/admin/role/ManagePageRole.jsp` |
| `{{CREATE_URL}}` | `jsp/admin/role/CreatePageRole.jsp` |
| `{{KEY_FIELD}}` | `role` |
| `{{KEY_VALUE}}` | `E2Erole1` |
| `{{DB_TABLE}}` | `core_role` |
| `{{DB_COLUMN}}` | `role` |
| `{{DB_CHILD_TABLES}}` | `[]` (aucune table fille) |
| `{{CLEANUP_MODE}}` | `exact` |
