#!/usr/bin/env bash
# guard-direct-style.sh — author-time, blocking direct-style-write guard.
#
# Enforces the universal rule: JS/TS must not mutate layout/appearance by
# assigning to an element's typed style properties directly
# (e.g. `el.style.top = ...`, `node.style.width = ...`). Instead, set a CSS
# custom property via `setProperty('--name', value)` and consume it in CSS.
# This keeps all values funneled through CSS variables rather than scattering
# imperative pixel/layout writes through script.
#
# Contract:
#   $1 = path to one file.
#   exit 0  if the file is clean, missing/unreadable, binary, or ignored.
#   exit 2  if a direct style-property write is found (blocking). Prints
#           `DIRECT STYLE: <path>:<line>` per hit plus a one-line rule reminder.
#
# Allowed (never flagged):
#   - .style.setProperty(...) / .style.removeProperty(...)  (the correct API)
#   - clearing a property by assigning an empty string (= '' / = "" / = ``)
#   - .style.cssText assignments (whole-string, not a single typed prop)
# The rule is structural: no per-file or per-project allowlist of properties.
set -euo pipefail

# Universal build-artifact ignore set. Matches anywhere in the path.
IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build)/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$'

path="${1:-}"

# No argument → nothing to check.
[ -z "$path" ] && exit 0

# Only inspect script files; anything else cannot have typed style writes.
case "$path" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac

# Ignored build artifact.
if printf '%s\n' "$path" | grep -Eq "$IGNORE"; then
  exit 0
fi

# Missing or unreadable → cannot check, do not block.
[ -f "$path" ] || exit 0
[ -r "$path" ] || exit 0

# Skip binary files (non-empty files with no text content).
if [ -s "$path" ] && ! LC_ALL=C grep -Iq . "$path" 2>/dev/null; then
  exit 0
fi

# Match a direct write to a typed style property:
#   <expr>.style.<prop> = <something-not-empty-string>
# An identifier property name (no parens) after `.style.` distinguishes a
# direct property assignment from `.style.setProperty(` or `.style.cssText`.
#
# ERE breakdown:
#   \.style\.[A-Za-z_][A-Za-z0-9_]*   typed property access
#   [[:space:]]*=[[:space:]]*          assignment (not == or =>, see filter)
WRITE_RE='\.style\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*'

found=0
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  lineno="${entry%%:*}"
  text="${entry#*:}"

  # Strip the property name to inspect the assignment target.
  prop=$(printf '%s\n' "$text" | grep -oE '\.style\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' | head -1)

  # Allowed: setProperty / removeProperty / cssText are not single-prop writes.
  case "$prop" in
    *.style.setProperty*|*.style.removeProperty*|*.style.cssText*) continue ;;
  esac
  case "$text" in
    *.style.setProperty*|*.style.removeProperty*|*.style.cssText*) continue ;;
  esac

  # Allowed: clearing a property with an empty string literal.
  if printf '%s\n' "$text" | grep -Eq "\.style\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(''|\"\"|\`\`)"; then
    continue
  fi

  # Allowed: == / === / => (not an assignment to the property).
  if printf '%s\n' "$text" | grep -Eq '\.style\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(==|=>)'; then
    # Only skip if there is no genuine single-`=` write on the line.
    if ! printf '%s\n' "$text" | grep -Eq '\.style\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[^=]'; then
      continue
    fi
  fi

  echo "DIRECT STYLE: $path:$lineno"
  found=1
done < <(grep -nE "$WRITE_RE" "$path" 2>/dev/null || true)

if [ "$found" -eq 1 ]; then
  echo "Rule: never assign element.style.<prop> directly — set a CSS custom property via element.style.setProperty('--name', value) and consume it in CSS." >&2
  exit 2
fi

exit 0
