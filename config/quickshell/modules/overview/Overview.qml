import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// ============================================================
//   WORKSPACE OVERVIEW  (Alt+Tab)
//   One tile per workspace with live previews of its windows at
//   their real positions, the workspace number, and the icons of
//   the apps on it.
//
//   Mouse: click a tile to go there, click a preview to focus that
//   window, drag a preview onto another tile to move it there or
//   onto another window to swap them, middle-click a preview to
//   close that window.
//   Keyboard: arrows move, Enter opens, 1-9 and 0 jump, Esc
//   closes.  Alt+Tab again steps to the next workspace, and
//   releasing Alt then goes there.
//
//   Models here are Quickshell's own ObjectModels (ws.toplevels),
//   never plain JS arrays holding window objects: that pattern
//   is what caused the earlier segfaults.
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
        // Built the first time it's opened, kept while it's in use, and
        // released 3 minutes after it closes (the Timer in its window).
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.overviewShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: winO

        // Released 3 minutes after it closes: its memory back.  Opening it
        // again builds it afresh, a moment's work.
        Timer {
            interval: 180000
            running: !app.overviewShown
            onTriggered: Qt.callLater(() => { perScreen.used = false })
        }
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Stays mapped and animates itself: mapping a new surface on each
        // open lagged, and Hyprland's own layer fade fought the shell's.
        // Closed, nothing shows and the mask lets every click through.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.overviewShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        property Region shownMask: Region { width: winO.width; height: winO.height }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        // every tile maps the main monitor
        readonly property var mon:
            Hyprland.monitors.values.find(m => m.name === app.mainScreen) ?? null
        readonly property real monW: mon ? mon.width / mon.scale : 3072
        readonly property real monH: mon ? mon.height / mon.scale : 1728
        readonly property int cols: Math.min(5, app.mainWorkspaces.length)
        readonly property real tileW: Math.min(360, (width * 0.86 - (cols - 1) * 14) / cols)
        readonly property real previewH: tileW * monH / monW
        readonly property real sc: tileW / monW

        // ---- keyboard selection ----
        property int sel: 0
        property bool stepped: false     // Alt+Tab pressed again while open

        onOpenChanged: if (open) {
            sel = Math.max(0, app.mainWorkspaces.indexOf(app.activeWorkspace))
            stepped = false
            keys.forceActiveFocus()
        }
        Connections {
            target: app
            function onOverviewStepChanged() {
                if (!winO.open) return
                winO.sel = (winO.sel + 1) % app.mainWorkspaces.length
                winO.stepped = true
            }
        }

        function close() { app.overviewShown = false }

        function goTo(index) {
            const id = app.mainWorkspaces[index]
            if (id === undefined) return
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
            close()
        }

        function focusWindow(addr) {
            if (!addr) return
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
            close()
        }

        // focus it, then close the focused window: the same dispatchers
        // the keybinds use, so nothing new to go wrong
        function closeWindow(addr) {
            if (!addr) return
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
            Hyprland.dispatch("hl.dsp.window.close()")
            refreshLater.restart()
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
        // moment later, or the previews would redraw from the old layout
        Timer {
            id: refreshLater
            interval: 90
            onTriggered: Hyprland.refreshToplevels()
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                const n = app.mainWorkspaces.length
                if (e.key === Qt.Key_Escape) winO.close()
                else if (e.key === Qt.Key_Right) winO.sel = (winO.sel + 1) % n
                else if (e.key === Qt.Key_Left) winO.sel = (winO.sel - 1 + n) % n
                else if (e.key === Qt.Key_Down) winO.sel = Math.min(n - 1, winO.sel + winO.cols)
                else if (e.key === Qt.Key_Up) winO.sel = Math.max(0, winO.sel - winO.cols)
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                    winO.goTo(winO.sel)
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) winO.goTo(e.key - Qt.Key_1)
                else if (e.key === Qt.Key_0) winO.goTo(9)
                else return
                e.accepted = true
            }
            // switcher style: after stepping with Alt+Tab, letting go of
            // Alt goes to the selected workspace
            Keys.onReleased: e => {
                if (e.key === Qt.Key_Alt && winO.stepped) winO.goTo(winO.sel)
            }
        }

        // the dimmed backdrop fades with the panel
        Rectangle {
            anchors.fill: parent
            color: app.scrim(0.45)
            opacity: winO.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
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
            y: Math.max(app.barBottom + 24, (parent.height - height) / 2 - 40)
            width: body.implicitWidth + 44
            height: body.implicitHeight + 40
            opacity: winO.open ? 1 : 0
            scale: winO.open ? 1 : 0.95
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            radius: 28
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)

            // swallow clicks so they don't reach the backdrop
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: body
                anchors.centerIn: parent
                spacing: 16

                // title and the controls, in one line
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    spacing: 12
                    Text {
                        text: "Workspaces"
                        color: app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(17)
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Arrows and Enter, or a number.  Drag windows between workspaces.  Middle-click closes one."
                        color: app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(11)
                    }
                }

                Grid {
                    id: grid
                    columns: winO.cols
                    spacing: 14

                    Repeater {
                        model: ScriptModel { values: app.mainWorkspaces }

                        delegate: Item {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property int wsId: modelData
                            readonly property var ws:
                                Hyprland.workspaces.values.find(w => w.id === wsId) ?? null
                            readonly property bool current: wsId === app.activeWorkspace
                            readonly property bool selected: index === winO.sel
                            readonly property int count: ws ? ws.toplevels.values.length : 0
                            // distinct app classes, as plain strings
                            readonly property var classes: {
                                const seen = {}, out = []
                                if (ws) for (const t of ws.toplevels.values) {
                                    const c = t.lastIpcObject?.class ?? ""
                                    if (c && !seen[c]) { seen[c] = true; out.push(c) }
                                }
                                return out.slice(0, 6)
                            }

                            width: winO.tileW
                            height: winO.previewH + 40

                            // ---- preview area ----
                            ClippingRectangle {
                                id: preview
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: winO.previewH
                                radius: 16
                                color: tile.current ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.10) : app.cTile
                                border.width: drop.containsDrag || tile.selected || tile.current ? 2 : 1
                                border.color: drop.containsDrag ? app.cTeal
                                             : tile.selected ? app.cTeal
                                             : tile.current ? app.cBlue
                                             : Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                                Behavior on border.color { ColorAnimation { duration: app.animQuick } }

                                // empty space: go to this workspace
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: winO.sel = tile.index
                                    onClicked: winO.goTo(tile.index)
                                }

                                // accepts a dragged window preview
                                DropArea {
                                    id: drop
                                    anchors.fill: parent
                                    keys: ["qs-window"]
                                    onDropped: d => winO.moveWindow(d.source.addr, tile.wsId)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: tile.count === 0
                                    text: "Empty"
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
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
                                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
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

                                            // the window's title while hovered
                                            Rectangle {
                                                visible: wHov.hovered && !dh.active && parent.height > 34
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 22
                                                color: Qt.rgba(0, 0, 0, 0.6)
                                                Text {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    verticalAlignment: Text.AlignVCenter
                                                    text: win.ipc?.title ?? ""
                                                    color: "white"
                                                    font.family: "Inter"
                                                    font.pixelSize: app.fs(10)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        HoverHandler {
                                            id: wHov
                                            onHoveredChanged: if (hovered) winO.sel = tile.index
                                        }

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
                                            acceptedButtons: Qt.LeftButton
                                            onTapped: winO.focusWindow(win.addr)
                                        }
                                        TapHandler {
                                            acceptedButtons: Qt.MiddleButton
                                            onTapped: winO.closeWindow(win.addr)
                                        }

                                        DragHandler {
                                            id: dh
                                            acceptedButtons: Qt.LeftButton
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

                            // ---- under the preview: number and app icons ----
                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 30
                                spacing: 8

                                Rectangle {
                                    implicitWidth: Math.max(28, numT.implicitWidth + 16)
                                    implicitHeight: 24
                                    radius: 12
                                    color: tile.current ? app.cBlue
                                         : tile.selected ? Qt.rgba(app.cTeal.r, app.cTeal.g, app.cTeal.b, 0.3)
                                         : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                    Text {
                                        id: numT
                                        anchors.centerIn: parent
                                        text: tile.wsId
                                        color: tile.current ? app.cOnAccent : app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        font.bold: true
                                    }
                                }

                                Row {
                                    spacing: 4
                                    Repeater {
                                        model: tile.classes
                                        delegate: IconImage {
                                            required property var modelData
                                            implicitSize: 18
                                            source: app.iconFor(modelData)
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    visible: tile.count > 1
                                    text: tile.count + " windows"
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
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
}
