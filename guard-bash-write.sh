#!/usr/bin/env bash
# guard-bash-write.sh — block Bash commands that write to files
# violating naming rules (morpheme dash limit).
#
# Agents bypass Edit/Write guards by using Bash heredocs, tee, sed -i,
# or shell redirects. This guard closes that loophole by extracting
# write targets from the proposed command and checking filenames/content.
#
# Contract:
#   $1 = proposed shell command (or stdin)
#   exit 0  = allow
#   exit 2  = block (reason on stderr)
set -euo pipefail

MAX_DASHES=2

if [ "$#" -ge 1 ]; then
  CMD="$1"
else
  CMD="$(cat)"
fi

[ -z "${CMD//[[:space:]]/}" ] && exit 0

targets=""
add_target() {
  local clean="$1"
  clean="${clean%\"}"
  clean="${clean%\'}"
  clean="${clean%\;}"
  targets="${targets:+$targets$'\n'}$clean"
}

# 1. Shell redirects: > file, >> file (not >& or >/dev/null)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in /dev/*|"&"*) continue ;; esac
  add_target "$t"
done < <(printf '%s' "$CMD" \
  | grep -oE '>>?[[:space:]]+[^;&|[:space:]]+' \
  | sed -E 's/^>>?[[:space:]]+//' || true)

# 2. tee [-a] FILE
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in /dev/*) continue ;; esac
  add_target "$t"
done < <(printf '%s' "$CMD" \
  | grep -oE 'tee[[:space:]]+(-a[[:space:]]+)?[^;&|[:space:]]+' \
  | sed -E 's/^tee[[:space:]]+(-a[[:space:]]+)?//' || true)

# 3. sed -i (in-place edit) — last non-flag argument
while IFS= read -r t; do
  [ -n "$t" ] || continue
  add_target "$t"
done < <(printf '%s' "$CMD" \
  | grep -oE "sed[[:space:]]+(-[^[:space:]]*)?-i[^[:space:]]*[[:space:]]+('[^']*'|\"[^\"]*\")[[:space:]]+[^;&|[:space:]]+" \
  | rev | cut -d' ' -f1 | rev || true)

# 4. perl -i / -pi / -ni (in-place edit) — every non-flag, non-script argument
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  skip_next=0
  for tok in $seg; do
    [ "$tok" = "perl" ] && continue
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$tok" in
      -e|-E) skip_next=1; continue ;;
      -*) continue ;;
      \'*|\"*) continue ;;
    esac
    add_target "$tok"
  done
done < <(printf '%s' "$CMD" \
  | grep -oE "perl[[:space:]]+[^;&|]*-[a-zA-Z]*i[a-zA-Z]*[^;&|]*" || true)

# 5. awk -i inplace — in-place writers that name a file argument
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  for tok in $seg; do
    case "$tok" in
      awk|-i|inplace|-*) continue ;;
      \'*|\"*|*\{*) continue ;;
    esac
    add_target "$tok"
  done
done < <(printf '%s' "$CMD" \
  | grep -oE "awk[[:space:]]+-i[[:space:]]+inplace[^;&|]*" || true)

[ -z "$targets" ] && exit 0

fail=0

check_written_content() {
  local f="$1" base key caps
  base="$(basename "$f")"
  case "$base" in
    *.yaml|*.yml|*.toml|*.json) ;;
    *) return 0 ;;
  esac

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    caps="$(printf '%s' "$key" | tr -cd 'A-Z' | wc -c | tr -d ' ')"
    if [ "$caps" -gt 2 ]; then
      printf 'BLOCKED: Bash write to "%s" would add config key "%s" with %d capital letters (max 2).\n' \
        "$f" "$key" "$caps" >&2
      fail=2
    fi
  done < <(printf '%s\n' "$CMD" \
    | sed -nE 's/^[+[:space:]]*"?(--)?([A-Za-z][A-Za-z0-9_-]*)"?[[:space:]]*[:=].*/\2/p')
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  base="$(basename "$f")"
  stem="${base%.*}"
  [ -n "$stem" ] || stem="$base"
  dashes="$(printf '%s' "$stem" | tr -cd '-' | wc -c | tr -d ' ')"
  if [ "$dashes" -gt "$MAX_DASHES" ]; then
    printf 'BLOCKED: Bash write to "%s" — %d dashes in filename (max %d). Rename the file or use fewer morphemes.\n' \
      "$f" "$dashes" "$MAX_DASHES" >&2
    fail=2
  fi
  check_written_content "$f"
done <<< "$targets"

exit "$fail"
