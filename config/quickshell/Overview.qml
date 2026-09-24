import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// ============================================================
//   WORKSPACE OVERVIEW  (Alt+Tab)
//   Five tiles, one per workspace, each showing live previews
//   of its windows at their real positions.  Drag a preview onto
//   another tile to move that window there; click a preview to
//   focus it; click a tile's empty space to switch workspace.
//
//   Models here are Quickshell's own ObjectModels (ws.toplevels),
//   never plain JS arrays holding window objects — that pattern
//   is what caused the earlier segfaults.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winO
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.overviewShown

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: app.scrim(0.35)

        // every tile maps the main monitor, since all five workspaces
        // live on DP-1
        readonly property var mon:
            Hyprland.monitors.values.find(m => m.name === app.mainScreen) ?? null
        readonly property real monW: mon ? mon.width / mon.scale : 3072
        readonly property real monH: mon ? mon.height / mon.scale : 1728
        readonly property real tileW: 300
        readonly property real tileH: tileW * monH / monW
        readonly property real sc: tileW / monW

        function close() { app.overviewShown = false }

        function focusWindow(addr) {
            if (!addr) return
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
            close()
        }

        function moveWindow(addr, wsId) {
            if (!addr) return
            // There is no "silent" flag on the Lua move dispatcher, so the
            // view follows the window.  Remember where we were and go back.
            const back = app.activeWorkspace
            Hyprland.dispatch("hl.dsp.window.move({ workspace = " + wsId
                              + ", window = \"address:" + addr + "\" })")
            if (back !== wsId)
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + back + " })")
            refreshLater.restart()
        }

        function swapWindows(a, b) {
            if (!a || !b || a === b) return
            Hyprland.dispatch("hl.dsp.window.swap({ window = \"address:" + a
                              + "\", target = \"address:" + b + "\" })")
            refreshLater.restart()
        }

        // the dispatch is asynchronous, so re-read window positions a
        // moment later rather than immediately, or the previews would
        // redraw from the old layout
        Timer {
            id: refreshLater
            interval: 90
            onTriggered: Hyprland.refreshToplevels()
        }

        // click the dimmed backdrop to close
        MouseArea {
            anchors.fill: parent
            onClicked: winO.close()
        }

        // ---- the panel ----
        Rectangle {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.12
            width: row.implicitWidth + 36
            height: row.implicitHeight + 36
            radius: 22
            color: app.cCard
            border.width: 1
            border.color: app.cBorder

            // swallow clicks so they don't reach the backdrop
            MouseArea { anchors.fill: parent }

            Grid {
                id: row
                anchors.centerIn: parent
                columns: 5
                spacing: 12

                Repeater {
                    model: app.mainWorkspaces

                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property int wsId: modelData
                        readonly property var ws:
                            Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
                        readonly property bool current: wsId === app.activeWorkspace

                        width: winO.tileW
                        height: winO.tileH
                        radius: 14
                        color: app.cTile
                        border.width: 2
                        border.color: drop.containsDrag ? app.cTeal
                                     : current ? app.cBlue
                                     : app.cBorder
                        clip: true

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        // empty space: switch to this workspace
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Hyprland.dispatch("hl.dsp.focus({ workspace = "
                                                  + tile.wsId + " })")
                                winO.close()
                            }
                        }

                        // accepts a dragged window preview
                        DropArea {
                            id: drop
                            anchors.fill: parent
                            keys: ["qs-window"]
                            onDropped: d => winO.moveWindow(d.source.addr, tile.wsId)
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 10
                            text: tile.wsId
                            color: tile.current ? app.cBlue : app.cDim
                            font.family: app.font
                            font.pixelSize: app.fs(15)
                            font.bold: true
                            z: 5
                        }

                        // ---- windows on this workspace ----
                        Repeater {
                            model: tile.ws ? tile.ws.toplevels : null

                            delegate: Item {
                                id: win
                                required property var modelData

                                readonly property var ipc: modelData.lastIpcObject
                                readonly property string addr: ipc?.address ?? ""
                                readonly property int wsId: tile.wsId
                                readonly property real baseX:
                                    ((ipc?.at?.[0] ?? 0) - (winO.mon?.x ?? 0)) * winO.sc
                                readonly property real baseY:
                                    ((ipc?.at?.[1] ?? 0) - (winO.mon?.y ?? 0)) * winO.sc

                                x: baseX
                                y: baseY
                                width: Math.max(24, (ipc?.size?.[0] ?? 0) * winO.sc)
                                height: Math.max(18, (ipc?.size?.[1] ?? 0) * winO.sc)
                                z: 2

                                Drag.active: dh.active
                                Drag.source: win
                                Drag.keys: ["qs-window"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                ClippingRectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: app.cSurf
                                    border.width: wHov.hovered || dh.active ? 2 : 0
                                    border.color: app.cBlue

                                    // live thumbnail, captured only while open
                                    ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: app.overviewShown
                                                       ? win.modelData.wayland : null
                                        live: true
                                    }

                                    // app icon while the capture spins up
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: Math.min(parent.width, parent.height) * 0.4
                                        source: app.iconFor(win.ipc?.class ?? "")
                                        visible: parent.width > 30
                                        opacity: 0.85
                                        z: -1
                                    }
                                }

                                HoverHandler { id: wHov }

                                // dropping onto a window: swap with it if it's
                                // on the same workspace, otherwise move there.
                                // Sits above the tile's DropArea, so it wins.
                                DropArea {
                                    id: winDrop
                                    anchors.fill: parent
                                    keys: ["qs-window"]
                                    onDropped: d => {
                                        const src = d.source
                                        if (!src || src.addr === win.addr) return
                                        if (src.wsId === win.wsId)
                                            winO.swapWindows(src.addr, win.addr)
                                        else
                                            winO.moveWindow(src.addr, win.wsId)
                                    }
                                }

                                // outline the window you'd swap with
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: "transparent"
                                    border.width: 2
                                    border.color: app.cTeal
                                    visible: winDrop.containsDrag
                                             && winDrop.drag.source !== win
                                    z: 3
                                }

                                TapHandler {
                                    onTapped: winO.focusWindow(win.addr)
                                }

                                DragHandler {
                                    id: dh
                                    onActiveChanged: {
                                        if (!active) {
                                            win.Drag.drop()
                                            // dragging broke the position
                                            // bindings; put them back
                                            win.x = Qt.binding(() => win.baseX)
                                            win.y = Qt.binding(() => win.baseY)
                                        }
                                    }
                                }

                                // while dragged, lift above every tile so it
                                // isn't clipped by its own workspace
                                states: State {
                                    when: dh.active
                                    ParentChange { target: win; parent: dragLayer }
                                }
                            }
                        }
                    }
                }
            }
        }

        // dragged previews are reparented here so they draw on top
        Item {
            id: dragLayer
            anchors.fill: parent
            z: 100
        }
    }
}
