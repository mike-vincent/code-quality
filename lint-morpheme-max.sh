#!/usr/bin/env bash
set -euo pipefail
#
# lint-morpheme-max.sh — batch naming-convention linter.
#
# Enforces, across many files:
#   1. File basename words: at most 3, a word being the stem split on `-` or
#      `_`. The batch twin of guard-morpheme-max.sh, which owns the 4-word
#      block for the naming ladder (1 preferred / 2 if needed / 3 max).
#   2. Exported function / identifier names: at most 2 capital letters
#      (camelCase humps) — applies only to recognized source files.
#
# Whether 3 words has become the MODE is a separate question this linter
# cannot answer, because it scores files one at a time against a ceiling.
# lint-naming.sh answers it over the files a branch adds.
#
# Universal: no per-file allowlists, no exemptions. A violation is a
# violation everywhere. The only thing skipped is a universal ignore set of
# generated/vendored artifacts.
#
# Usage:
#   lint-morpheme-max.sh [path ...]
# With no arguments, scans the current working directory recursively.
#
# Output: `path: <reason>` per violation, then a trailing count.
# Exit 1 if any violation found, else 0.

MAX_WORDS=3
MAX_CAPS=2

OUT="$(mktemp)"
FLIST="$(mktemp)"
trap 'rm -f "$OUT" "$FLIST"' EXIT

# --- Universal ignore set ---------------------------------------------------
# Path-segment names and file globs skipped everywhere. No project specifics.
IGNORE_DIRS_RE='(^|/)(node_modules|dist|build|\.build|target|target-linux|generated|\.git|\.wrangler|\.swiftpm|DerivedData)(/|$)|\.dSYM/'
ignored_file() {
  case "$1" in
    *.lock) return 0 ;;
    *.min.*) return 0 ;;
  esac
  printf '%s' "$1" | grep -qE "$IGNORE_DIRS_RE" && return 0
  return 1
}

# --- Build candidate file list ---------------------------------------------
collect() {
  local target="$1"
  if [ -f "$target" ]; then
    printf '%s\n' "$target"
  elif [ -d "$target" ]; then
    find "$target" \
      \( -name node_modules -o -name dist -o -name .git -o -name .wrangler -o -name generated \
         -o -name build -o -name .build -o -name target -o -name target-linux \
         -o -name .swiftpm -o -name DerivedData -o -name "*.dSYM" \) -type d -prune \
      -o -type f -print 2>/dev/null
  fi
}

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    collect "$arg"
  done
else
  collect "."
fi > "$FLIST"

# --- Helpers ----------------------------------------------------------------
is_source_file() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) return 0 ;;
    *) return 1 ;;
  esac
}

is_config_file() {
  case "$1" in
    *.yaml|*.yml|*.toml|*.json) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Scan -------------------------------------------------------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  ignored_file "$f" && continue

  base="$(basename "$f")"

  # 1. File basename word count. Words are the stem split on `-` or `_`.
  stem="${base%.*}"
  [ -n "$stem" ] || stem="$base"
  separators="$(printf '%s' "$stem" | tr -cd '_-' | wc -c | tr -d ' ')"
  words=$((separators + 1))
  if [ "$words" -gt "$MAX_WORDS" ]; then
    printf '%s: %s words in file name (max %s)\n' "$f" "$words" "$MAX_WORDS" >> "$OUT"
  fi

  # 2. Exported identifier capital count (source files only).
  if is_source_file "$base"; then
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      lineno="${match%%:*}"
      rest="${match#*:}"
      name="$(printf '%s' "$rest" \
        | sed -E 's/^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function[*[:space:]]+//' \
        | sed -E 's/[<(].*$//' \
        | tr -d '[:space:]')"
      [ -n "$name" ] || continue
      caps="$(printf '%s' "$name" | tr -cd 'A-Z' | wc -c | tr -d ' ')"
      if [ "$caps" -gt "$MAX_CAPS" ]; then
        printf '%s: exported name %s has %s capital letters (max %s) on line %s\n' \
          "$f" "$name" "$caps" "$MAX_CAPS" "$lineno" >> "$OUT"
      fi
    done < <(grep -nE '^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function' "$f" 2>/dev/null || true)
  fi

  if is_config_file "$base"; then
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      lineno="${match%%:*}"
      rest="${match#*:}"
      key="$(printf '%s' "$rest" | sed -E 's/^[+[:space:]]*"?(--)?([A-Za-z][A-Za-z0-9_-]*).*/\2/')"
      [ -n "$key" ] || continue
      caps="$(printf '%s' "$key" | tr -cd 'A-Z' | wc -c | tr -d ' ')"
      if [ "$caps" -gt "$MAX_CAPS" ]; then
        printf '%s: config key %s has %s capital letters (max %s) on line %s\n' \
          "$f" "$key" "$caps" "$MAX_CAPS" "$lineno" >> "$OUT"
      fi
    done < <(grep -nE '^[+[:space:]]*"?[A-Za-z][A-Za-z0-9_-]*"?[[:space:]]*[:=]' "$f" 2>/dev/null || true)
  fi
done < "$FLIST"

count="$(wc -l < "$OUT" | tr -d ' ')"
if [ "$count" -gt 0 ]; then
  cat "$OUT"
  printf '%s violation(s)\n' "$count"
  exit 1
fi
printf '0 violations\n'
exit 0
