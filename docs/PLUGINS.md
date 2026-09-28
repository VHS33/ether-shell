# Writing plugins for Ether Shell

A plugin adds something to Ether Shell without changing Ether Shell itself: an
item on the bar, results in the launcher, a widget on the desktop, and settings
of its own. Plugins are written in QML (Qt's language for interfaces, which
Ether Shell is written in) with a little JavaScript.

The quickest start is a template:

```
ether plugin new my-plugin
```

That makes `~/.config/ether-shell/plugins/my-plugin/`, with a working bar item.
Switch it on in **Settings, Plugins**, and it appears on your bar. Add
`--launcher`, `--widget` or `--settings` (or `--bar` alongside them) for those
parts; every template works as it is, so you change it rather than start from
nothing.

Three complete examples come with Ether Shell, in the same folder: **Uptime**
(a bar item), **Wikipedia** (launcher results from the web) and **Countdown**
(a desktop widget with settings).

## Contents

1. [A plugin's folder](#a-plugins-folder)
2. [plugin.json](#pluginjson)
3. [The parts](#the-parts): bar items, launcher results, desktop widgets, settings
4. [The toolkit: `ether`](#the-toolkit-ether)
5. [Trying it out](#trying-it-out)
6. [Mistakes worth knowing about](#mistakes-worth-knowing-about)
7. [Safety](#safety)

## A plugin's folder

Each plugin is a folder in `~/.config/ether-shell/plugins/`, named by the
plugin's id: lower-case letters, digits and dashes, starting with a letter or
digit, at most 40 characters (`uptime`, `my-plugin`, `todo2`).

```
~/.config/ether-shell/plugins/countdown/
    plugin.json        what it is, and what it adds
    Widget.qml         its desktop widget
    Settings.qml       its settings
    Countdown.mjs      JavaScript its parts share (optional)
```

A plugin can only use files inside its own folder. Its QML files can import
JavaScript modules (`.mjs`) and other QML files next to them, as usual.

Plugins are off until you switch them on in **Settings, Plugins**.

## plugin.json

```json
{
    "id": "countdown",
    "name": "Countdown",
    "description": "Days until a date of your choosing, on your desktop.",
    "version": "1.0",
    "author": "Your name",
    "api": 1,
    "widget": { "file": "Widget.qml", "name": "Countdown", "description": "Days until a date" },
    "settings": { "file": "Settings.qml" }
}
```

| Field | Required | What it is |
|---|---|---|
| `id` | yes | The folder's name, exactly. |
| `name` | no | Shown in Settings (60 characters at most). The id, if missing. |
| `description` | no | A sentence or two, shown in Settings (300 at most). |
| `version`, `author` | no | Shown in Settings. |
| `api` | yes | The toolkit version it's written for: `1`. A plugin asking for a newer one than your Ether Shell has is refused, with a note to update. |
| `bar` | one of these four | `{ "file": "Bar.qml", "side": "left" or "right" }` (right if missing). |
| `launcher` | one of these four | `{ "file": "Launcher.qml", "prefix": "!w", "title": "Wikipedia" }` (prefix optional). |
| `widget` | one of these four | `{ "file": "Widget.qml", "name": "...", "description": "..." }` |
| `settings` | no | `{ "file": "Settings.qml" }`. Settings alone don't make a plugin: they set up its other parts. |

Every file must be a `.qml` file in the plugin's own folder. A plugin with a
mistake in its `plugin.json` shows in Settings with the reason, in plain words,
and isn't loaded.

## The parts

Every part is a QML file whose top item has a property named `ether`, which is
how Ether Shell hands it [the toolkit](#the-toolkit-ether):

```qml
Item {
    property var ether     // given by Ether Shell
    ...
}
```

### Bar items

Shown on the bar, on the side you choose, in a rounded group like the bar's own.
Its size is its `implicitWidth` and `implicitHeight`: the bar makes room for
that. It's 28 pixels tall at most, so keep it to an icon and a few words.

```qml
import QtQuick

Item {
    id: item
    property var ether
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "schedule"                     // a Material Symbols icon name
            color: item.ether.accent
            font.family: item.ether.iconFont
            font.pixelSize: 16
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "3h 12m"
            color: item.ether.fg
            font.family: item.ether.font
            font.pixelSize: item.ether.fs(12)
        }
    }
    // beside the Row, not inside it (see "Mistakes worth knowing about")
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: item.ether.notify("Uptime", "Up 3h 12m")
    }
}
```

Icons are names from Google's Material Symbols (like `schedule`, `bolt`,
`cloud`, `extension`); search for one at fonts.google.com/icons.

### Launcher results

Ether Shell sets the part's `query` as you type, and shows its `results`,
whenever they're set. So a part can look things up (a command's output, a web
page) and fill `results` when the answer comes, without holding the launcher up.

```qml
import QtQuick

Item {
    property var ether
    property string query: ""
    property var results: query === "" ? [] : [
        { title: "You typed " + query, subtitle: "Enter copies it", icon: "content_copy", copy: query }
    ]
}
```

- **With a `prefix`** (like `"!w"`), the plugin is only asked once you type the
  prefix, and then its results are the only ones shown. `query` is what follows
  the prefix. A prefix is 1 to 6 letters, digits or `! # $ % & * + ? ~ ,`, and
  can't start with one the launcher uses itself (`= : ; > @ /`). If two plugins
  want the same prefix, the second is told so in Settings.
- **Without a prefix,** the plugin is asked whenever you search for apps (from
  two letters), and up to four of its results appear below your apps and files,
  labelled with its `title`.
- **Each result** is `{ title, subtitle, icon }` plus what choosing it does,
  one of:
  - `copy: "text"` copies the text;
  - `open: "https://..."` opens a link (`https:`, `http:`, `file:` or `mailto:`);
  - `run: ["program", "argument"]` runs a command (see [Safety](#safety)).

  Or give the part a function `activate(result)`, and it's called instead, with
  the result as you gave it (so it can carry anything else you need).
- **Looking things up:** wait for a pause in typing before asking (a `Timer`
  restarted when `query` changes), cancel an older request, and throw away an
  answer that arrives for an earlier search. The Wikipedia example shows all
  three; without them, a slow answer can replace a newer one.

### Desktop widgets

Offered in **Settings, Widgets** alongside the built-in ones, and arranged,
moved and removed the same way. Ether Shell draws the card; your part draws
only what's inside, at its own `implicitWidth` and `implicitHeight`. While the
plugin is switched off, its widgets are hidden (and come back when it's on).

```qml
import QtQuick

Column {
    property var ether
    spacing: 4
    Text { text: "88"; color: parent.ether.accent; font.family: parent.ether.font; font.pixelSize: 48 }
    Text { text: "days until Christmas"; color: parent.ether.fg; font.family: parent.ether.font; font.pixelSize: parent.ether.fs(14) }
}
```

Something that changes slowly (a date, the weather) should refresh slowly: a
`Timer` of ten minutes, not one second.

### Settings

Shown under the plugin's card in **Settings, Plugins**, while it's on. The part
is given the page's width. Read the plugin's saved settings from
`ether.settings`, and save one with `ether.set(key, value)`; everything bound to
`ether.settings`, in any of the plugin's parts, updates straight away.

```qml
import QtQuick

Column {
    id: s
    property var ether
    TextInput {
        width: 300
        text: s.ether.settings.greeting || ""
        color: s.ether.fg
        onEditingFinished: s.ether.set("greeting", text)
    }
}
```

Save when a field is finished (`onEditingFinished`), not at every key.

## The toolkit: `ether`

Everything a plugin needs from Ether Shell comes through `ether`, so Ether Shell
can change inside without breaking plugins. This is version 1 (`"api": 1`).

**Colours** (they follow the wallpaper's theme, light or dark):

| | |
|---|---|
| `ether.accent` | The theme's accent; `ether.onAccent` is text on it. |
| `ether.second`, `ether.third` | The wallpaper's other colours. |
| `ether.fg`, `ether.dim`, `ether.faint` | Text: normal, quieter, quietest. |
| `ether.bg`, `ether.card`, `ether.surface` | Backgrounds. |
| `ether.red` | Warnings and errors. |

For a translucent tint: `Qt.rgba(ether.fg.r, ether.fg.g, ether.fg.b, 0.08)`.

**Text:**

| | |
|---|---|
| `ether.font` | The shell's font (Inter). |
| `ether.monoFont` | Its monospaced font. |
| `ether.iconFont` | Material Symbols, for icons by name. |
| `ether.fs(12)` | A text size, scaled as set in Settings. Use it for all text. |

**Settings:**

| | |
|---|---|
| `ether.settings` | This plugin's saved settings (an object; empty to begin with). |
| `ether.set(key, value)` | Save one. |

**Doing things:**

| | |
|---|---|
| `ether.run(["program", "arg"])` | Run a command. |
| `ether.read(["program", "arg"], (output, code) => { ... })` | Run a command, and get its output and exit code. |
| `ether.copy(text)` | Copy to the clipboard. |
| `ether.open(url)` | Open a link or a file. |
| `ether.notify(title, body)` | Show a notification, from your plugin. |
| `ether.file("icon.png")` | A URL for a file in the plugin's folder (for an `Image`). |
| `ether.version` | The toolkit's version: `1`. |

Plugins can also use anything QML itself offers: `Timer`, `XMLHttpRequest` for
the web, animations, and so on.

## Trying it out

- **After changing a plugin's files:** `ether plugin reload`, or **Check
  plugins** in Settings, Plugins.
- **`ether plugin list`** shows each plugin as the Plugins page sees it: on,
  off, set aside (it failed to load, with the error), or can't be used (a
  mistake in `plugin.json`, with the reason).
- **A part with a mistake** (a typo in its QML) is set aside: the rest of Ether
  Shell carries on, and Settings, Plugins shows the error with its line number.
  Fix it, press **Check plugins**, and it gets another try.
- **Messages from your code** (`console.log("...")`) and any errors while it
  runs go to Ether Shell's log: `$XDG_RUNTIME_DIR/ether-shell.log`. Watch it
  with `tail -f "$XDG_RUNTIME_DIR/ether-shell.log"`.

## Mistakes worth knowing about

- **A `MouseArea` inside a `Row` or `Column`, filling it.** A Row sizes itself
  from what's in it, so something stretched to fill it confuses that, and the
  item can end up cut off. Put the Row and the MouseArea side by side in a plain
  `Item`, as in the bar example above.
- **No size.** Ether Shell makes room for a part's `implicitWidth` and
  `implicitHeight`. An `Item` with only anchored children has none, and shows as
  nothing; give it `implicitWidth: row.implicitWidth` (or similar).
- **`{ ...object }` in JavaScript.** Qt's JavaScript doesn't understand object
  spread (Node does, so it's easy to miss). Use
  `Object.assign({}, object, { extra: 1 })`.
- **Answers arriving out of order** in a launcher part: see
  [Launcher results](#launcher-results).
- **Refreshing too often.** Every `Timer` costs a little; match it to how fast
  the thing really changes.

## Safety

**Plugins are code**, and can do what a script can: only install plugins from
people you trust. Ether Shell still keeps them within some limits:

- A plugin's files must be in its own folder.
- Commands (`ether.run`, `ether.read`, a result's `run`) are lists of plain
  strings, program first: they're run directly, never through a shell, so text
  in them is never interpreted as a command (`["echo", "$(rm x)"]` prints
  `$(rm x)`). At most 16 `ether.read`s run at once.
- A result's `open` must be a web, file or mail link.
- A part that fails to load is set aside; the rest of Ether Shell carries on.
- Names, descriptions and results are trimmed to sensible lengths.
