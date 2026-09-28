import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

// ============================================================
//   LONG BAR  (bar style "long")
//   One long pill across the top of the main screen, and the open
//   drawer, drawn together on ONE surface.  Separate panels each get
//   their own blur, which showed as a line where they met; shapes on
//   one surface, meeting edge to edge, can't have a seam.
//
//   The drawer grows out of the bar's bottom edge: from the centre of
//   its section, or flush down one of the bar's ends (app.drawerCurX /
//   W / H, driven by app.drawerP), with curved joins forming as it
//   grows.  The section's own window draws the drawer's contents,
//   clipped to the same rectangle.
//
//   Purely a background: it takes no clicks, and Spacer.qml reserves
//   the bar's room.  In the islands style it stays shown but draws
//   nothing, so it keeps its place underneath everything.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // a concave corner: `corner` says which corner of the square is filled
    // ("tl" or "tr"), with a quarter circle cut from the rest
    // It reaches `pad` pixels past its edges into what it joins (up into the
    // bar, and sideways into the drawer), so the soft edges of neighbouring
    // pieces are covered rather than meeting side by side.
    component Fillet: Canvas {
        id: fil
        property var app
        property string corner: "tl"
        property real r: 14
        property int pad: 2
        property color fill: app.cBg
        width: Math.ceil(r) + pad
        height: Math.ceil(r) + pad
        onFillChanged: requestPaint()
        onRChanged: requestPaint()
        onCornerChanged: requestPaint()
        onPadChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = Math.ceil(r), p = pad
            if (w < 1) return
            ctx.fillStyle = fill
            // the rows reaching up into the bar
            ctx.fillRect(0, 0, w + p, p)
            ctx.beginPath()
            if (corner === "tl") {
                // right of the drawer: the drawer is to the left, so the
                // extra column is on the left
                ctx.fillRect(0, p, p, w)
                ctx.moveTo(p, p)
                ctx.lineTo(p + w, p)
                ctx.arc(p + w, p + w, w, -Math.PI / 2, Math.PI, true)
            } else {
                // left of the drawer: the extra column is on the right
                ctx.fillRect(w, p, p, w)
                ctx.moveTo(w, p)
                ctx.lineTo(0, p)
                ctx.arc(0, p + w, w, -Math.PI / 2, 0, false)
            }
            ctx.closePath()
            ctx.fill()
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
        id: strip
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Always shown on the main screen, even in the islands style (where
        // it draws nothing).  Wayland stacks panels in the order they
        // appear, so if this were hidden and shown again when switching
        // styles it would come back on top, over the bar's sections, and
        // hide them.  Staying put keeps it underneath everything.
        visible: modelData.name === app.mainScreen
        readonly property bool active: visible && app.barAttached

        // The whole screen, transparent and click-through, and never
        // resized.  It used to be only as tall as the tallest drawer, which
        // meant growing after the drawers had measured themselves; when that
        // growth didn't happen, a drawer's glass was drawn but cropped to a
        // sliver under the bar, leaving its contents with nothing behind.
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Clicks.  Normally only the open drawer takes them.  While a drawer,
        // the launcher or the clipboard is open, the whole screen does, and a
        // click anywhere outside them closes them.  (This used to be a
        // separate invisible full-screen window on every monitor.)  The bar's
        // sections are windows of their own, above this one, so clicking
        // another section still switches drawers.
        readonly property bool modalOpen: app.cardShown || app.quickShown || app.sysShown
                                          || app.launcherShown || app.clipShown
        property Region drawerMask: Region {
            x: Math.round(strip.dl)
            y: strip.y0 + strip.bh
            width: strip.dOpen ? Math.round(strip.dw) : 0
            height: strip.dOpen ? Math.ceil(strip.dh) : 0
        }
        property Region allMask: Region { width: strip.width; height: strip.height }
        mask: modalOpen ? allMask : drawerMask
        // Keyboard: the drawers take it when clicked into (a Wi-Fi password,
        // say).
        WlrLayershell.keyboardFocus: !strip.active ? WlrKeyboardFocus.None
            : app.drawerNow !== "" && app.drawerNow !== "island" ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

        // ---- the drawer's growth ----
        // Animated here, on this window's own render loop, so every step
        // lands on a frame of the screen; each step is written back to
        // app.drawerP for the sections' windows, which clip their contents
        // to the same shape.  Opening starts quickly and settles softly;
        // closing gathers pace and gets out of the way.
        property real p: 0
        property bool opening: true
        Behavior on p {
            id: pBehavior
            NumberAnimation {
                duration: strip.opening ? Math.round(app.animSlow * 1.25) : app.animNormal
                easing.type: strip.opening ? Easing.OutQuart : Easing.InCubic
            }
        }
        // There's one of these per screen, and only the main screen's is
        // shown.  Only that one may report progress: the hidden one's
        // animation runs on its own schedule, and it finishing late
        // ("open") after the visible one had closed is what left an empty
        // drawer showing.
        onPChanged: if (strip.active) {
            app.drawerP = p
            app.drawerStripP = p
            // log where each animation ends up
            if (p === 0 || p === 1) app.drawerLog("animation reached " + p)
        }
        Connections {
            target: app
            enabled: strip.active
            function onDrawerToChanged() {
                strip.opening = app.drawerTo > strip.p
                strip.p = app.drawerTo
            }
            // switching straight to another drawer: start it from closed
            function onDrawerRestartChanged() {
                pBehavior.enabled = false
                strip.p = 0
                pBehavior.enabled = true
                strip.opening = true
                strip.p = app.drawerTo
            }
        }

        readonly property real x0: app.gap
        readonly property real y0: app.barTop
        readonly property real bw: width - app.gap * 2
        readonly property real bh: app.barH
        readonly property real r: bh / 2

        // ---- the drawing: plain rounded rectangles on one surface ----
        // The bar and the open drawer used to be one curved outline drawn
        // by Qt's GPU curve renderer.  When that outline touched itself (the
        // flush drawers did), the renderer could break and stop drawing
        // altogether, leaving every later drawer without its glass.  These
        // are the most basic shapes Qt draws; they meet edge to edge on
        // whole pixels without overlapping, so there's still no seam.
        readonly property real dh: app.drawerCurH
        readonly property real dw: Math.max(0, app.drawerCurW)
        readonly property real dl: app.drawerCurX
        readonly property bool dOpen: active && dh > 0.5 && dw > 1
        readonly property string flush: app.drawerFlush
        readonly property real f: Math.max(0, Math.min(14, dh, dw / 4))     // the curved join
        readonly property real rb: Math.max(0, Math.min(24, dh / 2, dw / 2)) // the drawer's bottom corners

        // ---- the glass: one surface, with no seams ----
        // The bar, the drawer and the curved joins are drawn solid inside one
        // layer, overlapping a little at every join, and the layer as a whole
        // is then made see-through.  Drawn separately, each piece was itself
        // see-through with softened edges, and two half-transparent edges
        // side by side don't add up to the glass: a faint lighter line showed
        // where the drawer met the bar.  Solid pieces can overlap without
        // showing it, and one transparency for the whole leaves nothing to see.
        Item {
            id: glass
            visible: strip.active
            width: strip.width
            // just the bar and the tallest drawer, so the layer stays small
            readonly property real reach: Math.max(app.leftGeom?.h ?? 0, app.centerGeom?.h ?? 0,
                                                   app.rightGeom?.h ?? 0, app.islandGeom?.h ?? 0)
            height: Math.min(strip.height, strip.y0 + strip.bh + reach + 8)
            readonly property color solid: Qt.rgba(app.cBg.r, app.cBg.g, app.cBg.b, 1)
            opacity: app.cBg.a
            layer.enabled: true

            // the bar: when a drawer runs flush down one of its ends, that end's
            // bottom corner straightens as the drawer grows, so the bar's edge
            // carries straight on down the drawer's side
            Rectangle {
                x: strip.x0
                y: strip.y0
                width: strip.bw
                height: strip.bh
                color: glass.solid
                radius: strip.r
                bottomLeftRadius: strip.dOpen && strip.flush === "left" ? Math.max(0, strip.r - strip.dh) : strip.r
                bottomRightRadius: strip.dOpen && strip.flush === "right" ? Math.max(0, strip.r - strip.dh) : strip.r
            }

            // the drawer, reaching 2 px up into the bar so the join is covered
            Rectangle {
                visible: strip.dOpen
                x: Math.round(strip.dl)
                y: strip.y0 + strip.bh - 2
                width: Math.round(strip.dw)
                height: strip.dh + 2
                color: glass.solid
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: strip.rb
                bottomRightRadius: strip.rb
            }

            // the curved joins, on the sides that aren't flush with an end,
            // each reaching into the bar above and the drawer beside it
            Fillet {
                app: rootV.app
                fill: glass.solid
                corner: "tr"
                r: strip.f
                x: Math.round(strip.dl) - Math.ceil(strip.f)
                y: strip.y0 + strip.bh - pad
                visible: strip.dOpen && strip.flush !== "left" && strip.f >= 1
            }
            Fillet {
                app: rootV.app
                fill: glass.solid
                corner: "tl"
                r: strip.f
                x: Math.round(strip.dl) + Math.round(strip.dw) - pad
                y: strip.y0 + strip.bh - pad
                visible: strip.dOpen && strip.flush !== "right" && strip.f >= 1
            }
        }


        // ---- a click outside what's open closes it ----
        MouseArea {
            anchors.fill: parent
            enabled: strip.modalOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: mouse => {
                // an empty spot inside the open drawer isn't "outside"
                const top = strip.y0 + strip.bh
                if (strip.dOpen && mouse.x >= strip.dl && mouse.x <= strip.dl + strip.dw
                        && mouse.y >= top && mouse.y <= top + strip.dh) return
                app.cardShown = false
                app.quickShown = false
                app.sysShown = false
                app.launcherShown = false
                app.clipShown = false
            }
        }

        // ---- the open drawer's contents ----
        // Each section's drawer contents are moved in here, so they're drawn
        // on the same surface, in the same frame, as the glass beneath them.
        // Esc closes whichever drawer is open.
        Item {
            id: drawerLayer
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: {
                app.cardShown = false
                app.quickShown = false
                app.sysShown = false
                app.launcherShown = false
            }

            // ---- the dynamic island's contents ----
            Item {
                id: islandHost
                readonly property var d: app.islandData
                readonly property var g: app.islandGeom
                visible: strip.active && app.drawerWho === "island" && app.drawerP > 0 && g !== null
                x: app.drawerCurX
                y: strip.y0 + strip.bh
                width: app.drawerCurW
                height: app.drawerCurH
                clip: true

                // it waits while the mouse is over it; a click opens it
                HoverHandler { onHoveredChanged: app.holdIsland(hovered) }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: islandHost.d.kind === "notif" && islandHost.d.canOpen ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        const d = islandHost.d
                        if (d.kind === "notif" && d.canOpen) app.invokeNotifAction(d.id, "default")
                        else if (d.kind === "track") { app.hideIsland(); app.cardShown = true; return }
                        app.hideIsland()
                    }
                }

                Item {
                    // held at its final place while the shape grows around it
                    x: islandHost.g ? islandHost.g.x - app.drawerCurX : 0
                    width: islandHost.g ? islandHost.g.w : 0
                    height: islandHost.g ? islandHost.g.h : 0
                    opacity: app.drawerP > 0.55 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: app.animQuick } }

                    // ---- a notification ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 16
                        visible: islandHost.d.kind === "notif"
                        spacing: 12
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 12
                            color: islandHost.d.urgent ? Qt.rgba(app.cRed.r, app.cRed.g, app.cRed.b, 0.25)
                                                       : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 22
                                source: islandHost.d.icon || ""
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: islandHost.d.summary || islandHost.d.app || ""
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(13)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: (islandHost.d.body || "").replace(/\s+/g, " ")
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                        Text {
                            text: islandHost.d.app || ""
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                            font.family: "Inter"
                            font.pixelSize: app.fs(10)
                        }
                    }

                    // ---- volume, microphone, brightness, night light ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 18
                        visible: islandHost.d.kind === "osd"
                        spacing: 12
                        readonly property string k: islandHost.d.osdKind || "volume"
                        readonly property real v: islandHost.d.value || 0
                        readonly property bool off: islandHost.d.muted === true
                        readonly property color tint: k === "brightness" || k === "night" ? app.cYellow
                                                    : k === "mic" ? app.cTeal : app.cBlue
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: parent.off ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : parent.tint
                            Text {
                                anchors.centerIn: parent
                                readonly property var row: parent.parent
                                text: row.k === "mic" ? (row.off ? "mic_off" : "mic")
                                    : row.k === "night" ? (row.off ? "light_mode" : "dark_mode")
                                    : row.k === "brightness" ? (row.v < 0.34 ? "brightness_low" : row.v < 0.67 ? "brightness_medium" : "brightness_high")
                                    : row.off ? "volume_off" : row.v === 0 ? "volume_mute" : row.v < 0.5 ? "volume_down" : "volume_up"
                                color: row.off ? app.cDim : app.cOnAccent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(19)
                            }
                        }
                        Text {
                            readonly property var row: parent
                            text: row.k === "mic" ? (row.off ? "Microphone muted" : "Microphone")
                                : row.k === "night" ? (row.off ? "Night light off" : "Night light on")
                                : row.k === "brightness" ? "Brightness"
                                : row.off ? "Muted" : "Volume"
                            color: app.cFg
                            font.family: "Inter"
                            font.weight: Font.DemiBold
                            font.pixelSize: app.fs(13)
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            visible: parent.k !== "night"
                            implicitHeight: 8
                            radius: 4
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                            Rectangle {
                                width: parent.width * (parent.parent.off ? 0 : Math.min(1, parent.parent.v))
                                height: parent.height
                                radius: 4
                                color: parent.parent.tint
                                Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                            }
                        }
                        Item { Layout.fillWidth: true; visible: parent.k === "night" }
                        Text {
                            visible: parent.k !== "night"
                            text: parent.off ? "" : Math.round(parent.v * 100) + "%"
                            color: app.cDim
                            font.family: "Inter"
                            font.weight: Font.Medium
                            font.pixelSize: app.fs(12)
                        }
                    }

                    // ---- the next song ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16
                        visible: islandHost.d.kind === "track"
                        spacing: 12
                        Item {
                            implicitWidth: 40
                            implicitHeight: 40
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                Text {
                                    anchors.centerIn: parent
                                    visible: islandArt.status !== Image.Ready
                                    text: "music_note"
                                    color: app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(18)
                                }
                            }
                            Image {
                                id: islandArt
                                anchors.fill: parent
                                source: islandHost.d.kind === "track" ? (islandHost.d.art || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 96
                                visible: false
                            }
                            Item {
                                id: islandArtMask
                                anchors.fill: parent
                                layer.enabled: true
                                visible: false
                                Rectangle { anchors.fill: parent; radius: 10; color: "black" }
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: islandArt
                                maskEnabled: true
                                maskSource: islandArtMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                                visible: islandArt.status === Image.Ready
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: islandHost.d.title || ""
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(13)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: islandHost.d.artist || ""
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                        Text {
                            text: "graphic_eq"
                            color: app.mBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                    }

                    // ---- a game session ending ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16
                        visible: islandHost.d.kind === "game"
                        spacing: 12
                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: 12
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                            // the game's own icon (Steam installs one per game)
                            IconImage {
                                id: gameIcon
                                anchors.centerIn: parent
                                implicitSize: 28
                                source: islandHost.d.kind !== "game" ? ""
                                      : islandHost.d.appId ? Quickshell.iconPath("steam_icon_" + islandHost.d.appId, true)
                                                             || app.iconFor(islandHost.d.cls)
                                      : app.iconFor(islandHost.d.cls)
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !gameIcon.source || gameIcon.status === Image.Error
                                text: "sports_esports"
                                color: app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(20)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: islandHost.d.name || "Game"
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(13)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Played " + app.fmtPlay(islandHost.d.secs || 0)
                                      + ((islandHost.d.week || 0) > (islandHost.d.secs || 0) + 59
                                         ? "  \u2022  " + app.fmtPlay(islandHost.d.week) + " this week" : "")
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: "sports_esports"
                            color: app.cBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                    }

                    // ---- a scene saved or restored ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 18
                        visible: islandHost.d.kind === "scene"
                        spacing: 12
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: app.cPrimC
                            Text {
                                anchors.centerIn: parent
                                text: islandHost.d.verb === "Saved" ? "bookmark_added" : "view_quilt"
                                color: app.cOnPrimC
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(19)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: (islandHost.d.verb || "") + " \u201c" + (islandHost.d.name || "") + "\u201d"
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(13)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                Layout.fillWidth: true
                                text: islandHost.d.detail || ""
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ---- a timer finishing ----
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        visible: islandHost.d.kind === "timer"
                        spacing: 12
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: app.cRed
                            Text {
                                anchors.centerIn: parent
                                text: "alarm"
                                color: app.cOnAccent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(19)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "Time's up"
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(13)
                            }
                            Text {
                                text: "Your " + (islandHost.d.len || "") + " timer has finished"
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                            }
                        }
                        Rectangle {
                            implicitWidth: dismissT.implicitWidth + 24
                            implicitHeight: 32
                            radius: 16
                            color: app.cBlue
                            Text {
                                id: dismissT
                                anchors.centerIn: parent
                                text: "Dismiss"
                                color: app.cOnAccent
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(12)
                            }
                        }
                    }
                }
            }
        }
        Binding {
            target: app
            property: "drawerLayer"
            // Whichever copy is in charge writes; one that stops being in
            // charge must not put back the value from before it started.
            // (At startup the other monitor's copy is briefly in charge,
            // and restoring its stale values doubled the drawers.)
            restoreMode: Binding.RestoreNone
            value: drawerLayer
            when: strip.active
        }
    }
    }
}
