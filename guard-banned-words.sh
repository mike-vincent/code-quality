#!/usr/bin/env bash
# guard-banned-words.sh — author-time vocabulary guard (blocking, single file).
#
# Cardinal rule: shared architecture uses RFC 7231 / RFC 3986 / Apple HIG
# semantic + ARIA terms — never framework jargon. Banned words are UNIVERSAL
# and ABSOLUTE: there are no allow-lists, no per-file exemptions, no contexts.
# If a word is banned, it is banned everywhere. Domain nouns (whatever a given
# project's nouns happen to be) are that project's instance of violating this
# rule; this guard does not hardcode any project's domain — it bans only the
# generic framework/architecture jargon that is wrong in ANY codebase.
#
# Contract:
#   - Takes ONE file path as $1; checks only that file.
#   - Exit 0 = clean (also when $1 is missing, unreadable, or binary).
#   - Exit 2 = violation. Prints to stderr, one line per hit:
#       BANNED WORD: <term> (use <replacement>) at <path>:<line>
#     then a one-line reminder of the cardinal rule.
set -euo pipefail

# ── Inline dictionary (shared, self-contained) ──────────────────────────────
# Tab-separated triples: TERM <tab> REPLACEMENT <tab> ERE_PATTERN
# Patterns match identifier-shaped uses (CamelCase boundaries, snake_case,
# data-* attributes, CSS-ish tokens) so prose mentioning a word is not flagged.
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

# ── Resolve and validate the single target ──────────────────────────────────
file="${1:-}"
[ -n "$file" ] || exit 0
[ -f "$file" ] && [ -r "$file" ] || exit 0
# Banned-word rules target code identifiers, not prose. Skip documentation
# file types so docs (including dictionaries that define the bans) are free
# to mention the terms. This is file-TYPE scoping, not a per-file allowlist.
case "$file" in *.md|*.markdown|*.txt|*.rst|*.adoc) exit 0 ;; esac
# Skip binary files (NUL byte in first 4KB).
if LC_ALL=C grep -qI '' "$file" 2>/dev/null; then :; else exit 0; fi

# ── Scan ─────────────────────────────────────────────────────────────────────
# Feed awk the dictionary on stdin (the "-" input), then the target file.
# Tab-separated triples survive intact because awk splits on \t explicitly.
found=$(
  printf '%s\n' "$BANNED_DICT" | awk '
    BEGIN { n = 0 }
    # Phase 1: load dictionary from the first input (stdin).
    FNR == NR {
      if ($0 == "") next
      split($0, parts, "\t")
      terms[n] = parts[1]; uses[n] = parts[2]; pats[n] = parts[3]; n++
      next
    }
    # Phase 2: scan the target file.
    {
      line = $0
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      # Skip comment lines (// , /* , * , #).
      if (stripped ~ /^\/\//) next
      if (stripped ~ /^\/\*/) next
      if (stripped ~ /^\*/)  next
      if (stripped ~ /^#/)   next
      for (i = 0; i < n; i++) {
        if (match(line, pats[i])) {
          printf "%s\t%s\t%d\n", terms[i], uses[i], FNR
        }
      }
    }
  ' - "$file" 2>/dev/null
) || true

[ -n "$found" ] || exit 0

# ── Report ───────────────────────────────────────────────────────────────────
while IFS=$'\t' read -r term repl ln; do
  [ -n "$term" ] || continue
  printf 'BANNED WORD: %s (use %s) at %s:%s\n' "$term" "$repl" "$file" "$ln" >&2
done <<EOF
$found
EOF
printf 'Cardinal rule: shared architecture uses RFC 7231 / RFC 3986 / Apple HIG terms, never domain nouns or framework jargon.\n' >&2
exit 2
