# Bench e2e Lutece — décisions de conception

Un dossier `e2e/` autoportant, produit par un skill générique : environnement isolé, inventaire de **tous** les
écrans et actions, tests rapides, rapport lisible par un humain comme par un agent en quelques centaines de tokens.
À lire avant de changer un choix d'outil.

## Ce qui est retenu, et pourquoi

| Brique | Choix | Raison |
|---|---|---|
| Pilotage navigateur | **Playwright Python 1.62** (`sync_api`) + pytest 9 + pytest-xdist | Parallélisme par processus, JUnit XML natif pour Jenkins. Les tests sont paramétrés par des JSON : le langage compte peu, la stabilité du runner compte. |
| Runner | Image officielle `mcr.microsoft.com/playwright/python:v1.62.0-noble`, épinglée | Zéro dépendance sur l'agent Jenkins ; `RUNNER=local` pour itérer sur le poste. |
| Environnement | **Docker Compose v2** (db, app, dbinit, tests, k6) | Une pile e2e est un stack complet monté une fois ; Testcontainers vise l'isolation par test (intégration Java), hors sujet ici. |
| Serveur d'application | **Open Liberty 26.0.0.9 sur Temurin 21 (HotSpot)**, zip Maven Central | Les images ICR sont OpenJ9 uniquement ; OpenJ9 0.61 **plante** (assertion `VMAccess.cpp:133`) sous échantillonnage JFR et n'accepte pas `dumponexit`. HotSpot donne JFR complet, `jcmd JFR.dump` à chaud, `jfr view`. Différence JIT assumée : les goulots (SQL, N+1, verrous) sont les mêmes. |
| Base | **MariaDB 11.8** + `performance_schema` + slow log | Digests natifs (top requêtes par temps cumulé, lignes lues, sans index), zéro outil externe. `pt-query-digest`/PMM écartés : une image de plus pour la même info. |
| Schéma | plugin-liquibase au premier boot, comme en production v8 | Générique pour tout plugin/site : chaque jar apporte ses SQL ; pas de scripts à collecter à la main. |
| Volume synthétique | SQL pur, moteur **SEQUENCE** de MariaDB (`seq_1_to_N`) | 100 000 utilisateurs en quelques secondes côté serveur, idempotent, sans générateur externe (Datafaker, Misata… : dépendance et lenteur pour zéro gain sur des tables de référentiel). |
| Timings serveur | **Access log Liberty** (`%D` µs par requête) + `/metrics` (mpMetrics 5.1 / monitor-1.0 : pool JDBC, servlets, GC) | Mesure côté serveur sans instrumentation applicative ; p50/p95 par chemin dérivés par script. |
| Profil JVM | **JFR** continu (`settings=profile`) dumpé à chaud, résumé par `jfr view hot-methods / allocation-by-class / gc-pauses / contention-by-site` | Texte compact, lisible par un agent ; pas de JMC, pas de Grafana. |
| Charge | **k6 1.5** (conteneur `grafana/k6`) sur les écrans d'entrée, seuils p95 / taux d'erreur | Binaire unique, seuils = code de sortie. Gatling écarté (JVM, rapport HTML lourd) : la charge n'est qu'une phase courte du bench. |
| Empreinte d'écran | **Aria snapshot** (YAML de l'arbre d'accessibilité) + capture JPEG | Le diff structurel est textuel, stable entre machines, et coûte quelques lignes ; les pixels servent aux humains, pas aux assertions. |
| Console navigateur | `console` (error/warning), `pageerror`, `requestfailed`, réponses ≥ 400 sur chaque page | « Console 100 % propre » est une assertion, pas une option. |
| Exigences | **EARS** générées depuis l'inventaire + scénarios (`requirements.ears.md`) | Une phrase testable par écran/action ; la couverture se lit par exigence. Générées, jamais maintenues à la main. |
| Rapport | `summary.md` (compact) + `report.html` (galerie) + `junit-*.xml` | Le markdown est ce que lit l'agent ; JUnit est ce que lit Jenkins ; l'HTML est ce que regarde le chef de projet. |

## Ce qui est écarté, et pourquoi

- **Playwright Agents (planner / generator / healer), Playwright MCP** : génération de tests par LLM depuis VS Code. Coût en tokens élevé, non déterministe, à l'opposé du but (tests dérivés de l'inventaire par script). Le skill génère la structure, l'agent n'écrit que du YAML.
- **Allure** (2 Java / 3 Node) : demandé pour Jenkins. Allure 3 exige Node + `allure` dans le PATH des agents ; Allure 2 est un « global tool » Java. Le plugin JUnit de Jenkins lit `junit-*.xml` sans rien installer, HTML Publisher affiche `report.html`. Allure apporte l'historique/tendances : à ajouter seulement si un projet le demande (`allure-pytest` écrit `allure-results`, une ligne dans `run.sh`).
- **Grafana otel-lgtm / Prometheus** : superbe en exploration interactive, inutile pour un bench qui doit produire un rapport texte et s'éteindre.
- **Captures pixel comme oracle** : dépendantes des polices, de l'antialiasing, de l'OS ; faux positifs garantis en CI.
- **Testcontainers** : isolation par test, langage Java, pas un stack e2e.
- **Images ICR OpenJ9** pour le bench : voir ci-dessus (JFR). Restent la référence pour la production.
- **Rendu intégral en un seul rapport PDF** : `report.html` avec `content-visibility:auto` suffit ; un PDF peut être dérivé par Chromium si un projet l'exige.

## Flux `run.sh`

```
build      mvn install (cible) → site e2e (pom généré) → war → image app
up         compose up db+app → healthcheck → dbinit (post-init + seed)
inventory  inventory.py (SQL rights, plugin.xml, JSP, @Controller/@View/@Action, templates) → EARS
discover   crawl authentifié : liens GET depuis le menu et les entrées (jamais Do*/action=) → urls concrètes
test       screens (parallèle) → scenarios → forms ; /metrics avant/après
perf       k6 → jcmd JFR.dump → jfr view → access log → digests SQL → perf.json
report     summary.md + report.html + results.json
down       compose down -v
```

## Invariants du harnais

Ce que les scripts imposent, et qu'aucune modification ne doit relâcher :

1. **Oracle positif** (`lutece.classify`) : un écran n'est réussi que si le DOM porte la barre de menu admin
   (`#main-menu`) sans texte d'erreur ; toute autre page est classée (`confirmation`, `error`, `auth`, `login`,
   `error-page`, `fo`, `fragment`, `http-NNN`) et l'attendu est explicite par type d'écran. L'absence de marqueur
   d'erreur n'est jamais une réussite : « Veuillez vous authentifier » et « Internal error » se rendent en HTTP 200.
2. **Auto-tests de l'oracle** (`tests/test_harness.py`) exécutés en premier ; `run.sh` s'arrête (code 3) s'ils échouent.
3. **Classification visible** : le rapport compte les types de page des tests *réussis* (`auth ×40` saute aux yeux).
4. **Alarme de contenu identique** : des URL différentes réussies avec le même texte de page sont signalées.
5. **Garde de session** : un écran classé `auth` déclenche une reconnexion et un second essai ; les écrans publics
   (AdminForgot*, AdminFormContact, AdminResetPassword) tournent en contexte anonyme car ils invalident la session.
6. **Pas de no-op** : `fill_form`, `submit`, `click`, `fill` échouent sur un élément absent, résolvent l'élément par
   le locator Playwright (jamais `document.querySelector` avec `:has()` / `:text-is()`).
7. **Couverture par élément d'inventaire** (`tools/coverage.py`) : chaque écran/action est atteint, exclu avec une
   raison écrite (`scenarios/coverage-exclusions.yaml`), ou listé « à couvrir ». Prouvé ≠ atteint : ne sont prouvées
   que les pages qu'un oracle réussi a couvertes (`record.proven`) ; le reste est une dette listée, jamais soustraite.
8. **Cause serveur par échec** (`tools/causes.py`) : exceptions de `messages.log` corrélées par fenêtre de temps et
   confirmées par le nom de la JSP/du bean.
9. **Bare vs paramétré** : un écran appelé sans ses paramètres peut répondre un message Lutece, jamais une erreur
   interne ; le rapport sépare les deux populations.
10. **Une mutation sans oracle d'état** dans les trois pas suivants rend le scénario invalide (test rouge nommant le
    pas). Oracles d'état : `sql`, `expect_dom`, `mail`, `fake_log`, `http`, `download` ; `expect_text`, `expect_message`,
    `expect_kind`, `expect_html` lisent l'écran, pas l'état : faibles, jamais suffisants seuls après une mutation.
    `expect_text` sur une URL ou un nom de JSP est refusé ; `sql_exec` n'est permis qu'avant la première mutation ou
    après le dernier oracle.
11. **Négatif et droits obligatoires** : refus d'accès, CSRF sans jeton, doublons, champs obligatoires vides
    (`submit_novalidate` contourne le HTML5 pour atteindre le contrôle serveur).
12. **Trois populations d'échecs** : fonctionnels (écran paramétré, scénario, formulaire), front (JS, console) et
    robustesse (écran appelé sans paramètres). La propreté console est jugée par la suite écrans, une fois par écran.
13. **Découverte** : profondeur 8, 25 variantes par écran (chemin + `view`), formulaires collectés à toutes les
    profondeurs, formulaires GET suivis.
14. **Invariants du banc** : le fuzzer ne touche jamais les comptes du banc (`PROTECTED_SCREEN`, `protected`) ;
    `run.sh` vérifie après les tests que le compte administrateur existe encore, sinon code 4 et alerte en tête de rapport.
15. **Isolation des scénarios parallèles** : tout ce qui modifie un formulaire partagé (attributs, paramètres) choisit
    des valeurs neutres ou passe en `serial`.
16. **Un constat doit survivre à une base propre** : le seed de référence se rejoue avant chaque `test`, et un constat
    sur une donnée seedée n'est retenu qu'après vérification de sa présence.
17. **Un saut ne prouve rien** : une suite qui avait quelque chose à prouver et dont tous les tests sont ignorés fait
    échouer le run (code 8) ; le résumé la marque. Exception : une exclusion écrite et justifiée dans le banc
    (`screens.yaml` clé `skip`, ou `versions` d'un scénario) reste verte, avec sa raison dans le résumé.
18. **Le rapport dit ce qui a été testé** (`artifacts/fingerprint.json`) : commit des sources, hash du war, digests des
    images. Les codes de retour distinguent les causes (3 oracle, 4 invariant, 5 erreurs serveur,
    6 smoke, 7 revue, 8 suite ignorée) ; `compare` propage le code de la jambe v8.

## Pièges rencontrés (à conserver dans le skill)

- `configure.sh` de l'image Liberty échoue (code 22) si `jvm.options` contient `-XX:StartFlightRecording` (populate_scc).
- OpenJ9 : `dumponexit` invalide ; le dump se fait à l'arrêt de la JVM ; assertion VM sous échantillonnage → HotSpot.
- Le `dataSource` Liberty est résolu **avant** l'expansion du war : le driver JDBC doit être extrait à la construction de l'image (`shared/resources/jdbc`), pas lu dans `apps/expanded`.
- Bind mount `/logs` : créé root par Docker → `chmod 777` avant `up`, et l'app tourne avec l'uid hôte (`user:`) pour que JFR et access log soient lisibles.
- `form.action` n'est pas une chaîne quand un champ s'appelle `action` : lire `getAttribute('action')`.
- `plugins.dat.tpl` posé dans `webapp/` finit dans le war : garder les templates hors de l'arborescence copiée.
- Le healthcheck sur `AdminLogin.jsp` passe avant la fin de l'init Lutece si Liquibase échoue : lire `messages.log`, pas seulement l'état `healthy`.
- Ne jamais nommer le service Compose `app` : `.app` est un TLD de la liste HSTS préchargée de Chromium, `http://app:9090` est réécrit en https → `ERR_SSL_PROTOCOL_ERROR` dans le runner (l'IP et `localhost` passent, d'où un diagnostic trompeur vers l'entête HSTS du core, qui n'y est pour rien : un entête HSTS reçu en HTTP est ignoré). Le service s'appelle `lutece`.
- Le core envoie une CSP avec `upgrade-insecure-requests` : sur une origine non « potentially trustworthy » (tout sauf localhost/https) Chromium réécrit chaque sous-ressource en https. `--unsafely-treat-insecure-origin-as-secure` n'a pas suffi dans le headless shell ; la solution robuste : le runner (et k6) partagent le namespace réseau du conteneur applicatif (`network_mode: service:lutece`) et parlent à `http://localhost:9090`, origine de confiance pour Chromium, exactement comme depuis le poste.
- Le formulaire public « identifiant oublié » invalide la session : les écrans sans session tournent dans un contexte anonyme, sinon toute la suite du worker retombe sur `AdminMessage.jsp`.
- `DoCreateWorkgroup` affecte le créateur au groupe : la suppression est refusée tant qu'il n'est pas désaffecté (scénario réaliste : refus attendu, puis désaffectation, puis suppression).
- Ne jamais passer un sélecteur Playwright (`:has()`, `:text-is()`) à `document.querySelector` dans un `evaluate` : il lève une erreur qu'un `except` large avalait, et la soumission devenait un no-op silencieux. Résoudre l'élément par `locator(...).evaluate(...)`, et ne rattraper que le délai de navigation.
- `expect_message` : le thème n'expose que la couleur de la carte (`bg-danger`/`bg-warning`) ; la confirmation se reconnaît à ses deux formulaires (valider / annuler).

### Pièges des benchs de plugin
- Le core v8 lit le thème global dans une clé du datastore que seule l'installation neuve écrit : la montée 7→8
  ne la crée pas, `ThemeDAO.getGlobalTheme` déréférence une entité nulle et toutes les pages du site migré
  répondent 500. Le banc écrit la clé quand elle manque, en le disant : c'est un défaut amont contourné, pas un
  comportement de l'artefact testé.
- Un plugin assemblé côté v8 mais absent de la jambe v7 arrive sur une base où ses tables existent déjà, sans
  version enregistrée pour lui : il est installé comme neuf, son script de création est marqué appliqué et ses
  montées ne tournent jamais. Le schéma reste en forme v7 et le site échoue sur une colonne que la montée aurait
  ajoutée — cela se lit comme un défaut de migration. Les deux jambes listent les mêmes plugins.
- Une sonde du bench écrite avec les API v8 ne compile pas sur la jambe v7 : les scénarios qui passent par elle
  s'arrêtent avec une raison écrite au lieu de virer au rouge, sinon la comparaison lit « corrigé » sur du code
  de bench. Sur la version visée par le bench, la même sonde cassée reste rouge.
- La configuration d'un site v7 vit dans ses `.properties` et ses contextes Spring : aucune variable
  d'environnement ne l'atteint. `harness/v7-overlay/` est posé sur la webapp v7 assemblée pour la pointer vers
  les doublures, comme `app.env` le fait côté v8.
- Un pom v7 déclare souvent ses dépendances en intervalles ouverts dont le haut a bougé : la jambe ne compile
  plus. `E2E_V7_DEP_PINS` fige ces versions dans le worktree jetable, en intervalle à une valeur (une version
  simple perd face à un intervalle).
- Le créneau de ports d'un bench est enregistré, pas choisi sur les ports libres du moment : sinon tous les bancs
  initialisés sur une machine au repos prennent le créneau 0 et deux d'entre eux ne peuvent jamais tourner
  ensemble.
- `gen-site.sh` prenait `project.parent.version` pour le core : c'est la version du global-pom, pas du core. Résolu par `mvn dependency:list`.
- Un bench de plugin scanne aussi la webapp éclatée du site : sans marquage `origin`, 80 rouges du core noyaient les 4 du plugin dans le rapport.
- TinyMCE recopie le contenu de l'éditeur dans le textarea au submit : un `fill` DOM sur le textarea caché est écrasé. Le pas `fill` alimente aussi l'éditeur.
- Le macro offcanvas du core importe `./themes/shared/modules/bootstrap/luteceBSOffCanvas.js` en relatif : sur une page sans `<base>` (fragment servi sous `jsp/admin/plugins/<p>/`), la requête part vers `jsp/admin/plugins/<p>/themes/...` → 500. Défaut du core, visible dans « sous-requêtes en échec ».
- Les données d'exemple d'un plugin (`init_db_<p>_data_sample.sql`) sont consommées par le fuzzer dès le premier run : les scénarios ne s'y fient jamais, ils lisent `seed-<plugin>.sql`.
- Sans puits SMTP, `MailService.sendMailHtml` lève `MailConnectException` (localhost:25) et le flux métier qui l'appelle avant d'écrire en base échoue : Mailpit dans la stack, adressé par variables d'environnement (MicroProfile Config lit `MAIL_SERVER` pour `mail.server`).
- Un bench de plugin ne doit ouvrir que les écrans du plugin : `E2E_SCOPE=target` filtre découverte, suites et k6 sur l'inventaire `origin=target`.
- Sous pytest-xdist, `pytest_runtest_makereport` se déclenche sur chaque worker et sur le contrôleur : sans garde, chaque résultat est écrit deux fois (gwN.jsonl + main.jsonl) et le rapport double les compteurs. Garde : n'écrire que si worker (numprocesses défini ⇒ exiger PYTEST_XDIST_WORKER).

