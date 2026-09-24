# Developing Æther

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
| `BarLeft/Center/Right.qml` | The three bar pills |
| `Sidebar.qml` | Right sidebar: tiles, sliders, media, calendar, notifications, clipboard |
| `Popups.qml` | Notification popups |
| `VolumePop.qml` | Popover under the volume segment |
| `Dock.qml` | Dock, pinned apps, auto-hide |
| `Widgets.qml` | Desktop widgets and arrange mode |
| `SettingsPanel.qml` | The Settings app |
| `MediaCard, Osd, Overview, PowerMenu, Cheatsheet, Spacer` | The rest |

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
