# 0009 — Projects root defaults to `D:\projects` with a drive fallback

**Status:** Accepted · 2026-07-22

## Context

Most of these machines are desktops with a separate data drive, and code lives on
`D:\projects`. Some — laptops, VMs, a rebuilt box before the second drive is in —
have only `C:`.

A config value of `D:/projects` is correct for the common case and catastrophic
for the exception in a specific, quiet way: on Windows, creating `D:\projects`
when there's no `D:` drive doesn't error. Depending on context it can resolve
somewhere unintended or fail deep inside a clone rather than at the point the
path was chosen. Either way the failure surfaces far from its cause.

## Decision

Three layers, most specific first:

1. **`-ProjectsRoot 'E:\code'`** — per-run override, wins over everything.
2. **`dev.root`** — the configured default, `D:/projects`.
3. **`dev.fallbackRoot`** — `{HOME}/projects`, used automatically when
   `dev.root` names a drive this machine doesn't have.

`Resolve-NMProjectsRoot` extracts the drive qualifier, tests whether it exists,
and falls back with a visible warning naming both paths. The run log records the
resolved root, so a machine that fell back says so in its record.

With no `fallbackRoot` configured it warns and proceeds with the original path
rather than inventing a location.

## Alternatives considered

### Always use `~/projects` — rejected

Portable, always exists, no drive logic, and what most dotfile repos do.
Rejected because it's wrong for the majority of machines here. Putting code on
`C:` alongside the OS is exactly what the second drive exists to avoid, and
"correct by default on most machines" beats "never surprising but usually wrong".

### Require `-ProjectsRoot` explicitly, no default — rejected

Forces a conscious choice, never guesses. Rejected because the whole point is a
bare `.\bootstrap.ps1` doing the right thing. A required parameter is one more
thing to remember on a machine where you're already remembering the admin
ordering and the two-pass rule.

### Fail loudly when the drive is missing — seriously considered

Arguably more correct: refuse to guess, tell the user to pass `-ProjectsRoot`.
Explicit, no surprises, no chance of repos landing somewhere unexpected.

Rejected because the fallback is *obvious* rather than arbitrary — `~/projects`
is the only sensible alternative — and a hard failure at step 05 means the
preceding steps succeeded and you re-run for one path. The warning plus the run
log entry means the fallback is never invisible, which was the real concern.

Revisit if a fallback ever surprises someone in practice.

### Detect the largest non-system drive automatically — rejected

Clever: find the biggest fixed drive and use it. Rejected as too clever. It would
pick a backup drive, an external disk, or a scratch volume, and the choice would
change between runs as drives come and go. Non-deterministic placement of source
code is worse than a wrong-but-stable default.

### Per-machine `config.local.json` for the root — retained as the real answer

Already supported and git-ignored. For a machine that permanently wants a
different root, this is better than either the flag (per-run, forgettable) or the
fallback (automatic, drive-existence-driven). The fallback handles the
*unconfigured* case; `config.local.json` handles the *deliberately different*
case.

## Consequences

- **The check is drive-existence, not writability.** A `D:` that exists but is a
  read-only or full volume passes the check and fails later. Rare enough not to
  warrant probing with a test write.
- **Only the drive qualifier is validated,** not the rest of the path. `D:\typo\projects`
  passes and gets created.
- **A fallback changes where repos live without asking.** Deliberate, warned
  about, and recorded — but it does mean the same command produces different
  layouts on different machines. That's the intent, and the run log is the
  audit trail.
- **UNC and mapped-network paths are untested.** `Split-Path -Qualifier` on a UNC
  path doesn't return a drive letter; behaviour there is unverified.
- Verified in `selftest.ps1` against a genuinely unmounted drive letter rather
  than a mocked one, including the no-`fallbackRoot` case.
