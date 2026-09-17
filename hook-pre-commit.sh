#!/usr/bin/env bash
# hook-pre-commit.sh -- commit-time gate (blocking, diff-aware).
#
# Blocks drift: rules are checked against staged ADDED lines, every touched
# file for the morpheme ceiling, and files that CROSS the 300-line limit in
# this commit. Pre-existing untouched violations in mature repos do not
# deadlock commits. Touched files are held to the current standard.
#
# Husky-compatible: a repo's .husky/pre-commit calls this with the
# absolute path to this directory. Subprocess calls only; nothing sourced.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData)(/|$)|\.dSYM/|package-lock\.json$|\.lock$|\.min\.[^/]*$'
TEXT='\.(ts|tsx|js|jsx|mjs|cjs|css|html|svg|astro|svelte|ya?ml|toml|json)$'
LINE_CHECKS=(lint-banned-words lint-important-css lint-token-required)

rc=0
fail() { echo "[code-quality] $1" >&2; rc=1; }

# The naming ladder, per added file: 1 word preferred, 2 if needed, 3 max.
# guard-name-words.sh only ever advises -- 4+ is blocked by the morpheme
# ceiling below, which owns it. An advisory exits 0 with text on stderr, so it
# is echoed rather than dropped.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "$f" | grep -qE "$IGNORE" && continue
  if ! out="$("$HERE/guard-name-words.sh" "$f" 2>&1)"; then
    fail "$out"
  elif [ -n "$out" ]; then
    echo "[code-quality] $out" >&2
  fi
done < <(git diff --cached --name-only --diff-filter=A 2>/dev/null || true)

# Content rules: staged added/copied/modified text files.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  echo "$f" | grep -qE "$IGNORE" && continue
  # Skip binary files (images, fonts, etc.) -- they have no "lines".
  grep -Iq . "$f" 2>/dev/null || continue

  # Morpheme drift: any staged touched file must be clean now, including
  # edited legacy files and config keys.
  if ! out="$("$HERE/guard-morpheme-max.sh" "$f" 2>&1)"; then fail "$out"; fi

  # max-lines: block only if this commit pushes the file across 300.
  n=$(wc -l < "$f" | tr -d ' ')
  if [ "${n:-0}" -gt 300 ]; then
    prev=$( { git show "HEAD:$f" 2>/dev/null || true; } | wc -l | tr -d ' ')
    [ -z "$prev" ] && prev=0
    [ "$prev" -le 300 ] && fail "$f: $n lines (crossed the 300 limit in this commit)"
  fi

  echo "$f" | grep -qE "$TEXT" || continue

  # Added lines only -> temp file with the same extension so extension
  # filters in the line checks still apply.
  td="$(mktemp -d)"; ext="${f##*.}"; tmp="$td/added.$ext"
  git diff --cached -U0 -- "$f" 2>/dev/null | grep '^+' | grep -v '^+++' | sed 's/^+//' > "$tmp" || true
  if [ -s "$tmp" ]; then
    for chk in "${LINE_CHECKS[@]}"; do
      if ! out="$("$HERE/$chk.sh" "$tmp" 2>&1)"; then
        fail "$f: new $(echo "$chk" | sed 's/^lint-//') violation in added lines"
      fi
    done
  fi
  rm -rf "$td"
done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

# Repo-level: three words is the ceiling, so it must not also be the habit.
# This is the only check here that scores a SET rather than a file, because
# "three must not be the mode" is a property of a distribution and no per-file
# guard can see one. It measures the files this branch adds, so accumulated
# naming debt never blocks a commit that is not adding to it.
if ! out="$("$HERE/lint-naming.sh" 2>&1)"; then fail "$out"; fi

[ "$rc" -eq 0 ] || echo "[code-quality] commit blocked -- fix the NEW violations above and re-stage." >&2
exit "$rc"
