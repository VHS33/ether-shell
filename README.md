# Æther

A complete Hyprland desktop built on [Quickshell](https://quickshell.org):
bar, dock, sidebar, notifications, desktop widgets, lock screen and a full
settings app, all drawn from one wallpaper. Change the wallpaper and every
surface retints: the shell, the terminal, the launcher, window borders, the
lock screen, and GTK and KDE apps.

Everything is configured from a settings panel. You shouldn't need to open
a config file to make Æther yours.

## What's in it

- **Bar**: workspaces, system stats, what's playing (scrolls when it's
  long), volume with a popover, network speed, tray menus and the clock.
- **Sidebar**: clock and weather, quick toggles (sound, microphone,
  network, do not disturb, night light), volume and brightness, media,
  and a calendar with holidays, notes and notifications underneath.
  A clipboard history tab has search.
- **Notifications**: cards with app icons, the app's own buttons, and
  inline replies for apps that support them.
- **Dock**: pinned apps, running apps, window counts, optional auto-hide.
- **Desktop widgets**: clock, weather, calendar, system, media and notes.
  They sit behind your windows, and you drag them into place.
- **Settings**: 22 pages covering appearance, glass and blur, theme
  (Material You styles, light or dark), wallpaper, bar, windows, dock,
  notifications, idle and lock, displays (with a safe revert), keyboard,
  mouse, sound, per-app volume, weather, calendar, widgets, lock screen,
  default apps and system info.
- **Lock screen**: a large thin clock, a greeting, and what's playing.
- **Workspace overview** (ALT + Tab) with live previews and drag to move.

## Requirements

- An Arch-based system: Arch, EndeavourOS, CachyOS and so on.
- **Hyprland 0.55 or newer.** Æther's Hyprland config is Lua, which older
  versions can't read.
- For monitor brightness, monitors with DDC/CI switched on (most desktop
  monitors have it on by default).

## Install

```sh
git clone https://github.com/yourname/aether.git
cd aether
./install.sh --dry-run    # optional: see exactly what it will do
./install.sh
```

The installer:

- installs every dependency, from the official repos where it can and from
  the AUR otherwise (it installs `yay` first if you have no AUR helper);
- moves any config it replaces to `~/.config/aether-backup-<date>/`;
- copies the configs and scripts in, and three wallpapers to
  `~/Pictures/wallpapers`;
- loads `i2c-dev` at boot for brightness, and stops other notification
  daemons (like mako) from taking notifications away from the shell;
- sets up the first colour theme if you run it from inside Hyprland.

Options: `--dry-run`, `--no-packages` (configs only), `--yes` (don't ask).

## First steps

1. Log in to Hyprland, or restart it.
2. Click the clock to open the sidebar, then the gear for Settings.
   - **Weather**: search for your city. Nothing is fetched until you do.
   - **Displays**: choose the main monitor (where the bar and panels live)
     and set each monitor's mode. Changes revert on their own after 15
     seconds unless you press Keep.
   - **Wallpaper**: pick one, or add your own images to
     `~/Pictures/wallpapers`.
3. Press **SUPER + /** any time to see every keybind.

## Keybinds

| Keys | Does |
|---|---|
| SUPER (tap) | App launcher |
| SUPER + T | Terminal |
| SUPER + E | File manager |
| SUPER + R | App launcher |
| SUPER + Q or C | Close window |
| SUPER + SHIFT + V | Toggle floating |
| SUPER + P | Toggle pseudotile |
| SUPER + J | Toggle split direction |
| SUPER + arrows | Move focus |
| SUPER + drag (left / right button) | Move / resize window |
| SUPER + 1 ... 9, 0 | Go to workspace |
| SUPER + SHIFT + 1 ... 9, 0 | Send window to workspace |
| SUPER + scroll | Next / previous workspace |
| ALT + Tab | Workspace overview |
| SUPER + V | Clipboard history |
| SUPER + / | Keybind cheatsheet |
| SUPER + S | Screenshot a region |
| SUPER + SHIFT + S | Screenshot the screen |
| SUPER + H | Wallpaper picker |
| SUPER + L | Lock |
| SUPER + M | Exit Hyprland |
| Media and volume keys | What they say |

Screenshots go to `~/Pictures/screenshots` and the clipboard.

## Where things live

| Path | What |
|---|---|
| `~/.config/quickshell/` | The shell: one QML file per part |
| `~/.config/quickshell/settings.json` | Everything you change in Settings |
| `~/.config/hypr/hyprland.lua` | Hyprland: layout, binds, rules |
| `~/.config/hypr/shell-settings.lua` | Written by Settings, read by `hyprland.lua` |
| `~/.config/matugen/` | How the wallpaper becomes colours for each app |
| `~/.local/bin/setwall` | Sets a wallpaper and retints everything |

Files that Settings writes (`shell-settings.lua`, `hypridle.conf`,
`hyprlock-settings.conf`, kitty's `shell-settings.conf`) say so in their
first line. Change those values in Settings rather than by hand.

## Troubleshooting

**No notifications appear.** Another notification daemon has the service.
Check with
`busctl --user status org.freedesktop.Notifications | grep Comm=`. It
should say `quickshell`. If it says `mako` or `dunst`, remove that
package and restart the shell.

**Restarting the shell.** Stop every copy before starting a new one, or two
will run at once:

```sh
# fish
pkill -x quickshell; while pgrep -x quickshell >/dev/null; sleep 0.1; end; setsid quickshell >/dev/null 2>&1 &
# bash / zsh
pkill -x quickshell; while pgrep -x quickshell >/dev/null; do sleep 0.1; done; setsid quickshell >/dev/null 2>&1 &
```

**Brightness slider missing.** Run `ddcutil detect`. If it lists no
displays, turn on DDC/CI in your monitor's on-screen menu. Laptop screens
use the brightness keys instead.

**Locked out by the lock screen.** Switch to a text console with
Ctrl + Alt + F3, log in, run `pkill -USR1 hyprlock`, then switch back with
Ctrl + Alt + F1 or F2.

**Something broke after an update.** Your previous configs are in
`~/.config/aether-backup-<date>/`.

## Developing

See [docs/DEVELOPING.md](docs/DEVELOPING.md) for how the shell is put
together, and the lessons that cost hours to learn.

## License

MIT. See [LICENSE](LICENSE). The wallpapers in `wallpapers/` are
original and under the same license.
