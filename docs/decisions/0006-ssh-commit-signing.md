# 0006 — SSH commit signing rather than GPG

**Status:** Accepted · 2026-07-22

## Context

Commits should be signed so GitHub shows them Verified and so the history has
some provenance. Signing needs a key, and the machine already generates an
ed25519 SSH key in step 03 for authentication.

The setup has to be scriptable on a fresh machine. Anything requiring an
interactive prompt, a passphrase entry, or a GUI is a step that will be skipped
and never come back to.

## Decision

**SSH signing**, reusing the authentication key generated moments earlier in the
same step:

```
gpg.format = ssh
user.signingkey = ~/.ssh/id_ed25519.pub
gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers
commit.gpgsign = true
tag.gpgsign = true
```

The same public key is registered with GitHub twice — once as an
`authentication` key, once as a `signing` key. They're distinct key types on
GitHub's side even when the bytes are identical.

`config.json` keeps a `signing.method` of `ssh` | `gpg` | `none`. The `gpg`
branch exists and wires up `git config` correctly, but stops short of generating
a key — `gpg --full-generate-key` is interactive and the step tells you to run it
rather than pretending.

## Alternatives considered

### GPG signing — rejected as the default, retained as an option

The traditional answer, with real advantages: a web of trust, expiry and
revocation built in, subkeys so the signing key can be separate from the identity
key, and support outside GitHub.

Rejected as the default on setup cost, which is almost entirely front-loaded onto
exactly the moment this repo is trying to automate:

- Key generation is interactive and cannot be scripted cleanly.
- It needs `gpg-agent` and a working pinentry — a recurring source of "why won't
  it prompt" failures on Windows in particular.
- The key must be exported and uploaded separately from the SSH key.
- Passphrase handling on a fresh machine is another interactive step.

None of that is hard *once*. All of it is friction *every time*, which is the
thing that gets skipped.

The `gpg` config branch is kept because the decision is reversible and the wiring
is the easy part.

### No signing at all — rejected

Zero setup, and honestly fine for personal repos. Rejected because it's free once
the SSH key exists — the marginal cost over authentication-only is four `git
config` lines and one extra API call — and because Verified badges make it
obvious when something committed as you that wasn't you.

### Separate signing key from auth key — rejected

Better hygiene: compromise of the auth key doesn't let an attacker sign as you,
and the keys can rotate independently. Rejected as disproportionate for a
single-user personal setup. It would double the key management (two keys, two
uploads, two agent entries) to defend against a threat model where the attacker
already has your machine's private key — at which point they have your machine.

Reconsider if these keys ever protect anything shared.

### Sign tags only, not commits — rejected

Common compromise: sign the things that get released, leave day-to-day commits
alone. Rejected because there's no per-commit decision to make when it's
automatic, and partial signing makes an unsigned commit unremarkable rather than
suspicious.

## Consequences

- **One key does two jobs.** Compromise means both authentication and signing.
  Accepted per the threat model above.
- **`gh` needs extra scopes.** Registering keys requires `admin:public_key` and
  `admin:ssh_signing_key`, which an existing token often lacks. The step detects
  the 404 and prints the exact `gh auth refresh` command rather than failing
  opaquely — but it is a manual step, and it must be in the runbook.
- **`commit.gpgsign = true` is global.** Every commit on the machine is signed,
  including in repos where nobody cares. Harmless, but it means a broken agent
  breaks *all* commits, not just ones that need signing — including the run log's
  own auto-commit ([0010](0010-run-log.md)), which degrades to a warning.
- **`allowed_signers` is appended to, never deduplicated.** Re-running after
  regenerating a key leaves stale entries. Harmless (verification still passes on
  the current key) but untidy.
- **Verification outside GitHub needs the `allowed_signers` file.** Anyone else
  validating these signatures needs that file; GPG's web of trust would have
  handled it. Irrelevant for a personal repo, would matter for a shared one.
