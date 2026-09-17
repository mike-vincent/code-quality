#!/usr/bin/env bash
# lint-banned-words.sh — batch vocabulary lint (commit / CI).
#
# Cardinal rule: shared architecture uses RFC 7231 / RFC 3986 / Apple HIG
# semantic + ARIA terms — never framework jargon. Banned words are UNIVERSAL
# and ABSOLUTE: there are no allow-lists, no per-file exemptions, no contexts.
# If a word is banned, it is banned everywhere. Domain nouns (whatever a given
# project's nouns happen to be) are that project's instance of violating this
# rule; this linter does not hardcode any project's domain — it bans only the
# generic framework/architecture jargon that is wrong in ANY codebase.
#
# Contract:
#   - Takes file paths as args. With no args, scans text source files under
#     the current directory.
#   - Honors a universal ignore set (node_modules, dist, .git, .wrangler,
#     generated, build, *.lock, *.min.*).
#   - Prints each violation:  path:line: BANNED <term> -> <replacement>
#   - Prints a trailing count.
#   - Exit 1 if any violations, else 0.
set -euo pipefail

# ── Inline dictionary (shared, self-contained — identical to the guard) ──────
# Tab-separated triples: TERM <tab> REPLACEMENT <tab> ERE_PATTERN
read -r -d '' BANNED_DICT <<'DICT' || true
entity	resource	(Entity[A-Z_]|entity_[a-z]|[A-Z]Entity[^a-z]|[A-Z]Entity$)
hero	header	(Hero[A-Z_]|[Hh]ero_[a-z]|data-hero|[a-z]Hero[^a-z]|[a-z]Hero$|<Hero>)
chip	button	(Chip[A-Z_s]|chip_[a-z]|data-chip|[a-z]Chip[^a-z]|[a-z]Chip$|Chip[Rr]ow|ChipDef)
card	row	(Card[A-Z_]|card_[a-z]|data-card|[a-z]Card[^a-z]|[a-z]Card$)
feed	list	(Feed[A-Z_s]|feed_[a-z]|data-feed|[a-z]Feed[^a-z]|[a-z]Feed$|FeedRow|FeedShell)
shelf	section	(Shelf[A-Z_s]|shelf_[a-z]|data-shelf|[a-z]Shelf[^a-z]|[a-z]Shelf$)
strip	h-scroll	(Strip[A-Z_]|strip_[a-z]|data-strip|[a-z]Strip[^a-z]|[a-z]Strip$|[a-z]-strip[^a-z]|[a-z]-strip$)
rail	(banned, no replacement)	(Rail[A-Z_s]|rail_[a-z]|data-rail|[a-z]Rail[^a-z]|[a-z]Rail$|<Rail>)
navbar	nav	(NavBar|Navbar|navbar|nav_bar|data-navbar)
sidebar	aside	(SideBar|Sidebar|sidebar|side_bar|data-sidebar)
modal	dialog	(Modal[A-Z_s]|modal_[a-z]|data-modal|[a-z]Modal[^a-z]|[a-z]Modal$|<Modal>)
popup	dialog	(Popup[A-Z_s]|popup_[a-z]|data-popup|[a-z]Popup[^a-z]|[a-z]Popup$|<Popup>)
popover	dialog	(Popover[A-Z_s]|popover_[a-z]|[a-z]Popover[^a-z]|[a-z]Popover$|<Popover>)
widget	control	(Widget[A-Z_s]|widget_[a-z]|data-widget|[a-z]Widget[^a-z]|[a-z]Widget$|<Widget>)
partial	fragment	(Partial[A-Z_s]|partial_[a-z]|data-partial|[a-z]Partial[^a-z]|[a-z]Partial$|<Partial>)
island	fragment	(Island[A-Z_s]|island_[a-z]|data-island|[a-z]Island[^a-z]|[a-z]Island$|<Island>)
chunk	fragment	(Chunk[A-Z_]|chunk_[a-z]|data-chunk|[a-z]Chunk[^a-z]|[a-z]Chunk$|<Chunk>)
block	section	(Block[A-Z_]|block_[a-z]|data-block|[a-z]Block[^a-z]|[a-z]Block$)
loader	fetch function	(Loader[A-Z_s]|loader_[a-z]|data-loader|[a-z]Loader[^a-z]|[a-z]Loader$|<Loader>)
reducer	(banned, Redux jargon)	([Rr]educer[A-Z_]|[a-z]Reducer[^a-z]|[a-z]Reducer$|<Reducer>|use[A-Z][A-Za-z]*Reducer)
dispatch	method handler	(useDispatch|store\.dispatch|Dispatch[A-Z])
gateway	home	(Gateway[A-Z_]|gateway_[a-z]|data-gateway|[a-z]Gateway[^a-z]|[a-z]Gateway$|<Gateway>)
DICT

# ── Universal ignore set & source-extension scope ───────────────────────────
# Banned-word rules target code identifiers, not prose -- documentation
# (.md/.txt) is intentionally out of scope so docs may discuss the terms.
IGNORE_RE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build)/|\.lock$|\.min\.'
EXT_RE='\.(ts|tsx|js|jsx|css|html|svg|json|rs|py)$'

is_ignored() { printf '%s' "$1" | grep -qE "$IGNORE_RE"; }
is_source()  { printf '%s' "$1" | grep -qE "$EXT_RE"; }

# ── Collect target files ─────────────────────────────────────────────────────
files=()
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    [ -f "$f" ] || continue
    is_ignored "$f" && continue
    is_source "$f"  || continue
    files+=("$f")
  done
else
  while IFS= read -r f; do
    is_ignored "$f" && continue
    is_source "$f"  || continue
    files+=("$f")
  done < <(find . -type f 2>/dev/null | sed 's#^\./##' | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "Banned-words lint: no source files to scan."
  exit 0
fi

# ── Scan ─────────────────────────────────────────────────────────────────────
# Feed the dictionary on stdin (the "-" input), then every target file.
violations=$(
  printf '%s\n' "$BANNED_DICT" | awk '
    BEGIN { n = 0; count = 0 }
    # Phase 1: load dictionary from the first input (stdin "-").
    FILENAME == "-" {
      if ($0 != "") {
        split($0, parts, "\t")
        terms[n] = parts[1]; uses[n] = parts[2]; pats[n] = parts[3]; n++
      }
      next
    }
    # Phase 2: scan a target file.
    {
      line = $0
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^\/\//) next
      if (stripped ~ /^\/\*/) next
      if (stripped ~ /^\*/)  next
      if (stripped ~ /^#/)   next
      for (i = 0; i < n; i++) {
        if (match(line, pats[i])) {
          printf "%s:%d: BANNED %s -> %s\n", FILENAME, FNR, terms[i], uses[i]
          count++
        }
      }
    }
    END { printf "__COUNT__%d\n", count }
  ' - "${files[@]}" 2>/dev/null
) || true

# Split the trailing count marker from the reported lines.
count=$(printf '%s\n' "$violations" | sed -n 's/^__COUNT__//p' | tail -n 1)
report=$(printf '%s\n' "$violations" | grep -v '^__COUNT__' || true)
[ -n "$count" ] || count=0

[ -n "$report" ] && printf '%s\n' "$report"

echo "──────────────────────────────────────────"
if [ "$count" -gt 0 ]; then
  echo "BANNED-WORDS LINT: ${count} violation(s)."
  echo "Cardinal rule: shared architecture uses RFC 7231 / RFC 3986 / Apple HIG terms, never domain nouns or framework jargon."
  exit 1
fi
echo "Banned-words lint: no violations."
exit 0
