#!/usr/bin/env bash
# Bumps or checks the plugin version across every manifest declared in .version-bump.json.
# Usage: bump-version.sh <X.Y.Z> | --check

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/.version-bump.json"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Lists declared manifests as "path<TAB>jq field" lines.
entries() { jq -r '.files[] | "\(.path)\t\(.field)"' "$CONFIG"; }

# Prints every declared version and fails when they differ.
check() {
  local drift=0 first=""
  while IFS=$'\t' read -r path field; do
    local v; v="$(jq -r "$field" "$ROOT/$path")"
    printf '  %-40s %s\n' "$path" "$v"
    [ -z "$first" ] && first="$v"
    [ "$v" = "$first" ] || drift=1
  done < <(entries)
  [ "$drift" -eq 0 ] && echo "All manifests at $first" || { echo "DRIFT: versions differ"; return 1; }
}

# Writes the given version into every declared manifest.
bump() {
  local new="$1"
  [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$ ]] || { echo "expected X.Y.Z, got '$new'" >&2; exit 1; }
  while IFS=$'\t' read -r path field; do
    local f="$ROOT/$path" tmp
    tmp="$(mktemp)"
    jq --indent 2 --arg v "$new" "$field = \$v" "$f" > "$tmp" || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$f"
    echo "  $path -> $new"
  done < <(entries)
}

case "${1:-}" in
  --check) check ;;
  ""|-h|--help) echo "Usage: bump-version.sh <X.Y.Z> | --check" ;;
  *) bump "$1" && check ;;
esac
