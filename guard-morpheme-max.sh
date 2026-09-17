#!/usr/bin/env bash
set -euo pipefail
#
# guard-morpheme-max.sh — author-time, blocking naming-convention guard.
#
# Checks ONE file (passed as $1):
#   1. File basename words: at most 3, a word being the stem split on `-` or
#      `_`. This script OWNS the 4-word block for the whole naming ladder
#      (1 word preferred / 2 if needed / 3 max). guard-name-words.sh states
#      that ladder and announces the 3-word rung but never exits 2, so the
#      ceiling has exactly one implementation and one error message.
#   2. Exported function / identifier names: at most 2 capital letters
#      (camelCase humps) — applies only to recognized source files.
#
# Universal: no per-file allowlists, no exemptions. A violation is a
# violation everywhere. Missing/unreadable input exits 0 (nothing to check).
#
# Exit 0 = clean. Exit 2 = violation (reason printed to stderr).

MAX_WORDS=3
MAX_CAPS=2

file="${1:-}"

# Missing or unreadable input is a no-op.
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
[ -r "$file" ] || exit 0

reminder() {
  printf 'Rule: file basenames allow at most %d words (one preferred, two if needed); exported names allow at most %d capital letters.\n' \
    "$MAX_WORDS" "$MAX_CAPS" >&2
}

fail() {
  printf 'MORPHEME LIMIT: %s at %s\n' "$1" "$2" >&2
  reminder
  exit 2
}

# --- 1. File basename word count -------------------------------------------
base="$(basename "$file")"
# Strip a single trailing extension if present (e.g. foo-bar-baz.ts -> foo-bar-baz).
stem="${base%.*}"
[ -n "$stem" ] || stem="$base"

# Words are the stem split on `-` or `_`. Both are word separators in a
# filename; counting only dashes let book_state_view_cache.ts through a rule
# that book-state-view-cache.ts fails, which is the same name twice.
separators="$(printf '%s' "$stem" | tr -cd '_-' | wc -c | tr -d ' ')"
words=$((separators + 1))
if [ "$words" -gt "$MAX_WORDS" ]; then
  fail "$words words in file name (max $MAX_WORDS)" "$file"
fi

# --- 2. Exported identifier capital count ----------------------------------
# Only inspect recognized source files. Extension detection is content-neutral.
case "$base" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) is_source=1 ;;
  *) is_source=0 ;;
esac

if [ "$is_source" -eq 1 ]; then
  # Match exported function declarations, with or without `async`.
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    lineno="${match%%:*}"
    rest="${match#*:}"
    # Extract the identifier following `export [async] function`.
    name="$(printf '%s' "$rest" \
      | sed -E 's/^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function[*[:space:]]+//' \
      | sed -E 's/[<(].*$//' \
      | tr -d '[:space:]')"
    [ -n "$name" ] || continue
    caps="$(printf '%s' "$name" | tr -cd 'A-Z' | wc -c | tr -d ' ')"
    if [ "$caps" -gt "$MAX_CAPS" ]; then
      fail "exported name '$name' has $caps capital letters (max $MAX_CAPS) on line $lineno" "$file"
    fi
  done < <(grep -nE '^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function' "$file" 2>/dev/null || true)
fi

# --- 3. Config key capital count -------------------------------------------
case "$base" in
  *.yaml|*.yml|*.toml|*.json) is_config=1 ;;
  *) is_config=0 ;;
esac

# A CI workflow is a list of environment variables whose names belong to the tools that
# read them (e.g. CI secrets and API tokens). Applying our naming rule there does not
# rename anything; it just makes the file unwritable.
case "$file" in
  */.github/workflows/*) is_config=0 ;;
esac

if [ "$is_config" -eq 1 ]; then
  while IFS= read -r match; do
    [ -n "$match" ] || continue
    lineno="${match%%:*}"
    rest="${match#*:}"
    key="$(printf '%s' "$rest" | sed -E 's/^[+[:space:]]*"?(--)?([A-Za-z][A-Za-z0-9_-]*).*/\2/')"
    [ -n "$key" ] || continue
    # SCREAMING_SNAKE_CASE is the environment-variable convention, and those names belong
    # to whatever reads them (e.g. standard ENV_VAR names).
    case "$key" in
      [A-Z]|[A-Z][A-Z0-9_]*) continue ;;
    esac
    caps="$(printf '%s' "$key" | tr -cd 'A-Z' | wc -c | tr -d ' ')"
    if [ "$caps" -gt "$MAX_CAPS" ]; then
      fail "config key '$key' has $caps capital letters (max $MAX_CAPS) on line $lineno" "$file"
    fi
  done < <(grep -nE '^[+[:space:]]*"?[A-Za-z][A-Za-z0-9_-]*"?[[:space:]]*[:=]' "$file" 2>/dev/null || true)
fi

exit 0
