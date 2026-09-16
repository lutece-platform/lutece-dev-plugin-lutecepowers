#!/usr/bin/env bash
# Lists, per admin template, the form actions and the field names: everything needed to write a scenario
# without opening the templates. Usage: forms.sh <source root> [filter]   (filter: substring of the path)
set -euo pipefail
ROOT=${1:-.}; FILTER=${2:-}
find "$ROOT" -path '*templates/admin/*' -name '*.html' -not -path '*/target/*' -not -path '*/themes/*' | sort | while read -r f; do
  case "$f" in *"$FILTER"*) ;; *) continue;; esac
  a=$(grep -oE "(<@tform|<form)[^>]*action=['\"][^'\"]*['\"]" "$f" | grep -oE "action=['\"][^'\"]*" | sed "s/action=['\"]//" | sort -u | tr '\n' ' ' || true)
  [ -n "$a" ] || continue
  n=$(grep -oE "<@(input|select|checkBox|radioButton|textarea)[^>]*name=['\"][^'\"]+" "$f" | grep -oE "name=['\"][^'\"]+" | sed "s/name=['\"]//" | grep -v '^token$' | sort -u | tr '\n' ',' || true)
  u=$(grep -oE "type=['\"]file['\"]" "$f" | head -1 | sed 's/.*/ [file upload]/' || true)
  echo "${f#*templates/admin/} | $a| $n$u"
done
