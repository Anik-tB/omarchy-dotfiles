# Anik's Omarchy dotfiles

My customizations for [Omarchy](https://omarchy.org) (Arch + Hyprland) on an HP EliteBook 830 G5:
the **Anik** morpho-violet theme, the floating-island bar and its `anik.*` shell plugins,
Hyprland overrides, terminal setup and the violet screensaver.

The public theme package lives separately in
[omarchy-anik-theme](https://github.com/Anik-tB/omarchy-anik-theme). This repo is the full,
private backup of my machine's settings.

## How it is stored

A bare git repo at `~/.dotfiles` with `$HOME` as the work tree, so every file is tracked
**where it lives** (no symlinks, no copying). The `anik-dots` command wraps it.

| Command | What it does |
|---|---|
| `anik-dots save "message"` | copy system files, stage every tracked path (new files included), commit, push |
| `anik-dots status` / `diff` / `log` | what changed since the last save |
| `anik-dots restore <file>` | throw away local changes to a file |
| `anik-dots <any git args>` | plain git on this repo |

What gets tracked: [`.config/anik-dots/paths`](../.config/anik-dots/paths).
What is skipped: [`.config/anik-dots/ignore`](../.config/anik-dots/ignore) (`*.bak*`, caches, state).
System files outside `$HOME` (e.g. `/etc/default/limine` with the R75 keyboard USB quirk)
are listed in [`.config/anik-dots/system-files`](../.config/anik-dots/system-files) and
copied into `.config/anik-dots/system/` on each save. Restore those by hand with `sudo`.

## Staying safe across Omarchy updates

`omarchy update` only rewrites `/usr/share/omarchy`, never `~/.config`, so my files are
never overwritten. The real risk is **drift**: a copy of stock code stays behind while
Omarchy changes the code around it. Three rules keep that in check.

1. **Override, don't copy.** Change settings in `shell.json`, `shell.toml`, the theme and
   `~/.config/hypr/*.lua`. Only clone a plugin when its code has to change. To replace one
   stock command, put it in `~/.local/share/anik-overrides/bin/`.
   `~/.config/hypr/overrides.lua` puts that folder ahead of `/usr/share/omarchy/bin` on
   Hyprland's PATH. Example: `omarchy-screensaver` there runs my animation, while the
   stock launcher (monitors, workspaces, window rules) stays stock and keeps getting fixes.
2. **`anik-drift` warns about drift.** [`.config/anik-drift/watch.list`](../.config/anik-drift/watch.list)
   maps each copy or override to the stock files it came from. A baseline of those stock
   files is kept in `.local/share/anik-drift/baseline/`.

   | Command | What it does |
   |---|---|
   | `anik-drift` | which copies' stock sources have changed |
   | `anik-drift diff <name>` | exactly what Omarchy changed. Port what matters into my copy |
   | `anik-drift ack <name>` | mark as reviewed (baseline = current stock) |
3. **A post-update hook** (`.config/omarchy/hooks/post-update.d/anik-after-update`) runs
   after every `omarchy update`. It first runs `anik-dots save` (so anything the update's
   migrations changed in `~/.config` lands in its own commit), then `anik-drift check`
   (desktop notification if any copy drifted).

## Restore on a fresh Omarchy install

```bash
git clone --bare https://github.com/Anik-tB/omarchy-dotfiles.git ~/.dotfiles
git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout -f   # overwrites the default files
git --git-dir=$HOME/.dotfiles config status.showUntrackedFiles no
omarchy theme set anik && omarchy restart shell && hyprctl reload
```

Then copy any `.config/anik-dots/system/etc/...` files back into `/etc` with `sudo` and
run `sudo limine-update`.
