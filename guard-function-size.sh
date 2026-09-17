#!/usr/bin/env bash
# guard-function-size.sh — author-time, blocking guard on the length of one function.
#
# No function may exceed 40 lines. This is the gate that makes the other two unnecessary
# most of the time: if every function is small, files stay small and modular on their
# own, and a file ceiling stops being something anyone has to think about.
#
# It also catches what a file ceiling cannot. A 280-line file holding one 250-line
# function is legal by line count and unreviewable in practice.
#
# Contract:
#   $1 = path to one file.
#   exit 0  if every function is <= 40 lines, or the file is ignored/unparseable.
#   exit 2  if any function exceeds 40 lines (blocking).
set -euo pipefail

MAX="${FUNCTION_MAX:-40}"

IGNORE='(^|/)(node_modules|dist|\.git|\.wrangler|generated|build|\.build|target|target-linux|\.swiftpm|DerivedData|vendor)(/|$)|/migrations/|/locales/|\.dSYM/|(^|/)package-lock\.json$|\.lock$|\.min\.[^/]*$|\.snap$'

path="${1:-}"
[ -z "$path" ] && exit 0
printf '%s\n' "$path" | grep -Eq "$IGNORE" && exit 0
[ -f "$path" ] || exit 0
[ -r "$path" ] || exit 0
if [ -s "$path" ] && ! LC_ALL=C grep -Iq . "$path" 2>/dev/null; then exit 0; fi

case "$path" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.swift|*.go|*.rs) ;;
  *) exit 0 ;;
esac

# Brace depth from the line a function opens on, back to the line depth returns to zero.
# Deliberately a counter and not a parser: a real AST needs a toolchain per language and
# this runs on every save. It reads the shape all these languages share — a header line,
# a brace, a body, a closing brace at the same depth.
#
# Python has no braces, so it is measured by indentation instead: a `def` and the run of
# lines indented past it.
report=$(
  awk -v MAX="$MAX" '
    function flush(name, start, end,   n) {
      n = end - start + 1
      if (n > MAX) printf "  %s:%d  %s  %d lines\n", FILENAME, start, name, n
    }
    BEGIN { depth = 0; open_line = 0; open_name = ""; py_open = 0 }
    FILENAME ~ /\.py$/ {
      match($0, /^[ \t]*/); ind = RLENGTH
      if (py_open && $0 ~ /[^ \t]/ && ind <= py_ind) { flush(py_name, py_start, NR - 1); py_open = 0 }
      if ($0 ~ /^[ \t]*(async[ \t]+)?def[ \t]+[A-Za-z_]/) {
        if (py_open) flush(py_name, py_start, NR - 1)
        py_open = 1; py_ind = ind; py_start = NR
        py_name = $0; sub(/^[ \t]*(async[ \t]+)?def[ \t]+/, "", py_name); sub(/[ \t]*\(.*/, "", py_name)
      }
      next
    }
    {
      if (depth == 0 && open_line == 0 && $0 ~ /(function[ \t]|=>[ \t]*\{|[ \t]func[ \t]|[ \t]fn[ \t]|^[ \t]*(export[ \t]+)?(async[ \t]+)?(function|const|let|var)[ \t].*\{[ \t]*$|^[ \t]*[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(.*\)[ \t]*\{[ \t]*$)/) {
        open_line = NR
        open_name = $0
        gsub(/^[ \t]+|[ \t]+$/, "", open_name)
        if (length(open_name) > 56) open_name = substr(open_name, 1, 56) "..."
      }
      n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
      depth += n - m
      if (open_line && depth <= 0) { flush(open_name, open_line, NR); open_line = 0; depth = 0 }
    }
    END { if (py_open) flush(py_name, py_start, NR) }
  ' "$path" 2>/dev/null || true
)

[ -z "$report" ] && exit 0

echo "FUNCTION LENGTH: over $MAX lines in $path" >&2
printf '%s\n' "$report" >&2
cat >&2 <<EOF
Split each into named helpers. $MAX lines is the limit for one function.

Extracting a helper is the cheapest refactor there is: it names a step that currently
has no name, and it is what keeps the file under its own ceiling without anyone
counting lines.
EOF
exit 2
