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

## Benefit & Utility: Runtime Steering for LLM Agents

Autonomous Large Language Model agents write computer code quickly, but they suffer from **lexical drift**, **architectural entropy**, and **autoregressive error propagation**. When an agent makes a mistake early in a task, it builds more broken code on top of that mistake.

This repository provides a **deterministic runtime steering harness** that intercepts agent actions before they touch your disk:
- **How it intercepts**: When an agent proposes a tool call (such as an `Edit` writing `UserProfileModal`), the `PreToolUse` hook passes the proposed text to matching guards. If the code breaks a rule, the guard blocks execution with exit code 2 and outputs a single-line reason to `stderr`.
- **How the agent self-corrects**: The diagnostic message enters the agent's context window. The agent reads the exact rule violation and repairs its code in the next turn (e.g., rewriting it to use `<dialog>`).
- **Why this saves tokens**: Traditional linters run late in CI. When late tests fail, an agent burns large amounts of your token budget inspecting git diffs and rewriting multiple files. This harness forces instant zero-shot correction at $t=0$ before disk state mutation.
- **Stateless Hermeticity**: Every script is an independent, pure POSIX shell executable with zero external dependencies, running identically across Claude Code, Cursor, Codex, and Git pre-commit.

---

## Rules

| File | Description |
|---|---|
| `guard-banned-words.sh` | **Lexical Space Projection**: Author-time blocking guard enforcing RFC 7231, RFC 3986, and Apple Human Interface Guidelines (HIG) semantic and ARIA terms over framework jargon. Example: when an agent writes `UserProfileModal` or `<div class="card">`, it is blocked with exit 2, forcing immediate self-correction to native `<dialog>` or `row`. |
| `guard-bash-write.sh` | **Out-of-Band State Mutation Suppression**: Command guard blocking shell writes. Example: when an agent attempts `cat <<EOF > file` or `sed -i` to bypass author-time hooks, the command is blocked with exit 2, forcing the agent through auditable `Write`/`Edit` tool APIs. |
| `guard-cloudflare-kv.sh` | **Unbounded Resource-Sink Mitigation**: Author-time guard banning Cloudflare Workers KV bindings (`[[kv_namespaces]]`) and runtime calls (`.get()`, `.put()`). Example: catches and blocks an agent adding KV storage to a worker before runaway write costs ($5/1M writes) occur (exit 2). |
| `guard-deploy-push.sh` | **Production Deployment Invariants**: Release guard blocking production deploys from dirty or unpushed trees. Example: blocks an agent running `wrangler deploy` while local feature commits are unpushed, while allowing named preview environments (`--env staging`) (exit 2). |
| `guard-diff-size.sh` | **Generative Trajectory Drift Regularization**: Bounds total line-delta entropy on active feature branches. Example: blocks an agent when a single feature branch attempts a monolithic 500-line rewrite, forcing smaller, verifiable review increments (exit 2). |
| `guard-direct-style.sh` | **Imperative DOM Mutation Suppression**: Blocks direct JS style mutations (`element.style.x =`). Example: catches an agent writing `el.style.display = "none"`, forcing declarative CSS classes, data attributes, or design tokens instead (exit 2). |
| `guard-function-size.sh` | **Cognitive & Cyclomatic Complexity Ceiling**: Enforces a 50-line maximum per function. Example: halts an agent writing a sprawling 80-line helper, forcing decomposition into short, single-purpose functions (exit 2). |
| `guard-max-lines.sh` | **Context-Window Saturation Bound**: Enforces a 300-line ceiling per file. Example: rejects an agent write that would push a file to 350 lines, keeping files within a single cognitive window and preventing context bloat (exit 2). |
| `guard-morpheme-max.sh` | **Morphological Sparsity Ceiling**: Limits file basenames, functions, and config keys to 3 morphemes (split on `-` or `_`). Example: blocks `render-user-profile-header-card.tsx` (5 morphemes) at author time, while exempting uppercase ENV_VARS (exit 2). |
| `guard-name-words.sh` | **Lexical Parsimony Ladder**: Author-time ladder for new files (1 word preferred, 2 fine, 3 announced). Example: when an agent creates `user-menu-list.ts` (3 words), it emits an advisory warning to encourage simpler naming (exit 0). |
| `guard-pull-request.sh` | **Falsifiable Task-Completion Verification**: Command guard on `gh pr create`. Example: blocks an agent opening a PR with a vague text summary, requiring at least one task-list checkbox (`- [ ]`) defining falsifiable acceptance criteria (exit 2). |
| `guard-push-main.sh` | **Default Branch Invariant Protection**: Command guard on `git push`. Example: blocks an agent running `git push origin main`, forcing the agent to push a feature branch and open a pull request instead (exit 2). |
| `guard-url-version.sh` | **Protocol Versioning Conformance**: Enforces API versions in HTTP content negotiation headers (`Accept-Version`), never URL paths. Example: blocks an agent writing `/api/v1/users` or `?version=2`, keeping URLs version-free (exit 2). |
| `hook-post-edit.sh` | **PostToolUse Advisory Feedback**: Runtime dispatcher running fast linters on saved files. Example: after an agent saves a file, it reports styling and naming advisories directly into the context window without blocking execution (exit 0). |
| `hook-pre-commit.sh` | **Diff-Aware Commit Boundary Gate**: Pre-commit hook checking staged diffs for banned terms, raw styles, and length limits. Example: blocks `git commit` if the staged changes introduce a banned word, while ignoring pre-existing violations in legacy code (exit 1). |
| `hook-pre-tool.sh` | **PreToolUse Policy Interceptor**: Agent middleware intercepting `Write`, `Edit`, and `Bash` tool payloads. Example: inspects proposed file content in memory and executes matching guards before any byte is written to disk (exit 2). |
| `lint-banned-words.sh` | **Global Lexical Space Auditor**: Batch static analysis checking whole codebases against RFC 7231, RFC 3986, and Apple HIG terms. Example: scans repository files in CI and flags all occurrences of component jargon like `Sidebar` or `Modal` (exit 1). |
| `lint-dead-imports.sh` | **Static Dependency Graph Integrity**: Batch import validator. Example: parses all relative `./` and `../` imports across TypeScript/JS files and reports any import pointing to a missing or deleted file (exit 1). |
| `lint-important-css.sh` | **Cascade Determinism Enforcement**: Batch stylesheet linter banning `!important`. Example: scans CSS and styled-components, failing the build if `!important` is used to override specificity (exit 1). |
| `lint-max-lines.sh` | **Batch Context-Length Auditor**: Scans the whole repository for oversized files. Example: reports every source file exceeding the 300-line limit to maintain clean modular boundaries (exit 1). |
| `lint-morpheme-max.sh` | **Batch Morphological Auditor**: Scans files and exported functions for compound naming bloat. Example: flags any exported function with 4+ morphemes across the codebase (exit 1). |
| `lint-naming.sh` | **Lexical Distribution Mode Verification**: Branch-level statistical distribution check. Example: ensures that 3-word file names do not become the most common naming pattern among files added by a feature branch (exit 1). |
| `lint-token-required.sh` | **Design Token Structural Indirection**: Enforces design token usage. Example: flags raw color `#1a1a1a` or spacing `16px`, requiring tokens like `var(--color-bg)` and `var(--space-md)` (exit 1). |
| `lint-url-version.sh` | **Batch URI Architecture Validator**: Batch scanner for URL versioning anti-patterns. Example: scans API clients and routes, reporting any URL paths containing `/v1/` or `/v2/` (exit 1). |

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
