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
| `guard-banned-words.sh` | Blocks UI framework jargon like `navbar`, `modal`, `card`, and `hero` at write time. Enforces standard RFC 7231, RFC 3986, and Apple HIG terms (`nav`, `dialog`, `row`, `header`). (Blocks with exit 2). |
| `guard-bash-write.sh` | Blocks editing files through bash commands like `sed -i` or `echo > file`. Forces agents to write files through proper editor tools so changes are tracked. (Blocks with exit 2). |
| `guard-cloudflare-kv.sh` | Blocks Cloudflare Workers KV bindings and API calls. Cloudflare charges for every KV write ($5 per million), so this stops runaway billing leaks. (Blocks with exit 2). |
| `guard-deploy-push.sh` | Blocks deploying to production from a dirty working tree, a feature branch, or unpushed commits. Deploying to named non-prod environments (like staging) is allowed. (Blocks with exit 2). |
| `guard-diff-size.sh` | Blocks branches that change too many lines of code at once. Keeps pull requests small and reviewable instead of giant rewrites. (Blocks with exit 2). |
| `guard-direct-style.sh` | Blocks changing styles directly with JavaScript (`element.style.x =`). Use CSS classes or design tokens instead. (Blocks with exit 2). |
| `guard-function-size.sh` | Blocks any function that is longer than 50 lines. Keeps functions short and easy to understand. (Blocks with exit 2). |
| `guard-max-lines.sh` | Blocks any file that is longer than 300 lines. Keeps files small and focused. (Blocks with exit 2). |
| `guard-morpheme-max.sh` | Blocks file names and exported function names with more than 3 words (split on `-` or `_`). Standard uppercase environment variables are allowed. (Blocks with exit 2). |
| `guard-name-words.sh` | Naming ladder for new files: 1 word preferred, 2 fine, 3 announced. Warns the author when a 3-word file name is created. (Advisory, exit 0). |
| `guard-pull-request.sh` | Blocks opening a pull request if the body has no acceptance-criteria checkbox (`- [ ]`). Every PR must state clearly what "done" means. (Blocks with exit 2). |
| `guard-push-main.sh` | Blocks direct `git push` to `main` or `master`. Forces work into feature branches and pull requests. (Blocks with exit 2). |
| `guard-url-version.sh` | Blocks hardcoded version numbers in URL paths (like `/v1/`). API versions belong in HTTP headers (`Accept-Version`). (Blocks with exit 2). |
| `hook-post-edit.sh` | Runs fast linters immediately after an agent saves an edit. Prints advisory warnings back to the agent without blocking. (Advisory, exit 0). |
| `hook-pre-commit.sh` | Git pre-commit hook that checks staged changes for banned words, raw style values, and line limits. Blocks new mistakes without breaking existing legacy code. (Blocks commit on exit 1). |
| `hook-pre-tool.sh` | Agent dispatcher that checks proposed file writes and bash commands before they touch disk. If a rule is broken, it blocks the tool and shows the reason to the model so it self-corrects. (Blocks with exit 2). |
| `lint-banned-words.sh` | Batch scanner that checks the whole codebase for framework jargon and flags files using banned terms. (Exits 1 if violations found). |
| `lint-dead-imports.sh` | Batch scanner that checks TypeScript and JavaScript files for broken relative imports that point to files that do not exist. (Exits 1 if violations found). |
| `lint-important-css.sh` | Batch scanner that bans `!important` in CSS and styling code. Fix specificity issues properly instead of using overrides. (Exits 1 if violations found). |
| `lint-max-lines.sh` | Batch scanner that reports all files in the project that exceed the 300-line ceiling. (Exits 1 if violations found). |
| `lint-morpheme-max.sh` | Batch scanner that reports all file names and exported functions that have more than 3 words. (Exits 1 if violations found). |
| `lint-naming.sh` | Branch checker that looks at all files a branch adds. Fails if 3-word names are the most common naming pattern. (Exits 1 if violations found). |
| `lint-token-required.sh` | Batch scanner requiring CSS colors, sizes, and weights to use design tokens (`var(--*)`) instead of raw hardcoded values like `#fff` or `16px`. (Exits 1 if violations found). |
| `lint-url-version.sh` | Batch scanner that flags API version strings hardcoded into URL paths. (Exits 1 if violations found). |

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
