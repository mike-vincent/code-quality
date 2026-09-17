# code-quality

A flat, zero-dependency suite of deterministic runtime steering guards and batch linters for autonomous LLM coding agents and software repositories.

Every file is an independent, hermetic POSIX executable. No file imports or sources another, no per-repository configuration is required, and all validation dictionaries and predicates live inline. Use any script standalone or wire them individually into agent runtimes (Claude Code, Cursor, Codex) and Git lifecycle hooks.

---

## Invariant Catalog

| File | Type | Scientific Invariant & Plain-English Explanation | Contract |
| :--- | :--- | :--- | :--- |
| `guard-banned-words.sh` | Author-time Guard | **Lexical Space Projection**<br>Stops the AI from using confusing UI jargon like `navbar`, `modal`, `card`, or `hero`. Forces the agent to use standard HTML words like `<nav>`, `<dialog>`, `row`, and `<header>`. | Exit 2 on violation; blocks tool payload. |
| `guard-bash-write.sh` | Command Guard | **Out-of-Band State Mutation Suppression**<br>Stops the AI from using shell commands like `sed -i` or redirects (`>`) to edit files. Forces the agent to use standard file tools so every change is tracked. | Exit 2 on violation; blocks shell execution. |
| `guard-cloudflare-kv.sh` | Author-time Guard | **Unbounded Resource-Sink Mitigation**<br>Blocks the use of Cloudflare Workers KV storage. Cloudflare charges money for every write, so this stops the AI from creating expensive billing loops. | Exit 2 on violation; outputs cost diagnostic to stderr. |
| `guard-deploy-push.sh` | Command Guard | **Production Deployment Invariants**<br>Stops the AI from releasing uncommitted or unpushed code to production. All changes must be committed and pushed to the main branch first. | Exit 2 on unpushed or dirty working tree. |
| `guard-diff-size.sh` | Command Guard | **Generative Trajectory Drift Regularization**<br>Stops the AI agent from changing too many lines on one branch. It forces the agent to make small, clear steps instead of one giant rewrite. | Exit 2 if branch diff exceeds budget. |
| `guard-direct-style.sh` | Author-time Guard | **Imperative DOM Mutation Suppression**<br>Blocks code that changes styles directly with JavaScript (`element.style.x =`). Forces the code to use clean CSS classes and design tokens instead. | Exit 2 on direct style property assignment. |
| `guard-function-size.sh` | Author-time Guard | **Cognitive & Cyclomatic Complexity Ceiling**<br>Blocks functions that are longer than 50 lines. This keeps every function short, simple, and easy to test. | Exit 2 if function block length > 50 lines. |
| `guard-max-lines.sh` | Author-time Guard | **Context-Window Saturation Bound**<br>Blocks any file that grows beyond 300 lines. Short files fit easily into the AI model's memory and keep code organized. | Exit 2 if target file exceeds 300 lines. |
| `guard-morpheme-max.sh` | Author-time Guard | **Morphological Sparsity Ceiling**<br>Limits file names and exported function names to at most three words. Prevents the AI from creating overly long, complex names. | Exit 2 if basename or export > 3 morphemes. |
| `guard-name-words.sh` | Creation Guard | **Lexical Parsimony Ladder**<br>Warns authors when they create new files with multi-word names. Reinforces that one-word names are best and two words are fine. | Exit 0 with diagnostic advisory on stdout/stderr. |
| `guard-pull-request.sh` | Command Guard | **Falsifiable Task-Completion Verification**<br>Rejects pull requests that do not have a task checklist (`- [ ]`). Forces the AI or developer to state clearly what done means. | Exit 2 if PR description lacks criteria checkboxes. |
| `guard-push-main.sh` | Command Guard | **Default Branch Invariant Protection**<br>Blocks direct pushes to `main` or `master`. Forces developers and agents to use a branch and open a pull request. | Exit 2 if push targets default branch. |
| `guard-url-version.sh` | Author-time Guard | **Protocol Versioning Conformance**<br>Blocks API version numbers inside URL paths like `/v1/`. Requires version numbers to live cleanly in HTTP headers instead. | Exit 2 if URL path contains version tokens. |
| `hook-post-edit.sh` | Runtime Dispatcher | **PostToolUse Advisory Feedback**<br>Runs quick checks right after a file is edited. Gives the AI helpful advice on save without stopping its work. | Exit 0 with diagnostic advisory. |
| `hook-pre-commit.sh` | Git Dispatcher | **Diff-Aware Commit Boundary Gate**<br>Runs checks on staged Git files before you commit. Blocks new errors without breaking older legacy code. | Exit 1 on staged violations; blocks git commit. |
| `hook-pre-tool.sh` | Runtime Dispatcher | **PreToolUse Policy Interceptor**<br>Catches AI tool calls before they touch your disk. If a rule is broken, it stops the write and tells the AI why. | Exit 2 on invariant violation; passes stderr to context. |
| `lint-banned-words.sh` | Batch Linter | **Global Lexical Space Auditor**<br>Scans the whole project for banned UI framework words. Reports all files that need cleaner, standard terms. | Exit 1 on detected violations. |
| `lint-dead-imports.sh` | Batch Linter | **Static Dependency Graph Integrity**<br>Scans files for broken relative imports. Finds any import statement pointing to a file that does not exist. | Exit 1 on broken relative import paths. |
| `lint-important-css.sh` | Batch Linter | **Cascade Determinism Enforcement**<br>Scans style files and bans `!important`. Forces CSS styles to follow natural browser rules instead of forcing overrides. | Exit 1 on `!important` occurrences. |
| `lint-max-lines.sh` | Batch Linter | **Batch Context-Length Auditor**<br>Scans all files across the project. Flags any file that has grown beyond the 300-line limit. | Exit 1 if any file exceeds limit. |
| `lint-morpheme-max.sh` | Batch Linter | **Batch Morphological Auditor**<br>Scans all files and exports across the project. Flags any name that contains four or more words. | Exit 1 if violations found. |
| `lint-naming.sh` | Branch Linter | **Lexical Distribution Mode Verification**<br>Checks all files added by a branch. Ensures that three-word names do not become the most common naming pattern. | Exit 1 if 3-word names are strictly the mode. |
| `lint-token-required.sh` | Batch Linter | **Design Token Structural Indirection**<br>Ensures all CSS values use design tokens like `var(--*)`. Flags any hardcoded raw values like `#fff` or `16px`. | Exit 1 on raw styling literals. |
| `lint-url-version.sh` | Batch Linter | **Batch URI Architecture Validator**<br>Scans the project for version numbers hardcoded in URLs. Flags API routes using `/v1/` or `?version=`. | Exit 1 if URI versions detected. |

---

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

## Execution & Usage

Every script is an independent executable. Run any guard or linter directly from your shell:

```sh
# Author-time guard (evaluates a proposed file mutation)
./guard-max-lines.sh src/index.ts
./guard-banned-words.sh src/components/button.tsx
./guard-cloudflare-kv.sh wrangler.toml

# Command guard (evaluates a proposed shell execution payload)
./guard-push-main.sh "git push origin main"
./guard-pull-request.sh "gh pr create --title 'Fix' --body 'No checklist'"

# Batch linters (evaluates workspace or diff state)
./lint-banned-words.sh
./lint-token-required.sh
./lint-naming.sh
```

### Agent Steering Integration

To wire deterministic runtime steering into autonomous LLM agents:

- **Claude Code (`~/.claude/settings.json`)**:
  ```json
  {
    "hooks": {
      "PreToolUse": [{ "matcher": "Edit|Write|Bash", "hooks": [{ "type": "command", "command": "/path/to/hook-pre-tool.sh" }] }],
      "PostToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "/path/to/hook-post-edit.sh" }] }]
    }
  }
  ```
- **Git (`.git/hooks/pre-commit`)**:
  ```sh
  exec "/path/to/code-quality/hook-pre-commit.sh"
  ```

---

## License

[MIT](LICENSE) © 2026 Mike Vincent
