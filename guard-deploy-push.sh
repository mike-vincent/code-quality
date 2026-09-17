#!/usr/bin/env bash
# guard-deploy-push.sh
#
# Command guard: block deploy commands when the working tree is unsafe to
# ship from. A deploy must run from a clean tree that has already been pushed
# to the default branch's upstream, so what ships matches what is in version
# control.
#
# Contract:
#   - Reads the proposed shell command from $1, or from stdin if no arg.
#   - Exit 0  = allow (command is not a deploy, or the tree is safe).
#   - Exit 2  = block, with a one-line reason on stderr.
#
# Self-contained: no sourcing, no imports.
set -euo pipefail

# --- read the proposed command -------------------------------------------
if [ "$#" -ge 1 ]; then
  CMD="$1"
else
  CMD="$(cat)"
fi

[ -z "${CMD//[[:space:]]/}" ] && exit 0

# --- ignore read-only commands that merely mention "deploy" --------------
# (grep/cat/echo/etc. inspecting a deploy script should not be blocked.)
printf '%s' "$CMD" | grep -qE '^[[:space:]]*(grep|rg|cat|head|tail|less|wc|echo|read|awk|sed|find|ls|git[[:space:]]+log|git[[:space:]]+show|git[[:space:]]+diff)\b' && exit 0

# --- detect generic deploy verbs -----------------------------------------
# Project-neutral set of common production-deploy commands. Matched
# case-insensitively anywhere in the command (start or after a chain op).
DEPLOY_RE='(^|[;&|]|[[:space:]])('
DEPLOY_RE+='wrangler[[:space:]]+(pages[[:space:]]+)?deploy'    # Cloudflare Workers/Pages
DEPLOY_RE+='|vercel([[:space:]].*--prod| deploy --prod| --prod)' # Vercel prod
DEPLOY_RE+='|netlify[[:space:]]+deploy.*--prod'                # Netlify prod
DEPLOY_RE+='|firebase[[:space:]]+deploy'                       # Firebase
DEPLOY_RE+='|fly[[:space:]]+deploy'                            # Fly.io
DEPLOY_RE+='|flyctl[[:space:]]+deploy'
DEPLOY_RE+='|gcloud[[:space:]]+(app|run|functions)[[:space:]]+deploy' # GCP
DEPLOY_RE+='|aws[[:space:]]+(deploy|s3[[:space:]]+sync|cloudformation[[:space:]]+deploy)'
DEPLOY_RE+='|sls[[:space:]]+deploy|serverless[[:space:]]+deploy' # Serverless framework
DEPLOY_RE+='|kubectl[[:space:]]+apply'                         # k8s
DEPLOY_RE+='|cap[[:space:]]+production[[:space:]]+deploy'      # Capistrano
DEPLOY_RE+='|(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+deploy' # package-script deploy
DEPLOY_RE+='|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(release|ship|publish:prod)'
DEPLOY_RE+='|make[[:space:]]+deploy'
DEPLOY_RE+=')'

printf '%s' "$CMD" | grep -qiE "$DEPLOY_RE" || exit 0

# Allow an explicit escape hatch so the guard never becomes a hard wall when
# a deploy is genuinely intended from a verified state.
case "${ALLOW_DIRTY_DEPLOY:-}" in
  1|true|TRUE|yes) exit 0 ;;
esac

# --- check the repo the deploy actually runs in --------------------------
# Follow a leading `cd <dir>` in the command so the guard validates the
# TARGET repo's branch/cleanliness, not the caller's working directory
# (e.g. an agent worktree on a feature branch deploying a different repo).
DEPLOY_DIR="$(printf '%s' "$CMD" | grep -oE '(^|[;&|]|[[:space:]])cd[[:space:]]+[^[:space:];&|]+' | head -1 | sed -E 's/.*cd[[:space:]]+//' || true)"
gitc() {
  if [ -n "${DEPLOY_DIR:-}" ] && [ -d "$DEPLOY_DIR" ]; then
    git -C "$DEPLOY_DIR" "$@"
  else
    git "$@"
  fi
}

# --- must be inside a git work tree --------------------------------------
if ! gitc rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Not a repo → cannot verify cleanliness; allow rather than false-block.
  exit 0
fi

# --- 1. tracked working tree must be clean -------------------------------
# Ignore untracked files: transient artifacts (deploy logs, worktree dirs,
# build output) accumulate untracked and must not block a deploy. What ships
# is the tracked, committed source — so only uncommitted TRACKED changes are
# unsafe.
if [ -n "$(gitc status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  echo "BLOCKED: deploy with uncommitted tracked changes. Commit or stash them, then push before deploying." >&2
  exit 2
fi

# --- a named non-production environment is not a production deploy -------
# The two checks below exist to keep unreviewed code off the production host.
# A deploy that explicitly names a pre-production environment is the opposite
# intent: that host exists so a change can be SEEN working before it reaches
# production, which means it must be able to run code that is not yet on the
# default branch. Applying the production rules to it makes the environment
# unusable for the one thing it is for.
#
# The clean-tree check above still applied -- what ships must still be
# committed, wherever it ships to.
# Two ways an environment gets named: a --env flag, or a package script whose own
# name carries it (npm run deploy:staging). Both say the same thing.
NONPROD='(staging|preview|development|sandbox|qa)'
NONPROD_RE="--env(=|[[:space:]]+)${NONPROD}([[:space:]]|$)"
NONPROD_RE+="|(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+[^[:space:]]*${NONPROD}[^[:space:]]*"
printf '%s' "$CMD" | grep -qE -- "$NONPROD_RE" && exit 0

# --- 2. must be on the default branch ------------------------------------
DEFAULT_BRANCHES_RE='^(main|master)$'
BRANCH="$(gitc rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$BRANCH" ] && ! printf '%s' "$BRANCH" | grep -qE "$DEFAULT_BRANCHES_RE"; then
  echo "BLOCKED: deploy from non-default branch '$BRANCH'. Merge to the default branch and deploy from there." >&2
  exit 2
fi

# --- 3. local HEAD must be pushed to upstream ----------------------------
UPSTREAM="$(gitc rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ -n "$UPSTREAM" ]; then
  LOCAL="$(gitc rev-parse HEAD 2>/dev/null || true)"
  REMOTE="$(gitc rev-parse "$UPSTREAM" 2>/dev/null || true)"
  AHEAD="$(gitc rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null || echo 0)"
  if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ] && [ "${AHEAD:-0}" -gt 0 ]; then
    echo "BLOCKED: local HEAD is ahead of '$UPSTREAM' by $AHEAD commit(s). Push to the default remote before deploying." >&2
    exit 2
  fi
fi

# Clean, on default branch, pushed → safe to deploy.
exit 0
