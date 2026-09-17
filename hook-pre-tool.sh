#!/usr/bin/env bash
# hook-pre-tool.sh -- PreToolUse dispatcher (author-time, blocking).
#
# Platform adapter: reads a tool-call envelope on stdin, extracts the file
# path (for edit/write tools) or the command (for shell tools), and runs
# the matching guard-*.sh scripts in this same directory. Guards are run
# as subprocesses -- nothing is sourced or imported.
#
# Contract: exit 0 allows the tool. Exit 2 blocks it; the reason is on
# stderr (shown to the model so it self-corrects before writing).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# File guards run against a single edited file. Command guards inspect a
# proposed shell command. Both groups live flat in HERE.
FILE_GUARDS=(guard-banned-words guard-morpheme-max guard-max-lines guard-function-size guard-direct-style guard-cloudflare-kv guard-url-version)
CMD_GUARDS=(guard-push-main guard-deploy-push guard-pull-request guard-bash-write guard-diff-size)

# Guards that only apply when a file is being CREATED. A name costs nothing to
# change at creation and a rename afterwards, so the naming ladder is asked
# once, here, instead of re-announcing itself on every later edit of the same
# file. At PreToolUse the target is still absent on disk, which is the test.
NEW_FILE_GUARDS=(guard-name-words)

# --- extract fields from the stdin envelope ---------------------------------
envelope="$(cat 2>/dev/null || true)"
[ -n "$envelope" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "[code-quality] jq is required for PreToolUse guard parsing" >&2
  exit 2
}

get() {
  printf '%s' "$envelope" | jq -r "$1 // empty" 2>/dev/null || true
}

tool="$(get '.tool_name')"
file="$(get '.tool_input.file_path // .tool_input.path')"
cmd="$(get '.tool_input.command // .tool_input.cmd')"
new_text="$(get '.tool_input.new_string')"
content="$(get '.tool_input.content')"
patch="$(get 'if (.tool_input|type)=="string" then .tool_input else (.tool_input.patch // .tool_input.input) end')"

case "$tool" in
  functions.exec_command|exec_command) tool="Bash" ;;
  functions.apply_patch|apply_patch) tool="ApplyPatch" ;;
esac

# Self-exclusion: never block edits to the standard's own files. The
# banned-words dictionaries necessarily contain banned words; the rule
# files define the rules. This is the definition site, not a violation.
case "$file" in "$HERE"/*) exit 0 ;; esac

fail=0
report() { echo "[code-quality] $1" >&2; fail=2; }

# Run one guard against $2, reporting it under the real path $3.
#
# Exit 2 blocks and the reason is reported. Exit 0 WITH output is an advisory
# and is passed through rather than discarded -- a non-blocking rung of a
# ladder that nobody ever sees is not a rung.
run_guard() {
  local guard="$1" scan="$2" shown="$3" out
  [ -x "$HERE/$guard.sh" ] || return 0
  if out="$("$HERE/$guard.sh" "$scan" 2>&1)"; then
    [ -n "$out" ] && echo "[code-quality] ${out//$scan/$shown}" >&2
    return 0
  fi
  report "${out//$scan/$shown}"
}

case "$tool" in
  Edit|MultiEdit|NotebookEdit|str_replace*|edit_file)
    # Partial edits: scan only the changed text, under the file's real
    # basename, so untouched pre-existing violations don't block unrelated
    # edits while newly introduced ones still fail. Full-file rewrites fall
    # through to the Write branch below.
    [ -n "$file" ] && [ -f "$file" ] || exit 0
    scan="$file"
    if [ -n "$new_text" ]; then
      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT
      scan="$tmpdir/$(basename "$file")"
      printf '%s' "$new_text" > "$scan"
    fi
    for g in "${FILE_GUARDS[@]}"; do
      run_guard "$g" "$scan" "$file"
    done
    ;;
  Write|create_file)
    # Full-file rewrite: scan the proposed content under the real basename
    # (the on-disk file is still the stale/absent version at PreToolUse).
    [ -n "$file" ] || exit 0
    # Read creation-ness before anything is written: at PreToolUse the target
    # is still the pre-write state, so an absent file is a new file.
    is_new=0
    [ -f "$file" ] || is_new=1
    scan="$file"
    if [ -n "$content" ]; then
      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT
      scan="$tmpdir/$(basename "$file")"
      printf '%s' "$content" > "$scan"
    elif [ ! -f "$file" ]; then
      exit 0
    fi
    for g in "${FILE_GUARDS[@]}"; do
      run_guard "$g" "$scan" "$file"
    done
    if [ "$is_new" -eq 1 ]; then
      for g in "${NEW_FILE_GUARDS[@]}"; do
        run_guard "$g" "$scan" "$file"
      done
    fi
    ;;
  Bash|run_terminal_cmd|shell|terminal)
    [ -n "$cmd" ] || exit 0
    for g in "${CMD_GUARDS[@]}"; do
      [ -x "$HERE/$g.sh" ] || continue
      out="$("$HERE/$g.sh" "$cmd" 2>&1)" || report "$out"
    done
    ;;
  ApplyPatch)
    [ -n "$patch" ] || exit 0
    # Each line is "<Add|Update> <path>" so the creation-only guards can be
    # told apart from the ones that run on every touch.
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      verb="${entry%% *}"
      f="${entry#* }"
      [ -n "$f" ] || continue
      case "$f" in "$HERE"/*) continue ;; esac
      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT
      scan="$tmpdir/$(basename "$f")"
      printf '%s\n' "$patch" | sed -n 's/^+//p' > "$scan"
      for g in "${FILE_GUARDS[@]}"; do
        run_guard "$g" "$scan" "$f"
      done
      if [ "$verb" = "Add" ]; then
        for g in "${NEW_FILE_GUARDS[@]}"; do
          run_guard "$g" "$scan" "$f"
        done
      fi
    done < <(printf '%s\n' "$patch" | sed -nE 's/^\*\*\* (Add|Update) File: /\1 /p')
    ;;
  *) exit 0 ;;
esac

exit "$fail"
