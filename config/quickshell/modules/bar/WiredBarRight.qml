import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.modules.plugins
import qs.services

// The right pill's contents in the Wired look (Settings > Theme > Look):
// short labels with their values (VOL, NET, BAT, HUD, BELL), a running
// timer, recording and the 30 s replay when they're on, the tray, then the
// clock and MENU as light blocks like a window's title bar.  Same data and
// actions as the standard pill: a click opens quick settings, right-click
// on VOL mutes, the wheel on VOL turns it up and down.
Row {
    id: wr
    property var app
    property var win                     // the window, for the tray's menus
    spacing: 12
    height: 24

    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color red: app.cRed
    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color ink: "#0a0c0e"
    readonly property var sink: Audio.sink

    // a label and its value; clicks and the wheel go to the caller
    component Pair: Item {
        id: pr
        property string label: ""
        property string value: ""
        property color valueColour: wr.paper
        property color labelColour: wr.accent
        signal clicked(var m)
        signal wheeled(var w)
        width: row.implicitWidth + 8; height: 22
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle { anchors.fill: parent; color: hov.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent" }
        HoverHandler { id: hov }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Text { text: pr.label; color: pr.labelColour; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
            Text { text: pr.value; color: pr.valueColour; font.family: Theme.font; font.pixelSize: 11 }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: m => pr.clicked(m)
            onWheel: w => pr.wheeled(w)
        }
    }
    // a light block like a window's title bar
    component Block: Rectangle {
        id: bk
        property bool lit: false
        signal clicked()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        height: 22
        color: lit ? wr.accent : bkHov.hovered ? "#ffffff" : Qt.rgba(0.93, 0.94, 0.95, 0.92)
        HoverHandler { id: bkHov }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bk.clicked() }
    }

    PluginBarItems { app: wr.app; side: "right"; anchors.verticalCenter: parent.verticalCenter }

    // a running timer or stopwatch
    Rectangle {
        visible: wr.app.timerOn || wr.app.swOn
        anchors.verticalCenter: parent.verticalCenter
        width: tT.implicitWidth + 16; height: 22
        color: wr.app.timerOn && !wr.app.timerPaused && wr.app.timerLeft <= 10 ? wr.red : wr.accent
        Text {
            id: tT
            anchors.centerIn: parent
            text: (wr.app.timerOn ? (wr.app.timerPaused ? "PAUSE " : "TIMER ") : "SW ")
                  + (wr.app.timerOn ? wr.app.fmtDur(wr.app.timerPaused ? wr.app.timerHeld : wr.app.timerLeft)
                                    : wr.app.fmtDur(wr.app.swMs / 1000))
            color: wr.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wr.app.quickShown = !wr.app.quickShown }
    }
    // recording: a red block with its time; click to stop
    Rectangle {
        visible: Recorder.recording
        anchors.verticalCenter: parent.verticalCenter
        width: recT.implicitWidth + 16; height: 22
        color: wr.red
        Text { id: recT; anchors.centerIn: parent; text: "REC " + Recorder.elapsed; color: wr.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Recorder.stop() }
    }
    // the 30 s replay: click to save the last 30 seconds
    Pair {
        visible: Recorder.replaying
        label: "R30"; value: "SAVE"
        onClicked: Recorder.saveClip()
    }
    // volume: click for quick settings, right-click mutes, the wheel turns it
    Pair {
        readonly property bool muted: wr.sink?.audio?.muted ?? false
        readonly property int vol: Math.round((wr.sink?.audio?.volume ?? 0) * 100)
        label: "VOL"
        value: muted ? "MUTE" : ("00" + vol).slice(-3)
        valueColour: muted ? wr.dim : wr.paper
        onClicked: m => {
            const a = wr.sink?.audio
            if (m.button === Qt.RightButton) { if (a) a.muted = !a.muted }
            else wr.app.quickShown = !wr.app.quickShown
        }
        onWheeled: w => {
            const a = wr.sink?.audio
            if (a) a.volume = Math.max(0, Math.min(1, a.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
        }
    }
    // the network
    Pair {
        visible: wr.app.barNet
        label: "NET"
        value: wr.app.netKind === "wifi" ? "WIFI" : wr.app.netKind === "ethernet" ? "LAN" : "DOWN"
        valueColour: wr.app.netKind !== "" ? wr.paper : wr.second
        onClicked: wr.app.quickShown = !wr.app.quickShown
    }
    // the battery (laptops)
    Pair {
        visible: Battery.present
        label: "BAT"
        value: Battery.percent + "%" + (Battery.charging ? "+" : "")
        valueColour: Battery.low ? wr.red : wr.paper
        onClicked: wr.app.quickShown = !wr.app.quickShown
    }
    // the game overlay: click shows or hides it, right-click its settings
    Pair {
        visible: wr.app.gameHud !== "off"
        label: "HUD"
        value: wr.app.cfg.gameHudHidden !== true ? "ON" : "OFF"
        valueColour: wr.app.cfg.gameHudHidden !== true ? wr.paper : wr.dim
        onClicked: m => {
            if (m.button === Qt.RightButton) { wr.app.settingsPage = 25; wr.app.settingsShown = true }
            else wr.app.setting("gameHudHidden", wr.app.cfg.gameHudHidden !== true)
        }
    }
    // notifications
    Pair {
        label: "BELL"
        value: wr.app.dnd ? "DND" : ("0" + Math.min(99, wr.app.notifUnseen)).slice(-2)
        valueColour: wr.app.notifUnseen > 0 && !wr.app.dnd ? wr.accent : wr.dim
        onClicked: wr.app.quickShown = !wr.app.quickShown
    }
    // the tray
    Row {
        visible: SystemTray.items.values.length > 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: SystemTray.items
            delegate: Rectangle {
                id: trayItem
                required property var modelData
                width: 22; height: 22
                color: trHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                HoverHandler { id: trHov }
                IconImage { anchors.centerIn: parent; implicitSize: 15; source: trayItem.modelData.icon }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m => {
                        const it = trayItem.modelData
                        if (m.button === Qt.LeftButton && !it.onlyMenu) it.activate()
                        else if (m.button === Qt.MiddleButton) it.secondaryActivate()
                        else if (it.hasMenu) {
                            const p = trayItem.mapToItem(null, 0, trayItem.height + 6)
                            it.display(wr.win, Math.round(p.x), Math.round(p.y))
                        } else it.secondaryActivate()
                    }
                }
            }
        }
    }
    // the clock and the date: quick settings
    Block {
        width: clockRow.implicitWidth + 18
        onClicked: wr.app.quickShown = !wr.app.quickShown
        Row {
            id: clockRow
            anchors.centerIn: parent
            spacing: 10
            Text {
                text: wr.app.cfg.clock24h === true
                      ? Qt.formatDateTime(wr.app.now, "HH:mm" + (wr.app.cfg.clockSeconds === true ? ":ss" : ""))
                      : Qt.formatDateTime(wr.app.now, "h:mm" + (wr.app.cfg.clockSeconds === true ? ":ss" : "") + " AP")
                color: wr.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12
            }
            Text {
                visible: wr.app.cfg.clockDate !== false
                text: Qt.formatDateTime(wr.app.now, "yyyy.MM.dd ddd").toUpperCase()
                color: Qt.rgba(0.24, 0.25, 0.27, 1); font.family: Theme.font; font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    // the menu: quick settings
    Block {
        width: menuT.implicitWidth + 18
        lit: wr.app.quickShown
        onClicked: wr.app.quickShown = !wr.app.quickShown
        Text { id: menuT; anchors.centerIn: parent; text: wr.app.quickShown ? "CLOSE" : "MENU"; color: wr.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
    }
}
