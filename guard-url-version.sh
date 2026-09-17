#!/usr/bin/env bash
# guard-url-version.sh — author-time, blocking API versioning guard.
#
# Enforces the universal rule: API versions belong in HTTP headers
# (Accept-Version, X-API-Version, etc.), never in URL path segments
# (/v1/, /v2/) or query parameters (?version=, ?v=, &api_version=).
#
# Contract:
#   $1 = path to one file.
#   exit 0  if the file is clean, missing/unreadable, binary, or ignored.
#   exit 2  if a version-in-URL pattern is found (blocking). Prints
#           `VERSION IN URL: <path>:<line>` per hit plus a rule reminder.
#
# The rule is universal: no per-file or per-project allowlist.
set -euo pipefail

IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build)/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

path="${1:-}"
[ -z "$path" ] && exit 0

case "$path" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac

if printf '%s\n' "$path" | grep -Eq "$IGNORE"; then
  exit 0
fi

[ -f "$path" ] || exit 0
[ -r "$path" ] || exit 0

if [ -s "$path" ] && ! LC_ALL=C grep -Iq . "$path" 2>/dev/null; then
  exit 0
fi

# --- Patterns ---------------------------------------------------------------
# 1. Path-segment version: /v1, /v2, /v3 etc. in route definitions or URLs.
#    Matches /v followed by one or more digits then a segment boundary.
PATH_RE='/v[0-9]+(/|['"'"'"`?]|$)'

# 2. Query-param version: ?version=, &version=, ?api_version=, etc.
#    Bare ?v= is excluded — it is universally used for cache busting on static assets.
PARAM_RE='[?&](api_version|api-version|apiVersion|version|ver)='

# 3. Route-param version: :version or {version} in route definitions.
ROUTE_PARAM_RE='(:version|{version}|:api_version|{api_version}|:apiVersion|{apiVersion})'

found=0
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  lineno="${entry%%:*}"
  text="${entry#*:}"

  # Skip comments (// or * at start of trimmed line).
  trimmed="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*//')"
  case "$trimmed" in
    //*|"*"*|\#*) continue ;;
  esac

  # Skip lines that are clearly header-based versioning (the correct pattern).
  if printf '%s\n' "$text" | grep -qiE 'Accept-Version|X-API-Version|x-version'; then
    continue
  fi

  echo "VERSION IN URL: $path:$lineno" >&2
  found=1
done < <({
  grep -nE "$PATH_RE" "$path" 2>/dev/null || true
  grep -nE "$PARAM_RE" "$path" 2>/dev/null || true
  grep -nE "$ROUTE_PARAM_RE" "$path" 2>/dev/null || true
} | sort -t: -k1,1n -u)

if [ "$found" -eq 1 ]; then
  printf 'Rule: API versions belong in HTTP headers (Accept-Version), never in URL paths (/v1/) or query params (?version=).\n' >&2
  exit 2
fi

exit 0
