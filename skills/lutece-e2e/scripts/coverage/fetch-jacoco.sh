#!/usr/bin/env bash
# Récupère l'agent + le CLI JaCoCo dans .artifacts/jacoco/ (agent depuis M2 si présent, sinon Maven Central).
set -euo pipefail
DEST=".artifacts/jacoco"; mkdir -p "$DEST"
V="${JACOCO_VERSION:-0.8.12}"
AGENT=$(find ~/env/m2 ~/.m2 -path "*org.jacoco.agent/$V*" -name '*runtime.jar' 2>/dev/null | head -1)
if [ -n "$AGENT" ]; then cp -f "$AGENT" "$DEST/jacocoagent.jar"; else
  curl -fsSL -o "$DEST/jacocoagent.jar" "https://repo1.maven.org/maven2/org/jacoco/org.jacoco.agent/$V/org.jacoco.agent-$V-runtime.jar"; fi
[ -f "$DEST/jacococli.jar" ] || curl -fsSL -o "$DEST/jacococli.jar" "https://repo1.maven.org/maven2/org/jacoco/org.jacoco.cli/$V/org.jacoco.cli-$V-nodeps.jar"
echo "agent: $(du -h "$DEST/jacocoagent.jar" | cut -f1) · cli: $(du -h "$DEST/jacococli.jar" | cut -f1)"
