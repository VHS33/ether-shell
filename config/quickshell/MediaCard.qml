import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Hyprland

// ============================================================
//   MEDIA CARD
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winM
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.cardShown

        // centred under the bar, same as the calendar popout
        anchors { top: true }
        margins { top: app.gap + app.pillH + 6 }
        implicitWidth: 500
        implicitHeight: 184
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region { x: 8; y: 8; width: winM.width - 16; height: winM.height - 16 }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: app.cCard
            border.width: 1
            border.color: app.cBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                // ---- output volume, vertical, alongside the track ----
                Rectangle {
                    Layout.preferredWidth: 52
                    Layout.fillHeight: true
                    radius: 14
                    color: app.cTile

                    property var sink: Pipewire.defaultAudioSink
                    property real vol: sink?.audio?.volume ?? 0
                    property bool muted: sink?.audio?.muted ?? false

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: parent.parent.muted ? "\u{f075f}" : "\u{f057e}"
                            color: parent.parent.muted ? app.cFaint : app.cMauve
                            font.family: app.font
                            font.pixelSize: app.fs(14)

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                onClicked: {
                                    const a = Pipewire.defaultAudioSink?.audio
                                    if (a) a.muted = !a.muted
                                }
                            }
                        }

                        // the track itself; drag or scroll anywhere on it
                        Rectangle {
                            id: volTrack
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillHeight: true
                            implicitWidth: 16
                            radius: 8
                            color: app.cSurf

                            readonly property real frac:
                                parent.parent.muted ? 0 : parent.parent.vol

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * volTrack.frac
                                radius: 8
                                color: app.cMauve
                                Behavior on height {
                                    NumberAnimation { duration: 90 }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                function setFromY(y) {
                                    const a = Pipewire.defaultAudioSink?.audio
                                    if (!a) return
                                    const f = 1 - (y / volTrack.height)
                                    a.volume = Math.max(0, Math.min(1, f))
                                    a.muted = false
                                }
                                onPressed: mouse => setFromY(mouse.y)
                                onPositionChanged: mouse => {
                                    if (pressed) setFromY(mouse.y)
                                }
                                onWheel: event => {
                                    const a = Pipewire.defaultAudioSink?.audio
                                    if (!a) return
                                    const step = event.angleDelta.y > 0 ? 0.02 : -0.02
                                    a.volume = Math.max(0, Math.min(1, a.volume + step))
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(parent.parent.vol * 100) + "%"
                            color: app.cDim
                            font.family: app.font
                            font.pixelSize: app.fs(10)
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 120
                    Layout.alignment: Qt.AlignVCenter
                    radius: 12
                    color: app.cSurf
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: app.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !app.player?.trackArtUrl
                        text: "\u{f075a}"
                        color: app.cFaint
                        font.family: app.font
                        font.pixelSize: app.fs(34)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: app.player?.trackTitle ?? "Nothing playing"
                        color: app.cFg
                        font.family: app.font
                        font.pixelSize: app.fs(14)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: app.player?.trackArtist ?? ""
                        color: app.cTeal
                        font.family: app.font
                        font.pixelSize: app.fs(12)
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: app.player?.trackAlbum ?? ""
                        color: app.cDim
                        font.family: app.font
                        font.pixelSize: app.fs(11)
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 26
                        Item { Layout.fillWidth: true }

                        Repeater {
                            model: [
                                { glyph: "\u{f04ae}", act: "prev" },
                                { glyph: "",          act: "play" },
                                { glyph: "\u{f04ad}", act: "next" }
                            ]
                            delegate: Text {
                                required property var modelData
                                readonly property bool isPlay: modelData.act === "play"

                                text: isPlay
                                    ? (app.player?.playbackState === MprisPlaybackState.Playing
                                        ? "\u{f03e4}" : "\u{f040c}")
                                    : modelData.glyph
                                color: hov.hovered ? app.cBlue : app.cFg
                                font.family: app.font
                                font.pixelSize: app.fs(isPlay ? 34 : 23)
                                scale: hov.hovered ? 1.12 : 1.0

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                HoverHandler { id: hov }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const p = app.player
                                        if (!p) return
                                        if (modelData.act === "prev") p.previous()
                                        else if (modelData.act === "next") p.next()
                                        else if (p.canTogglePlaying) p.togglePlaying()
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Item { Layout.fillHeight: true }

                    // ---- cava spectrum ----
                    // Fixed-height slots: the bars grow inside them rather
                    // than changing their own implicit height, which would
                    // otherwise push the card taller and make it bounce.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        Layout.bottomMargin: 2

                        RowLayout {
                            anchors.fill: parent
                            spacing: 3

                            Repeater {
                                // A fixed count, not the array itself — using
                                // the array as the model makes the Repeater
                                // destroy and rebuild every delegate on each
                                // frame, which is what caused the flashing.
                                model: 28

                                delegate: Item {
                                    required property int index

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    readonly property real frac:
                                        Math.max(0.06,
                                                 (app.cavaBars[index] ?? 0) / 100)

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height * parent.frac
                                        radius: width / 2

                                        color: Qt.tint(
                                            app.cMauve,
                                            Qt.rgba(app.cTeal.r, app.cTeal.g,
                                                    app.cTeal.b,
                                                    index / 28))
                                        opacity: 0.55 + 0.45 * parent.frac

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 55
                                                easing.type: Easing.OutQuad
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 9

                        Text {
                            text: app.fmtTime(seekBar.pos)
                            color: app.cDim
                            font.family: app.font
                            font.pixelSize: app.fs(10)
                        }

                        Item {
                            id: seekBar
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14

                            readonly property real len: app.player?.length ?? 0
                            readonly property real pos: app.player?.position ?? 0
                            readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0

                            Rectangle {
                                id: track
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 5
                                radius: 3
                                color: app.cSurf

                                Rectangle {
                                    width: track.width * seekBar.frac
                                    height: track.height
                                    radius: 3
                                    color: app.cBlue
                                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: mouse => {
                                    const p = app.player
                                    if (!p || !p.canSeek || !p.length) return
                                    p.position = (mouse.x / width) * p.length
                                }
                            }
                        }

                        Text {
                            text: app.fmtTime(seekBar.len)
                            color: app.cDim
                            font.family: app.font
                            font.pixelSize: app.fs(10)
                        }
                    }
                }
            }
        }
    }
}
