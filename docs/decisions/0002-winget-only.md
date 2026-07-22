# 0002 — winget as the only package manager

**Status:** Accepted · 2026-07-22

## Context

Step 01 installs ~29 packages spanning three categories with different needs:

- **CLI tools** (`ripgrep`, `fd`, `jq`, `starship`) — want fast, per-user,
  no-admin installs and frequent updates.
- **GUI applications** (Chrome, VS Code, Docker Desktop, Obsidian) — normal
  installers, often machine-scoped, occasionally requiring admin.
- **Developer runtimes** (`fnm`, `uv`) — manage their own downstream toolchains.

The dominant constraint is bootstrap: on a fresh Windows install, whatever
installs the packages must itself already be present, or its own installation
becomes step zero — an unversioned, unrepeatable curl-to-shell.

## Decision

`winget` only. It ships with Windows 10 1809+ via App Installer, so on any
machine this repo targets it is already there. Step 01 fails with a clear message
if it isn't rather than silently installing a package manager.

Package IDs live in `manifest/packages.json`, one row per tool, tagged (`core`,
`cli`, `dev`, `apps`, `optional`) so `-Tags core,cli` gets a minimal machine.

Every `winget` ID in the manifest has been verified against the live repository
with `winget show --id <id> --exact`. The `brew` and `apt` columns in the same
file are **unverified placeholders** for the eventual macOS/Linux ports, and the
manifest header says so — a guessed ID that looks authoritative is worse than an
obviously empty field.

## Alternatives considered

### Scoop — seriously considered

Genuinely better for the CLI-tool category: per-user by default, no admin, clean
`scoop update *`, and shims that keep `PATH` tidy. Several tools here (`fzf`,
`delta`, `lazygit`) are more current in scoop buckets than in winget.

Rejected on bootstrap cost. Scoop installs via `irm get.scoop.sh | iex` — an
unpinned remote script, executed before anything in this repo has run, that
cannot itself be made idempotent or auditable. That would put an unversioned
network dependency in front of the whole bootstrap. It also doesn't cover GUI
apps well, so it would be an *addition* to winget rather than a replacement,
doubling the manifest schema and the "which manager owns this package?" question.

Revisit if the CLI-tool half of the manifest starts lagging badly.

### Chocolatey — rejected

Broadest catalogue, especially for older and enterprise software, and the
established answer for Windows automation. Rejected for three reasons: it needs
the same unpinned bootstrap script as scoop; most operations want admin, which
conflicts with keeping the bulk of this repo unelevated
([0004](0004-powershell-51-floor.md) applies the same principle to elevation);
and its package quality is community-variable in a way winget's
publisher-submitted manifests mostly aren't.

### winget + scoop split by category — rejected

The "right" answer on paper: winget for GUI apps, scoop for CLI tools. Rejected
because it doubles the failure surface and forces a judgment call on every new
package. The manifest would need a `manager` field, step 01 would need two code
paths, and the self-test would need to validate two ID namespaces. For a personal
machine setup that isn't worth it.

### Per-tool official installers — rejected

Most accurate (always the vendor's real installer, always current) and how
several of these tools document their own install. Rejected outright: it makes
every package its own bespoke script with its own idempotency check, download
verification, and upgrade story. That's the entire problem a package manager
exists to solve.

## Consequences

- **Package currency is winget's to control.** When a tool lags in winget, this
  repo lags. No override mechanism today; a per-package `installScript` escape
  hatch is the obvious future addition (already sketched in
  `platforms/linux/README.md` for the same reason).
- **Some installs need admin.** Accepted; those are reported rather than silently
  failing.
- **A winget outage or ID rename breaks step 01.** Mitigated by verifying IDs and
  by treating `0x8A15002B` ("already installed") as success, not failure.
- **The `brew`/`apt` columns are decoration until someone verifies them.** They
  give the ports a starting shape and they're clearly labelled unverified, but
  they are not evidence of anything.
