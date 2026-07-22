# 0004 — Windows PowerShell 5.1 is the compatibility floor

**Status:** Accepted · 2026-07-22

## Context

A fresh Windows install ships **Windows PowerShell 5.1** and nothing newer.
PowerShell 7 (`pwsh`) is a separate product that must be installed — and in this
repo it *is* installed, by step 01, from the manifest.

That creates an ordering problem: the script that installs PowerShell 7 cannot
require PowerShell 7. Whatever runs first runs on 5.1.

5.1 is not a slightly older 7. It is a different engine with different parsing,
different defaults, and different error semantics, and the differences fail in
ways that don't look like version problems.

## Decision

**Everything in the bootstrap path must run correctly under Windows PowerShell
5.1.** PowerShell 7 gets installed and becomes the daily driver, but nothing in
this repo may depend on it.

Three concrete rules, each learned by breaking:

### Scripts must be pure ASCII

5.1 reads a BOM-less `.ps1` as Windows-1252, not UTF-8. A UTF-8 em-dash (`E2 80
94`) decodes as three CP1252 characters — the last of which is `"`. That closing
quote terminates whatever string it lands in, and the file fails to parse with a
misleading error pointing at a line far from the real one.

Two step files failed this way on the first real run. `tests/selftest.ps1`-adjacent
verification now greps every `.ps1` for non-ASCII.

### Never redirect a native command's stderr

`some.exe 2>$null` or `2>&1` in 5.1 wraps each stderr line in an `ErrorRecord`.
Under `$ErrorActionPreference = 'Stop'` — which this repo sets — that promotes a
tool merely *warning* into a terminating error. `gh ssh-key list` printing an
HTTP 404 notice killed an entire step this way.

All external commands go through `Invoke-NMNative`, which isolates
`$ErrorActionPreference`, captures stderr as text, and judges success by exit
code only.

### StrictMode punishes absent things

`Set-StrictMode -Version Latest` makes reading an unset variable or a missing
property a hard error. Two instances: `$IsWindows` doesn't exist in 5.1 at all
(so the platform check killed bootstrap on line one), and reading a registry
value that isn't set yet threw rather than returning `$null` — which is the
normal case for a setting you're about to configure.

The rule is to probe (`Test-Path Variable:IsWindows`,
`$item.PSObject.Properties[$name]`) rather than reference.

The shared PowerShell profile is subject to the same floor — it's linked into
both the 5.1 and 7 profile paths, so it must *parse* under 5.1: no `??`, no `?.`,
no ternary, and PSReadLine features are version-gated at runtime.

## Alternatives considered

### Bootstrap pwsh first, then run everything in 7 — seriously considered

A tiny 5.1-compatible shim installs PowerShell 7 and re-launches the real
bootstrap under it. This is the standard answer and it's a good one — it buys
`??`, ternaries, sane `2>&1`, cross-platform parity with a future macOS port
([0003](0003-platform-neutral-core.md)), and removes every constraint above.

Rejected on failure modes at exactly the wrong moment. The re-launch has to
survive `PATH` not yet containing `pwsh` in the current session, has to forward
every parameter correctly, and leaves you debugging a two-engine handoff on a
machine with no tooling. It also doesn't remove 5.1 from the picture — the shim
is still 5.1 code, and the profile still has to parse under 5.1 because it's
linked into both.

The constraints turned out to be three rules, all mechanically checkable. That's
cheaper than a re-launch mechanism.

### Require the user to install PowerShell 7 manually first — rejected

Documented prerequisite, one winget command. Rejected because it's exactly the
undocumented manual step this repo exists to eliminate, and it will be forgotten.

### Write the bootstrap in something else (Python, Go, batch) — rejected

Python and Go both need installing first — same chicken-and-egg as
[0002](0002-winget-only.md). Batch is worse than 5.1 in every dimension. 5.1 is
the only language guaranteed present on the target.

### Drop StrictMode — rejected

Would remove one of the three rules. Rejected because StrictMode catches typo'd
property names, which is a far more common error in this codebase than the
awkwardness it imposes. Both StrictMode failures were real bugs it surfaced
early, not false positives.

## Consequences

- **Modern PowerShell syntax is unavailable throughout**, including in code that
  will only ever run after PowerShell 7 is installed. Uniformity is worth more
  than the occasional nicety.
- **The ASCII rule is easy to violate accidentally.** Any editor, any paste, any
  well-meant em-dash reintroduces it. It needs an automated check on every change
  — currently a manual grep, which is the weakest link in this decision.
- **`Invoke-NMNative` is mandatory, not advisory.** A direct `& git ...` with a
  redirect will work in testing and fail on a machine where that tool warns.
- **Verbose property probing.** `$item.PSObject.Properties[$name]` instead of
  `$item.$name` everywhere state might be absent.
- **Everything is testable on the target machine as-is**, with no bootstrap
  ordering to reason about — which is the whole point.
