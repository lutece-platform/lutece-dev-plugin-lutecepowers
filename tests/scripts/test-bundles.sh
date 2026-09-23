#!/usr/bin/env bash
# Checks bundles.py against the java.util.Properties rules: continuation lines, comments, the three separators.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="$HERE/../../skills/lutece-migration-v8-agent-teams/scripts"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf '%s\n' \
  '# comment = not a key' \
  '! other comment' \
  '' \
  'plain=value' \
  'colon:value' \
  'space value after a space' \
  'multi=first part \' \
  '      (0: continued, not a key)' \
  'escaped\=key=value' \
  'even=ends with an escaped backslash \\' \
  'next=after the even line' \
  '   indented = value' \
  'last=three \' \
  '# still the value of last' > "$T/demo_messages.properties"
OUT=$(python3 - "$SCRIPTS" "$T/demo_messages.properties" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from bundles import entries
for n, k, v in entries(sys.argv[2]):
    print("%d|%s|%s" % (n, k, v))
PY
)
EXPECTED='4|plain|value
5|colon|value
6|space|value after a space
7|multi|first part (0: continued, not a key)
9|escaped\=key|value
10|even|ends with an escaped backslash \\
11|next|after the even line
12|indented|value
13|last|three # still the value of last'
if [ "$OUT" = "$EXPECTED" ]; then
  echo "PASS: bundles.py reads bundles as java.util.Properties does"
else
  echo "FAIL: bundles.py"; diff <(echo "$EXPECTED") <(echo "$OUT"); exit 1
fi
