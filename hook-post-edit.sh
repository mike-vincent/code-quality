#!/usr/bin/env bash
# hook-post-edit.sh -- PostToolUse / afterFileEdit dispatcher (advisory).
#
# Runs the batch lint-*.sh checks against the single file that was just
# edited and prints any findings. Always exits 0 -- this stage detects and
# advises; commit-time and merge-time stages block. Subprocess calls only;
# nothing is sourced.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINTS=(lint-banned-words lint-morpheme-max lint-max-lines lint-token-required lint-important-css lint-dead-imports lint-url-version)

envelope="$(cat 2>/dev/null || true)"
[ -n "$envelope" ] || exit 0

command -v jq >/dev/null 2>&1 || {
  echo "[code-quality] jq is required for PostToolUse guard parsing" >&2
  exit 2
}
file="$(printf '%s' "$envelope" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

[ -n "${file:-}" ] && [ -f "$file" ] || exit 0

found=""
for l in "${LINTS[@]}"; do
  [ -x "$HERE/$l.sh" ] || continue
  out="$("$HERE/$l.sh" "$file" 2>&1)" || found+="$out"$'\n'
done

[ -n "$found" ] && printf '[code-quality] advisory findings:\n%s' "$found" >&2
exit 0
