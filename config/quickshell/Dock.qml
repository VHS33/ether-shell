import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// ============================================================
//   DOCK
//   Pinned apps (in pinned order), a divider, then running apps that
//   aren't pinned.
//     click         focus the app (again: its next window), or start it
//     scroll        through its windows, either way
//     middle-click  a new window
//     right-click   its menu: its windows (switch to one, or close it),
//                   new window, the app's own actions, pin, close
//   An app started from here pulses until its window appears.
//
//   Auto-hide keeps the window mapped and slides the card below the
//   screen edge; a thin strip along the bottom brings it back.  The window
//   is taller than the dock so tooltips (and the menu) have room; the mask
//   keeps that space click-through.
//
//   Model: app.dockItems, plain values, through ScriptModels keyed by each
//   item's key: an app that's still there keeps its icon (a plain list
//   would have every icon recreated at each change).  Window titles are
//   read only when shown (app.windowsOf).
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // ---- one app's icon ----
    component DockIcon: Rectangle {
        id: it
        property var app
        property var win
        required property var modelData
        readonly property bool isActive: modelData.act === 1
        readonly property bool elsewhere: modelData.running && modelData.here !== 1
        readonly property bool starting: !modelData.running && modelData.id !== ""
                                         && app.dockStarting[modelData.id] !== undefined

        implicitWidth: win.cell
        implicitHeight: win.cell
        radius: width * 0.32
        color: isActive ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
             : itHov.hovered || win.menuKey === modelData.key ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
             : "transparent"
        opacity: win.dragKey === modelData.key ? 0.3 : elsewhere ? 0.5 : 1
        Behavior on color { ColorAnimation { duration: it.app.animQuick } }
        Behavior on opacity { NumberAnimation { duration: it.app.animQuick; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: itHov
            // running apps show their windows' previews after a moment
            onHoveredChanged: {
                if (hovered) it.win.hoverIcon(it.modelData, it.win.middle(it))
                else it.win.leaveIcon()
            }
        }

        IconImage {
            id: icon
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -2
            implicitSize: it.app.dockIcon
            source: it.modelData.icon
            // starting: a gentle pulse until its window appears
            SequentialAnimation on opacity {
                running: it.starting
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) icon.opacity = 1
            }
        }

        // running: a dot; focused: a short bar
        Rectangle {
            readonly property int len: it.isActive ? (it.modelData.n > 1 ? 18 : 12) : 5
            visible: it.modelData.running
            // along the edge nearest the screen's
            x: it.win.edge === "left" ? 3 : it.win.edge === "right" ? parent.width - width - 3 : (parent.width - width) / 2
            y: it.win.vertical ? (parent.height - height) / 2 : parent.height - height - 3
            width: it.win.vertical ? 4 : len
            height: it.win.vertical ? len : 4
            radius: 2
            color: it.isActive ? it.app.cBlue : it.app.cDim
            Behavior on width { NumberAnimation { duration: it.app.animQuick; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: it.app.animQuick; easing.type: Easing.OutCubic } }
        }

        // notifications waiting for it
        readonly property int badge: app.dockBadges[modelData.key] || 0
        Rectangle {
            visible: it.badge > 0
            width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
            color: it.app.cRed
            anchors.left: parent.left
            anchors.top: parent.top
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: it.badge > 9 ? "9+" : it.badge
                color: "#2b0a06"
                font.family: "Inter"
                font.pixelSize: it.app.fs(9)
                font.bold: true
            }
        }

        // window count
        Rectangle {
            visible: it.modelData.n > 1
            width: 16; height: 16; radius: 8
            color: it.app.cBlue
            anchors.right: parent.right
            anchors.top: parent.top
            Text {
                anchors.centerIn: parent
                text: it.modelData.n
                color: it.app.cOnAccent
                font.family: "Inter"
                font.pixelSize: it.app.fs(9)
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            // dragging: a pinned app to another place, or a running one into
            // the pinned ones to pin it there (a drag is never a click)
            property real pressAt: 0
            property bool dragged: false
            onPressed: m => { pressAt = it.win.vertical ? m.y : m.x; dragged = false }
            onPositionChanged: m => {
                if (!(pressedButtons & Qt.LeftButton)) return
                if (!dragged && Math.abs((it.win.vertical ? m.y : m.x) - pressAt) > 10 && it.modelData.id !== "") {
                    dragged = true
                    it.win.startDrag(it.modelData)
                }
                if (dragged) it.win.moveDrag(it.win.alongPoint(it, m.x, m.y))
            }
            onReleased: if (dragged) it.win.endDrag()
            onCanceled: if (dragged) { dragged = false; it.win.cancelDrag() }
            onClicked: m => {
                if (dragged) { dragged = false; return }
                const d = it.modelData
                if (m.button === Qt.RightButton) {
                    it.win.openMenu(d, it.win.middle(it))
                } else if (m.button === Qt.MiddleButton) {
                    if (d.id) it.app.dockLaunch(d.id)
                } else if (d.running) {
                    it.app.cycleGroup(d.cls, d.addrs)
                } else if (d.id) {
                    it.app.dockLaunch(d.id)
                }
            }
            // scroll: through its windows, either way
            onWheel: w => {
                const d = it.modelData
                if (d.running && d.addrs.length) it.app.cycleGroup(d.cls, d.addrs, w.angleDelta.y > 0)
            }
        }

        // tooltip, in the room above the dock (titles read only now)
        Rectangle {
            visible: itHov.hovered && it.win.menuKey === "" && it.win.dragKey === ""
                     && !(it.modelData.running && it.win.previewKey === it.modelData.key)
            radius: 12
            color: it.app.cCard
            border.width: 1
            border.color: Qt.rgba(it.app.cBorder.r, it.app.cBorder.g, it.app.cBorder.b, 0.6)
            implicitWidth: Math.min(tipText.implicitWidth + 20, 340)
            implicitHeight: tipText.implicitHeight + 12
            anchors.horizontalCenter: it.win.vertical ? undefined : parent.horizontalCenter
            anchors.bottom: it.win.vertical ? undefined : parent.top
            anchors.bottomMargin: 10
            anchors.verticalCenter: it.win.vertical ? parent.verticalCenter : undefined
            anchors.left: it.win.edge === "left" ? parent.right : undefined
            anchors.leftMargin: 10
            anchors.right: it.win.edge === "right" ? parent.left : undefined
            anchors.rightMargin: 10
            z: 10
            Text {
                id: tipText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 320)
                text: {
                    if (!itHov.hovered) return ""
                    const d = it.modelData
                    if (it.starting) return d.name + ", starting\u2026"
                    if (!d.running) return d.name
                    const ws = it.app.windowsOf(d.addrs)
                    const main = d.n > 1 ? d.name + ", " + d.n + " windows" : ((ws[0] && ws[0].title) || d.name)
                    return main + (it.elsewhere ? " (another workspace)" : "")
                }
                color: it.app.cFg
                font.family: "Inter"
                font.pixelSize: it.app.fs(11)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ---- one line of the menu ----
    component MenuRow: Rectangle {
        id: mr
        property var app
        property string glyph: ""
        property string text: ""
        property string detail: ""
        property bool danger: false
        signal chosen()
        Layout.fillWidth: true
        implicitWidth: mrRow.implicitWidth + 24
        implicitHeight: 34
        radius: 10
        color: mrHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
        HoverHandler { id: mrHov }
        RowLayout {
            id: mrRow
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Text {
                text: mr.glyph
                color: mr.danger ? mr.app.cRed : mr.app.cDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: 18
            }
            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: 260
                text: mr.text
                color: mr.danger ? mr.app.cRed : mr.app.cFg
                font.family: "Inter"
                font.pixelSize: mr.app.fs(12)
                elide: Text.ElideRight
            }
            Text {
                visible: mr.detail !== ""
                text: mr.detail
                color: mr.app.cFaint
                font.family: "Inter"
                font.pixelSize: mr.app.fs(11)
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mr.chosen() }
    }

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // only when the dock is switched on (on the main screen, or on every
        // screen with that option)
        active: (modelData.name === rootV.app.mainScreen || rootV.app.dockAllScreens) && rootV.app.dockEnabled

    PanelWindow {
        id: winD
        readonly property var app: rootV.app
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: (modelData.name === app.mainScreen || app.dockAllScreens) && app.dockEnabled && app.dockItems.length > 0

        readonly property int cell: app.dockIcon + 16
        readonly property int cardH: cell + 12
        readonly property int tipRoom: vertical ? 360 : 44
        readonly property int bottomPad: app.dockAutoHide ? app.gap : 0

        // ---- which edge: along the bottom, or down the left or right ----
        readonly property string edge: app.dockEdge
        readonly property bool vertical: edge !== "bottom"
        // positions along the dock: x for the bottom, y down a side (in the window)
        function alongPoint(item, px, py) { const p = item.mapToItem(contentItem, px, py); return vertical ? p.y : p.x }
        function middle(item) { return alongPoint(item, item.width / 2, item.height / 2) }
        function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
        // a popup of size w x h: beside the dock (above it, or to its side),
        // centred on `pos` along it, kept on the screen
        function popX(w, pos) {
            return !vertical ? clamp(pos - w / 2, 8, width - w - 8)
                 : edge === "left" ? card.x + card.width + 8 : card.x - w - 8
        }
        function popY(h, pos) { return !vertical ? card.y - h - 8 : clamp(pos - h / 2, 8, height - h - 8) }

        // ---- the menu: which item's is open, and where ----
        property var menuFor: null
        property real menuX: 0
        property var menuWins: []
        readonly property string menuKey: menuFor ? menuFor.key : ""
        readonly property bool menuOpen: menuFor !== null
        function openMenu(d, x) {
            if (menuKey === d.key) { closeMenu(); return }
            menuWins = d.running ? app.windowsOf(d.addrs) : []
            menuX = x
            menuFor = d
            menuFocus.forceActiveFocus()
        }
        function closeMenu() { menuFor = null }

        // ---- previews: a running app's windows, live, above its icon ----
        property var previewFor: null
        property real previewX: 0
        readonly property string previewKey: previewFor ? previewFor.key : ""
        readonly property bool previewOpen: previewFor !== null && !menuOpen && dragKey === ""
        property var pendingPreview: null
        property real pendingX: 0
        property bool overPreviews: false
        function hoverIcon(d, x) {
            leavePreview.stop()
            if (!d.running || menuOpen || dragKey !== "") { pendingPreview = null; showPreview.stop(); return }
            if (previewOpen) { previewFor = d; previewX = x; return }      // already showing: switch now
            pendingPreview = d; pendingX = x
            showPreview.restart()
        }
        function leaveIcon() { showPreview.stop(); leavePreview.restart() }
        Timer { id: showPreview; interval: 450; onTriggered: { winD.previewFor = winD.pendingPreview; winD.previewX = winD.pendingX } }
        Timer { id: leavePreview; interval: 250; onTriggered: if (!winD.overPreviews) winD.previewFor = null }

        // ---- dragging ----
        property string dragKey: ""
        property var dragFor: null
        property real dragX: 0
        property int dropIndex: -1
        function startDrag(d) { dragFor = d; dragKey = d.key; previewFor = null; showPreview.stop() }
        // where it would land: before the first pinned icon it's left of
        // (past the divider, a pinned app just goes back where it was)
        function moveDrag(x) {
            dragX = x
            const n = pinnedRep.count
            let idx = n
            for (let k = 0; k < n; k++) {
                const ic = pinnedRep.itemAt(k)
                if (!ic) continue
                if (x < middle(ic)) { idx = k; break }
            }
            const lastPinned = n > 0 ? pinnedRep.itemAt(n - 1) : null
            const pastPinned = lastPinned && x > alongPoint(lastPinned, lastPinned.width + (vertical ? 0 : winD.cell * 0.6),
                                                                        lastPinned.height + (vertical ? winD.cell * 0.6 : 0))
            dropIndex = pastPinned ? -1 : idx
        }
        function endDrag() {
            if (dragFor && dropIndex >= 0) app.movePin(dragFor, dropIndex)
            cancelDrag()
        }
        function cancelDrag() { dragFor = null; dragKey = ""; dropIndex = -1 }
        // where the marker goes: the gap before icon dropIndex
        function dropMarkerX() {
            const n = pinnedRep.count
            if (dropIndex < 0 || n === 0) return -100
            if (dropIndex < n) { const ic = pinnedRep.itemAt(dropIndex); return ic ? alongPoint(ic, -2, -2) : -100 }
            const last = pinnedRep.itemAt(n - 1)
            return last ? alongPoint(last, last.width + 2, last.height + 2) : -100
        }
        // the item it's for, kept current (its windows open and close)
        Connections {
            target: winD.app
            function onDockItemsChanged() {
                if (!winD.menuFor) return
                const d = winD.app.dockItems.find(x => x.key === winD.menuFor.key)
                if (!d) { winD.closeMenu(); return }
                winD.menuFor = d
                winD.menuWins = d.running ? winD.app.windowsOf(d.addrs) : []
            }
        }
        // a click anywhere else, or Escape, closes it
        HyprlandFocusGrab {
            windows: [ winD ]
            active: winD.menuOpen
            onCleared: winD.closeMenu()
        }
        WlrLayershell.keyboardFocus: menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Item {
            id: menuFocus
            Keys.onEscapePressed: winD.closeMenu()
        }

        // with auto-hide the window reaches the very bottom edge, so the
        // strip that brings the dock back is where the pointer stops
        // along its edge: the full width at the bottom, the full height down a side
        anchors { bottom: true; top: vertical; left: edge !== "right"; right: edge !== "left" }
        margins {
            bottom: edge === "bottom" && !app.dockAutoHide ? app.gap : 0
            left: edge === "left" && !app.dockAutoHide ? app.gap : 0
            right: edge === "right" && !app.dockAutoHide ? app.gap : 0
        }
        // its depth: the dock, plus room for what opens beside it
        readonly property int depth: cardH + bottomPad
            + Math.max(tipRoom, menuOpen ? (vertical ? menu.implicitWidth : menu.implicitHeight) + 16 : 0,
                       previewOpen ? (vertical ? previews.implicitWidth : previews.implicitHeight) + 16 : 0)
        implicitHeight: vertical ? 0 : depth
        implicitWidth: vertical ? depth : 0
        color: "transparent"

        // reserve the strip only while the dock stays up
        exclusionMode: app.dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: app.dockAutoHide ? 0 : cardH + app.gap

        // ---- auto-hide ----
        property bool pointerIn: false
        // "windows": up unless a window on this screen's current workspace
        // overlaps where it sits (its area, in Hyprland's logical pixels)
        readonly property bool covered: app.dockHide === "windows"
            && app.dockCovered(modelData.name,
                edge === "left"  ? { x: modelData.x, y: modelData.y + card.y, w: cardH + app.gap, h: card.height }
              : edge === "right" ? { x: modelData.x + modelData.width - cardH - app.gap, y: modelData.y + card.y, w: cardH + app.gap, h: card.height }
              :                    { x: modelData.x + card.x, y: modelData.y + modelData.height - cardH - app.gap, w: card.width, h: cardH + app.gap })
        readonly property bool shown: app.dockHide === "never" || (app.dockHide === "windows" && !covered)
                                      || pointerIn || holdOpen.running || menuOpen || overPreviews || dragKey !== ""
        Timer {
            id: holdOpen
            interval: 600
        }

        property Region cardMask: Region { item: card; Region { item: menu } Region { item: previews } }
        // the thin strip along the screen's edge that brings it back
        property Region edgeMask: Region {
            x: winD.edge === "right" ? winD.width - 3 : 0
            y: winD.vertical ? 0 : winD.height - 3
            width: winD.vertical ? 3 : winD.width
            height: winD.vertical ? winD.height : 3
        }
        mask: shown ? cardMask : edgeMask

        // touching the bottom edge brings it back
        MouseArea {
            x: winD.edge === "right" ? parent.width - 3 : 0
            y: winD.vertical ? 0 : parent.height - 3
            width: winD.vertical ? 3 : parent.width
            height: winD.vertical ? parent.height : 3
            hoverEnabled: true
            enabled: winD.app.dockAutoHide && !winD.shown
            onEntered: winD.pointerIn = true
        }

        Rectangle {
            id: card
            // centred along its edge; slid off the screen when hidden
            x: winD.edge === "left"  ? (winD.shown ? winD.bottomPad : -width - 8)
             : winD.edge === "right" ? (winD.shown ? winD.width - width - winD.bottomPad : winD.width + 8)
             : (winD.width - width) / 2
            y: winD.vertical ? (winD.height - height) / 2
             : (winD.shown ? winD.height - winD.cardH - winD.bottomPad : winD.height + 8)
            Behavior on y { enabled: !winD.vertical; NumberAnimation { duration: winD.app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on x { enabled: winD.vertical; NumberAnimation { duration: winD.app.animNormal; easing.type: Easing.OutCubic } }
            width: winD.vertical ? winD.cardH : dockRow.implicitWidth + 16
            height: winD.vertical ? dockRow.implicitHeight + 16 : winD.cardH
            radius: height / 2.4
            color: winD.app.cBg
            border.width: 1
            border.color: Qt.rgba(winD.app.cBorder.r, winD.app.cBorder.g, winD.app.cBorder.b, 0.5)

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) winD.pointerIn = true
                    else { winD.pointerIn = false; holdOpen.restart() }
                }
            }

            // a row along the bottom, a column down a side
            GridLayout {
                id: dockRow
                anchors.centerIn: parent
                flow: winD.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                rows: winD.vertical ? -1 : 1
                columns: winD.vertical ? 1 : -1
                rowSpacing: 4
                columnSpacing: 4

                Repeater {
                    id: pinnedRep
                    model: ScriptModel { values: winD.app.dockItems.filter(i => i.pinned); objectProp: "key" }
                    delegate: DockIcon { app: winD.app; win: winD }
                }
                // between pinned apps and the other running ones
                Rectangle {
                    visible: pinnedRep.count > 0 && otherRep.count > 0
                    Layout.alignment: Qt.AlignCenter
                    Layout.leftMargin: winD.vertical ? 0 : 4
                    Layout.rightMargin: winD.vertical ? 0 : 4
                    Layout.topMargin: winD.vertical ? 4 : 0
                    Layout.bottomMargin: winD.vertical ? 4 : 0
                    implicitWidth: winD.vertical ? winD.cell * 0.55 : 1
                    implicitHeight: winD.vertical ? 1 : winD.cell * 0.55
                    color: Qt.rgba(winD.app.cFg.r, winD.app.cFg.g, winD.app.cFg.b, 0.22)
                }
                Repeater {
                    id: otherRep
                    model: ScriptModel { values: winD.app.dockItems.filter(i => !i.pinned); objectProp: "key" }
                    delegate: DockIcon { app: winD.app; win: winD }
                }
            }
        }

        // ---- previews: live, while showing (captures stop when they close) ----
        Rectangle {
            id: previews
            readonly property var wins: winD.previewOpen ? winD.app.toplevelsOf(winD.previewFor.addrs) : []
            readonly property int thumbW: 220
            readonly property int thumbH: 132
            visible: winD.previewOpen && wins.length > 0
            width: visible ? prevRow.implicitWidth + 16 : 0
            height: visible ? prevRow.implicitHeight + 16 : 0
            implicitHeight: prevRow.implicitHeight + 16
            implicitWidth: prevRow.implicitWidth + 16
            x: winD.popX(width, winD.previewX)
            y: winD.popY(height, winD.previewX)
            radius: 18
            color: winD.app.cCard
            border.width: 1
            border.color: Qt.rgba(winD.app.cBorder.r, winD.app.cBorder.g, winD.app.cBorder.b, 0.6)
            HoverHandler {
                onHoveredChanged: {
                    winD.overPreviews = hovered
                    if (!hovered) leavePreview.restart()
                }
            }
            Row {
                id: prevRow
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: previews.wins
                    delegate: Rectangle {
                        id: pv
                        required property var modelData
                        readonly property string addr: modelData.lastIpcObject?.address ?? ""
                        width: previews.thumbW
                        height: previews.thumbH + 30
                        radius: 12
                        color: pvHov.hovered ? Qt.rgba(winD.app.cFg.r, winD.app.cFg.g, winD.app.cFg.b, 0.1) : "transparent"
                        HoverHandler { id: pvHov }
                        Item {
                            id: shot
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                            height: previews.thumbH - 6
                            clip: true
                            ScreencopyView {
                                id: cap
                                anchors.centerIn: parent
                                // the window's own shape, fitted in
                                readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
                                width: Math.min(parent.width, parent.height * ratio)
                                height: width / ratio
                                captureSource: winD.previewOpen ? pv.modelData.wayland : null
                                live: true
                            }
                            // its icon until the capture arrives
                            IconImage {
                                anchors.centerIn: parent
                                visible: !cap.hasContent
                                implicitSize: 40
                                source: winD.previewFor ? winD.previewFor.icon : ""
                            }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 30; bottomMargin: 7 }
                            text: pv.modelData.title || (winD.previewFor ? winD.previewFor.name : "")
                            color: winD.app.cFg
                            font.family: "Inter"
                            font.pixelSize: winD.app.fs(11)
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { winD.app.focusWindow(pv.addr); winD.previewFor = null }
                        }
                        // close just this window
                        Rectangle {
                            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                            implicitWidth: 24; implicitHeight: 24; radius: 12
                            opacity: pvHov.hovered ? 1 : 0
                            color: pxHov.hovered ? Qt.rgba(winD.app.cRed.r, winD.app.cRed.g, winD.app.cRed.b, 0.2) : "transparent"
                            HoverHandler { id: pxHov }
                            Text {
                                anchors.centerIn: parent
                                text: "close"
                                color: pxHov.hovered ? winD.app.cRed : winD.app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: winD.app.closeWindow(pv.addr) }
                        }
                    }
                }
            }
        }

        // ---- dragging: the icon under the pointer, and where it would go ----
        IconImage {
            visible: winD.dragKey !== ""
            implicitSize: winD.app.dockIcon
            source: winD.dragFor ? winD.dragFor.icon : ""
            x: winD.vertical ? card.x + (winD.cardH - width) / 2 + (winD.edge === "left" ? 10 : -10) : winD.dragX - width / 2
            y: winD.vertical ? winD.dragX - height / 2 : card.y + (winD.cardH - height) / 2 - 10
            opacity: 0.9
            z: 20
        }
        Rectangle {
            visible: winD.dragKey !== "" && winD.dropIndex >= 0
            width: winD.vertical ? winD.cell * 0.7 : 3
            height: winD.vertical ? 3 : winD.cell * 0.7
            radius: 1.5
            color: winD.app.cBlue
            x: winD.vertical ? card.x + (winD.cardH - width) / 2 : winD.dropMarkerX() - 1
            y: winD.vertical ? winD.dropMarkerX() - 1 : card.y + (winD.cardH - height) / 2
            z: 19
        }

        // ---- the menu, above the icon it's for ----
        Rectangle {
            id: menu
            readonly property var d: winD.menuFor
            readonly property var entry: d && d.id ? DesktopEntries.byId(d.id) : null
            readonly property var actions: entry && entry.actions ? Array.from(entry.actions) : []
            // the app's own "New Window", when it has one, instead of ours
            readonly property bool ownNewWindow: actions.some(a => String(a.name).trim().toLowerCase() === "new window")
            visible: winD.menuOpen
            width: winD.menuOpen ? Math.max(220, menuCol.implicitWidth + 12) : 0
            height: winD.menuOpen ? menuCol.implicitHeight + 12 : 0
            implicitHeight: menuCol.implicitHeight + 12
            implicitWidth: Math.max(220, menuCol.implicitWidth + 12)
            x: winD.popX(width, winD.menuX)
            y: winD.popY(height, winD.menuX)
            radius: 16
            color: winD.app.cCard
            border.width: 1
            border.color: Qt.rgba(winD.app.cBorder.r, winD.app.cBorder.g, winD.app.cBorder.b, 0.6)

            ColumnLayout {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    Layout.bottomMargin: 4
                    text: menu.d ? menu.d.name : ""
                    color: winD.app.cFg
                    font.family: "Inter"
                    font.pixelSize: winD.app.fs(13)
                    font.bold: true
                    elide: Text.ElideRight
                }

                // its windows: switch to one, or close just that one
                Repeater {
                    model: winD.menuWins
                    delegate: Rectangle {
                        id: wr
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: wrRow.implicitWidth + 24
                        implicitHeight: 34
                        radius: 10
                        color: wrHov.hovered ? Qt.rgba(winD.app.cFg.r, winD.app.cFg.g, winD.app.cFg.b, 0.1) : "transparent"
                        HoverHandler { id: wrHov }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { winD.app.focusWindow(wr.modelData.addr); winD.closeMenu() }
                        }
                        RowLayout {
                            id: wrRow
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 10
                            Text {
                                text: wr.modelData.active ? "radio_button_checked" : "web_asset"
                                color: wr.modelData.active ? winD.app.cBlue : winD.app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 18
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 260
                                text: wr.modelData.title || menu.d.name
                                color: winD.app.cFg
                                font.family: "Inter"
                                font.pixelSize: winD.app.fs(12)
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: wr.modelData.ws !== ""
                                text: wr.modelData.ws
                                color: winD.app.cFaint
                                font.family: "Inter"
                                font.pixelSize: winD.app.fs(11)
                            }
                            // close just this window (shown on hover)
                            Rectangle {
                                implicitWidth: 24; implicitHeight: 24; radius: 12
                                opacity: wrHov.hovered ? 1 : 0
                                color: xHov.hovered ? Qt.rgba(winD.app.cRed.r, winD.app.cRed.g, winD.app.cRed.b, 0.2) : "transparent"
                                HoverHandler { id: xHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: "close"
                                    color: xHov.hovered ? winD.app.cRed : winD.app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: winD.app.closeWindow(wr.modelData.addr)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: winD.menuWins.length > 0
                    Layout.fillWidth: true
                    Layout.margins: 6
                    implicitHeight: 1
                    color: Qt.rgba(winD.app.cFg.r, winD.app.cFg.g, winD.app.cFg.b, 0.12)
                }

                MenuRow {
                    app: winD.app
                    visible: menu.d !== null && menu.d.id !== "" && !menu.ownNewWindow
                    glyph: "add"
                    text: menu.d && menu.d.running ? "New window" : "Open"
                    onChosen: { winD.app.dockLaunch(menu.d.id); winD.closeMenu() }
                }
                // the app's own actions (its desktop file's)
                Repeater {
                    model: menu.actions
                    delegate: MenuRow {
                        required property var modelData
                        required property int index
                        app: winD.app
                        glyph: "bolt"
                        text: modelData.name
                        onChosen: { winD.app.launchAction(menu.d.id, index); winD.closeMenu() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: 6
                    implicitHeight: 1
                    color: Qt.rgba(winD.app.cFg.r, winD.app.cFg.g, winD.app.cFg.b, 0.12)
                }

                MenuRow {
                    app: winD.app
                    visible: menu.d !== null && (menu.d.id !== "" || menu.d.pinned)
                    glyph: menu.d && menu.d.pinned ? "keep_off" : "keep"
                    text: menu.d && menu.d.pinned ? "Unpin from the dock" : "Pin to the dock"
                    onChosen: { winD.app.togglePin(menu.d); winD.closeMenu() }
                }
                MenuRow {
                    app: winD.app
                    visible: menu.d !== null && menu.d.running
                    glyph: "close"
                    danger: true
                    text: menu.d && menu.d.n > 1 ? "Close all " + menu.d.n + " windows" : "Close"
                    onChosen: { for (const a of menu.d.addrs) winD.app.closeWindow(a); winD.closeMenu() }
                }
            }
        }
    }
    }
}
