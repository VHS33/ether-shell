import QtQuick

// The toolkit each plugin gets, as its `ether` property (version 1).
// Everything a plugin needs to fit in and to do things, without reaching into
// the shell itself, so Ether Shell can change inside without breaking plugins.
//
//   colours    ether.accent, onAccent, second, third, fg, dim, faint,
//              bg, card, surface, red           (they follow the theme)
//   text       ether.font, monoFont, iconFont, ether.fs(px) (sized as in
//              Settings)
//   settings   ether.settings (this plugin's own, saved), ether.set(key, value)
//   doing      ether.run(["cmd", "arg"]), ether.read(["cmd"], (out, code) => ...),
//              ether.copy(text), ether.open(url), ether.notify(title, body)
//   its files  ether.file("name.png")
QtObject {
    id: api
    property var app
    property string pluginId
    property string dir

    readonly property int version: 1

    readonly property color accent:   app.cBlue
    readonly property color onAccent: app.cOnAccent
    readonly property color second:   app.cPeach
    readonly property color third:    app.cGreen
    readonly property color fg:       app.cFg
    readonly property color dim:      app.cDim
    readonly property color faint:    app.cFaint
    readonly property color bg:       app.cBg
    readonly property color card:     app.cCard
    readonly property color surface:  app.cSurf
    readonly property color red:      app.cRed

    readonly property string font:     "Inter"
    readonly property string monoFont: app.font
    readonly property string iconFont: "Material Symbols Rounded"
    function fs(px) { return app.fs(px) }

    readonly property var settings: (app.cfg.pluginSettings || {})[pluginId] || ({})
    function set(key, value) { app.pluginSetting(pluginId, key, value) }

    function run(command) { app.pluginRun(pluginId, command) }
    function read(command, callback) { app.pluginRead(pluginId, command, callback) }
    function copy(text) { app.pluginRun(pluginId, ["wl-copy", "--", String(text)]) }
    function open(url) { app.pluginRun(pluginId, ["xdg-open", String(url)]) }
    function notify(title, body) { app.pluginRun(pluginId, ["notify-send", "-a", pluginId, String(title), String(body ?? "")]) }
    function file(name) { return "file://" + dir + "/" + String(name).replace(/^\/+|\.\.\//g, "") }
}
