import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../lib/keybinds.mjs" as Keybinds
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 24
    readonly property int pageNo: 24
    spacing: 4
    readonly property var now: Keybinds.effective(app.keybinds)

    Card {
        app: settingsRoot.app
        title: "Your shortcuts"
        desc: "Click a shortcut, then press the keys you want it to be; Escape cancels. The workspace keys (SUPER + 1 to 0) and media keys stay as they are."
        trailing: [
            Seg {
                app: settingsRoot.app
                visible: Object.keys(app.keybinds).length > 0
                options: ["Reset all"]
                current: -1
                onPicked: app.resetKeybinds()
            }
        ]
    }

    Repeater {
        model: ["Apps", "Windows", "Ether Shell", "Screenshots"]
        delegate: ColumnLayout {
            id: kgroup
            required property string modelData
            Layout.fillWidth: true
            spacing: 4
            SectionLabel { app: settingsRoot.app; text: kgroup.modelData }
            Repeater {
                model: Keybinds.CATALOG.filter(c => c.group === kgroup.modelData)
                delegate: Card {
                    id: kc
                    required property var modelData
                    readonly property string combo: kgroup.parent.now[modelData.id] || modelData.def
                    readonly property bool changed: combo !== modelData.def
                    readonly property bool capturing: settingsWin.kbCapture === modelData.id
                    app: settingsRoot.app
                    title: modelData.label
                    desc: capturing ? (settingsWin.kbError !== "" ? settingsWin.kbError : "Press the keys you want\u2026 (Escape cancels)")
                          : changed ? "Changed from " + modelData.def : ""
                    trailing: [
                        // back to its default
                        Rectangle {
                            visible: kc.changed && !kc.capturing
                            implicitWidth: 32; implicitHeight: 32; radius: 16
                            color: rsHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : "transparent"
                            HoverHandler { id: rsHov }
                            Text {
                                anchors.centerIn: parent
                                text: "restart_alt"
                                color: app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 18
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.resetKeybind(kc.modelData.id) }
                        },
                        // the keys: click to change them
                        Rectangle {
                            implicitWidth: Math.max(80, chip.implicitWidth + 28)
                            implicitHeight: 32
                            radius: 16
                            color: kc.capturing ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                                 : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.14)
                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                            border.width: kc.capturing ? 1 : 0
                            border.color: settingsWin.kbError !== "" ? app.cRed : app.cBlue
                            HoverHandler { id: chipHov }
                            Text {
                                id: chip
                                anchors.centerIn: parent
                                text: kc.capturing ? "\u2026" : kc.combo
                                color: kc.changed ? app.cBlue : app.cFg
                                font.family: app.font
                                font.pixelSize: app.fs(12)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: kc.capturing ? settingsWin.endKeyCapture() : settingsWin.startKeyCapture(kc.modelData.id)
                            }
                        }
                    ]
                }
            }
        }
    }
}
