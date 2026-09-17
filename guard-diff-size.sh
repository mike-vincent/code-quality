#!/usr/bin/env bash
# guard-diff-size.sh — local pre-push diff sizer.
#
# Total delta (added + deleted) across the whole branch against its base. Over the
# ceiling, the push is refused and the branch must be split into two.
#
# This is the third of the three size gates and the one that catches what the other two
# cannot. A file ceiling says nothing about ten files changed at once, and a function
# ceiling says nothing about a rename that touches sixty call sites. Delta is the only
# number that answers "can a person review this in one sitting".
#
# Added AND deleted, not net. A change that removes 300 lines and adds 300 is not a
# small change; net-zero is how a rewrite disguises itself as a wash.
#
# Contract (the CMD_GUARDS shape in hook-pre-tool.sh):
#   $1 = the proposed shell command.
#   exit 0  unless that command is a push and the branch delta is over the ceiling.
#   exit 2  if it is (blocking).
#
# It fires on push rather than on every command because a push is the moment the change
# stops being local. Before that, a growing branch is still one an author can split
# without rewriting history.
set -euo pipefail

MAX="${DIFF_DELTA_MAX:-200}"

cmd="${1:-}"
# Only a push. `git push`, and the `gh pr create` that implies one.
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+create' || exit 0

# Exclusion matrix. These are generated or mechanical: counting them measures the
# generator, not the change. Lockfiles, build output, vendored code, database
# migrations, translation catalogues, and minified bundles.
EXCLUDE=(
  ':(exclude)*.lock'
  ':(exclude)package-lock.json'
  ':(exclude)pnpm-lock.yaml'
  ':(exclude)yarn.lock'
  ':(exclude)poetry.lock'
  ':(exclude)Cargo.lock'
  ':(exclude)*.min.*'
  ':(exclude)node_modules/**'
  ':(exclude)dist/**'
  ':(exclude)build/**'
  ':(exclude)vendor/**'
  ':(exclude)**/migrations/**'
  ':(exclude)**/locales/**'
  ':(exclude)**/*.snap'
)

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

base=""
for cand in origin/main origin/master main master; do
  if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then base="$cand"; break; fi
done
# Nothing to compare against — a fresh repo or a detached checkout. Do not block.
[ -n "$base" ] || exit 0

merge_base="$(git merge-base "$base" HEAD 2>/dev/null || true)"
[ -n "$merge_base" ] || exit 0

# --numstat gives added and deleted per file. Binary files report "-" and are skipped.
read -r added deleted files <<<"$(
  git diff --numstat "$merge_base"...HEAD -- . "${EXCLUDE[@]}" 2>/dev/null |
  awk '$1 != "-" && $2 != "-" { a += $1; d += $2; n += 1 } END { print (a+0), (d+0), (n+0) }'
)"
delta=$(( added + deleted ))

[ "$delta" -le "$MAX" ] && exit 0

cat >&2 <<EOF
Branch delta is ${delta} lines (+${added} / -${deleted}) across ${files} files, against ${base}.
The ceiling is ${MAX}.

Do not raise the ceiling. Split the branch.

A diff this size cannot be reviewed in one sitting, and it is how a rename, a refactor
and a fix arrive in one commit so that none of them can be reverted alone.

  1. Read your task list. This branch is doing more than one thing — name the two.
  2. Put the second thing on its own branch, from the same base.
  3. Push the first. Open its PR. Then rebase the second onto it, or onto main once
     the first has landed.

Two small PRs merge faster than one large one, and each can be reverted by itself.

If the delta is genuinely one indivisible change — a generated data table, a single new
contract file, a mechanical codemod with no hand edits — the exclusion matrix above is
where that belongs, not a raised ceiling. Add the path pattern and say why in the commit.
EOF
exit 2
