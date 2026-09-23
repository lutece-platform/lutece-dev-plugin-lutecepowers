#!/usr/bin/env bash
# Checks fix-i18n-bundles.py on a synthetic plugin: each of the five repairs, and what it must leave alone.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts/fix-i18n-bundles.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/plugin-demo/src/java/fr/paris/lutece/plugins/demo/resources"
mkdir -p "$R" "$T/plugin-demo/webapp/WEB-INF/templates"
printf 'name=Demo\r\ntwice=Twice\r\nlong=first \\\r\n     (0: second)\r\ndemo.dup=duplicate of dup\r\ndup=Dup\r\ndemo.only=prefixed only\r\ndemo.asked=really asked as demo.demo.asked\r\n' > "$R/demo_messages.properties"
printf 'name=D\xc3\xa9mo\r\nlong=premi\xc3\xa8re \\\r\n     (0: seconde)\r\ndup=Doublon\r\ndemo.only=pr\xc3\xa9fix\xc3\xa9e\r\ndemo.asked=demand\xc3\xa9e\r\ntwice=ancien\r\nname=D\xc3\xa9mo final\r\n' > "$R/demo_messages_fr.properties"
printf 'name=Demo\ndup>Dup\nlong>Lunga (esempio: x)\nTranslated\\u00e1Key=garbage\ngone.key=removed from default\n' > "$R/demo_messages_dk.properties"
echo '#i18n{demo.demo.asked}' > "$T/plugin-demo/webapp/WEB-INF/templates/page.html"
(cd "$T/plugin-demo" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
python3 "$SCRIPT" --dry-run "$T/plugin-demo" > "$T/dry.txt"
dry_status=$(cd "$T/plugin-demo" && git status --short)
python3 "$SCRIPT" "$T/plugin-demo" > "$T/out.txt"
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
check "dry-run touches nothing" '[ -z "$dry_status" ]'
check "dry-run prints what the run does" 'diff -q "$T/dry.txt" "$T/out.txt" >/dev/null'
check "arrow fixed when the value holds a colon" 'grep -qx "long=Lunga (esempio: x)" "$R/demo_messages_da.properties"'
check "dk renamed to da" '[ -f "$R/demo_messages_da.properties" ] && [ ! -f "$R/demo_messages_dk.properties" ]'
check "rename recorded by git" '(cd "$T/plugin-demo" && git status --short | grep -q "^R.*demo_messages_da")'
check "arrow separator fixed" 'grep -qx "dup=Dup" "$R/demo_messages_da.properties"'
check "orphan translated key removed" '! grep -q "Translated" "$R/demo_messages_da.properties"'
check "orphan old key removed" '! grep -q "gone.key" "$R/demo_messages_da.properties"'
check "prefixed duplicate removed" '! grep -q "^demo.dup" "$R/demo_messages.properties"'
check "prefixed only key renamed" 'grep -q "^only=prefixed only" "$R/demo_messages.properties" && grep -q "^only=pr" "$R/demo_messages_fr.properties"'
check "doubled key asked for is kept" 'grep -q "^demo.asked=" "$R/demo_messages.properties"'
check "duplicate keeps the last value" '[ "$(grep -c "^name=" "$R/demo_messages_fr.properties")" = 1 ] && grep -q "^name=D.*mo final" "$R/demo_messages_fr.properties"'
check "continuation kept" 'grep -q "(0: seconde)" "$R/demo_messages_fr.properties"'
check "utf-8 bytes kept" 'grep -q "$(printf "D\xc3\xa9mo")" "$R/demo_messages_fr.properties"'
check "CRLF kept" '[ "$(grep -c $'"'"'\r$'"'"' "$R/demo_messages.properties")" = "$(wc -l < "$R/demo_messages.properties")" ]'
check "second run changes nothing" '[ -z "$(python3 "$SCRIPT" "$T/plugin-demo")" ]'
echo "dup" > "$T/dead.txt"
python3 "$SCRIPT" --drop "$T/dead.txt" "$T/plugin-demo" >> "$T/out.txt"
check "dropped key gone in every language" '! grep -q "^dup[=>]" "$R/demo_messages.properties" "$R/demo_messages_fr.properties" "$R/demo_messages_da.properties"'
check "other keys kept by drop" 'grep -q "^name=" "$R/demo_messages.properties" "$R/demo_messages_da.properties"'
if [ $fail = 0 ]; then echo "PASS: fix-i18n-bundles repairs I18N05, I18N06, I18N01, I18N10, I18N09 and keeps the rest"; else cat "$T/out.txt"; exit 1; fi
