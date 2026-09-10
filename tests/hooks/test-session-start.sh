#!/usr/bin/env bash
# Verifies the session-start hook emits the JSON shape each harness consumes,
# that manifests are valid JSON and in sync, that generated files match their sources,
# and that the bootstrap skill and rules index are consistent.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session-start"
FAIL=0
# Prints a passing check.
pass() { echo "  [PASS] $1"; }
# Prints a failing check and counts it.
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export LUTECE_REFERENCES_DIR="$TMP/refs"
export PATH="$TMP/bin:$PATH"; mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/git"; chmod +x "$TMP/bin/git"

# Runs the hook with a clean environment. Args: stdin payload, optional harness argument, then VAR=value pairs.
run_hook() {
  local stdin="$1"; shift
  local args=()
  while [ $# -gt 0 ] && [[ "$1" != *=* ]]; do args+=("$1"); shift; done
  (cd "$TMP" && printf '%s' "$stdin" | env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR -u CURSOR_PROJECT_DIR -u CURSOR_PLUGIN_ROOT -u CLAUDE_ENV_FILE -u PLUGIN_ROOT -u LUTECEPOWERS_HARNESS "$@" bash "$HOOK" "${args[@]}" 2>/dev/null)
}

# Parses hook output and asserts the JSON shape and bootstrap content for one harness. Args: label, shape, output, expected root.
check_shape() {
  local label="$1" shape="$2" out="$3" root="${4:-$ROOT}"
  if printf '%s' "$out" | SHAPE="$shape" ROOT="$root" python3 -c '
import json, os, sys
d = json.load(sys.stdin); shape = os.environ["SHAPE"]
if shape == "nested":
    assert set(d) == {"hookSpecificOutput"}, d.keys()
    assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart"
    ctx = d["hookSpecificOutput"]["additionalContext"]
elif shape == "cursor":
    assert set(d) == {"additional_context", "env"}, d.keys()
    assert d["env"]["LUTECEPOWERS_ROOT"] == os.environ["ROOT"]
    ctx = d["additional_context"]
else:
    assert set(d) == {"additionalContext"}, d.keys()
    ctx = d["additionalContext"]
assert "LUTECEPOWERS_ROOT=" + os.environ["ROOT"] in ctx
assert "# Using Lutecepowers" in ctx and "<EXTREMELY_IMPORTANT>" in ctx
assert "name: using-lutecepowers" not in ctx, "frontmatter leaked"
assert "\r" not in ctx, "CR leaked"
'; then pass "$label"; else fail "$label"; echo "$out" | head -c 400; echo; fi
}

echo "session-start hook"
CLAUDE_IN='{"session_id":"s","cwd":"'"$TMP"'","hook_event_name":"SessionStart","source":"startup"}'
check_shape "Claude Code / Codex: nested hookSpecificOutput" nested "$(run_hook "$CLAUDE_IN" CLAUDE_PLUGIN_ROOT="$ROOT")"
check_shape "Unknown harness defaults to nested shape" nested "$(run_hook "$CLAUDE_IN")"
check_shape "Cursor by env: additional_context + env" cursor "$(run_hook '{}' CURSOR_PROJECT_DIR="$TMP")"
check_shape "Cursor by argument" cursor "$(run_hook '{}' cursor)"
check_shape "OpenCode by argument: nested shape" nested "$(run_hook '' opencode)"

CRLF_PLUGIN="$TMP/crlf-plugin"; mkdir -p "$CRLF_PLUGIN"
cp -r "$ROOT/hooks" "$ROOT/skills" "$ROOT/rules" "$CRLF_PLUGIN/"
sed -i 's/$/\r/' "$CRLF_PLUGIN/skills/using-lutecepowers/SKILL.md"
OUT="$(cd "$TMP" && printf '' | env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_ENV_FILE bash "$CRLF_PLUGIN/hooks/session-start" 2>/dev/null)"
check_shape "CRLF checkout still injects the full body" nested "$OUT" "$CRLF_PLUGIN"
printf '\n\033[1mansi\033[0m \b\f\v\n' >> "$CRLF_PLUGIN/skills/using-lutecepowers/SKILL.md"
OUT="$(cd "$TMP" && printf '' | env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_ENV_FILE bash "$CRLF_PLUGIN/hooks/session-start" 2>/dev/null)"
check_shape "control characters in the skill still yield valid JSON" nested "$OUT" "$CRLF_PLUGIN"
printf '%s' "$(run_hook "$CLAUDE_IN")" | grep -q 'LUTECEPOWERS_ROOT}/rules' && fail "placeholder left unresolved in injected body" || pass "placeholder substituted by the literal root in the injected body"

echo "rules copy"
mkdir -p "$TMP/proj" && echo '<packaging>lutece-plugin</packaging>' > "$TMP/proj/pom.xml"
ENVF="$TMP/env"; : > "$ENVF"
OUT="$(run_hook "$CLAUDE_IN" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$TMP/proj" CLAUDE_ENV_FILE="$ENVF")"
if [ -f "$TMP/proj/.claude/rules/dao-patterns.md" ] && printf '%s' "$OUT" | grep -q "rules copied"; then pass "Claude Code on a Lutece project copies rules into .claude/rules/"; else fail "rules copy on Lutece project"; fi
grep -q "export LUTECEPOWERS_ROOT=\"$ROOT\"" "$ENVF" && pass "CLAUDE_ENV_FILE receives LUTECEPOWERS_ROOT" || fail "CLAUDE_ENV_FILE export"
rm -rf "$TMP/proj/.claude"
run_hook "$CLAUDE_IN" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$TMP/proj" CLAUDE_ENV_FILE="$ENVF" PLUGIN_ROOT="$ROOT" >/dev/null
[ -d "$TMP/proj/.claude" ] && fail "Codex must not copy rules" || pass "Codex (PLUGIN_ROOT set) does not copy rules"
run_hook "$CLAUDE_IN" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$TMP/proj" >/dev/null
[ -f "$TMP/proj/.claude/rules/dao-patterns.md" ] && pass "Claude Code without CLAUDE_ENV_FILE still copies rules" || fail "rules copy must not depend on CLAUDE_ENV_FILE"
echo local-edit > "$TMP/proj/.claude/rules/dao-patterns.md"; touch "$TMP/proj/.claude/rules/dao-patterns.md"
run_hook "$CLAUDE_IN" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$TMP/proj" >/dev/null
grep -q local-edit "$TMP/proj/.claude/rules/dao-patterns.md" && pass "newer local rule copy is preserved" || fail "local rule copy clobbered"
rm -rf "$TMP/proj/.claude"
run_hook '{}' CURSOR_PROJECT_DIR="$TMP/proj" >/dev/null
[ -d "$TMP/proj/.claude" ] && fail "Cursor must not copy rules" || pass "Cursor does not copy rules"

echo "reference sync"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$LUTECE_REFERENCES_DIR/.last-sync" ] && break; sleep 0.3; done
[ -f "$LUTECE_REFERENCES_DIR/.last-sync" ] && pass "sync stamp written after a successful pass" || fail "sync stamp missing"
BEFORE="$(stat -c %Y "$LUTECE_REFERENCES_DIR/.last-sync")"; sleep 1.1
run_hook "$CLAUDE_IN" >/dev/null; sleep 0.5
[ "$(stat -c %Y "$LUTECE_REFERENCES_DIR/.last-sync")" = "$BEFORE" ] && pass "sync throttled within the hour" || fail "sync ran again within the hour"
FAILREFS="$TMP/refs-fail"; printf '#!/bin/sh\nexit 128\n' > "$TMP/bin/git"; LUTECE_REFERENCES_DIR="$FAILREFS" run_hook "$CLAUDE_IN" >/dev/null; sleep 0.5; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/git"
[ -f "$FAILREFS/.last-sync" ] && fail "failed sync must not write the stamp" || pass "failed sync leaves no stamp, next session retries"

echo "manifests"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json .agents/plugins/marketplace.json .cursor-plugin/plugin.json package.json hooks/hooks.json hooks/hooks-cursor.json; do
  python3 -m json.tool "$ROOT/$f" >/dev/null 2>&1 && pass "valid JSON: $f" || fail "invalid JSON: $f"
done
python3 -c 'import json,sys; g=json.load(open(sys.argv[1]))["hooks"]["SessionStart"]; assert sorted(x["matcher"] for x in g)==["clear","compact","startup"]; assert all("|" not in x["matcher"] for x in g)' "$ROOT/hooks/hooks.json" 2>/dev/null && pass "SessionStart uses exact matchers startup/clear/compact" || fail "SessionStart matchers"
grep -q 'eol=lf' "$ROOT/.gitattributes" && ! grep -q 'crlf' "$ROOT/.gitattributes" && pass ".gitattributes forces LF" || fail ".gitattributes"
[ -e "$ROOT/hooks/run-hook.cmd" ] && fail "run-hook.cmd should be gone" || pass "no polyglot wrapper"
python3 -c 'import json,sys; assert "version" not in json.load(open(sys.argv[1]))["plugins"][0]' "$ROOT/.claude-plugin/marketplace.json" 2>/dev/null && pass "marketplace entry carries no duplicate version" || fail "marketplace version duplicated"
bash "$ROOT/scripts/bump-version.sh" --check >/dev/null && pass "versions in sync" || fail "version drift"

echo "opencode plugin"
node --check "$ROOT/.opencode/plugins/lutecepowers.js" 2>/dev/null && pass "OpenCode plugin parses" || fail "OpenCode plugin syntax"
if (cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_ENV_FILE node --input-type=module -e '
const { LutecepowersPlugin } = await import(process.argv[1]);
const p = await LutecepowersPlugin();
const cfg = {}; await p.config(cfg);
if (!cfg.skills.paths[0].endsWith("/skills")) throw new Error("skills path not registered");
const msgs = [{ info: { role: "user" }, parts: [{ id: "p1", sessionID: "s", messageID: "m", type: "text", text: "hi" }] }];
await p["experimental.chat.messages.transform"]({}, { messages: msgs });
await p["experimental.chat.messages.transform"]({}, { messages: msgs });
if (msgs[0].parts.length !== 2) throw new Error("expected exactly one injected part, got " + msgs[0].parts.length);
const b = msgs[0].parts[0];
if (b.id === "p1" || !b.text.includes("LUTECEPOWERS_ROOT=") || !b.text.includes("# Using Lutecepowers")) throw new Error("bad bootstrap part");
' "$ROOT/.opencode/plugins/lutecepowers.js" 2>/dev/null); then pass "OpenCode plugin injects the hook bootstrap once with its own part id"; else fail "OpenCode plugin injection"; fi

echo "skills"
for d in "$ROOT"/skills/*/; do
  n="$(basename "$d")"
  fm="$(sed -n '2,/^---$/p' "$d/SKILL.md")"
  echo "$fm" | grep -q "^name: $n$" && pass "skill name matches directory: $n" || fail "skill name mismatch: $n"
  echo "$fm" | grep -qE "^(user-invocable|argument-hint|allowed-tools|paths|context|hooks):" && fail "non-portable frontmatter in $n" || true
  [ "$n" = "using-lutecepowers" ] && continue
  grep -q "^| \`$n\` |" "$ROOT/skills/using-lutecepowers/SKILL.md" && pass "skill listed in bootstrap: $n" || fail "skill missing from bootstrap: $n"
done
[ "$(grep -c '^| `lutece' "$ROOT/skills/using-lutecepowers/SKILL.md")" = "$(grep '^| `lutece' "$ROOT/skills/using-lutecepowers/SKILL.md" | sort -u | wc -l)" ] && pass "no duplicate rows in bootstrap tables" || fail "duplicate rows in bootstrap tables"
[ "$(grep -c '^| `lutece' "$ROOT/README.md")" = "$(grep '^| `lutece' "$ROOT/README.md" | sort -u | wc -l)" ] && pass "no duplicate rows in README tables" || fail "duplicate rows in README tables"
sed -n '2,/^---$/p' "$ROOT/agents/lutece-v8-reviewer.md" | grep -q "^name: lutece-v8-reviewer$" && pass "agent name is lutece-v8-reviewer" || fail "agent name"
grep -rn 'CLAUDE_PLUGIN_ROOT' "$ROOT/skills" "$ROOT/agents" | grep -v 'CLAUDE_PLUGIN_ROOT:-' | grep -q . && fail "CLAUDE_PLUGIN_ROOT still referenced in skills/agents" || pass "skills/agents use LUTECEPOWERS_ROOT only"

echo "rules"
for f in "$ROOT"/rules/*.md; do
  n="$(basename "$f" .md)"
  grep -q "^| \`$n\` |" "$ROOT/skills/using-lutecepowers/SKILL.md" && pass "rule listed in bootstrap: $n" || fail "rule missing from bootstrap: $n"
done
GEN="$TMP/gen"; mkdir -p "$GEN/rules" "$GEN/scripts"; cp "$ROOT"/rules/*.md "$GEN/rules/"; cp "$ROOT/scripts/build-cursor-rules.sh" "$GEN/scripts/"
bash "$GEN/scripts/build-cursor-rules.sh" >/dev/null 2>&1
diff -rq "$GEN/rules-cursor" "$ROOT/rules-cursor" >/dev/null 2>&1 && pass "rules-cursor/ matches rules/ (regenerated)" || fail "rules-cursor/ out of date: run scripts/build-cursor-rules.sh"
mkdir -p "$GEN/skills/using-lutecepowers"; cp -r "$ROOT"/skills/* "$GEN/skills/"; cp "$ROOT/README.md" "$GEN/"; cp "$ROOT/scripts/build-tables.sh" "$GEN/scripts/"
bash "$GEN/scripts/build-tables.sh" >/dev/null 2>&1
diff -q "$GEN/README.md" "$ROOT/README.md" >/dev/null && diff -q "$GEN/skills/using-lutecepowers/SKILL.md" "$ROOT/skills/using-lutecepowers/SKILL.md" >/dev/null && pass "skills/rules tables match frontmatter (regenerated)" || fail "tables out of date: run scripts/build-tables.sh"

[ "$FAIL" -gt 0 ] && { echo "STATUS: FAILED ($FAIL)"; exit 1; }
echo "STATUS: PASSED"
