# 0008 — Repos clone in named sets, explicit or dynamically resolved

**Status:** Accepted · 2026-07-22

## Context

Different machines want different repos. A personal laptop shouldn't pull down
work repositories; a work machine wants the whole org. There are ~26 personal
repos and ~14 in the SayWhatTech org, and cloning all 40 on every machine is
both slow and wrong.

The two groups also behave differently over time:

- **Personal repos** are a stable handful I actually keep locally. New ones
  appear rarely and most aren't wanted on every machine.
- **Org repos** churn. New ones get created, old ones archived, and a work
  machine generally wants whatever is currently active — a hand-maintained list
  goes stale immediately.

## Decision

Named **repo sets** in `config.json`, selected with `-Repos Personal,SayWhatTech`
(or `all` / `none`), defaulting to `dev.defaultRepoSets`.

A set defines its members one of two ways:

- **Explicit** — a `repos` array of `owner/name` shorthand or full URLs. Right
  for a curated handful.
- **Dynamic** — an `owner` plus `includeAll`, resolved through `gh repo list` at
  clone time, filtered by `excludeArchived` and an `exclude` list. New org repos
  appear without editing config.

Both keys together means the explicit list is *added* to the resolved one.

Each set gets its own subdirectory via `path`, so `D:\projects\personal\` and
`D:\projects\saywhattech\` stay separate. `defaultRepoSets` is `["Personal"]`
only — a bare run never pulls work repos onto a personal machine; that requires
asking for it explicitly.

An unrecognized set name fails with the list of valid names and exit code 1,
rather than resolving to nothing and silently cloning zero repos.

## Alternatives considered

### One flat list of repos — rejected

What the first version did (`dev.clone: [...]`). Rejected the moment a second
context appeared: there's no way to say "this machine gets personal only", so
either every machine gets everything or you hand-edit config per machine — which
defeats having one committed config.

### Dynamic for everything (`gh repo list` for both owners) — rejected

Consistent, and never goes stale. Rejected for the personal set specifically:
26 repos of which maybe 3 are wanted on a given machine. Dynamic resolution is
right when you want *everything* an owner has; it's wrong when you want a curated
subset, and personal repos are a curated subset by nature.

### Explicit for everything — rejected

Predictable, no network dependency, no `gh` requirement, reviewable in a diff.
Rejected for the org set: work repos churn enough that a hand-maintained list is
stale within weeks, and the failure is silent — you just don't have the repo, and
you don't find out until you need it.

### Topic or naming-convention driven — considered, deferred

`gh repo list --topic active`, or a naming prefix. More expressive than
`excludeArchived` and the natural next step if `exclude` lists grow. Deferred
because it requires disciplined topic-tagging that doesn't currently exist —
adding the mechanism before the discipline just moves the staleness.

### Flat layout, no per-set subdirectories — rejected

`D:\projects\` currently holds repos flat, so this was the status quo. Rejected
because 14 org repos landing alongside personal ones makes the directory
unnavigable and makes "which of these is work?" a question you answer by
remembering. Both sets got their own subdirectory rather than only the new one,
so the rule is uniform.

### `git clone --filter` / sparse or shallow clones — rejected

Would make cloning 40 repos cheap enough that the whole selection problem
disappears. Rejected because partial clones make ordinary history operations slow
or network-dependent later, trading a one-time setup cost for a permanent
working cost. Wrong direction for repos you actually develop in.

## Consequences

- **Dynamic sets need `gh` authenticated at step 05.** On a fresh machine that's
  satisfied by step 03, but running `-Only 05` in a shell where `gh` isn't on
  `PATH` yet warns and resolves to nothing. The step distinguishes "couldn't ask"
  (returns null, reports the reason) from "owner genuinely has no repos".
- **Dynamic sets are non-deterministic.** Two machines set up a month apart get
  different repo lists. That's the intent, but it means the run log's record of
  *what* got cloned is the only history of it.
- **The 200-repo `--limit` is arbitrary** and silently truncates beyond it. Fine
  now; a footgun at scale.
- **This repo is a member of its own `Personal` set.** Cloning it into
  `personal/` while working from a different path produces a second copy. Handled
  in the runbook (`-Repos none` on first runs, move the repo afterwards) rather
  than special-cased in code, since the alternative is the tool making surprising
  decisions about its own location.
- Sets are selected per-run, so the same machine can pull work repos later
  without a config change.
