# Ether Shell

A desktop for Hyprland: bar, drawers, dock, launcher, lock screen,
notifications, screen recording and settings, all themed from your
wallpaper, down to the mouse cursor.

## Install

You need an Arch-based system (Arch, EndeavourOS, CachyOS...) and
Hyprland 0.55 or newer. Paste this in a terminal:

```
curl -fsSL https://raw.githubusercontent.com/VHS33/ether-shell/main/install.sh | bash
```

It asks before installing packages. Anything it replaces is moved to
`~/.config/ether-backup-<time>/` first, so you can go back.

Then log in to Hyprland (or restart it).

## First steps

- **SUPER + comma** opens Settings: set your city for the weather, and your
  monitors.
- **SUPER + /** shows every keybind.
- Pick a wallpaper in Settings and everything recolours to match.
- Your own Hyprland rules go in `~/.config/hypr/user.lua`. Updates never
  touch it.

## Update

Run the same install line again.

## Try it first

To see what it would do first (it downloads its own files, and changes
nothing else):

```
curl -fsSL https://raw.githubusercontent.com/VHS33/ether-shell/main/install.sh | bash -s -- --dry-run
```
