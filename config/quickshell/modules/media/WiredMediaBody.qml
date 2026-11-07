import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.services

// The media drawer in the Wired look (Settings > Theme > Look), after the
// Wired lock: a title bar with the player and whether it's playing, the
// cover greyed and scanned (a little of its colour kept), the track, a
// segmented level meter (cava), where it is as segments, the controls as
// boxes with SHUF and LOOP (OFF, ALL, ONE) for players that have them,
// the player's own volume, and the lyrics.  Same data and controls as the
// standard media view (MediaBody).
Item {
    id: wm
    property var app
    signal close()
    readonly property var p: app.player

    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color faint: Qt.rgba(0.38, 0.4, 0.44, 1)
    readonly property color ink: "#0a0c0e"
    readonly property color off: Qt.rgba(0.15, 0.165, 0.18, 1)
    readonly property var families: Qt.fontFamilies()
    readonly property string jpFont: ["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "IPAGothic"]
                                     .find(f => families.indexOf(f) >= 0) || ""
    readonly property bool jp: jpFont !== ""

    readonly property bool playing: p?.playbackState === MprisPlaybackState.Playing
    // where it is, or where the seek bar is being dragged to
    property bool seeking: false
    property real seekFrac: 0
    readonly property real len: p?.length ?? 0
    readonly property real pos: p?.position ?? 0
    readonly property real frac: seeking ? seekFrac : (len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0)

    implicitHeight: body.y + body.implicitHeight + 16

    // an outlined box with a word in it; "lit" fills it
    component Btn: Rectangle {
        id: b
        property string text: ""
        property bool lit: false
        property bool usable: true
        property int size: 12
        signal clicked()
        width: bT.implicitWidth + 24; height: 24
        color: lit ? wm.accent : bHov.hovered && usable ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        border.width: lit ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.3)
        opacity: usable ? 1 : 0.35
        HoverHandler { id: bHov }
        Text { id: bT; anchors.centerIn: parent; text: b.text; color: b.lit ? wm.ink : wm.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: b.size }
        MouseArea { anchors.fill: parent; enabled: b.usable; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    component Label: Row {
        property string en: ""
        property string ja: ""
        spacing: 8
        Text { text: parent.en; color: wm.accent; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        Text { visible: wm.jp && parent.ja !== ""; text: parent.ja; color: wm.dim; font.family: wm.jpFont; font.pixelSize: 11 }
    }

    // ---- the title bar: MEDIA, the player and its state; the boxes close it ----
    Rectangle {
        id: titleBar
        width: parent.width; height: 22
        color: Qt.rgba(0.93, 0.94, 0.95, 0.9)
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text { text: "MEDIA"; color: wm.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 13 }
            Text { visible: wm.jp; text: "再生"; color: wm.ink; font.family: wm.jpFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            anchors.right: boxes.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: (wm.p?.identity ? String(wm.p.identity).toUpperCase() + "  " : "")
                  + (wm.playing ? "PLAYING" : wm.p?.playbackState === MprisPlaybackState.Paused ? "PAUSED" : "STOPPED")
            color: Qt.rgba(0.24, 0.25, 0.27, 1); font.family: Theme.font; font.pixelSize: 12
        }
        Row {
            id: boxes
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 3; delegate: Rectangle { width: 7; height: 7; color: "transparent"; border.width: 1; border.color: wm.ink } }
        }
        MouseArea { anchors.right: parent.right; width: 40; height: parent.height; cursorShape: Qt.PointingHandCursor; onClicked: wm.close() }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 3; anchors.topMargin: titleBar.height + 3
        color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
    }

    Column {
        id: body
        x: 16; y: titleBar.height + 14
        width: parent.width - 32
        spacing: 14

        // ---- which player, when there's more than one ----
        Flow {
            visible: wm.app.playerList.length > 1
            width: parent.width
            spacing: 6
            Repeater {
                model: ScriptModel { values: wm.app.playerList; objectProp: "key" }
                delegate: Btn {
                    required property var modelData
                    size: 11
                    text: (modelData.playing ? "> " : "") + String(modelData.name).toUpperCase()
                    lit: wm.p?.dbusName === modelData.key
                    onClicked: Media.pickedPlayer = modelData.key
                }
            }
        }

        // ---- the cover and the track ----
        Item {
            width: parent.width; height: 150
            // the cover: grey and scanned, a little of its colour kept
            Rectangle {
                id: art
                width: 150; height: 150
                color: Qt.rgba(1, 1, 1, 0.03)
                clip: true
                Column {
                    anchors.centerIn: parent
                    visible: artImg.status !== Image.Ready
                    spacing: 4
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NO SIGNAL"; color: wm.faint; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
                    Text { visible: wm.jp; anchors.horizontalCenter: parent.horizontalCenter; text: "信号なし"; color: wm.faint; font.family: wm.jpFont; font.pixelSize: 11 }
                }
                Image {
                    id: artImg
                    anchors.fill: parent
                    sourceSize.width: 300
                    sourceSize.height: 300
                    source: wm.p?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: artImg
                    saturation: -0.65
                    contrast: 0.08
                    visible: artImg.status === Image.Ready
                }
                // scan lines
                Column {
                    visible: artImg.status === Image.Ready
                    Repeater {
                        model: 50
                        delegate: Item {
                            width: art.width; height: 3
                            Rectangle { width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.3) }
                        }
                    }
                }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
            }
            Column {
                x: art.width + 16
                width: parent.width - x
                spacing: 4
                Label { en: "NOW PLAYING"; ja: "再生中" }
                Item { width: 1; height: 2 }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: wm.p?.trackTitle || "Unknown track"
                    color: wm.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 17
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: wm.p?.trackArtist ?? ""
                    color: wm.dim; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: (wm.p?.trackAlbum ?? "") !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: "from  " + (wm.p?.trackAlbum ?? "")
                    color: wm.faint; font.family: Theme.font; font.pixelSize: 11
                }
            }
            // a level meter, segmented, as it plays (cava)
            Row {
                x: art.width + 16
                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                spacing: 4
                Repeater {
                    model: 24
                    delegate: Item {
                        required property int index
                        width: 9; height: 26
                        readonly property real f: Math.max(0, Math.min(1, (wm.app.cavaBars[Math.round(index * 27 / 23)] ?? 0) / 100))
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 3 + Math.round(parent.f * 23)
                            color: parent.f > 0.45 ? wm.accent : Qt.rgba(wm.accent.r, wm.accent.g, wm.accent.b, 0.4)
                        }
                    }
                }
            }
        }

        // ---- where it is: drag along it, it jumps on release ----
        Item {
            width: parent.width; height: 12
            Item {
                id: seekBox
                width: parent.width - 110; height: parent.height
                readonly property bool canSeek: (wm.p?.canSeek ?? false) && wm.len > 0
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                        model: 40
                        delegate: Rectangle {
                            required property int index
                            width: (seekBox.width - 39 * 3) / 40; height: 8
                            color: index < Math.round(wm.frac * 40) ? wm.accent : wm.off
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    enabled: seekBox.canSeek
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function at(x) { return Math.max(0, Math.min(1, (x - 4) / seekBox.width)) }
                    onPressed: m => { wm.seeking = true; wm.seekFrac = at(m.x) }
                    onPositionChanged: m => { if (pressed) wm.seekFrac = at(m.x) }
                    onReleased: { if (wm.p) wm.p.position = wm.seekFrac * wm.len; wm.seeking = false }
                    onCanceled: wm.seeking = false
                }
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: wm.app.fmtTime(wm.frac * wm.len) + " / " + wm.app.fmtTime(wm.len)
                color: wm.paper; font.family: Theme.font; font.pixelSize: 11
            }
        }

        // ---- the controls, shuffle and repeat, and the player's volume ----
        Item {
            width: parent.width; height: 24
            Row {
                spacing: 10
                Btn { width: 48; text: "|<"; usable: wm.p?.canGoPrevious ?? false; onClicked: wm.p?.previous() }
                Btn { width: 48; text: wm.playing ? "||" : ">"; lit: true; usable: wm.p?.canTogglePlaying ?? false; onClicked: wm.p?.togglePlaying() }
                Btn { width: 48; text: ">|"; usable: wm.p?.canGoNext ?? false; onClicked: wm.p?.next() }
                Item { width: 14; height: 1 }
                // shuffle and repeat, for players that have them (Spotify does)
                Btn {
                    visible: wm.p?.shuffleSupported ?? false
                    width: 52; size: 11
                    text: "SHUF"
                    lit: wm.p?.shuffle ?? false
                    onClicked: if (wm.p) wm.p.shuffle = !wm.p.shuffle
                }
                Btn {
                    readonly property int loop: wm.p?.loopState ?? MprisLoopState.None
                    visible: wm.p?.loopSupported ?? false
                    width: 84; size: 11
                    text: loop === MprisLoopState.Track ? "LOOP ONE" : loop === MprisLoopState.Playlist ? "LOOP ALL" : "LOOP OFF"
                    lit: loop !== MprisLoopState.None
                    // off, the whole playlist, this track
                    onClicked: {
                        if (!wm.p) return
                        wm.p.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                                       : loop === MprisLoopState.Playlist ? MprisLoopState.Track
                                       : MprisLoopState.None
                    }
                }
            }
            // the player's own volume: click or drag along it, or the wheel
            Row {
                visible: wm.p?.volumeSupported ?? false
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                readonly property real v: Math.max(0, Math.min(1, wm.p?.volume ?? 0))
                Text { anchors.verticalCenter: parent.verticalCenter; text: "VOL"; color: wm.second; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
                Item {
                    width: 10 * 4 + 9 * 2; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: 10
                            delegate: Rectangle {
                                required property int index
                                width: 4; height: 8
                                color: index < Math.round(wm.p?.volume * 10 || 0) ? wm.second : wm.off
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        function set(x) { if (wm.p) wm.p.volume = Math.max(0, Math.min(1, x / width)) }
                        onPressed: m => set(m.x)
                        onPositionChanged: m => { if (pressed) set(m.x) }
                        onWheel: w => { if (wm.p) wm.p.volume = Math.max(0, Math.min(1, wm.p.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))) }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: volM.advanceWidth
                    horizontalAlignment: Text.AlignRight
                    text: String(Math.round((wm.p?.volume ?? 0) * 100))
                    color: wm.paper; font.family: Theme.font; font.pixelSize: 11
                    TextMetrics { id: volM; font.family: Theme.font; font.pixelSize: 11; text: "100" }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.16) }

        // ---- lyrics, following along (from LRCLIB) ----
        Item {
            width: parent.width; height: 24
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Label { en: "LYRICS"; ja: "歌詞" }
                Text {
                    text: !wm.app.lyricsOn ? "hidden"
                        : wm.app.lyricsState === "loading" ? "finding lyrics…"
                        : wm.app.lyricsState === "none" ? "none found for this song"
                        : wm.app.lyricsState === "plain" ? "not timed"
                        : ""
                    color: wm.faint; font.family: Theme.font; font.pixelSize: 11
                }
            }
            Btn {
                anchors.right: parent.right
                size: 11
                text: wm.app.lyricsOn ? "HIDE" : "SHOW"
                onClicked: {
                    wm.app.setting("lyricsShown", !wm.app.lyricsOn)
                    if (wm.app.lyricsOn) wm.app.fetchLyrics()
                }
            }
        }
        // timed: the line being sung bright, centred; the rest fade
        ListView {
            id: lyr
            width: parent.width; height: 150
            visible: wm.app.lyricsOn && wm.app.lyricsState === "synced"
            model: wm.app.lyrics
            interactive: false
            clip: true
            currentIndex: Math.max(0, wm.app.lyricIndex)
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: height / 2 - 12
            preferredHighlightEnd: height / 2 + 12
            highlightMoveDuration: wm.app.dur(450)
            highlightMoveVelocity: -1
            delegate: Text {
                required property var modelData
                required property int index
                readonly property bool cur: index === wm.app.lyricIndex
                readonly property int dist: Math.abs(index - Math.max(0, wm.app.lyricIndex))
                width: lyr.width
                topPadding: 3; bottomPadding: 3
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: (cur ? "> " : "") + (modelData.text !== "" ? modelData.text : "~")
                color: cur ? wm.paper : Qt.rgba(0.6, 0.62, 0.65, Math.max(0.25, 0.85 - dist * 0.18))
                font.family: Theme.font
                font.weight: cur ? Font.Bold : Font.Normal
                font.pixelSize: cur ? 14 : 12
            }
        }
        // not timed: the words to scroll through
        Flickable {
            width: parent.width; height: 150
            visible: wm.app.lyricsOn && wm.app.lyricsState === "plain"
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
                text: wm.app.lyricsPlain
                color: wm.dim; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }
}
