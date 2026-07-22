# macOS — not implemented yet

The cross-platform pieces already exist and need no changes:

- `config.json` — identity, dev root, tweak flags
- `manifest/packages.json` — every entry already carries a `brew` ID
- `dotfiles/links.json` — has an empty `macos` array with the same schema
- `dotfiles/git/*`, `dotfiles/starship/*` — already platform-neutral

## To add macOS

1. Write `bootstrap.sh` at the repo root, mirroring `bootstrap.ps1`: read
   `config.json` with `jq`, dispatch on `uname`, run `platforms/macos/steps/*.sh`
   in order.
2. Port `platforms/windows/lib/common.ps1` to `platforms/macos/lib/common.sh` —
   the same six primitives (logging, dry-run wrapper, path-token expansion,
   command probe, directory create, idempotent setting write).
3. Write the steps with matching numbers so `-Only 03` means the same thing on
   both platforms:

   | Step | Windows | macOS equivalent |
   |------|---------|------------------|
   | 01 | winget | `brew install` / `brew install --cask` |
   | 02 | symlink dotfiles | same, `ln -sfn` (no privilege problem) |
   | 03 | ssh-agent, gh, SSH signing | identical except agent uses `--apple-use-keychain` |
   | 04 | registry tweaks | `defaults write` |
   | 05 | dev dirs + clones | identical |

4. Fill the `macos` array in `dotfiles/links.json` (zsh profile, `~/.config/starship.toml`,
   `~/Library/Application Support/Code/User/settings.json`).
5. Add a `macos` block to `config.json` alongside `osTweaks` for `defaults write`
   settings (Dock autohide, key repeat rate, Finder path bar, screenshot location).

Anything you find yourself hardcoding into a step is a sign it belongs in
`config.json` or the manifest instead.
