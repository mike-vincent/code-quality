#!/usr/bin/env bash
# lint-dead-imports.sh
#
# Batch linter for broken relative imports. Scans JS/TS source files and
# reports any import/require/export-from specifier that points at a relative
# path which resolves to no file on disk.
#
# Universal: no project directories, no rename allowlists. Resolution uses
# only the source file's own location plus the standard module-resolution
# rules (explicit extension, common extensions, and index files in a dir).
#
# Usage:
#   lint-dead-imports.sh [path ...]
#     - With paths: scan each (files scanned directly, dirs scanned recursively).
#     - Without paths: scan the current working directory recursively.
#
# Output:
#   path:line: dead import '<spec>'
#   ...
#   <N> dead import(s)        (trailing count)
#
# Exit:
#   0 : no dead imports
#   1 : one or more dead imports found
set -euo pipefail

# Directories and file globs we never descend into or inspect.
IGNORE_DIRS=(node_modules dist .git .wrangler generated build .build target target-linux .swiftpm DerivedData)
IGNORE_GLOBS=('*.lock' '*.min.*')

# Source extensions we lint.
SRC_EXTS=(ts tsx js jsx mjs cjs mts cts)

# Candidate extensions tried when resolving an extensionless specifier.
RESOLVE_EXTS=(ts tsx js jsx mjs cjs mts cts json)

# ---------------------------------------------------------------------------
# Build the find command that enumerates lintable source files.
# ---------------------------------------------------------------------------
enumerate_files() {
  local root="$1"
  local -a args=()

  # Prune ignored directories.
  args+=('(')
  local first_prune=1
  for d in "${IGNORE_DIRS[@]}"; do
    if [ "$first_prune" -eq 1 ]; then
      first_prune=0
    else
      args+=('-o')
    fi
    args+=(-name "$d")
  done
  args+=(')' -type d -prune -o)

  # Match source files by extension.
  args+=('(')
  local first_ext=1
  for e in "${SRC_EXTS[@]}"; do
    if [ "$first_ext" -eq 1 ]; then
      first_ext=0
    else
      args+=('-o')
    fi
    args+=(-name "*.$e")
  done
  args+=(')' -type f -print)

  find "$root" "${args[@]}" 2>/dev/null
}

# Return 0 if the given file path matches an ignored glob.
is_ignored_glob() {
  local f="$1" base
  base="$(basename "$f")"
  for g in "${IGNORE_GLOBS[@]}"; do
    # shellcheck disable=SC2053
    case "$base" in
      $g) return 0 ;;
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Resolve a relative specifier against the importing file's directory.
# Echoes the resolved path on success; returns non-zero if nothing resolves.
# ---------------------------------------------------------------------------
resolve_spec() {
  local from_dir="$1" spec="$2"
  # Normalize the base target (may or may not exist as-is).
  local target="$from_dir/$spec"

  # 1. Exact path as written (already has an extension or is otherwise a file).
  [ -f "$target" ] && { echo "$target"; return 0; }

  # 2. Specifier + each candidate extension:  ./foo -> ./foo.ts
  for e in "${RESOLVE_EXTS[@]}"; do
    [ -f "$target.$e" ] && { echo "$target.$e"; return 0; }
  done

  # 3. Directory index:  ./foo -> ./foo/index.ts
  if [ -d "$target" ]; then
    for e in "${RESOLVE_EXTS[@]}"; do
      [ -f "$target/index.$e" ] && { echo "$target/index.$e"; return 0; }
    done
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Scan a single file for relative import specifiers and check resolution.
# Appends "path:line: dead import '<spec>'" lines to global REPORT.
# ---------------------------------------------------------------------------
scan_file() {
  local file="$1"
  local from_dir
  from_dir="$(cd "$(dirname "$file")" && pwd)"

  # Pull every line that carries an import-like construct with a relative spec.
  #   import ... from './x'      export ... from '../y'
  #   import('./z')              require('./w')
  # We only care about specifiers beginning with './' or '../'.
  local lineno spec
  while IFS= read -r entry; do
    lineno="${entry%%:*}"
    local rest="${entry#*:}"

    # Extract the quoted specifier from the matched line.
    spec="$(printf '%s\n' "$rest" \
      | grep -oE "(from[[:space:]]+|import[[:space:]]*\(|require[[:space:]]*\()[[:space:]]*['\"](\.\.?/)[^'\"]*['\"]" \
      | grep -oE "['\"](\.\.?/)[^'\"]*['\"]" \
      | head -n 1 \
      | sed -E "s/^['\"]//; s/['\"]$//")"

    [ -z "$spec" ] && continue

    if ! resolve_spec "$from_dir" "$spec" >/dev/null; then
      REPORT+=("${file}:${lineno}: dead import '${spec}'")
    fi
  done < <(grep -nE "(from[[:space:]]+|import[[:space:]]*\(|require[[:space:]]*\()[[:space:]]*['\"](\.\.?/)" "$file" 2>/dev/null || true)
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------
declare -a REPORT=()
declare -a TARGETS=()

if [ "$#" -eq 0 ]; then
  TARGETS=(".")
else
  TARGETS=("$@")
fi

# Collect the file list across all targets.
declare -a FILES=()
for t in "${TARGETS[@]}"; do
  if [ -f "$t" ]; then
    FILES+=("$t")
  elif [ -d "$t" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && FILES+=("$f")
    done < <(enumerate_files "$t")
  fi
done

for f in ${FILES[@]+"${FILES[@]}"}; do
  is_ignored_glob "$f" && continue
  scan_file "$f"
done

if [ "${REPORT+x}" ]; then
  count="${#REPORT[@]}"
else
  count=0
fi
if [ "$count" -gt 0 ]; then
  for line in "${REPORT[@]}"; do
    echo "$line"
  done
fi
echo "${count} dead import(s)"

[ "$count" -gt 0 ] && exit 1
exit 0
