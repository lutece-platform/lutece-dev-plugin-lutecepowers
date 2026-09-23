---
name: lutece-checkup
description: "Use when the user wants the mechanical state of a Lutece 8 project (core, plugin, module, site) without changing it: runs every check script of the toolkit in one pass (verify-migration, template scanner, i18n keys, template parse), summarises the blocking and the warning findings, then asks the user what to do. Triggers on 'checkup', 'bilan', 'état du plugin', 'lance les contrôles', 'vérifie le projet', 'mechanical check'."
---

# Lutece checkup

A read-only health check. It changes nothing; the user decides what comes next.

## 1. Run

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-checkup/scripts/checkup.sh <project-dir>
```

A few seconds once the project is assembled (the scanner and the i18n check assemble it with
`mvn lutece:exploded-lite` the first time). Full outputs land in `<project>/target/checkup/`.
Exit 1 means at least one blocking finding.

## 2. Report

Give the user, in their language, three short groups taken from the script's output only:

- **Blocking**: every FAIL of verify-migration, unresolved i18n keys, templates that do not parse, a tool that
  stopped before its end (and why).
- **To fix**: every WARN, grouped by code, with the files.
- **To decide**: the INFO codes and their counts.

For the meaning of a code and how to fix it, read its row in
`skills/lutece-migration-v8-agent-teams/verification/checks.md`; the rule it points to is in `rules/`.
Never add a finding the tools did not print, never drop one.

## 3. Ask

Ask the user what to do, with these options: fix the blocking findings, fix blocking and warnings, explain
one finding, or stop here. Fixing follows the skill that owns the files (lutece-patterns for Java,
lutece-update-template-bo / -fo for templates) and ends by running this checkup again.
