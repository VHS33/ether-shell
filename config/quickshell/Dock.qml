import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// ============================================================
//   DOCK
//   Pinned apps (in pinned order), then running apps that aren't
//   pinned.  Left-click focuses / cycles an app's windows, or
//   launches a pinned app that isn't running; middle-click opens a
//   new window; right-click pins or unpins.
//
//   Auto-hide keeps the window mapped and slides the card below
//   the screen edge; a thin strip along the bottom brings it back.
//   The window is taller than the dock so tooltips have room, and
//   the mask keeps that extra space click-through.
//
//   Model: app.dockItems, plain values only.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // only when the dock is switched on
        active: modelData.name === app.mainScreen && app.dockEnabled

    PanelWindow {
        id: winD
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.dockEnabled && app.dockItems.length > 0

        readonly property int cell: app.dockIcon + 16
        readonly property int cardH: cell + 12
        readonly property int tipRoom: 44

        // with auto-hide the window reaches the very bottom edge, so the
        // strip that brings the dock back is where the pointer stops
        anchors { bottom: true; left: true; right: true }
        margins { bottom: app.dockAutoHide ? 0 : app.gap }
        implicitHeight: cardH + tipRoom + (app.dockAutoHide ? app.gap : 0)
        color: "transparent"

        // reserve the strip only while the dock stays up
        exclusionMode: app.dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: app.dockAutoHide ? 0 : cardH + app.gap

        // ---- auto-hide ----
        property bool pointerIn: false
        readonly property bool shown: !app.dockAutoHide || pointerIn || holdOpen.running
        Timer {
            id: holdOpen
            interval: 600
        }

        property Region cardMask: Region { item: card }
        property Region edgeMask: Region { x: 0; y: winD.height - 3; width: winD.width; height: 3 }
        mask: shown ? cardMask : edgeMask

        // touching the bottom edge brings it back
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            hoverEnabled: true
            enabled: app.dockAutoHide && !winD.shown
            onEntered: winD.pointerIn = true
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: winD.shown ? winD.tipRoom : winD.height + 8
            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            width: dockRow.implicitWidth + 16
            height: winD.cardH
            radius: height / 2.4
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) winD.pointerIn = true
                    else { winD.pointerIn = false; holdOpen.restart() }
                }
            }

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: app.dockItems

                    delegate: Rectangle {
                        id: it
                        required property var modelData
                        readonly property bool isActive: modelData.act === 1
                        readonly property bool elsewhere: modelData.running && modelData.here !== 1

                        implicitWidth: winD.cell
                        implicitHeight: winD.cell
                        radius: width * 0.32
                        color: isActive ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                             : itHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                             : "transparent"
                        opacity: elsewhere ? 0.5 : 1
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

                        HoverHandler { id: itHov }

                        IconImage {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -2
                            implicitSize: app.dockIcon
                            source: it.modelData.icon
                        }

                        // running: a dot; focused: a short bar
                        Rectangle {
                            visible: it.modelData.running
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: it.isActive ? (it.modelData.n > 1 ? 18 : 12) : 5
                            height: 4
                            radius: 2
                            color: it.isActive ? app.cBlue : app.cDim
                            Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        }

                        // window count
                        Rectangle {
                            visible: it.modelData.n > 1
                            width: 16; height: 16; radius: 8
                            color: app.cBlue
                            anchors.right: parent.right
                            anchors.top: parent.top
                            Text {
                                anchors.centerIn: parent
                                text: it.modelData.n
                                color: app.cOnAccent
                                font.family: "Inter"
                                font.pixelSize: app.fs(9)
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m => {
                                const d = it.modelData
                                if (m.button === Qt.RightButton) {
                                    app.togglePin(d)
                                } else if (m.button === Qt.MiddleButton) {
                                    if (d.id) app.launchApp(d.id)
                                } else if (d.running) {
                                    app.cycleGroup(d.cls, d.addrs)
                                } else if (d.id) {
                                    app.launchApp(d.id)
                                }
                            }
                        }

                        // tooltip, in the room above the dock
                        Rectangle {
                            visible: itHov.hovered
                            radius: 12
                            color: app.cCard
                            border.width: 1
                            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)
                            implicitWidth: Math.min(tipCol.implicitWidth + 20, 340)
                            implicitHeight: tipCol.implicitHeight + 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.top
                            anchors.bottomMargin: 10
                            z: 10

                            Column {
                                id: tipCol
                                anchors.centerIn: parent
                                Text {
                                    width: Math.min(implicitWidth, 320)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: {
                                        const d = it.modelData
                                        const main = d.n > 1 ? d.name + ", " + d.n + " windows"
                                                   : (d.titles[0] || d.name)
                                        return main + (it.elsewhere ? " (other workspace)" : "")
                                    }
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: it.modelData.id !== ""
                                    text: it.modelData.pinned ? "Right-click to unpin" : "Right-click to pin"
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(10)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
