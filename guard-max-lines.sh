#!/usr/bin/env bash
# guard-max-lines.sh — author-time, blocking line-count guard.
#
# Enforces a universal 300-line ceiling on a single file. Intended to run on
# every edit/save of one file (e.g. an editor hook or pre-edit gate).
#
# Contract:
#   $1 = path to one file.
#   exit 0  if the file has <= 300 lines, is missing/unreadable, or is ignored.
#   exit 2  if the file has > 300 lines (blocking).
#
# The ceiling is universal: no per-file or per-project allowlist. Only
# generated build artifacts are ignored.
set -euo pipefail

MAX=300
# The proactive trigger, 100 lines under the ceiling. See the note beside its check.
TRIGGER="${SPLIT_TRIGGER:-200}"

# Universal build-artifact ignore set. Matches anywhere in the path.
# Directories: node_modules, dist, .git, .wrangler, generated, build,
# .build, target, target-linux, .swiftpm, DerivedData.
# Files: *.lock, package-lock.json, *.min.* (minified bundles).
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData)(/|$)|\.dSYM/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

path="${1:-}"

# No argument → nothing to check.
[ -z "$path" ] && exit 0

# Ignored build artifact → not subject to the ceiling.
if printf '%s\n' "$path" | grep -Eq "$IGNORE"; then
  exit 0
fi

# Missing or unreadable → cannot check, do not block.
[ -f "$path" ] || exit 0
[ -r "$path" ] || exit 0

# Skip binary files (non-empty files with no text content).
if [ -s "$path" ] && ! LC_ALL=C grep -Iq . "$path" 2>/dev/null; then
  exit 0
fi

lines=$(wc -l < "$path" | tr -d ' ')

if [ "$lines" -gt "$MAX" ]; then
  echo "MAX LINES: $path has $lines lines (limit $MAX)" >&2
  echo "Rule: no file may exceed $MAX lines — split it by responsibility before adding more." >&2
  exit 2
fi

# The split trigger, 100 lines below the ceiling.
#
# A hard gate on its own produces boundary oscillation: the author writes, miscounts,
# hits the block, compresses whitespace to claw back two lines, and loops at 300/301
# without ever splitting. The trigger fires while there is still room to act, and the
# 100-line buffer is what pays for the imports and error handling an extraction adds —
# so the split happens deliberately at 200 rather than under duress at 301.
#
# It does NOT block. A file between the trigger and the ceiling is legal; it is simply
# the last comfortable moment to divide it.
if [ "$lines" -gt "$TRIGGER" ]; then
  echo "SPLIT NOW: $path has $lines lines (trigger $TRIGGER, ceiling $MAX)" >&2
  echo "Freeze this file and extract one helper or child component into its own file." >&2
  echo "Doing it here costs one commit; at $MAX it costs a blocked push and a rewrite." >&2
fi

exit 0
