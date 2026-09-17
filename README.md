# code-quality

One universal, project-neutral code-quality standard. Every file here
ships unchanged to any repo — there is no per-repo config, no allowlist,
no exemption, and no file imports another. The rule and its data live in
the same file.

## Conventions

- **Flat.** No subdirectories. One file per rule.
- **Naming ladder.** One word preferred, two if needed, three max — and
  three must not be the mode. A word is the stem split on `-` or `_`.
  The name is neutral and is itself the scope.
- **Two verbs.** `guard-*` runs at author time on one file (exit 2 =
  block; exit 0 with output = advisory, passed through by the
  dispatcher). `lint-*` reports violations in a batch (exit 1 = violations).
  `hook-*` is a platform dispatcher that runs the above.
- **Self-contained.** Each script carries its own data inline. Run any
  one directly: `./lint-max-lines.sh path/to/file`.

## Enforcement stages (earliest wins)

| Stage | Dispatcher | Effect |
|---|---|---|
| author-time | `hook-pre-tool.sh` (PreToolUse) | blocks the write; reason shown to the model |
| edit-time | `hook-post-edit.sh` (PostToolUse) | advisory on save |
| commit-time | `hook-pre-commit.sh` (git pre-commit) | blocks the commit |
| merge-time | run `lint-*.sh` in CI | blocks the merge |

The cardinal rules — banned words, morpheme naming, 300-line ceiling —
exist as both `guard-*` (author-time, blocking) and `lint-*`
(commit/CI batch), so they reach the model as often as possible and are
still caught when an edit bypasses the model.

---

## Why use this with AI coding agents?

AI coding agents (like Claude Code, Cursor, and Codex) work fast, but they often make predictable mistakes:
- They invent framework jargon (like `Navbar` or `Modal`) instead of standard HTML elements.
- They generate giant, messy files and oversized functions.
- They make accidental changes that can cause surprise cloud bills (like Cloudflare KV writes).

This repository acts as a live guardrail:
- **Catches mistakes before they touch disk**: When an agent tries to save bad code, `hook-pre-tool.sh` blocks the write.
- **Shows the model the exact fix**: The guard prints a single-line explanation to stderr. The AI reads it, fixes its own mistake, and writes clean code on the next try.
- **Saves time and tokens**: Catching errors on the spot stops the AI from getting confused and having to rewrite files later.
- **Zero setup**: Every script is a standalone shell script. No packages to install, no configuration files to write.

---

## Rules

| File | Description |
|---|---|
| `guard-banned-words.sh` | Stops framework jargon from entering the codebase. Enforces standard W3C semantic HTML, ARIA roles, RFC 7231, and Apple HIG terms.<br>**Agent action:** Writes `<div className="navbar"><button className="chip">Save</button></div>`.<br>**Guard action:** Flags `navbar` and `chip`; enforces `<nav aria-label="Main"><button type="button">Save</button></nav>`. |
| `guard-bash-write.sh` | Stops bash commands that write or edit files directly, bypassing editor guards and tool tracking.<br>**Agent action:** Runs `cat << 'EOF' > user-profile-manager.ts` or `sed -i` to sneak past editor hooks.<br>**Guard action:** Rejects the command and forces writing through editor tools with clean names. |
| `guard-cloudflare-kv.sh` | Stops Cloudflare Workers KV bindings and write calls. Cloudflare charges \$5 per million writes, which creates runaway bills when scripts loop.<br>**Agent action:** Adds `[[kv_namespaces]]` to `wrangler.toml` or calls `await env.KV.put(key, val)`.<br>**Guard action:** Rejects KV usage to prevent metered billing leaks; requires static assets or non-metered storage. |
| `guard-deploy-push.sh` | Stops production deploys from an uncommitted working tree, an unmerged branch, or unpushed commits.<br>**Agent action:** Runs `wrangler deploy` on branch `fix-login` with uncommitted edits.<br>**Guard action:** Rejects the deploy until changes are committed, pushed, and merged into the default branch. |
| `guard-diff-size.sh` | Stops git pushes when a branch changes more than 200 lines (added plus deleted) against its base branch.<br>**Agent action:** Runs `git push` on a branch changing 450 lines (`+320, -130`).<br>**Guard action:** Rejects the push until the author splits the change into smaller branches under 200 lines each. |
| `guard-direct-style.sh` | Stops JavaScript and TypeScript from writing directly to element style properties. Funnels style changes through CSS custom properties.<br>**Agent action:** Writes `element.style.color = "#ff0000"` or `node.style.width = "200px"`.<br>**Guard action:** Rejects direct style mutation; enforces `element.style.setProperty("--theme-color", "var(--color-alert)")`. |
| `guard-function-size.sh` | Stops any single function from growing past 40 lines. Keeps functions short so code stays modular naturally.<br>**Agent action:** Writes a 65-line `parseUserData()` function with nested conditionals.<br>**Guard action:** Rejects the file until the function is broken into smaller helpers under 40 lines each. |
| `guard-max-lines.sh` | Stops any single file from growing past 300 lines, with an advisory warning starting at 200 lines.<br>**Agent action:** Appends 50 lines to `table.ts`, pushing the file to 325 lines.<br>**Guard action:** Rejects the write; agent splits the code into `table.ts` and `column.ts`. |
| `guard-morpheme-max.sh` | Stops file names with more than 3 words (split on `-` or `_`) and exported functions with more than 2 uppercase humps.<br>**Agent action:** Creates `user-account-profile-view.ts` or exports `function getUserAccountDetails()`.<br>**Guard action:** Rejects 4-word name and 3-hump function; agent uses `user-profile.ts` and `getAccountDetails()`. |
| `guard-name-words.sh` | Enforces the naming ladder on newly created files: 1 word preferred (`book.ts`), 2 words fine (`book-state.ts`), 3 words announced.<br>**Agent action:** Creates a new file named `audio-player-controller.ts` (3 words).<br>**Guard action:** Prints an advisory notice that 3 words is the ceiling and suggests `audio-player.ts` or `player.ts`. |
| `guard-pull-request.sh` | Stops creating a pull request with `gh pr create` if the body lacks an acceptance criteria checkbox.<br>**Agent action:** Runs `gh pr create --body "Updated authentication flow"`.<br>**Guard action:** Rejects the PR create until a task-list checkbox is added (`- [ ] Pass user auth test suite`). |
| `guard-push-main.sh` | Stops direct `git push` commands to `main` or `master`. Keeps the default branch clean and reviewable.<br>**Agent action:** Runs `git push origin main`.<br>**Guard action:** Rejects the push; forces pushing to a feature branch with a pull request. |
| `guard-url-version.sh` | Stops hardcoding API versions into URL path segments or query strings. Enforces versioning through HTTP headers.<br>**Agent action:** Calls `fetch("/api/v1/users")` or `fetch("/items?version=2")`.<br>**Guard action:** Rejects URL versioning; enforces `fetch("/api/users", { headers: { "Accept-Version": "1.0.0" } })`. |
| `hook-post-edit.sh` | Runs batch linters right after an agent saves an edit. Prints advisory warnings back to the agent without interrupting work.<br>**Agent action:** Saves `header.ts` with 310 lines after an edit.<br>**Hook action:** Prints `header.ts: 310 lines (limit 300)` as an advisory notice in the agent's turn. |
| `hook-pre-commit.sh` | Git pre-commit hook that checks newly staged lines and touched files for banned words, raw styles, and line limits.<br>**Agent action:** Stages a git commit adding `className="card"` to an existing component.<br>**Hook action:** Catches the staged line and rejects the commit until changed to `className="row"`. |
| `hook-pre-tool.sh` | Agent dispatcher for `PreToolUse`. Inspects proposed file writes and bash commands before they touch disk.<br>**Agent action:** Calls `Write` to create `src/modal-view.tsx`.<br>**Hook action:** Intercepts the tool call, prints `BANNED WORD: modal`, and agent retries with `src/dialog.tsx`. |
| `lint-banned-words.sh` | Batch scanner that checks the whole codebase for framework jargon and non-standard terms.<br>**Agent action:** Commits legacy components with `hero-banner.vue` and `data-card` attributes.<br>**Lint action:** Flags non-standard words and points author to semantic replacements (`header`, `row`). |
| `lint-dead-imports.sh` | Batch scanner that finds broken relative imports in JavaScript and TypeScript files.<br>**Agent action:** Moves `date.ts` to another folder, leaving `import { format } from "./utils/date"` behind.<br>**Lint action:** Flags the dead import path so the broken reference can be fixed. |
| `lint-important-css.sh` | Batch scanner that flags `!important` in stylesheets and inline styles. Enforces resolving CSS specificity cleanly.<br>**Agent action:** Writes `.btn { color: white !important; }` to override button styles.<br>**Lint action:** Flags `!important`; enforces `@layer components { .btn { color: var(--color-btn); } }`. |
| `lint-max-lines.sh` | Batch scanner that reports every file in the project that exceeds the 300-line ceiling.<br>**Agent action:** Merges changes over time until `app.ts` reaches 520 lines.<br>**Lint action:** Fails CI build with `app.ts: 520 lines (limit 300)` until the file is split into smaller units. |
| `lint-morpheme-max.sh` | Batch scanner that flags file names with more than 3 words and exported functions with more than 2 uppercase humps.<br>**Agent action:** Exports `function calculateUserMonthlyInvoiceSummary()`.<br>**Lint action:** Flags 3 uppercase humps (`User`, `Monthly`, `Invoice`, `Summary`); author shortens to `calculateInvoiceSummary()`. |
| `lint-naming.sh` | Checks the naming distribution across all files added by a branch. Fails if 3-word names become the most common pattern.<br>**Agent action:** Branch adds four 3-word files (`user-auth-guard.ts`, `data-sync-task.ts`, etc.) and no 1-word files.<br>**Lint action:** Fails CI because 3-word names became the mode; author renames files to 1 or 2 words (`auth.ts`, `sync.ts`). |
| `lint-token-required.sh` | Batch scanner requiring CSS colors, sizes, and font weights to reference CSS custom properties (`var(--*)`).<br>**Agent action:** Writes hardcoded values like `margin: 16px; color: #1a1a1a;`.<br>**Lint action:** Flags raw values; enforces design tokens: `margin: var(--spacing-md); color: var(--color-text);`. |
| `lint-url-version.sh` | Batch scanner that flags API version numbers hardcoded into URL paths or query strings.<br>**Agent action:** Writes API calls targeting `/api/v2/products`.<br>**Lint action:** Flags version in path; enforces routing to `/api/products` with headers. |

---

## Usage

Run any script directly against a file or project:

```sh
# Check a single file with a guard
./guard-max-lines.sh path/to/file.ts
./guard-cloudflare-kv.sh wrangler.toml
./guard-banned-words.sh src/button.tsx

# Run a batch linter across the current directory
./lint-max-lines.sh
./lint-banned-words.sh
./lint-token-required.sh
./lint-naming.sh
```

### Agent Integration

Add to agent settings for author-time (blocking) and edit-time (advisory) enforcement:

Claude Code (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse":  [{ "matcher": "Edit|Write|Bash", "hooks": [{ "type": "command", "command": "/path/to/hook-pre-tool.sh" }] }],
    "PostToolUse": [{ "matcher": "Edit|Write",      "hooks": [{ "type": "command", "command": "/path/to/hook-post-edit.sh" }] }]
  }
}
```

Git pre-commit (`.git/hooks/pre-commit`):
```sh
exec "/path/to/code-quality/hook-pre-commit.sh"
```

---

## License

[MIT](LICENSE) © 2026 Mike Vincent
