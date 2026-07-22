# 0005 — Symlink dotfiles, fall back to copy, support export

**Status:** Accepted · 2026-07-22

## Context

Dotfiles split cleanly into two kinds, and they want opposite handling:

- **Files I hand-edit** — `.gitconfig`, the PowerShell profile, `starship.toml`.
  I want edits made on the machine to *be* edits to the repo, with no copy step
  to forget.
- **Files an application rewrites** — Windows Terminal's `settings.json`, VS
  Code's `settings.json`. These get rewritten wholesale whenever you change a
  setting in the GUI, so a symlink means the app silently dirties the repo every
  time you toggle anything.

Two Windows-specific complications:

- **Symlinks need privilege.** Creating one requires either admin or Developer
  Mode. Developer Mode is enabled by step 04 — which needs admin, and which runs
  *after* dotfiles in step order.
- **Symlink privilege is fixed at process launch.** Enabling Developer Mode
  doesn't grant it to already-running shells; the token is stamped when the
  process starts.

## Decision

Per-entry `mode` in `dotfiles/links.json`:

- `mode: "link"` — symlink. Edits on the machine are edits to the repo.
- `mode: "copy"` — copy, with `-Export` to pull machine-side changes back into
  the repo when you're ready.

Symlink capability is probed **once per run** (admin, or Developer Mode set in
`HKLM`). Without it, `link` entries degrade to copies with a warning naming the
fix. The bootstrap does not fail and does not silently do nothing.

Existing files are moved to `<file>.bak-<timestamp>` before replacement.
Idempotency is checked by resolving the existing symlink target, and by content
comparison for copies — so a second run reports skips.

## Alternatives considered

### Copy everything, always — rejected

Simplest, no privilege requirement, no fallback logic, works identically
everywhere. Rejected because it makes the repo lie by default: you edit
`~/.gitconfig`, the repo still has the old version, and you discover the drift on
the next machine when your alias is missing. The whole value proposition is that
the repo *is* the config.

### Symlink everything, always — rejected

Consistent and simple in the other direction. Rejected on the app-rewrite
problem: Windows Terminal rewrites `settings.json` on every settings change, so
`git status` is permanently dirty with changes you didn't consciously make, and
`git diff` becomes noise you learn to ignore. That's how you eventually commit
something you didn't mean to.

### Hardlinks — rejected

No privilege requirement, and edits propagate both ways. Rejected because they
break on the operation that matters most: an app that writes by
create-temp-then-rename (which is most of them, for atomicity) replaces the inode
and silently severs the link. You'd think it was working and it wouldn't be.
Also same-volume only.

### Junctions — rejected

Work without privilege, but directory-only. Most of these entries are individual
files in directories full of things that should *not* be in the repo
(`%APPDATA%\Code\User` also holds workspace state and caches).

### Require admin for the whole bootstrap — rejected

Removes the fallback path entirely and simplifies the step. Rejected because most
of the bootstrap deliberately doesn't need admin, and elevating everything means
package installs and `gh auth login` run elevated too. Narrow elevation, clearly
signposted, is better than blanket elevation.

### chezmoi / GNU Stow — seriously considered

Purpose-built. chezmoi in particular handles templating (per-machine values),
encryption for secrets, and cross-platform targets — all things this repo either
hand-rolls or does without.

Rejected on bootstrap grounds ([0002](0002-winget-only.md)): another tool to
install before the tool that installs tools. Also, `links.json` currently has
eight entries and the machine-specific piece (git identity) is handled by
generating `~/.gitconfig.local` from `config.json`, so the templating that
justifies chezmoi isn't needed yet. **This is the most likely decision to be
superseded** — if `dotfiles/` grows past ~20 entries or needs real per-machine
templating, chezmoi is the answer.

## Consequences

- **A symlinked dotfile is a write target for every tool that owns that path.**
  Link mode means "edits on the machine are edits to the repo" — and *any*
  writer counts, not just you in an editor. `~/.gitconfig` is a symlink to the
  tracked `dotfiles/git/gitconfig`, so `git config --global` in steps 03 and 04
  wrote this machine's absolute paths (`C:\Users\<name>\.ssh\...`) straight into
  the file every other machine would inherit — and left the repo dirty after
  every run.

  The rule that follows: **anything a step writes programmatically goes to
  `~/.gitconfig.local`; the tracked file is only ever hand-edited.** Enforced by
  `Set-NMGitLocal` (which uses `git config --file`) and by self-test assertions
  that the tracked file carries no absolute user paths and that no step calls
  `git config --global`.

  Generalizes beyond git: before linking any file, ask what else writes to that
  path. VS Code and Windows Terminal were spotted up front and given `copy`
  mode; git's own tooling was not, because the writer is a step in this repo
  rather than a third-party app.

- **The first run on a fresh machine produces copies, not links,** unless step 04
  runs elevated first and then a *new shell* is opened. That ordering is
  non-obvious and has to be documented in the runbook, not discovered.
- **Two modes mean a judgment call per file.** Get it wrong and you either lose
  edits (copy that should have been link) or get a permanently dirty repo (link
  that should have been copy).
- **`-Export` has to be remembered.** Nothing prompts you that a `copy`-mode file
  has drifted; it's a manual reconciliation step.
- **Backups accumulate.** `.bak-<timestamp>` files are never cleaned up. Safe,
  but untidy over many runs — `.gitignore` covers them for repo hygiene only.
- Copy-mode entries are skipped entirely when the target directory doesn't exist
  yet (Windows Terminal's `LocalState` only appears after first launch), rather
  than creating a directory the app may not expect.
