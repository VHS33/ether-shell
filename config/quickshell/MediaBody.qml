import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// ============================================================
//   MEDIA BODY
//   The inside of the media view: blurred artwork background,
//   cover, track, controls, seek bar, player switcher, player
//   volume and the visualiser.  Shared by the card under the bar
//   (MediaCard.qml) and the centre pill's panel (CenterIsland.qml),
//   so there's one copy to keep right.
// ============================================================
Item {
    id: mb
    property var app
    // corner radius of whatever this sits in, for the background mask
    property real radius: 28
    readonly property var p: app.player

    implicitHeight: body.implicitHeight + 40

    // ---- seek preview while dragging ----
    property bool seeking: false
    property real seekFrac: 0
    readonly property real len: p?.length ?? 0
    readonly property real pos: p?.position ?? 0
    readonly property real frac: seeking ? seekFrac
                               : (len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0)

    component Ctl: Rectangle {
        id: ctl
        property var app
        property string glyph: ""
        property bool main: false
        property bool lit: false
        property bool usable: true
        signal clicked()

        implicitWidth: main ? 56 : 40
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: main ? app.mBlue
             : lit ? Qt.rgba(app.mBlue.r, app.mBlue.g, app.mBlue.b, 0.22)
             : ctlHov.hovered && usable ? Qt.rgba(app.cSurf.r, app.cSurf.g, app.cSurf.b, 0.9)
             : "transparent"
        opacity: usable ? 1 : 0.35
        scale: ctlMa.pressed && usable ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: app.animQuick } }
        Behavior on scale { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

        HoverHandler { id: ctlHov }

        Text {
            anchors.centerIn: parent
            text: ctl.glyph
            color: ctl.main ? ctl.app.mOnAccent : ctl.lit ? ctl.app.mBlue : ctl.app.cFg
            font.family: "Material Symbols Rounded"
            font.pixelSize: ctl.app.fs(ctl.main ? 26 : 18)
        }

        MouseArea {
            id: ctlMa
            anchors.fill: parent
            enabled: ctl.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: ctl.clicked()
        }
    }

    // ---- the artwork, blurred into the background ----
    Image {
        id: bgArt
        anchors.fill: parent
        // blurred to a wash of colour: a small copy is all it needs
        sourceSize.width: 256
        sourceSize.height: 256
        source: mb.p?.trackArtUrl ?? ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    Item {
        id: bgMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: mb.radius; color: "black" }
    }
    MultiEffect {
        anchors.fill: parent
        source: bgArt
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        maskEnabled: true
        maskSource: bgMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: 0.28
        visible: bgArt.status === Image.Ready
    }

    // ---- cava, a soft strip along the bottom edge ----
    Row {
        id: cava
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 8
        height: 28
        spacing: 3
        readonly property real barW: (width - spacing * 27) / 28
        Repeater {
            // a fixed count, not the array: using the array as the
            // model rebuilt every bar on each frame and flickered
            model: 28
            delegate: Item {
                required property int index
                width: cava.barW
                height: cava.height
                readonly property real f: Math.max(0.08, (app.cavaBars[index] ?? 0) / 100)
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.height * parent.f
                    radius: width / 2
                    color: Qt.tint(app.cMauve, Qt.rgba(app.cTeal.r, app.cTeal.g, app.cTeal.b, index / 28))
                    opacity: 0.25 + 0.35 * parent.f
                    // no animation between readings: cava already smooths
                    // them, and animating kept the drawer redrawing at the
                    // screen's full refresh rate the whole time
                }
            }
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 14

        // ---- which player, when there's more than one ----
        Flow {
            Layout.fillWidth: true
            visible: app.playerList.length > 1
            spacing: 6
            Repeater {
                model: app.playerList
                delegate: Rectangle {
                    id: pl
                    required property var modelData
                    readonly property bool on: mb.p?.dbusName === modelData.key
                    implicitWidth: plRow.implicitWidth + 24
                    implicitHeight: 30
                    radius: 15
                    color: on ? Qt.rgba(app.mBlue.r, app.mBlue.g, app.mBlue.b, 0.26)
                         : plHov.hovered ? app.cSurf
                         : Qt.rgba(app.cSurf.r, app.cSurf.g, app.cSurf.b, 0.6)
                    border.width: on ? 1 : 0
                    border.color: app.mBlue
                    HoverHandler { id: plHov }
                    Row {
                        id: plRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pl.modelData.playing
                            width: 6; height: 6; radius: 3
                            color: app.cGreen
                        }
                        Text {
                            text: pl.modelData.name
                            color: pl.on ? app.cFg : app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                            font.bold: pl.on
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.pickedPlayer = pl.modelData.key
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            // ---- cover ----
            Item {
                implicitWidth: 156
                implicitHeight: 156
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: app.cSurf
                    Text {
                        anchors.centerIn: parent
                        visible: artImg.status !== Image.Ready
                        text: "music_note"
                        color: app.cFaint
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(46)
                    }
                }
                Image {
                    id: artImg
                    anchors.fill: parent
                    // shown at 156 px (more on a scaled screen): a 400 px copy is plenty
                    sourceSize.width: 400
                    sourceSize.height: 400
                    source: mb.p?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Item {
                    id: artMask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Rectangle { anchors.fill: parent; radius: 20; color: "black" }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: artImg
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    visible: artImg.status === Image.Ready
                }
            }

            // ---- track and controls ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: mb.p?.identity ?? ""
                    color: app.cFaint
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: mb.p?.trackTitle || "Unknown track"
                    color: app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(18)
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: mb.p?.trackArtist ?? ""
                    color: app.mBlue
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: mb.p?.trackAlbum ?? ""
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true; implicitHeight: 6 }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Ctl {
                        app: mb.app
                        glyph: "shuffle"
                        usable: mb.p?.shuffleSupported ?? false
                        lit: mb.p?.shuffle ?? false
                        onClicked: if (mb.p) mb.p.shuffle = !mb.p.shuffle
                    }
                    Ctl {
                        app: mb.app
                        glyph: "skip_previous"
                        usable: mb.p?.canGoPrevious ?? false
                        onClicked: mb.p?.previous()
                    }
                    Ctl {
                        app: mb.app
                        main: true
                        glyph: mb.p?.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                        usable: mb.p?.canTogglePlaying ?? false
                        onClicked: mb.p?.togglePlaying()
                    }
                    Ctl {
                        app: mb.app
                        glyph: "skip_next"
                        usable: mb.p?.canGoNext ?? false
                        onClicked: mb.p?.next()
                    }
                    // repeat: off, whole playlist, one track
                    Ctl {
                        app: mb.app
                        readonly property int loop: mb.p?.loopState ?? MprisLoopState.None
                        glyph: loop === MprisLoopState.Track ? "repeat_one" : "repeat"
                        usable: mb.p?.loopSupported ?? false
                        lit: loop !== MprisLoopState.None
                        onClicked: {
                            if (!mb.p) return
                            mb.p.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                                             : loop === MprisLoopState.Playlist ? MprisLoopState.Track
                                             : MprisLoopState.None
                        }
                    }
                }
            }
        }

        // ---- seek bar: drag the handle, it jumps on release ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.preferredWidth: 44
                text: app.fmtTime(mb.frac * mb.len)
                color: app.cDim
                font.family: "Inter"
                font.pixelSize: app.fs(11)
            }

            Item {
                id: seekBox
                Layout.fillWidth: true
                implicitHeight: 22
                readonly property bool canSeek: (mb.p?.canSeek ?? false) && mb.len > 0

                Rectangle {
                    id: seekTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Qt.rgba(app.cSurf.r, app.cSurf.g, app.cSurf.b, 0.9)
                    Rectangle {
                        width: seekTrack.width * mb.frac
                        height: parent.height
                        radius: 3
                        color: app.mBlue
                    }
                }
                Rectangle {
                    visible: seekBox.canSeek
                    width: seekMa.containsMouse || mb.seeking ? 16 : 12
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: seekTrack.verticalCenter
                    x: seekTrack.width * mb.frac - width / 2
                    color: app.mBlue
                    border.width: 2
                    border.color: app.cCard
                    Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: seekMa
                    anchors.fill: parent
                    enabled: seekBox.canSeek
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function at(x) { return Math.max(0, Math.min(1, x / width)) }
                    onPressed: m => { mb.seeking = true; mb.seekFrac = at(m.x) }
                    onPositionChanged: m => { if (pressed) mb.seekFrac = at(m.x) }
                    onReleased: {
                        if (mb.p) mb.p.position = mb.seekFrac * mb.len
                        mb.seeking = false
                    }
                    onCanceled: mb.seeking = false
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: app.fmtTime(mb.len)
                color: app.cDim
                font.family: "Inter"
                font.pixelSize: app.fs(11)
            }
        }

        // ---- lyrics, following along (from LRCLIB) ----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "lyrics"
                    color: mb.app.cDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: mb.app.fs(15)
                }
                Text {
                    Layout.fillWidth: true
                    text: !mb.app.lyricsOn ? "Lyrics hidden"
                        : mb.app.lyricsState === "loading" ? "Finding lyrics\u2026"
                        : mb.app.lyricsState === "none" ? "No lyrics found for this song"
                        : mb.app.lyricsState === "plain" ? "Lyrics (not timed)"
                        : "Lyrics"
                    color: mb.app.cDim
                    font.family: "Inter"
                    font.pixelSize: mb.app.fs(11)
                }
                // show or hide them
                Rectangle {
                    implicitWidth: lyrT.implicitWidth + 18
                    implicitHeight: 24
                    radius: 12
                    color: lyrHov.hovered ? Qt.rgba(mb.app.cFg.r, mb.app.cFg.g, mb.app.cFg.b, 0.12)
                                          : Qt.rgba(mb.app.cFg.r, mb.app.cFg.g, mb.app.cFg.b, 0.06)
                    HoverHandler { id: lyrHov }
                    Text {
                        id: lyrT
                        anchors.centerIn: parent
                        text: mb.app.lyricsOn ? "Hide" : "Show"
                        color: mb.app.cDim
                        font.family: "Inter"
                        font.weight: Font.Medium
                        font.pixelSize: mb.app.fs(11)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            mb.app.setting("lyricsShown", !mb.app.lyricsOn)
                            if (mb.app.lyricsOn) mb.app.fetchLyrics()
                        }
                    }
                }
            }

            // timed: the current line bright and larger, centred; the rest
            // fade the further they are from it
            ListView {
                id: lyr
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                visible: mb.app.lyricsOn && mb.app.lyricsState === "synced"
                model: mb.app.lyrics
                interactive: false
                clip: true
                currentIndex: Math.max(0, mb.app.lyricIndex)
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: height / 2 - 14
                preferredHighlightEnd: height / 2 + 14
                highlightMoveDuration: mb.app.dur(450)
                highlightMoveVelocity: -1
                delegate: Text {
                    required property var modelData
                    required property int index
                    readonly property bool cur: index === mb.app.lyricIndex
                    readonly property int dist: Math.abs(index - Math.max(0, mb.app.lyricIndex))
                    width: lyr.width
                    topPadding: 3
                    bottomPadding: 3
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    // an empty line is a gap in the singing
                    text: modelData.text !== "" ? modelData.text : "\u266a"
                    color: cur ? mb.app.cFg
                         : Qt.rgba(mb.app.cFg.r, mb.app.cFg.g, mb.app.cFg.b, Math.max(0.18, 0.55 - dist * 0.12))
                    font.family: "Inter"
                    font.weight: cur ? Font.DemiBold : Font.Normal
                    font.pixelSize: mb.app.fs(cur ? 15 : 12)
                    Behavior on color { ColorAnimation { duration: mb.app.animNormal } }
                }
            }

            // not timed: the words to scroll through
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                visible: mb.app.lyricsOn && mb.app.lyricsState === "plain"
                contentHeight: plainT.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: plainT
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    lineHeight: 1.25
                    text: mb.app.lyricsPlain
                    color: Qt.rgba(mb.app.cFg.r, mb.app.cFg.g, mb.app.cFg.b, 0.7)
                    font.family: "Inter"
                    font.pixelSize: mb.app.fs(12)
                }
            }
        }

        // ---- the player's own volume, where it offers one ----
        RowLayout {
            Layout.fillWidth: true
            visible: mb.p?.volumeSupported ?? false
            spacing: 12

            Text {
                Layout.preferredWidth: 44
                text: "volume_up"
                color: app.cMauve
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(15)
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: 22
                readonly property real v: Math.max(0, Math.min(1, mb.p?.volume ?? 0))
                Rectangle {
                    id: pvTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Qt.rgba(app.cSurf.r, app.cSurf.g, app.cSurf.b, 0.9)
                    Rectangle {
                        width: pvTrack.width * parent.parent.v
                        height: parent.height
                        radius: 3
                        color: app.cMauve
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function set(x) { if (mb.p) mb.p.volume = Math.max(0, Math.min(1, x / width)) }
                    onPressed: m => set(m.x)
                    onPositionChanged: m => { if (pressed) set(m.x) }
                    onWheel: w => { if (mb.p) mb.p.volume = Math.max(0, Math.min(1, mb.p.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))) }
                }
            }
            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: Math.round((mb.p?.volume ?? 0) * 100) + "%"
                color: app.cDim
                font.family: "Inter"
                font.pixelSize: app.fs(11)
            }
        }

        // room for the visualiser strip under everything
        Item { implicitHeight: 26 }
    }
}
