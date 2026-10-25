pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The mouse cursor's look (Settings > Mouse > Cursor), through
// ~/.local/bin/cursor: the themes installed, with previews of each one's
// arrow, hand and text cursors; the one in use; and its size.  A theme
// picked here is applied everywhere at once, and again each time the shell
// starts (at login).  Use it anywhere as Cursors.themes, .current, .size,
// .pick(id), .setSize(px), .refresh() (import qs.services).
// Ether, the shell's own theme (a dot, a ring over things you can click, a
// slim text bar), is drawn in the accent: made again whenever the
// wallpaper's colours change, and put on again if it's the one in use.
// Nothing goes over the network.
Singleton {
    id: cur

    readonly property string cmd: Quickshell.env("HOME") + "/.local/bin/cursor"
    // [{ id, name, previews, made }]: Ether first, then by name; `made`
    // changes when the previews are made again (Ether in a new colour)
    property var themes: []
    property bool loaded: false
    // what's in use when nothing's been picked here (GTK's setting, or the
    // default theme older apps use)
    property string system: ""
    readonly property string current: Config.cfg.cursorTheme || system
    readonly property int size: {
        const v = Number(Config.cfg.cursorSize)
        return isFinite(v) && v > 0 ? Math.max(16, Math.min(96, Math.round(v))) : 24
    }

    function refresh() { if (!lister.running) lister.running = true }
    function pick(id) { Config.setting("cursorTheme", id) }
    function setSize(px) { Config.setting("cursorSize", px) }

    function apply() {
        const t = current
        if (t === "") return
        applier.command = [cmd, "apply", t, String(size)]
        applier.running = true
    }

    Process {
        id: lister
        command: [cur.cmd, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const f = line.split("\t")
                    if (f.length >= 3 && f[0] !== "") out.push({ id: f[0], name: f[1], previews: f[2], made: f[3] || "0" })
                }
                cur.themes = out
                cur.loaded = true
            }
        }
    }
    Process {
        id: asker
        command: [cur.cmd, "current"]
        stdout: StdioCollector { onStreamFinished: cur.system = text.trim() }
    }
    Process { id: applier }

    // ---- Ether, in the accent ----
    // (the accent it's heading for, not the one fading towards it)
    readonly property string accent: String(Theme.accentTarget)
    onAccentChanged: etherSoon.restart()
    // (a tenth of a second: a burst of changes makes one cursor)
    Timer { id: etherSoon; interval: 100; onTriggered: cur.makeEther() }
    function makeEther() {
        if (!/^#[0-9a-fA-F]{6}$/.test(accent)) return
        if (etherMaker.running) { etherSoon.restart(); return }
        // in use: made and put on in one go (the quickest way to the screen)
        etherMaker.command = current === "Ether" ? [cmd, "make-ether", accent, "apply", String(size)]
                                                 : [cmd, "make-ether", accent]
        etherMaker.running = true
    }
    Process {
        id: etherMaker
        onExited: code => {
            if (code !== 0) return
            if (cur.loaded) cur.refresh()       // its previews, in the new colour (after)
        }
    }

    Connections {
        target: Config
        function onSettingChanged(key) {
            if (key === "cursorTheme" || key === "cursorSize" || key === "*") cur.apply()
        }
        // at login: your theme and size again (only once you've picked one)
        function onLoadedChanged() { if (Config.loaded && Config.cfg.cursorTheme) cur.apply() }
    }
    Component.onCompleted: {
        asker.running = true
        etherSoon.start()
        if (Config.loaded && Config.cfg.cursorTheme) apply()
    }
}
