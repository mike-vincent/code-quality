#!/usr/bin/env bash
# guard-cloudflare-kv.sh
#
# Author-time, blocking, fail-closed guard for a SINGLE file.
#
# Cloudflare Workers KV is banned as a universal engineering standard:
#   - Writes are expensive ($5 per million writes).
#   - Runaway write paths have caused real billing leaks.
#
# This guard refuses any change that introduces a KV namespace binding or
# uses the KV runtime API. There are no allowlists and no per-file carve-outs:
# the ban is universal. Use Postgres, R2, D1, Durable Objects, or a cache
# layer instead of KV.
#
# Contract:
#   - Takes exactly one argument: the path to the file to inspect.
#   - Exit 0  : clean (no KV usage) OR file missing/unreadable.
#   - Exit 2  : violation. Prints "CLOUDFLARE KV BANNED: <path>:<line>"
#               plus a one-line cost/billing reason.
set -euo pipefail

FILE="${1:-}"

# No argument, missing file, or unreadable file: nothing to inspect.
if [ -z "$FILE" ] || [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  exit 0
fi

REASON="Cloudflare KV is banned: writes cost ~\$5/1M and have caused billing leaks. Use Postgres, R2, D1, Durable Objects, or a cache layer instead."

# ---------------------------------------------------------------------------
# Detection patterns.
#
# We classify the file loosely to choose the right detectors. Config files
# (wrangler.toml / wrangler.jsonc / wrangler.json) declare KV bindings.
# Source files use the KV runtime API and types.
# ---------------------------------------------------------------------------

base="$(basename "$FILE")"
violation_line=""

# Print a violation and exit fail-closed.
fail() {
  local line="$1"
  echo "CLOUDFLARE KV BANNED: ${FILE}:${line}"
  echo "$REASON"
  exit 2
}

# Return the first matching line number for an extended regex, or empty.
first_match() {
  local pattern="$1"
  grep -nE "$pattern" "$FILE" 2>/dev/null | head -n 1 | cut -d: -f1 || true
}

# --- Config-binding detectors (wrangler.toml / .jsonc / .json) -------------
case "$base" in
  wrangler.toml|wrangler.jsonc|wrangler.json)
    # TOML table or array-of-tables binding:
    #   [[kv_namespaces]]
    #   [[env.production.kv_namespaces]]
    line="$(first_match '^\s*\[\[?\s*(env\.[^]]+\.)?kv_namespaces\s*\]\]?')"
    [ -n "$line" ] && fail "$line"

    # JSON/JSONC binding key:  "kv_namespaces": [ ... ]
    line="$(first_match '"kv_namespaces"\s*:')"
    [ -n "$line" ] && fail "$line"
    ;;
esac

# A binding can appear in any config file regardless of name; catch the
# canonical TOML and JSON forms anywhere.
line="$(first_match '^\s*\[\[?\s*(env\.[^]]+\.)?kv_namespaces\s*\]\]?')"
[ -n "$line" ] && fail "$line"
line="$(first_match '"kv_namespaces"\s*:')"
[ -n "$line" ] && fail "$line"

# --- Runtime API + type + provisioning detectors --------------------------

# KVNamespace type reference (TS bindings / Env interface).
line="$(first_match '\bKVNamespace\b')"
[ -n "$line" ] && fail "$line"

# Wrangler / API provisioning verbs for KV namespaces.
#   kv_namespace_create, kv_namespace_delete, kv_namespaces_list, etc.
#   `wrangler kv:namespace create`, `wrangler kv namespace ...`
line="$(first_match 'kv_namespace[s]?(_(create|delete|list|get|update|rename))?')"
[ -n "$line" ] && fail "$line"
line="$(first_match 'wrangler[[:space:]]+kv([:[:space:]])')"
[ -n "$line" ] && fail "$line"

# KV runtime API: a .get/.put/.list/.delete/.getWithMetadata call on a
# binding whose identifier looks like KV (e.g. env.MY_KV.get(...),
# KV_NAMESPACE.put(...), someKvStore.delete(...)). Case-insensitive match
# on the binding name containing "kv".
line="$(grep -niE '\b[A-Za-z_][A-Za-z0-9_.]*kv[A-Za-z0-9_.]*\.(get|put|list|delete|getWithMetadata)\s*\(' "$FILE" 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
[ -n "$line" ] && fail "$line"

# Explicit env.<BINDING>.<kvMethod> where the property chain references a
# namespace via getWithMetadata (KV-exclusive method) regardless of naming.
line="$(first_match '\.getWithMetadata\s*\(')"
[ -n "$line" ] && fail "$line"

# Clean.
exit 0
