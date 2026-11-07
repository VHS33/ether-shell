import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.services

// Quick settings in the Wired look (Settings > Theme > Look), after the
// Wired lock: a title bar with the clock, the time out of register, the
// weather and the month, the next hours, timer and stopwatch, what's
// playing, the switches as blocks that fill when on (Wi-Fi and Bluetooth
// open their lists here), segmented sliders, the sound outputs,
// notifications as a log, and the buttons along the foot.  The same data
// and actions as the standard drawer.  It fills the window it's put in;
// the middle scrolls when it doesn't fit, the buttons stay put.
Item {
    id: wq
    property var app
    property var sink: null
    property var source: null
    signal close()

    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color red: app.cRed
    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color faint: Qt.rgba(0.38, 0.4, 0.44, 1)
    readonly property color ink: "#0a0c0e"
    readonly property color off: Qt.rgba(0.15, 0.165, 0.18, 1)
    readonly property var families: Qt.fontFamilies()
    readonly property string jpFont: ["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "IPAGothic"]
                                     .find(f => families.indexOf(f) >= 0) || ""
    readonly property bool jp: jpFont !== ""

    // which list is open under the switches: "wifi", "bt" or none
    property string picker: ""
    onVisibleChanged: if (!visible) picker = ""
    // notification groups opened to show all their messages
    property var openGroups: ({})
    function toggleGroup(name) {
        const g = Object.assign({}, openGroups)
        g[name] = !g[name]
        openGroups = g
    }

    // ---- small parts ----
    component Label: Row {
        property string en: ""
        property string ja: ""
        spacing: 8
        Text { text: parent.en; color: wq.accent; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        Text { visible: wq.jp && parent.ja !== ""; text: parent.ja; color: wq.dim; font.family: wq.jpFont; font.pixelSize: 11 }
    }
    component Rule: Rectangle { width: parent ? parent.width : 0; height: 1; color: Qt.rgba(1, 1, 1, 0.16) }
    // an outlined box with a word in it; "lit" fills it
    component Btn: Rectangle {
        id: b
        property string text: ""
        property bool lit: false
        property color tone: wq.paper
        signal clicked()
        width: bT.implicitWidth + 20; height: 22
        color: lit ? wq.accent : bHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        border.width: lit ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.3)
        HoverHandler { id: bHov }
        Text { id: bT; anchors.centerIn: parent; text: b.text; color: b.lit ? wq.ink : b.tone; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    // a switch: its square fills and the block lights when it's on
    component Switch: Rectangle {
        id: sw
        property string title: ""
        property string ja: ""
        property string sub: ""
        property bool on: false
        property bool chevron: false
        property bool expanded: false
        signal clicked()
        signal chevronClicked()
        height: 40
        color: on ? wq.accent : swHov.hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02)
        border.width: on ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        HoverHandler { id: swHov }
        Rectangle {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12
            color: sw.on ? wq.ink : "transparent"
            border.width: sw.on ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, 0.5)
        }
        Column {
            x: 32; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32 - (sw.chevron ? 30 : 8)
            spacing: 1
            Row {
                spacing: 6
                Text { text: sw.title; color: sw.on ? wq.ink : wq.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
                Text { visible: wq.jp && sw.ja !== ""; text: sw.ja; color: sw.on ? wq.ink : wq.dim; font.family: wq.jpFont; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: sw.sub.toUpperCase()
                color: sw.on ? Qt.rgba(0.04, 0.05, 0.06, 0.75) : wq.dim
                font.family: Theme.font; font.pixelSize: 10
            }
        }
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: sw.chevron ? 26 : 0
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.clicked()
        }
        // the arrow that opens its list
        Item {
            visible: sw.chevron
            anchors.right: parent.right
            width: 26; height: parent.height
            Rectangle { width: 1; height: parent.height - 10; anchors.verticalCenter: parent.verticalCenter; color: sw.on ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(1, 1, 1, 0.16) }
            Text { anchors.centerIn: parent; text: sw.expanded ? "v" : ">"; color: sw.on ? wq.ink : wq.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.chevronClicked() }
        }
    }
    // a segmented level: click or drag along it, the wheel nudges it; the
    // label (for sound) mutes
    component Level: Item {
        id: lv
        property string en: ""
        property string ja: ""
        property real v: 0
        property bool muted: false
        property color tone: wq.accent
        signal picked(real at)
        signal nudge(real by)
        signal labelClicked()
        width: parent ? parent.width : 0
        height: 18
        Item {
            width: 84; height: parent.height
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text { text: lv.en; color: lv.muted ? wq.dim : lv.tone; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
                Text { visible: wq.jp && lv.ja !== ""; text: lv.ja; color: wq.dim; font.family: wq.jpFont; font.pixelSize: 10 }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lv.labelClicked() }
        }
        Item {
            id: track
            x: 88; width: parent.width - 88 - 48; height: parent.height
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: 32
                    delegate: Rectangle {
                        required property int index
                        width: (track.width - 31 * 2) / 32; height: 8
                        color: !lv.muted && index < Math.round(lv.v * 32) ? lv.tone : wq.off
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: m => lv.picked(Math.max(0, Math.min(1, m.x / width)))
                onPositionChanged: m => { if (pressed) lv.picked(Math.max(0, Math.min(1, m.x / width))) }
                onWheel: w => lv.nudge(w.angleDelta.y > 0 ? 0.02 : -0.02)
            }
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: lv.muted ? "MUTE" : Math.round(lv.v * 100) + "%"
            color: lv.muted ? wq.dim : wq.paper
            font.family: Theme.font; font.pixelSize: 11
        }
    }

    // ---- the title bar: QUICK, the clock with seconds, the boxes close it ----
    Rectangle {
        id: titleBar
        width: parent.width; height: 22
        color: Qt.rgba(0.93, 0.94, 0.95, 0.9)
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text { text: "QUICK"; color: wq.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 13 }
            Text { visible: wq.jp; text: "操作"; color: wq.ink; font.family: wq.jpFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            anchors.right: boxes.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(wq.app.now, "HH:mm:ss")
            color: Qt.rgba(0.24, 0.25, 0.27, 1); font.family: Theme.font; font.pixelSize: 12
        }
        Row {
            id: boxes
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 3; delegate: Rectangle { width: 7; height: 7; color: "transparent"; border.width: 1; border.color: wq.ink } }
        }
        MouseArea { anchors.right: parent.right; width: 40; height: parent.height; cursorShape: Qt.PointingHandCursor; onClicked: wq.close() }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 3; anchors.topMargin: titleBar.height + 3
        color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
    }

    // ---- the middle, scrolling when it doesn't fit ----
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: titleBar.bottom; bottom: foot.top; topMargin: 4; bottomMargin: 18 }
        contentWidth: width
        contentHeight: col.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 16; y: 10
            width: flick.width - 32
            spacing: 12

            // the time, out of register, and the date (and the battery)
            Item {
                width: parent.width; height: 60
                Repeater {
                    model: [ { d: -2, c: Qt.rgba(1, 0.27, 0.24, 0.5) }, { d: 2, c: Qt.rgba(0.24, 0.78, 0.9, 0.5) }, { d: 0, c: wq.paper } ]
                    delegate: Text {
                        required property var modelData
                        x: modelData.d
                        text: wq.app.cfg.clock24h === true ? Qt.formatDateTime(wq.app.now, "HH:mm")
                                                            : Qt.formatDateTime(wq.app.now, "h:mm AP").split(" ")[0]
                        color: modelData.c
                        font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 54
                        transform: Scale { xScale: 0.72 }
                    }
                }
                TextMetrics {
                    id: timeM
                    font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 54
                    text: wq.app.cfg.clock24h === true ? Qt.formatDateTime(wq.app.now, "HH:mm")
                                                        : Qt.formatDateTime(wq.app.now, "h:mm AP").split(" ")[0]
                }
                Column {
                    x: Math.round(timeM.advanceWidth * 0.72) + 26; y: 6
                    spacing: 3
                    Text { text: Qt.formatDateTime(wq.app.now, "yyyy.MM.dd  ddd").toUpperCase() + (wq.app.cfg.clock24h === true ? "" : "  " + Qt.formatDateTime(wq.app.now, "AP")); color: wq.paper; font.family: Theme.font; font.pixelSize: 12 }
                    Text {
                        visible: wq.jp
                        text: ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][wq.app.now.getDay()]
                              + "   " + (wq.app.netKind !== "" ? "接続" : "未接続")
                        color: wq.dim; font.family: wq.jpFont; font.pixelSize: 12
                    }
                    Text {
                        visible: Battery.present
                        text: "BAT " + Battery.percent + "%" + (Battery.charging ? "  CHARGING" : "") + (Power.shown ? "  " + Power.name.toUpperCase() : "")
                        color: Battery.low ? wq.red : wq.faint; font.family: Theme.font; font.pixelSize: 10
                    }
                }
            }
            Rule {}

            // the weather and the month, side by side
            Item {
                width: parent.width
                height: Math.max(wx.implicitHeight, cal.implicitHeight)
                Column {
                    id: wx
                    width: 150
                    spacing: 4
                    Label { en: "WEATHER"; ja: "天気" }
                    Text {
                        visible: wq.app.wxOk
                        text: wq.app.wxTemp
                        color: wq.paper; font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 30
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: wq.app.wxOk ? String(wq.app.wxCond).toUpperCase() : "NO DATA"
                        color: wq.app.wxOk ? wq.paper : wq.dim
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        visible: wq.app.wxOk && wq.app.wxHi !== ""
                        text: "H " + wq.app.wxHi + "   L " + wq.app.wxLo
                        color: wq.dim; font.family: Theme.font; font.pixelSize: 11
                    }
                    Text {
                        visible: !wq.app.wxOk
                        width: parent.width; wrapMode: Text.WordWrap
                        text: wq.app.wxHasPlace ? "no weather yet" : "set a city in settings > weather"
                        color: wq.faint; font.family: Theme.font; font.pixelSize: 10
                    }
                }
                Column {
                    id: cal
                    x: 170
                    width: parent.width - 170
                    spacing: 4
                    readonly property var cells: {
                        const n = wq.app.now
                        const y = n.getFullYear(), mo = n.getMonth()
                        const lead = (new Date(y, mo, 1).getDay() - wq.app.calWeekStart + 7) % 7
                        const days = new Date(y, mo + 1, 0).getDate()
                        const pad = v => (v < 10 ? "0" : "") + v
                        const out = []
                        for (let i = 0; i < lead; i++) out.push({ d: "", key: "", dow: (i + wq.app.calWeekStart) % 7 })
                        for (let d = 1; d <= days; d++) {
                            const key = y + "-" + pad(mo + 1) + "-" + pad(d)
                            out.push({ d: d, key: key, today: d === n.getDate(), hol: wq.app.holidayOn(key) !== "",
                                       dow: (lead + d - 1 + wq.app.calWeekStart) % 7 })
                        }
                        return out
                    }
                    readonly property real cw: width / 7
                    Label { en: Qt.formatDateTime(wq.app.now, "MMMM yyyy").toUpperCase(); ja: (wq.app.now.getMonth() + 1) + "月" }
                    Row {
                        Repeater {
                            model: 7
                            delegate: Text {
                                required property int index
                                readonly property int dow: (index + wq.app.calWeekStart) % 7
                                width: cal.cw
                                horizontalAlignment: Text.AlignHCenter
                                text: ["S", "M", "T", "W", "T", "F", "S"][dow]
                                color: dow === 0 || dow === 6 ? wq.accent : wq.dim
                                font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 10
                            }
                        }
                    }
                    Grid {
                        columns: 7
                        rowSpacing: 1
                        Repeater {
                            model: cal.cells
                            delegate: Item {
                                id: dc
                                required property var modelData
                                width: cal.cw; height: 16
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 1
                                    visible: dc.modelData.today === true || dc.modelData.hol === true
                                    color: dc.modelData.today ? wq.accent : "transparent"
                                    border.width: dc.modelData.today ? 0 : 1
                                    border.color: wq.second
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: dc.modelData.d
                                    color: dc.modelData.today ? wq.ink : dc.modelData.hol ? wq.second
                                         : dc.modelData.dow === 0 || dc.modelData.dow === 6 ? wq.dim : wq.paper
                                    font.family: Theme.font; font.weight: dc.modelData.today ? Font.Bold : Font.Normal; font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }

            // the next hours, sideways
            Column {
                visible: wq.app.wxOk && wq.app.wxHours.length > 0
                width: parent.width
                spacing: 6
                Rule {}
                Label { en: "NEXT HOURS"; ja: "予報" }
                Flickable {
                    width: parent.width; height: 48
                    contentWidth: hrRow.implicitWidth
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    Row {
                        id: hrRow
                        spacing: 4
                        Repeater {
                            model: wq.app.wxHours
                            delegate: Rectangle {
                                id: hr
                                required property var modelData
                                width: 50; height: 48
                                color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: hr.modelData.time; color: wq.dim; font.family: Theme.font; font.pixelSize: 10 }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: hr.modelData.temp; color: wq.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: hr.modelData.rain >= 20 ? hr.modelData.rain + "%" : " "; color: wq.second; font.family: Theme.font; font.pixelSize: 9 }
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: w => { parent.contentX = Math.max(0, Math.min(parent.contentWidth - parent.width, parent.contentX - w.angleDelta.y)) }
                    }
                }
            }
            Rule {}

            // timer and stopwatch
            Item {
                width: parent.width; height: 52
                Column {
                    spacing: 6
                    Label { en: "TIMER"; ja: "タイマー" }
                    Row {
                        visible: !wq.app.timerOn
                        spacing: 6
                        Repeater {
                            model: [1, 5, 10, 25]
                            delegate: Btn { required property var modelData; text: modelData + "M"; onClicked: wq.app.startTimer(modelData * 60) }
                        }
                    }
                    Row {
                        visible: wq.app.timerOn
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wq.app.fmtDur(wq.app.timerPaused ? wq.app.timerHeld : wq.app.timerLeft)
                            color: wq.app.timerLeft <= 10 && !wq.app.timerPaused ? wq.red : wq.paper
                            font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 16
                        }
                        Btn { text: wq.app.timerPaused ? "RESUME" : "PAUSE"; onClicked: wq.app.timerPaused ? wq.app.resumeTimer() : wq.app.pauseTimer() }
                        Btn { text: "STOP"; tone: wq.second; onClicked: wq.app.cancelTimer() }
                    }
                }
                Column {
                    x: parent.width - 196
                    width: 196
                    spacing: 6
                    Label { en: "STOPWATCH"; ja: "計時" }
                    Row {
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 92
                            text: wq.app.fmtDur(wq.app.swMs / 1000) + "." + Math.floor((wq.app.swMs % 1000) / 100)
                            color: wq.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 16
                        }
                        Btn { text: wq.app.swRunning ? "||" : ">"; lit: true; onClicked: wq.app.swToggle() }
                        Btn { visible: wq.app.swOn && !wq.app.swRunning; text: "RESET"; onClicked: wq.app.swReset() }
                    }
                }
            }

            // what's playing: click it for the media card
            Column {
                visible: wq.app.player !== null
                width: parent.width
                spacing: 6
                Rule {}
                Label { en: "NOW PLAYING"; ja: "再生中" }
                Item {
                    width: parent.width; height: 36
                    Column {
                        id: npText
                        width: parent.width - 150
                        Text { width: parent.width; elide: Text.ElideRight; text: wq.app.player?.trackTitle || "Unknown track"; color: wq.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
                        Text { width: parent.width; elide: Text.ElideRight; text: wq.app.player?.trackArtist ?? ""; color: wq.dim; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    MouseArea { anchors.fill: npText; cursorShape: Qt.PointingHandCursor; onClicked: { wq.app.quickShown = false; wq.app.cardShown = true } }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Btn { text: "|<"; onClicked: { const p = wq.app.player; if (p) p.previous() } }
                        Btn {
                            text: wq.app.player?.playbackState === MprisPlaybackState.Playing ? "||" : ">"
                            lit: true
                            onClicked: { const p = wq.app.player; if (p && p.canTogglePlaying) p.togglePlaying() }
                        }
                        Btn { text: ">|"; onClicked: { const p = wq.app.player; if (p) p.next() } }
                    }
                }
            }
            Rule {}

            // the switches
            Label { en: "SWITCHES"; ja: "切替" }
            Grid {
                id: sws
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                readonly property real cellW: (width - 8) / 2
                Switch {
                    width: sws.cellW
                    readonly property bool isMuted: wq.sink?.audio?.muted ?? false
                    title: "SOUND"; ja: "音"
                    sub: isMuted ? "Muted" : Math.round((wq.sink?.audio?.volume ?? 0) * 100) + "%"
                    on: !isMuted
                    onClicked: { const a = wq.sink?.audio; if (a) a.muted = !a.muted }
                }
                Switch {
                    width: sws.cellW
                    readonly property bool isMuted: wq.source?.audio?.muted ?? false
                    title: "MIC"; ja: "マイク"
                    sub: isMuted ? "Muted" : "On"
                    on: !isMuted
                    onClicked: { const a = wq.source?.audio; if (a) a.muted = !a.muted }
                }
                Switch {
                    width: sws.cellW
                    readonly property var joined: wq.app.wifiList.find(n => n.active)
                    title: wq.app.wifiHas ? "WI-FI" : wq.app.netKind === "ethernet" ? "WIRED" : "NETWORK"; ja: "網"
                    sub: wq.app.wifiHas ? (!wq.app.wifiOn ? "Off" : joined ? joined.ssid : "Not connected")
                         : wq.app.netName !== "" ? wq.app.netName : "Not connected"
                    on: wq.app.wifiHas ? wq.app.wifiOn : wq.app.netKind !== ""
                    chevron: wq.app.wifiHas
                    expanded: wq.picker === "wifi"
                    onClicked: if (wq.app.wifiHas) wq.app.wifiToggle()
                    onChevronClicked: {
                        wq.picker = wq.picker === "wifi" ? "" : "wifi"
                        if (wq.picker === "wifi") wq.app.refreshWifi(true)
                    }
                }
                Switch {
                    width: sws.cellW
                    readonly property var linked: wq.app.btList.find(d => d.connected)
                    readonly property string btState: !BluetoothService.adapter ? "none"
                                                  : !BluetoothService.active && !wq.app.btHas ? "stopped" : "ready"
                    opacity: btState === "none" ? 0.45 : 1
                    title: "BLUETOOTH"; ja: "藍牙"
                    sub: btState === "none" ? "No adapter found"
                       : btState === "stopped" ? (BluetoothService.starting ? "Starting…"
                                                : BluetoothService.error !== "" ? BluetoothService.error
                                                : "Service off, tap to start")
                       : !wq.app.btOn ? "Off"
                       : linked ? linked.name + ((linked.battery ?? -1) >= 0 ? ", " + linked.battery + "%" : "") : "On"
                    on: btState === "ready" && wq.app.btOn
                    chevron: btState === "ready"
                    expanded: wq.picker === "bt"
                    onClicked: {
                        if (btState === "stopped") BluetoothService.start()
                        else if (btState === "ready") wq.app.btToggle()
                    }
                    onChevronClicked: {
                        wq.picker = wq.picker === "bt" ? "" : "bt"
                        if (wq.picker === "bt") { wq.app.refreshBt(); if (wq.app.btOn) wq.app.btScan() }
                    }
                }
                Switch { width: sws.cellW; title: "NIGHT LIGHT"; ja: "夜間"; sub: wq.app.nightLight ? "Warmer colours" : "Off"; on: wq.app.nightLight; onClicked: wq.app.toggleNight() }
                Switch { width: sws.cellW; title: "GAME MODE"; ja: "遊戯"; sub: wq.app.gameMode ? "Blur and animations off" : "Off"; on: wq.app.gameMode; onClicked: wq.app.toggleGameMode() }
                Switch { width: sws.cellW; title: "KEEP AWAKE"; ja: "覚醒"; sub: wq.app.keepAwake ? "Won't lock or sleep" : "Off"; on: wq.app.keepAwake; onClicked: wq.app.keepAwake = !wq.app.keepAwake }
                Switch { width: sws.cellW; title: "DO NOT DISTURB"; ja: "静音"; sub: wq.app.dnd ? "Popups hidden" : "Off"; on: wq.app.dnd; onClicked: wq.app.dnd = !wq.app.dnd }
                Switch {
                    width: sws.cellW
                    title: "SCREEN REC"; ja: "録画"
                    sub: !Recorder.available ? "Needs gpu-screen-recorder"
                       : Recorder.recording ? "Recording " + Recorder.elapsed
                       : Recorder.replaying ? "Starts 30 s back" : "Off"
                    on: Recorder.recording
                    onClicked: { if (!Recorder.available) return; wq.app.quickShown = false; Recorder.toggle() }
                }
                Switch {
                    width: sws.cellW
                    title: "REC 30S BACK"; ja: "遡及"
                    sub: !Recorder.available ? "Needs gpu-screen-recorder"
                       : Recorder.replaying ? "Recordings start 30 s earlier" : "Off"
                    on: Recorder.replaying
                    onClicked: if (Recorder.available) Recorder.setReplay(!Recorder.replaying)
                }
                Switch {
                    visible: Power.shown
                    width: sws.cellW
                    title: "POWER MODE"; ja: "電源"
                    sub: Power.name
                    on: false
                    onClicked: Power.cycle()
                }
            }

            // the Wi-Fi or Bluetooth list, opened from a switch's arrow
            Column {
                id: pick
                visible: wq.picker !== ""
                readonly property bool wifi: wq.picker === "wifi"
                width: parent.width
                spacing: 4
                Item {
                    width: parent.width; height: 20
                    Label { en: pick.wifi ? "WI-FI" : "BLUETOOTH"; ja: pick.wifi ? "無線" : "藍牙"; anchors.verticalCenter: parent.verticalCenter }
                    Btn {
                        anchors.right: parent.right
                        text: !pick.wifi && wq.app.btScanning ? "SCANNING" : "SCAN"
                        onClicked: pick.wifi ? wq.app.refreshWifi(true) : wq.app.btScan()
                    }
                }
                Text {
                    visible: pick.wifi ? !wq.app.wifiOn : !wq.app.btOn
                    text: pick.wifi ? "> wi-fi is off. click the switch to turn it on." : "> bluetooth is off. click the switch to turn it on."
                    color: wq.faint; font.family: Theme.font; font.pixelSize: 11
                }
                Text { visible: pick.wifi && wq.app.wifiError !== ""; width: parent.width; wrapMode: Text.WordWrap; text: wq.app.wifiError; color: wq.red; font.family: Theme.font; font.pixelSize: 11 }
                Text {
                    visible: pick.wifi ? wq.app.wifiOn && wq.app.wifiList.length === 0 : wq.app.btOn && wq.app.btList.length === 0
                    text: pick.wifi ? "> no networks found yet" : "> no devices yet. put yours in pairing mode."
                    color: wq.faint; font.family: Theme.font; font.pixelSize: 11
                }
                Repeater {
                    model: wq.picker === "" ? []
                         : pick.wifi ? (wq.app.wifiOn ? wq.app.wifiList.slice(0, 10) : [])
                         : (wq.app.btOn ? wq.app.btList.slice(0, 10) : [])
                    delegate: Column {
                        id: pr
                        required property var modelData
                        readonly property bool isWifi: pick.wifi
                        readonly property bool linked: isWifi ? modelData.active : modelData.connected
                        readonly property bool busy: isWifi ? wq.app.wifiBusy === modelData.ssid : wq.app.btBusy === modelData.mac
                        readonly property bool asking: isWifi && wq.app.wifiAskPw === modelData.ssid
                        width: pick.width
                        spacing: 4
                        Rectangle {
                            width: parent.width; height: 24
                            color: pr.linked ? Qt.rgba(wq.accent.r, wq.accent.g, wq.accent.b, 0.2) : prHov.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                            HoverHandler { id: prHov }
                            Text {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 150
                                elide: Text.ElideRight
                                text: (pr.linked ? "> " : "  ") + (pr.isWifi ? pr.modelData.ssid : pr.modelData.name)
                                color: pr.linked ? wq.paper : wq.dim
                                font.family: Theme.font; font.pixelSize: 12
                            }
                            Text {
                                anchors.right: sig.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                readonly property string batt: !pr.isWifi && (pr.modelData.battery ?? -1) >= 0 ? pr.modelData.battery + "%" : ""
                                text: pr.busy ? "CONNECTING" : pr.linked ? "CONNECTED" + (batt ? " " + batt : "")
                                    : !pr.isWifi && pr.modelData.paired ? "PAIRED" : pr.isWifi && pr.modelData.secure ? "KEY" : ""
                                color: pr.linked ? wq.accent : wq.faint
                                font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 10
                            }
                            Row {
                                id: sig
                                visible: pr.isWifi
                                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    model: 4
                                    delegate: Rectangle {
                                        required property int index
                                        anchors.bottom: parent.bottom
                                        width: 5; height: 4 + index * 3
                                        color: (pr.modelData.signal ?? 0) > index * 25 ? wq.accent : wq.off
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (pr.busy) return
                                    const d = pr.modelData
                                    if (pr.isWifi) { if (d.active) wq.app.wifiDisconnect(d.ssid); else wq.app.wifiConnect(d.ssid, "") }
                                    else { if (d.connected) wq.app.btDisconnect(d.mac); else wq.app.btConnect(d.mac, d.paired) }
                                }
                            }
                        }
                        // its password, when it asks for one
                        Row {
                            visible: pr.asking
                            onVisibleChanged: if (visible) pw.forceActiveFocus()
                            spacing: 8
                            Rectangle {
                                width: pick.width - 80; height: 26
                                color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.4)
                                TextInput {
                                    id: pw
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: wq.paper
                                    font.family: Theme.font; font.pixelSize: 12
                                    Keys.onReturnPressed: if (pw.text) wq.app.wifiConnect(pr.modelData.ssid, pw.text)
                                    Keys.onEnterPressed: if (pw.text) wq.app.wifiConnect(pr.modelData.ssid, pw.text)
                                    Keys.onEscapePressed: wq.app.wifiCancelPw()
                                    Text {
                                        visible: !pw.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "password for " + pr.modelData.ssid
                                        color: wq.faint; font.family: Theme.font; font.pixelSize: 11
                                    }
                                }
                            }
                            Btn { text: "JOIN"; lit: pw.text !== ""; onClicked: if (pw.text) wq.app.wifiConnect(pr.modelData.ssid, pw.text) }
                        }
                    }
                }
            }
            Rule {}

            // the levels: sound, the mic, the screens' brightness
            Column {
                width: parent.width
                spacing: 8
                Level {
                    en: "VOL"; ja: "音量"
                    v: wq.sink?.audio?.volume ?? 0
                    muted: wq.sink?.audio?.muted ?? false
                    onPicked: x => { const a = wq.sink?.audio; if (a) { a.volume = x; if (a.muted) a.muted = false } }
                    onNudge: by => { const a = wq.sink?.audio; if (a) a.volume = Math.max(0, Math.min(1, a.volume + by)) }
                    onLabelClicked: { const a = wq.sink?.audio; if (a) a.muted = !a.muted }
                }
                Level {
                    en: "MIC"; ja: "入力"
                    tone: wq.second
                    v: wq.source?.audio?.volume ?? 0
                    muted: wq.source?.audio?.muted ?? false
                    onPicked: x => { const a = wq.source?.audio; if (a) { a.volume = x; if (a.muted) a.muted = false } }
                    onNudge: by => { const a = wq.source?.audio; if (a) a.volume = Math.max(0, Math.min(1, a.volume + by)) }
                    onLabelClicked: { const a = wq.source?.audio; if (a) a.muted = !a.muted }
                }
                Level {
                    visible: wq.app.brightOk
                    en: "BRIGHT"; ja: "輝度"
                    v: wq.app.brightAvg / 100
                    onPicked: x => wq.app.setAllBright(100 * x)
                    onNudge: by => wq.app.setAllBright(wq.app.brightAvg + (by > 0 ? 5 : -5))
                }
            }

            // the sound outputs: the one in use is lit
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: Pipewire.nodes
                    delegate: Btn {
                        id: outB
                        required property var modelData
                        readonly property bool isOut: !!modelData && !!modelData.audio && modelData.isSink && !modelData.isStream
                        visible: isOut
                        width: isOut ? Math.min(implicitWidth, 200) : 0
                        text: isOut ? String(modelData?.nickname || modelData?.description || modelData?.name || "Output").toUpperCase() : ""
                        lit: modelData === wq.sink
                        onClicked: if (!lit) Pipewire.preferredDefaultAudioSink = outB.modelData
                    }
                }
            }
            Rule {}

            // notifications, as a log
            Item {
                width: parent.width; height: 22
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Label { en: "NOTIFY"; ja: "通知" }
                    Text { text: ("0" + Math.min(99, wq.app.notifCount)).slice(-2); color: wq.app.notifCount > 0 ? wq.paper : wq.dim; font.family: Theme.font; font.pixelSize: 11 }
                }
                Btn { visible: wq.app.notifCount > 0; anchors.right: parent.right; text: "CLEAR ALL"; onClicked: wq.app.clearNotifs() }
            }
            Text {
                visible: wq.app.notifCount === 0
                text: "> you're all caught up"
                color: wq.faint; font.family: Theme.font; font.pixelSize: 12
            }
            Repeater {
                model: wq.app.notifGroups
                delegate: Column {
                    id: grp
                    required property var modelData
                    readonly property bool open: wq.openGroups[modelData.app] === true
                    readonly property int more: modelData.items.length - 1
                    width: col.width
                    spacing: 4
                    // the app: its name, how many, open them all, clear them
                    Item {
                        width: parent.width; height: 18
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(grp.modelData.app || "App").toUpperCase(); color: wq.accent; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Text {
                                visible: grp.more > 0
                                text: grp.open ? "LESS" : "+" + grp.more + " MORE"
                                color: wq.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 10
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: wq.toggleGroup(grp.modelData.app) }
                            }
                            Text {
                                text: "x"
                                color: wq.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
                                MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: wq.app.dismissGroup(grp.modelData.app) }
                            }
                        }
                    }
                    Repeater {
                        model: grp.open ? grp.modelData.items : grp.modelData.items.slice(0, 1)
                        delegate: Item {
                            id: item
                            required property var modelData
                            required property int index
                            readonly property bool actionable: !modelData.saved
                            width: grp.width
                            height: nCol.implicitHeight + 6
                            Rectangle { width: 3; height: parent.height; color: item.index === 0 ? wq.accent : wq.faint }
                            Column {
                                id: nCol
                                x: 12; width: parent.width - 100
                                spacing: 2
                                Text { width: parent.width; elide: Text.ElideRight; text: item.modelData.summary || ""; color: wq.paper; font.family: Theme.font; font.pixelSize: 12; textFormat: Text.PlainText }
                                Text { visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: item.modelData.body || ""; color: wq.dim; font.family: Theme.font; font.pixelSize: 11; textFormat: Text.PlainText }
                            }
                            // when it came
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 20; anchors.top: parent.top; anchors.topMargin: 1
                                text: wq.app.notifWhen(item.modelData)
                                color: wq.dim; font.family: Theme.font; font.pixelSize: 10
                            }
                            MouseArea {
                                anchors.fill: nCol
                                cursorShape: item.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (item.actionable) { wq.app.quickShown = false; wq.app.invokeNotifAction(item.modelData.id, "default") }
                            }
                            Text {
                                anchors.right: parent.right; anchors.top: parent.top
                                text: "x"
                                color: wq.faint; font.family: Theme.font; font.pixelSize: 11
                                MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: wq.app.dismissNotif(item.modelData.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- the buttons along the foot ----
    Rectangle { x: 16; width: parent.width - 32; height: 1; anchors.bottom: foot.top; anchors.bottomMargin: 10; color: Qt.rgba(1, 1, 1, 0.16) }
    Row {
        id: foot
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        x: 16
        spacing: 6
        readonly property real bw: (wq.width - 32 - 5 * 6) / 6
        Repeater {
            model: [
                { t: "SHOT", a: "shot" }, { t: "PICK", a: "pick" }, { t: "WALL", a: "wall" },
                { t: "SET", a: "set" }, { t: "LOCK", a: "lock" }, { t: "PWR", a: "pwr" }
            ]
            delegate: Btn {
                required property var modelData
                width: foot.bw; height: 28
                text: modelData.t
                tone: modelData.a === "pwr" ? wq.second : wq.paper
                onClicked: {
                    const a = modelData.a
                    wq.app.quickShown = false
                    if (a === "shot") wq.app.run("sleep 0.4; $HOME/.local/bin/shot")
                    else if (a === "pick") wq.app.run("sleep 0.4; $HOME/.local/bin/pickcolor")
                    else if (a === "wall") { wq.app.settingsPage = 3; wq.app.settingsShown = true }
                    else if (a === "set") wq.app.settingsShown = true
                    else if (a === "lock") wq.app.run("sleep 0.3; \"$HOME/.local/bin/lock\" || loginctl lock-session")
                    else if (a === "pwr") wq.app.powerShown = true
                }
            }
        }
    }
}
