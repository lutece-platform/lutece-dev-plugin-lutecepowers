#!/usr/bin/env bash
# Orchestre l'environnement de test à conteneurs mock (activation à la carte via profils).
#   testenv.sh up [mail|captcha|all ...]   |   testenv.sh down
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/docker-compose.testenv.yml"

cmd="${1:-up}"; shift || true
case "$cmd" in
  up)
    profiles=("${@:-mail}")
    args=(); for p in "${profiles[@]}"; do args+=(--profile "$p"); done
    docker compose -f "$F" "${args[@]}" up -d
    # attentes de disponibilité selon les profils activés
    printf '%s\n' "${profiles[@]}" | grep -qE 'mail|all' && for i in $(seq 1 30); do curl -sf http://localhost:8025/api/v2/messages >/dev/null 2>&1 && { echo "✓ MailHog (http://localhost:8025)"; break; }; sleep 1; done
    printf '%s\n' "${profiles[@]}" | grep -qE 'captcha|all' && for i in $(seq 1 30); do curl -sf http://localhost:8090/__admin/mappings >/dev/null 2>&1 && { echo "✓ WireMock (http://localhost:8090/__admin)"; break; }; sleep 1; done
    ;;
  down)
    docker compose -f "$F" --profile all down ;;
  *)
    echo "usage: testenv.sh up [mail|captcha|all ...] | down"; exit 1 ;;
esac
