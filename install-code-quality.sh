#!/usr/bin/env bash
# install-code-quality.sh -- wire this universal standard into a repo.
#
# Usage: install-code-quality.sh [target-repo-dir]   (default: cwd)
#
# Wires the one universal commit-time gate (git pre-commit -> this dir's
# hook-pre-commit.sh) and prints the snippets for the author-time and
# edit-time stages, which live in the agent's settings rather than the
# repo. Idempotent. No per-repo config is created -- the standard lives
# here, the repo only references it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "${1:-$PWD}" && pwd)"

[ -d "$TARGET/.git" ] || { echo "Not a git repo: $TARGET" >&2; exit 1; }

# --- commit-time: git pre-commit hook -----------------------------------
if [ -f "$TARGET/.husky/pre-commit" ] || [ -d "$TARGET/.husky" ]; then
  mkdir -p "$TARGET/.husky"
  hook="$TARGET/.husky/pre-commit"
else
  hook="$TARGET/.git/hooks/pre-commit"
fi

line="\"$HERE/hook-pre-commit.sh\""
if [ -f "$hook" ] && grep -qF "hook-pre-commit.sh" "$hook"; then
  echo "pre-commit already wired: $hook"
else
  { [ -f "$hook" ] && cat "$hook" || printf '#!/usr/bin/env sh\n'; echo "$line"; } > "$hook.tmp"
  mv "$hook.tmp" "$hook"
  chmod +x "$hook"
  echo "wired pre-commit -> $hook"
fi

# --- author-time + edit-time: agent settings snippets -------------------
cat <<SNIP

Add these to the agent settings to gain author-time (blocking) and
edit-time (advisory) enforcement. The commit-time gate above is already
wired.

Claude Code (~/.claude/settings.json):
  "hooks": {
    "PreToolUse":  [{ "matcher": "Edit|Write|Bash",
                      "hooks": [{ "type": "command", "command": "$HERE/hook-pre-tool.sh" }] }],
    "PostToolUse": [{ "matcher": "Edit|Write",
                      "hooks": [{ "type": "command", "command": "$HERE/hook-post-edit.sh" }] }]
  }

Cursor (.cursor/hooks.json): point afterFileEdit at hook-post-edit.sh and
beforeShellExecution / beforeReadFile at hook-pre-tool.sh.

CI: run "$HERE"/lint-*.sh over the working tree.
SNIP
