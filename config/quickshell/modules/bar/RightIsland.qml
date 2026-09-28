import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "../../lib/models.mjs" as Models
import qs.services
import qs.modules.plugins

// ============================================================
//   RIGHT ISLAND: QUICK SETTINGS
//   The right pill, able to grow.  Clicking the clock or the
//   volume stretches the pill down and to the left, pinned to the
//   right edge, into quick settings: tiles, sliders, outputs,
//   notifications and actions.  Esc or the arrow shrinks it back.
//
//   Settings > Bar > "Clicking the clock" switches back to the
//   separate pill, sidebar and volume popover, which stay as they
//   were.  The tiles and sliders are the sidebar's own components.
//   Lists are Repeaters over plain values or Pipewire.nodes, never
//   live objects copied into JS arrays.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    component Seg: Rectangle {
        id: sg
        property var app
        property bool lit: false
        default property alias content: sgRow.data
        signal clicked(var mouse)
        signal wheeled(var wheel)

        implicitWidth: sgRow.implicitWidth + 14
        implicitHeight: 26
        radius: 13
        color: lit ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
             : sgHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
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

    // a quick-settings tile: a tonal container, filled with the deeper
    // accent when on, its icon in a rounded square of the accent
    component Tile: Rectangle {
        id: tile
        property var app
        property string glyph: ""          // a Material Symbol name
        property string title: ""
        property string sub: ""
        property bool on: false
        property bool chevron: false
        property bool expanded: false      // its list is open
        signal clicked()
        signal chevronClicked()

        Layout.fillWidth: true
        implicitHeight: 58
        radius: 18
        color: on ? app.cPrimC
             : tHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
        Behavior on color { ColorAnimation { duration: app.animQuick } }
        HoverHandler { id: tHov }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: 12
                color: tile.on ? tile.app.cBlue : Qt.rgba(tile.app.cFg.r, tile.app.cFg.g, tile.app.cFg.b, 0.1)
                Behavior on color { ColorAnimation { duration: tile.app.animQuick } }
                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.on ? tile.app.cOnAccent : tile.app.cFg
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: tile.app.fs(19)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    color: tile.on ? tile.app.cOnPrimC : tile.app.cFg
                    font.family: "Inter"
                    font.weight: Font.Medium
                    font.pixelSize: tile.app.fs(13)
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.sub
                    color: tile.on ? Qt.rgba(tile.app.cOnPrimC.r, tile.app.cOnPrimC.g, tile.app.cOnPrimC.b, 0.75)
                                   : tile.app.cDim
                    font.family: "Inter"
                    font.pixelSize: tile.app.fs(11)
                    elide: Text.ElideRight
                }
            }
            // the arrow: its own button, turning to show the list is open
            Rectangle {
                visible: tile.chevron
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: chevHov.hovered ? Qt.rgba(tile.app.cFg.r, tile.app.cFg.g, tile.app.cFg.b, 0.12) : "transparent"
                HoverHandler { id: chevHov }
                Text {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    rotation: tile.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: tile.app.animQuick; easing.type: Easing.OutCubic } }
                    color: tile.on ? tile.app.cOnPrimC : tile.app.cDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: tile.app.fs(18)
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // the arrow's end of the tile opens the list; the rest toggles
            onClicked: m => {
                if (tile.chevron && m.x > width - 44) tile.chevronClicked()
                else tile.clicked()
            }
        }

    }

    // a tonal squircle button; `danger` fills with the error colour on hover
    component RoundBtn: Rectangle {
        id: rb
        property var app
        property string glyph: ""          // a Material Symbol name
        property bool danger: false
        property int size: 44
        signal clicked()

        implicitWidth: size
        implicitHeight: size
        radius: size * 0.36
        color: rbHov.hovered ? (danger ? app.cRed : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.13))
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
        scale: rbMa.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: app.animQuick } }
        Behavior on scale { NumberAnimation { duration: app.animQuick } }
        HoverHandler { id: rbHov }
        Text {
            anchors.centerIn: parent
            text: rb.glyph
            color: rbHov.hovered && rb.danger ? rb.app.cOnAccent : rb.app.cFg
            font.family: "Material Symbols Rounded"
            font.pixelSize: rb.app.fs(20)
        }
        MouseArea {
            id: rbMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    // a thick pill slider for a PipeWire node: the icon sits in the fill
    // (click it to mute), the level at the right
    component VolRow: Item {
        id: vr
        property var app
        property var au: null
        property string glyph: "volume_up"
        property string mutedGlyph: "volume_off"
        property color accent: app.cBlue
        readonly property real v: au?.volume ?? 0
        readonly property bool muted: au?.muted ?? false

        Layout.fillWidth: true
        implicitHeight: 34

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.08)
        }
        Rectangle {
            id: vrFill
            height: parent.height
            width: Math.max(height, parent.width * Math.min(1, vr.v))
            radius: height / 2
            color: vr.muted ? Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.22) : vr.accent
            Behavior on color { ColorAnimation { duration: vr.app.animQuick } }
        }
        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: vr.muted ? vr.mutedGlyph : vr.glyph
            color: vr.muted ? vr.app.cFg : vr.app.cOnAccent
            font.family: "Material Symbols Rounded"
            font.pixelSize: vr.app.fs(17)
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: vr.muted ? "Muted" : Math.round(vr.v * 100) + "%"
            color: vr.app.cDim
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: vr.app.fs(11)
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            property bool onIcon: false
            function set(x) {
                if (!vr.au) return
                vr.au.volume = Math.max(0, Math.min(1, x / width))
                if (vr.au.muted) vr.au.muted = false
            }
            onPressed: m => {
                onIcon = m.x < 38
                if (!onIcon) set(m.x)
            }
            onPositionChanged: m => { if (pressed && !onIcon) set(m.x) }
            onReleased: m => { if (onIcon && m.x < 38 && vr.au) vr.au.muted = !vr.au.muted }
            onWheel: w => {
                if (!vr.au) return
                vr.au.volume = Math.max(0, Math.min(1, vr.au.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
            }
        }
    }

    // brightness for both monitors together, through DDC/CI, as the same
    // thick pill
    component BrightRow: Item {
        id: br
        property var app
        readonly property real v: app.brightAvg / 100

        Layout.fillWidth: true
        implicitHeight: 34

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(br.app.cFg.r, br.app.cFg.g, br.app.cFg.b, 0.08)
        }
        Rectangle {
            height: parent.height
            width: Math.max(height, parent.width * br.v)
            radius: height / 2
            color: br.app.cYellow
        }
        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "light_mode"
            color: br.app.cOnAccent
            font.family: "Material Symbols Rounded"
            font.pixelSize: br.app.fs(17)
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: br.app.brightAvg + "%"
            color: br.app.cDim
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: br.app.fs(11)
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function set(x) { br.app.setAllBright(100 * Math.max(0, Math.min(1, x / width))) }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x) }
            onWheel: w => br.app.setAllBright(br.app.brightAvg + (w.angleDelta.y > 0 ? 5 : -5))
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
        id: isr
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.rightMorph
        // ---- where this section's drawer goes, for the long bar ----
        // this window's left edge on screen, the section's centre, and the
        // drawer's final left edge: centred under the section, but kept
        // clear of the bar's rounded ends
        readonly property real scrX: modelData.width - isr.width
        readonly property real secCX: scrX + shape.x + shape.width / 2
        // the right drawer runs flush down the bar's right end
        readonly property real finalX: modelData.width - app.gap - openW
        Binding {
            target: app
            property: "rightGeom"
            // Whichever copy is in charge writes; one that stops being in
            // charge must not put back the value from before it started.
            // (At startup the other monitor's copy is briefly in charge,
            // and restoring its stale values doubled the drawers.)
            restoreMode: Binding.RestoreNone
            when: isr.visible && isr.att
            value: ({ x: isr.finalX, w: isr.openW, h: isr.openH, cx: isr.secCX, secW: shape.width,
                      flush: "right" })
        }

        readonly property bool open: app.quickShown
        // the Wi-Fi or Bluetooth list open inside the drawer, if any
        property string picker: ""
        // notification groups that are expanded, by app name
        property var openGroups: ({})
        function toggleGroup(name) {
            const g = Object.assign({}, openGroups)
            g[name] = !g[name]
            openGroups = g
        }
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource

        readonly property real pillW: rightRow.implicitWidth + 12
        readonly property real openW: 500
        readonly property real openH: panel.implicitHeight

        // extra room to the left and below, for the open panel's shadow
        readonly property int shadowRoom: 36
        // attached: flush with the top-right corner, the section inset
        // far enough for the drawer's curved corner to fit beside it
        readonly property bool att: app.barAttached
        anchors { top: true; right: true }
        margins { top: att ? 0 : app.gap; right: att ? 0 : app.gap }
        implicitWidth: openW + shadowRoom + 16
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

        // Every audio device and app stream (for the outputs list) is only
        // watched once the drawer has finished opening: picking them all up
        // at once was part of the stutter.
        property bool settled: false
        Timer {
            id: settleT
            interval: Math.round(app.animSlow * 1.3) + 40
            onTriggered: isr.settled = true
        }
        PwObjectTracker {
            objects: isr.open && isr.settled ? Pipewire.nodes.values
                              : [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
        }

        // Sections arrive one after another once the shape has mostly
        // grown: `revealed` counts how many are in.  Closing drops them
        // all together.  With animations off, everything is in at once.
        readonly property int sections: 7
        property int revealed: 0
        Timer {
            id: revealStart
            interval: Math.round(app.animSlow * 0.45)
            onTriggered: { isr.revealed = 1; revealStep.start() }
        }
        Timer {
            id: revealStep
            interval: app.dur(45)
            repeat: true
            onTriggered: {
                isr.revealed += 1
                if (isr.revealed >= isr.sections) stop()
            }
        }
        onOpenChanged: {
            revealStep.stop()
            revealStart.stop()
            if (open) {
                keys.forceActiveFocus()
                settleT.restart()
                if (app.motionOn) { revealed = 0; revealStart.start() }
                else revealed = sections
            } else {
                revealed = 0
                picker = ""
                app.wifiCancelPw()
                settleT.stop()
                settled = false
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: app.quickShown = false
        }

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
            id: shape
            anchors.right: parent.right
            anchors.rightMargin: isr.att ? app.gap + 10 : 0
            y: isr.att ? app.barTop : 0
            width: isr.open && !isr.att ? isr.openW : isr.pillW
            height: isr.att ? app.barH : (isr.open ? isr.openH : app.pillH)
            // attached: square along the top (it's part of the bar),
            // rounded at the bottom once it's a drawer
            radius: isr.att ? app.barH / 2 : (isr.open ? 28 : app.pillH / 2)
            // edgeless glass while it's a pill; hovering brightens it a
            // touch.  The hairline edge returns once it opens into a panel.
            color: isr.att
                   ? "transparent"
                   : (isr.open ? app.cCard
                      : shapeHov.hovered ? Qt.tint(app.cBg, Qt.rgba(1, 1, 1, 0.07)) : app.cBg)
            border.width: !isr.att && isr.open ? 1 : 0
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
            scale: !isr.att && !isr.open && shapeHov.hovered ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
            HoverHandler { id: shapeHov }
            clip: true

            // a soft shadow so the open panel floats; only while it's
            // bigger than the pill, so the closed pill is unchanged
            // depth only for the open panel: the pill stays flat glass
            layer.enabled: !isr.att && (isr.open || height > app.pillH + 2)
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 1.0
                shadowVerticalOffset: 10
                shadowHorizontalOffset: 0
            }

            // a faint glow of the accent along the top edge.  Rounded like
            // the panel: its clip only cuts square, so a square glow would
            // show over the rounded corners.
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
                opacity: isr.open && !isr.att ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.16) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            Behavior on width { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: app.animNormal } }

            // a thin line of light along the top edge of the glass, the
            // upper half of a pill-shaped hairline
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: app.pillH / 2
                clip: true
                opacity: isr.open || isr.att ? 0 : 1
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
                anchors.right: parent.right
                anchors.top: parent.top
                width: isr.pillW
                height: isr.att ? app.barH : app.pillH
                opacity: isr.att || !isr.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

                RowLayout {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 6

                    // plugins' bar items for this side (Settings, Plugins)
                    PluginBarItems { app: rootV.app; side: "right" }

                    // a running timer (or stopwatch), so it's visible without opening anything
                    Rectangle {
                        visible: app.timerOn || app.swOn
                        implicitWidth: tcRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: 14
                        color: app.timerOn && !app.timerPaused && app.timerLeft <= 10 ? app.cRed : app.cPrimC
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        Row {
                            id: tcRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: app.timerOn ? (app.timerPaused ? "pause_circle" : "hourglass_top") : "timer"
                                color: app.timerOn && app.timerLeft <= 10 && !app.timerPaused ? app.cOnAccent : app.cOnPrimC
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(15)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: app.timerOn ? app.fmtDur(app.timerPaused ? app.timerHeld : app.timerLeft)
                                                  : app.fmtDur(app.swMs / 1000)
                                color: app.timerOn && app.timerLeft <= 10 && !app.timerPaused ? app.cOnAccent : app.cOnPrimC
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(12)
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.quickShown = !app.quickShown
                        }
                    }

                    // status icons and the tray, in one tonal group
                    Rectangle {
                        implicitWidth: statusRow.implicitWidth + 8
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        RowLayout {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 0
                            // ---- volume: its icon; hover slides the level out ----
                            Seg {
                                id: volSeg
                                app: rootV.app
                                readonly property bool muted: isr.sink?.audio?.muted ?? false
                                readonly property int vol: Math.round((isr.sink?.audio?.volume ?? 0) * 100)
                                lit: false
                                onClicked: m => {
                                    const a = isr.sink?.audio
                                    if (m.button === Qt.RightButton) { if (a) a.muted = !a.muted }
                                    else app.quickShown = !app.quickShown
                                }
                                onWheeled: w => {
                                    const a = isr.sink?.audio
                                    if (!a) return
                                    a.volume = Math.max(0, Math.min(1, a.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: volSeg.muted ? "volume_off"
                                        : volSeg.vol === 0 ? "volume_mute"
                                        : volSeg.vol < 50 ? "volume_down" : "volume_up"
                                    color: volSeg.muted ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                                        : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.85)
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(17)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: volHov.hovered ? implicitWidth : 0
                                    clip: true
                                    opacity: volHov.hovered ? 1 : 0
                                    Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: app.animQuick } }
                                    text: volSeg.muted ? "Muted" : volSeg.vol + "%"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                                HoverHandler { id: volHov }
                            }

                            // ---- network: its icon; hover slides the speeds out ----
                            Seg {
                                id: netSeg
                                app: rootV.app
                                visible: app.barNet
                                lit: false
                                onClicked: app.quickShown = !app.quickShown
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: app.netKind === "wifi" ? "wifi"
                                        : app.netKind === "ethernet" ? "lan" : "wifi_off"
                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, app.netKind !== "" ? 0.85 : 0.4)
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(17)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: netHov.hovered ? implicitWidth : 0
                                    clip: true
                                    opacity: netHov.hovered ? 1 : 0
                                    Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: app.animQuick } }
                                    text: "\u2193 " + app.netDown + "   \u2191 " + app.netUp
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                                HoverHandler { id: netHov }
                            }

                            // ---- the game overlay (Settings, Game overlay): shows or hides
                            // the frame rate, in a game too (MangoHud rereads its config
                            // as soon as it changes); right-click: its settings ----
                            Seg {
                                app: rootV.app
                                visible: app.gameHud !== "off"
                                lit: app.cfg.gameHudHidden !== true
                                onClicked: m => {
                                    if (m.button === Qt.RightButton) { app.settingsPage = 25; app.settingsShown = true }
                                    else app.setting("gameHudHidden", app.cfg.gameHudHidden !== true)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "speed"
                                    color: app.cfg.gameHudHidden !== true ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.55)
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(17)
                                }
                            }

                            // ---- notifications: a bell, with a dot when there are some ----
                            Seg {
                                app: rootV.app
                                lit: false
                                onClicked: app.quickShown = !app.quickShown
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: bell.implicitWidth
                                    height: bell.implicitHeight
                                    Text {
                                        id: bell
                                        text: app.dnd ? "notifications_off" : "notifications"
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.85)
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(17)
                                    }
                                    Rectangle {
                                        visible: app.notifUnseen > 0
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: 1
                                        anchors.topMargin: 1
                                        width: 7; height: 7; radius: 3.5
                                        color: app.cBlue
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
                                        color: trHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
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
                                                    it.display(isr, Math.round(p.x), Math.round(p.y))
                                                } else {
                                                    it.secondaryActivate()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // the date and time, in a group filled with the deeper accent
                    Rectangle {
                        implicitWidth: clockRow.implicitWidth + 4
                        implicitHeight: 28
                        radius: 14
                        color: app.cPrimC
                        RowLayout {
                            id: clockRow
                            anchors.centerIn: parent
                            // ---- date and time: opens quick settings ----
                            Seg {
                                app: rootV.app
                                lit: false
                                onClicked: app.quickShown = !app.quickShown
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: app.cfg.clockDate !== false
                                    text: Qt.formatDateTime(app.now, "ddd d")
                                    color: Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.7)
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: app.cfg.clock24h === true
                                          ? Qt.formatDateTime(app.now, "HH:mm" + (app.cfg.clockSeconds === true ? ":ss" : ""))
                                          : Qt.formatDateTime(app.now, "h:mm" + (app.cfg.clockSeconds === true ? ":ss" : "") + " AP")
                                    color: app.cOnPrimC
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                            }
                        }
                    }

                    // ---- the menu button: opens quick settings ----
                    // Clicking the clock does too, but nothing about a clock
                    // says so; a menu button does.  It turns into a close
                    // button while the menu is open.
                    Rectangle {
                        id: menuBtn
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: app.quickShown ? app.cPrimC
                             : menuHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: menuHov }
                        Text {
                            anchors.centerIn: parent
                            text: app.quickShown ? "close" : "menu"
                            color: app.quickShown ? app.cOnPrimC : app.cFg
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(18)
                            rotation: app.quickShown ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.quickShown = !app.quickShown
                        }
                    }
                }
            }

            // ================= the panel =================
            Item {
                id: panel
                // long bar: inside the drawer that grows out of the bar;
                // islands: inside the pill's own shape
                parent: isr.att ? drawerHost : shape
                x: isr.att ? isr.finalX - app.drawerCurX : shape.width - isr.openW
                y: 0
                width: isr.openW
                implicitHeight: qCol.implicitHeight + 32
                opacity: isr.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: qCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    // header: the time, and the arrow that shrinks it back
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        opacity: isr.revealed > 0 ? 1 : 0
                        transform: Translate { y: isr.revealed > 0 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            spacing: 10
                            Row {
                                spacing: 6
                                Text {
                                    id: qTime
                                    text: app.cfg.clock24h === true
                                          ? Qt.formatDateTime(app.now, "HH:mm")
                                          : Qt.formatDateTime(app.now, "h:mm AP").split(" ")[0]
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(28)
                                    font.weight: Font.Light
                                }
                                Text {
                                    visible: app.cfg.clock24h !== true
                                    anchors.baseline: qTime.baseline
                                    text: Qt.formatDateTime(app.now, "AP")
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Qt.formatDateTime(app.now, "dddd, d MMMM")
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 28
                                radius: 14
                                color: qcHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                                HoverHandler { id: qcHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: "expand_less"
                                    color: qcHov.hovered ? app.cFg : app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(16)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.quickShown = false
                                }
                            }
                        }
                    }

                    // ---- the weather and this month, side by side ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        opacity: isr.revealed > 1 ? 1 : 0
                        transform: Translate { y: isr.revealed > 1 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        // the weather, as tall as the calendar beside it
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            implicitHeight: 96
                            radius: 22
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 2
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: app.wxOk ? app.wxSymbol(app.wxCond, app.wxDay) : "cloud_off"
                                    color: !app.wxOk ? app.cDim
                                         : /sunny|partly_cloudy_day/.test(text) ? app.cYellow : app.cBlue
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(40)
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 4
                                    text: app.wxOk ? app.wxTemp : "\u2014"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(26)
                                    font.weight: Font.Light
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: app.wxOk ? app.wxCond
                                          : (app.wxHasPlace ? "No weather yet" : "Set a location in Settings")
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: app.wxOk && app.wxHi !== ""
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "H " + app.wxHi + "   L " + app.wxLo
                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.5)
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(11)
                                }
                            }
                        }

                        Rectangle {
                            id: cal
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1.4
                            implicitHeight: calCol.implicitHeight + 28
                            radius: 22
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)

                            readonly property var cells: {
                                const n = app.now
                                const y = n.getFullYear(), mo = n.getMonth()
                                const lead = (new Date(y, mo, 1).getDay() - app.calWeekStart + 7) % 7
                                const days = new Date(y, mo + 1, 0).getDate()
                                const pad = v => (v < 10 ? "0" : "") + v
                                const out = []
                                for (let i = 0; i < lead; i++) out.push({ d: "", key: "" })
                                for (let d = 1; d <= days; d++) {
                                    const key = y + "-" + pad(mo + 1) + "-" + pad(d)
                                    out.push({ d: d, key: key, today: d === n.getDate(),
                                               hol: app.holidayOn(key) !== "" })
                                }
                                return out
                            }

                            ColumnLayout {
                                id: calCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 6
                                Text {
                                    text: Qt.formatDateTime(app.now, "dddd, d MMMM")
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    font.bold: true
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 7
                                    rowSpacing: 2
                                    columnSpacing: 2
                                    Repeater {
                                        model: 7
                                        delegate: Text {
                                            required property int index
                                            readonly property int dow: (index + app.calWeekStart) % 7
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: ["S", "M", "T", "W", "T", "F", "S"][dow]
                                            color: (dow === 0 || dow === 6) ? app.cPeach : app.cDim
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(10)
                                            font.bold: true
                                        }
                                    }
                                    Repeater {
                                        model: cal.cells
                                        delegate: Rectangle {
                                            id: dc
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            radius: 13
                                            color: modelData.today ? app.cBlue
                                                 : modelData.hol ? Qt.rgba(app.cPeach.r, app.cPeach.g, app.cPeach.b, 0.18)
                                                 : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: dc.modelData.d
                                                color: dc.modelData.today ? app.cOnAccent
                                                     : dc.modelData.hol ? app.cPeach : app.cFg
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                                font.bold: dc.modelData.today === true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- the next twelve hours; scroll sideways for more ----
                    Rectangle {
                        Layout.fillWidth: true
                        visible: app.wxOk && app.wxHours.length > 0
                        implicitHeight: 104
                        radius: 18
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        opacity: isr.revealed > 1 ? 1 : 0
                        transform: Translate { y: isr.revealed > 1 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        Flickable {
                            id: hoursFlick
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            contentWidth: hoursRow.width
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            // the mouse wheel scrolls it sideways
                            WheelHandler {
                                onWheel: e => {
                                    const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x
                                    hoursFlick.contentX = Math.max(0, Math.min(
                                        hoursFlick.contentWidth - hoursFlick.width, hoursFlick.contentX - d))
                                }
                            }
                            Row {
                                id: hoursRow
                                height: parent.height
                                Repeater {
                                    model: app.wxHours
                                    delegate: Item {
                                        id: hr
                                        required property var modelData
                                        required property int index
                                        width: 58
                                        height: hoursRow.height
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: hr.modelData.time
                                                color: hr.index === 0 ? app.cFg : app.cDim
                                                font.family: "Inter"
                                                font.weight: hr.index === 0 ? Font.DemiBold : Font.Normal
                                                font.pixelSize: app.fs(11)
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                readonly property string sym: app.wxSymbol(hr.modelData.cond, hr.modelData.day)
                                                text: sym
                                                color: /sunny|partly_cloudy_day/.test(sym) ? app.cYellow
                                                     : /rainy|thunder|snowy/.test(sym) ? app.cBlue
                                                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.8)
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(22)
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: hr.modelData.temp
                                                color: app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.Medium
                                                font.pixelSize: app.fs(13)
                                            }
                                            // the chance of rain, when it's worth mentioning
                                            Row {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                spacing: 1
                                                opacity: hr.modelData.rain >= 20 ? 1 : 0
                                                Text {
                                                    text: "water_drop"
                                                    color: app.cBlue
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: app.fs(11)
                                                }
                                                Text {
                                                    text: hr.modelData.rain + "%"
                                                    color: app.cBlue
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

                    // ---- timer and stopwatch ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        opacity: isr.revealed > 1 ? 1 : 0
                        transform: Translate { y: isr.revealed > 1 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        // the timer: presets to start; a ring, pause and cancel while it runs
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 96
                            radius: 18
                            color: app.timerOn ? app.cPrimC : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            Behavior on color { ColorAnimation { duration: app.animQuick } }

                            // not running: a title and presets
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                visible: !app.timerOn
                                spacing: 8
                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: "hourglass_top"
                                        color: app.cFg
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(16)
                                    }
                                    Text {
                                        text: "Timer"
                                        color: app.cFg
                                        font.family: "Inter"
                                        font.weight: Font.DemiBold
                                        font.pixelSize: app.fs(12)
                                    }
                                }
                                Row {
                                    spacing: 4
                                    Repeater {
                                        model: [1, 5, 10, 25]
                                        delegate: Rectangle {
                                            id: pre
                                            required property var modelData
                                            width: 42
                                            height: 30
                                            radius: 12
                                            color: preHov.hovered ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                                            HoverHandler { id: preHov }
                                            Text {
                                                anchors.centerIn: parent
                                                text: pre.modelData + "m"
                                                color: preHov.hovered ? app.cOnAccent : app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.Medium
                                                font.pixelSize: app.fs(12)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.startTimer(pre.modelData * 60)
                                            }
                                        }
                                    }
                                }
                            }

                            // running: a ring with the time left, pause and cancel
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                visible: app.timerOn
                                spacing: 10
                                Item {
                                    implicitWidth: 64
                                    implicitHeight: 64
                                    Canvas {
                                        id: tRing
                                        anchors.fill: parent
                                        readonly property real f: app.timerTotal > 0
                                            ? (app.timerPaused ? app.timerHeld : app.timerLeft) / app.timerTotal : 0
                                        onFChanged: requestPaint()
                                        onPaint: {
                                            const ctx = getContext("2d")
                                            ctx.reset()
                                            const c = app.cOnPrimC, a = app.cBlue
                                            ctx.lineWidth = 5
                                            ctx.lineCap = "round"
                                            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.18)
                                            ctx.beginPath()
                                            ctx.arc(32, 32, 27, 0, 2 * Math.PI)
                                            ctx.stroke()
                                            if (f > 0) {
                                                ctx.strokeStyle = a
                                                ctx.beginPath()
                                                ctx.arc(32, 32, 27, -Math.PI / 2, -Math.PI / 2 + f * 2 * Math.PI)
                                                ctx.stroke()
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: app.fmtDur(app.timerPaused ? app.timerHeld : app.timerLeft)
                                        color: app.cOnPrimC
                                        font.family: "Inter"
                                        font.weight: Font.DemiBold
                                        font.pixelSize: app.fs(app.timerLeft >= 600 || app.timerHeld >= 600 ? 12 : 13)
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Column {
                                    spacing: 6
                                    RoundBtn {
                                        app: rootV.app
                                        size: 32
                                        glyph: app.timerPaused ? "play_arrow" : "pause"
                                        onClicked: app.timerPaused ? app.resumeTimer() : app.pauseTimer()
                                    }
                                    RoundBtn {
                                        app: rootV.app
                                        size: 32
                                        glyph: "close"
                                        danger: true
                                        onClicked: app.cancelTimer()
                                    }
                                }
                            }
                        }

                        // the stopwatch: the time, start or pause, reset
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 96
                            radius: 18
                            color: app.swRunning ? app.cPrimC : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6
                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: "timer"
                                        color: app.swRunning ? app.cOnPrimC : app.cFg
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(16)
                                    }
                                    Text {
                                        text: "Stopwatch"
                                        color: app.swRunning ? app.cOnPrimC : app.cFg
                                        font.family: "Inter"
                                        font.weight: Font.DemiBold
                                        font.pixelSize: app.fs(12)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        // tenths of a second while it runs
                                        text: app.fmtDur(app.swMs / 1000) + "." + Math.floor((app.swMs % 1000) / 100)
                                        color: app.swRunning ? app.cOnPrimC : app.swOn ? app.cFg : app.cDim
                                        font.family: "Inter"
                                        font.weight: Font.Medium
                                        font.pixelSize: app.fs(20)
                                        font.features: ({ "tnum": 1 })
                                    }
                                    RoundBtn {
                                        app: rootV.app
                                        size: 32
                                        visible: app.swOn && !app.swRunning
                                        glyph: "restart_alt"
                                        onClicked: app.swReset()
                                    }
                                    Rectangle {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        radius: 12
                                        color: app.cBlue
                                        Text {
                                            anchors.centerIn: parent
                                            text: app.swRunning ? "pause" : "play_arrow"
                                            color: app.cOnAccent
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(18)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: app.swToggle()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- mini player, while something plays ----
                    Rectangle {
                        id: mini
                        readonly property var p: app.player
                        Layout.fillWidth: true
                        visible: p !== null
                        implicitHeight: 64
                        radius: 18
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                        opacity: isr.revealed > 1 ? 1 : 0
                        transform: Translate { y: isr.revealed > 1 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            // the cover and title open the full media panel
                            Item {
                                implicitWidth: 44
                                implicitHeight: 44
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: app.cCard
                                    Text {
                                        anchors.centerIn: parent
                                        visible: miniArt.status !== Image.Ready
                                        text: "music_note"
                                        color: app.cFaint
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(18)
                                    }
                                }
                                Image {
                                    id: miniArt
                                    anchors.fill: parent
                                    // shown at 44 px
                                    sourceSize.width: 128
                                    sourceSize.height: 128
                                    source: mini.p?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: false
                                }
                                Item {
                                    id: miniMask
                                    anchors.fill: parent
                                    layer.enabled: true
                                    visible: false
                                    Rectangle { anchors.fill: parent; radius: 12; color: "black" }
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: miniArt
                                    maskEnabled: true
                                    maskSource: miniMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                    visible: miniArt.status === Image.Ready
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: mini.p?.trackTitle || "Unknown track"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: mini.p?.trackArtist ?? ""
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    elide: Text.ElideRight
                                }
                            }
                            Repeater {
                                model: [
                                    { g: "skip_previous", a: "prev" },
                                    { g: "",          a: "play" },
                                    { g: "skip_next", a: "next" }
                                ]
                                delegate: Rectangle {
                                    id: mBtn
                                    required property var modelData
                                    readonly property bool isPlay: modelData.a === "play"
                                    implicitWidth: isPlay ? 38 : 30
                                    implicitHeight: implicitWidth
                                    radius: implicitWidth / 2
                                    color: isPlay ? app.mBlue : mbHov.hovered ? app.cCard : "transparent"
                                    HoverHandler { id: mbHov }
                                    Text {
                                        anchors.centerIn: parent
                                        text: mBtn.isPlay
                                            ? (mini.p?.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow")
                                            : mBtn.modelData.g
                                        color: mBtn.isPlay ? app.mOnAccent : app.cFg
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(mBtn.isPlay ? 17 : 14)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = mini.p
                                            if (!p) return
                                            if (mBtn.modelData.a === "prev") p.previous()
                                            else if (mBtn.modelData.a === "next") p.next()
                                            else if (p.canTogglePlaying) p.togglePlaying()
                                        }
                                    }
                                }
                            }
                        }
                        // everything left of the buttons opens the media panel
                        MouseArea {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width - 130
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { app.quickShown = false; app.cardShown = true }
                        }
                    }

                    // ---- tiles ----
                    GridLayout {
                        Layout.fillWidth: true
                        opacity: isr.revealed > 2 ? 1 : 0
                        transform: Translate { y: isr.revealed > 2 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        Tile {
                            app: rootV.app
                            readonly property bool isMuted: isr.sink?.audio?.muted ?? false
                            glyph: isMuted ? "volume_off" : "volume_up"
                            title: "Sound"
                            sub: isMuted ? "Muted" : Math.round((isr.sink?.audio?.volume ?? 0) * 100) + "%"
                            on: !isMuted
                            onClicked: { const a = isr.sink?.audio; if (a) a.muted = !a.muted }
                        }
                        Tile {
                            app: rootV.app
                            readonly property bool isMuted: isr.source?.audio?.muted ?? false
                            glyph: isMuted ? "mic_off" : "mic"
                            title: "Microphone"
                            sub: isMuted ? "Muted" : "On"
                            on: !isMuted
                            onClicked: { const a = isr.source?.audio; if (a) a.muted = !a.muted }
                        }
                        // Wi-Fi when there's an adapter; otherwise the wired connection
                        Tile {
                            app: rootV.app
                            readonly property var joined: app.wifiList.find(n => n.active)
                            glyph: app.wifiHas ? (app.wifiOn ? "wifi" : "wifi_off")
                                 : app.netKind === "ethernet" ? "lan" : "wifi_off"
                            title: app.wifiHas ? "Wi-Fi" : app.netKind === "ethernet" ? "Wired" : "Network"
                            sub: app.wifiHas ? (!app.wifiOn ? "Off" : joined ? joined.ssid : "Not connected")
                                 : app.netName !== "" ? app.netName : "Not connected"
                            on: app.wifiHas ? app.wifiOn : app.netKind !== ""
                            chevron: app.wifiHas
                            expanded: isr.picker === "wifi"
                            onClicked: if (app.wifiHas) app.wifiToggle()
                            onChevronClicked: {
                                isr.picker = isr.picker === "wifi" ? "" : "wifi"
                                if (isr.picker === "wifi") app.refreshWifi(true)
                            }
                        }
                        // Bluetooth, always in its place: no adapter, its service
                        // off (tap to start it), or the usual on/off and devices
                        Tile {
                            app: rootV.app
                            readonly property var linked: app.btList.find(d => d.connected)
                            // "none": no adapter; "stopped": the service isn't running
                            readonly property string btState: !BluetoothService.adapter ? "none"
                                                          : !BluetoothService.active && !app.btHas ? "stopped" : "ready"
                            opacity: btState === "none" ? 0.45 : 1
                            glyph: btState !== "ready" || !app.btOn ? "bluetooth_disabled"
                                 : linked ? "bluetooth_connected" : "bluetooth"
                            title: "Bluetooth"
                            sub: btState === "none" ? "No adapter found"
                               : btState === "stopped" ? (BluetoothService.starting ? "Starting\u2026"
                                                        : BluetoothService.error !== "" ? BluetoothService.error
                                                        : "Service off, tap to start")
                               : !app.btOn ? "Off"
                               : linked ? linked.name + ((linked.battery ?? -1) >= 0 ? ", " + linked.battery + "%" : "") : "On"
                            on: btState === "ready" && app.btOn
                            chevron: btState === "ready"
                            expanded: isr.picker === "bt"
                            onClicked: {
                                if (btState === "stopped") BluetoothService.start()
                                else if (btState === "ready") app.btToggle()
                            }
                            onChevronClicked: {
                                isr.picker = isr.picker === "bt" ? "" : "bt"
                                if (isr.picker === "bt") { app.refreshBt(); if (app.btOn) app.btScan() }
                            }
                        }
                        Tile {
                            app: rootV.app
                            glyph: "dark_mode"
                            title: "Night light"
                            sub: app.nightLight ? "Warmer colours" : "Off"
                            on: app.nightLight
                            onClicked: app.toggleNight()
                        }
                        Tile {
                            app: rootV.app
                            glyph: "sports_esports"
                            title: "Game mode"
                            sub: app.gameMode ? "Blur and animations off" : "Off"
                            on: app.gameMode
                            onClicked: app.toggleGameMode()
                        }
                        Tile {
                            app: rootV.app
                            glyph: "coffee"
                            title: "Keep awake"
                            sub: app.keepAwake ? "Won't lock or sleep" : "Off"
                            on: app.keepAwake
                            onClicked: app.keepAwake = !app.keepAwake
                        }
                        Tile {
                            app: rootV.app
                            glyph: app.dnd ? "notifications_off" : "notifications"
                            title: "Do not disturb"
                            sub: app.dnd ? "Popups hidden" : "Off"
                            on: app.dnd
                            onClicked: app.dnd = !app.dnd
                        }
                    }

                    // ---- the Wi-Fi or Bluetooth list, opened from a tile's arrow ----
                    Rectangle {
                        id: pickerBox
                        Layout.fillWidth: true
                        readonly property bool shown: isr.picker !== ""
                        readonly property bool wifi: isr.picker === "wifi"
                        implicitHeight: shown ? pickCol.implicitHeight + 24 : 0
                        Behavior on implicitHeight { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        visible: implicitHeight > 0.5
                        opacity: shown ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: app.animQuick } }
                        clip: true
                        radius: 18
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.05)

                        ColumnLayout {
                            id: pickCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.bottomMargin: 4
                                spacing: 8
                                Text {
                                    text: pickerBox.wifi ? "Wi-Fi networks" : "Bluetooth devices"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: app.fs(13)
                                }
                                Text {
                                    visible: !pickerBox.wifi && app.btScanning
                                    text: "Searching\u2026"
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                }
                                Item { Layout.fillWidth: true }
                                RoundBtn {
                                    app: rootV.app
                                    size: 30
                                    glyph: "refresh"
                                    onClicked: pickerBox.wifi ? app.refreshWifi(true) : app.btScan()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                visible: pickerBox.wifi ? !app.wifiOn : !app.btOn
                                text: pickerBox.wifi ? "Wi-Fi is off. Click the tile to turn it on."
                                                     : "Bluetooth is off. Click the tile to turn it on."
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                visible: pickerBox.wifi && app.wifiError !== ""
                                text: app.wifiError
                                color: app.cRed
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                visible: (pickerBox.wifi ? app.wifiOn && app.wifiList.length === 0
                                                         : app.btOn && app.btList.length === 0)
                                text: pickerBox.wifi ? "No networks found yet" : "No devices yet. Put yours in pairing mode."
                                color: app.cFaint
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                            }

                            Repeater {
                                model: !pickerBox.shown ? []
                                     : pickerBox.wifi ? (app.wifiOn ? app.wifiList.slice(0, 10) : [])
                                     : (app.btOn ? app.btList.slice(0, 10) : [])
                                delegate: ColumnLayout {
                                    id: pr
                                    required property var modelData
                                    readonly property bool isWifi: pickerBox.wifi
                                    readonly property bool linked: isWifi ? modelData.active : modelData.connected
                                    readonly property bool busy: isWifi ? app.wifiBusy === modelData.ssid
                                                                        : app.btBusy === modelData.mac
                                    readonly property bool asking: isWifi && app.wifiAskPw === modelData.ssid
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 44
                                        radius: 14
                                        color: pr.linked ? app.cPrimC
                                             : prHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08) : "transparent"
                                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                                        HoverHandler { id: prHov }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10
                                            Text {
                                                text: pr.isWifi
                                                    ? (pr.modelData.signal > 66 ? "network_wifi"
                                                       : pr.modelData.signal > 33 ? "network_wifi_2_bar" : "network_wifi_1_bar")
                                                    : (/head|bud|pods|ear|audio|speaker/i.test(pr.modelData.name) ? "headphones"
                                                       : /controller|pad|xbox|dualsense|dualshock/i.test(pr.modelData.name) ? "sports_esports"
                                                       : /mouse/i.test(pr.modelData.name) ? "mouse"
                                                       : /keyboard/i.test(pr.modelData.name) ? "keyboard" : "bluetooth")
                                                color: pr.linked ? app.cOnPrimC : app.cFg
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(18)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: pr.isWifi ? pr.modelData.ssid : pr.modelData.name
                                                color: pr.linked ? app.cOnPrimC : app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.Medium
                                                font.pixelSize: app.fs(12)
                                                elide: Text.ElideRight
                                                textFormat: Text.PlainText
                                            }
                                            Text {
                                                // battery, for devices that report it (headphones, controllers)
                                                readonly property string batt: !pr.isWifi && (pr.modelData.battery ?? -1) >= 0
                                                                               ? pr.modelData.battery + "%" : ""
                                                text: pr.busy ? "Connecting\u2026"
                                                    : pr.linked ? "Connected" + (batt ? ", " + batt : "")
                                                    : !pr.isWifi && pr.modelData.paired ? "Paired" : ""
                                                visible: text !== ""
                                                color: pr.linked ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.75)
                                                                 : app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                            Text {
                                                visible: pr.isWifi && pr.modelData.secure
                                                text: "lock"
                                                color: pr.linked ? app.cOnPrimC : app.cDim
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(14)
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (pr.busy) return
                                                const d = pr.modelData
                                                if (pr.isWifi) {
                                                    if (d.active) app.wifiDisconnect(d.ssid)
                                                    else app.wifiConnect(d.ssid, "")
                                                } else {
                                                    if (d.connected) app.btDisconnect(d.mac)
                                                    else app.btConnect(d.mac, d.paired)
                                                }
                                            }
                                        }
                                    }

                                    // a network that needs a password asks for it right here
                                    Rectangle {
                                        Layout.fillWidth: true
                                        visible: pr.asking
                                        implicitHeight: 42
                                        radius: 14
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                        onVisibleChanged: if (visible) pw.forceActiveFocus()
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 5
                                            spacing: 8
                                            Text {
                                                text: "key"
                                                color: app.cDim
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(16)
                                            }
                                            TextInput {
                                                id: pw
                                                Layout.fillWidth: true
                                                echoMode: TextInput.Password
                                                color: app.cFg
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(12)
                                                clip: true
                                                Text {
                                                    visible: !pw.text
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Password for " + pr.modelData.ssid
                                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                                    font: pw.font
                                                }
                                                Keys.onReturnPressed: if (pw.text) app.wifiConnect(pr.modelData.ssid, pw.text)
                                                Keys.onEnterPressed: if (pw.text) app.wifiConnect(pr.modelData.ssid, pw.text)
                                                Keys.onEscapePressed: app.wifiCancelPw()
                                            }
                                            Rectangle {
                                                implicitWidth: joinT.implicitWidth + 24
                                                implicitHeight: 32
                                                radius: 12
                                                color: app.cBlue
                                                opacity: pw.text ? 1 : 0.5
                                                Text {
                                                    id: joinT
                                                    anchors.centerIn: parent
                                                    text: "Join"
                                                    color: app.cOnAccent
                                                    font.family: "Inter"
                                                    font.weight: Font.DemiBold
                                                    font.pixelSize: app.fs(12)
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (pw.text) app.wifiConnect(pr.modelData.ssid, pw.text)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- sliders ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        opacity: isr.revealed > 3 ? 1 : 0
                        transform: Translate { y: isr.revealed > 3 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        spacing: 2
                        VolRow {
                            app: rootV.app
                            au: isr.sink?.audio ?? null
                            glyph: "volume_up"
                            mutedGlyph: "volume_off"
                        }
                        VolRow {
                            app: rootV.app
                            au: isr.source?.audio ?? null
                            glyph: "mic"
                            mutedGlyph: "mic_off"
                            accent: rootV.app.cTeal
                        }
                        BrightRow {
                            app: rootV.app
                            visible: app.brightOk
                        }
                    }

                    // ---- outputs, one click to switch ----
                    Flow {
                        Layout.fillWidth: true
                        opacity: isr.revealed > 4 ? 1 : 0
                        transform: Translate { y: isr.revealed > 4 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        spacing: 6
                        Repeater {
                            model: Pipewire.nodes
                            delegate: Rectangle {
                                id: outChip
                                required property var modelData
                                readonly property bool isOut:
                                    !!modelData && !!modelData.audio && modelData.isSink && !modelData.isStream
                                readonly property bool isDefault: modelData === isr.sink
                                visible: isOut
                                width: isOut ? outT.implicitWidth + 26 : 0
                                height: isOut ? 30 : 0
                                radius: 15
                                color: isDefault ? app.cPrimC
                                     : ocHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
                                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                                border.width: 0
                                HoverHandler { id: ocHov }
                                Text {
                                    id: outT
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, 190)
                                    text: outChip.modelData?.nickname || outChip.modelData?.description
                                          || outChip.modelData?.name || "Output"
                                    color: outChip.isDefault ? app.cOnPrimC : app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    font.bold: outChip.isDefault
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!outChip.isDefault)
                                        Pipewire.preferredDefaultAudioSink = outChip.modelData
                                }
                            }
                        }
                    }

                    // ---- notifications ----
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: isr.revealed > 5 ? 1 : 0
                        transform: Translate { y: isr.revealed > 5 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        Layout.topMargin: 4
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        spacing: 8
                        Text {
                            text: "Notifications"
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                            font.bold: true
                        }
                        Rectangle {
                            visible: app.notifCount > 0
                            implicitWidth: Math.max(18, qnT.implicitWidth + 10)
                            implicitHeight: 18
                            radius: 9
                            color: app.cBlue
                            Text {
                                id: qnT
                                anchors.centerIn: parent
                                text: app.notifCount
                                color: app.cOnAccent
                                font.family: "Inter"
                                font.pixelSize: app.fs(10)
                                font.bold: true
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: app.notifCount > 0
                            text: "Clear all"
                            color: qclr.hovered ? app.cRed : app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                            font.bold: true
                            HoverHandler { id: qclr }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.clearNotifs()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: app.notifCount === 0
                        opacity: isr.revealed > 5 ? 1 : 0
                        transform: Translate { y: isr.revealed > 5 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        text: "You're all caught up"
                        color: app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(12)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // ---- grouped by app: the newest shows, the rest fold away ----
                    Flickable {
                        id: notifFlick
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(groupCol.implicitHeight, 340)
                        visible: app.notifCount > 0
                        contentHeight: groupCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        opacity: isr.revealed > 5 ? 1 : 0
                        transform: Translate { y: isr.revealed > 5 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                        Column {
                            id: groupCol
                            width: notifFlick.width
                            spacing: 6

                            Repeater {
                                // a group's key says what's in it: a group that gains a notification also
                            // moves to the top, and ScriptModel keeps a moved item's old contents
                            model: ScriptModel { values: Models.keyed(app.notifGroups, g => g.app + "~" + g.items.length + "~" + (g.items[0] ? g.items[0].id : "")); objectProp: "_key" }
                                delegate: Rectangle {
                                    id: grp
                                    required property var modelData
                                    readonly property bool open: isr.openGroups[modelData.app] === true
                                    readonly property int more: modelData.items.length - 1
                                    width: groupCol.width
                                    implicitHeight: gCol.implicitHeight + 16
                                    radius: 18
                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)

                                    Column {
                                        id: gCol
                                        x: 12
                                        y: 8
                                        width: parent.width - 24
                                        spacing: 4

                                        // the app: icon, name, count; expand and clear
                                        RowLayout {
                                            width: parent.width
                                            height: 28
                                            spacing: 8
                                            IconImage {
                                                implicitSize: 18
                                                source: app.notifIcon(grp.modelData.items[0])
                                            }
                                            Text {
                                                text: grp.modelData.app
                                                color: app.cDim
                                                font.family: "Inter"
                                                font.weight: Font.DemiBold
                                                font.pixelSize: app.fs(11)
                                            }
                                            Rectangle {
                                                visible: grp.modelData.items.length > 1
                                                implicitWidth: cntT.implicitWidth + 12
                                                implicitHeight: 18
                                                radius: 9
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                                Text {
                                                    id: cntT
                                                    anchors.centerIn: parent
                                                    text: grp.modelData.items.length
                                                    color: app.cDim
                                                    font.family: "Inter"
                                                    font.weight: Font.DemiBold
                                                    font.pixelSize: app.fs(10)
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                visible: grp.more > 0
                                                implicitWidth: 26
                                                implicitHeight: 26
                                                radius: 13
                                                color: expHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                                                HoverHandler { id: expHov }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "expand_more"
                                                    rotation: grp.open ? 180 : 0
                                                    Behavior on rotation { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                                    color: app.cDim
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: app.fs(18)
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: isr.toggleGroup(grp.modelData.app)
                                                }
                                            }
                                            Rectangle {
                                                implicitWidth: 26
                                                implicitHeight: 26
                                                radius: 13
                                                color: clrHov.hovered ? Qt.rgba(app.cRed.r, app.cRed.g, app.cRed.b, 0.18) : "transparent"
                                                HoverHandler { id: clrHov }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "close"
                                                    color: clrHov.hovered ? app.cRed : app.cDim
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: app.fs(16)
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: app.dismissGroup(grp.modelData.app)
                                                }
                                            }
                                        }

                                        // the notifications: the newest, or all when open
                                        Repeater {
                                            model: grp.open ? grp.modelData.items : grp.modelData.items.slice(0, 1)
                                            delegate: Rectangle {
                                                id: item
                                                required property var modelData
                                                readonly property bool actionable: !modelData.saved
                                                    && (modelData.actions || []).some(a => a.key === "default")
                                                width: gCol.width
                                                implicitHeight: itCol.implicitHeight + 14
                                                radius: 12
                                                color: itHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06) : "transparent"
                                                border.width: modelData.urgency >= 2 ? 1 : 0
                                                border.color: app.cRed
                                                HoverHandler { id: itHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: item.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: if (item.actionable) {
                                                        app.invokeNotifAction(item.modelData.id, "default")
                                                        app.quickShown = false
                                                    }
                                                }
                                                ColumnLayout {
                                                    id: itCol
                                                    x: 6
                                                    y: 7
                                                    width: parent.width - 12
                                                    spacing: 1
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: item.modelData.summary || item.modelData.app
                                                            color: app.cFg
                                                            font.family: "Inter"
                                                            font.weight: Font.DemiBold
                                                            font.pixelSize: app.fs(12)
                                                            elide: Text.ElideRight
                                                            textFormat: Text.PlainText
                                                        }
                                                        Text {
                                                            visible: !itHov.hovered
                                                            text: app.notifWhen(item.modelData)
                                                            color: app.cFaint
                                                            font.family: "Inter"
                                                            font.pixelSize: app.fs(10)
                                                        }
                                                        Text {
                                                            visible: itHov.hovered
                                                            text: "close"
                                                            color: itX.hovered ? app.cRed : app.cDim
                                                            font.family: "Material Symbols Rounded"
                                                            font.pixelSize: app.fs(14)
                                                            HoverHandler { id: itX }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                anchors.margins: -6
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: app.dismissNotif(item.modelData.id)
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        visible: text !== ""
                                                        text: item.modelData.body
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                        textFormat: Text.PlainText
                                                    }
                                                }
                                            }
                                        }

                                        // the rest, folded away
                                        Text {
                                            visible: !grp.open && grp.more > 0
                                            leftPadding: 6
                                            bottomPadding: 2
                                            text: grp.more + " more"
                                            color: app.cBlue
                                            font.family: "Inter"
                                            font.weight: Font.Medium
                                            font.pixelSize: app.fs(11)
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: isr.toggleGroup(grp.modelData.app)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- actions ----
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: isr.revealed > 6 ? 1 : 0
                        transform: Translate { y: isr.revealed > 6 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        Layout.topMargin: 4
                        spacing: 0
                        Item { Layout.fillWidth: true }
                        RoundBtn {
                            app: rootV.app
                            glyph: "screenshot_region"
                            onClicked: { app.quickShown = false; app.run("sleep 0.4; $HOME/.local/bin/shot") }
                        }
                        Item { Layout.fillWidth: true }
                        RoundBtn {
                            app: rootV.app
                            glyph: "wallpaper"
                            onClicked: { app.quickShown = false; app.settingsPage = 3; app.settingsShown = true }
                        }
                        Item { Layout.fillWidth: true }
                        RoundBtn {
                            app: rootV.app
                            glyph: "settings"
                            onClicked: { app.quickShown = false; app.settingsShown = true }
                        }
                        Item { Layout.fillWidth: true }
                        RoundBtn {
                            app: rootV.app
                            glyph: "lock"
                            onClicked: { app.quickShown = false; app.run("sleep 0.3; loginctl lock-session") }
                        }
                        Item { Layout.fillWidth: true }
                        RoundBtn {
                            app: rootV.app
                            glyph: "power_settings_new"
                            danger: true
                            onClicked: { app.quickShown = false; app.powerShown = true }
                        }
                        Item { Layout.fillWidth: true }
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
            readonly property bool moved: isr.att && app.drawerLayer !== null && isr.visible
            parent: moved ? app.drawerLayer : drawerHome
            onMovedChanged: if (app.debugLog) console.log("drawer: right contents " + (moved ? "moved into" : "left")
                                        + " the bar window, from the copy on " + isr.modelData.name
                                        + " (main is " + app.mainScreen + ")")
            // Always shown (on the long bar), just clipped to nothing while
            // another drawer, or none, is open: hiding it made Qt throw away
            // its contents' drawing data, and opening rebuilt it all in one
            // frame, which was the stutter at the start of opening.
            readonly property bool active: app.drawerWho === "right" && app.drawerP > 0
            visible: isr.visible && isr.att
            x: moved ? app.drawerCurX : app.drawerCurX - isr.scrX
            y: app.barBottom
            width: active ? app.drawerCurW : 0
            height: active ? app.drawerCurH : 0
            clip: true
        }
    }
    }
}
