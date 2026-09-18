#!/usr/bin/env bash
# guard-cloudflare-assets.sh
#
# Author-time, blocking, fail-closed guard for a SINGLE file.
#
# Cloudflare Workers Static Assets bill a Workers *request* whenever the
# Worker runs first (run_worker_first = true). Blanket true turns every
# /js /css /fonts hit into a metered request and has caused real overages.
# Selective path arrays are allowed — they keep HTML/API on the Worker while
# free assets skip it.
#
# Contract:
#   - Takes exactly one argument: the path to the file to inspect.
#   - Exit 0  : clean OR file missing/unreadable.
#   - Exit 2  : violation. Prints "CLOUDFLARE ASSETS RWF BANNED: <path>:<line>"
#               plus a one-line billing reason.
set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  exit 0
fi

REASON="Blanket run_worker_first = true bills every static asset as a Workers request. Use false, or a selective path array so free assets skip the Worker (HTML/API still hit it)."

fail() {
  local line="$1"
  echo "CLOUDFLARE ASSETS RWF BANNED: ${FILE}:${line}"
  echo "$REASON"
  exit 2
}

first_match() {
  local pattern="$1"
  grep -nE "$pattern" "$FILE" 2>/dev/null | head -n 1 | cut -d: -f1 || true
}

# TOML: run_worker_first = true  (not an array)
line="$(first_match '^\s*run_worker_first\s*=\s*true\b')"
[ -n "$line" ] && fail "$line"

# JSON/JSONC: "run_worker_first": true
line="$(first_match '"run_worker_first"\s*:\s*true\b')"
[ -n "$line" ] && fail "$line"

# Clean (false, omitted, or selective arrays like run_worker_first = ["/api/*"]).
exit 0
