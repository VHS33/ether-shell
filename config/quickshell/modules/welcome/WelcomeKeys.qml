import QtQuick
import QtQuick.Layouts
import qs.services
import "../../lib/keybinds.mjs" as KeybindsLib

// The welcome's "Keys to know": the handful that matter, as they're set now
// (your own changes from Settings, Keybinds included), and where the rest are.
ColumnLayout {
    id: keysPage
    property var app
    spacing: 12

    // which ones, in this order (ids from lib/keybinds.mjs)
    readonly property var wanted: ["terminal", "files", "settings", "cheatsheet", "quick", "shot", "clipboard", "overview", "last_workspace", "close", "lock", "power", "wallpaper"]
    readonly property var now: KeybindsLib.effective(app.keybinds)
    readonly property var rows: {
        // (SUPER pressed and let go by itself; with another key it's that shortcut)
        const out = [{ label: "Launcher: apps, windows, settings", keys: ["SUPER"], alone: true }]
        for (const id of wanted) {
            const c = KeybindsLib.CATALOG.find(x => x.id === id)
            if (c && now[id]) out.push({ label: c.label, keys: String(now[id]).split(" + ").map(pretty) })
        }
        return out
    }
    // how a key is printed on it
    function pretty(k) {
        const named = { comma: ",", period: ".", slash: "/", semicolon: ";", apostrophe: "'", minus: "-", equal: "=",
                        grave: "`", bracketleft: "[", bracketright: "]", backslash: "\\", Return: "Enter", space: "Space",
                        Prior: "Page Up", Next: "Page Down", left: "←", right: "→", up: "↑", down: "↓" }
        return named[k] || k
    }

    WelcomeHeading { app: keysPage.app; title: "Keys to know"; sub: "The ones you'll use most, as they're set now. SUPER is the Windows key." }

    Flickable {
        id: keysFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: keysGrid.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        GridLayout {
            id: keysGrid
            width: keysFlick.width
            columns: 2
            columnSpacing: 18
            rowSpacing: 6
            Repeater {
                model: keysPage.rows
                delegate: RowLayout {
                    id: kr
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: (keysGrid.width - keysGrid.columnSpacing) / 2
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: kr.modelData.label
                        color: keysPage.app.cFg
                        font.family: Theme.uiFont
                        font.pixelSize: keysPage.app.fs(12)
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: 4
                        Repeater {
                            model: kr.modelData.keys
                            delegate: Rectangle {
                                required property var modelData
                                width: Math.max(28, kt.implicitWidth + 14)
                                height: 26
                                radius: app.rr(7)
                                color: Qt.rgba(keysPage.app.cFg.r, keysPage.app.cFg.g, keysPage.app.cFg.b, 0.09)
                                border.width: 1
                                border.color: Qt.rgba(keysPage.app.cFg.r, keysPage.app.cFg.g, keysPage.app.cFg.b, 0.14)
                                Text {
                                    id: kt
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: keysPage.app.cFg
                                    font.family: Theme.uiFont
                                    font.pixelSize: keysPage.app.fs(11)
                                    font.bold: true
                                }
                            }
                        }
                        Text {
                            visible: kr.modelData.alone === true
                            anchors.verticalCenter: parent.verticalCenter
                            text: "on its own"
                            color: keysPage.app.cDim
                            font.family: Theme.uiFont
                            font.pixelSize: keysPage.app.fs(11)
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Every shortcut: " + (keysPage.now.cheatsheet ? keysPage.now.cheatsheet.split(" + ").map(keysPage.pretty).join(" + ") : "SUPER + /")
              + ". Change any of them in Settings, Keybinds."
        color: keysPage.app.cDim
        font.family: Theme.uiFont
        font.pixelSize: keysPage.app.fs(12)
    }
}
