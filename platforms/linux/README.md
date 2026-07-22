# Linux — not implemented yet

Same story as [macOS](../macos/README.md): the manifest already carries an `apt`
ID per package and `dotfiles/links.json` has an empty `linux` array.

## Extra decisions Linux needs

- **Distro dispatch.** `manifest/packages.json` has one `apt` field. If you want
  Fedora/Arch too, either add `dnf` / `pacman` fields alongside it, or change the
  field to an object: `"linux": { "apt": "ripgrep", "dnf": "ripgrep" }`. Prefer
  the second once you need more than two — it keeps the row readable.
- **Packages apt doesn't carry.** `starship`, `zoxide`, `fnm`, `uv`, `eza` and
  `lazygit` are commonly absent or stale in distro repos. Give the manifest an
  optional `installScript` field for those, and have step 01 fall back to it when
  the package-manager ID is null.
- **Step 04.** There's no registry. `04-os-tweaks.sh` becomes `gsettings set`
  for GNOME, or a no-op with a warning under other desktops.
