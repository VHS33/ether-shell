import QtQuick
import QtQuick.Layouts
import qs.services

// The welcome's "Where things are": a small drawing of the desktop (the bar
// along the top, the dock along the bottom) with a numbered dot on each
// part, and what each one does beside it.  Point at a number, or at its
// line, and both light up.  (What each part does: modules/bar and
// modules/dock; the clock's and the stats' follow Settings, Bar.)
ColumnLayout {
    id: where
    property var app
    property int lit: -1
    spacing: 12

    readonly property var parts: [
        { n: 1, g: "auto_awesome",   t: "The assistant",          d: "Opens the AI chat down the left side." },
        { n: 2, g: "grid_view",      t: "Workspaces",             d: "Click a number to go there; scroll anywhere on the left of the bar to step through them. Your other screen's come after its little screen icon." },
        { n: 3, g: "monitoring",     t: "CPU and memory",         d: where.app.leftMorph ? "Click for live graphs and the busiest apps." : "Click to open btop, a full system monitor." },
        { n: 4, g: "web_asset",      t: "The window you're on",   d: "Its name; \"Desktop\" when nothing is focused." },
        { n: 5, g: "music_note",     t: "What's playing",         d: "Shows while music or a video plays. Click it for the player, middle-click to pause, scroll to change track." },
        { n: 6, g: "volume_up",      t: "Volume and network",     d: "Scroll on the speaker to change the volume, right-click to mute. Next to it: Wi-Fi, and your notifications." },
        { n: 7, g: "schedule",       t: "The clock",              d: where.app.rightMorph
              ? "Opens the same panel as the menu button next to it."
              : "Opens the sidebar: the weather, quick toggles, sound and microphone, the calendar with your notifications, and your clipboard." },
        { n: 8, g: "menu",           t: "The menu button, far right", d: "Opens the panel with nearly everything: the weather and forecast, the calendar, a timer and stopwatch, what's playing, your switches (Wi-Fi, Bluetooth, night light, game mode, keep awake, Do not disturb, screen recording), sound, microphone and brightness, which speakers or headphones play, your notifications, and buttons for a screenshot, the colour picker, wallpapers, Settings, lock and power. Click it again (it turns into an X) to close it." },
        { n: 9, g: "dock_to_bottom", t: "The dock",               d: "Your pinned and open apps. Click to open or switch to one, middle-click for a new window, right-click for its menu (pin, close, its windows)." }
    ]
    // where each number sits on the drawing, as fractions of it
    readonly property var spots: [
        { n: 1, x: 0.045, y: 0.10 }, { n: 2, x: 0.16, y: 0.10 }, { n: 3, x: 0.30, y: 0.10 }, { n: 4, x: 0.40, y: 0.10 },
        { n: 5, x: 0.50, y: 0.10 }, { n: 6, x: 0.68, y: 0.10 }, { n: 7, x: 0.82, y: 0.10 }, { n: 8, x: 0.945, y: 0.10 },
        { n: 9, x: 0.50, y: 0.86 }
    ]

    WelcomeHeading { app: where.app; title: "Where things are"; sub: "Point at a number to see what it is. Everything here opens with the mouse or a key." }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 18

        // ---- the drawing ----
        Item {
            id: drawing
            Layout.preferredWidth: 300
            Layout.preferredHeight: 190
            Layout.alignment: Qt.AlignTop
            Rectangle {                                     // the screen
                anchors.fill: parent
                radius: 14
                color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.05)
                border.width: 1
                border.color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.12)
            }
            Rectangle {                                     // the bar
                x: 8; y: 8
                width: parent.width - 16
                height: 22
                radius: 11
                color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.12)
            }
            Rectangle {                                     // a window
                x: 40; y: 46
                width: parent.width - 80
                height: 88
                radius: 8
                color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.06)
            }
            Rectangle {                                     // the dock
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 32
                width: 130
                height: 22
                radius: 11
                color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.12)
            }
            Repeater {
                model: where.spots
                delegate: Rectangle {
                    id: dot
                    required property var modelData
                    readonly property bool on: where.lit === modelData.n
                    x: modelData.x * drawing.width - width / 2
                    y: modelData.y * drawing.height - height / 2 + (modelData.n === 9 ? 2 : 1)
                    width: on ? 24 : 20
                    height: width
                    radius: width / 2
                    color: on ? where.app.cBlue : Qt.rgba(where.app.cBlue.r, where.app.cBlue.g, where.app.cBlue.b, 0.55)
                    Behavior on width { NumberAnimation { duration: where.app.animQuick } }
                    Text {
                        anchors.centerIn: parent
                        text: dot.modelData.n
                        color: where.app.cOnAccent
                        font.family: Theme.uiFont
                        font.pixelSize: where.app.fs(11)
                        font.bold: true
                    }
                    HoverHandler { onHoveredChanged: if (hovered) where.lit = dot.modelData.n }
                }
            }
        }

        // ---- what each one is ----
        Flickable {
            id: whereFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Behavior on contentY { NumberAnimation { duration: where.app.animQuick * 2; easing.type: Easing.OutCubic } }
            // there's more below: a thin bar shows where you are
            Rectangle {
                parent: whereFlick
                visible: whereFlick.contentHeight > whereFlick.height
                anchors.right: parent.right
                width: 3
                radius: 2
                color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.18)
                y: whereFlick.visibleArea.yPosition * whereFlick.height
                height: Math.max(24, whereFlick.visibleArea.heightRatio * whereFlick.height)
            }
            contentHeight: whereCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: whereCol
                width: whereFlick.width
                spacing: 4
                Repeater {
                    model: where.parts
                    delegate: Rectangle {
                        id: part
                        required property var modelData
                        readonly property bool on: where.lit === modelData.n
                        Layout.fillWidth: true
                        implicitHeight: partRow.implicitHeight + 14
                        radius: 12
                        color: on ? Qt.rgba(where.app.cBlue.r, where.app.cBlue.g, where.app.cBlue.b, 0.16) : "transparent"
                        Behavior on color { ColorAnimation { duration: where.app.animQuick } }
                        HoverHandler { id: partHov; onHoveredChanged: if (hovered) where.lit = part.modelData.n }
                        // lit from the drawing: scrolled into sight
                        onOnChanged: if (on && !partHov.hovered)
                            whereFlick.contentY = Math.max(0, Math.min(y - 6, whereFlick.contentHeight - whereFlick.height))
                        RowLayout {
                            id: partRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 20; implicitHeight: 20; radius: 10
                                color: part.on ? where.app.cBlue : Qt.rgba(where.app.cBlue.r, where.app.cBlue.g, where.app.cBlue.b, 0.55)
                                Text {
                                    anchors.centerIn: parent
                                    text: part.modelData.n
                                    color: where.app.cOnAccent
                                    font.family: Theme.uiFont
                                    font.pixelSize: where.app.fs(11)
                                    font.bold: true
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: part.modelData.t
                                    color: where.app.cFg
                                    font.family: Theme.uiFont
                                    font.pixelSize: where.app.fs(13)
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: part.modelData.d
                                    color: where.app.cDim
                                    font.family: Theme.uiFont
                                    font.pixelSize: where.app.fs(12)
                                }
                            }
                        }
                    }
                }
                // the launcher has no spot on the bar: it's a key
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: lRow.implicitHeight + 16
                    radius: 12
                    color: Qt.rgba(where.app.cFg.r, where.app.cFg.g, where.app.cFg.b, 0.05)
                    RowLayout {
                        id: lRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: "search"
                            color: where.app.cBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: where.app.fs(20)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "The launcher: press SUPER on its own"
                                color: where.app.cFg
                                font.family: Theme.uiFont
                                font.pixelSize: where.app.fs(13)
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: "Type to find apps, open windows and settings. Start with # for windows, ? for settings, = for maths, : for emoji, ; for your clipboard, > for commands, / for files."
                                color: where.app.cDim
                                font.family: Theme.uiFont
                                font.pixelSize: where.app.fs(12)
                            }
                        }
                    }
                }
            }
        }
    }
}
