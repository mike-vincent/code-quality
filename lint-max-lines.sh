#!/usr/bin/env bash
# lint-max-lines.sh — batch line-count linter.
#
# Enforces a universal 300-line ceiling across many files. Intended to run in
# CI or on demand over a whole tree.
#
# Contract:
#   Args (optional) = explicit file/dir paths to check.
#   No args         = scan the current working directory.
#   Prints "path: <n> lines (limit 300)" for each file over the ceiling,
#   then a trailing count line.
#   exit 1 if any file exceeds the ceiling, else exit 0.
#
# The ceiling is universal: no per-file or per-project allowlist. Only
# generated build artifacts are ignored.
set -euo pipefail

MAX=300

# Universal build-artifact ignore set. Matches anywhere in the path.
# Directories: node_modules, dist, .git, .wrangler, generated, build,
# .build, target, target-linux, .swiftpm, DerivedData.
# Files: *.lock, package-lock.json, *.min.* (minified bundles).
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData)(/|$)|\.dSYM/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

violations=0

check_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -r "$f" ] || return 0

  # Ignored build artifact.
  if printf '%s\n' "$f" | grep -Eq "$IGNORE"; then
    return 0
  fi

  # Skip binary files (non-empty files with no text content).
  if [ -s "$f" ] && ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
    return 0
  fi

  local lines
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -gt "$MAX" ]; then
    echo "$f: $lines lines (limit $MAX)"
    violations=$((violations + 1))
  fi
}

# Build the list of candidate files.
find_files() {
  find "$1" \
    \( -name node_modules -o -name dist -o -name .git -o -name .wrangler -o -name generated \
       -o -name build -o -name .build -o -name target -o -name target-linux \
       -o -name .swiftpm -o -name DerivedData -o -name "*.dSYM" \) -type d -prune \
    -o -type f -print
}

list_files() {
  if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
      if [ -d "$arg" ]; then
        find_files "$arg"
      elif [ -e "$arg" ]; then
        printf '%s\n' "$arg"
      fi
    done
  else
    find_files "."
  fi
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_file "$f"
done < <(list_files "$@" | sort -u)

if [ "$violations" -gt 0 ]; then
  echo "$violations file(s) over the $MAX-line limit"
  exit 1
fi

echo "0 files over the $MAX-line limit"
exit 0
