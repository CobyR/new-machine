# 0007 — Rewrite HTTPS to SSH for our owners only

**Status:** Accepted · 2026-07-22

## Context

Repos should be on SSH: the key is already set up in step 03, it avoids
credential-helper prompts and token expiry, and it's what the clone URLs in
`config.json` produce.

Fixing existing remotes is a one-time cleanup. Keeping them that way isn't,
because HTTPS URLs keep arriving from sources you don't control:

- GitHub's **Code** button defaults to the HTTPS tab.
- Submodules embed whatever URL the author committed.
- `go get`, `pip install git+https://...`, and similar tooling emit HTTPS.
- Copy-pasted setup instructions in READMEs are almost always HTTPS.

Without something structural, "everything is on SSH" is true on the day you fix
it and quietly false a few months later.

## Decision

Rewrite rules in `dotfiles/git/gitconfig`, **scoped to owners we actually clone
from**:

```ini
[url "git@github.com:CobyR/"]
	insteadOf = https://github.com/CobyR/
[url "git@github.com:SayWhatTech/"]
	insteadOf = https://github.com/SayWhatTech/
```

Git substitutes the prefix before connecting, so an HTTPS clone of one of our
repos transparently becomes SSH regardless of where the URL came from.

`tests/selftest.ps1` derives the owner list from `dev.repoSets` in `config.json`
and asserts each has a matching rule — adding an org can't silently leave it on
HTTPS — and asserts no blanket rule has crept in.

Verified with `GIT_TRACE`: `https://github.com/CobyR/network` invokes `ssh ...
git@github.com git-upload-pack CobyR/network`, while `https://github.com/git/git`
still runs `git remote-https`.

## Alternatives considered

### Blanket rewrite of `https://github.com/` — rejected

One rule, covers every repo forever, nothing to maintain when a new org appears.
This was the original proposal.

Rejected because it also rewrites **third-party public repos**, which then need a
loaded SSH key to clone. Anonymous HTTPS cloning of a public repo requires no
credentials at all; SSH cloning requires a key in the agent. So a blanket rule
turns `git clone https://github.com/someone/tool` — which would have just worked
— into a failure on:

- a fresh machine before step 03 has run
- any shell where `ssh-agent` isn't running or the key isn't loaded
- CI or a container that inherited the dotfile but has no key

Failing to clone a public repo *because of a convenience rule about your own
repos* is a bad trade. The scoped version delivers the actual guarantee — our
repos are always SSH — with none of it.

### Fix each remote by hand as you notice — rejected

What we did once, and it works. Rejected because it's unbounded manual
maintenance with a silent failure mode: nothing tells you a remote is on HTTPS
until you hit an auth prompt, and by then you've usually just entered a token and
moved on, entrenching it.

### `pushInsteadOf` instead of `insteadOf` — seriously considered

Rewrites only push URLs, leaving fetch on HTTPS. Anonymous fetch keeps working
without a key while writes still go over SSH — a genuinely elegant split.

Rejected because it produces a *mixed* state that's harder to reason about: `git
remote -v` shows different fetch and push URLs, and "is this repo on SSH?" no
longer has a single answer. For our own repos we want the key present anyway, so
the fetch-without-key case it protects doesn't arise. Worth revisiting if the
scoped list ever grows to include orgs with public repos cloned by people without
access.

### Set `url` correctly at clone time only — rejected

`ConvertTo-NMCloneUrl` already emits SSH URLs for repos this bootstrap clones, so
step 05's output is correct without any rewrite rule. Rejected as insufficient:
it covers only clones *this repo performs*, which is a small fraction of clones
you actually do. The rewrite covers the manual ones, which is where drift comes
from.

### Credential helper with a PAT over HTTPS — rejected

The other coherent answer: stay on HTTPS everywhere and let Git Credential
Manager hold a token. Works well, and is arguably better for machines where SSH
is awkward. Rejected because it means managing token expiry and scopes as an
ongoing chore, whereas the SSH key is already generated, already uploaded, and
already needed for signing ([0006](0006-ssh-commit-signing.md)).

## Consequences

- **The owner list needs maintaining.** A new org means a new rule. Mitigated by
  the self-test failing loudly, which converts a silent drift into a caught one.
- **The rule is invisible when it fires.** `git clone https://...` succeeding over
  SSH is exactly what we want, but if SSH is broken the error mentions SSH for a
  command you typed as HTTPS, which is confusing until you remember this exists.
- **Only applies once dotfiles are linked.** The rule lives in the repo's
  `gitconfig`; it does nothing until step 02 has run. The bootstrap's own first
  clone is necessarily HTTPS.
- **Doesn't fix remotes on already-cloned repos.** `insteadOf` affects URL
  resolution, not stored remote config — an existing HTTPS remote keeps its
  stored URL (though the rewrite applies when git resolves it). Existing repos
  still need `git remote set-url` once.
