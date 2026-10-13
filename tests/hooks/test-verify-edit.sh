#!/usr/bin/env bash
# Checks the verify-edit PostToolUse hook: hands back what an edit adds (exit 2), leaves the committed debt of a file
# and a project below Lutece 8 to one non-blocking note per session, stays silent on a clean file, outside a
# Lutece project and under the e2e folder of a project.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/../.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export TMPDIR="$T"
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
run() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "${2:-s1}" "$1" | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/verify-edit" >"$T/out" 2>"$T/err"; echo $?; }
runo() { python3 -c 'import json, sys; print(json.dumps({"session_id": sys.argv[3], "tool_name": "Edit", "tool_input": {"file_path": sys.argv[1]}, "tool_response": {"originalFile": open(sys.argv[2]).read()}}))' "$1" "$2" "${3:-s3}" | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/verify-edit" >"$T/out" 2>"$T/err"; echo $?; }
mkdir -p "$T/p/src/java" "$T/q" "$T/g/src/java" "$T/o/src/java"
POM='<project><parent><artifactId>lutece-global-pom</artifactId><version>8.0.2</version></parent><artifactId>plugin-x</artifactId></project>'
printf '%s\n' "$POM" > "$T/p/pom.xml"
printf 'package x;\nimport javax.servlet.http.HttpServletRequest;\npublic class Bad {}\n' > "$T/p/src/java/Bad.java"
printf 'package x;\npublic class Good {}\n' > "$T/p/src/java/Good.java"
printf '<project><artifactId>other</artifactId></project>\n' > "$T/q/pom.xml"; cp "$T/p/src/java/Bad.java" "$T/q/Bad.java"
check "a broken new Lutece file is handed back (exit 2)" '[ "$(run "$T/p/src/java/Bad.java")" = 2 ] && grep -q "FAIL JX01" "$T/err"'
check "a clean Lutece file is never an error" '[ "$(run "$T/p/src/java/Good.java" s0)" = 0 ] && [ ! -s "$T/err" ]'
check "a clean file of a project with Lutece 7 code elsewhere gets the note" 'grep -q "carry Lutece 7 code" "$T/out" && grep -q "lutece-update-plugin skill" "$T/out"'
mkdir -p "$T/c/src/java" && printf '%s\n' "$POM" > "$T/c/pom.xml" && cp "$T/p/src/java/Good.java" "$T/c/src/java/"
check "a clean file of a clean project is silent" '[ "$(run "$T/c/src/java/Good.java" s0)" = 0 ] && [ ! -s "$T/err" ] && [ ! -s "$T/out" ]'
check "a file outside a Lutece project is silent" '[ "$(run "$T/q/Bad.java")" = 0 ]'
check "a file of another kind is silent" 'echo x > "$T/p/notes.md"; [ "$(run "$T/p/notes.md")" = 0 ]'

printf '%s\n' "$POM" > "$T/g/pom.xml"; cp "$T/p/src/java/Bad.java" "$T/g/src/java/Bad.java"
git -C "$T/g" init -q && git -C "$T/g" add -A && git -C "$T/g" -c user.name=t -c user.email=t@t commit -qm init
printf '// edited\n' >> "$T/g/src/java/Bad.java"
check "a finding the committed file had is not an error" '[ "$(run "$T/g/src/java/Bad.java")" = 0 ] && [ ! -s "$T/err" ]'
check "it is a note offering the update skill" 'grep -q "additionalContext" "$T/out" && grep -q "lutece-update-plugin skill" "$T/out"'
check "the note comes once per session" '[ "$(run "$T/g/src/java/Bad.java")" = 0 ] && [ ! -s "$T/out" ]'
sed -i 's/^public class/import javax.inject.Inject;\npublic class/' "$T/g/src/java/Bad.java"
check "what the edit adds is handed back, alone" '[ "$(run "$T/g/src/java/Bad.java")" = 2 ] && grep -q "JX04" "$T/err" && ! grep -q "JX01" "$T/err"'

printf '<project><parent><artifactId>lutece-global-pom</artifactId><version>7.0.5</version></parent><artifactId>plugin-x</artifactId></project>\n' > "$T/o/pom.xml"
cp "$T/p/src/java/Bad.java" "$T/o/src/java/Bad.java"
check "a project below Lutece 8 is never an error" '[ "$(run "$T/o/src/java/Bad.java" s2)" = 0 ] && [ ! -s "$T/err" ]'
check "it gets the note instead" 'grep -q "below Lutece 8" "$T/out" && grep -q "lutece-update-plugin skill" "$T/out"'
mkdir -p "$T/n/src/java" && printf '%s\n' "$POM" > "$T/n/pom.xml" && cp "$T/p/src/java/Bad.java" "$T/n/before.java"
sed 's/^public class Bad {}/public class Bad { int x; }/' "$T/n/before.java" > "$T/n/src/java/Bad.java"
check "outside git, the file before the edit is the baseline" '[ "$(runo "$T/n/src/java/Bad.java" "$T/n/before.java")" = 0 ] && [ ! -s "$T/err" ]'
sed 's/^public class/import javax.inject.Inject;\npublic class/' "$T/n/before.java" > "$T/n/src/java/Bad.java"
check "outside git, what the edit adds is handed back, alone" '[ "$(runo "$T/n/src/java/Bad.java" "$T/n/before.java")" = 2 ] && grep -q "JX04" "$T/err" && ! grep -q "JX01" "$T/err"'
mkdir -p "$T/r/mod/src/java"
printf '<project><parent><artifactId>lutece-global-pom</artifactId><version>6.1.0</version></parent><artifactId>root</artifactId><packaging>pom</packaging></project>\n' > "$T/r/pom.xml"
printf '<project><parent><artifactId>root</artifactId></parent><artifactId>plugin-m</artifactId><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><version>${lutece.core.version}</version></dependency></dependencies></project>\n' > "$T/r/mod/pom.xml"
cp "$T/p/src/java/Bad.java" "$T/r/mod/src/java/Bad.java"
check "a module of a reactor below Lutece 8 is never an error" '[ "$(run "$T/r/mod/src/java/Bad.java" s4)" = 0 ] && grep -q "below Lutece 8" "$T/out"'
mkdir -p "$T/k/src/java"
printf '<project><!-- <artifactId>lutece-core</artifactId><version>7.0.0</version> --><properties><core.v>[8.0.0,)</core.v></properties><dependencies><dependency><groupId>fr.paris.lutece</groupId><artifactId>lutece-core</artifactId><scope>provided</scope><version>${core.v}</version></dependency></dependencies></project>\n' > "$T/k/pom.xml"
cp "$T/p/src/java/Bad.java" "$T/k/src/java/Bad.java"
check "a commented 7 and a property range of 8 read as Lutece 8" '[ "$(run "$T/k/src/java/Bad.java" s5)" = 2 ] && grep -q "JX01" "$T/err"'
mkdir -p "$T/m/.migration" "$T/m/src/java" && cp "$T/o/pom.xml" "$T/m/pom.xml" && cp "$T/p/src/java/Bad.java" "$T/m/src/java/Bad.java"
check "during an update every finding comes back, without note" '[ "$(runo "$T/m/src/java/Bad.java" "$T/m/src/java/Bad.java" s6)" = 2 ] && grep -q "JX01" "$T/err" && [ ! -s "$T/out" ]'
mkdir -p "$T/plugins/plugin-w/webapp/WEB-INF/plugins" && printf '%s\n' "$POM" > "$T/plugins/plugin-w/pom.xml"
printf '<plug-in><application-class>x</application-class></plug-in>\n' > "$T/plugins/plugin-w/before.xml"
printf '<plug-in><application-class>x</application-class><!-- c --></plug-in>\n' > "$T/plugins/plugin-w/webapp/WEB-INF/plugins/w.xml"
check "a check that reads the path sees the same path before the edit" '[ "$(runo "$T/plugins/plugin-w/webapp/WEB-INF/plugins/w.xml" "$T/plugins/plugin-w/before.xml" s7)" = 0 ] && [ ! -s "$T/err" ]'
mkdir -p "$T/e/e2e/harness/site/webapp/jsp/e2e" "$T/e/webapp/jsp/admin" "$T/e/src/java/x/e2e" && printf '%s\n' "$POM" > "$T/e/pom.xml"
printf '<project><parent><artifactId>lutece-global-pom</artifactId><version>8.0.2</version></parent><artifactId>site-e2e</artifactId><packaging>lutece-site</packaging></project>\n' > "$T/e/e2e/harness/site/pom.xml"
printf '<%%@ page contentType="text/plain" %%><%% out.print("ok"); %%>\n' > "$T/e/e2e/harness/site/webapp/jsp/e2e/probe.jsp"
cp "$T/e/e2e/harness/site/webapp/jsp/e2e/probe.jsp" "$T/e/webapp/jsp/admin/Probe.jsp"
cp "$T/p/src/java/Bad.java" "$T/e/src/java/x/e2e/Bad.java"
check "a test page of the e2e folder is silent" '[ "$(run "$T/e/e2e/harness/site/webapp/jsp/e2e/probe.jsp" s8)" = 0 ] && [ ! -s "$T/err" ] && [ ! -s "$T/out" ]'
check "the same page shipped by the project is handed back" '[ "$(run "$T/e/webapp/jsp/admin/Probe.jsp" s8)" = 2 ] && grep -q "JS02" "$T/err"'
check "a source package named e2e is still checked" '[ "$(run "$T/e/src/java/x/e2e/Bad.java" s8)" = 2 ] && grep -q "JX01" "$T/err"'
if [ $fail = 0 ]; then echo "PASS: verify-edit hands back what an edit adds, notes the debt once, stays silent otherwise"; else exit 1; fi
