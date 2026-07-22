# 0011 — Don't touch Obsidian's config; Sync stays manual

**Status:** Accepted · 2026-07-22 · *supersedes an earlier vault-registration approach*

## Context

The ask was "install Obsidian and enable sync with my primary vault." Installing
is trivial (it's a manifest row). Enabling Sync is the interesting half.

Obsidian Sync requires, in order: signing in to an Obsidian account (email,
password, possibly 2FA), enabling Sync in settings, and choosing a remote vault
from a dialog. There is no CLI, no config file that holds the credential, and no
API. The credentials are also not something this repo should hold — it's a public
GitHub repo, and even if it weren't, a setup script is the wrong place for
account passwords.

Obsidian *does* keep known vaults in `%APPDATA%\obsidian\obsidian.json`, keyed by
a random id, and writing an entry there makes it open that vault instead of
showing its chooser.

## Decision

**Touch nothing.** Step 06 is read-only: once Obsidian is installed it prints the
four manual steps (sign in → enable Sync → choose remote vault → let the first
sync finish) and does nothing else. `obsidian.remindAboutSync: false` silences it.

Obsidian shows its normal vault chooser on first launch, which is the correct
entry point when the vault is coming from Sync.

## Alternatives considered

### Register the vault path in `obsidian.json` — implemented, then removed

This was built and merged first: `obsidian.vaultPath` in config, a registered
entry in `obsidian.json`, backup-before-write, optional folder creation, optional
launch. It worked, and skipping the chooser is a real convenience *when the vault
already exists locally*.

Removed because it's the wrong default for the actual scenario. When the vault
comes from Sync, the chooser is exactly where you sign in and pull it down. Pre-
registering a local path points Obsidian at a folder that may not exist yet, and
puts you in a worse starting position than the one the app gives you by default —
you now have to undo the helpful thing before you can do the real thing.

It was also the more complex option by a wide margin: the removal took out ~117
lines, a backup path, a `createIfMissing` toggle, an `openAfterSetup` toggle, and
two config keys.

Sequencing made this hard to see up front: registration is the obviously helpful
move if you assume a local vault, and only wrong once you know Sync is involved.
That's the reason to record it — the mistake was assuming the local-vault case,
not the implementation.

### Automate Sync itself — not possible

Investigated and ruled out on capability, not preference. No CLI, no config-file
credential, no API. Anything achieving it would be UI automation against a
proprietary app's login flow, which is fragile, breaks on any redesign, and
requires storing account credentials.

### Prompt for the vault path during bootstrap — rejected

Would make registration correct by asking rather than assuming. Rejected because
it makes the bootstrap interactive. Everything else runs unattended; adding one
prompt means the whole run needs supervision, which is a large cost for skipping
one dialog.

### Drop step 06 entirely — seriously considered

If it only prints text, is it earning a file? Nearly rejected the step.

Kept because the manual steps are real, easily forgotten, and otherwise recorded
nowhere the machine will show you at the right moment. The reminder appears
immediately after Obsidian is installed, which is when it's actionable. It also
gives the decision somewhere to live: the file's header explains why it *doesn't*
write config, so the next person to think "I should automate this" finds the
reasoning first.

### Sync the vault through this repo instead — rejected

Obsidian vaults are just folders; git could carry one. Rejected because vaults
contain personal notes that don't belong in a machine-setup repo, git handles
large binary attachments poorly, and Obsidian Sync already solves this with
conflict resolution this repo would have to reinvent.

## Consequences

- **The bootstrap does not finish the job.** It installs and reminds; a human
  finishes. This is a deliberate limit, stated plainly, rather than a gap to
  close later.
- **Step 06 is unlike every other step** — it changes nothing. It exists for the
  reminder and for the decision record it anchors.
- **The reminder is easy to miss** in a long run's output, since it's the last
  thing printed after a wall of package installs.
- **Nothing verifies Sync was actually configured.** No follow-up check, no
  record in the run log. A machine can be "fully set up" with Obsidian
  signed out.
- The removal cost nothing on existing machines: `vaultPath` defaulted to `null`,
  so the write path never executed anywhere.
