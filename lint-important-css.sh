#!/usr/bin/env bash
# lint-important-css.sh — batch linter banning `!important`.
#
# Enforces the universal rule: `!important` is banned in style code. Win
# specificity battles with proper selector specificity / cascade layers, not
# by escalating to `!important`. Applies to dedicated stylesheets and to style
# strings embedded in TS/JS (inline styles, template literals, CSS-in-JS).
#
# Contract:
#   Args (optional) = explicit file/dir paths to check.
#   No args         = scan the current working directory.
#   Prints `path:line: !important banned` per hit, then a trailing count line.
#   exit 1 if any hit, else exit 0.
#
# The rule is structural: no per-file or per-project allowlist.
set -euo pipefail

# Universal build-artifact ignore set. Matches anywhere in the path.
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build)/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

# File extensions that can carry style declarations.
case_ext() {
  case "$1" in
    *.css|*.scss|*.sass|*.less|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) return 0 ;;
    *) return 1 ;;
  esac
}

violations=0

check_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -r "$f" ] || return 0
  case_ext "$f" || return 0

  # Ignored build artifact.
  if printf '%s\n' "$f" | grep -Eq "$IGNORE"; then
    return 0
  fi

  # Skip binary files (non-empty files with no text content).
  if [ -s "$f" ] && ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
    return 0
  fi

  local entry lineno
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    lineno="${entry%%:*}"
    echo "$f:$lineno: !important banned"
    violations=$((violations + 1))
  done < <(grep -nE '!important' "$f" 2>/dev/null || true)
}

# Build the list of candidate files.
list_files() {
  if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
      if [ -d "$arg" ]; then
        find "$arg" -type f
      elif [ -e "$arg" ]; then
        printf '%s\n' "$arg"
      fi
    done
  else
    find . -type f
  fi
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_file "$f"
done < <(list_files "$@" | sort -u)

if [ "$violations" -gt 0 ]; then
  echo "$violations !important violation(s)"
  exit 1
fi

echo "0 !important violations"
exit 0
