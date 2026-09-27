# Ether Shell

A complete Hyprland desktop built on [Quickshell](https://quickshell.org),
written from scratch. One long frosted bar across the top, whose sections
pull open into drawers that grow out of the bar itself, with a dynamic island
in the middle; a launcher, a clipboard, an AI chat, quick settings, lyrics, a
desktop that notices your games, saved desktop layouts, a dock, widgets, a
lock screen, a login screen and a full settings app. Everything takes its colours from your
wallpaper, and fades to the new ones when you change it: the shell, terminal,
prompt, window borders, lock screen, GTK and KDE apps, and more.

It's light: around 440 MB and well under 1% of one CPU core while idle, with
the continuous work (system stats, the GPU, the visualiser, the clipboard,
file search, monitor brightness, wallpaper colours) done in a small C++
plugin.

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

**Workspaces**, as numbers or as the icon of the app on each, and hover one
for a live preview of it. A second monitor gets its own set, and SUPER + 1-5
reach them while it has focus.

**The dynamic island.** The middle of the bar briefly grows to show what
just happened: volume and brightness changes, the next song, a timer
finishing, a game session ending, a scene saved or restored.

**The drawers.**
- **Media** (click the song): cover, controls, a draggable seek bar, a
  switcher when several apps are playing, the app's own volume, a
  visualiser, and **synced lyrics** that scroll along with the song
  (from [LRCLIB](https://lrclib.net)).
- **Quick settings** (the ☰ button, the clock, or a status icon): weather with an
  hourly forecast, this month's calendar, a timer and stopwatch, the
  player, tiles for **Wi-Fi** and **Bluetooth** (with pickers that open
  inside the drawer, and battery levels for Bluetooth devices), do not disturb, night light, **game mode** (blur,
  shadows and animations off) and **keep awake**, thick sliders for
  volume, microphone and brightness (monitor brightness changes as you drag), output switching, and notifications
  **grouped by app** with a history that survives restarts.
- **System** (click the stats): live graphs for CPU, memory, GPU and GPU
  temperature, the busiest processes, and this week's playtime.

**The launcher** (tap SUPER). A floating search box for everything: apps
ranked by how often you use them, maths (`=`, or just type a sum), emoji
(`:`), clipboard history (`;`), commands (`>`), scenes (`@`), timers
(`timer 5m`) and web search.

**Files, as you type.** The launcher finds your files too: `/` for files
only, or just type and the best matches appear under your apps. Fuzzy
(`q3rep` finds `Q3 report.pdf`), several words at once, recent files first,
kept up to date as files change. Enter opens, Alt + Enter shows it in its
folder. App search forgives a typo (`fierfox`).

**Copy text from the screen** (SUPER + SHIFT + T). Select any area (a video,
an image, a game, an app that won't let you select) and its text is copied.

**The clipboard** (SUPER + V). A panel down the right side: search, text or
images (copied pictures show as thumbnails), Enter to copy back. What you
copy stays on the clipboard after you close the app you copied it from, and
copies a password manager marks secret are never kept.

**The assistant** (SUPER + A). A chat panel down the left side of the
screen, using **Claude, Gemini or ChatGPT** with your own API key, set up
from inside the panel. Replies stream in and are formatted. Keys stay on
your computer, in a file only you can read.

**Games.** Steam games (native or Proton) are recognised by themselves, and
others can be marked once. While one runs, the desktop switches into game
mode (animations and blur off, notifications held) and puts everything back
when it closes, and the island shows how long you played. Variable refresh
rate and direct scanout for fullscreen games are in Settings.

**Scenes.** Save your whole layout (which apps, on which workspace and
monitor) under a name, and restore it later: apps that are open are moved
back, apps that aren't are started. Nothing is ever closed.

**Colours from your wallpaper, done properly.** Ether Shell picks the colour
that matters in a wallpaper (the red poppies, not the dark field around them;
the subject, not a face's skin tones or a picture's border), and builds the
palette from the wallpaper's **own** colours, so nothing in it is a colour
the picture doesn't have. The accent is the wallpaper's real colour, not a
washed-out version, only lightened when it wouldn't be readable, and it's the
same everywhere: the shell, window borders, the terminal and prompt, the lock
screen, GTK and KDE apps, even Dolphin's folders. (Prefer Material You's
softer accents? Settings, Theme, Accent.) Terminal colours keep their meaning
(red is red, green is green) and stay readable. Swatches in the wallpaper
selector show each wallpaper's colours before you pick it; Auto picks light
or dark by how bright the wallpaper is; and while music plays, the media
views take their colours from the album art. Also themed:
kitty, fish, starship, btop, rofi, GTK and KDE apps, Firefox (through its
system theme, or Pywalfox) and Discord (through Vencord or Vesktop).

**And:** a dock with pinned and running apps; desktop widgets (clock,
weather, calendar, system, media, notes) that sit behind your windows;
notification popups with the apps' own buttons and inline replies; an
on-screen display for volume, microphone, brightness and night light; a
workspace overview (ALT + Tab) with live previews and drag to move; a power
menu with a countdown before anything drastic; a searchable keybind
cheatsheet; and a lock screen with a large clock and what's playing.

**The login screen** (optional). A sign-in screen in the same style, instead
of SDDM: your wallpaper, blurred, with the clock and a sign-in card on your
main monitor. It shows the look of whoever signed in last, or a background of
its own (Settings, Lock screen). See [The login screen](#the-login-screen).

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

- installs every dependency, all from the official Arch repos (versions you
  already have from the AUR, like `quickshell-git`, are left alone);
- builds the small C++ plugin (`native/`); if that fails, the shell still
  works, just a little less efficiently;
- moves any config it replaces to `~/.config/ether-backup-<date>/`;
- copies the configs and scripts in, and three wallpapers to
  `~/Pictures/wallpapers`;
- loads `i2c-dev` at boot for brightness, and stops other notification
  daemons (like mako) from taking notifications away from the shell;
- sets up the first colour theme if you run it from inside Hyprland;
- keeps your own kitty settings (like `shell fish`) in
  `~/.config/kitty/user.conf`, which updates never touch, and moves aside any
  `quickshell.service` from another setup, which would start the shell twice.

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

## UWSM (optional)

[UWSM](https://github.com/Vladimir-csp/uwsm) runs your session under systemd,
as Hyprland recommends: apps each run as their own unit (contained, closed
cleanly when you log out, with their own memory and CPU use), and services
that start with the session get the right environment. The installer adds
it; to use it, choose **Hyprland (uwsm-managed)** at login instead of
Hyprland. Ether Shell notices and launches apps through it; everything also
works as before in the plain session. Environment variables for a UWSM
session go in `~/.config/uwsm/env` (and `env-hyprland`), not in
`hyprland.lua`.

## The login screen

Optional, and a single command either way. It replaces your current login
manager (SDDM, for example) with greetd showing Ether Shell's own login
screen, from the next boot:

```sh
sudo ~/.local/bin/ether-login install    # set it up
sudo ~/.local/bin/ether-login undo       # back to what you had
~/.local/bin/ether-login status          # which one is in use
```

It signs you straight into Hyprland (with UWSM, or on its own). If the login
screen ever can't start, a plain text login appears in its place, so you're
never locked out; Ctrl + Alt + F2 gives a text console as always. Settings,
Lock screen has its background (your wallpaper, or one of its own) and a
preview.

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
| SUPER + SHIFT + T | Copy text from the screen |
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
| `~/.local/share/ether-shell/clipboard/` | Clipboard history, readable only by you |
| `~/.config/kitty/user.conf` | Your own kitty settings (your shell, font...), never overwritten |
| `~/.config/uwsm/` | The environment for a UWSM session |
| `~/.config/ether-greeter/` | The login screen (installed to `/etc/ether-greeter/`) |
| `/var/lib/ether-greeter/` | The look your desktop shares with the login screen |

Files that Settings writes (`shell-settings.lua`, `hypridle.conf`,
`hyprlock-settings.conf`, kitty's `shell-settings.conf`) say so in their
first line. Change those values in Settings rather than by hand.

## Troubleshooting

**No notifications appear.** Another notification daemon has the service.
Check with
`busctl --user status org.freedesktop.Notifications | grep Comm=`. It
should say `quickshell`. If it says `mako` or `dunst`, remove that
package and restart the shell.

**The native plugin didn't build.** Ether Shell works without it, using its
own readers for the stats and visualiser. To build it, install `cmake` and
`base-devel` and re-run the installer.

**Restarting the shell.** Run `~/.local/bin/ether-shell`. It stops the
running shell first (so two never run at once) and keeps it on NVIDIA's
driver alone when that's installed. Its log is
`$XDG_RUNTIME_DIR/ether-shell.log`.

**Brightness slider missing.** Run `ddcutil detect`. If it lists no
displays, turn on DDC/CI in your monitor's on-screen menu. Laptop screens
use the brightness keys instead.

**Locked out by the lock screen.** Switch to a text console with
Ctrl + Alt + F3, log in, run `pkill -USR1 hyprlock`, then switch back with
Ctrl + Alt + F1 or F2.

**Icons show as words** (like `volume_up`). The icon font is missing:
`sudo pacman -S inter-font ttf-material-symbols-variable`,
then restart the shell.

**The assistant says a model wasn't found.** Providers rename their models
from time to time. Open the assistant, click the gear, and type a current
model name under Model.

**The login screen isn't right, or you want SDDM back.** Run
`sudo ~/.local/bin/ether-login undo` and restart. From a text console
(Ctrl + Alt + F2) if need be.

**Two bars, or everything slow, in a UWSM session.** A `quickshell.service`
from another setup is starting a second copy. Check with
`pgrep -xc quickshell` (it should say 1); the installer moves such a service
aside, or rename `~/.config/systemd/user/quickshell.service` yourself and
run `systemctl --user daemon-reload`.

**kitty starts bash instead of your shell.** Put `shell fish` (or zsh...) in
`~/.config/kitty/user.conf`.

**Something broke after an update.** Your previous configs are in
`~/.config/ether-backup-<date>/`.

## Developing

See [docs/DEVELOPING.md](docs/DEVELOPING.md) for how the shell is put
together, and the lessons that cost hours to learn.

## License

MIT. See [LICENSE](LICENSE). The wallpapers in `wallpapers/` are
original and under the same license.
