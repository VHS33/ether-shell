import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// ============================================================
//   WORKSPACE PREVIEW
//   Rest the mouse on a workspace in the bar and, after a moment, a card
//   drops out beneath it with a live miniature of that workspace: the
//   wallpaper, and each window at its real place and size, captured live.
//   It follows along as you move across the workspaces and fades when
//   you leave.  Not while a drawer or the overview is open; never takes
//   clicks.
//
//   A card with a gap under the bar, so a window of its own is fine.  It
//   stays shown (invisible when not in use): windows stack in the order
//   they appear, and one shown again later would come back on top.
//
//   Windows come from the workspace's own `toplevels` (a live model, not
//   a JS array), positioned from Hyprland's IPC data, which is refreshed
//   when a preview starts.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // built the first time a workspace is hovered, then kept
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.wsHoverId >= 0)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: pw
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen

        anchors { top: true; left: true; right: true }
        implicitHeight: app.barBottom + 300
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region { width: 0; height: 0 }

        // ---- when to show: after resting a moment; gone shortly after leaving ----
        readonly property bool allowed: app.drawerNow === "" && !app.overviewShown
                                        && !app.cardShown && !app.quickShown && !app.sysShown
        property int shownId: -1
        property bool shown: false
        Timer {
            id: showLater
            interval: pw.shown ? 60 : 340          // quick when moving between workspaces
            onTriggered: {
                if (app.wsHoverId < 0 || !pw.allowed) return
                Hyprland.refreshToplevels()
                pw.shownId = app.wsHoverId
                pw.shown = true
            }
        }
        Timer {
            id: hideLater
            interval: 160
            onTriggered: pw.shown = false
        }
        Connections {
            target: app
            function onWsHoverIdChanged() {
                if (app.wsHoverId >= 0) { hideLater.stop(); showLater.restart() }
                else { showLater.stop(); hideLater.restart() }
            }
        }
        onAllowedChanged: if (!allowed) { showLater.stop(); shown = false }
        // built because a workspace is being hovered: begin as if it just started
        Component.onCompleted: if (app.wsHoverId >= 0) showLater.restart()

        // ---- what's being shown ----
        readonly property var ws: Hyprland.workspaces.values.find(w => w.id === pw.shownId) ?? null
        readonly property string monName: app.wsHoverScreen || app.mainScreen
        readonly property var mon: Hyprland.monitors.values.find(m => m.name === pw.monName) ?? null
        readonly property real monW: mon ? mon.width / mon.scale : 1920
        readonly property real monH: mon ? mon.height / mon.scale : 1080
        readonly property real thumbW: 300
        readonly property real thumbH: thumbW * monH / monW
        readonly property real sc: thumbW / monW
        readonly property int count: ws ? ws.toplevels.values.length : 0
        // its number in its own monitor's list (the top monitor's count from 1)
        readonly property int number: {
            const list = pw.monName === app.secondScreen ? app.secondWorkspaces : app.mainWorkspaces
            const i = list.indexOf(pw.shownId)
            return i >= 0 ? i + 1 : pw.shownId
        }

        Rectangle {
            id: card
            width: pw.thumbW + 16
            height: pw.thumbH + 44
            // under the workspace, kept on screen
            x: Math.max(8, Math.min(pw.width - width - 8, app.wsHoverX - width / 2))
            y: app.barBottom + 8
            Behavior on x { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            radius: 18
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
            transformOrigin: Item.Top
            opacity: pw.shown ? 1 : 0
            scale: pw.shown ? 1 : 0.94
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

            // ---- the miniature ----
            ClippingRectangle {
                id: thumb
                x: 8
                y: 8
                width: pw.thumbW
                height: pw.thumbH
                radius: 12
                color: app.cSurf

                // the wallpaper behind it all
                Image {
                    anchors.fill: parent
                    source: app.currentWall ? "file://" + app.currentWall : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 600
                    opacity: 0.9
                }

                Repeater {
                    model: pw.ws ? pw.ws.toplevels : null
                    delegate: Item {
                        id: win
                        required property var modelData
                        readonly property var ipc: modelData.lastIpcObject
                        x: ((ipc?.at?.[0] ?? 0) - (pw.mon?.x ?? 0)) * pw.sc
                        y: ((ipc?.at?.[1] ?? 0) - (pw.mon?.y ?? 0)) * pw.sc
                        width: Math.max(16, (ipc?.size?.[0] ?? 0) * pw.sc)
                        height: Math.max(12, (ipc?.size?.[1] ?? 0) * pw.sc)

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 5
                            color: app.cCard
                            // the window, captured live only while the preview shows
                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: pw.shown ? win.modelData.wayland : null
                                live: true
                            }
                            // its icon until the capture arrives
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: Math.min(parent.width, parent.height) * 0.45
                                source: app.iconFor(win.modelData.wayland?.appId ?? "")
                                z: -1
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: pw.count === 0
                    text: "Empty"
                    color: "white"
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                    font.family: "Inter"
                    font.weight: Font.DemiBold
                    font.pixelSize: app.fs(13)
                }
            }

            // ---- which workspace, and what's on it ----
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 8
                spacing: 8
                Rectangle {
                    id: numBadge
                    // the workspace showing on its monitor right now
                    readonly property bool current:
                        pw.shownId === (pw.monName === app.secondScreen ? app.secondActive : app.mainActive)
                    implicitWidth: numT.implicitWidth + 14
                    implicitHeight: 20
                    radius: 10
                    color: current ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                    Text {
                        id: numT
                        anchors.centerIn: parent
                        text: pw.number
                        color: numBadge.current ? app.cOnAccent : app.cFg
                        font.family: "Inter"
                        font.weight: Font.DemiBold
                        font.pixelSize: app.fs(11)
                    }
                }
                Text {
                    visible: pw.monName === app.secondScreen
                    text: "desktop_windows"
                    color: app.cDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(13)
                }
                Text {
                    Layout.fillWidth: true
                    text: pw.count === 0 ? "No windows"
                        : pw.count === 1 ? "1 window" : pw.count + " windows"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                }
                // the apps on it
                Row {
                    spacing: 3
                    Repeater {
                        model: pw.ws ? pw.ws.toplevels : null
                        delegate: IconImage {
                            required property var modelData
                            required property int index
                            visible: index < 6
                            implicitSize: 14
                            source: app.iconFor(modelData.wayland?.appId ?? "")
                        }
                    }
                }
            }
        }
    }
    }
}
