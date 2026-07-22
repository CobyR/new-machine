# 0003 — Platform-neutral data at the root, platform code at the edges

**Status:** Accepted · 2026-07-22

## Context

The immediate need is Windows-only — every machine in scope today runs Windows.
But macOS and Linux are plausible later, and the cost of that being possible is
paid entirely up front, in layout. Retrofitting cross-platform structure onto a
Windows-shaped repo means moving every file and rewriting every path, at exactly
the moment you're also learning a new platform's quirks.

The opposite failure is just as real: building a cross-platform abstraction for
platforms that never arrive, and paying indirection tax forever on the one
platform that does.

## Decision

Split by **what varies**, not by what exists today.

Platform-neutral things live at the repo root and are consumed by every
bootstrap:

- `config.json` — identity, tags, dev root, repo sets, feature toggles
- `manifest/packages.json` — one row per tool, with `winget` / `brew` / `apt`
  columns side by side
- `dotfiles/` — the actual config files, plus `links.json` mapping source →
  target with an array per platform

Platform-specific things live under `platforms/<os>/`: the step scripts, the
helper library, and the OS-specific settings model.

Two conventions make the neutral files genuinely neutral rather than
Windows-files-in-a-neutral-folder:

- **Path tokens.** `links.json` and `config.json` use `{HOME}`, `{DOCUMENTS}`,
  `{APPDATA}`, `{LOCALAPPDATA}`, `{REPO}` rather than `%APPDATA%` or `$HOME`, so
  a bash implementation reads the same file without a translation layer.
  `{DOCUMENTS}` is resolved by asking Windows, not by assuming `~/Documents` —
  OneDrive redirection makes the naive answer wrong on a lot of machines.
- **Step numbering is shared vocabulary.** `03` means SSH and signing on every
  platform, so `-Only 03` means the same thing everywhere.

`platforms/macos/README.md` and `platforms/linux/README.md` record what porting
actually takes, including the parts that *don't* map cleanly — Linux needs
distro dispatch and an `installScript` escape hatch for tools apt doesn't carry.

## Alternatives considered

### Windows-only now, restructure later — rejected

Honest and minimal, and the default outcome if nobody thinks about it. Rejected
because the restructure never happens at a good time. The moment you want macOS
support is the moment you're on a new machine with no tooling, and that is the
worst possible time to also be moving every file in the repo.

The cost of avoiding it turned out to be small: three columns in a JSON file, a
token convention, and two README stubs.

### A separate repo per platform — rejected

Clean isolation, no abstraction tax. Rejected because the *data* is the valuable,
slow-to-rebuild part — the package list, the dotfiles, the repo sets — and it is
genuinely shared. Splitting repos means either duplicating it (and watching the
copies drift) or introducing a submodule, which is worse than the problem.

### A branch per platform — rejected

Same data-sharing problem as separate repos, plus permanent merge conflicts on
every shared file. Branches are for changes over time, not variants in parallel.

### A cross-platform tool (chezmoi, Nix, Ansible) — rejected

Nix in particular solves this properly and reproducibly. All rejected on the same
bootstrap grounds as [0002](0002-winget-only.md): each needs itself installed
first, and Nix on Windows means WSL, which means the thing setting up Windows
runs inside a Linux VM on the Windows machine it is configuring. chezmoi is the
most tempting (real templating, real cross-platform dotfiles) and would be the
first thing to evaluate if `dotfiles/` outgrows `links.json`.

### PowerShell 7 everywhere — rejected

PowerShell Core runs on all three platforms, so in principle one implementation
covers everything. Rejected because a fresh Windows machine doesn't have it — see
[0004](0004-powershell-51-floor.md). Bootstrapping pwsh with 5.1 to then run
everything in pwsh is possible but means two languages in the repo anyway, and
pwsh-on-macOS is nobody's idiom.

## Consequences

- **The macOS/Linux readiness is unproven.** The structure is right and the data
  is in place, but no bash bootstrap has been written and the `brew`/`apt` IDs
  are unverified ([0002](0002-winget-only.md)). This is *reduced* future work,
  not eliminated work — and it may reveal that `links.json` needs a schema change
  after all.
- **Token expansion is a small tax on every path.** `Expand-NMPath` sits between
  config and filesystem everywhere. Cheap, but it means you can't paste a config
  path into Explorer.
- **Deeper nesting than a Windows-only repo needs.** `platforms/windows/steps/`
  is three levels for something that could be `steps/`.
- **Nothing enforces the split.** A Windows path could be committed into
  `config.json` and only the eventual porter would notice. The self-test checks
  `dev.root` and `fallbackRoot` are set, not that they're portable.
