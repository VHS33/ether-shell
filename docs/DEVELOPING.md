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
| `BarStrip.qml` | The long bar's glass, the open drawer's glass **and** its contents, in one window |
| `LeftIsland.qml` | Left section (assistant button, workspaces, stats) and the system drawer |
| `CenterIsland.qml` | Middle section (what's playing) and the media drawer |
| `RightIsland.qml` | Right section (timer chip, status, tray, clock) and quick settings |
| `MediaBody.qml` | The media view, shared by the media drawer and `MediaCard.qml` |
| `Launcher.qml` | The launcher (tap SUPER); `emoji.json` is its emoji list |
| `AiPanel.qml` | The assistant panel down the left side (SUPER + A) |
| `IslandCatcher.qml` | Invisible layer under the drawers: a click outside closes them |
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

`BarStrip` takes the keyboard for the launcher (always) and other drawers
(when clicked into), and handles Esc. `IslandCatcher` sits above it with a
hole cut where the drawer is, so a click outside closes the drawer and a
click inside reaches it.

Only one drawer is open at a time: each `on...ShownChanged` handler closes
the others. `qs ipc call drawer state` prints what the shell believes, and
`qs ipc call drawer reset` closes everything; every open and close is
logged as `drawer:` in the shell's log.

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
- **Every module is a `Variants`, so there's one copy per screen**, even
  though only the main screen's is shown. Any copy that writes shared state
  must check it's the visible one. A hidden `BarStrip` finishing its own
  animation late and writing "open" is what left empty drawers stuck
  on screen. (`Binding { when: ...visible }` does the same for bindings.)
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
