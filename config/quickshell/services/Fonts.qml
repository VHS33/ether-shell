pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Fonts (Settings > General > Fonts), through ~/.local/bin/font: the font
// families installed, and passing your choice on to apps.  The shell's own
// text follows Theme.uiFont, kitty its settings file (Session), and GTK and
// Qt/KDE apps get it here, at once and again at login (and after each new
// wallpaper, from setwall).  Use it anywhere as Fonts.text, .mono, .all,
// .monoAll, .picksText, .picksMono, .setText(f), .setMono(f), .refresh()
// (import qs.services).  Nothing goes over the network.
Singleton {
    id: fonts

    readonly property string cmd: Quickshell.env("HOME") + "/.local/bin/font"
    readonly property string defaultText: "Inter"
    readonly property string defaultMono: "JetBrainsMono Nerd Font"
    readonly property string text: Config.cfg.uiFont || defaultText
    readonly property string mono: Config.cfg.monoFont || defaultMono

    // every family installed, and the monospace ones
    property var all: []
    property var monoAll: []
    property bool loaded: false

    // good choices, shown first: those of them that are installed
    readonly property var goodText: ["Inter", "Geist", "Manrope", "Outfit", "Lexend", "Rubik", "Nunito",
        "Poppins", "IBM Plex Sans", "Fira Sans", "Noto Sans", "Roboto", "Open Sans", "Source Sans 3",
        "Ubuntu", "Cantarell", "Lato", "DejaVu Sans"]
    readonly property var goodMono: ["JetBrainsMono Nerd Font", "JetBrains Mono", "Geist Mono", "Fira Code",
        "Cascadia Code", "Maple Mono", "Iosevka", "Hack", "IBM Plex Mono", "Source Code Pro",
        "Noto Sans Mono", "DejaVu Sans Mono"]
    function picks(good, have, current) {
        const out = good.filter(f => have.indexOf(f) >= 0).slice(0, 8)
        // what's in use is always shown, even if it isn't one of them
        if (current && out.indexOf(current) < 0) out.unshift(current)
        return out.slice(0, 8)
    }
    readonly property var picksText: picks(goodText, all, text)
    readonly property var picksMono: picks(goodMono, monoAll, mono)

    function refresh() { if (!lister.running) lister.running = true }
    function setText(f) { Config.setting("uiFont", f === defaultText ? "" : f) }
    function setMono(f) { Config.setting("monoFont", f === defaultMono ? "" : f) }

    function applyApps() {
        applier.command = [cmd, "apply", text, mono]
        applier.running = true
    }

    Process {
        id: lister
        command: [fonts.cmd, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = [], m = []
                for (const line of text.split("\n")) {
                    const f = line.split("\t")
                    if (f[0] === "") continue
                    a.push(f[0])
                    if (f[1] === "1") m.push(f[0])
                }
                fonts.all = a
                fonts.monoAll = m
                fonts.loaded = true
            }
        }
    }
    Process { id: applier }

    Connections {
        target: Config
        function onSettingChanged(key) {
            if (key === "uiFont" || key === "monoFont" || key === "*") fonts.applyApps()
        }
        // at login: apps get your fonts again (only once you've chosen one)
        function onLoadedChanged() { if (Config.loaded && (Config.cfg.uiFont || Config.cfg.monoFont)) fonts.applyApps() }
    }
    Component.onCompleted: if (Config.loaded && (Config.cfg.uiFont || Config.cfg.monoFont)) applyApps()
}
