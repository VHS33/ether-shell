# Changelog

## v0.5

### New
- **Plugins.** Add-ons in `~/.config/ether-shell/plugins`, switched on in
  Settings, Plugins: bar items, launcher results (among the usual ones, or
  after a prefix), desktop widgets, and settings of their own. A plugin with a
  mistake is set aside, with its error shown, and the rest carries on. Three
  examples come with it: Uptime (bar), Wikipedia (launcher, `!w`) and
  Countdown (desktop widget). Start your own with `ether plugin new NAME`; the
  guide is `~/.config/ether-shell/PLUGINS.md` (docs/PLUGINS.md here).
- **The `ether` command.** `ether doctor` checks the whole setup and says what
  to fix; also `ether restart`, `ether wallpaper`, `ether theme`,
  `ether login`, `ether plugin list | new | reload`. Tab completion in fish.
- **The dock**, reworked: a right-click menu (the app's windows, new window,
  its own actions, pin, close); live window previews on hover; drag to reorder,
  or to pin a running app; scroll through an app's windows; a pulse while an
  app starts; notification badges; a divider between pinned and running apps.
  It can hide always, never, or only while a window overlaps it; sit along the
  bottom or down either side; and show on every screen.
- **Settings search.** Type anywhere in Settings: every setting on every page,
  by name or description, typos forgiven; Enter takes you to it.
- **Displays: drag to arrange.** Your screens to scale; they snap edge to edge.
  Rotation and variable refresh rate per screen. Any number of screens.
- **Keybinds page.** Change any shortcut: click it and press the new keys.
  Clashes and missing modifiers are explained; the cheatsheet follows.
- **Game overlay.** Frame rate, frame times, GPU and CPU on top of your games
  (MangoHud), in your theme's colours; for all Steam games or ones you choose.
  A bar button shows or hides it, mid-game too.

### Faster
- The dock no longer rebuilds every icon whenever any window's title changes.
- Busy lists (launcher results, notifications, workspaces and more) update in
  place instead of rebuilding; a reply you're typing in a notification survives
  another one arriving.
- Settings, the cheatsheet, the power menu and the AI panel are released from
  memory a few minutes after they close.
- Start-up no longer scans your monitors for brightness control every time: the
  answer is remembered, and checked against each monitor's fingerprint.
- The music player's position isn't polled while it's paused.

### Fixed
- An accent colour could come out slightly too faint on very pale or very dark
  wallpapers.

### Install and checks
- The installer adds MangoHud (and its 32-bit half where multilib is enabled),
  and puts `~/.local/bin` on the session's PATH, so `ether` works by name.
- `tests/run.sh` (and GitHub's checks) now also: run every JavaScript module in
  Qt's own engine; check the keybinds agree with hyprland.lua; check the
  overlay's settings against MangoHud's own; make plugins from every template;
  and catch a QML object that sets the same handler twice (which stops it
  loading).
