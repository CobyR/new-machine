# 0010 — Append-only JSONL run log, auto-committed and auto-pushed

**Status:** Accepted · 2026-07-22

## Context

The requirement: know which machines this repo has been used to set up, and when.
Over years and many machines, "did I ever run this on the old laptop?" and "what
did that machine actually get?" are real questions with no other source of truth.

Constraints that shaped it:

- **Runs happen on different machines at unpredictable times**, occasionally
  close together, each pushing to the same repo.
- **The record is worthless if it stays local.** A machine set up once and walked
  away from must not leave its only record in an uncommitted file.
- **Writing the log must never endanger real work.** It runs at the end of a
  bootstrap in a repo that may have uncommitted changes.

## Decision

One **JSON Lines** record appended to `logs/runs.jsonl` per real run (dry runs
are not recorded), capturing: timestamp, hostname, crypto `MachineGuid`, user,
domain, elevation, OS caption/build/arch, manufacturer/model/CPU/RAM, PowerShell
version, repo commit + branch + dirty flag, the invocation (flags, tags, steps),
duration, counts, the list of changed items, and any failures.

Written from `bootstrap.ps1` rather than as a step, so it captures **every** use
of the repo including partial `-Only` / `-Skip` runs.

`log.autoCommit` and `log.autoPush` both default to **true**. The commit is
scoped to the log file alone:

```
git commit --only -- logs/runs.jsonl
```

A rejected push is rebased onto the remote and retried once; an unresolvable
rebase is aborted so the working tree is left as found, with the commit in place
and the manual fix printed.

`.gitattributes` marks the file `merge=union`.

`tools/Show-RunLog.ps1` renders it per-run, per-machine, or in full.

## Alternatives considered

### A single JSON array — rejected

The obvious shape, and readable without a special tool. Rejected on the merge
behaviour: appending to a JSON array rewrites the closing bracket and the
previous last element's line, so two machines appending independently conflict on
*every* concurrent run — and the conflict is in the middle of structured data,
which is exactly the kind of merge you resolve wrong at 11pm.

JSONL appends a line and touches nothing else, which makes `merge=union` a
correct resolution rather than a hopeful one: both machines' lines survive, order
is irrelevant because every record is timestamped.

### CSV — rejected

Better still for merging, and trivially readable. Rejected because the record is
genuinely nested (os, hardware, repo, invocation, result, changed[]) and
flattening it into columns either loses structure or produces forty columns.
`changed` is a variable-length list, which CSV handles badly.

### SQLite — rejected

Proper queries, proper types, no parsing. Rejected outright: a binary file in git
means every run is an unmergeable conflict, which is the exact failure JSONL was
chosen to avoid.

### External telemetry (a service, a gist, a spreadsheet) — rejected

Keeps the repo clean and gives real querying. Rejected because it adds an
auth-and-network dependency to a tool whose whole job is working on a machine
that isn't set up yet, and because the record belongs with the thing it describes
— cloning the repo should bring its history.

### Local log, committed manually — rejected

The original default (`autoCommit: false`), on the reasoning that a tool
committing on your behalf is surprising. Rejected in use: it produces exactly the
failure the log exists to prevent. You set up a machine, walk away, and the only
record of it sits uncommitted until that machine is wiped.

The surprise concern is real, and the answer is scoping rather than abstention —
`--only` means an in-progress edit elsewhere in the repo is never swept in.
Verified by committing a run mid-edit and confirming unrelated modified files
stayed unstaged.

### Commit but don't push — rejected

Intermediate position, avoids an outward-facing action. Rejected for the same
reason: commits sitting unpushed on a machine you've walked away from are only
marginally better than uncommitted ones. Once push failure was made survivable
(rebase-and-retry), the argument for withholding it went away.

## Consequences

- **The bootstrap makes commits.** Unusual behaviour for a setup script and it
  must be documented, or a `git log` full of `Record setup run on <HOST>` looks
  like something went wrong.
- **A bare `git push` was broken before the retry existed** — non-fast-forward as
  soon as another machine pushed first, which is the normal case when
  provisioning two machines in a session. The feature was effectively unusable in
  its main scenario until fixed.
- **`merge=union` is only correct because every line is independent.** Any future
  header, footer, or aggregate in that file breaks the property silently.
- **The log records hardware and a machine GUID.** Fine for a personal repo,
  would be a disclosure question in a shared one.
- **Failures degrade to warnings.** No network, no push access, or a signing
  failure ([0006](0006-ssh-commit-signing.md)) warns and moves on, leaving the
  entry committed locally to go up with the next successful push. The bootstrap
  never fails because logging failed.
- **`Get-NMRepoState` reports `dirty` from before the log write,** so a run's own
  record never shows the dirt it is about to create.
