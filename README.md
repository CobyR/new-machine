# new-machine

Turns a fresh Windows install into my working machine — and keeps the ones I
already have in line. One command, repeatable, safe to run again.

## What it does

`bootstrap.ps1` reads `config.json` and runs six numbered steps in order. What
you end up with:

| Step | Result | Needs admin |
|---|---|---|
| `01-packages` | 31 tools and applications installed via winget, plus VS Code extensions | some installers |
| `02-dotfiles` | git config, PowerShell profile, starship, Windows Terminal and VS Code settings, symlinked out of this repo | no (wants Developer Mode) |
| `03-ssh-and-signing` | ed25519 key generated, agent running, key registered with GitHub, commits signed and showing Verified | ssh-agent service only |
| `04-os-tweaks` | Explorer, taskbar and theme tweaks; NTFS long paths; Developer Mode | long paths + Developer Mode |
| `05-dev-dirs` | Folder layout under `D:\projects`, repos cloned by named set | no |
| `06-obsidian` | Prints the manual Sync steps — deliberately changes nothing | no |

Four properties do most of the work:

- **Idempotent.** Every step checks before it acts. A second run on a configured
  machine changes nothing and reports all skips, so you can re-run it any time
  without thinking about what state you're in.
- **Inspectable.** `-DryRun` narrates the entire plan — every package, every
  file, every registry write — without touching the machine.
- **Selective.** `-Only`, `-Skip`, `-Tags` and `-Repos` let you run one step, a
  minimal package set, or a work machine's repos, from the same config.
- **Self-recording.** Each run appends a record to `logs/runs.jsonl` — host,
  hardware, what changed — then commits and pushes it. The repo accumulates a
  history of every machine it has set up.

Everything that varies by machine lives in `config.json`; everything else is
data (`manifest/packages.json`, `dotfiles/links.json`) rather than code. Adding
a package or a dotfile is a row in a JSON file, not a change to a script.

It's Windows-only today, but the platform-neutral parts sit at the repo root so
macOS and Linux can be added without restructuring.

**Why it's built this way, and what else was considered:**
[docs/decisions](docs/decisions/).

---

## First run on a fresh machine

### 0. Allow scripts to run

Windows PowerShell defaults to `Restricted`, so *nothing* here runs until you
change it. Without this you get:

```
.\bootstrap.ps1 : File ... cannot be loaded because running scripts is disabled
on this system.
```

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`CurrentUser` needs no admin and persists. `RemoteSigned` is enough — `git clone`
doesn't tag files with a Zone.Identifier stream, so these scripts count as local
and don't need to be signed. Check what you've got with
`Get-ExecutionPolicy -List`.

### 1. Get the repo

```powershell
winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
git clone https://github.com/CobyR/new-machine D:\projects\new-machine
cd D:\projects\new-machine
.\bootstrap.ps1 -DryRun          # read the plan before running it
```

HTTPS for this one clone — SSH isn't set up yet. Everything after this is SSH.

### 2. Elevated pass — do this first

```powershell
# in an ADMIN terminal, from the repo
.\bootstrap.ps1 -Only 03,04
```

The only part needing admin: ssh-agent set to auto-start, NTFS long paths, and
**Developer Mode**. Explorer restarts at the end — expect a taskbar flicker.

Developer Mode must be on **before** dotfiles are linked, or they land as copies
and you redo them.

### 3. Open a new, non-admin terminal

Not optional. Symlink privilege is stamped into a process's token when it starts,
so the shell that runs step 02 has to be launched *after* Developer Mode is on.

### 4. Full pass

```powershell
cd D:\projects\new-machine
.\bootstrap.ps1 -Repos none
```

Installs the packages, links the dotfiles, sets up SSH and signing. Docker
Desktop is the slow one and may want a reboot for WSL2.

### 5. New terminal, run it again

```powershell
.\bootstrap.ps1 -Repos none
```

The first pass installs VS Code and friends; they only reach `PATH` in a new
shell. This pass picks up whatever reported *"not on PATH yet"* — VS Code
extensions in particular. It's fast and mostly reports skips.

### 6. Clone the repos

`-Repos none` above is deliberate: the `Personal` set contains **this repo**, so a
normal run would clone a second copy to `D:\projects\personal\new-machine` while
you're working in `D:\projects\new-machine`. Move it first, then clone the rest:

```powershell
Move-Item D:\projects\new-machine D:\projects\personal\new-machine
cd D:\projects\personal\new-machine
.\bootstrap.ps1 -Only 05 -Repos Personal,SayWhatTech
```

Step 05 now sees this repo as already cloned and fetches the others.

### If step 03 warns about GitHub scopes

Registering the signing key needs scopes your token may not have. Run what it
prints, then re-run the step:

```powershell
gh auth refresh -s admin:public_key,admin:ssh_signing_key
.\bootstrap.ps1 -Only 03
```

### Expect commits

Every run appends to `logs/runs.jsonl`, commits it, and pushes. A `git log` full
of `Record setup run on <HOST>` is the machine record building itself, not a
problem. See [Run log](#run-log).

---

## Options

```powershell
.\bootstrap.ps1 -DryRun                  # no changes, just narrate
.\bootstrap.ps1 -Only packages           # one step (substring match on filename)
.\bootstrap.ps1 -Only 03,04              # or several, by number
.\bootstrap.ps1 -Skip packages           # everything except
.\bootstrap.ps1 -Tags core,cli           # override config.json's package tags
.\bootstrap.ps1 -ProjectsRoot 'E:\code'  # where repos go
.\bootstrap.ps1 -Repos SayWhatTech       # which repo sets to clone (or: all, none)
```

Steps run directly too, with the same parameters:

```powershell
.\platforms\windows\steps\05-dev-dirs.ps1 -ProjectsRoot 'E:\code' -Repos all
```

Exit code is `0` when nothing failed, `1` otherwise. Output symbols: `+` changed,
`=` unchanged, `~` would change (dry run), `!` warning, `x` failed.

---

## Configuring it

**`config.json` is the only file you edit.**

| Key | What it controls |
|-----|------------------|
| `identity.name` / `.email` | Written to `~/.gitconfig.local` by step 02 |
| `packages.tags` | Which manifest tags install. Default `core, cli, dev, apps`; `optional` is opt-in |
| `dev.root` | Where repos live (`D:/projects`) |
| `dev.fallbackRoot` | Used when `dev.root`'s drive doesn't exist on this machine |
| `dev.subdirs` | Extra folders created under the root |
| `dev.cloneProtocol` | `ssh` or `https` for `owner/name` shorthand |
| `dev.defaultRepoSets` | What clones when you don't pass `-Repos` |
| `dev.repoSets` | Named sets — see [Repo sets](#repo-sets) |
| `ssh.*` | Key type, filename, comment, whether to upload to GitHub |
| `signing.method` | `ssh`, `gpg`, or `none` |
| `obsidian.remindAboutSync` | Whether step 06 prints its reminder |
| `log.*` | Run log: `enabled`, `path`, `recordChangedItems`, `autoCommit`, `autoPush` |
| `osTweaks.*` | One boolean per Windows setting |

For settings you want on **this machine only**, drop a `config.local.json`
alongside it — git-ignored, deep-merged over `config.json`:

```json
{ "packages": { "tags": ["core", "cli"] },
  "dev":      { "root": "C:/src" },
  "osTweaks": { "darkMode": false } }
```

### Adding a package

Add a row to `manifest/packages.json`:

```json
{ "name": "Rust", "tags": ["dev"], "winget": "Rustlang.Rustup",
  "brew": "rustup", "apt": null, "check": "rustup" }
```

`check` is a command name used as a fast "already installed?" probe. Verify the
ID before committing it:

```powershell
winget show --id Rustlang.Rustup --exact
```

Every `winget` ID in the manifest has been verified this way. `brew` and `apt`
have **not** — they're unverified placeholders for the macOS/Linux ports.

### Adding a dotfile

Put the file under `dotfiles/`, add an entry to `dotfiles/links.json`:

```json
{ "source": "dotfiles/foo/.foorc", "target": "{HOME}/.foorc", "mode": "link" }
```

- `mode: "link"` — symlink. Edits on the machine *are* edits to the repo. Use for
  anything you hand-edit.
- `mode: "copy"` — for files an app rewrites itself (Windows Terminal, VS Code).
  Pull changes back with:

```powershell
.\platforms\windows\steps\02-dotfiles.ps1 -Export
```

Targets use tokens, not Windows environment syntax: `{HOME}`, `{DOCUMENTS}`,
`{APPDATA}`, `{LOCALAPPDATA}`, `{REPO}`. Existing files are moved to
`<file>.bak-<timestamp>` before being replaced.

### Repo sets

`-Repos` picks which groups to clone. `all` clones every set; `none` creates the
directories and stops. An unknown name fails with the list of valid ones.

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

- **Explicit** (`repos`) — fixed list. `owner/name` shorthand or a full URL.
- **Dynamic** (`owner` + `includeAll`) — resolved via `gh repo list` at clone
  time, so new org repos appear without editing config. Both keys together means
  the explicit list is added to the resolved one.

`path` gives a set its own subdirectory under the root:

```
D:\projects\
  personal\      CobyR repos
  saywhattech\   SayWhatTech org repos
  scratch\       from dev.subdirs
  forks\
```

Adding a new owner? Add a matching `insteadOf` rule to `dotfiles/git/gitconfig`
so it stays on SSH — `selftest.ps1` fails if you forget.

---

## Run log

Every real run appends one JSON Lines record to `logs/runs.jsonl`: host, machine
GUID, OS build, hardware, PowerShell version, repo commit, the flags you passed,
duration, and what changed. Dry runs aren't recorded.

```powershell
.\tools\Show-RunLog.ps1              # one line per run, newest first
.\tools\Show-RunLog.ps1 -ByMachine   # one row per machine, first/last seen
.\tools\Show-RunLog.ps1 -Detail      # full records incl. what changed
.\tools\Show-RunLog.ps1 -HostName DESKTOP-X -Last 5
```

`autoCommit` and `autoPush` are both on. The commit is scoped to the log file
alone, so work in progress elsewhere is never swept in. A push rejected because
another machine got there first is rebased and retried once. No network, or no
push access, warns and moves on — the entry goes up with the next run.

---

## Obsidian

Installed by step 01; **its config is deliberately untouched**, so Obsidian shows
its normal vault chooser on first launch. Sign in there, enable Sync, and pull
your vault down from the remote.

Sync can't be automated — no CLI, no config file, no API. Step 06 prints the
manual steps; `obsidian.remindAboutSync: false` silences it.

---

## Testing changes

```powershell
.\tests\selftest.ps1        # 68 assertions against a sandbox, no machine state touched
.\bootstrap.ps1 -DryRun     # end-to-end narration, no writes
```

Run both before committing. Scripts must be **pure ASCII** — check with:

```powershell
Get-ChildItem -Recurse -Include *.ps1 |
  Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '[^\x00-\x7F]' }
```

Anything returned will fail to parse under Windows PowerShell 5.1.

---

## Layout

```
config.json              the one file you edit
bootstrap.ps1            Windows entry point
manifest/
  packages.json          package list, winget + brew + apt IDs
  vscode-extensions.txt
dotfiles/                the config files themselves, plus links.json
platforms/
  windows/
    lib/common.ps1       logging, dry-run, path tokens, idempotent writes
    steps/01..06
  macos/README.md        what porting takes
  linux/README.md
tools/Show-RunLog.ps1
tests/selftest.ps1
logs/runs.jsonl          appended by every run
docs/decisions/          why it's built this way
```

Platform-neutral things (`config.json`, `manifest/`, `dotfiles/`) live at the
root; Windows-specific code lives under `platforms/windows/`.

---

## Working on this repo

Three rules that aren't obvious and will bite:

1. **Scripts must be pure ASCII** — a UTF-8 em-dash breaks parsing under
   PowerShell 5.1, which is all a fresh machine has.
2. **Never redirect a native command's stderr** (`2>$null`, `2>&1`) — use
   `Invoke-NMNative`.
3. **The shared profile must parse under 5.1** — no `??`, no `?.`, no ternary.

The reasoning for each, and for every other structural choice, is in
[docs/decisions](docs/decisions/).
