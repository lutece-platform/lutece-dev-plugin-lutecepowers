#!/usr/bin/env bash
# Échafaude un projet de tests e2e Lutèce à partir des templates du skill.
# Usage : scaffold.sh <dossier-cible> <BASE_URL>
set -euo pipefail

DEST="${1:?usage: scaffold.sh <dossier-cible> <BASE_URL> [--force]}"
BASE_URL="${2:?BASE_URL requis (ex. http://localhost:9090/mon-site/)}"
FORCE="${3:-}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Ne pas écraser un projet de tests EXISTANT.
if [ -f "$DEST/playwright.config.ts" ] && [ "$FORCE" != "--force" ]; then
  echo "✗ Projet de tests déjà présent dans : $DEST" >&2
  echo "  → utiliser le MODE DELTA (couvrir seulement les changements, sans écraser) :" >&2
  echo "    $HERE/scripts/delta/delta-mode.md" >&2
  echo "  → ou forcer l'échafaudage (ÉCRASE l'existant) : scaffold.sh \"$DEST\" \"$BASE_URL\" --force" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -r "$HERE/templates/." "$DEST/"

# Conf locale : partir du gabarit, injecter la BASE_URL.
if [ ! -f "$DEST/.env.local" ]; then
  cp "$DEST/.env.local.example" "$DEST/.env.local"
fi
sed -i "s#^BASE_URL=.*#BASE_URL=${BASE_URL}#" "$DEST/.env.local"

cd "$DEST"
npm install
npx playwright install chromium

echo
echo "✓ Projet e2e prêt dans : $DEST"
echo "  BASE_URL = $BASE_URL"
echo "  → Renseigner dans $DEST/.env.local : ADMIN_USER, ADMIN_PASS, DB_NAME, DB_USER, DB_PASSWORD."
echo "    (livrés VIDES volontairement : une valeur héritée ferait tourner les tests contre la mauvaise base)"
echo "  → Optionnel : PLUGIN_NAME (priorise le plugin cible), PLUGIN_XML, SITE_DIR, UPLOAD_HANDLER, FO_USER/FO_PASS."
echo "  → Lancer :  (cd \"$DEST\" && npx playwright test)"
