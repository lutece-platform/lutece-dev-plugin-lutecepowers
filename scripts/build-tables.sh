#!/usr/bin/env bash
# Regenerates the skills and rules tables of the bootstrap skill and the README from the
# frontmatter of skills/*/SKILL.md and rules/*.md, between <!-- skills --> / <!-- rules --> markers.
# Run after adding or editing a skill or rule. Output is committed.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])

def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""

def field(fm, name):
    m = re.search(rf'^{name}:\s*"?(.*?)"?\s*$', fm, re.M)
    return m.group(1).strip() if m else ""

skills = []
for d in sorted(root.glob("skills/*/")):
    fm = frontmatter(d / "SKILL.md")
    if field(fm, "name") == "using-lutecepowers":
        continue
    skills.append((field(fm, "name"), field(fm, "description")))
skills_table = "| Skill | Use when |\n|---|---|\n" + "\n".join(f"| `{n}` | {d} |" for n, d in skills)

rules = []
for f in sorted(root.glob("rules/*.md")):
    fm = frontmatter(f)
    globs = re.findall(r'^\s*-\s*"?([^"\n]+?)"?\s*$', fm, re.M) if "paths:" in fm else []
    scope = ", ".join(f"`{g}`" for g in globs) if globs else "always"
    rules.append((f.stem, scope, field(fm, "description")))
rules_table = "| Rule | Applies to | Constraint |\n|---|---|---|\n" + "\n".join(f"| `{n}` | {s} | {d} |" for n, s, d in rules)

def splice(path, marker, table):
    text = path.read_text(encoding="utf-8")
    start, end = f"<!-- {marker}:start -->", f"<!-- {marker}:end -->"
    if start not in text or end not in text:
        raise SystemExit(f"{path}: missing {marker} markers")
    head, rest = text.split(start, 1)
    _, tail = rest.split(end, 1)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(f"{head}{start}\n{table}\n{end}{tail}")

for target in (root / "skills/using-lutecepowers/SKILL.md", root / "README.md"):
    splice(target, "skills", skills_table)
    splice(target, "rules", rules_table)
print(f"Tables regenerated: {len(skills)} skills, {len(rules)} rules")
PY
