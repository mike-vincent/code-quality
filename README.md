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

## Rules

| File | Enforces |
|---|---|
| `guard-banned-words.sh` / `lint-banned-words.sh` | RFC 7231 / 3986 / HIG terms; no framework jargon |
| `guard-morpheme-max.sh` / `lint-morpheme-max.sh` | 3-word ceiling (owns the 4+ block) |
| `guard-name-words.sh` | the ladder: 1 preferred, 2 fine, 3 announced. Advisory only |
| `lint-naming.sh` | 3-word names must not be the mode among the files a branch adds |
| `guard-max-lines.sh` / `lint-max-lines.sh` | 300-line ceiling |
| `guard-function-size.sh` | 50-line single-function ceiling |
| `guard-diff-size.sh` | bounds diff size on active feature branches |
| `guard-direct-style.sh` | no `element.style.x =` mutation |
| `guard-cloudflare-kv.sh` | no Cloudflare KV (cost / billing) |
| `guard-url-version.sh` / `lint-url-version.sh` | API versions belong in HTTP headers, never in URLs |
| `guard-bash-write.sh` | blocks file writing via unsafe bash redirects/in-place edits |
| `lint-token-required.sh` | style values must be `var(--*)`, not raw literals |
| `lint-important-css.sh` | no `!important` |
| `lint-dead-imports.sh` | no broken relative imports |
| `guard-push-main.sh` | no direct push to the default branch |
| `guard-deploy-push.sh` | no deploy from a dirty / unpushed tree |
| `guard-pull-request.sh` | PR body must carry an acceptance-criteria checkbox |

## Install

```sh
/path/to/code-quality/install-code-quality.sh /path/to/your-repo
```

Wires the git pre-commit gate and prints the agent-settings snippets for
the author-time and edit-time stages. Delete the repo's local `lint-*.sh`
and `linters.json` afterward — this is the single source.

## License

[MIT](LICENSE) © 2026 Mike Vincent

