import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

// ============================================================
//   CENTRE ISLAND
//   The centre pill, able to grow.  Click it and the pill itself
//   stretches down and out into a panel (media on the left, the
//   weather and this month on the right), its corners easing from
//   pill to card.  The pill's text fades out as the panel's fades
//   in; closing reverses it back into the pill.
//
//   One shape, one window, always mapped while something plays:
//   the mask follows the shape, so only the pill, or the open
//   panel, takes clicks.  Settings > Bar > "Clicking the centre
//   pill" switches back to the separate card (BarCenter.qml and
//   MediaCard.qml), which stay as they were.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: isl
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.barMorph
                 && app.player !== null && app.barMedia
        // ---- where this section's drawer goes, for the long bar ----
        // this window's left edge on screen, the section's centre, and the
        // drawer's final left edge: centred under the section, but kept
        // clear of the bar's rounded ends
        readonly property real scrX: (modelData.width - isl.width) / 2
        readonly property real secCX: scrX + shape.x + shape.width / 2
        readonly property real finalX: Math.max(app.gap + app.barH / 2 + 16,
            Math.min(modelData.width - app.gap - app.barH / 2 - 16 - openW, secCX - openW / 2))
        Binding {
            target: app
            property: "centerGeom"
            // Whichever copy is in charge writes; one that stops being in
            // charge must not put back the value from before it started.
            // (At startup the other monitor's copy is briefly in charge,
            // and restoring its stale values doubled the drawers.)
            restoreMode: Binding.RestoreNone
            when: isl.visible && isl.att
            value: ({ x: isl.finalX, w: isl.openW, h: isl.openH, cx: isl.secCX, secW: shape.width,
                      flush: "" })
        }

        readonly property bool open: app.cardShown
        readonly property bool playing: app.player?.playbackState === MprisPlaybackState.Playing

        readonly property real pillW: Math.min(centerRow.implicitWidth + 16, 720)
        // audio only: the media card and its margins
        readonly property real openW: 616
        readonly property real openH: panel.implicitHeight

        // extra room on both sides and below, for the open panel's shadow
        readonly property int shadowRoom: 36
        // attached: flush with the top edge
        readonly property bool att: app.barAttached
        anchors { top: true }
        margins { top: att ? 0 : app.gap }
        implicitWidth: openW + shadowRoom * 2
        implicitHeight: att ? app.barBottom + openH + 8
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

        // Sections arrive one after another once the shape has mostly
        // grown, the same way quick settings does.  Closing drops them
        // all together.  With animations off, everything is in at once.
        readonly property int sections: 2
        property int revealed: 0
        Timer {
            id: revealStart
            interval: Math.round(app.animSlow * 0.45)
            onTriggered: { isl.revealed = 1; revealStep.start() }
        }
        Timer {
            id: revealStep
            interval: app.dur(45)
            repeat: true
            onTriggered: {
                isl.revealed += 1
                if (isl.revealed >= isl.sections) stop()
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
            Keys.onEscapePressed: app.cardShown = false
        }

        Rectangle {
            id: shape
            anchors.horizontalCenter: parent.horizontalCenter
            y: isl.att ? app.barTop : 0
            width: isl.open && !isl.att ? isl.openW : isl.pillW
            height: isl.att ? app.barH : (isl.open ? isl.openH : app.pillH)
            // attached: square along the top (it's part of the bar),
            // rounded at the bottom once it's a drawer
            radius: isl.att ? app.barH / 2 : (isl.open ? 30 : app.pillH / 2)
            // edgeless glass while it's a pill; hovering brightens it a
            // touch.  The hairline edge returns once it opens into a panel.
            color: isl.att
                   ? "transparent"
                   : (isl.open ? app.cCard
                      : shapeHov.hovered ? Qt.tint(app.cBg, Qt.rgba(1, 1, 1, 0.07)) : app.cBg)
            border.width: !isl.att && isl.open ? 1 : 0
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
            scale: !isl.att && !isl.open && shapeHov.hovered ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
            HoverHandler { id: shapeHov }
            clip: true

            // a soft shadow so the open panel floats; only while it's
            // bigger than the pill, so the closed pill is unchanged
            // depth only for the open panel: the pill stays flat glass
            layer.enabled: !isl.att && (isl.open || height > app.pillH + 2)
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 1.0
                shadowVerticalOffset: 10
                shadowHorizontalOffset: 0
            }

            // a faint glow of the accent along the top edge, rounded like
            // the panel (its clip only cuts square)
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                height: 120
                radius: shape.radius
                opacity: isl.open ? 1 : 0
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
                opacity: isl.open || isl.att ? 0 : 1
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
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: isl.pillW
                height: isl.att ? app.barH : app.pillH
                opacity: isl.att || !isl.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

                // the media group: a tonal container behind the cover and title
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 28
                    radius: 14
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, isl.open || shapeHov.hovered ? 0.12 : 0.07)
                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                }


                RowLayout {
                    id: centerRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: 4
                    spacing: 8

                    // a tiny rounded cover
                    Item {
                        implicitWidth: 20
                        implicitHeight: 20
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                            Text {
                                anchors.centerIn: parent
                                visible: pillArt.status !== Image.Ready
                                text: "music_note"
                                color: app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(11)
                            }
                        }
                        Image {
                            id: pillArt
                            anchors.fill: parent
                            source: app.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 64
                            visible: false
                        }
                        Item {
                            id: pillArtMask
                            anchors.fill: parent
                            layer.enabled: true
                            visible: false
                            Rectangle { anchors.fill: parent; radius: 10; color: "black" }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: pillArt
                            maskEnabled: true
                            maskSource: pillArtMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            visible: pillArt.status === Image.Ready
                        }
                    }
                    // title and artist scroll together, marquee-style, only
                    // when they don't fit
                    Item {
                        id: marquee
                        readonly property real maxW: 560
                        readonly property real overflow: Math.max(0, line.implicitWidth - maxW)
                        implicitWidth: Math.min(line.implicitWidth, maxW)
                        implicitHeight: line.implicitHeight
                        clip: true

                        Row {
                            id: line
                            spacing: 8
                            Text {
                                text: app.player?.trackTitle || "Unknown track"
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                font.weight: Font.Medium
                            }
                            Text {
                                visible: text !== ""
                                text: app.player?.trackArtist ?? ""
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.5)
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                            }
                        }

                        // wait, scroll to the end at an even pace, wait, jump back
                        SequentialAnimation {
                            id: scroller
                            running: marquee.overflow > 0 && isl.visible && !isl.open
                            loops: Animation.Infinite
                            PropertyAction { target: line; property: "x"; value: 0 }
                            PauseAnimation { duration: 2000 }
                            NumberAnimation {
                                target: line
                                property: "x"
                                to: -marquee.overflow
                                duration: marquee.overflow * 28
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 1500 }
                        }

                        // a new track starts from the beginning
                        Connections {
                            target: app
                            function onPlayerChanged() { scroller.restart() }
                        }
                        property string key: (app.player?.trackTitle ?? "") + (app.player?.trackArtist ?? "")
                        onKeyChanged: {
                            line.x = 0
                            if (overflow > 0) scroller.restart()
                        }

                        // soft fade at the edges while scrolling
                        Rectangle {
                            visible: marquee.overflow > 0
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 14
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: app.cBg }
                                GradientStop { position: 1; color: "transparent" }
                            }
                            opacity: line.x < 0 ? 1 : 0
                        }
                        Rectangle {
                            visible: marquee.overflow > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 14
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: app.cBg }
                            }
                            opacity: line.x > -marquee.overflow + 1 ? 1 : 0
                        }
                    }

                    Timer {
                        id: eqTick
                        property int n: 0
                        interval: 100
                        repeat: true
                        running: isl.playing && !isl.open && isl.visible && app.motionOn
                        onTriggered: n++
                    }
                    // equaliser bars: they dance while playing and settle
                    // to a low line when paused
                    Row {
                        spacing: 2
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: bar
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                radius: 1
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.75)
                                opacity: isl.playing ? 1 : 0.5
                                // a new height ten times a second; animating them
                                // smoothly redrew the bar (and Hyprland its blur)
                                // at the screen's full refresh rate, nonstop
                                readonly property var steps: [
                                    [11, 5, 13, 7, 14, 6, 9, 12],
                                    [6, 12, 8, 14, 5, 11, 13, 7],
                                    [9, 7, 12, 5, 10, 14, 6, 11]
                                ]
                                height: isl.playing && !isl.open && app.motionOn
                                        ? steps[bar.index % 3][eqTick.n % 8] : 4
                            }
                        }
                    }
                }

                // how far into the track, as a thin line along the bottom
                Rectangle {
                    readonly property real len: app.player?.length ?? 0
                    readonly property real frac: len > 0
                        ? Math.max(0, Math.min(1, (app.player?.position ?? 0) / len)) : 0
                    visible: len > 0
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: app.pillH / 2
                    anchors.bottomMargin: 3
                    width: (parent.width - app.pillH) * frac
                    height: 2
                    radius: 1
                    color: app.cBlue
                    opacity: 0.8
                }

                // click: grow.  Middle-click: play or pause.  Scroll: tracks.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m => {
                        const p = app.player
                        if (m.button === Qt.MiddleButton) {
                            if (p && p.canTogglePlaying) p.togglePlaying()
                        } else {
                            app.cardShown = !app.cardShown
                        }
                    }
                    onWheel: w => {
                        const p = app.player
                        if (!p) return
                        if (w.angleDelta.y > 0) p.next()
                        else p.previous()
                    }
                }
            }

            // ================= the panel =================
            Item {
                id: panel
                // long bar: inside the drawer that grows out of the bar;
                // islands: inside the pill's own shape
                parent: isl.att ? drawerHost : shape
                x: isl.att ? isl.finalX - app.drawerCurX : 0
                y: 0
                width: isl.openW
                implicitHeight: panelCol.implicitHeight + 36
                opacity: isl.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: panelCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 14

                    // header: click it, or the chevron, to shrink back
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        opacity: isl.revealed > 0 ? 1 : 0
                        transform: Translate { y: isl.revealed > 0 ? 0 : 10
                            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            spacing: 8
                            Text {
                                text: isl.playing ? "pause" : "play_arrow"
                                color: isl.playing ? app.cTeal : app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(13)
                            }
                            Text {
                                text: "Now playing"
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 30
                                implicitHeight: 28
                                radius: 14
                                color: colHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                                HoverHandler { id: colHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: "expand_less"
                                    color: colHov.hovered ? app.cFg : app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(16)
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.cardShown = false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        // ---- media, the same view as the card ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            opacity: isl.revealed > 1 ? 1 : 0
                            transform: Translate { y: isl.revealed > 1 ? 0 : 10
                                Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } } }
                            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                            implicitHeight: media.implicitHeight
                            radius: 24
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            MediaBody {
                                id: media
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                app: rootV.app
                                radius: 24
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
            readonly property bool moved: isl.att && app.drawerLayer !== null && isl.visible
            parent: moved ? app.drawerLayer : drawerHome
            onMovedChanged: console.log("drawer: center contents " + (moved ? "moved into" : "left")
                                        + " the bar window, from the copy on " + isl.modelData.name
                                        + " (main is " + app.mainScreen + ")")
            // Always shown (on the long bar), just clipped to nothing while
            // another drawer, or none, is open: hiding it made Qt throw away
            // its contents' drawing data, and opening rebuilt it all in one
            // frame, which was the stutter at the start of opening.
            readonly property bool active: app.drawerWho === "center" && app.drawerP > 0
            visible: isl.visible && isl.att
            x: moved ? app.drawerCurX : app.drawerCurX - isl.scrX
            y: app.barBottom
            width: active ? app.drawerCurW : 0
            height: active ? app.drawerCurH : 0
            clip: true
        }
    }
}
