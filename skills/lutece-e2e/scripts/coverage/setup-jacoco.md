# Mesure de couverture JaCoCo (Phase 3)

Mesure la couverture de code **réelle** (lignes/branches) exercée par la suite e2e, et la confronte à
la carte du graphe (Phase 2). L'instrumentation nécessite un **redémarrage** du serveur.

## Étapes

```bash
# 1) Outils (agent + CLI) dans .artifacts/jacoco/
bash scripts/coverage/fetch-jacoco.sh

# 2) Instrumenter le serveur : ajouter l'agent au jvm.options SOURCE (liberty:dev le recopie au démarrage)
bash scripts/coverage/instrument.sh <projet-site>/src/main/liberty/config/jvm.options .artifacts/jacoco/jacocoagent.jar
#    → REDÉMARRER liberty:dev (ou wlp/bin/server stop && start), puis vérifier :
ss -tlnp | grep 6300      # le port tcpserver de l'agent doit être en écoute

# 3) Lancer la suite e2e (le serveur accumule la couverture)
npx playwright test

# 4) Dump + rapport (jars des plugins + sources)
node scripts/coverage/coverage-report.mjs <projet-site>/target/site-support-*/WEB-INF/lib "$HOME/.lutece-references/<repo>/src/java"
#    (⚠️ ne PAS mettre "~/…" entre guillemets : le shell n'expanse pas le ~ quoté → utiliser $HOME)
#    → report/jacoco/index.html + report/jacoco.xml

# 5) Confronter graphe × couverture réelle
node scripts/coverage/graph-vs-jacoco.mjs   # → report/graph-vs-jacoco.md
```

## Retrait

Après mesure : retirer la ligne `-javaagent:...jacoco...` du jvm.options et redémarrer le serveur
(l'agent en tcpserver ne doit pas rester en permanence).

## Interprétation

- Une classe de JspBean du graphe à **0 % / « jamais exercée »** = fonctionnalité détectée mais non testée
  → cibler avec un test (gabarit) si atteignable par l'IHM, sinon test unitaire.
- JaCoCo **tranche** entre branches *détectées* (graphe statique) et branches *réellement exercées*.
