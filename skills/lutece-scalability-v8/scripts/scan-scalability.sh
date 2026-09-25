#!/usr/bin/env bash
# Scan a Lutece plugin for multi-instance scalability anti-patterns (6 axes).
# Heuristic: flags points to REVIEW (judgment required), not to fix blindly.
# Usage: scan-scalability.sh [plugin-dir]   (default .)  -> JSON on stdout
set -uo pipefail
ROOT="${1:-.}"
SRC="$ROOT/src/java"
[ -d "$SRC" ] || SRC="$ROOT/src/main/java"
[ -d "$SRC" ] || { echo "{\"error\":\"no java source under $ROOT\"}"; exit 1; }

# Prints the number of Java files matching the pattern.
cnt(){ grep -rIlE "$1" "$SRC" --include=*.java 2>/dev/null | wc -l | tr -d ' '; }
# Prints up to eight matching files as JSON strings, relative to the plugin root.
files(){ grep -rIlE "$1" "$SRC" --include=*.java 2>/dev/null | sed "s#$ROOT/##" | head -8 | awk '{printf "%s\"%s\"", (NR>1?",":""), $0}'; }
# Prints one finding as a JSON object. Args: axis, label, extended regex.
section(){ printf '    {"axis":"%s","label":"%s","count":%s,"files":[%s]}' "$1" "$2" "$(cnt "$3")" "$(files "$3")"; }

art=$(grep -m1 -oE "<artifactId>[^<]+" "$ROOT/pom.xml" 2>/dev/null | sed 's/<artifactId>//')

cat <<JSON
{
  "plugin": "${art:-unknown}",
  "source": "$SRC",
  "findings": [
$(section "1-locks"        "JVM-local locks/concurrency (replace with DB distributed lock)" 'ReentrantLock|synchronized\s*\(|Collections\.synchronized|\.tryLock\(|new ConcurrentHashMap'),
$(section "1-id"           "ID generation via SELECT MAX (concurrency race)" 'SELECT\s+MAX\(|select\s+max\(|newPrimaryKey'),
$(section "3-singleton"    "Mutable static singletons (move to CDI bean, remove getInstance)" 'private\s+static\s+.*_instance|static\s+final\s+\w+\s+\w+\s*=\s*new |getInstance\s*\('),
$(section "3-cdi-static"   "Static CDI init (CDI.current in a field/static, too early)" 'static.*CDI\.current\(\)|=\s*CDI\.current\(\)\.select'),
$(section "2-session"      "HTTP session state (must be Serializable + light)" 'getSession\(\s*\).*setAttribute|HttpSession'),
$(section "2-sessionscoped" "Stateful @SessionScoped/@ConversationScoped CDI beans (whole field graph must be Serializable; REQUIRES Liberty writeContents=GET_AND_SET_ATTRIBUTES to replicate in-place mutations; add a passivation test)" '@SessionScoped|@ConversationScoped'),
$(section "2-nonserial"    "Non-serializable objects in session/cache (Future/Timer/Thread/Stream)" 'ScheduledFuture|java\.util\.Timer|ScheduledExecutorService|Executors\.new|new Thread\('),
$(section "4-cache"        "In-JVM cache/state (distribute via JCache)" 'private\s+static\s+(final\s+)?(Map|HashMap|List|Set)\b|EhCache|CacheManager'),
$(section "5-config"       "Hardcoded config/paths/URLs (externalize via MicroProfile)" 'new File\(\s*"/|"https?://|"jdbc:|System\.getProperty\(|/var/|/tmp/'),
$(section "6-streams"      "Container streams closed by hand (response stream/writer)" 'getOutputStream\(\s*\)\.close|getWriter\(\s*\)\.close|out\.close\(\)'),
$(section "6-threadlocal"  "ThreadLocal not cleaned (set(null) instead of remove())" 'ThreadLocal|setLocal\(\s*null|\.set\(\s*null\s*\)')
  ]
}
JSON
