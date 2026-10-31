import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.services

// The Wired lock screen (Settings > Lock screen > Style), after the
// computer screens of late-90s anime: a heavy clock whose colour layers
// sit slightly out of register, overlapping terminal windows (a turning
// wireframe globe with your address on it, a trace of the processor, the
// machine's state, the password), a column of hex running up the screen,
// Japanese labels, and film grain with fine interlace lines over it all.
// Nothing glows or flashes: the globe turns, the trace and the hex run, the
// lines decode as it locks and the clock's digits glitch as they change,
// and all of it holds still once the screen's left alone (awake).
// Colours follow the wallpaper (the theme's main and second colours).  The
// Japanese shows only when a Japanese font is installed (the installer
// adds IPAex); without one the English stands alone.
Item {
    id: wired
    property var app
    property var lock
    property real enter: 0
    property bool awake: true
    // the way out once the password's right (0 to 1, LockView): the
    // initialization sequence (LockWiredBoot), this many seconds long.
    // Once it's faded all the way in, the screen under it is let go of
    // (so it doesn't show through as everything fades to the desktop).
    property real leave: 0
    readonly property real bootLength: (lock && lock.wiredOutMs ? lock.wiredOutMs : 3100) / 1000
    readonly property bool booted: leave * bootLength >= 0.4
    property color okColour: "#4ade80"
    property color failColour: "#f87171"
    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color paper: "#eceef2"

    // ---- Japanese, when there's a font for it ----
    readonly property var families: Qt.fontFamilies()
    function firstOf(list) {
        for (const f of list) if (families.indexOf(f) !== -1) return f
        return ""
    }
    readonly property string jpSans: firstOf(["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP",
                                              "Source Han Sans", "IPAGothic", "VL Gothic", "TakaoGothic"])
    readonly property string jpSerif: firstOf(["IPAexMincho", "Noto Serif CJK JP", "Noto Serif JP", "Source Han Serif JP",
                                               "Source Han Serif", "IPAMincho"]) || jpSans
    readonly property bool jp: jpSans !== ""

    // ---- the machine: name, kernel and address, read once as it locks ----
    property string host: ""
    property string kernel: ""
    property string addr: ""
    // (and for the initialization sequence's log)
    property string etherVersion: ""
    property string hyprVersion: ""
    property string qsVersion: ""
    readonly property string lockedAt: Qt.formatTime(new Date(), "hh:mm:ss")
    // uptime the terminal way: "up 1 week, 2 days, 3 hours, 5 minutes"
    // becomes "9d 03h 05m", short enough for its window
    function shortUptime(s) {
        const n = unit => { const m = String(s).match(new RegExp("(\\d+)\\s+" + unit)); return m ? parseInt(m[1]) : 0 }
        const d = n("year") * 365 + n("week") * 7 + n("day"), h = n("hour"), m = n("minute")
        const two = v => (v < 10 ? "0" : "") + v
        if (d > 0) return d + "d " + two(h) + "h " + two(m) + "m"
        if (h > 0) return h + "h " + two(m) + "m"
        return m + "m"
    }
    Process {
        running: true
        command: ["sh", "-c",
            'echo "host=$(cat /etc/hostname 2>/dev/null)"; echo "kernel=$(uname -r)"; ' +
            'echo "addr=$(ip -4 -o route get 1.1.1.1 2>/dev/null | sed -n "s/.* src \\([0-9.]*\\).*/\\1/p")"; ' +
            'echo "ether=$(head -1 "$1" 2>/dev/null)"; ' +
            'echo "hypr=$(hyprctl version 2>/dev/null | sed -n "1s/^Hyprland \\([^ ]*\\).*/\\1/p")"; ' +
            'echo "qs=$(qs --version 2>/dev/null | head -1 | grep -o "[0-9][0-9.]*" | head -1)"',
            "sh", Quickshell.shellPath("VERSION")]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i < 0) continue
                    const k = line.slice(0, i), v = line.slice(i + 1).trim()
                    if (k === "host") wired.host = v
                    else if (k === "kernel") wired.kernel = v.split("-")[0]
                    else if (k === "addr") wired.addr = v
                    else if (k === "ether") wired.etherVersion = v
                    else if (k === "hypr") wired.hyprVersion = v.replace(/^v/, "")
                    else if (k === "qs") wired.qsVersion = v
                }
            }
        }
    }

    // ---- a little darker than the other styles, for the windows ----
    Rectangle { anchors.fill: parent; color: "#06080a"; opacity: 0.35; visible: !wired.booted }

    // ---- the layout, drawn for 1920 x 1080 and scaled to the screen ----
    Item {
        id: stage
        visible: !wired.booted
        width: 1920; height: 1080
        anchors.centerIn: parent
        scale: Math.min(wired.width / 1920, wired.height / 1080)
        // the window last picked up is on top
        property int topZ: 10

        // header
        Row {
            x: 150; y: 186
            spacing: 22
            LockDecode {
                go: wired.enter > 0.3
                target: "ETHER // SESSION LOCKED"
                color: Qt.rgba(1, 1, 1, 0.78)
                font.family: Theme.font
                font.pixelSize: 15
            }
            Text {
                visible: wired.jp
                text: "ロック中"
                color: wired.accent
                font.family: wired.jpSans
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ---- the clock: three copies, red and cyan slightly out of
        // register under the white, like an old print, on an old tube: it
        // flickers a little, a hum bar rolls down through the digits, fine
        // scan lines cross them, and now and then the picture slips
        // sideways.  The tube rests with the screen (awake). ----
        Item {
            id: clock
            x: 150; y: 222
            readonly property string time: wired.app.cfg.clock24h === true ? Qt.formatTime(wired.app.now, "HH:mm")
                                          : Qt.formatTime(wired.app.now, "h:mm AP").split(" ")[0]
            property string shown: ""
            property real split: 5
            property real jitter: 0
            property int steps: 0
            width: face.width * 0.72
            height: face.height

            readonly property bool live: wired.awake && wired.visible
            // the flicker: mostly a faint waver, once in a while a small dip
            property real flick: 1
            opacity: flick
            Timer {
                interval: 70; repeat: true; running: clock.live
                onTriggered: clock.flick = Math.random() < 0.035 ? 0.8 + Math.random() * 0.06 : 0.95 + Math.random() * 0.05
                onRunningChanged: if (!running) clock.flick = 1
            }
            // the slip: a sideways jolt for a moment, every few seconds
            property real hsync: 0
            Timer {
                interval: 4000; repeat: true; running: clock.live
                onTriggered: {
                    interval = 3500 + Math.random() * 6000
                    clock.hsync = (Math.random() < 0.5 ? -1 : 1) * (3 + Math.random() * 4)
                    slipBack.restart()
                }
            }
            Timer { id: slipBack; interval: 70; onTriggered: clock.hsync = 0 }
            function scramble(t) {
                let out = ""
                for (const ch of t) out += (ch >= "0" && ch <= "9" && Math.random() < 0.6) ? String(Math.floor(Math.random() * 10)) : ch
                return out
            }
            // a change (and the first showing) glitches for a moment
            onTimeChanged: { steps = 5; glitch.restart() }
            Component.onCompleted: { shown = time; steps = 6; glitch.restart() }
            Timer {
                id: glitch
                interval: 55; repeat: true
                onTriggered: {
                    if (clock.steps-- > 0) {
                        clock.shown = clock.scramble(clock.time)
                        clock.split = 5 + Math.random() * 12
                        clock.jitter = (Math.random() - 0.5) * 16
                    } else {
                        clock.shown = clock.time
                        clock.split = 5
                        clock.jitter = 0
                        stop()
                    }
                }
            }
            Repeater {
                model: [ { d: -1, c: Qt.rgba(1, 0.27, 0.24, 0.5) }, { d: 1, c: Qt.rgba(0.24, 0.78, 0.9, 0.5) }, { d: 0, c: "#eef0f3" } ]
                delegate: Text {
                    required property var modelData
                    x: clock.hsync + modelData.d * clock.split + (modelData.d === 0 ? 0 : clock.jitter)
                    text: clock.shown
                    color: modelData.c
                    font.family: Theme.uiFont
                    font.weight: Font.Black
                    font.pixelSize: 300
                    font.letterSpacing: -6
                    transform: Scale { xScale: 0.72 }
                }
            }
            // the hum bar: the digits dimmer in a band rolling slowly down,
            // softer toward its edges
            Item {
                id: hum
                visible: clock.live
                width: clock.width + 60; height: clock.height
                property real mid: -60
                NumberAnimation on mid {
                    from: -60; to: clock.height + 60
                    duration: 5200; loops: Animation.Infinite
                    running: clock.live
                }
                Repeater {
                    model: [ { h: 120, dim: 0.93 }, { h: 84, dim: 0.86 }, { h: 52, dim: 0.79 }, { h: 24, dim: 0.73 } ]
                    delegate: Item {
                        required property var modelData
                        y: hum.mid - modelData.h / 2
                        width: hum.width; height: modelData.h
                        clip: true
                        Text {
                            x: clock.hsync
                            y: -parent.y
                            text: clock.shown
                            color: Qt.rgba(0.933 * modelData.dim, 0.941 * modelData.dim, 0.953 * modelData.dim, 1)
                            font.family: Theme.uiFont
                            font.weight: Font.Black
                            font.pixelSize: 300
                            font.letterSpacing: -6
                            transform: Scale { xScale: 0.72 }
                        }
                    }
                }
            }
            // scan lines: dark lines every third pixel, on the digits only
            // (the lines, cut out by the digits' shape)
            Column {
                id: scanLines
                width: clock.width + 40; height: clock.height
                Repeater {
                    model: Math.ceil(clock.height / 3)
                    delegate: Item {
                        width: scanLines.width; height: 3
                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.32) }
                    }
                }
            }
            Item {
                id: scanShape
                width: scanLines.width; height: clock.height
                Text {
                    x: clock.hsync
                    text: clock.shown
                    color: "white"
                    font.family: Theme.uiFont
                    font.weight: Font.Black
                    font.pixelSize: 300
                    font.letterSpacing: -6
                    transform: Scale { xScale: 0.72 }
                }
            }
            ShaderEffectSource { id: scanTex; sourceItem: scanLines; hideSource: true; visible: false; width: scanLines.width; height: scanLines.height }
            ShaderEffectSource { id: shapeTex; sourceItem: scanShape; hideSource: true; visible: false; width: scanShape.width; height: scanShape.height }
            MultiEffect {
                width: scanLines.width; height: clock.height
                source: scanTex
                maskEnabled: true
                maskSource: shapeTex
                maskThresholdMin: 0.4
                maskSpreadAtMin: 0.2
                autoPaddingEnabled: false
            }
            Text {
                id: face
                visible: false
                text: clock.time
                font.family: Theme.uiFont
                font.weight: Font.Black
                font.pixelSize: 300
                font.letterSpacing: -6
            }
        }

        // date, address, and the same in Japanese
        Column {
            x: 150
            y: clock.y + clock.height - 18
            spacing: 6
            LockDecode {
                go: wired.enter > 0.45
                target: Qt.formatDate(wired.app.now, "yyyy.MM.dd  ddd").toUpperCase() + (wired.addr ? "   " + wired.addr : "")
                color: Qt.rgba(1, 1, 1, 0.84)
                font.family: Theme.font
                font.pixelSize: 15
            }
            Text {
                visible: wired.jp
                text: ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][wired.app.now.getDay()]
                      + "   " + (wired.addr ? "接続中" : "未接続")
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: wired.jpSans
                font.pixelSize: 15
            }
        }

        // down the left edge: awaiting authentication
        Column {
            visible: wired.jp
            x: 70; y: 300
            spacing: 2
            Repeater {
                model: ["認", "証", "待", "機", "中"]
                delegate: Text {
                    required property string modelData
                    text: modelData
                    color: Qt.rgba(wired.accent.r, wired.accent.g, wired.accent.b, 0.8)
                    font.family: wired.jpSans
                    font.pixelSize: 15
                }
            }
        }
        Rectangle {
            visible: wired.jp
            x: 92; y: 296; width: 1; height: 5 * 22 + 6
            color: Qt.rgba(wired.accent.r, wired.accent.g, wired.accent.b, 0.45)
        }

        // ---- NODE: a wireframe globe with you on it ----
        // You're pinned where Settings > Weather has your city (nothing is
        // looked up: no location set, no pin on a place, just the
        // address).  The globe sways slowly either side of your meridian,
        // so the pin stays in view, with the place, its coordinates and the
        // address beside it.
        WiredWindow {
            x: 1040; y: 120; width: 380; height: 350
            title: "NODE"; jp: "接続"; showJp: wired.jp
            spots: wired.lock.wiredSpots || null
            onRaised: z = ++stage.topZ
            Item {
                id: node
                anchors.fill: parent
                readonly property bool placed: Weather.wxHasPlace
                readonly property real lat: placed ? Weather.wxLat : 0
                readonly property real lon: placed ? Weather.wxLon : 0
                readonly property real rad: 128
                readonly property real cx: width / 2
                readonly property real cy: height / 2 - 4
                readonly property real tilt: 22 * Math.PI / 180
                // how far the globe has swung, either side of your meridian
                property real phase: 0
                readonly property real facing: (90 + 35 * Math.sin(phase)) * Math.PI / 180
                Timer {
                    interval: 50; repeat: true
                    running: wired.awake && wired.visible
                    onTriggered: node.phase = (node.phase + 0.01) % (2 * Math.PI)
                }
                // where a point of the globe lands in the window
                function at(latDeg, lonRad) {
                    const la = latDeg * Math.PI / 180
                    const x = rad * Math.cos(la) * Math.cos(lonRad), y = rad * Math.sin(la), z = rad * Math.cos(la) * Math.sin(lonRad)
                    return Qt.point(cx + x, cy - (y * Math.cos(tilt) - z * Math.sin(tilt)))
                }
                // (node.: the clock has a "face" too)
                readonly property point pin: node.at(node.lat, node.facing)
                onFacingChanged: globe.requestPaint()

                Canvas {
                    id: globe
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.lineWidth = 1
                        // latitudes, in the main colour
                        ctx.strokeStyle = Qt.rgba(wired.accent.r, wired.accent.g, wired.accent.b, 0.6)
                        for (let la = -60; la <= 60; la += 30) {
                            ctx.beginPath()
                            for (let a = 0; a <= 360; a += 6) {
                                const p = node.at(la, a * Math.PI / 180)
                                if (a === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y)
                            }
                            ctx.stroke()
                        }
                        // meridians, every 20 degrees from yours
                        for (let k = 0; k < 9; k++) {
                            ctx.strokeStyle = k === 0 && node.placed ? Qt.rgba(wired.second.r, wired.second.g, wired.second.b, 0.55)
                                                                      : Qt.rgba(1, 1, 1, 0.26)
                            const lo = node.facing + k * 20 * Math.PI / 180
                            ctx.beginPath()
                            for (let a = -90; a <= 270; a += 6) {
                                const p = node.at(a <= 90 ? a : 180 - a, a <= 90 ? lo : lo + Math.PI)
                                if (a === -90) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y)
                            }
                            ctx.stroke()
                        }
                        // you
                        const p = node.pin
                        ctx.strokeStyle = wired.second
                        ctx.lineWidth = 2
                        ctx.beginPath(); ctx.arc(p.x, p.y, 5, 0, 2 * Math.PI); ctx.stroke()
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(p.x - 11, p.y); ctx.lineTo(p.x - 7, p.y); ctx.moveTo(p.x + 7, p.y); ctx.lineTo(p.x + 11, p.y)
                        ctx.moveTo(p.x, p.y - 11); ctx.lineTo(p.x, p.y - 7); ctx.moveTo(p.x, p.y + 7); ctx.lineTo(p.x, p.y + 11); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(p.x + 6, p.y - 6); ctx.lineTo(label.x - 4, label.y + label.height / 2); ctx.stroke()
                    }
                }
                // the place, its coordinates and the address, beside the pin
                // (kept inside the window)
                Column {
                    id: label
                    x: Math.min(node.width - width - 8, node.pin.x + 46)
                    y: Math.max(6, node.pin.y - 58)
                    spacing: 1
                    Text {
                        text: node.placed ? String(Weather.wxPlace).split(",")[0].toUpperCase() : "NO LOCATION"
                        color: wired.second
                        font.family: Theme.font
                        font.weight: Font.Bold
                        font.pixelSize: 12
                    }
                    Text {
                        visible: node.placed
                        text: Math.abs(node.lat).toFixed(2) + (node.lat >= 0 ? "N  " : "S  ")
                              + Math.abs(node.lon).toFixed(2) + (node.lon >= 0 ? "E" : "W")
                        color: Qt.rgba(wired.second.r, wired.second.g, wired.second.b, 0.8)
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    Text {
                        text: wired.addr || "no address"
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }
            Text {
                x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                text: (wired.host ? "HOST " + wired.host.toUpperCase() : "") + (wired.addr ? "   LINK UP" : "   NO LINK")
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        // ---- SYS: the machine's state ----
        WiredWindow {
            x: 1470; y: 120; width: 330; height: 250
            title: "SYS"; jp: "状態"; showJp: wired.jp
            spots: wired.lock.wiredSpots || null
            onRaised: z = ++stage.topZ
            Column {
                x: 12; y: 12
                spacing: 6
                Repeater {
                    // (the names only: each value is worked out in its row,
                    // so a change updates that row instead of rebuilding all)
                    model: ["HOST", "USER", "KERNEL", "UPTIME", "BATT", "MAIL", "NET", "LOCK"]
                    delegate: Row {
                        required property string modelData
                        required property int index
                        readonly property string value: {
                            switch (modelData) {
                            case "HOST": return wired.host || "-"
                            case "USER": return Quickshell.env("USER") || "-"
                            case "KERNEL": return wired.kernel || "-"
                            case "UPTIME": return wired.app.uptimeText ? wired.shortUptime(wired.app.uptimeText) : "-"
                            case "BATT": return Battery.present ? Battery.percent + "%" : "mains"
                            case "MAIL": return Notifications.notifUnseen > 0 ? Notifications.notifUnseen + " unread" : "none"
                            case "NET": return wired.addr ? "up" : "down"
                            default: return wired.lockedAt
                            }
                        }
                        spacing: 0
                        Text {
                            width: 98
                            text: modelData
                            color: wired.accent
                            font.family: Theme.font
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        LockDecode {
                            go: wired.enter > 0.5 + index * 0.04
                            quietUpdates: true
                            duration: 500
                            target: value
                            // stops at the window's edge (a long kernel or host name)
                            width: 330 - 12 - 98 - 14
                            elide: Text.ElideRight
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.family: Theme.font
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }

        // ---- SIGNAL: the processor, traced ----
        WiredWindow {
            x: 1300; y: 400; width: 500; height: 210
            title: "SIGNAL"; jp: "信号"; showJp: wired.jp
            spots: wired.lock.wiredSpots || null
            onRaised: z = ++stage.topZ
            Canvas {
                id: trace
                anchors.fill: parent
                anchors.margins: 6
                anchors.bottomMargin: 26
                renderStrategy: Canvas.Cooperative
                readonly property var hist: System.cpuHist
                onHistChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.09)
                    ctx.lineWidth = 1
                    for (let k = 1; k < 8; k++) { ctx.beginPath(); ctx.moveTo(k * width / 8, 0); ctx.lineTo(k * width / 8, height); ctx.stroke() }
                    for (let k = 1; k < 5; k++) { ctx.beginPath(); ctx.moveTo(0, k * height / 5); ctx.lineTo(width, k * height / 5); ctx.stroke() }
                    const h = hist || []
                    if (h.length < 2) return
                    ctx.strokeStyle = wired.accent
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    const step = width / 59
                    const start = 60 - h.length
                    for (let i = 0; i < h.length; i++) {
                        const x = (start + i) * step
                        const y = height - 6 - (Math.max(0, Math.min(100, h[i])) / 100) * (height - 12)
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
            }
            Text {
                x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                text: "CPU " + wired.app.cpuPct + "%   MEM " + wired.app.memPct + "%"
                      + (wired.app.gpuOk ? "   GPU " + wired.app.gpuTemp + "°" : "")
                color: Qt.rgba(1, 1, 1, 0.7)
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        // ---- a column of hex ----
        // Each row rolls over to a new value now and then, the even rows
        // rolling up and the odd ones down, one row at a time.  On the
        // verdict, a block in its colour, green or red, rolls in over one
        // whole group of four in each row, a row after another from the
        // top, the group's characters showing dark inside it; they roll
        // back out when the verdict's gone.
        Item {
            id: hex
            x: 1060; y: 500; width: 210; height: 540
            readonly property int rows: 36
            readonly property real lh: 15
            function line() {
                const g = "0123456789ABCDEF"
                let out = ""
                for (let w = 0; w < 4; w++) {
                    if (w) out += " "
                    for (let i = 0; i < 4; i++) out += g.charAt(Math.floor(Math.random() * 16))
                }
                return out
            }
            // the ping: its colour, how far down it's got (in rows), and the
            // character each row lights
            property color pingColour: "white"
            property real pingPos: -1                   // how far down the blocks have got, in rows
            property var pingGroup: []                  // per row: which group of four
            property var pingWords: []                  // per row: that group's characters
            readonly property bool pinging: pingPos >= 0
            function ping(colour) {
                const g = [], w = []
                for (let r = 0; r < rows; r++) {
                    const k = Math.floor(Math.random() * 4)
                    const row = hexRows.itemAt(r)
                    g.push(k)
                    w.push(row ? row.value.substr(k * 5, 4) : "")
                }
                pingGroup = g
                pingWords = w
                pingColour = colour
                pingRun.restart()
            }
            // the blocks out again (they roll back), and the rows free to roll
            function unping() { pingRun.stop(); pingPos = -1 }
            // (timed, not stepped, so a busy machine still gets every row in)
            NumberAnimation {
                id: pingRun
                target: hex; property: "pingPos"
                from: 0; to: hex.rows; duration: 450
            }
            Connections {
                target: wired.lock
                function onResultChanged() {
                    if (wired.lock.result === "ok") hex.ping(wired.okColour)
                    else if (wired.lock.result === "fail") hex.ping(wired.failColour)
                    else hex.unping()
                }
            }

            Rectangle {
                x: 0; y: 0; width: 1; height: hex.rows * hex.lh
                color: Qt.rgba(wired.accent.r, wired.accent.g, wired.accent.b, 0.55)
            }
            Repeater {
                id: hexRows
                model: hex.rows
                delegate: Item {
                    id: row
                    required property int index
                    x: 14
                    y: index * hex.lh
                    width: hex.width - 14
                    height: hex.lh
                    clip: true
                    // fading in at the bottom and out at the top
                    opacity: 0.4 * Math.sin(Math.PI * (index + 0.5) / hex.rows)
                    readonly property int dir: index % 2 === 0 ? 1 : -1      // 1 rolls up, -1 down
                    property string value: hex.line()
                    property string prev: ""
                    property real t: 1                                       // 0 rolling, 1 settled
                    function roll() { prev = value; value = hex.line(); rolling.restart() }
                    NumberAnimation { id: rolling; target: row; property: "t"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                    Text {
                        visible: row.t < 1
                        y: -row.dir * row.t * hex.lh
                        text: row.prev
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    Text {
                        y: row.dir * (1 - row.t) * hex.lh
                        text: row.value
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
            }
            // the blocks, each rolling in over its row's group (from below
            // on the even rows, above on the odd, like the rows' own roll)
            TextMetrics { id: cell; font.family: Theme.font; font.pixelSize: 13; text: "0" }
            Repeater {
                model: hex.rows
                delegate: Item {
                    id: slot
                    required property int index
                    readonly property int dir: index % 2 === 0 ? 1 : -1
                    readonly property int g: hex.pingGroup[index] !== undefined ? hex.pingGroup[index] : 0
                    readonly property bool on: hex.pingPos > index
                    property real p: 0                      // 0 out, 1 in
                    onOnChanged: { (on ? rollIn : rollOut).restart() }
                    NumberAnimation { id: rollIn; target: slot; property: "p"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { id: rollOut; target: slot; property: "p"; to: 0; duration: 220; easing.type: Easing.InCubic }
                    x: 14 + g * 5 * cell.advanceWidth - 3
                    y: index * hex.lh + 1
                    width: 4 * cell.advanceWidth + 6
                    height: hex.lh - 1
                    clip: true
                    visible: p > 0
                    // softer at the column's faded ends, like the rows under it
                    opacity: 0.35 + 0.65 * Math.sin(Math.PI * (index + 0.5) / hex.rows)
                    Rectangle {
                        width: parent.width; height: parent.height
                        y: slot.dir * (1 - slot.p) * parent.height
                        color: hex.pingColour
                        Text {
                            anchors.centerIn: parent
                            text: hex.pingWords[slot.index] || ""
                            color: "#0a0c0e"
                            font.family: Theme.font
                            font.weight: Font.Bold
                            font.pixelSize: 13
                        }
                    }
                }
            }
            // a row at a time rolls over, while you're there (held still
            // while a ping runs, so it lights what's showing)
            Timer {
                interval: 170; repeat: true
                running: wired.awake && wired.visible && !hex.pinging
                onTriggered: {
                    const r = hexRows.itemAt(Math.floor(Math.random() * hex.rows))
                    if (r) r.roll()
                }
            }
        }

        // ---- AUTH: the password ----
        WiredWindow {
            id: auth
            x: 150; y: 720; width: 670; height: 136
            title: "AUTH"; jp: "認証"; showJp: wired.jp
            spots: wired.lock.wiredSpots || null
            onRaised: z = ++stage.topZ
            readonly property string result: wired.lock.result
            readonly property int count: Math.min(26, result !== "" ? wired.lock.heldLen : wired.lock.buffer.length)
            readonly property color mark: result === "ok" ? wired.okColour : result === "fail" ? wired.failColour : wired.accent
            // eased, so the marks roll in and out (and change colour) instead of popping
            property real shown: count
            Behavior on shown { NumberAnimation { duration: 60; easing.type: Easing.OutCubic } }
            property color markShown: mark
            Behavior on markShown { ColorAnimation { duration: 100 } }
            Row {
                x: 16; y: 12
                spacing: 10
                Text {
                    text: wired.lock.busy && auth.result === "" ? "verifying" : "password"
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                Text {
                    visible: wired.jp
                    text: wired.lock.busy && auth.result === "" ? "照合中" : "パスワード"
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.family: wired.jpSans
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            // what went wrong, or Caps Lock
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16
                y: 12
                text: wired.lock.message !== "" ? wired.lock.message.toUpperCase()
                    : wired.lock.capsLock ? "CAPS LOCK" : ""
                color: wired.lock.messageIsError ? wired.failColour : Qt.rgba(1, 1, 1, 0.7)
                font.family: Theme.font
                font.pixelSize: 13
            }
            Rectangle {
                id: field
                x: 16; y: 40
                width: parent.width - 32; height: 44
                color: Qt.rgba(0, 0, 0, 0.6)
                border.width: 1
                border.color: auth.result !== "" ? auth.markShown : Qt.rgba(1, 1, 1, 0.55)
                Behavior on border.color { ColorAnimation { duration: 100 } }
                transform: Translate { id: shakeT; x: 0 }
                Item {
                    id: marks
                    readonly property int step: 21              // a mark and the gap after it
                    x: 16; width: 26 * step; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: wired.lock.busy && auth.result === "" ? 0.45 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Repeater {
                        model: 26
                        // each mark rolls up into place as it's typed, and
                        // back down when it's deleted
                        delegate: Item {
                            id: mk
                            required property int index
                            readonly property real p: Math.max(0, Math.min(1, auth.shown - index))
                            x: index * marks.step
                            width: 12; height: 18
                            clip: true
                            visible: p > 0
                            Rectangle {
                                width: 12; height: 18
                                y: (1 - mk.p) * 18
                                opacity: 0.4 + 0.6 * mk.p
                                color: auth.markShown
                            }
                        }
                    }
                    // the cursor (steady), gliding along after the marks
                    Rectangle {
                        visible: auth.result === "" && !wired.lock.busy
                        x: auth.shown * marks.step
                        width: 2; height: 18
                        color: wired.paper
                    }
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
            }
            Connections { target: wired.lock; function onWrong() { shake.restart() } }
        }

        // standing by, like a title card
        Column {
            anchors.right: parent.right; anchors.rightMargin: 150
            y: 900
            spacing: 2
            Text {
                visible: wired.jp
                anchors.right: parent.right
                text: "待機"
                color: Qt.rgba(1, 1, 1, 0.85)
                font.family: wired.jpSerif
                font.weight: Font.Bold
                font.pixelSize: 64
            }
            Text {
                anchors.right: parent.right
                text: "STANDBY"
                color: wired.accent
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: 15
                font.letterSpacing: 1
            }
        }
    }

    // ---- the right password: a hard cut to an initialization sequence ----
    LockWiredBoot {
        anchors.fill: parent
        visible: wired.leave > 0
        wired: wired
        t: wired.leave * wired.bootLength
    }

    // ---- film grain and fine interlace lines, over everything ----
    Canvas {
        id: grainTile
        width: 256; height: 256
        visible: false
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            for (let i = 0; i < 2600; i++) {
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.03 + Math.random() * 0.05)
                ctx.fillRect(Math.floor(Math.random() * width), Math.floor(Math.random() * height), 1, 1)
            }
        }
        // (taken once: asking for the picture paints again, which would
        // ask again, and so on)
        property bool taken: false
        onPainted: if (!taken) { taken = true; grain.source = toDataURL("image/png") }
    }
    Image {
        id: grain
        anchors.fill: parent
        fillMode: Image.Tile
        smooth: false
    }
    Canvas {
        id: lineTile
        width: 4; height: 4
        visible: false
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.16)
            ctx.fillRect(0, 0, 4, 1)
            ctx.fillRect(0, 2, 4, 1)
        }
        property bool taken: false
        onPainted: if (!taken) { taken = true; lines.source = toDataURL("image/png") }
    }
    Image {
        id: lines
        anchors.fill: parent
        fillMode: Image.Tile
        smooth: false
    }
    // the edges darker, like a tube's
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: wired.width / 2; centerY: wired.height / 2
                centerRadius: Math.hypot(wired.width, wired.height) * 0.6
                focalX: wired.width / 2; focalY: wired.height / 2
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
            startX: 0; startY: 0
            PathLine { x: wired.width; y: 0 }
            PathLine { x: wired.width; y: wired.height }
            PathLine { x: 0; y: wired.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
