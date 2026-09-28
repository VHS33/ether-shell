import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.plugins

// ============================================================
//   LEFT ISLAND: SYSTEM
//   The left pill, able to grow.  Workspace dots and scrolling
//   work as always; clicking a stat stretches the pill down and to
//   the right, pinned to the left edge, into live graphs for CPU,
//   memory, GPU and temperature (the last two minutes, from
//   app.cpuHist and friends) and the busiest processes.  Esc or the
//   arrow shrinks it back.
//
//   Settings > Bar > "Clicking a stat" switches back to the plain
//   pill (BarLeft.qml), whose stats open btop.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // a stat inside the stats group: its icon (soft) and its number, in a
    // fixed-width slot so the group doesn't shift as values change
    component Stat: Row {
        id: st
        property var app
        property string icon: ""
        property string value: ""
        property string widest: "100%"
        property real level: 0
        property color tint: app.cFg
        property bool clickable: false
        signal clicked()
        spacing: 4

        TextMetrics {
            id: stMetrics
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: st.app.fs(12)
            text: st.widest
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: st.icon
            color: Qt.rgba(st.app.cFg.r, st.app.cFg.g, st.app.cFg.b, 0.55)
            font.family: "Material Symbols Rounded"
            font.pixelSize: st.app.fs(15)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: stMetrics.advanceWidth
            text: st.value
            color: st.app.cFg
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: st.app.fs(12)
        }
    }

    // a stat with its value and an area graph of its recent history
    component Graph: Rectangle {
        id: gr
        property var app
        property string title: ""
        property string value: ""
        property var points: []
        property real maxValue: 100
        property color tint: app.cBlue

        Layout.fillWidth: true
        implicitHeight: 128
        radius: 20
        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
        clip: true

        // kept up to date even while the drawer is closed (they're small),
        // so opening shows them already drawn
        onPointsChanged: plot.requestPaint()
        onTintChanged: if (visible) plot.requestPaint()
        onVisibleChanged: if (visible) plot.requestPaint()

        Canvas {
            id: plot
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.62
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const pts = gr.points
                if (!pts || pts.length < 2) return
                const n = 60, w = width, h = height
                const step = w / (n - 1)
                const x0 = w - (pts.length - 1) * step
                const y = v => h - Math.max(0, Math.min(1, v / gr.maxValue)) * (h - 4) - 2
                const c = gr.tint
                // the area
                ctx.beginPath()
                ctx.moveTo(x0, h)
                for (let i = 0; i < pts.length; i++) ctx.lineTo(x0 + i * step, y(pts[i]))
                ctx.lineTo(w, h)
                ctx.closePath()
                const g = ctx.createLinearGradient(0, 0, 0, h)
                g.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.38))
                g.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.02))
                ctx.fillStyle = g
                ctx.fill()
                // the line on top
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const px = x0 + i * step, py = y(pts[i])
                    if (i === 0) ctx.moveTo(px, py)
                    else ctx.lineTo(px, py)
                }
                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.95)
                ctx.stroke()
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 0
            Text {
                text: gr.title
                color: gr.app.cDim
                font.family: "Inter"
                font.pixelSize: gr.app.fs(11)
                font.bold: true
            }
            Text {
                text: gr.value
                color: gr.app.cFg
                font.family: "Inter"
                font.pixelSize: gr.app.fs(24)
                font.weight: Font.Light
            }
        }
    }

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        active: modelData.name === app.mainScreen

    PanelWindow {
        id: isl3
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.leftMorph
        // ---- where this section's drawer goes, for the long bar ----
        // this window's left edge on screen, the section's centre, and the
        // drawer's final left edge: centred under the section, but kept
        // clear of the bar's rounded ends
        readonly property real scrX: 0
        readonly property real secCX: scrX + shape.x + shape.width / 2
        // the left drawer runs flush down the bar's left end
        readonly property real finalX: app.gap
        Binding {
            target: app
            property: "leftGeom"
            // Whichever copy is in charge writes; one that stops being in
            // charge must not put back the value from before it started.
            // (At startup the other monitor's copy is briefly in charge,
            // and restoring its stale values doubled the drawers.)
            restoreMode: Binding.RestoreNone
            when: isl3.visible && isl3.att
            value: ({ x: isl3.finalX, w: isl3.openW, h: isl3.openH, cx: isl3.secCX, secW: shape.width,
                      flush: "left" })
        }

        readonly property bool open: app.sysShown

        readonly property real pillW: leftRow.implicitWidth + 12
        // On the long bar, worked out as if the title pill were at its widest,
        // so it stays the same whatever's focused, and is never narrower than
        // the section (the drawer grows out of the bar's left end, and would
        // otherwise shrink as it opened).
        readonly property real openW: att ? Math.max(560, pillW - awGroup.implicitWidth + awGroup.maxW)
                                          : Math.max(560, pillW)
        readonly property real openH: panel.implicitHeight

        // extra room to the right and below, for the open panel's shadow
        readonly property int shadowRoom: 36
        // attached: flush with the top-left corner, the section inset
        // far enough for the drawer's curved corner to fit beside it
        readonly property bool att: app.barAttached
        anchors { top: true; left: true }
        margins { top: att ? 0 : app.gap; left: att ? 0 : app.gap }
        // On the long bar a fixed size, well beyond what the section needs, so
        // nothing inside it (the title growing and shrinking) resizes the
        // window: resizing makes Hyprland redraw it from scratch.  Only the
        // shape takes clicks, so the extra width is invisible and inert.
        implicitWidth: att ? Math.max(openW + 16, Math.round(app.mainScreenW / 2))
                           : openW + shadowRoom + 16
        // On the long bar just the bar's height: the drawer's contents are
        // drawn in the glass window (BarStrip), so a drawer-tall window here
        // only held bigger buffers and redraw area for nothing.
        implicitHeight: att ? app.barBottom + 6
                            : Math.max(openH, app.pillH) + shadowRoom
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // on the long bar the drawer lives in BarStrip's window, which takes
        // the keyboard; this window only needs it for the islands style
        WlrLayershell.keyboardFocus: open && !att ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // only the shape takes clicks, whatever size it is right now
        mask: Region {
            item: shape
            Region {
                x: drawerHost.x
                y: drawerHost.y
                width: drawerHost.width
                height: 0      // the drawer takes its clicks in BarStrip's window
            }
        }

        // sections arrive in turn, as in the other islands
        readonly property int sections: 4
        property int revealed: 0
        Timer {
            id: revealStart
            interval: Math.round(app.animSlow * 0.45)
            onTriggered: { isl3.revealed = 1; revealStep.start() }
        }
        Timer {
            id: revealStep
            interval: app.dur(45)
            repeat: true
            onTriggered: {
                isl3.revealed += 1
                if (isl3.revealed >= isl3.sections) stop()
            }
        }
        onOpenChanged: {
            revealStep.stop()
            revealStart.stop()
            if (open) {
                keys.forceActiveFocus()
                if (app.motionOn) { revealed = 0; revealStart.start() }
                else revealed = sections
            } else {
                revealed = 0
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: app.sysShown = false
        }

        Rectangle {
            id: shape
            anchors.left: parent.left
            anchors.leftMargin: isl3.att ? app.gap + 10 : 0
            y: isl3.att ? app.barTop : 0
            width: isl3.open && !isl3.att ? isl3.openW : isl3.pillW
            height: isl3.att ? app.barH : (isl3.open ? isl3.openH : app.pillH)
            // attached: square along the top (it's part of the bar),
            // rounded at the bottom once it's a drawer
            radius: isl3.att ? app.barH / 2 : (isl3.open ? 28 : app.pillH / 2)
            // edgeless glass while it's a pill; hovering brightens it a
            // touch.  The hairline edge returns once it opens into a panel.
            color: isl3.att
                   ? "transparent"
                   : (isl3.open ? app.cCard
                      : shapeHov.hovered ? Qt.tint(app.cBg, Qt.rgba(1, 1, 1, 0.07)) : app.cBg)
            border.width: !isl3.att && isl3.open ? 1 : 0
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
            scale: !isl3.att && !isl3.open && shapeHov.hovered ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
            HoverHandler { id: shapeHov }
            clip: true

            Behavior on width { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: app.animNormal } }

            // depth only for the open panel: the pill stays flat glass
            layer.enabled: !isl3.att && (isl3.open || height > app.pillH + 2)
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 1.0
                shadowVerticalOffset: 10
                shadowHorizontalOffset: 0
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                height: 120
                radius: shape.radius
                // only for the three-pill style, where the panel opens around
                // it; on the long bar it drew a tinted pill, rounded corners
                // and all, inside the section whenever a drawer was open
                opacity: isl3.open && !isl3.att ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.16) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            // a thin line of light along the top edge of the glass, the
            // upper half of a pill-shaped hairline
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: app.pillH / 2
                clip: true
                opacity: isl3.open || isl3.att ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animQuick } }
                Rectangle {
                    width: parent.width
                    height: app.pillH
                    radius: app.pillH / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                }
            }

            // ================= the pill =================
            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                width: isl3.pillW
                height: isl3.att ? app.barH : app.pillH
                opacity: isl3.att || !isl3.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

                // scroll anywhere on the pill to change workspace
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: w => app.cycleWorkspace(w.angleDelta.y > 0 ? -1 : 1)
                }

                RowLayout {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: 6

                    // ---- the assistant: opens its panel down the left side ----
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: app.aiShown ? app.cPrimC
                             : aiHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: aiHov }
                        Text {
                            anchors.centerIn: parent
                            text: "auto_awesome"
                            color: app.aiShown ? app.cOnPrimC : app.cFg
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(16)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.aiShown = !app.aiShown
                        }
                    }

                    // ---- workspaces, in their own group: a number, or the icon
                    //      of the app on it; the one showing on this monitor is
                    //      a solid pill (softer when the other monitor has focus)
                    Rectangle {
                        implicitWidth: wsStrip.implicitWidth + 8
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, wsGHov.hovered ? 0.11 : 0.07)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: wsGHov }

                        Item {
                            id: wsStrip
                            anchors.centerIn: parent
                            readonly property var ids: app.mainWorkspaces
                            readonly property int count: ids.length
                            readonly property int slot: 22
                            readonly property int gap: 1
                            readonly property int pitch: slot + gap
                            readonly property int activeIndex: ids.indexOf(app.mainActive)
                            readonly property bool here: !app.secondFocused
                            implicitWidth: count * slot + (count - 1) * gap
                            implicitHeight: 22

                            // the one showing on this monitor
                            Rectangle {
                                width: 28
                                height: 22
                                radius: 11
                                x: wsStrip.activeIndex * wsStrip.pitch + (wsStrip.slot - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: wsStrip.here ? app.cBlue : Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.3)
                                visible: wsStrip.activeIndex >= 0
                                Behavior on x {
                                    NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic }
                                }
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                            }

                            // The dots are made once and kept: the model is just how many
                            // there are, and each dot reads its own details.  (Handing
                            // the list itself to the Repeater destroyed and remade every
                            // dot, icons and all, on each change of window focus.)
                            readonly property var info: app.workspacesFor(app.mainScreen)
                            Repeater {
                                model: wsStrip.count
                                delegate: Item {
                                    id: ws
                                    required property int index
                                    readonly property var modelData: wsStrip.info[index]
                                                                     ?? ({ id: -1, occupied: false, app: "" })
                                    readonly property bool active: modelData.id === app.mainActive
                                    readonly property bool showIcon: modelData.app !== ""
                                    x: index * wsStrip.pitch
                                    width: wsStrip.slot
                                    height: wsStrip.height
                                    HoverHandler {
                                        id: wsHov
                                        onHoveredChanged: {
                                            if (hovered) app.wsHoverStart(ws.modelData.id,
                                                ws.mapToItem(null, ws.width / 2, 0).x + isl3.scrX, app.mainScreen)
                                            else app.wsHoverEnd(ws.modelData.id)
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !ws.showIcon
                                        text: ws.index + 1 === 10 ? "10" : ws.index + 1
                                        color: ws.active && wsStrip.here ? app.cOnAccent
                                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b,
                                                       ws.active || wsHov.hovered ? 0.9 : ws.modelData.occupied ? 0.65 : 0.3)
                                        font.family: "Inter"
                                        font.weight: ws.active ? Font.DemiBold : Font.Medium
                                        font.pixelSize: app.fs(11)
                                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    }
                                    // the app on this workspace
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: ws.showIcon
                                        implicitSize: 15
                                        source: ws.showIcon ? app.iconFor(ws.modelData.app) : ""
                                        opacity: ws.active || wsHov.hovered ? 1 : 0.8
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            app.wsHoverEnd(ws.modelData.id)
                                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws.modelData.id + " })")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- the other monitor's workspaces, numbered 1-5 of their own;
                    //      SUPER + number reaches them while that monitor has focus
                    Rectangle {
                        visible: app.secondScreen !== "" && app.secondWorkspaces.length > 0
                        implicitWidth: wsStrip2.implicitWidth + 8 + 22
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, wsGHov2.hovered ? 0.11 : 0.07)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: wsGHov2 }

                        Text {
                            id: monIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: "desktop_windows"
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, app.secondFocused ? 0.9 : 0.45)
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(13)
                        }
                        Item {
                            id: wsStrip2
                            anchors.left: monIcon.right
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property var ids: app.secondWorkspaces
                            readonly property int count: ids.length
                            readonly property int slot: 22
                            readonly property int gap: 1
                            readonly property int pitch: slot + gap
                            readonly property int activeIndex: ids.indexOf(app.secondActive)
                            readonly property bool here: app.secondFocused
                            implicitWidth: count * slot + (count - 1) * gap
                            implicitHeight: 22

                            // the one showing on this monitor
                            Rectangle {
                                width: 28
                                height: 22
                                radius: 11
                                x: wsStrip2.activeIndex * wsStrip2.pitch + (wsStrip2.slot - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: wsStrip2.here ? app.cBlue : Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.3)
                                visible: wsStrip2.activeIndex >= 0
                                Behavior on x {
                                    NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic }
                                }
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                            }

                            // The dots are made once and kept: the model is just how many
                            // there are, and each dot reads its own details.  (Handing
                            // the list itself to the Repeater destroyed and remade every
                            // dot, icons and all, on each change of window focus.)
                            readonly property var info: app.workspacesFor(app.secondScreen)
                            Repeater {
                                model: wsStrip2.count
                                delegate: Item {
                                    id: ws2
                                    required property int index
                                    readonly property var modelData: wsStrip2.info[index]
                                                                     ?? ({ id: -1, occupied: false, app: "" })
                                    readonly property bool active: modelData.id === app.secondActive
                                    readonly property bool showIcon: modelData.app !== ""
                                    x: index * wsStrip2.pitch
                                    width: wsStrip2.slot
                                    height: wsStrip2.height
                                    HoverHandler {
                                        id: wsHov2
                                        onHoveredChanged: {
                                            if (hovered) app.wsHoverStart(ws2.modelData.id,
                                                ws2.mapToItem(null, ws2.width / 2, 0).x + isl3.scrX, app.secondScreen)
                                            else app.wsHoverEnd(ws2.modelData.id)
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !ws2.showIcon
                                        text: ws2.index + 1 === 10 ? "10" : ws2.index + 1
                                        color: ws2.active && wsStrip2.here ? app.cOnAccent
                                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b,
                                                       ws2.active || wsHov2.hovered ? 0.9 : ws2.modelData.occupied ? 0.65 : 0.3)
                                        font.family: "Inter"
                                        font.weight: ws2.active ? Font.DemiBold : Font.Medium
                                        font.pixelSize: app.fs(11)
                                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    }
                                    // the app on this workspace
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: ws2.showIcon
                                        implicitSize: 15
                                        source: ws2.showIcon ? app.iconFor(ws2.modelData.app) : ""
                                        opacity: ws2.active || wsHov2.hovered ? 1 : 0.8
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            app.wsHoverEnd(ws2.modelData.id)
                                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws2.modelData.id + " })")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- stats, in a second group; click it for the system drawer ----
                    Rectangle {
                        visible: app.barStats || (app.gpuOk && app.barGpu)
                        implicitWidth: statRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b,
                                       isl3.open || stGHov.hovered ? 0.12 : 0.07)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: stGHov }

                        Row {
                            id: statRow
                            anchors.centerIn: parent
                            spacing: 12
                            Stat {
                                app: rootV.app
                                visible: app.barStats
                                icon: "memory"
                                value: app.cpuPct + "%"
                            }
                            Stat {
                                app: rootV.app
                                visible: app.barStats
                                icon: "memory_alt"
                                value: app.memPct + "%"
                            }
                            Stat {
                                app: rootV.app
                                visible: app.gpuOk && app.barGpu
                                icon: "developer_board"
                                value: app.gpuPct + "%"
                            }
                            Stat {
                                app: rootV.app
                                visible: app.gpuOk && app.barGpu
                                icon: "thermostat"
                                value: app.gpuTemp + "\u00b0"
                                widest: "100\u00b0"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.sysShown = !app.sysShown
                        }
                    }
                
                    // ---- plugins' bar items for this side (Settings, Plugins) ----
                    PluginBarItems { app: rootV.app; side: "left" }

                    // ---- the active window: its icon and title ----
                    // Always shown ("Desktop" with nothing focused), so it never
                    // appears and disappears.
                    Rectangle {
                        id: awGroup
                        readonly property var tl: ToplevelManager.activeToplevel
                        readonly property string title: tl ? (tl.title || "") : ""
                        // fits the title, up to maxW, and glides to its new size;
                        // it's last in the row, so nothing else moves
                        readonly property real maxW: 320
                        implicitWidth: Math.min(maxW, 9 + 16 + 7 + awT.implicitWidth + 12)
                        Behavior on implicitWidth { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        clip: true
                        RowLayout {
                            id: awRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 9
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Item {
                                implicitWidth: 16
                                implicitHeight: 16
                                IconImage {
                                    anchors.fill: parent
                                    visible: awGroup.title !== ""
                                    source: awGroup.tl ? app.iconFor(awGroup.tl.appId || "") : ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: awGroup.title === ""
                                    text: "desktop_windows"
                                    color: app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(15)
                                }
                            }
                            Text {
                                id: awT
                                Layout.fillWidth: true
                                text: awGroup.title || "Desktop"
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.8)
                                font.family: "Inter"
                                font.weight: Font.Medium
                                font.pixelSize: app.fs(12)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }
            }

            // ================= the panel =================
            Item {
                id: panel
                // long bar: inside the drawer that grows out of the bar;
                // islands: inside the pill's own shape
                parent: isl3.att ? drawerHost : shape
                x: isl3.att ? isl3.finalX - app.drawerCurX : 0
                y: 0
                width: isl3.openW
                implicitHeight: sCol.implicitHeight + 32
                opacity: isl3.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: sCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    // header
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        opacity: isl3.revealed > 0 ? 1 : 0
                        transform: Translate { y: isl3.revealed > 0 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            spacing: 10
                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: "System"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(15)
                                    font.bold: true
                                }
                                Text {
                                    visible: text !== ""
                                    text: app.uptimeText ? app.uptimeText.replace(/^up /, "Up ") : ""
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 28
                                radius: 14
                                color: shHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                                HoverHandler { id: shHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: "expand_less"
                                    color: shHov.hovered ? app.cFg : app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(16)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.sysShown = false
                                }
                            }
                        }
                    }

                    // graphs
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 10
                        opacity: isl3.revealed > 1 ? 1 : 0
                        transform: Translate { y: isl3.revealed > 1 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        Graph {
                            app: rootV.app
                            title: "CPU"
                            value: app.cpuPct + "%"
                            points: app.cpuHist
                            tint: app.cGreen
                        }
                        Graph {
                            app: rootV.app
                            title: "Memory"
                            value: app.memPct + "%"
                            points: app.memHist
                            tint: app.cPeach
                        }
                        Graph {
                            app: rootV.app
                            visible: app.gpuOk
                            title: "GPU"
                            value: app.gpuPct + "%"
                            points: app.gpuHist
                            tint: app.cMauve
                        }
                        Graph {
                            app: rootV.app
                            visible: app.gpuOk
                            title: "GPU temperature"
                            value: app.gpuTemp + "\u00b0C"
                            points: app.tempHist
                            maxValue: 100
                            tint: app.gpuTemp >= 80 ? app.cRed : app.cTeal
                        }
                    }

                    // the busiest processes
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: procCol.implicitHeight + 24
                        radius: 20
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        opacity: isl3.revealed > 2 ? 1 : 0
                        transform: Translate { y: isl3.revealed > 2 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: procCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: "Busiest processes"
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    font.bold: true
                                }
                                Text {
                                    Layout.preferredWidth: 90
                                    text: "CPU"
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(10)
                                }
                                Text {
                                    Layout.preferredWidth: 90
                                    text: "Memory"
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(10)
                                }
                            }

                            Repeater {
                                // (a plain list: it re-sorts and updates its numbers at every refresh, and
                            // ScriptModel keeps an item's old contents when it moves)
                            model: app.topProcs
                                delegate: RowLayout {
                                    id: pr
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 2
                                        text: pr.modelData.name
                                        color: app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        elide: Text.ElideRight
                                    }
                                    // cpu and memory as small bars with the number
                                    Repeater {
                                        model: [
                                            { v: pr.modelData.cpu, c: "green" },
                                            { v: pr.modelData.mem, c: "peach" }
                                        ]
                                        delegate: RowLayout {
                                            id: cell
                                            required property var modelData
                                            Layout.preferredWidth: 90
                                            spacing: 6
                                            Rectangle {
                                                implicitWidth: 42
                                                implicitHeight: 6
                                                radius: 3
                                                color: app.cSurf
                                                Rectangle {
                                                    width: parent.width * Math.min(1, cell.modelData.v / 100)
                                                    height: parent.height
                                                    radius: 3
                                                    color: cell.modelData.c === "green" ? app.cGreen : app.cPeach
                                                }
                                            }
                                            Text {
                                                text: cell.modelData.v.toFixed(1) + "%"
                                                color: app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(10)
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: app.topProcs.length === 0
                                text: "Reading\u2026"
                                color: app.cFaint
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                            }
                        }
                    }

                    // ---- playtime: this week's games ----
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: playCol.implicitHeight + 24
                        radius: 20
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        opacity: isl3.revealed > 3 ? 1 : 0
                        transform: Translate { y: isl3.revealed > 3 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: playCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8
                            readonly property var games: app.playWeek.slice(0, 5)
                            readonly property real most: games.length ? games[0].week : 1
                            readonly property real total: app.playWeek.reduce((t, g) => t + g.week, 0)

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: "Playtime this week"
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    font.bold: true
                                }
                                Text {
                                    visible: playCol.total > 0
                                    text: app.fmtPlay(playCol.total)
                                    color: app.cFaint
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(10)
                                }
                            }

                            // a game running now: automatic game mode is on
                            Rectangle {
                                visible: app.gameRunning
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 15
                                color: app.cPrimC
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 8
                                    Text {
                                        text: "sports_esports"
                                        color: app.cOnPrimC
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(16)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: app.autoGame ? "Playing now: game mode is on" : "Playing now"
                                        color: app.cOnPrimC
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(11)
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Repeater {
                                model: playCol.games
                                delegate: RowLayout {
                                    id: gRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10
                                    IconImage {
                                        implicitSize: 20
                                        source: gRow.modelData.appId
                                            ? Quickshell.iconPath("steam_icon_" + gRow.modelData.appId, true) || app.iconFor(gRow.modelData.cls)
                                            : app.iconFor(gRow.modelData.cls)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: gRow.modelData.name
                                                color: app.cFg
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(12)
                                                elide: Text.ElideRight
                                                textFormat: Text.PlainText
                                            }
                                            Text {
                                                text: app.fmtPlay(gRow.modelData.week)
                                                color: app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                        }
                                        // this week, against the most played
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 4
                                            radius: 2
                                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                            Rectangle {
                                                width: parent.width * Math.max(0.03, gRow.modelData.week / playCol.most)
                                                height: parent.height
                                                radius: 2
                                                color: app.cBlue
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: !playCol.games.length
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                text: "Games you play show up here. Steam games are recognised by themselves."
                                color: app.cFaint
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                wrapMode: Text.Wrap
                            }

                            // for games from elsewhere (Heroic, Lutris, emulators)
                            Rectangle {
                                Layout.alignment: Qt.AlignLeft
                                implicitWidth: markRow.implicitWidth + 24
                                implicitHeight: 30
                                radius: 15
                                color: markHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.13)
                                                       : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                                HoverHandler { id: markHov }
                                RowLayout {
                                    id: markRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "add"
                                        color: app.cDim
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(15)
                                    }
                                    Text {
                                        text: "Count the last window as a game"
                                        color: app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(11)
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.markGame()
                                }
                            }
                        }
                    }

                    // the full picture
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: isl3.revealed > 3 ? 1 : 0
                        transform: Translate { y: isl3.revealed > 3 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: btT.implicitWidth + 36
                            implicitHeight: 36
                            radius: 18
                            color: btHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.13) : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            HoverHandler { id: btHov }
                            Text {
                                id: btT
                                anchors.centerIn: parent
                                text: "Open btop"
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.sysShown = false
                                    app.run(app.termCmd + " -e sh -c 'command -v btop >/dev/null && exec btop || exec top'")
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- long bar: the drawer's contents ----
        // BarStrip draws the drawer as part of the bar's own outline; this
        // is what goes inside it, clipped to the same growing shape, so it
        // is revealed outward from the section's centre.
        // The drawer's contents live in BarStrip's window, on the same
        // surface as the glass, so glass and contents are drawn together in
        // the same frame.  (Kept in this window, and positioned for it, only
        // until BarStrip has shown up.)
        Item { id: drawerHome; anchors.fill: parent }
        Item {
            id: drawerHost
            // only the main screen's copy: every section exists once per
            // monitor, and a hidden copy moved in too drew its contents a
            // second time, lined up against the other monitor's width
            readonly property bool moved: isl3.att && app.drawerLayer !== null && isl3.visible
            parent: moved ? app.drawerLayer : drawerHome
            onMovedChanged: if (app.debugLog) console.log("drawer: left contents " + (moved ? "moved into" : "left")
                                        + " the bar window, from the copy on " + isl3.modelData.name
                                        + " (main is " + app.mainScreen + ")")
            // Always shown (on the long bar), just clipped to nothing while
            // another drawer, or none, is open: hiding it made Qt throw away
            // its contents' drawing data, and opening rebuilt it all in one
            // frame, which was the stutter at the start of opening.
            readonly property bool active: app.drawerWho === "left" && app.drawerP > 0
            visible: isl3.visible && isl3.att
            x: moved ? app.drawerCurX : app.drawerCurX - isl3.scrX
            y: app.barBottom
            width: active ? app.drawerCurW : 0
            height: active ? app.drawerCurH : 0
            clip: true
        }
    }
    }
}
