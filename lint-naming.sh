#!/usr/bin/env bash
set -euo pipefail
#
# lint-naming.sh — repo-level naming DISTRIBUTION linter.
#
# The naming ladder is: 1 word preferred, 2 if needed, 3 max — and three must
# not be the mode. The first half of that is a per-file ceiling and is already
# owned elsewhere: guard-name-words.sh announces the 3-word rung, and
# guard-morpheme-max.sh / lint-morpheme-max.sh block 4+. This linter exists
# because the second half is not a property of any file. "Three must not be
# the mode" is a statement about a distribution, so it can only be checked
# over a set — which is why no per-file guard can enforce it and why this is
# a separate stage rather than another rung in those scripts.
#
# It scores the files a branch ADDS, not the whole tree. A mature repo carries
# naming debt it did not choose; judging the tree would either deadlock it or
# force a mass rename. Judging added files measures the direction the repo is
# moving, which is the thing the rule is actually about.
#
# The mode is taken over the legal buckets (1, 2, 3). A 4+ name is a blocked
# violation, not a competing bucket, and must not be able to out-count the
# 3-word bucket and thereby hide it.
#
# Usage:
#   lint-naming.sh [base-ref]      # default: $LINT_BASE_REF, else the later of
#                                  # the main / origin/main merge base
#
# Output: the 1/2/3/4+ distribution, then the verdict.
# Exit 1 if 3-word names are strictly the most common bucket, else 0.
# Exit 0 when no base ref resolves or nothing is added — an unmeasurable
# distribution is unknown, never a pass with a hidden failure.

# Universal build-artifact ignore set. Matches anywhere in the path.
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData)(/|$)|\.dSYM/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
git rev-parse --verify HEAD >/dev/null 2>&1 || exit 0

# --- resolve the tightest branch point --------------------------------------
# An explicit ref wins outright. Otherwise both trunk spellings are tried and
# the LATER merge base wins. A local main and an origin/main routinely diverge,
# and taking the older of the two ancestors silently attributes trunk commits
# to this branch -- it then fails the branch over names the branch never chose,
# which is the one way this check could be worse than useless.
explicit="${1:-${LINT_BASE_REF:-}}"
if [ -n "$explicit" ]; then
  candidates="$explicit"
else
  candidates="main origin/main"
fi

base=""
merge_base=""
for candidate in $candidates; do
  git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 || continue
  mb="$(git merge-base HEAD "$candidate" 2>/dev/null || true)"
  [ -n "$mb" ] || continue
  if [ -z "$merge_base" ] || git merge-base --is-ancestor "$merge_base" "$mb"; then
    merge_base="$mb"
    base="$candidate"
  fi
done
[ -n "$merge_base" ] || exit 0

# Merge-base tree vs the INDEX: files already committed on this branch plus
# files staged right now. That is "what this branch adds" at commit time and
# still correct when re-run afterwards in CI.
added="$(git diff --cached --diff-filter=A --name-only "$merge_base" 2>/dev/null || true)"

# --- bucket by word count ---------------------------------------------------
one=0; two=0; three=0; over=0
three_files=""
total=0

while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf '%s\n' "$f" | grep -Eq "$IGNORE" && continue

  b="$(basename "$f")"
  stem="${b%.*}"
  [ -n "$stem" ] || stem="$b"
  separators="$(printf '%s' "$stem" | tr -cd '_-' | wc -c | tr -d ' ')"
  words=$((separators + 1))
  total=$((total + 1))

  case "$words" in
    1) one=$((one + 1)) ;;
    2) two=$((two + 1)) ;;
    3) three=$((three + 1)); three_files="$three_files$f"$'\n' ;;
    *) over=$((over + 1)) ;;
  esac
done <<< "$added"

if [ "$total" -eq 0 ]; then
  echo "naming: no files added vs $base — nothing to measure"
  exit 0
fi

# --- report -----------------------------------------------------------------
echo "naming distribution over $total file(s) added vs $base:"
printf '  1 word    %s\n' "$one"
printf '  2 words   %s\n' "$two"
printf '  3 words   %s\n' "$three"
printf '  4+ words  %s   (blocked by lint-morpheme-max.sh, not counted here)\n' "$over"

if [ "$three" -gt "$one" ] && [ "$three" -gt "$two" ]; then
  echo
  echo "NAME MODE: 3-word names are the most common bucket among added files."
  echo "Rule: one word preferred, two if needed, three max — three must not be the mode."
  echo "Rename these until 1- or 2-word names outnumber them:"
  printf '%s' "$three_files" | sed '/^$/d' | sed 's/^/  /'
  echo "1 violation(s)"
  exit 1
fi

echo "0 violations"
exit 0
