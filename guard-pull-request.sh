#!/usr/bin/env bash
# guard-pull-request.sh
#
# Command guard: when a `gh pr create` is proposed, require that the PR body
# carries acceptance criteria — at least one Markdown task-list checkbox
# (`- [ ]` or `- [x]`). This enforces that every pull request states, in
# falsifiable form, what "done" means.
#
# Contract:
#   - Reads the proposed shell command from $1, or from stdin if no arg.
#   - Exit 0  = allow (not a PR-create, or body has >= 1 AC checkbox).
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

# --- only act on a PR write ----------------------------------------------
# Matches `gh pr create` and `gh pr edit` when a body is being set.
is_pr_write() {
  printf '%s' "$CMD" | grep -qiE '(^|[;&|]|[[:space:]])gh[[:space:]]+pr[[:space:]]+create' && return 0
  if printf '%s' "$CMD" | grep -qiE '(^|[;&|]|[[:space:]])gh[[:space:]]+pr[[:space:]]+edit'; then
    printf '%s' "$CMD" | grep -qE -- '(--body|--body-file|(^|[[:space:]])-[bF]([[:space:]]|=))' && return 0
  fi
  return 1
}
is_pr_write || exit 0

# A checkbox anywhere in the supplied body satisfies the rule.
# Leading '-' is passed to grep via -e so it is not parsed as an option.
CHECKBOX_RE='-[[:space:]]\[[ xX]\]'

# --- gather the PR body text from the command ----------------------------
# `gh pr create` can supply the body several ways; we inspect each.
BODY=""

# 1. --body / -b "<text>" or --body=<text>
#    Pull the value out of the command string. Handles single/double quotes.
extract_flag_value() {
  # $1 = command, $2 = long flag (e.g. body), $3 = short flag (e.g. b)
  printf '%s' "$1" | perl -0777 -ne '
    my ($cmd, $long, $short) = ($_, "'"$2"'", "'"$3"'");
    while ($cmd =~ /--\Q$long\E(?:=|\s+)("([^"]*)"|'"'"'([^'"'"']*)'"'"'|(\S+))/g) {
      print(defined $2 ? $2 : defined $3 ? $3 : $4, "\n");
    }
    while ($short ne "" && $cmd =~ /(?<![-\w])-\Q$short\E(?:=|\s+)("([^"]*)"|'"'"'([^'"'"']*)'"'"'|(\S+))/g) {
      print(defined $2 ? $2 : defined $3 ? $3 : $4, "\n");
    }
  ' 2>/dev/null || true
}

INLINE_BODY="$(extract_flag_value "$CMD" "body" "b" || true)"
[ -n "$INLINE_BODY" ] && BODY+="$INLINE_BODY"$'\n'

# 2. --body-file <path>  (including `-` for stdin / heredoc — can't read it,
#    so treat presence as "body is supplied elsewhere": fall through to file).
BODY_FILE="$(extract_flag_value "$CMD" "body-file" "F" || true)"
if [ -n "$BODY_FILE" ]; then
  # `-` means the body is piped in (heredoc / pipe). We cannot see it from the
  # command text alone, so allow rather than false-block.
  if [ "$BODY_FILE" = "-" ]; then
    exit 0
  fi
  if [ -f "$BODY_FILE" ]; then
    BODY+="$(cat "$BODY_FILE" 2>/dev/null || true)"$'\n'
  else
    # Referenced file not readable from here → cannot verify; allow.
    exit 0
  fi
fi

# 3. --fill / --fill-first / --web / --template / --editor:
#    body comes from commits, an interactive editor, or a template we can't
#    see here. Don't false-block these flows.
if printf '%s' "$CMD" | grep -qiE '(^|[[:space:]])--(fill|fill-first|web|editor)([[:space:]]|=|$)'; then
  exit 0
fi
if printf '%s' "$CMD" | grep -qiE '(^|[[:space:]])(--template|-T)([[:space:]]|=)'; then
  exit 0
fi

# --- no inspectable body at all → require an explicit one ----------------
if [ -z "${BODY//[[:space:]]/}" ]; then
  echo "BLOCKED: this PR write has no inspectable body. Provide --body/--body-file containing acceptance-criteria checkboxes ('- [ ] ...')." >&2
  exit 2
fi

# --- enforce: at least one acceptance-criteria checkbox ------------------
if printf '%s' "$BODY" | grep -qE -e "$CHECKBOX_RE"; then
  exit 0
fi

echo "BLOCKED: PR body has no acceptance-criteria checkbox. Add at least one '- [ ]' / '- [x]' item describing how 'done' is verified." >&2
exit 2
