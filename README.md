# new-machine

Turns a fresh Windows install into my working machine. Idempotent — running it
on an already-configured machine changes nothing and reports all skips.

## Use it

On a brand-new machine, in PowerShell:

```powershell
winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
git clone https://github.com/CobyR/new-machine "$env:USERPROFILE\projects\new-machine"
cd "$env:USERPROFILE\projects\new-machine"

.\bootstrap.ps1 -DryRun     # see what it would do
.\bootstrap.ps1             # do it
```

HTTPS for the first clone because SSH isn't set up yet — step 03 fixes that, and
step 05 clones this repo again to its permanent home if it isn't already there.

Run it **twice**: the first pass installs Git/VS Code/etc., but those only land on
`PATH` for a *new* shell. Open a fresh terminal and re-run to pick up the pieces
that were skipped with a "not on PATH yet" warning. The second pass is fast.

Elevation: everything works unelevated except NTFS long paths, Developer Mode,
and the ssh-agent service. Those are skipped with a note. To get them:

```powershell
.\bootstrap.ps1 -Only os-tweaks     # in an admin terminal
.\bootstrap.ps1 -Only dotfiles      # re-run: real symlinks now that Dev Mode is on
```

### Options

```powershell
.\bootstrap.ps1 -DryRun                  # no changes, just narrate
.\bootstrap.ps1 -Only packages           # one step (matches on filename)
.\bootstrap.ps1 -Only 03,04              # or several, by number
.\bootstrap.ps1 -Skip packages           # everything except
.\bootstrap.ps1 -Tags core,cli           # override config.json's package tags
.\bootstrap.ps1 -ProjectsRoot 'E:\code'  # where repos go (default D:\projects)
.\bootstrap.ps1 -Repos SayWhatTech       # which repo sets to clone
```

A work machine in one line:

```powershell
.\bootstrap.ps1 -Repos Personal,SayWhatTech
```

Steps are also runnable directly, with the same parameters:

```powershell
.\platforms\windows\steps\05-dev-dirs.ps1 -ProjectsRoot 'E:\code' -Repos all
```

## Projects root

`config.json`'s `dev.root` is `D:/projects`, which is right for most of these
machines. When it isn't:

- `-ProjectsRoot 'E:\code'` for a one-off run
- `dev.fallbackRoot` (`{HOME}/projects`) kicks in automatically when `dev.root`
  names a drive the machine doesn't have — so a laptop with no D: drive works
  with no config edit and no `D:\projects` accidentally landing on C:
- a `config.local.json` with `{"dev": {"root": "C:/src"}}` to make it permanent
  on one machine

## Repo sets

`-Repos` picks which groups to clone from `dev.repoSets`. `all` clones every
set, `none` creates the directories and stops. An unrecognized name fails with
the list of valid ones rather than silently cloning nothing.

Two ways to define a set:

```json
"Personal": {
  "path": "personal",
  "repos": ["CobyR/new-machine", "CobyR/computers", "CobyR/network"]
},
"SayWhatTech": {
  "path": "saywhattech",
  "owner": "SayWhatTech",
  "includeAll": true,
  "excludeArchived": true,
  "exclude": [".github"]
}
```

- **Explicit** (`repos`) — a fixed list. Entries can be `owner/name` shorthand or
  a full URL; shorthand becomes SSH, or HTTPS if you set `dev.cloneProtocol`.
- **Dynamic** (`owner` + `includeAll`) — resolved through `gh repo list` at clone
  time, so a new repo in the org gets cloned without editing this file. Filter
  with `excludeArchived` and `exclude`. Both keys together means the explicit
  list is added to the resolved one.

`path` puts a set in its own subdirectory under the root; `null` clones straight
into it. So the layout is:

```
D:\projects\
  personal\      CobyR repos
  saywhattech\   SayWhatTech org repos
  scratch\       dev.subdirs
  forks\
```

`defaultRepoSets` is what runs when you don't pass `-Repos`.

## What it does

| Step | Does |
|------|------|
| `01-packages` | winget-installs everything in `manifest/packages.json` matching your tags, then VS Code extensions from `manifest/vscode-extensions.txt` |
| `02-dotfiles` | Symlinks (or copies) everything in `dotfiles/links.json` into place; writes git identity to `~/.gitconfig.local` |
| `03-ssh-and-signing` | Generates an ed25519 key, starts ssh-agent, `gh auth login`, uploads the key to GitHub, configures SSH commit signing |
| `04-os-tweaks` | Explorer/taskbar/theme settings, NTFS long paths, Developer Mode |
| `05-dev-dirs` | Creates the dev folder layout under the projects root and clones the selected repo sets |
| `06-obsidian` | Prints the manual Obsidian Sync steps after install (touches no Obsidian config) |

Every run is recorded — see [Run log](#run-log) below.

## Configuring it

**`config.json` is the only file you need to edit.** Identity, which package
tags to install, dev folder layout, repos to clone, which OS tweaks to apply.

For settings you want on *this* machine only, drop a `config.local.json` next to
it — it's git-ignored and deep-merged over `config.json`:

```json
{ "packages": { "tags": ["core", "cli"] },
  "osTweaks": { "darkMode": false } }
```

### Adding a package

Add a row to `manifest/packages.json`:

```json
{ "name": "Rust", "tags": ["dev"], "winget": "Rustlang.Rustup",
  "brew": "rustup", "apt": null, "check": "rustup" }
```

`check` is a command name used as a fast "already installed?" probe. `tags`
decide whether it's in your set — `core`, `cli`, `dev`, `apps` install by
default; `optional` only with `-Tags optional`.

Verify an ID before committing it:

```powershell
winget show --id Rustlang.Rustup --exact
```

Every `winget` ID in the manifest has been verified this way. The `brew` and
`apt` columns have **not** — they're placeholders to give the macOS/Linux ports a
starting shape, and each needs checking (`brew info`, `apt-cache show`) before
those bootstraps rely on it.

### Adding a dotfile

Put the file under `dotfiles/`, add an entry to `dotfiles/links.json`:

```json
{ "source": "dotfiles/foo/.foorc", "target": "{HOME}/.foorc", "mode": "link" }
```

`mode: "link"` symlinks, so edits on the machine *are* edits to the repo — the
right choice for anything you hand-edit. `mode: "copy"` is for files an app
rewrites itself (Windows Terminal, VS Code); to pull those changes back:

```powershell
.\platforms\windows\steps\02-dotfiles.ps1 -Export
```

Targets use tokens rather than Windows environment syntax — `{HOME}`,
`{DOCUMENTS}`, `{APPDATA}`, `{LOCALAPPDATA}`, `{REPO}` — so `links.json` stays
readable by a future bash bootstrap. `{DOCUMENTS}` asks Windows where Documents
actually is, which matters when OneDrive has redirected it.

Existing files are moved to `<file>.bak-<timestamp>` before being replaced.
Nothing is destroyed.

## Run log

Every real run appends one JSON Lines record to `logs/runs.jsonl` — host, machine
GUID, OS build, hardware, PowerShell version, repo commit, the flags you passed,
duration, and what changed. Dry runs aren't recorded.

```powershell
.\tools\Show-RunLog.ps1              # one line per run, newest first
.\tools\Show-RunLog.ps1 -ByMachine   # one row per machine, first/last seen
.\tools\Show-RunLog.ps1 -Detail      # full records incl. what changed
```

JSONL rather than a JSON array so appending never rewrites earlier lines;
`.gitattributes` marks the file `merge=union`, so two machines provisioned before
either pushes merge without a conflict. Set `log.autoCommit` / `log.autoPush` in
`config.json` to commit and push the entry automatically — both default to off,
since pushing is a side effect you should opt into.

## Obsidian

Installed by step 01; **its config is deliberately left alone**. Obsidian shows
its normal vault chooser on first launch, which is what you want when the vault
comes from Sync — sign in, connect Sync, and pull the vault down from the remote
rather than pointing Obsidian at a local folder that may not exist yet.

Sync can't be automated regardless: it needs an interactive account login and a
remote-vault picker, with no CLI, config file, or API, and the credentials aren't
something this repo should hold. Step 06 just prints the remaining manual steps
after install. Set `obsidian.remindAboutSync` to `false` to silence it.

## Testing changes

```powershell
.\tests\selftest.ps1        # exercises the real code paths in a sandbox
.\bootstrap.ps1 -DryRun     # end-to-end, no writes
```

`selftest.ps1` covers config loading, JSON validity across the repo, path-token
expansion, the dry-run wrapper, native-command handling, registry idempotency,
the symlink/copy fallback, projects-root resolution (including the missing-drive
fallback), clone-URL normalization, repo-set validity, and manifest sanity (no
duplicate IDs, every `links.json` source exists).

## Layout

```
config.json              the one file you edit
bootstrap.ps1            Windows entry point
manifest/
  packages.json          platform-neutral package list (winget + brew + apt IDs)
  vscode-extensions.txt
dotfiles/                the actual config files, plus links.json (what goes where)
platforms/
  windows/
    lib/common.ps1       logging, dry-run, path tokens, idempotent writes
    steps/01..05
  macos/README.md        what porting takes
  linux/README.md
tests/selftest.ps1
```

Anything platform-neutral (`config.json`, `manifest/`, `dotfiles/`) lives at the
root; anything Windows-specific lives under `platforms/windows/`. Adding macOS
means writing `bootstrap.sh` plus `platforms/macos/` — the manifest already
carries a `brew` ID per package and `links.json` already has a `macos` array.
See [platforms/macos/README.md](platforms/macos/README.md).

## Notes for future me

- **Scripts must be ASCII.** Windows PowerShell 5.1 reads BOM-less `.ps1` as
  Windows-1252, so a UTF-8 em-dash decodes as `â€"` — that `"` terminates the
  string and the file fails to parse. A fresh machine has only 5.1, so the
  bootstrap has to run there.
- **Never redirect a native command's stderr directly.** In 5.1 that wraps each
  line in an ErrorRecord, which under `$ErrorActionPreference='Stop'` turns a
  tool that merely warns into a fatal error. Use `Invoke-NMNative` instead — it
  judges success by exit code only.
- The profile is linked to both PowerShell 7 and 5.1, so it must parse under
  5.1: no `??`, no `?.`, no ternary.
