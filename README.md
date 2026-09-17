# code-quality

A flat, zero-dependency suite of deterministic runtime steering guards and batch linters for autonomous LLM coding agents and software repositories.

Every file is an independent, hermetic POSIX executable. No file imports or sources another, no per-repository configuration is required, and all validation dictionaries and predicates live inline. Use any script standalone or wire them individually into agent runtimes (Claude Code, Cursor, Codex) and Git lifecycle hooks.

---

## Invariant Catalog

| File | Type | Steering Dimension / Scientific Invariant | Contract |
| :--- | :--- | :--- | :--- |
| `guard-banned-words.sh` | Author-time Guard | **Lexical Space Projection**: Enforces vocabulary mapping onto RFC 7231 / RFC 3986 / Apple HIG ontologies; projects out framework jargon (`navbar` → `nav`, `modal` → `dialog`, `card` → `row`, `hero` → `header`). | Exit 2 on violation; blocks pre-execution tool payload. |
| `guard-bash-write.sh` | Command Guard | **Out-of-Band State Mutation Suppression**: Intercepts shell redirect writes (`>`, `>>`) and in-place stream modifications (`sed -i`, `perl -i`, `awk -i`) to ensure file mutations remain within auditable tool boundaries. | Exit 2 on violation; blocks shell execution. |
| `guard-cloudflare-kv.sh` | Author-time Guard | **Unbounded Resource-Sink Mitigation**: Statically rejects runtime bindings and API invocations for write-amplified storage to prevent runaway agentic billing loops. | Exit 2 on violation; outputs cost diagnostic to stderr. |
| `guard-deploy-push.sh` | Command Guard | **Production Deployment Invariants**: Enforces upstream tracking synchronization and working-tree cleanliness before release execution; permits pre-production environments. | Exit 2 on unpushed or dirty working tree. |
| `guard-diff-size.sh` | Command Guard | **Generative Trajectory Drift Regularization**: Bounds total line-delta entropy on active feature branches to prevent monolithic agent rollouts. | Exit 2 if branch diff exceeds budget. |
| `guard-direct-style.sh` | Author-time Guard | **Imperative DOM Mutation Suppression**: Blocks imperative element style mutations (`element.style.x =`) in favor of declarative token-driven styling. | Exit 2 on direct style property assignment. |
| `guard-function-size.sh` | Author-time Guard | **Cognitive & Cyclomatic Complexity Ceiling**: Hard upper bound of 50 lines per function block, preventing agentic generation of monolithic procedures. | Exit 2 if function block length > 50 lines. |
| `guard-max-lines.sh` | Author-time Guard | **Context-Window Saturation Bound**: Imposes a strict 300-line ceiling per file, bounding cognitive complexity and downstream LLM context consumption. | Exit 2 if target file exceeds 300 lines. |
| `guard-morpheme-max.sh` | Author-time Guard | **Morphological Sparsity Ceiling**: Constrains identifier stems to $k \le 3$ morphemes; prevents multi-word token explosion and naming drift. | Exit 2 if basename or export > 3 morphemes. |
| `guard-name-words.sh` | Creation Guard | **Lexical Parsimony Ladder**: Author-time advisory check on new file creation; reinforces single-word stem preference ($k=1$). | Exit 0 with diagnostic advisory on stdout/stderr. |
| `guard-pull-request.sh` | Command Guard | **Falsifiable Task-Completion Verification**: Rejects `gh pr create` actions lacking Markdown task checkboxes (`- [ ]` / `- [x]`), forcing agent self-verification against explicit acceptance criteria. | Exit 2 if PR description lacks criteria checkboxes. |
| `guard-push-main.sh` | Command Guard | **Default Branch Invariant Protection**: Blocks direct `git push` to protected default branches (`main`, `master`), enforcing branch-isolation workflows. | Exit 2 if push targets default branch. |
| `guard-url-version.sh` | Author-time Guard | **Protocol Versioning Conformance**: Restricts API versioning to HTTP content negotiation headers (`Accept-Version`), rejecting URI path pollution (`/v1/`). | Exit 2 if URL path contains version tokens. |
| `hook-post-edit.sh` | Runtime Dispatcher | **PostToolUse Advisory Feedback**: Dispatches fast batch linters immediately following file modifications; feeds advisory diagnostics back to the agent without blocking. | Exit 0 with diagnostic advisory. |
| `hook-pre-commit.sh` | Git Dispatcher | **Diff-Aware Commit Boundary Gate**: Executes line-level invariant checks on staged changes; blocks regressions while preventing legacy technical debt deadlock. | Exit 1 on staged violations; blocks git commit. |
| `hook-pre-tool.sh` | Runtime Dispatcher | **PreToolUse Policy Interceptor**: Intercepts proposed agent tool calls (`Write`, `Edit`, `Bash`) and executes matching guards before disk state transition occurs. | Exit 2 on invariant violation; passes stderr to context. |
| `lint-banned-words.sh` | Batch Linter | **Global Lexical Space Auditor**: Batch static analysis scanning tracked source files for out-of-distribution framework jargon and anti-patterns. | Exit 1 on detected violations. |
| `lint-dead-imports.sh` | Batch Linter | **Static Dependency Graph Integrity**: Validates all relative module import specifiers, identifying dangling references or missing targets. | Exit 1 on broken relative import paths. |
| `lint-important-css.sh` | Batch Linter | **Cascade Determinism Enforcement**: Flags and rejects `!important` declarations to eliminate specificity escalation battles. | Exit 1 on `!important` occurrences. |
| `lint-max-lines.sh` | Batch Linter | **Batch Context-Length Auditor**: Scans the repository for files exceeding the 300-line ceiling. | Exit 1 if any file exceeds limit. |
| `lint-morpheme-max.sh` | Batch Linter | **Batch Morphological Auditor**: Scans repository files and exported identifiers for violations of the 3-morpheme ceiling. | Exit 1 if violations found. |
| `lint-naming.sh` | Branch Linter | **Lexical Distribution Mode Verification**: Evaluates the statistical distribution of added file names; guarantees 3-word identifiers do not form the mode. | Exit 1 if 3-word names are strictly the mode. |
| `lint-token-required.sh` | Batch Linter | **Design Token Structural Indirection**: Verifies that color, size, weight, and opacity values reference CSS custom properties (`var(--*)`) rather than raw literals. | Exit 1 on raw styling literals. |
| `lint-url-version.sh` | Batch Linter | **Batch URI Architecture Validator**: Scans source files for hardcoded version strings inside URL paths. | Exit 1 if URI versions detected. |

---

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
