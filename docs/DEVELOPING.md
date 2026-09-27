# Developing Ether Shell

How the shell is put together, and what cost hours to learn. Read this
before changing anything, and keep it current: it's the handoff for
whoever works on this next, human or AI.

## Shape of the shell

`shell.qml` is the root. It holds **all shared state** (colours, settings,
the clock, notifications, workspaces, audio, weather and every `Process`)
and passes itself to each module as `app`:

```qml
Sidebar { app: root }
```

Inside a module, shared things are `app.something`, never `root.something`.
A module can't see another module's ids. New shared state goes in
`shell.qml`.

Each module is a `Variants` over `Quickshell.screens`, showing only on
`app.mainScreen` (chosen on the Displays page, else the first screen).

| File | What |
|---|---|
| `Scenes.qml` | Saved desktops: save and restore every window's workspace (`~/.local/state/ether/scenes.json`) |
| `GameWatch.qml` | Recognises games, runs automatic game mode, keeps playtime (`~/.local/state/ether/playtime.json`) |
| `BarStrip.qml` | The long bar's glass, the open drawer's glass **and** its contents, in one window |
| `LeftIsland.qml` | Left section (assistant button, workspaces, stats) and the system drawer |
| `CenterIsland.qml` | Middle section (what's playing) and the media drawer |
| `RightIsland.qml` | Right section (timer chip, status, tray, clock) and quick settings |
| `MediaBody.qml` | The media view, shared by the media drawer and `MediaCard.qml` |
| `Launcher.qml` | The launcher (tap SUPER); `emoji.json` is its emoji list |
| `AiPanel.qml` | The assistant panel down the left side (SUPER + A) |
| `Sidebar.qml` | Right sidebar: clipboard history, and more (SUPER + V) |
| `Popups.qml` | Notification popups |
| `Dock.qml` | Dock, pinned apps, auto-hide |
| `Widgets.qml` | Desktop widgets and arrange mode |
| `SettingsPanel.qml` | The Settings app |
| `Osd, Overview, PowerMenu, Cheatsheet, Spacer` | The rest |
| `BarLeft/Center/Right.qml`, `MediaCard.qml`, `VolumePop.qml` | The older floating pills and popovers, used when a section's drawer is switched off in Settings |

## The long bar and its drawers

Bar style "long" (the default) is one pill across the top; "islands" is
three separate floating pills. `app.barAttached` is true for the long bar.

**One window draws the bar's glass, every drawer's glass, and the open
drawer's contents: `BarStrip.qml`.** It covers the whole screen,
transparent, never resized, and takes clicks only where a drawer is open.
The bar's sections (`LeftIsland`, `CenterIsland`, `RightIsland`) are small
windows of their own above it. Each one builds its drawer's contents in an
item called `drawerHost`, which is **moved into `BarStrip`'s window**
(`app.drawerLayer`). The launcher does the same.

Why one window: two surfaces side by side each get their own blur, so a
join shows as a line; and glass in one window with contents in another
fell out of step in every way possible (glass stuck after closing, glass
missing behind contents, one drawer breaking the rest). In one window,
glass and contents are drawn together in the same frame. See the rules
below; this took a week to learn.

How a drawer opens:

1. A section publishes where its drawer goes, in screen coordinates, to
   `app.leftGeom` / `centerGeom` / `rightGeom` / `launcherGeom`:
   `{ x, w, h, cx, secW, flush }`.
2. Opening sets `cardShown` / `quickShown` / `sysShown` / `launcherShown`.
   `app.drawerNow` says which is open, and `app.drawerTo` where it's
   heading (0 or 1).
3. `BarStrip` animates `p` toward `drawerTo` and writes each step to
   `app.drawerP`. From that, `shell.qml` works out `drawerCurX / W / H`:
   the drawer widens from the section's centre (or, for
   `flush: "left"/"right"`, down the bar's end) and extends downward.
4. `BarStrip` draws the bar and drawer as plain rounded rectangles plus two
   small corner pieces, meeting edge to edge on whole pixels (no overlap,
   no seam), and clips the contents to the same rectangle.

`BarStrip` takes the keyboard for the drawers (when clicked into) and
handles Esc. It also closes things on an outside click: while a drawer, the
launcher or the clipboard is open, its click area becomes the whole screen,
and a click anywhere but the open drawer closes them. The bar's sections sit
above it, so clicking another section still switches drawers.

Only one drawer is open at a time: each `on...ShownChanged` handler closes
the others. `qs ipc call drawer state` prints what the shell believes, and
`qs ipc call drawer reset` closes everything; every open and close is
logged as `drawer:` in the shell's log.

## The native plugin (`native/`)

The work that runs all the time is done in C++, in a small QML module,
`Ether.Native`:

- `SystemStats`: CPU, memory and network read straight from `/proc`, and the
  GPU through NVIDIA's library (NVML), loaded at runtime, so there's no
  `nvidia-smi` running alongside. On other hardware `gpuOk` stays false.
- `CavaReader`: the visualiser's bars, from cava's binary output
  (`config/cava/quickshell-bin.conf`), newest frame only.
- `ArtColors`: accent colours from the current song's album art (a file,
  `file://`, `data:` or http(s) URL), for the media views' `app.mBlue`,
  `mOnAccent`, `mPrimC` and `mOnPrimC`. Greyscale art leaves the theme alone.
  The same component reads the wallpaper (in `NativeStats.qml`) for three
  more things: its `lightness` (Auto light or dark), a `suggestedScheme`
  (Auto colour style: monochrome, neutral, fidelity or tonal spot, from
  Hasler and Susstrunk's colourfulness and how much colour is one hue), and
  `calmSpots()`, the calmest places for widgets by edge detail (Sobel), with
  the wallpaper's crop to the screen taken into account; the shell only
  moves a widget to a spot measuring 8 or less out of 255.
- The colour a theme is built from (the colour source "smart", the default):
  `ArtColors.smartAnalyse`, in OKLab. It trims uniform borders, finds the
  subject (detail and colour that stands out), counts skin tones for less,
  and scores hue families on area, vividness and how much they're the
  subject; `smartSeed` goes to `setwall` as `SEED`, which runs `matugen color
  hex` instead of `matugen image`, and `smartSecond` becomes the shell's
  third accent. Developed against matugen's own picks on 40 real wallpapers
  (a Python prototype, then this; the two agreed on 39 of 40). The lock
  screen's wallpaper comes from `hyprlock-wallpaper.conf`, written by
  `setwall`, since `matugen color` has no image.
- Themes are made in two matugen passes. `config.toml` is the theme itself,
  in the chosen style. `config-terminal.toml` is the colours that must keep
  their meaning (the terminal's 16, and fish, btop, starship and Discord,
  which use them), always in the tonal spot style: monochrome turns them all
  white and content turns the bright ones black. kitty includes both
  (`colors.conf`, `ansi.conf`). The shell's third accent (`thirdAccent`)
  comes from the picture: its second colour, or a close neighbour of the main
  one, never Material's rotated hue.

The installer builds it with CMake into `~/.local/lib/ether-shell/qml`, and
`ether-shell` adds that to `QML_IMPORT_PATH`. **It's optional.**
`NativeStats.qml` is the only file that imports it, and `shell.qml` loads it
through a `Loader`. If the module is missing, that load fails and the shell
starts its own readers (`statsProc`, `gpuStream`, `cavaProc`) instead, so
the plugin can never take the shell down. Build it by hand with:

```sh
cmake -S native -B /tmp/ether-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/ether-build && cmake --install /tmp/ether-build
```

Rebuild after a Qt major update (re-running the installer does it).

## Features that keep state in `shell.qml`

- **Launcher**: results are plain values; apps are looked up with
  `DesktopEntries.byId` when launched. Launch counts are a setting
  (`launchCounts`). The calculator only evaluates input made of numbers,
  operators, brackets and a short list of named functions.
- **Wi-Fi and Bluetooth**: `nmcli` and `bluetoothctl`, always run with
  arguments as a list, never through a shell with names pasted in. `nmcli
  -t` escapes `:` inside fields; `nmFields()` splits it by hand (Qt's JS
  engine may not support regex look-behind).
- **Game mode** is a setting (`gameMode`) written to `shell-settings.lua`
  as `game_mode`; `hyprland.lua` turns blur, shadows and animations off
  for it, and `app.motionOn` goes false for the shell.
- **Keep awake** holds `systemd-inhibit --what=idle:sleep` while it's on;
  hypridle honours it.
- **Notifications** carry a timestamp (`ts`), are grouped by app
  (`notifGroups`), and are saved to
  `~/.local/state/ether/notifications.json` (the newest 100) and read
  back at startup, marked `saved` with their buttons stripped.
- **Lyrics** come from lrclib.net, fetched only while the media drawer is
  open, once per song, cached for 40. The track's details go to `curl` as
  arguments.
- **Timer and stopwatch** keep times against the clock (when it ends,
  when it started), never by counting ticks.
- **The assistant** talks to Anthropic, Google or OpenAI with the user's
  key. Keys live one per file in `~/.config/ether/ai/` (mode 600),
  written through **stdin**; each request copies the key into a private
  temporary header file for curl (`-H @file`), so it never appears in a
  process's arguments. The request body also goes through stdin. Replies
  stream (server-sent events); each provider's format is parsed in
  `aiProc`.

## Settings

`~/.config/quickshell/settings.json` holds **only what the user changed**.
`shell.qml` merges it over `cfgDefaults` into `app.cfg`, so a missing or
broken file changes nothing. Readers always clamp: `app.cfg.x` may be
anything a hand edit put there.

- `app.setting(key, value)`, `app.resetSetting(key)`, `app.resetAllSettings()`
  write through a temp file and a rename, one write at a time.
- `applyExternal(key)` pushes a change to anything outside Quickshell:

| Written file | By | Read by |
|---|---|---|
| `~/.config/hypr/shell-settings.lua` | `writeHypr()` | `hyprland.lua` at the top, then `hyprctl reload` |
| `~/.config/hypr/hypridle.conf` | `writeIdle()` (whole file) | hypridle, restarted |
| `~/.config/hypr/hyprlock-settings.conf` | lock settings | `hyprlock.conf` via `source =` |
| `~/.config/kitty/shell-settings.conf` | `writeKitty()` | kitty include, `SIGUSR1` |
| `~/.config/matugen/shell-theme` | theme settings | `setwall` sources it |

Only keys the user changed go into `shell-settings.lua`; `hyprland.lua`
supplies every default itself. Add a Hyprland setting in three places: the
default in `hyprland.lua`, the key in `hyprKeys` in `shell.qml`, and the
control in `SettingsPanel.qml`.

`qs ipc call settings sync` rewrites the generated files, for after
`settings.json` was edited by hand.

## Settings panel

A layer surface, not a toplevel, so Hyprland never tiles it. It's a
transparent full-screen window with the card moving inside it. Moving the
surface itself made drags shake. Pages are numbered in `pages`, and each
page is a `ColumnLayout` with `visible: win.page === N`. The navigation
order is separate from those numbers, so new pages go at the end of the
numbering and anywhere in the navigation.

The building blocks are inline components: `Card`, `Seg`, `Slider` (which
is a − value + stepper), `ChoiceRow`, `Chip`, `IconBtn`, `DeviceRow`,
`StreamCard`.

## Rules that prevent crashes and bugs

- **Never put live QObjects in plain JS arrays used as models.** Three
  segfaults came from this: a notification or window dies, the model entry
  still points at it, and Qt crashes building the next delegate. Model
  entries hold plain values; live objects stay in a lookup keyed by id
  (`app.notifRefs`), or use a real ObjectModel (`Pipewire.nodes`).
- **A function can't be named after a property's change signal.**
  `function draftChanged()` beside `property var draft` stops the whole
  file from loading.
- **Inline components can't nest**, and can't see the file's ids. Pass
  `app` in as a property.
- **A layout only stretches if one of its children does.** Give a child
  `Layout.fillWidth: true`, not just the layout.
- **Don't bind `running:` on a Process and also assign it**: the
  assignment breaks the binding for good.
- **Qt's `h` is only 12-hour when `AP` is in the same format string.**
  Format with `"h:mm AP"` and split it, don't format `"h:mm"` alone.
- **`Rectangle { clip: true }` clips square**, not to its radius. Rounded
  images use `MultiEffect` with a mask (see `RoundImage` in `Sidebar.qml`).
- **Popups must not take keyboard focus.** An `OnDemand` layer is focused
  the moment it maps, which steals typing from the window you're in.
- **Panels that open often stay mapped** and slide their content in
  (sidebar). Mapping a new surface each time, plus Hyprland's layer
  animation, is what made opening lag.
- **Main-screen panels are built once.** Each module is a `Variants` over the
  screens, but its window sits inside a `LazyLoader` that's only active for
  `app.mainScreen`, so the other monitors' copies stay empty. Building a
  hidden copy per monitor doubled memory and background work, and hidden
  copies writing shared state caused doubled and stuck drawers. Only
  `Widgets` is genuinely per-screen. Shared values set
  with `Binding` use `restoreMode: Binding.RestoreNone`.
- **Never split one visual thing across two windows.** Glass drawn in one
  window with its contents in another, kept in step by a shared number,
  broke in a new way every time it was patched. Put them in one window
  (move the item there with `parent:`), and there's nothing to keep in
  step.
- **Layer windows stack in the order they appear.** A window that's hidden
  and shown again comes back on top of everything. Anything that must stay
  underneath (the bar's glass, the click catcher) stays shown and simply
  draws nothing when it isn't needed.
- **Don't resize a layer window after it's shown.** A window meant to grow
  once its contents had measured themselves sometimes didn't, and what was
  drawn below its old edge was cropped away. Give it its full size from the
  start and use a mask for clicks.
- **Qt's `Shape.CurveRenderer` can stop drawing** after an outline that
  touches itself. Plain rounded `Rectangle`s (with per-corner radii) are
  sturdier for anything that animates.
- **Only one handler per signal per object.** Two `onQuickShownChanged:`
  in `shell.qml` is a load error. Search before adding a handler, and merge
  into the one that's there.
- **All motion takes its length from `app.animQuick / animNormal /
  animSlow` (or `app.dur(ms)`)**, so the Animation speed setting and game
  mode reach everything.
- **Pills and drawers clip to their own shape**, so a tooltip hanging
  below one is cut off. Reveal extra detail inline instead (the hover
  slide-outs in the bar).

## Hyprland (0.55+, Lua)

- The config is **Lua**, and most guides online are for the old syntax.
  `/usr/share/hypr/stubs/hl.meta.lua` is the authoritative API reference.
  Read it before guessing a name.
- `hyprctl dispatch` takes Lua: `hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'`.
- Hyprland watches `hyprland.lua` but **not** files it `dofile()`s: after
  writing one, run `hyprctl reload`.
- `pcall(dofile, colors.lua)` stays the **last line**: the last setter of
  `general.col` wins.
- Bare-modifier binds (tap SUPER) need `ignore_mods = true`.
- Workspace rules apply **when a workspace is created** only.
- Springs ignore an animation's `speed`; scale the spring instead. Spring
  mass below 0.5 is rejected, so speed up by raising stiffness.
- Monitors not named in the settings get no rule, and Hyprland gives them
  their preferred mode and places them automatically.
- hyprlock and hypridle still use hyprlang, not Lua. In hyprlang, `#`
  starts a comment (write `##` for a literal one), and `$name` is a
  variable. Keep shell variables out of `cmd[]` labels, and use `$(...)`.

## Theming

`setwall <image>` sets the wallpaper and runs matugen with the style,
contrast, colour source and mode from `shell-theme`. Every template uses
`.default` colours (never `.dark`), so light mode follows automatically.

- matugen 4 **needs `--prefer`**. Without it, it stops to ask which colour
  to use, and with no terminal (rofi, the panel) it fails outright.
- The Quickshell hook is `qs ipc call theme reload`, never a restart,
  which would close whatever panel is open.
- KDE apps only repaint when told to: `setwall` sends
  `org.kde.KGlobalSettings.notifyChange` **after** matugen finishes. Sent
  from a template hook, it raced the `kdeglobals` write.
- GTK light/dark comes from `gsettings` (`color-scheme`, `gtk-theme`), not
  from colours alone.

## Notifications

Quickshell owns `org.freedesktop.Notifications`. Nothing else may: if mako,
dunst or Plasma's notifier holds it, the shell shows nothing. The installer
drops `~/.local/share/dbus-1/services/org.freedesktop.Notifications.service`
pointing at `/bin/false`, so D-Bus can't auto-start another daemon.

## Working on it

- **Read the stubs or the source before writing.** Guessed API names cost
  hours, every time.
- **One change at a time, and test between.** Batched changes made failures
  ambiguous.
- **Know how to undo a risky change before making it** (monitors, idle,
  the lock screen).
- **Restart the shell properly.** `pkill` returns before the old process
  exits, so a quick restart runs two shells, and the second can't register
  notifications. Wait in a loop until `pgrep` finds nothing.
- **The user's shell may be fish**: `while ...; ...; end`, not `do ... done`.
- Lint with `qmllint` (it catches syntax, not runtime errors), check
  braces balance, then watch Quickshell's log on the first run.
- File search (`FileIndex`, in `NativeStats.qml`): every file and folder in
  home, minus hidden folders, dependency and cache folders (anything with a
  `CACHEDIR.TAG`) and game internals. 16 bytes a node, names in one shared
  arena (about 5 MB for 80,000 entries); scanned on a thread at start-up,
  kept live with inotify (within half the kernel's watch budget), rescanned
  every 30 minutes. Searches run on a thread; `resultsFor` says which query
  results belong to, so the launcher never shows a stale search. `/` in the
  launcher is files only; files also follow apps from three letters.
- `local/bin/ocr` (SUPER + SHIFT + T): slurp, grim at 2x, Tesseract, wl-copy.
- Wi-Fi and Bluetooth: `NetNative.qml` uses Quickshell's own
  `Quickshell.Networking` (NetworkManager) and `Quickshell.Bluetooth` (BlueZ)
  modules, live, nothing polled. `shell.qml` loads it with a Loader and binds
  its values onto the same properties the nmcli and bluetoothctl code sets,
  so on a Quickshell without those modules it fails to load and the old code
  carries on. Tested against stand-in modules built from the 0.3.0 source's
  API (passwords, wrong passwords, open networks, scanning, pairing).
- Brightness: `Ddc` (native/src/ddc.*, the protocol in ddcproto.h) talks
  DDC/CI to /dev/i2c-N directly, framed as ddcutil frames it (checked
  against ddcutil's source and its unit test's checksum). Buses stay open;
  a background thread sends only the newest value per monitor, 50 ms apart
  (40 ms between a get and its reply); plain write()/read(), which NVIDIA's
  driver accepts. ddcutil still maps connectors to buses at start-up, and
  any monitor the direct route fails for uses ddcutil from then on.
- The visualiser: `AudioBars` (native/src/audiobars.*, the analysis in
  spectrum.h) captures the default output's monitor from PipeWire
  (stream.capture.sink, so no microphone and not listed as recording) and
  computes 28 bars itself: a 4096-point FFT, bands from 50 Hz to 10 kHz
  spaced by pitch, linear strength lifted with pitch, each band evened out
  against its own recent peaks (0.5x to 3x), cava-style automatic
  sensitivity, gravity and smoothing; values 0-100 as cava's reader gives
  them. Tuned live against cava on the same audio: about 1.3x cava's bar
  swing, 2.7x the log-scale version it replaced. Only while the media drawer is open. Tested against a real
  PipeWire daemon with test tones and drums; about 0.6% of a core. Built
  only when libpipewire-0.3 is found; otherwise, or if PipeWire can't be
  reached, cava runs as before.
- The clipboard: `ClipboardHistory` (native/src/clipboard.*) has its own
  Wayland connection, on its own thread, using the wlr data-control protocol
  (native/protocols/, bindings generated by wayland-scanner at build time).
  One poll loop covers the compositor, incoming data and outgoing data, so
  copying from our own history never waits on itself; SIGPIPE is blocked on
  that thread. Text up to 5 MB and pictures up to 40 MB are kept in
  ~/.local/share/ether-shell/clipboard/ (0700, files 0600); duplicates move
  up; x-kde-passwordManagerHint copies are never kept; when the app that
  copied goes away, the last copy is offered again (not at login). cliphist's
  history is imported once. Without the protocol (or Wayland development
  files at build time) the shell starts wl-paste and cliphist watchers
  itself. Tested against headless sway.
- The accent in every app: setwall takes a quick look at the new palette
  (a one-line probe template), works out the accent (Vivid: the smart colour
  lightened only to 4.5:1 on the new background, in awk, the same rule as the
  shell's readableAccent, checked colour for colour; Soft: Material's
  primary) and adds it to both passes as the custom colours vivid and
  on_vivid (blend off). Templates use vivid_value / on_vivid_value for
  accents; container colours stay Material's. The shell reads pal.vivid, so
  the bar and every app match exactly.
- The palette from the picture: with the vivid accent, the second and third
  colours are the picture's own (ArtColors.smartSecond / smartThird: its
  other colour families, each 35 degrees apart and at least 2% of it, then
  its neutral tone), made readable by setwall's readable() (the same rule as
  the accent) and passed to the templates as the custom colours second and
  third. A dull yellow-green (OKLab hue 90-125, chroma under 0.10) is
  penalised as an accent, as Material's DislikeAnalyzer does. Checked on 43
  pictures that every colour in each theme is one the picture has.
- The login screen: config/ether-greeter (greeter.qml wraps GreeterView.qml,
  which is plain QtQuick and testable alone). install-greeter.sh puts it in
  /etc/ether-greeter, verifies its Hyprland config (hyprland.lua, started by
  greetd as "start-hyprland -- --config ..."), sets up /var/lib/ether-greeter
  (group ether-greeter, 2775, plus an ACL for the installing user) where each
  user's shell shares its wallpaper, colours and main screen, records the
  previous display manager and switches to greetd. uninstall-greeter.sh
  reverses it. Both honour ETHER_TEST_ROOT and --dry-run; tested end to end
  in a test root (install, re-install, undo).
- UWSM: hyprland.lua reads /proc/self/cgroup at load (a wayland-wm@ unit
  means UWSM; never run a program there: Hyprland waits for its config); under UWSM
  its long-running programs and app keybinds go through `uwsm-app --` (or
  `uwsm app --`), the shell's launchEntry does the same (appLauncher), and
  ether-shell starts quickshell with `uwsm app -s b --` (a scope keeps the
  script's environment). Plain Hyprland is unchanged. Variables for UWSM are
  in ~/.config/uwsm/env and env-hyprland (never overwritten by the
  installer); hyprland.lua keeps its hl.env lines for the plain session.
- The login screen for real: `sudo ether-login install` installs greetd and
  greetd-agreety, copies config/ether-greeter to /etc/ether-greeter, makes
  /var/lib/ether-greeter the user's (the shell shares its look there) and
  /var/cache/ether-greeter the greeter's, writes /etc/greetd/config.toml
  (backing up the old one) and switches display-manager.service to greetd,
  remembering the previous one for `ether-login undo`. greetd runs
  /etc/ether-greeter/start: start-hyprland with the greeter's own
  hyprland.lua, which runs greeter.qml and exits with it; the greeter marks a
  sign-in just before launching, and without that mark the script falls back
  to agreety (so a broken login screen never locks anyone out). Rehearsed on
  a pretend root with ETHER_ROOT.
