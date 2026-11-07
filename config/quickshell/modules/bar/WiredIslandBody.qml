import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.services

// The long bar's island (a notification, volume and the like, the next
// song, a game ending, a scene, a timer) in the Wired look (Settings >
// Theme > Look): a light block naming what it is, like the lock's blocks,
// then the details in mono type; volume and brightness as a segmented
// level.  The same data as the standard island (app.islandData).
Item {
    id: wi
    property var app
    property var d: ({})

    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color red: app.cRed
    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color faint: Qt.rgba(0.38, 0.4, 0.44, 1)
    readonly property color ink: "#0a0c0e"
    readonly property color off: Qt.rgba(0.15, 0.165, 0.18, 1)
    readonly property string jpFont: ["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "IPAGothic"]
                                     .find(f => Qt.fontFamilies().indexOf(f) >= 0) || ""

    readonly property string kind: d.kind || ""
    readonly property string osdKind: d.osdKind || "volume"
    readonly property bool muted: d.muted === true
    readonly property real v: Math.max(0, Math.min(1, d.value || 0))
    readonly property bool toggleKind: osdKind === "night" || osdKind === "game"

    // what it is, in English and Japanese
    readonly property var label: {
        if (kind === "notif") return ["NOTIFY", "通知"]
        if (kind === "track") return ["TRACK", "再生"]
        if (kind === "game") return ["GAME", "遊戯"]
        if (kind === "scene") return ["SCENE", "配置"]
        if (kind === "timer") return ["TIMER", "終了"]
        if (osdKind === "mic") return ["MIC", "入力"]
        if (osdKind === "brightness") return ["BRIGHT", "輝度"]
        if (osdKind === "night") return ["NIGHT", "夜間"]
        if (osdKind === "game") return ["GAME", "遊戯"]
        return ["VOL", "音量"]
    }
    // the block lights up red for an urgent notice or the timer, goes
    // dark when something's muted or off
    readonly property color blockColour: kind === "timer" || (kind === "notif" && d.urgent) ? red
                                       : kind === "osd" && muted ? off
                                       : Qt.rgba(0.93, 0.94, 0.95, 0.92)
    readonly property color blockInk: kind === "osd" && muted ? dim : ink

    // ---- the block ----
    Rectangle {
        id: block
        x: 8; y: 8
        width: 78; height: parent.height - 16
        color: wi.blockColour
        Column {
            anchors.centerIn: parent
            spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: wi.label[0]; color: wi.blockInk; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
            Text { visible: wi.jpFont !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: wi.label[1]; color: wi.blockInk; font.family: wi.jpFont; font.pixelSize: 10 }
        }
    }

    // ---- what it says ----
    Item {
        id: info
        x: block.x + block.width + 12
        width: parent.width - x - 14
        height: parent.height

        // a notification, a game, a scene, a timer: two lines and a tag
        Column {
            visible: wi.kind !== "osd" && wi.kind !== "track"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - tag.width - 10
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: wi.kind === "notif" ? (wi.d.summary || wi.d.app || "")
                    : wi.kind === "game" ? String(wi.d.name || "Game")
                    : wi.kind === "scene" ? (wi.d.verb || "") + " “" + (wi.d.name || "") + "”"
                    : wi.kind === "timer" ? "TIME'S UP" : ""
                color: wi.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12
            }
            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: wi.kind === "notif" ? (wi.d.body || "").replace(/\s+/g, " ")
                    : wi.kind === "game" ? "played " + wi.app.fmtPlay(wi.d.secs || 0)
                                           + ((wi.d.week || 0) > (wi.d.secs || 0) + 59 ? "   " + wi.app.fmtPlay(wi.d.week) + " this week" : "")
                    : wi.kind === "scene" ? (wi.d.detail || "")
                    : wi.kind === "timer" ? "your " + (wi.d.len || "") + " timer has finished" : ""
                color: wi.dim; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Text {
            id: tag
            visible: wi.kind === "notif" || wi.kind === "timer"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: wi.kind === "timer" ? "[ OK ]" : String(wi.d.app || "").toUpperCase()
            color: wi.kind === "timer" ? wi.paper : wi.faint
            font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 10
            width: Math.min(implicitWidth, 110)
            elide: Text.ElideRight
        }

        // volume, the mic, brightness, night light, game mode
        Column {
            visible: wi.kind === "osd"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 6
            Item {
                width: parent.width; height: 16
                Text {
                    text: wi.osdKind === "mic" ? (wi.muted ? "MICROPHONE MUTED" : "MICROPHONE")
                        : wi.osdKind === "night" ? (wi.muted ? "NIGHT LIGHT OFF" : "NIGHT LIGHT ON")
                        : wi.osdKind === "game" ? (wi.muted ? "GAME MODE OFF" : "GAME MODE ON")
                        : wi.osdKind === "brightness" ? "BRIGHTNESS"
                        : wi.muted ? "MUTED" : "VOLUME"
                    color: wi.muted ? wi.dim : wi.paper
                    font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12
                }
                Text {
                    visible: !wi.toggleKind
                    anchors.right: parent.right
                    text: wi.muted ? "---" : ("00" + Math.round(wi.v * 100)).slice(-3) + "%"
                    color: wi.paper; font.family: Theme.font; font.pixelSize: 12
                }
            }
            Row {
                visible: !wi.toggleKind
                spacing: 2
                Repeater {
                    model: 32
                    delegate: Rectangle {
                        required property int index
                        width: (info.width - 31 * 2) / 32; height: 8
                        color: !wi.muted && index < Math.round(wi.v * 32)
                               ? (wi.osdKind === "brightness" ? wi.second : wi.osdKind === "mic" ? wi.second : wi.accent)
                               : wi.off
                    }
                }
            }
        }

        // the next song: its cover, greyed and scanned, then the song
        Item {
            visible: wi.kind === "track"
            anchors.fill: parent
            Rectangle {
                id: cover
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40
                color: Qt.rgba(1, 1, 1, 0.04)
                clip: true
                Image {
                    id: art
                    anchors.fill: parent
                    source: wi.kind === "track" ? (wi.d.art || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 96
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    saturation: -0.65
                    visible: art.status === Image.Ready
                }
                Column {
                    visible: art.status === Image.Ready
                    Repeater { model: 14; delegate: Item { width: 40; height: 3; Rectangle { width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.3) } } }
                }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
            }
            Column {
                x: cover.width + 12
                width: parent.width - x - 30
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: wi.d.title || ""; color: wi.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
                Text { width: parent.width; visible: text !== ""; elide: Text.ElideRight; textFormat: Text.PlainText; text: wi.d.artist || ""; color: wi.dim; font.family: Theme.font; font.pixelSize: 11 }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: [10, 16, 7, 13]
                    delegate: Rectangle { required property var modelData; anchors.bottom: parent.bottom; width: 3; height: modelData; color: wi.accent }
                }
            }
        }
    }
}
