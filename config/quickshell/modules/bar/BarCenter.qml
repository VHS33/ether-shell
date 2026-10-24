import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// ============================================================
//   CENTER PILL
//   What's playing.  Click: media card.  Middle-click: play or
//   pause.  Scroll: next / previous track.
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
        // part of the older pill style: only built when that's in use
        active: modelData.name === app.mainScreen && !app.barMorph

    PanelWindow {
        id: winC
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.player !== null && app.barMedia && !app.barMorph

        anchors { top: true }
        margins { top: app.gap }
        implicitWidth: Math.min(centerRow.implicitWidth + 28, 720)
        implicitHeight: app.pillH
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region { x: 6; y: 6; width: winC.width - 12; height: winC.height - 12 }

        readonly property bool playing: app.player?.playbackState === MprisPlaybackState.Playing

        Rectangle {
            anchors.fill: parent
            radius: app.pillH / 2
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)

            Rectangle {
                id: hit
                anchors.fill: parent
                anchors.margins: 5
                radius: height / 2
                color: app.cardShown ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                     : cHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
                     : "transparent"
                Behavior on color { ColorAnimation { duration: app.animQuick } }
                HoverHandler { id: cHov }
            }

            RowLayout {
                id: centerRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: winC.playing ? "pause" : "play_arrow"
                    color: winC.playing ? app.cTeal : app.cFaint
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(13)
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
                            color: winC.playing ? app.cFg : app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: text !== ""
                            text: app.player?.trackArtist ?? ""
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                        }
                    }

                    // wait, scroll to the end at an even pace, wait, jump back
                    SequentialAnimation {
                        id: scroller
                        running: marquee.overflow > 0 && winC.visible
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
            }

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
    }
    }
}
