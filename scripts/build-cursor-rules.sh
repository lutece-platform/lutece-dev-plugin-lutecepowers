#!/usr/bin/env bash
# Generates rules-cursor/*.mdc (Cursor rule format: description, globs, alwaysApply) from rules/*.md.
# Run after editing any rule. Output is committed so the plugin works without a build step.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/rules"
DST="$ROOT/rules-cursor"

rm -rf "$DST" && mkdir -p "$DST"

for f in "$SRC"/*.md; do
  name="$(basename "$f" .md)"
  python3 - "$f" "$DST/$name.mdc" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
m = re.match(r"---\n(.*?)\n---\n(.*)$", text, re.S)
fm, body = (m.group(1), m.group(2)) if m else ("", text)
desc = re.search(r'^description:\s*"?(.*?)"?\s*$', fm, re.M)
desc = desc.group(1) if desc else ""
globs = re.findall(r'^\s*-\s*"?([^"\n]+?)"?\s*$', fm, re.M) if "paths:" in fm else []
out = ["---", f'description: "{desc}"']
if globs:
    out.append("globs: " + ", ".join(globs))
    out.append("alwaysApply: false")
else:
    out.append("alwaysApply: true")
out.append("---")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n" + body.lstrip("\n"))
PY
done
echo "Generated $(ls "$DST" | wc -l) Cursor rules in rules-cursor/"
