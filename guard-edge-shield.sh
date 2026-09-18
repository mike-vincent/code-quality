#!/usr/bin/env bash
# guard-edge-shield.sh
#
# Author-time, blocking, fail-closed guard for a SINGLE file.
#
# A second Worker on the www/apex hot path that proxies to `app` double-bills
# every request (edge + app). radioindex-edge-shield did this and was removed;
# www/apex must route only to `app`.
#
# Contract:
#   - Takes exactly one argument: the path to the file to inspect.
#   - Exit 0  : clean OR file missing/unreadable.
#   - Exit 2  : violation with a clear front-door / double-bill reason.
set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  exit 0
fi

REASON="Front-door proxy Workers double-bill: every www hit pays the proxy Worker plus app. Route www/apex only to app. Do not reintroduce radioindex-edge-shield, deploy-edge-shield, or a second Worker proxy on the public hot path."

fail() {
  local line="$1" tag="$2"
  echo "${tag}: ${FILE}:${line}"
  echo "$REASON"
  exit 2
}

first_match() {
  local pattern="$1"
  grep -nE "$pattern" "$FILE" 2>/dev/null | head -n 1 | cut -d: -f1 || true
}

# Script / package / path name
line="$(first_match 'radioindex-edge-shield')"
[ -n "$line" ] && fail "$line" "EDGE SHIELD BANNED"

line="$(first_match 'workers/[^[:space:]]*edge-shield')"
[ -n "$line" ] && fail "$line" "EDGE SHIELD BANNED"

line="$(first_match 'deploy:edge-shield|deploy-edge-shield')"
[ -n "$line" ] && fail "$line" "EDGE SHIELD BANNED"

# AGENTS / docs that put a second Worker on www as proxy in front of app
line="$(first_match 'via[[:space:]]+`?radioindex-edge-shield`?|[[:space:]]edge-shield[[:space:]]*->|[[:space:]]edge-shield[[:space:]]+to[[:space:]]+')"
[ -n "$line" ] && fail "$line" "EDGE SHIELD BANNED"

line="$(first_match 'Custom-domain route ownership belongs to the .+edge-shield')"
[ -n "$line" ] && fail "$line" "EDGE SHIELD BANNED"

exit 0
