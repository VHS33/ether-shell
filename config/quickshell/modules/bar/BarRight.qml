import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire

// ============================================================
//   RIGHT PILL
//   Volume (click: popover, right-click: mute, scroll: adjust),
//   network speed, tray (right-click: the app's own menu), and
//   the clock, which opens the sidebar.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // a hoverable segment of the pill
    component Seg: Rectangle {
        id: sg
        property var app
        property bool lit: false
        default property alias content: sgRow.data
        signal clicked(var mouse)
        signal wheeled(var wheel)

        implicitWidth: sgRow.implicitWidth + 16
        implicitHeight: 24
        radius: 12
        color: lit ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
             : sgHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
             : "transparent"
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: sgHov }

        Row {
            id: sgRow
            anchors.centerIn: parent
            spacing: 5
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: m => sg.clicked(m)
            onWheel: w => sg.wheeled(w)
        }
    }

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // part of the older pill style: only built when that's in use
        active: modelData.name === app.mainScreen && !app.rightMorph

    PanelWindow {
        id: winR
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && !app.rightMorph

        anchors { top: true; right: true }
        margins { top: app.gap; right: app.gap }
        implicitWidth: rightRow.implicitWidth + 16
        implicitHeight: app.pillH
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region { x: 6; y: 6; width: winR.width - 12; height: winR.height - 12 }

        readonly property var sink: Pipewire.defaultAudioSink
        PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

        TextMetrics {
            id: rateMetrics
            font.family: "Inter"
            font.pixelSize: app.fs(12)
            text: "999 KB/s"
        }
        TextMetrics {
            id: volMetrics
            font.family: "Inter"
            font.pixelSize: app.fs(12)
            text: "100%"
        }

        Rectangle {
            anchors.fill: parent
            radius: app.pillH / 2
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)

            RowLayout {
                id: rightRow
                anchors.centerIn: parent
                spacing: 4

                // ---- volume ----
                Seg {
                    app: rootV.app
                    readonly property bool muted: winR.sink?.audio?.muted ?? false
                    readonly property int vol: Math.round((winR.sink?.audio?.volume ?? 0) * 100)
                    lit: app.volPopShown
                    onClicked: m => {
                        const a = winR.sink?.audio
                        if (m.button === Qt.RightButton) { if (a) a.muted = !a.muted }
                        else app.volPopShown = !app.volPopShown
                    }
                    onWheeled: w => {
                        const a = winR.sink?.audio
                        if (!a) return
                        a.volume = Math.max(0, Math.min(1, a.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.parent.muted ? "volume_off"
                            : parent.parent.vol < 34 ? "volume_down"
                            : parent.parent.vol < 67 ? "volume_down" : "volume_up"
                        color: parent.parent.muted ? app.cFaint : app.cMauve
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(14)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: volMetrics.advanceWidth
                        text: parent.parent.muted ? "Mute" : parent.parent.vol + "%"
                        color: parent.parent.muted ? app.cFaint : app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(12)
                    }
                }

                // ---- network ----
                Row {
                    visible: app.barNet
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    spacing: 10
                    Row {
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "arrow_downward"
                            color: app.cGreen
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(13)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: rateMetrics.advanceWidth
                            text: app.netDown
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                        }
                    }
                    Row {
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "arrow_upward"
                            color: app.cBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(13)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: rateMetrics.advanceWidth
                            text: app.netUp
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                        }
                    }
                }

                // ---- tray ----
                Row {
                    visible: SystemTray.items.values.length > 0
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    spacing: 2
                    Repeater {
                        model: SystemTray.items
                        delegate: Rectangle {
                            id: trayItem
                            required property var modelData
                            width: 26
                            height: 24
                            radius: 12
                            color: trHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11) : "transparent"
                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                            HoverHandler { id: trHov }
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 16
                                source: trayItem.modelData.icon
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: m => {
                                    const it = trayItem.modelData
                                    if (m.button === Qt.LeftButton && !it.onlyMenu) {
                                        it.activate()
                                    } else if (m.button === Qt.MiddleButton) {
                                        it.secondaryActivate()
                                    } else if (it.hasMenu) {
                                        // the app's own menu, opened just under the icon
                                        const p = trayItem.mapToItem(null, 0, trayItem.height + 6)
                                        it.display(winR, Math.round(p.x), Math.round(p.y))
                                    } else {
                                        it.secondaryActivate()
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- clock: opens the sidebar ----
                Seg {
                    app: rootV.app
                    lit: app.sidebarShown
                    onClicked: app.sidebarShown = !app.sidebarShown

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: app.cfg.clockDate !== false
                        text: Qt.formatDateTime(app.now, "ddd d MMM")
                        color: app.cDim
                        font.family: "Inter"
                        font.pixelSize: app.fs(12)
                    }
                    Item {
                        visible: app.cfg.clockDate !== false
                        width: 4; height: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // the bar's format carries the date too; take only the time
                        text: Qt.formatDateTime(app.now,
                                  (app.cfg.clock24h === true ? "HH:mm" : "h:mm")
                                  + (app.cfg.clockSeconds === true ? ":ss" : "")
                                  + (app.cfg.clock24h === true ? "" : " AP"))
                        color: app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(12)
                        font.weight: Font.DemiBold
                    }
                    // unread notifications
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: app.notifCount > 0 && !app.sidebarShown
                        width: 7; height: 7; radius: 3.5
                        color: app.cRed
                    }
                }
            }
        }
    }
    }
}
