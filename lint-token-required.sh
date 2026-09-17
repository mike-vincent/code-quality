#!/usr/bin/env bash
# lint-token-required.sh — batch linter requiring design-token references.
#
# Enforces ONE universal, structural rule:
#
#   Every size / color / weight / opacity VALUE that appears as a style value
#   must reference a CSS custom property (var(--*)). It must never be a raw
#   literal — no px/em/rem length, no hex/rgb()/rgba() color, no bare
#   font-weight number.
#
# There is no allowlist of "approved" values, no blessed token names, and no
# per-file exemption. The check is purely structural: if a style value is a
# raw literal where a token belongs, it is flagged. If it is `var(--anything)`,
# it passes. This makes the rule project-neutral — any repo's token names work.
#
# Contract:
#   Args (optional) = explicit file/dir paths to check.
#   No args         = scan the current working directory.
#   Prints `path:line: raw value <x> — use a var(--*) custom property` per hit,
#   then a trailing count line.
#   exit 1 if any hit, else exit 0.
#
# Conservative scoping (to avoid false positives on non-style numbers):
#   - In .css/.scss/.less files: every declaration line is a style context.
#   - In .ts/.tsx/.js/.jsx files: only lines that contain a style attribute or
#     style object (`style=` or `style{`) are inspected — matching the source
#     scripts' scope. Plain numeric code elsewhere is never touched.
#   - `0` lengths, and `0.5px`/`1px` on border/outline (hairlines) are allowed.
#   - Hex/rgb inside var() or color-mix() expressions are not double-flagged.
set -euo pipefail

# Universal build-artifact ignore set. Matches anywhere in the path.
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build)/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

violations=0

ext_of() {
  case "$1" in
    *.css|*.scss|*.sass|*.less) echo "css" ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) echo "js" ;;
    *) echo "skip" ;;
  esac
}

# A line is a style context. For css/less always true; for js it must hold an
# inline style attribute or style object literal.
is_style_context() {
  local kind="$1" line="$2"
  if [ "$kind" = "css" ]; then
    return 0
  fi
  case "$line" in
    *style=*|*style\ =*|*style:*|*style\{*) return 0 ;;
    *) return 1 ;;
  esac
}

# Report a raw value hit.
report() {
  local f="$1" lineno="$2" val="$3"
  echo "$f:$lineno: raw value $val — use a var(--*) custom property"
  violations=$((violations + 1))
}

check_line() {
  local f="$1" lineno="$2" line="$3"

  # Strip whitespace prefix; skip pure comment lines.
  local stripped="${line#"${line%%[![:space:]]*}"}"
  case "$stripped" in
    //*|/\**|\**) return 0 ;;
  esac

  # ── Raw hex colors (#rgb / #rrggbb / #rrggbbaa) ──
  # Skip ones embedded only inside color-mix(...) (interpolation helpers).
  local hex
  hex=$(printf '%s\n' "$line" | grep -oE '#[0-9a-fA-F]{3,8}' | head -1 || true)
  if [ -n "$hex" ] && ! printf '%s\n' "$line" | grep -qE 'color-mix\('; then
    report "$f" "$lineno" "$hex"
  fi

  # ── Raw rgb()/rgba() color literals (numeric channels, not var-driven) ──
  local rgb
  rgb=$(printf '%s\n' "$line" | grep -oE 'rgba?\([[:space:]]*[0-9]' | head -1 || true)
  if [ -n "$rgb" ]; then
    local rgbfull
    rgbfull=$(printf '%s\n' "$line" | grep -oE 'rgba?\([^)]*\)' | head -1 || true)
    report "$f" "$lineno" "${rgbfull:-rgb(...)}"
  fi

  # ── Raw font-weight numbers ──
  if printf '%s\n' "$line" | grep -qE 'font-?[Ww]eight[[:space:]]*:[[:space:]]*[0-9]'; then
    if ! printf '%s\n' "$line" | grep -qE 'font-?[Ww]eight[[:space:]]*:[[:space:]]*var\(--'; then
      local w
      w=$(printf '%s\n' "$line" | grep -oE 'font-?[Ww]eight[[:space:]]*:[[:space:]]*[0-9]+' | head -1)
      report "$f" "$lineno" "$w"
    fi
  fi

  # ── Raw opacity numbers (decimal, not var-driven, not 0 or 1) ──
  if printf '%s\n' "$line" | grep -qE '(^|[^a-zA-Z-])opacity[[:space:]]*:[[:space:]]*[0-9]'; then
    if ! printf '%s\n' "$line" | grep -qE 'opacity[[:space:]]*:[[:space:]]*var\(--'; then
      local op
      op=$(printf '%s\n' "$line" | grep -oE 'opacity[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?' | head -1)
      local opnum="${op##*:}"
      opnum="${opnum// /}"
      case "$opnum" in
        0|1|0.0|1.0) : ;;  # full transparent/opaque are not magic values
        *) report "$f" "$lineno" "$op" ;;
      esac
    fi
  fi

  # ── Raw px/em/rem length values in property: value pairs ──
  # Iterate each `prop: <num><unit>` occurrence not already wrapped in var().
  local match prop val num
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    prop="${match%%:*}"
    prop="${prop##*[^a-zA-Z-]}"   # last identifier before the colon
    val=$(printf '%s\n' "$match" | grep -oE '[0-9]+(\.[0-9]+)?(px|em|rem)' | head -1)
    [ -z "$val" ] && continue
    num="${val%%[a-z]*}"

    # Allow zero lengths regardless of unit.
    case "$num" in 0|0.0) continue ;; esac

    # Allow hairline borders/outlines (0.5px / 1px).
    case "$prop" in
      border*|outline*)
        case "$val" in 0.5px|1px) continue ;; esac
        ;;
    esac

    report "$f" "$lineno" "$val"
  done < <(printf '%s\n' "$line" \
    | grep -oE '[a-zA-Z-]+[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?(px|em|rem)' \
    | grep -v 'var(' || true)
}

check_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -r "$f" ] || return 0

  local kind
  kind=$(ext_of "$f")
  [ "$kind" = "skip" ] && return 0

  if printf '%s\n' "$f" | grep -Eq "$IGNORE"; then
    return 0
  fi

  if [ -s "$f" ] && ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
    return 0
  fi

  local lineno=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    is_style_context "$kind" "$line" || continue
    check_line "$f" "$lineno" "$line"
  done < "$f"
}

list_files() {
  if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
      if [ -d "$arg" ]; then
        find "$arg" -type f
      elif [ -e "$arg" ]; then
        printf '%s\n' "$arg"
      fi
    done
  else
    find . -type f
  fi
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_file "$f"
done < <(list_files "$@" | sort -u)

if [ "$violations" -gt 0 ]; then
  echo "$violations raw-value violation(s)"
  exit 1
fi

echo "0 raw-value violations"
exit 0
