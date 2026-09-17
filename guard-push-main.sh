#!/usr/bin/env bash
# guard-push-main.sh
#
# Command guard: block direct `git push` to the default branch (main/master).
# Forces a branch + pull-request workflow.
#
# Contract:
#   - Reads the proposed shell command from $1, or from stdin if no arg.
#   - Exit 0  = allow (command is unrelated, or push targets a non-default branch).
#   - Exit 2  = block, with a one-line reason on stderr.
#
# Self-contained: no sourcing, no imports.
set -euo pipefail

# --- read the proposed command -------------------------------------------
if [ "$#" -ge 1 ]; then
  CMD="$1"
else
  CMD="$(cat)"
fi

[ -z "${CMD//[[:space:]]/}" ] && exit 0

# --- only act on `git push` ----------------------------------------------
# Match `git push` allowing global flags between (e.g. `git -C dir push`).
# Ignore `gh pr merge` (that is a sanctioned merge, not a raw push).
printf '%s' "$CMD" | grep -qiE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' && exit 0
printf '%s' "$CMD" | grep -qE '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push' || exit 0

# --- default-branch names we protect -------------------------------------
DEFAULT_BRANCHES_RE='^(main|master)$'

# --- extract the refspec: 2nd positional token after `push` --------------
# Skips flags (tokens starting with `-`). The first positional is the remote,
# the second is the refspec (local[:remote]).
REFSPEC="$(printf '%s' "$CMD" | awk '
  {
    found = 0; pos = 0
    for (i = 1; i <= NF; i++) {
      if (!found && $i == "push") { found = 1; continue }
      if (found && $i ~ /^-/) continue          # skip flags
      if (found && $i ~ /^[;&|]/) break          # stop at command chaining
      if (found) { pos++; if (pos == 2) { print $i; exit } }
    }
  }')"

# Normalize a refspec to its destination branch (right side of any `:`).
dest_branch_of() {
  local spec="$1"
  case "$spec" in
    *:*) printf '%s' "${spec##*:}" ;;   # src:dst -> dst
    *)   printf '%s' "$spec" ;;
  esac
}

# --- explicit refspec present --------------------------------------------
if [ -n "$REFSPEC" ]; then
  DEST="$(dest_branch_of "$REFSPEC")"
  # Strip a leading refs/heads/ if present.
  DEST="${DEST#refs/heads/}"
  if printf '%s' "$DEST" | grep -qE "$DEFAULT_BRANCHES_RE"; then
    echo "BLOCKED: push targets default branch '$DEST'. Use a feature branch and open a pull request." >&2
    exit 2
  fi
  # Explicit non-default refspec → allow.
  exit 0
fi

# --- no refspec: push inherits the current branch ------------------------
# Determine the current branch from the working tree.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$BRANCH" ] && printf '%s' "$BRANCH" | grep -qE "$DEFAULT_BRANCHES_RE"; then
  echo "BLOCKED: on default branch '$BRANCH' with no refspec. Create a feature branch and push that instead." >&2
  exit 2
fi

exit 0
