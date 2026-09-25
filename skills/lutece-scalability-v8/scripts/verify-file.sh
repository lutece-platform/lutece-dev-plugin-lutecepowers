#!/usr/bin/env bash
# Verify a Java file after a scalability fix. Flags residual anti-patterns.
# Usage: verify-file.sh <file.java>
set -uo pipefail
F="${1:?usage: verify-file.sh <file.java>}"
[ -f "$F" ] || { echo "FAIL: file not found $F"; exit 1; }
issues=0
# Prints a warning with the first matching lines when the file matches the pattern. Args: label, extended regex.
chk(){ if grep -nE "$2" "$F" >/dev/null 2>&1; then echo "  WARN [$1] $F"; grep -nE "$2" "$F" | head -3 | sed 's/^/      /'; issues=$((issues+1)); fi; }

chk "JVM-local lock"        'ReentrantLock|synchronized\s*\(|\.tryLock\('
chk "SELECT MAX id"         'SELECT\s+MAX\(|select\s+max\(|newPrimaryKey'
chk "static singleton"      'private\s+static\s+.*_instance|getInstance\s*\('
case "$F" in *Home.java) ;; *) chk "static CDI.current" 'static.*=\s*CDI\.current\(\)\.select' ;; esac
chk "Future/Timer/Thread"   'ScheduledFuture|java\.util\.Timer|new Thread\('
chk "hardcoded config"      'new File\(\s*"/|"https?://|"jdbc:'
chk "container stream close" 'getOutputStream\(\s*\)\.close|getWriter\(\s*\)\.close'
chk "threadlocal set(null)" 'setLocal\(\s*null|\.set\(\s*null\s*\)'

if [ "$issues" -eq 0 ]; then echo "  OK $F"; else echo "  -> $issues point(s) to review in $F"; fi
exit 0
