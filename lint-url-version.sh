#!/usr/bin/env bash
# lint-url-version.sh — batch API versioning linter.
#
# Enforces: API versions belong in HTTP headers, never in URL path
# segments (/v1/, /v2/) or query parameters (?version=, ?v=).
#
# Usage:
#   lint-url-version.sh [path ...]
# With no arguments, scans the current working directory recursively.
#
# Output: `path:line: <reason>` per violation, then a trailing count.
# Exit 1 if any violation found, else 0.
set -euo pipefail

IGNORE_RE='(^|/)(node_modules|dist|build|generated|\.git|\.wrangler)(/|$)'

ignored() {
  case "$1" in *.lock|*.min.*) return 0 ;; esac
  printf '%s' "$1" | grep -qE "$IGNORE_RE" && return 0
  return 1
}

is_source() {
  case "$1" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) return 0 ;; esac
  return 1
}

OUT="$(mktemp)"
FLIST="$(mktemp)"
trap 'rm -f "$OUT" "$FLIST"' EXIT

collect() {
  if [ -f "$1" ]; then printf '%s\n' "$1"
  elif [ -d "$1" ]; then find "$1" -type f 2>/dev/null
  fi
}

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do collect "$arg"; done
else
  collect "."
fi > "$FLIST"

PATH_RE='/v[0-9]+(/|['"'"'"`?]|$)'
PARAM_RE='[?&](api_version|api-version|apiVersion|version|ver)='
ROUTE_PARAM_RE='(:version|{version}|:api_version|{api_version}|:apiVersion|{apiVersion})'

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  ignored "$f" && continue
  is_source "$(basename "$f")" || continue

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    lineno="${entry%%:*}"
    text="${entry#*:}"
    trimmed="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*//')"
    case "$trimmed" in //*|"*"*|\#*) continue ;; esac
    printf '%s\n' "$text" | grep -qiE 'Accept-Version|X-API-Version|x-version' && continue
    printf '%s:%s: version in URL\n' "$f" "$lineno" >> "$OUT"
  done < <({
    grep -nE "$PATH_RE" "$f" 2>/dev/null || true
    grep -nE "$PARAM_RE" "$f" 2>/dev/null || true
    grep -nE "$ROUTE_PARAM_RE" "$f" 2>/dev/null || true
  } | sort -t: -k1,1n -u)
done < "$FLIST"

count="$(wc -l < "$OUT" | tr -d ' ')"
if [ "$count" -gt 0 ]; then
  cat "$OUT"
  printf '%s violation(s)\n' "$count"
  exit 1
fi
printf '0 violations\n'
exit 0
