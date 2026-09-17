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
| `guard-banned-words.sh` | **Lexical Space Projection**: Stops the AI from using confusing UI jargon like `navbar`, `modal`, `card`, or `hero`. Forces the agent to use standard HTML words like `<nav>`, `<dialog>`, `row`, and `<header>`. |
| `guard-bash-write.sh` | **Out-of-Band State Mutation Suppression**: Stops the AI from using shell commands like `sed -i` or redirects (`>`) to edit files. Forces the agent to use standard file tools so every change is tracked. |
| `guard-cloudflare-kv.sh` | **Unbounded Resource-Sink Mitigation**: Blocks the use of Cloudflare Workers KV storage. Cloudflare charges money for every write, so this stops the AI from creating expensive billing loops. |
| `guard-deploy-push.sh` | **Production Deployment Invariants**: Stops the AI from releasing uncommitted or unpushed code to production. All changes must be committed and pushed to the main branch first. |
| `guard-diff-size.sh` | **Generative Trajectory Drift Regularization**: Stops the AI agent from changing too many lines on one branch. Forces small, safe steps instead of one giant rewrite. |
| `guard-direct-style.sh` | **Imperative DOM Mutation Suppression**: Blocks code that changes styles directly with JavaScript (`element.style.x =`). Forces the code to use clean CSS classes and design tokens instead. |
| `guard-function-size.sh` | **Cognitive & Cyclomatic Complexity Ceiling**: Blocks functions that are longer than 50 lines. Keeps every function short, simple, and easy to test. |
| `guard-max-lines.sh` | **Context-Window Saturation Bound**: Blocks any file that grows beyond 300 lines. Short files fit easily into the AI model's memory and keep code organized. |
| `guard-morpheme-max.sh` | **Morphological Sparsity Ceiling**: Limits file names and exported function names to at most three words. Prevents the AI from creating overly long, complex names. |
| `guard-name-words.sh` | **Lexical Parsimony Ladder**: Warns authors when they create new files with multi-word names. Reinforces that one-word names are best and two words are fine. |
| `guard-pull-request.sh` | **Falsifiable Task-Completion Verification**: Rejects pull requests that do not have a task checklist (`- [ ]`). Forces the AI or developer to state clearly what done means. |
| `guard-push-main.sh` | **Default Branch Invariant Protection**: Blocks direct pushes to `main` or `master`. Forces developers and agents to use a branch and open a pull request. |
| `guard-url-version.sh` | **Protocol Versioning Conformance**: Blocks API version numbers inside URL paths like `/v1/`. Requires version numbers to live cleanly in HTTP headers instead. |
| `hook-post-edit.sh` | **PostToolUse Advisory Feedback**: Runs quick checks right after a file is edited. Gives the AI helpful advice on save without stopping its work. |
| `hook-pre-commit.sh` | **Diff-Aware Commit Boundary Gate**: Runs checks on staged Git files before you commit. Blocks new errors without breaking older legacy code. |
| `hook-pre-tool.sh` | **PreToolUse Policy Interceptor**: Catches AI tool calls before they touch your disk. If a rule is broken, it stops the write and tells the AI why. |
| `lint-banned-words.sh` | **Global Lexical Space Auditor**: Scans the whole project for banned UI framework words. Reports all files that need cleaner, standard terms. |
| `lint-dead-imports.sh` | **Static Dependency Graph Integrity**: Scans files for broken relative imports. Finds any import statement pointing to a file that does not exist. |
| `lint-important-css.sh` | **Cascade Determinism Enforcement**: Scans style files and bans `!important`. Forces CSS styles to follow natural browser rules instead of forcing overrides. |
| `lint-max-lines.sh` | **Batch Context-Length Auditor**: Scans all files across the project. Flags any file that has grown beyond the 300-line limit. |
| `lint-morpheme-max.sh` | **Batch Morphological Auditor**: Scans all files and exports across the project. Flags any name that contains four or more words. |
| `lint-naming.sh` | **Lexical Distribution Mode Verification**: Checks all files added by a branch. Ensures that three-word names do not become the most common naming pattern. |
| `lint-token-required.sh` | **Design Token Structural Indirection**: Ensures all CSS values use design tokens like `var(--*)`. Flags any hardcoded raw values like `#fff` or `16px`. |
| `lint-url-version.sh` | **Batch URI Architecture Validator**: Scans the project for version numbers hardcoded in URLs. Flags API routes using `/v1/` or `?version=`. |

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
