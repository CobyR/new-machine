# Decision Records

Why this repo is shaped the way it is. The [main README](../../README.md) covers
*what* it does and *how* to run it; these cover *why*, and what else was on the
table.

Each record is immutable once accepted. If a decision changes, add a new record
that supersedes the old one rather than editing history — the reasoning that led
to a since-abandoned choice is usually the most valuable part.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-numbered-idempotent-steps.md) | Numbered idempotent step scripts driven by one config file | Accepted |
| [0002](0002-winget-only.md) | winget as the only package manager | Accepted |
| [0003](0003-platform-neutral-core.md) | Platform-neutral data at the root, platform code at the edges | Accepted |
| [0004](0004-powershell-51-floor.md) | Windows PowerShell 5.1 is the compatibility floor | Accepted |
| [0005](0005-dotfiles-symlink-with-fallback.md) | Symlink dotfiles, fall back to copy, support export | Accepted |
| [0006](0006-ssh-commit-signing.md) | SSH commit signing rather than GPG | Accepted |
| [0007](0007-scoped-https-to-ssh-rewrite.md) | Rewrite HTTPS to SSH for our owners only | Accepted |
| [0008](0008-repo-sets.md) | Repos clone in named sets, explicit or dynamically resolved | Accepted |
| [0009](0009-projects-root-with-fallback.md) | Projects root defaults to `D:\projects` with a drive fallback | Accepted |
| [0010](0010-run-log.md) | Append-only JSONL run log, auto-committed and auto-pushed | Accepted |
| [0011](0011-obsidian-left-alone.md) | Don't touch Obsidian's config; Sync stays manual | Accepted |
| [0012](0012-testing-strategy.md) | Sandboxed self-test plus dry run, no VM or CI | Accepted |

## Format

Context (the forces at play) → Decision (what we're doing) → Alternatives
considered (what we didn't do, and why) → Consequences (what this costs us).
