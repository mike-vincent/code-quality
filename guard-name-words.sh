#!/usr/bin/env bash
set -euo pipefail
#
# guard-name-words.sh — author/commit-time naming ladder (advisory half).
#
# A basename is counted in WORDS: the stem split on `-` and `_`. So `book.rs`
# is 1 word, `book-state.rs` is 2, `guard-name-words.sh` is 3. Dots are
# extension syntax (`foo.test.ts`), not word separators.
#
# The standard is a ladder, not a single limit:
#
#   1 word   preferred — `book.rs`, never `book-state.rs` / `book_state.rs`.
#   2 words  fine when one word genuinely will not carry the meaning.
#   3 words  the ceiling: legal, but announced, because it must not become the
#            default spelling of every file.
#   4+ words blocked — by guard-morpheme-max.sh, which OWNS that ceiling for
#            both this ladder and the identifier rules. This script does not
#            re-implement the block: one rule, one owner.
#
# Consequently this script never exits 2. It is the advisory half of the pair,
# and it is deliberately per-file only. Whether 3 words has BECOME the default
# is a property of a distribution, which no per-file guard can observe —
# lint-naming.sh measures the mode across the files a branch adds and fails
# when 3 is the most common bucket.
#
# Checks ONE file (passed as $1).
# Exit 0 always. A 3-word basename prints an advisory on stderr first.

MAX=3   # the ceiling this ladder announces; guard-morpheme-max.sh enforces it

# Universal build-artifact ignore set. Matches anywhere in the path.
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData)(/|$)|\.dSYM/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

file="${1:-}"
[ -n "$file" ] || exit 0

if printf '%s\n' "$file" | grep -Eq "$IGNORE"; then
  exit 0
fi

base="$(basename "$file")"
stem="${base%.*}"          # strip one extension: book-state.rs -> book-state
[ -n "$stem" ] || stem="$base"

separators="$(printf '%s' "$stem" | tr -cd '_-' | wc -c | tr -d ' ')"
words=$((separators + 1))

if [ "$words" -eq "$MAX" ]; then
  printf 'NAME WORDS: "%s" is %d words — the ceiling, not the default.\n' "$base" "$words" >&2
  printf 'Rule: one word preferred, two if needed, three max — and three must not be the mode.\n' >&2
fi

exit 0
