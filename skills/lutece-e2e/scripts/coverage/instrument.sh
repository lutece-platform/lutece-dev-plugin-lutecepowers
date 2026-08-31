#!/usr/bin/env bash
# Ajoute l'agent JaCoCo (mode tcpserver:6300) au jvm.options du serveur Liberty. Redémarrage requis ensuite.
set -euo pipefail
OPTS="${1:?usage: instrument.sh <chemin jvm.options> <chemin jacocoagent.jar>}"
AGENT="${2:?chemin jacocoagent.jar}"
AGENT_ABS="$(cd "$(dirname "$AGENT")" && pwd)/$(basename "$AGENT")"
LINE="-javaagent:${AGENT_ABS}=output=tcpserver,address=localhost,port=6300,append=false"
if grep -qF "org.jacoco" "$OPTS" 2>/dev/null; then
  echo "déjà instrumenté : $(grep jacoco "$OPTS")"
else
  echo "$LINE" >> "$OPTS"
  echo "ajouté à $OPTS :"; grep jacoco "$OPTS"
fi
echo "→ REDÉMARRER le serveur pour appliquer (liberty:dev : relancer ; wlp/bin/server : stop puis start)."
