# 0012 — Sandboxed self-test plus dry run, no VM or CI

**Status:** Accepted · 2026-07-22

## Context

This repo is unusually hard to test honestly. Its entire job is **mutating the
machine it runs on** — installing software, writing the registry, replacing
files in the home directory, generating SSH keys. The obvious test ("run it and
see") is destructive, slow, and can only be done once per machine before the
machine is no longer fresh.

It also runs rarely. A bug introduced today surfaces in six months, on a new
machine, with no tooling, at the exact moment you need the tool to work. That
raises the value of catching mistakes at edit time well above what a
twice-a-year script would normally justify.

## Decision

Two layers, neither of which touches machine state:

**`tests/selftest.ps1`** — exercises the *real*, non-dry-run code paths against a
throwaway sandbox directory and an `HKCU` scratch key. 68 assertions covering
config loading, JSON validity across every file in the repo, path-token
expansion, the dry-run wrapper, native-command handling, registry idempotency,
the symlink/copy fallback, projects-root resolution (against a genuinely
unmounted drive letter, not a mock), clone-URL normalization, repo-set validity,
run-log write/append/skip behaviour, SSH-rewrite coverage, and manifest sanity.

**`.\bootstrap.ps1 -DryRun`** — end-to-end narration of every step against the
real machine's real state, writing nothing.

The two are complementary and neither is sufficient: `-DryRun` walks the true
control flow but skips every `Invoke-NMAction` body, so the code that does the
work never executes. The self-test executes those bodies but against synthetic
inputs.

Some assertions are **consistency checks between files** rather than unit tests —
every owner in `dev.repoSets` has an `insteadOf` rule
([0007](0007-scoped-https-to-ssh-rewrite.md)), every `links.json` source exists,
no duplicate winget IDs. These catch the failure mode that matters most here:
config and code drifting apart silently.

## Alternatives considered

### Pester — seriously considered

The PowerShell testing framework: real assertions, mocking, discovery,
CI-friendly output. Everything the hand-rolled `Check` function does, done
properly.

Rejected on the same bootstrap constraint as everything else
([0002](0002-winget-only.md)): Pester 5 is a module to install before you can
test, and the version shipped with Windows (Pester 3.4) is incompatible with
modern syntax. That means testing requires a set-up machine — but the code under
test is *what sets up the machine*, so on a fresh box you couldn't verify the
thing you're about to run.

A ~15-line `Check` function with a pass/fail tally has no dependencies and runs
anywhere the bootstrap runs. Worth revisiting if the suite outgrows a single
file, but the dependency-free property is worth real ergonomic cost here.

### A disposable VM or Windows Sandbox — the honest answer, deferred

The only way to genuinely test a fresh-machine bootstrap: snapshot, run, inspect,
roll back. Would have caught every bug found the hard way, and is the *correct*
solution.

Deferred on setup cost — a Windows image, Hyper-V or Sandbox configured, and a
provisioning harness — which is a project of comparable size to this repo. Also
partly unusable for the interactive parts: `gh auth login` needs a browser and a
real GitHub account, so the VM can't validate step 03 end-to-end anyway.

**This is the biggest known gap.** The self-test cannot catch anything about how
steps interact on a genuinely fresh machine — package installs, PATH propagation
between steps, Developer Mode taking effect. Those were found by running on a
real machine and reading failures.

### CI (GitHub Actions with a Windows runner) — rejected

Would run the self-test on every push, for free. Genuinely tempting and the
cheapest of the rejected options.

Rejected because the runner is not a fresh consumer Windows install — different
preinstalled software, different PowerShell, no Developer Mode, no interactive
auth — so a green CI run would assert something other than what matters. The risk
is false confidence: a passing badge that says nothing about the failure modes
this repo actually has. The `-DryRun` and self-test still need running on a real
target.

Reconsider narrowly: CI could validate the *pure* checks (JSON parses, ASCII
cleanliness, manifest/config consistency) without pretending to test provisioning.
The ASCII rule in particular is the weakest link in
[0004](0004-powershell-51-floor.md) — it's currently a manual grep and it's
exactly the kind of thing CI is good at.

### Test only via `-DryRun` — rejected

Zero additional code; the dry run already narrates everything. Rejected because
it skips every action body — the code that actually does the work is never
executed. Three of the four bugs found on the first real run were inside action
bodies that `-DryRun` had walked straight past.

## Consequences

- **The shell that runs the tests is not the shell that runs the tool.** This
  produced two false passes, both discovered only when a human typed the command
  themselves:

  - **Execution policy.** Automated sessions launch PowerShell with
    `-ExecutionPolicy Bypass`; a real interactive shell falls through to Windows
    PowerShell's `Restricted` default. The first command in the runbook failed
    with *"running scripts is disabled on this system"* after passing every
    check here.
  - **Elevation.** The automated session happened to be running elevated, so
    `New-Item -ItemType SymbolicLink` succeeded and the self-test reported
    `PASS symlink created` — on a machine where Developer Mode was **off** and a
    normal shell would have taken the copy fallback. The test asserted the
    happy path while the real path was the fallback.

  Neither is a bug in the suite; both are outside what it can observe. The
  general lesson is that **the invocation path and the ambient security context
  are untested by construction**. Anything between "user types a command" and
  "our code starts executing" — execution policy, `PATH`, elevation, file
  associations, Zone.Identifier blocking, profile load failures — is invisible
  here, and a permissive harness makes the tool look more capable than it is.

  Practical mitigation short of a VM: assert the *context*, not just the
  behaviour. A test that records whether it ran elevated makes a
  privilege-dependent pass self-identifying instead of silently reassuring.

- **No coverage of cross-step interaction on a fresh machine.** Accepted, and the
  reason the runbook prescribes `-DryRun` first and two passes.
- **The self-test asserts against synthetic state**, so it proves the logic, not
  the outcome. `Set-NMRegistryValue` is verified against a scratch key, not
  against the real Explorer settings it will write.
- **Hand-rolled assertions mean no test discovery, no filtering, no structured
  output.** One file, top to bottom, all or nothing.
- **The ASCII rule has no automated enforcement** in the committed suite — it's a
  manual grep, which is precisely the kind of check that gets skipped.
- **Interactive steps are untested by construction.** `gh auth login` and the
  Obsidian flow ([0011](0011-obsidian-left-alone.md)) can't be exercised without
  a human.
- The suite runs in seconds with no dependencies, which is why it actually gets
  run before every commit.
