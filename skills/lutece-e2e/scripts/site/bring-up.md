# Mettre un site Lutèce 8 debout (prérequis des tests e2e)

Le SKILL énonce le prérequis en une ligne — « un site Lutèce running ». **C'est là que passe le plus de
temps** : en usage réel, plusieurs heures, sur trois pièges qui se ressemblent tous (« le serveur démarre
mais l'application ne marche pas ») et qui coûtent chacun un diagnostic complet.

À lire **avant** de conclure qu'un test échoue : un site mal monté produit des rouges qui n'ont rien à voir
avec le code testé.

## Ordre STRICT (les étapes ne commutent pas)

```bash
mvn clean install -Dmaven.test.skip=true          # 1) artefacts
mvn liberty:create                                # 2) crée/réinitialise le serveur
mvn liberty:deploy                                # 3) déploie l'application (loose-app)
<wlp>/bin/featureUtility installServerFeatures <serveur>   # 4) installe les features du server.xml
#    → PUIS SEULEMENT : patcher le loose-app (voir piège 3)
<wlp>/bin/server start <serveur>                  # 5) démarrer
```

**Après l'étape 4, ne relancer AUCUN goal `mvn liberty:*`** : `liberty:create` réinitialise le serveur et
**efface les features installées** (piège 2). Si un goal `liberty` doit être rejoué, il faut réinstaller les
features derrière.

## Les trois pièges

### 1. Serveur démarré, aucune feature installée
Une installation Liberty fraîche n'embarque **rien**. Le serveur démarre normalement, mais le journal dit :

```
CWWKF0012I: The server installed the following features: []
```

Conséquence : ni servlet, ni CDI, ni JDBC → l'application ne répond pas, ou répond en erreur, sans message
explicite. **Contrôle** : `CWWKF0012I` doit lister des features (`servlet-6.0`, `cdi-4.0`, `jdbc-4.3`,
`concurrent-3.0`…). Si la liste est vide → étape 4.

### 2. `liberty:create` efface les features déjà installées
C'est le piège qui fait tourner en rond : on installe les features, ça marche ; on rejoue un goal Maven
« pour être sûr », et on retombe sur le piège 1 **avec l'impression d'avoir déjà réglé le problème**.

### 3. Le loose-app mappe la configuration un niveau trop bas
Le descripteur généré peut contenir :

```xml
<dir sourceOnDisk=".../webapp/WEB-INF/conf/local" targetInArchive="/WEB-INF/conf/"/>
```

alors que l'arborescence source **commence déjà** par `WEB-INF/conf/`. Le chemin effectif devient donc
`/WEB-INF/conf/WEB-INF/conf/...` : **aucun override n'est lu**, le `db.properties` livré par défaut gagne,
et le site échoue sur :

```
AppException: Database access error
WELD-000049 ...
```

**Correctif** : `targetInArchive="/"`. **Contrôle** : vérifier que le fichier d'override est bien visible à
l'emplacement attendu dans l'application déployée avant de démarrer.

## Un espace dans le chemin casse Lutèce en silence

Un espace dans le chemin du projet (ex. `mon projet/`) casse `AppPathService.getResourceStream` : le
chemin est encodé (`%20`) puis utilisé tel quel comme chemin de fichier. Résultat mesuré : **6 descripteurs
de plugins sur 13 ne se chargent pas**, aucun module d'authentification admin ne s'enregistre, et le BO
rend une **500** sur NPE `AdminAuthenticationService.getLoginPageUrl()`.

**Le FO, lui, répond 200.** Donc un contrôle sommaire conclut « site debout » et on part chercher un défaut
applicatif inexistant. Un test d'une ligne — « le chemin contient-il un espace ? » — remplace une heure de
diagnostic. Le `global-setup` le fait si `SITE_DIR` est renseigné dans `.env.local`.

## Contrôles avant de lancer la suite

| Contrôle | Comment | Pourquoi |
|---|---|---|
| Features installées | `CWWKF0012I` non vide dans le journal | piège 1 |
| Application démarrée | attendre **`CWWKT0016I`** (application disponible), pas seulement le port ouvert | un port ouvert ne veut pas dire application déployée |
| Override de conf lu | le fichier d'override est présent dans l'application déployée | piège 3 |
| Chemin sans espace | `SITE_DIR` renseigné → contrôle automatique au `global-setup` | descripteurs non chargés |
| **Une page BO authentifiée répond** | ouvrir `jsp/admin/AdminLogin.jsp` puis se connecter | **FO 200 ne prouve rien** |

> **Règle** : ne jamais démarrer une campagne de tests sur la seule preuve que le FO répond. Le contrôle qui
> vaut, c'est une page **BO authentifiée** — c'est exactement ce que fait `assertAuthenticated` dans le
> `global-setup`, et c'est pour ça qu'il échoue bruyamment plutôt que d'enregistrer une session invalide.

## Si la suite s'effondre en masse

Ne pas diagnostiquer spec par spec. Regarder le **HTML réellement servi** sur une URL quelconque : une page
« Startup error » rendue en **HTTP 200** fait échouer l'intégralité de la suite sans qu'un seul test soit en
cause. Remonter alors au journal du serveur, pas aux specs.
