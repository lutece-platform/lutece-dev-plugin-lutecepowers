---
name: lutece-e2e
description: "Génère et exécute des tests e2e Playwright pour un site ou un plugin Lutèce 8 : crawl + interaction FO/BO, CRUD réversible par entité, contrôle visuel déterministe (CSS/superposition), assertion d'effet en base (mysql2). Modes : site (BASE_URL), plugin (nom + site hôte), et incrémental/delta (couvrir seulement les changements d'un projet de tests existant, via diff git + graphe). Orchestre les tâches parallélisables (génération de tests, revue visuelle) en workflow multi-agents. Utiliser quand l'utilisateur veut tester/recetter un site ou un plugin Lutèce, écrire des tests end-to-end, couvrir des changements, ou vérifier une migration."
user-invocable: true
---

# Tests e2e Playwright pour Lutèce 8

Ce skill échafaude un projet Playwright taillé pour une cible Lutèce et génère les tests.
Base : `templates/` (config, `global-setup`, `lib/`, `reporter/`), scripts dans `scripts/`.

> Prérequis : Node 20+, `google-chrome` (rendu PDF), et un **site Lutèce running** (la cible, ou
> un site hôte où le plugin est déployé). Login BO par défaut `admin`/`adminadmin`.
>
> ⚠️ « Site running » est le prérequis qui coûte le plus de temps (plusieurs heures en usage réel, sur
> trois pièges non commutatifs). Procédure et contrôles : **`scripts/site/bring-up.md`** — à lire AVANT
> de conclure qu'un test échoue.

> **`$SKILL`** = le dossier de ce skill (scripts/templates/workflows y vivent). Installé via le plugin
> `lutecepowers-v8`, c'est `${CLAUDE_PLUGIN_ROOT}/skills/lutece-e2e`. Toutes les commandes ci-dessous
> préfixent les scripts par `$SKILL/`.

## Déroulé

### 1. Échafauder le projet
```bash
"$SKILL/scripts/scaffold.sh" <dossier-cible> <BASE_URL>
# ex : "$SKILL/scripts/scaffold.sh" ~/e2e-monsite http://localhost:9090/mon-site/
```
Puis renseigner `<dossier-cible>/.env.local` — **livré vide volontairement** : `ADMIN_USER`, `ADMIN_PASS`,
`DB_NAME`, `DB_USER`, `DB_PASSWORD`. Optionnel : `PLUGIN_NAME` (priorise le plugin cible dans le crawl BO),
`PLUGIN_XML`, `SITE_DIR`, `UPLOAD_HANDLER`, `FO_USER`/`FO_PASS`.
Le `.env.local` n'est **jamais** versionné (secrets). Échec bruyant si une variable DB manque — une valeur
**héritée** serait pire qu'une valeur absente (elle ferait tourner la suite contre la mauvaise base).

> Les scripts `.mjs` (§4-6) ne chargent **pas** `.env.local` : leur passer les variables en ligne —
> p. ex. `PLUGIN_NAME=monplugin node "$SKILL/scripts/graph/coverage-map.mjs"`.

> **Projet de tests déjà existant** (le dossier contient `playwright.config.ts`) : ne pas ré-échafauder
> (`scaffold.sh` refuse pour ne pas écraser l'existant). Passer au **mode delta** (§8) pour couvrir
> uniquement les changements.

### 2. Mode site — parcours complet FO + BO
Le `global-setup` : découvre les pages FO (crawl borné), se logue **une seule fois** au BO
(vérifié par `assertAuthenticated` — échec bruyant sinon), découvre les fonctionnalités du menu admin.
Puis lancer :
```bash
cd <dossier-cible> && npx playwright test          # headless (CI)
npx playwright test --headed                       # navigateur visible (démo/debug)
```
- `fo-crawl` / `bo-crawl` : une page = un test → `assertNoError` + `assertLayout` + `exerciseControls` + screenshot.
- `fo-functional` : recherche, navigation, formulaire de contact (rempli, **non soumis**).
- Rapport : `report/rapport.pdf` (synthèse + galerie de captures).

### 3. Mode plugin — CRUD par entité
Suivre `scripts/discover-features.md` : énumérer les entités du plugin (convention Lutèce +
`plugin.xml` + JspBeans), inspecter en **live** chaque formulaire (vrais `name=`, lien de suppression,
table via le DAO), puis instancier le **bon des 2 gabarits** selon le pattern détecté :
`_entity-crud.spec.ts.tmpl` (legacy : Create/Remove JSP séparées, clé texte) ou
`_entity-crud-mvc.spec.ts.tmpl` (MVC `@Controller` : ManageX.jsp `?view=`/`?action=`, offcanvas, id auto),
en `tests/bo-<plugin>-<entité>-crud.spec.ts`. Flux = **create → read + vérif en base → delete → verify**
(Create-Read-Delete **réversible** ; l'Update n'est pas dans le gabarit par défaut, cf. « État & limites »).

### 4. Mode graphe — couverture exhaustive (détection centrale)

> **Où lancer les scripts (phases 4-6)** : les scripts vivent dans le skill (`$SKILL`, non copiés par
> `scaffold.sh`) mais lisent/écrivent `.artifacts/`, `tests/`, `report/` dans le **répertoire courant**.
> Se placer **dans le projet échafaudé** et invoquer les scripts par chemin, p. ex. :
> `cd <dossier-cible> ; node "$SKILL/scripts/graph/build-graph.mjs" …`  (`$SKILL` défini plus haut).

Le crawl ne suit que les liens visibles ; le **graphe de fonctionnalités** (analyse statique des sources)
révèle tout le reste (actions orphelines, branches conditionnelles). Sur un plugin (ex. blog) il expose
p. ex. **26 actions** là où le crawl ne voit que 2 pages.

```bash
# 1) construire le graphe depuis les sources d'un/des plugin(s)
node "$SKILL/scripts/graph/build-graph.mjs" <plugin-dir> [<plugin-dir>...]   # → .artifacts/graph.json
# (à grande échelle : un sous-agent par plugin, cf. scripts/graph/build-graph.md)
# 2) carte de couverture : quels nœuds ont un test ?
node "$SKILL/scripts/graph/coverage-map.mjs"                                 # → report/graph-coverage.md
```
Chaque nœud (`view`/`action`/`form`/`list-control`) doit avoir ≥ 1 test. Les nœuds **NON couverts**
et atteignables par l'IHM → générer un test via les gabarits (`discover-features.md`) ; les non
atteignables (code défensif) → tests unitaires. **JaCoCo (phase suivante) confronte la carte au réel.**
`coverage-map.mjs` écrit aussi `.artifacts/to-generate.json` : **≥ 4 nœuds à générer → déléguer au
workflow** `workflows/generate-tests.js` (cf. « Parallélisation par workflow »).

### 5. Mode couverture — JaCoCo (mesure réelle)

Mesure la couverture **réelle** (lignes/branches) exercée par la suite et la confronte à la carte du graphe.
Instrumentation = **redémarrage du serveur requis** (agent JVM). Détail : `scripts/coverage/setup-jacoco.md`.

```bash
bash "$SKILL/scripts/coverage/fetch-jacoco.sh"                                   # agent + cli dans .artifacts/jacoco/
bash "$SKILL/scripts/coverage/instrument.sh" <site>/src/main/liberty/config/jvm.options .artifacts/jacoco/jacocoagent.jar
#   → REDÉMARRER liberty:dev, vérifier : ss -tlnp | grep 6300
npx playwright test                                                     # exercer le serveur
node "$SKILL/scripts/coverage/coverage-report.mjs" <site>/target/*/WEB-INF/lib "<repo>/src/java"   # → report/jacoco.xml + HTML
node "$SKILL/scripts/coverage/graph-vs-jacoco.mjs"                               # → report/graph-vs-jacoco.md
```
Une classe du graphe à **0 %** = fonctionnalité détectée mais non exercée → cible (test e2e si atteignable, sinon unitaire).
JaCoCo **tranche** entre branches *détectées* (graphe) et *réellement exercées*. **Retirer l'agent** du jvm.options
après mesure (+ redémarrage) — il ne doit pas rester en permanence.

### 6. Mode revue visuelle — IA (hors suite)

Claude (vision) analyse les screenshots et signale ce que `assertLayout` (déterministe) ne peut juger :
thème/CSS non appliqué, superpositions subtiles, texte tronqué, désalignement, **mauvaise page capturée**.
Étape **séparée** de `npx playwright test` (la suite reste sans IA) ; consultative (ne bloque pas la CI).

```bash
# 1) run SANS --reporter override (sinon les captures ne sont pas écrites)
HEADLESS=1 npx playwright test
# 2) préparer le lot de revue
node "$SKILL/scripts/visual/prep-review.mjs"                 # → .artifacts/visual-manifest.json
# 3) Claude suit scripts/visual/review.md : Read chaque capture → report/revue-visuelle.md
#    (à l'échelle : un sous-agent visual-reviewer par lot)
```
Chaque capture doit être **effectivement regardée** (leçon : une capture non examinée ne prouve rien).
Exemple réel : la revue a détecté une capture « accueil » qui était en fait la page Open Liberty
(`goto('/')` hors context-root) — invisible pour la couche déterministe.
**≥ 4 captures → déléguer au workflow** `workflows/visual-review.js` (`args` = `.artifacts/visual-manifest.json`) ;
il renvoie les findings, la boucle principale écrit `report/revue-visuelle.md`.

### 7. Mode env de test — conteneurs mock (bout-en-bout, extensible)

Mocke les **dépendances externes** dans des conteneurs locaux pour tester de bout en bout, sans appel réel.
Bibliothèque + compose unifié dans `scripts/testenv/` (registry : `scripts/testenv/REGISTRY.md`).

```bash
bash "$SKILL/scripts/testenv/testenv.sh" up mail captcha   # ou : up all
# ... surcharger la conf Lutèce vers chaque mock (voir REGISTRY.md) + REDÉMARRER ...
bash "$SKILL/scripts/testenv/testenv.sh" down                       # + retirer les overrides + restart
```

| Mock | Conteneur | Override Lutèce | Vérif |
|---|---|---|---|
| **Mail** | MailHog (:1025/:8025) | `mail.server=localhost` · `mail.server.port=1025` (clés SIMPLES, pas `%profil.`) | `lib/mail.ts` `waitForMail` — **validé** (mot de passe oublié → mail) |
| **CAPTCHA** | WireMock (:8090) | `captchetat.api.token.url` / `captchetat.api.url` → `http://localhost:8090/...` | `fo-contact-submit` → mail *(fidélité bornée par le contrat PISTE v2 ; repli : désactiver le captcha en profil e2e)* |
| **SSO / OIDC** | *(gabarit)* Keycloak (:8081) | selon le module d'auth (`mylutece-openam.*`) | à compléter avec le realm de la cible — voir `REGISTRY.md` |
| **Auth FO** | user seedé | mylutece-database | `fo-login` (voir `scripts/testenv/seed-fo-user.md`) |

**Principe** : chaque mock **répond 200 et rapporte son verdict** — « le mock sert, le test juge ».
On **assert l'effet** (mail émis, claim reçu…), pas l'affichage. **Ajouter une dépendance** (CRM…) = suivre
le patron de `REGISTRY.md`. Retirer les overrides (mail/captcha) + `testenv.sh down` après les tests.

### 8. Mode incrémental (delta) — projet de tests existant

Quand une suite e2e **existe déjà**, on ne régénère pas tout : on couvre **seulement ce qui a changé**.
Le mode croise un **diff git** (base paramétrable, défaut `develop`) avec le graphe → nœuds impactés,
sépare **non couverts** (à générer) et **déjà couverts** (à vérifier), et **signale** les tests existants
possiblement caducs (référencent une JSP / `@View` / `@Action` / `name=` supprimé) — **sans jamais les modifier**.

```bash
SKILL=<...>/.claude/skills/lutece-e2e ; cd <projet-tests-existant>
node "$SKILL/scripts/graph/build-graph.mjs" <repo-du-code>              # graphe du code courant
node "$SKILL/scripts/delta/changed-features.mjs" <repo-du-code> develop # → report/delta-coverage.md
```
Puis : générer les tests des nœuds « À générer » (via `discover-features.md`, **dans le style des tests
existants**), confirmer les « À vérifier », revoir **manuellement** les « caducs ». Détail : `scripts/delta/delta-mode.md`.
`changed-features.mjs` écrit `.artifacts/to-generate.json` : **≥ 4 nœuds → déléguer au workflow**
`workflows/generate-tests.js`.

## Parallélisation par workflow (tâches à items indépendants)

Certaines tâches sont composées d'**unités indépendantes** → les exécuter en **fan-out d'agents** via le
tool `Workflow`. **Ces instructions valent opt-in** : quand un mode ci-dessous s'applique à **≥ 4 items**,
lancer le workflow ; en dessous de 4, faire **inline** (le fan-out ne vaut pas son coût).

```
Workflow({ scriptPath: "$SKILL/workflows/<x>.js", args: <liste-JSON> })   # $SKILL = dossier du skill
```

| Tâche | Workflow | `args` | Après |
|---|---|---|---|
| **Génération de tests** (entités CRUD / nœuds à couvrir / nœuds « à générer » du delta) | `workflows/generate-tests.js` | `.artifacts/to-generate.json` | passe de **revue de code** sur les specs générés (agent code-reviewer si disponible) |
| **Revue visuelle IA** (lots de captures) | `workflows/visual-review.js` | `.artifacts/visual-manifest.json` | j'écris `report/revue-visuelle.md` depuis le retour |

Forme imposée : **fan-out → vérification adversariale → synthèse**. Respecter le cap **< 15 agents**
(les scripts bornent déjà : lots de **8** captures et ≤ 10 lots, génération ≤ 12 items/vague — relancer
pour la suite).

Le **script** de workflow n'a pas accès au disque (sandbox) : il ne peut pas écrire de fichier, il
**retourne** des données structurées. Ses **agents**, eux, disposent des outils normaux :
- `generate-tests.js` → les agents **écrivent** les specs (`Write`) et **lancent** Playwright ;
- `visual-review.js` → les agents **lisent** les captures et renvoient des findings ; c'est la boucle
  principale qui écrit `report/revue-visuelle.md` et **mesure** les constats avant de les retenir.

**Pas** de workflow pour le crawl/exécution (Playwright parallélise via ses *workers*) ni l'extraction
de graphe (scripts Node déterministes et rapides).

## Garde-fous (NON négociables)

- **CRUD réversible uniquement** : create puis delete, clé de test préfixée `E2E`, nettoyage en `afterAll`
  **enfants d'abord** (`deleteCascade`) puis `assertNoResidue`. Choisir une entité supprimable sans contrainte
  (ex. rôle de page ; **pas** un groupe de travail — l'admin créateur y est rattaché → suppression refusée).
- **Une spec n'invalide JAMAIS un état partagé.** Playwright crée un contexte par test **depuis le même
  `storageState.json`** : toutes les specs présentent le même `JESSIONID`. Donc **jamais** de
  `DoAdminLogout.jsp`, de changement de langue, ni de purge de session « par prudence » : la spec fautive
  passe et **la suivante meurt en accusant l'authentification**. Se reconnecter suffit ; déconnecter d'abord
  est un sabotage.
- **Un seul login** réutilisé (`storageState`), **et vérifié vivant** avant réutilisation
  (`sessionEncoreValide` dans le `global-setup`) — le core bannit après 3 échecs (`core_connections_log`,
  purge via `resetLockout()`). Jamais de boucle de login.
- **Trois niveaux de données, jamais mélangés** (le mauvais choix détruit une ligne métier réelle sur une
  base de recette partagée) :
  | Type de table | Nettoyage autorisé | Helper |
  |---|---|---|
  | **table de travail** (ne contient que des données de test) | `LIKE 'E2E%'` | `cleanupByPrefix` (refuse un préfixe < 3 car.) |
  | **table portant des données réelles** | **valeur exacte**, jamais un `LIKE` | `deleteExact` |
  | **table de référentiel** | **aucune suppression** — modifier puis restaurer | `withRestore` |
- **Un nettoyage raté doit être bruyant** : jamais de `.catch(() => {})` autour du nettoyage.
- **Effets de bord interdits** hors env de test : formulaire de contact **rempli mais jamais soumis**
  (CAPTCHA + mail réel) ; `exerciseControls` **exclut** tout libellé/href destructif
  (Supprimer, Envoyer, Publier, Valider…) et s'arrête sur navigation.
- **Clés de test** : alphanumériques (`E2E…`) — certaines validations Lutèce interdisent le tiret.
- **Aucune valeur de projet en dur** dans les templates : ni URL, ni base, ni identifiant. Un repli
  silencieux (`process.env.X || 'littéral'`) sur une **URL** ou une **base** fait tourner la suite contre
  la mauvaise cible **sans rien signaler** — utiliser `env('X')` (échec bruyant).
- **Confidentialité** : les captures d'un site de recette contiennent des **données personnelles réelles**.
  `report/screenshots/`, `rapport.pdf` et `preuves/` ne sont **ni versionnés ni transmis** (cf. `scripts/visual/review.md`).

## Règles d'assertion (leçons du terrain — cf. `~/.lutece-references` et `lecons-tests.md`)

### Ce qui fait un vrai vert

- **Le statut avant le contenu** : `response.status()` est un instrument plus fort qu'une chaîne cherchée
  dans le corps de page. Toujours passer la `Response` à `assertNoError(page, resp)` — sans elle, le
  contrôle de statut n'a pas lieu (le rapport le signale désormais).
- **Lutèce rend ses erreurs en HTTP 200** — page d'erreur technique v8 (« Technical error »,
  « Erreur technique »), « Startup error » servie sur *toutes* les URL, « Page not found ». Asserter
  sur le **contenu** en plus du statut.
- **Asserter l'effet, pas l'affichage** : vérifier la **ligne en base** (`db.exists`), pas seulement
  la liste UI. `assertNoError` lit le **texte visible** (`innerText`), jamais le HTML brut.
- **Succès silencieux ⇒ assertion en base.** Pour une fonction dont le succès n'affiche rien (gardes
  avant le `try`, rien journalisé), l'assertion porte sur la **trace** (`workflow_resource_history`,
  table métier) — **jamais** sur l'absence de message d'erreur.
- **Contrôle positif obligatoire** — pas seulement pour l'authentification :
  - auth : `assertAuthenticated` (élément réservé admin présent) ;
  - **tout test de refus** doit prouver que le même parcours **réussit** dans le cas autorisé, sinon il
    passerait au vert sur n'importe quelle panne ;
  - **toute découverte** : `expect(entrees.length).toBeGreaterThan(0)` avant de boucler dessus.
- **Rouge avant vert, et rouge pour la bonne raison** : voir le test échouer, et vérifier que le message
  d'échec désigne bien la cause visée.
- **Contrôle négatif** : prouver que l'assertion **sait échouer** (valeur voisine inexistante → `false`).
  Un test qui n'a jamais pu échouer ne vaut rien.
- **Préconditions créées, jamais empruntées** : campagne ouverte, référentiel peuplé, fenêtre de dates →
  le test **crée** sa fixture bac-à-sable (`withFixture`) et la retire. Sinon il passe vert sans que la
  fonction ait jamais joué.

### Hiérarchie d'attente (« visible ≠ actif » ne suffit pas)

1. **Le composant est prêt** — `composantPret(page, 'Uppy')` : `waitForFunction(window.X)` puis
   `networkidle`. Un composant instrumenté en JS attache son gestionnaire **après** plusieurs requêtes ;
   agir avant ne déclenche rien, l'échec ressemble à un défaut serveur et il est **intermittent**.
2. **L'élément est actionnable** (`toBeEnabled`, `click` avec auto-wait).
3. **L'élément est attaché/visible** — suffisant **uniquement** pour du HTML statique.

> Test de discrimination : si un correctif de spec suffit **sans redémarrer le serveur**, c'était une
> **course**, pas un état serveur.

### Pièges d'URL

- **Ne jamais résoudre un href relatif contre `page.url()`** : `new URL(href, page.url())` double le
  segment de chemin (`…/jsp/site/jsp/site/Portal.jsp`) → 404 qui ressemble à un lien mort du site.
  Passer le href **brut** à `page.goto()` : Playwright applique déjà la `baseURL`. Si une base explicite
  est nécessaire, c'est `BASE_URL`, jamais l'URL courante.
- **`goto('')` ≠ `goto('/')`** : `''` reste sous le context-root, `/` va à la racine du serveur (on a
  capturé la page d'accueil Open Liberty en croyant tester le site).
- **Ne jamais deviner une URL** : les entrées sont **lues sur la page**. Un `else` ne navigue pas vers une
  URL supposée — c'est un `test.skip(motif)` ou un échec bruyant.
- **Un paramètre à valeur vide n'est pas émis** → Lutèce se rabat sur sa vue par défaut et le test ne
  mesure rien.
- **`page.request` ne partage pas la session** du navigateur : une requête API « authentifiée » mesure
  en réalité la page de login. `assertAuthenticated` ne s'applique qu'à une `Page`.

### Portée et objet de l'assertion

- **Ni trop large, ni trop étroite** : `expect(page.locator('body')).toContainText(K)` passe au vert si
  `K` apparaît n'importe où (y compris dans un message d'erreur). Scoper au conteneur utile, et
  **revérifier** après tout élargissement de portée.
- **Vérifier qu'on mesure le bon objet** : le fichier, pas le répertoire (qui survit vide) ; la ligne,
  pas le compteur.
- **Lire la console avant de théoriser** sur le CSS ou le réseau : `collectConsole(page)` (console +
  `pageerror`) avant l'assertion. Une trace de diagnostic s'attache **avant** l'échec, pour que l'échec
  la porte (`expectResponse` liste les requêtes réellement observées).
- **Contrôle visuel déterministe** (`assertLayout`) : CSS chargé (`styleSheets`>0 + styles calculés),
  aucune image cassée, aucune **superposition** de contrôles (heuristique excluant imbriqués/positionnés).
- **Regarder les captures** : une capture non examinée ne prouve rien — elle est **« non instruite »**,
  jamais conforme (→ revue visuelle, §6). Et une capture ne prouve que ce qui est rendu **dans les
  conditions du test** : la **locale du navigateur** en fait partie (fixée à `fr-FR`, sans quoi Lutèce
  sert ses libellés en anglais et la revue conclut à de faux défauts de traduction).

## Hygiène d'exécution

- **Une seule tâche lourde à la fois** ; ne pas redémarrer le serveur sous une suite en cours.
- **Jamais de `pkill -f` à motif large** (tue son propre shell) — tuer par PID.
- **Une spec qui échoue en suite mais passe en isolation n'est presque jamais un défaut du produit** :
  chercher d'abord l'**état partagé** (session invalidée, cache serveur, données laissées par une autre spec).
- **Un effondrement en masse** ne se diagnostique pas spec par spec : vérifier d'abord que l'application
  est debout, en regardant le **HTML réellement servi** (une page « Startup error » en 200 fait échouer
  tout, sans que rien ne soit cassé côté tests).
- **FO 200 ne prouve pas que le site est debout** : un descripteur non chargé rend le FO en 200 et le BO
  en 500. Toujours contrôler une page BO **authentifiée**.
- **Attribuer un échec après isolation** (rejouer le test seul), pas au dernier changement par réflexe.
- Un échec e2e peut révéler un **vrai défaut du site** (ex. 404 sur une feature au menu) : le consigner
  comme finding, ne pas le masquer.
- **Un test qui prouve un défaut ne dit pas si le défaut vaut d'être corrigé** : après un correctif,
  **rejouer la suite du parcours** (un correctif « évident » d'affichage a déjà cassé le dépôt de dossier).
- **Distinguer trois causes de rouge** — le rapport le fait désormais par badge : **échec réel** /
  **non applicable** (`na`) / **environnement absent** (`env-absent`). Seuls les premiers sont des défauts ;
  deux rouges permanents usent la confiance dans tous les autres.
- **Pièges de build Lutèce** : `mvn install` d'un plugin **ne déploie ni les templates ni les i18n**
  (deux cycles de débogage perdus) ; les `.properties` sont en **ISO-8859-1** ; une consigne de build
  générique ne prime jamais sur une contrainte du projet.

## Fichiers du skill

- `templates/` : projet Playwright paramétrable — `playwright.config.ts`, `package.json`, `tsconfig.json`,
  `tests/global-setup.ts`, `tests/global-teardown.ts`, `tests/lib/{crawler,helpers,db,mail,graph-schema}.ts`,
  specs `tests/{fo-crawl,bo-crawl,fo-functional,bo-mail-forgot-password,fo-contact-submit,fo-login}.spec.ts`,
  gabarits CRUD `tests/{_entity-crud,_entity-crud-mvc}.spec.ts.tmpl`, `reporter/`.
- `scripts/scaffold.sh` : copie `templates/` + `npm install` + `npx playwright install chromium`.
  Refuse d'écraser un projet de tests existant (→ mode delta, §8).
- `scripts/site/bring-up.md` : mise en route d'un site Lutèce 8 sur Liberty (le prérequis coûteux).
- `scripts/discover-features.md` : procédure d'inspection live (mode plugin, 2 patterns).
- `scripts/graph/` : graphe de fonctionnalités — `extract-{plugin-xml,controllers,templates}.mjs`,
  `build-graph.mjs`(+`.md`), `coverage-map.mjs` (§4).
- `scripts/coverage/` : JaCoCo — `fetch-jacoco.sh`, `instrument.sh`, `coverage-report.mjs`,
  `graph-vs-jacoco.mjs`, `setup-jacoco.md` (§5).
- `scripts/visual/` : revue IA — `prep-review.mjs`, `review.md` (§6).
- `scripts/delta/` : mode incrémental — `changed-features.mjs`, `delta-mode.md` (§8).
- `workflows/` : orchestration multi-agents — `generate-tests.js`, `visual-review.js` (cf. « Parallélisation par workflow »).
- `scripts/testenv/` : env de test à conteneurs mock — `docker-compose.testenv.yml`, `testenv.sh`,
  `REGISTRY.md`, `seed-fo-user.md`, `wiremock/mappings/` (§7).

## État & limites connues

Les 6 axes de la spec sont en place : crawl+interaction, CRUD (2 gabarits), visuel déterministe + revue IA,
DB, graphe de fonctionnalités, couverture JaCoCo, env de test à conteneurs mock (MailHog/WireMock,
extensible). **Limites honnêtes** :
- **CRUD = Create-Read-Delete réversible** (par les 2 gabarits). L'**Update** n'est pas dans le gabarit par
  défaut : choix de réversibilité (garde-fou « create puis delete ») + un champ mutable dépend de l'entité →
  à ajouter au cas par cas sur le modèle du gabarit. La couverture fonctionnelle large passe par le graphe (§4).
- **CaptchEtat (contact soumis)** : framework WireMock livré, mais la fidélité au contrat **PISTE captchetat v2**
  (génération front + validation back) n'est pas complète → repli **actionnable** dans `scripts/testenv/REGISTRY.md`
  (désactiver le captcha en profil e2e).
- **Auth FO** : spec + doc de seed livrés ; la vérif live nécessite un utilisateur créé avec le bon hash (via l'UI BO).
- **SSO / OIDC** : seul un **gabarit** est livré (aucun realm — il est propre à chaque organisation) ; le
  câblage et la vérification des claims restent à faire sur la cible.
- **Preuve avant/après** : `capturePreuve(page, id, 'avant'|'apres')` écrit dans **`preuves/`** — archive
  **locale, non versionnée** (données personnelles) et **jamais purgée**, contrairement à `report/screenshots/`
  que chaque run réécrit. `shot()` reste la capture courante attachée au rapport.
- **Non rejoué en live depuis la passe de correction** (issue d'un retour d'usage réel : 29 correctifs,
  dont marqueurs d'erreur v8, vérification de session, sémantique de nettoyage, locale `fr-FR`). Le dernier
  run réel portait sur la version précédente. Les templates ne sont copiés qu'au **scaffold** : un projet
  déjà généré ne reçoit pas ces correctifs — le rejouer suppose de ré-échafauder ailleurs.
- **`workflows/generate-tests.js`** : validé à vide (0 agent) ; son chemin d'exécution réel (un agent écrit
  un spec puis le vérifie) n'a pas encore tourné.
Cf. la spec `docs/superpowers/specs/2026-08-04-skill-lutece-e2e-design.md`.
