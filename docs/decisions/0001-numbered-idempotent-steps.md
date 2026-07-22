# 0001 — Numbered idempotent step scripts driven by one config file

**Status:** Accepted · 2026-07-22

## Context

The repo has to take a fresh Windows install to a working machine, and it will
be run rarely — maybe twice a year. That cadence is what drives the design:

- **I will not remember how it works.** Anything requiring me to hold a mental
  model six months from now is a design failure.
- **It will be run partially.** Something always fails midway — a package
  download times out, a scope is missing, a reboot is needed. Re-running the
  whole thing has to be safe and cheap.
- **It will be run on a half-configured machine.** Not just fresh installs; also
  "I already set this box up by hand, now make it match."
- **It has to be inspectable before it runs.** Handing a script admin rights on
  a new machine without being able to see what it will do is unpleasant.

## Decision

Numbered step scripts under `platforms/windows/steps/`, executed in filename
order by `bootstrap.ps1`, with all machine-varying values in a single
`config.json`.

Every step is **idempotent**: it checks current state before acting and reports
one of `+` changed, `=` unchanged, `!` warning, `x` failed. A second run of a
configured machine reports all skips and changes nothing. Steps are independently
runnable (`.\steps\04-os-tweaks.ps1`) and selectable (`-Only 03,04`, `-Skip
packages`).

Everything routes through `Invoke-NMAction`, which gives dry-run and consistent
reporting for free — so `-DryRun` narrates the entire plan without touching the
machine, and no step has to implement dry-run itself.

A per-step failure is caught by `bootstrap.ps1` and does not abort the run; the
remaining steps still execute and the failure is collected into the summary.

## Alternatives considered

### One monolithic script — rejected

Simplest thing that could work, and where this started. Rejected because partial
re-runs are the common case, not the exception. Without step boundaries there's
no `-Only`, no way to re-run just the elevated parts, and a failure two-thirds of
the way through means either re-running everything or hand-editing the script.

### PowerShell DSC — rejected

The idiomatic Microsoft answer, and genuinely declarative-idempotent. Rejected on
weight: DSC needs a configuration compile step, an LCM to configure, and its own
mental model. For a script run twice a year that's a large tax, and DSC's own
future has been unclear across versions. Debugging a DSC failure on a fresh
machine is worse than debugging a PowerShell script.

### Ansible / Chef / Puppet — rejected

Real config management with real idempotency primitives. Rejected because they
need a control node, a Python or Ruby runtime, and (for Windows targets) WinRM
configured — all of which are things you don't have on a machine you're trying to
bootstrap. Chicken-and-egg: the tool that sets up the machine can't require a
set-up machine.

### `winget configure` / WinGet DSC YAML — seriously considered

The closest native fit: declarative YAML, idempotent resources, no extra runtime,
and it handles packages *and* settings. Rejected for now on two grounds. First,
coverage — the resource ecosystem doesn't reach the things this repo actually
needs (SSH keygen, `gh` auth, dotfile symlinks, repo cloning), so a large escape
hatch into scripting would be needed anyway. Second, inspectability — there's no
equivalent of `-DryRun` narrating every action.

Worth revisiting. If the resource ecosystem catches up, steps 01 and 04 are the
natural candidates to move over first.

### Boxstarter — rejected

Solves a genuinely hard problem (surviving reboots mid-provision). Rejected
because it's Chocolatey-coupled (see [0002](0002-winget-only.md)) and this repo
doesn't need reboot survival — no step requires a reboot to continue.

## Consequences

- Idempotency is a per-step obligation, not something the framework enforces.
  Every new step has to implement its own "is this already done?" check, and the
  self-test can't verify that for arbitrary steps.
- Step *ordering* is implicit in filenames and unenforced. `02-dotfiles` assumes
  `01-packages` ran; nothing checks. Mitigated by steps degrading gracefully —
  02 warns and continues rather than failing when a tool isn't on `PATH` yet.
- `-Only` uses substring matching, so `-Only 0` would match every step. Acceptable
  for a personal tool; a real CLI would want exact matching.
- Adding a step is genuinely cheap: one file, no registration.
