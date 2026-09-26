# Ether Shell

A complete Hyprland desktop built on [Quickshell](https://quickshell.org),
written from scratch. One long frosted bar across the top, whose sections
pull open into drawers that grow out of the bar itself; a launcher, an AI
assistant, quick settings, lyrics, a dock, desktop widgets, a lock screen and
a full settings app. Everything takes its colours from your wallpaper:
change it and the shell, terminal, window borders, lock screen, and GTK and
KDE apps all retint together.

Everything is configured from the settings panel. You shouldn't need to
open a config file to make Ether Shell yours.

## What's in it

**The bar.** One long bar of frosted glass with its parts in soft
groups: an assistant button, numbered workspaces, system stats, what's
playing (with its cover and a progress line), status icons, the tray and
the clock. Click a part and a drawer grows out of the bar from that spot,
drawn as one shape with it, and slides back in when you click again, click
anywhere else or press Esc. Prefer separate floating pills? Settings, Bar,
Bar style.

**The drawers.**
- **Media** (click the song): cover, controls, a draggable seek bar, a
  switcher when several apps are playing, the app's own volume, a
  visualiser, and **synced lyrics** that scroll along with the song
  (from [LRCLIB](https://lrclib.net)).
- **Quick settings** (click the clock or a status icon): weather with an
  hourly forecast, this month's calendar, a timer and stopwatch, the
  player, tiles for **Wi-Fi** and **Bluetooth** (with pickers that open
  inside the drawer), do not disturb, night light, **game mode** (blur,
  shadows and animations off) and **keep awake**, thick sliders for
  volume, microphone and brightness, output switching, and notifications
  **grouped by app** with a history that survives restarts.
- **System** (click the stats): live graphs for CPU, memory, GPU and GPU
  temperature, and the busiest processes.

**The launcher** (tap SUPER). One search box for everything: apps ranked by
how often you use them, maths (`=`, or just type a sum), emoji (`:`),
clipboard history (`;`), commands (`>`), timers (`timer 5m`) and web
search.

**The assistant** (SUPER + A). A chat panel down the left side of the
screen, using **Claude, Gemini or ChatGPT** with your own API key, set up
from inside the panel. Replies stream in and are formatted. Keys stay on
your computer, in a file only you can read.

**And:** a dock with pinned and running apps; desktop widgets (clock,
weather, calendar, system, media, notes) that sit behind your windows;
notification popups with the apps' own buttons and inline replies; an
on-screen display for volume, microphone, brightness and night light; a
workspace overview (ALT + Tab) with live previews and drag to move; a power
menu with a countdown before anything drastic; a searchable keybind
cheatsheet; and a lock screen with a large clock and what's playing.

**Settings** has 23 pages: appearance, glass and blur, theme (Material You
styles, light or dark), wallpaper, bar, windows, dock, notifications, idle,
lock screen, widgets, displays (with a safe revert), keyboard, mouse, sound,
per-app volume, microphones, weather, calendar, default apps, the AI
assistant and system info.

## Requirements

- An Arch-based system: Arch, EndeavourOS, CachyOS and so on.
- **Hyprland 0.55 or newer.** Ether Shell's Hyprland config is Lua, which older
  versions can't read.
- For monitor brightness, monitors with DDC/CI switched on (most desktop
  monitors have it on by default).
- For the assistant, an API key from Anthropic, Google or OpenAI (optional;
  everything else works without one).

## Install

One line:

```sh
curl -fsSL https://raw.githubusercontent.com/VHS33/ether-shell/main/install.sh | bash
```

That downloads the repo to `~/.local/share/ether-shell` and runs the installer
from there. Running it again later updates it.

Or, to read everything before running it:

```sh
git clone https://github.com/VHS33/ether-shell.git
cd ether-shell
./install.sh --dry-run    # optional: see exactly what it will do
./install.sh
```

The installer:

- installs every dependency, from the official repos where it can and from
  the AUR otherwise (it installs `yay` first if you have no AUR helper);
- moves any config it replaces to `~/.config/ether-backup-<date>/`;
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
| SUPER (tap) | Launcher: apps, maths, emoji, clipboard, commands |
| SUPER + A | AI assistant |
| SUPER + T | Terminal |
| SUPER + E | File manager |
| SUPER + R | rofi (a fallback launcher) |
| SUPER + Q or C | Close window |
| SUPER + SHIFT + V | Toggle floating |
| SUPER + P | Toggle pseudotile |
| SUPER + J | Toggle split direction |
| SUPER + arrows | Move focus |
| SUPER + SHIFT + arrows | Move the window |
| SUPER + CTRL + arrows | Resize the window (hold) |
| SUPER + F | Fullscreen |
| SUPER + SHIFT + F | Maximise (keeps the bar) |
| SUPER + Tab | Last workspace on this monitor |
| SUPER + drag (left / right button) | Move / resize window |
| SUPER + 1 ... 9, 0 | Go to workspace |
| SUPER + SHIFT + 1 ... 9, 0 | Send window to workspace |
| SUPER + scroll | Next / previous workspace |
| ALT + Tab | Workspace overview (Tab again to step, release ALT to go) |
| SUPER + V | Clipboard |
| SUPER + N | Quick settings |
| SUPER + X | Power menu |
| SUPER + , | Settings |
| SUPER + . | Emoji picker |
| SUPER + / | Keybind cheatsheet |
| SUPER + S | Screenshot a region |
| SUPER + SHIFT + S | Screenshot the screen |
| SUPER + H | Wallpaper selector |
| SUPER + L | Lock |
| Media and volume keys | What they say |

In the launcher, start with `=` for maths, `:` for emoji, `;` for the
clipboard or `>` for commands, or type `timer 10m`.

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
| `~/.config/ether/ai/` | Your AI API keys, one file each, readable only by you |
| `~/.local/state/ether/notifications.json` | Notification history |

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

**Icons show as words** (like `volume_up`). The icon font is missing:
`sudo pacman -S inter-font` and `yay -S ttf-material-symbols-variable-git`,
then restart the shell.

**The assistant says a model wasn't found.** Providers rename their models
from time to time. Open the assistant, click the gear, and type a current
model name under Model.

**Something broke after an update.** Your previous configs are in
`~/.config/ether-backup-<date>/`.

## Developing

See [docs/DEVELOPING.md](docs/DEVELOPING.md) for how the shell is put
together, and the lessons that cost hours to learn.

## License

MIT. See [LICENSE](LICENSE). The wallpapers in `wallpapers/` are
original and under the same license.
