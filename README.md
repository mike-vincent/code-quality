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

Autonomous Large Language Model agents write computer code quickly.
However, agents often suffer from **lexical drift** and **architectural entropy**.
They create giant files, use confusing jargon, and cause **autoregressive error propagation**.

This repository provides **deterministic runtime steering** for coding agents:
- **Protects the Token Budget**: Blocks bad code before the write happens. The agent self-corrects in one turn without wasting prompt tokens on multi-file rollbacks.
- **Enforces Structural Invariants**: Sets hard mathematical limits ($k \le 3$ morphemes, 300 lines per file, 50 lines per function).
- **Stops Lexical Drift**: Forces models to use standard ontologies (RFC 7231, RFC 3986, Apple HIG) instead of hallucinated framework terms.
- **Mitigates Resource Sinks**: Prevents autonomous agents from entering runaway billing loops on write-amplified storage APIs like Cloudflare KV.
- **Stateless Hermeticity**: Each script is pure POSIX shell with zero external dependencies, running identically across Claude Code, Cursor, Codex, and CI.

---

## Example: Closed-Loop Agent Steering

Here is a real-world example of an autonomous LLM agent interacting with `guard-banned-words.sh` via the `hook-pre-tool.sh` interceptor:

### 1. Agent Action Proposal
The agent attempts to call its `Edit` tool with non-compliant framework jargon:

```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "src/components/profile.tsx",
    "new_string": "export function UserProfileModal() {\n  return <div className=\"modal\">Profile</div>;\n}"
  }
}
```

### 2. PreToolUse Interception & Rejection
`hook-pre-tool.sh` catches the tool payload before disk state mutation. It runs `guard-banned-words.sh` on the proposed text buffer.

The guard aborts execution with **exit code 2** and prints to `stderr`:
```text
BANNED WORD: modal (use dialog) at src/components/profile.tsx:1
Cardinal rule: shared architecture uses RFC 7231 / RFC 3986 / Apple HIG terms, never domain nouns or framework jargon.
```

### 3. In-Context Self-Correction
The diagnostic error message is injected directly into the LLM context window. The agent conditions on the rule violation and emits a corrected tool call in the next turn:

```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "src/components/profile.tsx",
    "new_string": "export function UserProfileDialog() {\n  return <dialog className=\"user-dialog\">Profile</dialog>;\n}"
  }
}
```

The guard evaluates the repaired payload, returns **exit code 0**, and allows the state mutation to complete.

---

## Rules

| File | Description |
|---|---|
| `guard-banned-words.sh` | **Lexical Space Projection**: Author-time blocking guard enforcing RFC 7231, RFC 3986, and Apple Human Interface Guidelines (HIG) semantic and ARIA terms. Projects out framework jargon (e.g., `navbar` → `nav`, `sidebar` → `aside`, `modal`/`popup` → `dialog`, `card` → `row`, `hero` → `header`, `shelf` → `section`, `feed` → `list`). Stops LLMs from hallucinating non-standard UI component names before writing to disk (exit 2). |
| `guard-bash-write.sh` | **Out-of-Band State Mutation Suppression**: Command-line execution guard intercepting unsafe shell redirections (`>`, `>>`) and in-place stream modifications (`sed -i`, `perl -i`, `awk -i`). Forces agents to use audited tool APIs (`Write`, `Edit`) rather than bypassing author-time guards through raw terminal writes (exit 2). |
| `guard-cloudflare-kv.sh` | **Unbounded Resource-Sink Mitigation**: Author-time blocking guard that rejects Cloudflare Workers KV namespace bindings (`[[kv_namespaces]]`) and runtime API invocations (`.get()`, `.put()`, `.delete()`). Prevents runaway agentic billing loops caused by write-amplified storage ($5/million writes) (exit 2). |
| `guard-deploy-push.sh` | **Production Deployment Invariants**: Release command guard blocking production deploys from dirty working trees, non-default branches, or local commits ahead of upstream. Allows named non-production environments (`--env staging`, `deploy:preview`) while guaranteeing what ships matches audited version control (exit 2). |
| `guard-diff-size.sh` | **Generative Trajectory Drift Regularization**: Branch-level boundary guard that bounds total line-delta entropy on active feature branches. Prevents autonomous agents from runaway generative rewrites, forcing incremental, reviewable commits (exit 2). |
| `guard-direct-style.sh` | **Imperative DOM Mutation Suppression**: Author-time guard banning direct JavaScript style property mutations (`element.style.x =`). Mandates declarative CSS classes, data attributes, and CSS custom properties (`var(--*)`) to preserve style encapsulation and prevent specificity drift (exit 2). |
| `guard-function-size.sh` | **Cognitive & Cyclomatic Complexity Ceiling**: Author-time structural guard enforcing a hard ceiling of 50 lines per function block. Prevents LLMs from generating monolithic procedures, forcing modular decomposition and clean unit testability (exit 2). |
| `guard-max-lines.sh` | **Context-Window Saturation Bound**: Author-time structural guard enforcing a hard ceiling of 300 lines per file. Keeps files within a single cognitive horizon, preventing context-window pollution and attention degradation in downstream agent sessions (exit 2). |
| `guard-morpheme-max.sh` | **Morphological Sparsity Ceiling**: Author-time structural guard limiting file basenames, exported functions, and config keys to at most 3 morpheme word units (split on `-` or `_`). Exempts standard uppercase environment variables while stopping LLM compound-naming bloat (exit 2). |
| `guard-name-words.sh` | **Lexical Parsimony Ladder**: Author-time creation guard enforcing the naming ladder for new files: 1 word preferred, 2 fine, 3 announced. Emits an advisory on stdout/stderr when a 3-word name is introduced to guide agent self-correction before committing (exit 0). |
| `guard-pull-request.sh` | **Falsifiable Task-Completion Verification**: Pull request command guard inspecting `gh pr create` and `gh pr edit`. Requires the PR description to include at least one Markdown task checkbox (`- [ ]` or `- [x]`), ensuring agents state falsifiable acceptance criteria for what "done" means (exit 2). |
| `guard-push-main.sh` | **Default Branch Invariant Protection**: Git command guard intercepting `git push` commands targeting default branches (`main`, `master`). Forces human developers and autonomous agents to work on feature branches and submit pull requests (exit 2). |
| `guard-url-version.sh` | **Protocol Versioning Conformance**: Author-time guard enforcing the universal rule that API versioning belongs strictly in HTTP content negotiation headers (`Accept-Version`), never hardcoded in URL paths (`/v1/`) or query parameters (`?version=`) (exit 2). |
| `hook-post-edit.sh` | **PostToolUse Advisory Feedback**: Platform dispatcher wired into agent `PostToolUse` lifecycle events (e.g. Claude Code, Cursor). Immediately runs fast batch linters on saved files, feeding non-blocking advisory diagnostics directly into the agent's context window (exit 0). |
| `hook-pre-commit.sh` | **Diff-Aware Commit Boundary Gate**: Universal Git pre-commit hook that runs line-level checks (`lint-banned-words`, `lint-important-css`, `lint-token-required`) strictly on staged diffs. Blocks new invariant violations without causing legacy deadlocks on pre-existing code debt (exit 1). |
| `hook-pre-tool.sh` | **PreToolUse Policy Interceptor**: Author-time platform dispatcher wired into agent `PreToolUse` hooks (Claude Code, Cursor, Codex). Intercepts proposed `Edit`, `Write`, and `Bash` tool payloads, running corresponding file and command guards before disk state mutation occurs (exit 2). |
| `lint-banned-words.sh` | **Global Lexical Space Auditor**: Batch static analysis counterpart to `guard-banned-words.sh`. Scans tracked source code for banned framework jargon and anti-patterns, verifying adherence to RFC 7231, RFC 3986, and Apple HIG terminology across the entire codebase (exit 1). |
| `lint-dead-imports.sh` | **Static Dependency Graph Integrity**: Batch static analysis linter that validates all relative TypeScript and JavaScript module imports (`./`, `../`). Flags broken relative import paths and missing module targets across the repository (exit 1). |
| `lint-important-css.sh` | **Cascade Determinism Enforcement**: Batch stylesheet linter that strictly bans `!important` across CSS, SCSS, LESS, and CSS-in-JS templates. Preserves predictable cascade layers and eliminates CSS specificity escalation wars (exit 1). |
| `lint-max-lines.sh` | **Batch Context-Length Auditor**: Batch counterpart to `guard-max-lines.sh`. Scans all tracked text files across the project and reports every file that exceeds the 300-line ceiling (exit 1). |
| `lint-morpheme-max.sh` | **Batch Morphological Auditor**: Batch counterpart to `guard-morpheme-max.sh`. Scans all repository source files and exported function identifiers, reporting any names that exceed the 3-word morpheme ceiling (exit 1). |
| `lint-naming.sh` | **Lexical Distribution Mode Verification**: Statistical branch linter checking the word-count distribution (1, 2, 3 words) of all files added by a feature branch. Enforces that 3-word names must not be the statistical mode among added files (exit 1). |
| `lint-token-required.sh` | **Design Token Structural Indirection**: Batch style linter requiring all color, length, font-weight, and opacity declarations to reference CSS custom properties (`var(--*)`). Flags raw magic literals (`#fff`, `16px`, `rgb(...)`) to ensure 100% tokenized design systems (exit 1). |
| `lint-url-version.sh` | **Batch URI Architecture Validator**: Batch counterpart to `guard-url-version.sh`. Scans the codebase for hardcoded API versions embedded in URL strings, ensuring versioning remains in HTTP request headers (exit 1). |

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
