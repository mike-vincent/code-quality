# code-quality

A collection of independent, self-contained code-quality guards and linters.

Every file here is completely standalone. There are no shared dependencies, no per-repo configuration files, no allowlists, and no file imports another. The rule, its logic, and its data live entirely within the same file.

Use any single file a la carte, copy what you need into your project, or run them directly.

---

## Design Principles

- **Independent.** Every script stands alone. You can use one without adopting any other.
- **Self-contained.** Each script carries its own data inline. No imports, no libraries.
- **Flat.** No subdirectories. One file per rule.
- **Universal.** No per-repo configuration. The rule enforces the same standard everywhere.

---

## Two Verbs

- `guard-*`: Author-time gate for a single file or command.
  - `exit 0`: Clean (or advisory pass-through).
  - `exit 2`: Hard block with a single-line explanation on `stderr`.
- `lint-*`: Batch checker for a whole directory or branch.
  - `exit 0`: Clean.
  - `exit 1`: Violations found.

---

## Independent Usage

Run any script directly from your terminal against a file or project:

```sh
# Check a single file with a guard
./guard-max-lines.sh path/to/file.ts
./guard-cloudflare-kv.sh wrangler.toml
./guard-banned-words.sh src/button.tsx

# Run a batch linter across the current directory
./lint-max-lines.sh
./lint-banned-words.sh
./lint-token-required.sh
./lint-important-css.sh
./lint-naming.sh
```

---

## Catalog of Rules

### Vocabulary & Naming
| File | Scope | Enforces |
|---|---|---|
| `guard-banned-words.sh` | Single file | Enforces RFC 7231 / 3986 / Apple HIG terms; blocks UI framework jargon (`navbar` → `nav`, `modal` → `dialog`, `card` → `row`, `hero` → `header`). |
| `lint-banned-words.sh` | Batch | Batch counterpart to `guard-banned-words.sh`. |
| `guard-name-words.sh` | Single file | Naming ladder for new files: 1 word preferred, 2 fine, 3 announced. |
| `guard-morpheme-max.sh` | Single file | Hard ceiling: file basenames and exported functions cannot exceed 3 morphemes. |
| `lint-morpheme-max.sh` | Batch | Batch counterpart checking file names and exports. |
| `lint-naming.sh` | Branch | 3-word names must not be the mode among the files a branch adds. |

### Size & Complexity Limits
| File | Scope | Enforces |
|---|---|---|
| `guard-max-lines.sh` | Single file | Hard ceiling of 300 lines per file. |
| `lint-max-lines.sh` | Batch | Batch counterpart reporting all files exceeding 300 lines. |
| `guard-function-size.sh` | Single file | Hard ceiling of 50 lines per function. |
| `guard-diff-size.sh` | Branch | Bounds the line delta of an active feature branch. |

### CSS & Styling
| File | Scope | Enforces |
|---|---|---|
| `guard-direct-style.sh` | Single file | Blocks direct inline style mutations (`element.style.x =`). |
| `lint-token-required.sh` | Batch | Style properties must reference a design token (`var(--*)`), never raw literals. |
| `lint-important-css.sh` | Batch | Blocks `!important` declarations to prevent CSS specificity wars. |

### Resource & Financial Safety
| File | Scope | Enforces |
|---|---|---|
| `guard-cloudflare-kv.sh` | Single file | Blocks Cloudflare KV bindings and API usage to prevent runaway write billing loops. |
| `guard-url-version.sh` | Single file | API versions belong in HTTP headers (`Accept-Version`), never in URL paths (`/v1/`). |
| `lint-url-version.sh` | Batch | Batch counterpart checking for versioned URL patterns. |
| `guard-bash-write.sh` | Command | Blocks writing files via unsafe bash redirects and in-place replacements. |

### Git & Release Safety
| File | Scope | Enforces |
|---|---|---|
| `guard-push-main.sh` | Command | Blocks direct `git push` to `main` or `master`. |
| `guard-deploy-push.sh` | Command | Blocks production deployments from dirty or unpushed branches. |
| `guard-pull-request.sh` | Command | Requires pull request descriptions to include at least one acceptance criteria checkbox (`- [ ]`). |
| `lint-dead-imports.sh` | Batch | Detects broken relative imports across TypeScript and JavaScript files. |

---

## Hook & Dispatcher Integration (Optional)

If you use AI coding agents (Claude Code, Cursor, Codex) or Git hooks, you can wire individual guards into lifecycle events:

- **Author-Time (PreToolUse):** `hook-pre-tool.sh` intercepts tool calls before writing to disk.
- **Save-Time (PostToolUse):** `hook-post-edit.sh` runs advisory checks after an edit.
- **Commit-Time:** `hook-pre-commit.sh` runs as a standard git pre-commit hook.

You can also cherry-pick any individual guard script and invoke it directly from your `.git/hooks/pre-commit` or CI configuration without using the dispatchers.

---

## License

[MIT](LICENSE) © 2026 Mike Vincent
