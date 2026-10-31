import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.services

// The Wired lock screen's way out: once the password's right, an
// initialization sequence, after the computer screens of late-90s anime
// (the MAGI's three blocks, a boot log, two traces coming into sync).
// Everything in it is this machine's own: your user and host, your
// screens, the Hyprland, Ether and Quickshell versions, your sound output
// and address.  Nothing flashes or glows; the blocks fill green from
// below, like the hash's.  It fades in over the lock as it builds, and
// once it's done it holds a moment and fades into your desktop
// (LockView).  Colours follow the wallpaper.  `t` is the seconds since it
// started (LockWired drives it).
Item {
    id: boot
    property var wired
    property real t: 0
    readonly property real done: 2.3            // everything up; it fades out over the last half second
    opacity: eout(part(0, 0.4))

    function part(start, span) { return Math.max(0, Math.min(1, (t - start) / span)) }
    function eout(x) { return 1 - Math.pow(1 - x, 3) }
    function ease(x) { return x * x * (3 - 2 * x) }

    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color ink: "#0a0c0e"
    readonly property color accent: wired.accent
    readonly property color second: wired.second
    readonly property color green: wired.okColour
    readonly property bool jp: wired.jp
    readonly property bool complete: t >= done

    // a session number, made up once
    property string session: ""
    Component.onCompleted: {
        const h = "0123456789ABCDEF"
        let s = ""
        for (let i = 0; i < 4; i++) s += h.charAt(Math.floor(Math.random() * 16))
        session = s
    }
    // the hex in the blocks moves on while they wait
    property int tick: 0
    Timer { interval: 60; repeat: true; running: boot.visible && !boot.complete; onTriggered: boot.tick++ }
    function hexLine() {
        const h = "0123456789ABCDEF"
        const g = []
        for (let k = 0; k < 6; k++) {
            let w = ""
            for (let i = 0; i < 4; i++) w += h.charAt(Math.floor(Math.random() * 16))
            g.push(w)
        }
        return g.join(" ")
    }

    // what's coming up, from this machine
    readonly property string user: Quickshell.env("USER") || "user"
    readonly property var log: {
        const L = []
        L.push(["pam", "session opened for " + user])
        L.push(["mount", Quickshell.env("HOME") || "/home/" + user])
        for (const s of Quickshell.screens)
            L.push(["display", s.name + "  " + Math.round(s.width * s.devicePixelRatio) + "x" + Math.round(s.height * s.devicePixelRatio)])
        L.push(["hyprland", wired.hyprVersion || "running"])
        L.push(["audio", Audio.sink ? (Audio.sink.description || Audio.sink.nickname || Audio.sink.name || "output") : "no output"])
        L.push(["net", wired.addr || "no link"])
        L.push(["shell", "ether " + (wired.etherVersion || "?") + (wired.qsVersion ? "  quickshell " + wired.qsVersion : "")])
        L.push(["theme", "palette from wallpaper"])
        L.push(["notify", Notifications.notifUnseen + " waiting"])
        L.push(["session", "restore"])
        return L.slice(0, 14)
    }
    // (spread so the last line's in before everything's up)
    readonly property real logStep: Math.min(0.16, (done - 0.22 - 0.32) / Math.max(1, log.length - 1))

    // a block with its top-right and bottom-left corners cut
    component Chamfer: Shape {
        id: ch
        property color fill: "transparent"
        property color stroke: "transparent"
        property real line: -1
        property real cut: 22
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            fillColor: ch.fill
            strokeColor: ch.stroke
            strokeWidth: ch.line
            startX: 0; startY: 0
            PathLine { x: ch.width - ch.cut; y: 0 }
            PathLine { x: ch.width; y: ch.cut }
            PathLine { x: ch.width; y: ch.height }
            PathLine { x: ch.cut; y: ch.height }
            PathLine { x: 0; y: ch.height - ch.cut }
            PathLine { x: 0; y: 0 }
        }
    }

    Rectangle { anchors.fill: parent; color: "#07090b" }
    // a faint grid
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.025)
            const step = 48 * stage.scale
            for (let x = 0; x < width; x += step) ctx.fillRect(Math.round(x), 0, 1, height)
            for (let y = 0; y < height; y += step) ctx.fillRect(0, Math.round(y), width, 1)
        }
    }

    Item {
        id: stage
        width: 1920; height: 1080
        anchors.centerIn: parent
        scale: Math.min(boot.width / 1920, boot.height / 1080)

        // ---- rules, drawn in from the left, and the edges' small print ----
        Rectangle { x: 96; y: 92; height: 1; width: 1728 * boot.eout(boot.part(0, 0.28)); color: Qt.rgba(1, 1, 1, 0.47) }
        Rectangle { x: 96; y: 1000; height: 1; width: 1728 * boot.eout(boot.part(0, 0.28)); color: Qt.rgba(1, 1, 1, 0.47) }
        Row {
            x: 96; y: 58
            spacing: 40
            visible: boot.t > 0.08
            Text { text: "ETHER // SESSION 0x" + boot.session; color: boot.paper; font.family: Theme.font; font.pixelSize: 18 }
            Text {
                text: (boot.user + "@" + (boot.wired.host || "localhost")).toUpperCase()
                      + (Quickshell.env("XDG_VTNR") ? "    TTY" + Quickshell.env("XDG_VTNR") : "")
                color: boot.dim; font.family: Theme.font; font.pixelSize: 18
            }
        }
        Text {
            x: 1824 - width; y: 58
            visible: boot.t > 0.08
            text: "T+" + (boot.t < 10 ? "0" : "") + boot.t.toFixed(2) + "s"
            color: boot.accent; font.family: Theme.font; font.pixelSize: 18
        }
        Text {
            x: 96; y: 1012
            visible: boot.jp && boot.t > 0.08
            text: "システム起動シーケンス"
            color: boot.dim; font.family: boot.wired.jpSans; font.pixelSize: 17
        }
        Text {
            x: 1824 - width; y: 1014
            visible: boot.t > 0.08
            text: "ETHER SHELL " + (boot.wired.etherVersion || "")
            color: Qt.rgba(0.35, 0.38, 0.4, 1); font.family: Theme.font; font.pixelSize: 16
        }

        // ---- the title: 起動 ("activation"), out of register like the clock ----
        Item {
            id: title
            x: 96; y: 92
            visible: boot.jp
            width: 330; height: 230
            Repeater {
                model: [ { d: -1, c: Qt.rgba(1, 0.27, 0.24, 0.5) }, { d: 1, c: Qt.rgba(0.24, 0.78, 0.9, 0.5) }, { d: 0, c: "#eef0f3" } ]
                delegate: Text {
                    required property var modelData
                    x: modelData.d * 4
                    text: "起動"
                    color: modelData.c
                    font.family: boot.wired.jpSerif
                    font.weight: Font.Black
                    font.pixelSize: 200
                    transform: Scale { xScale: 0.82 }
                }
            }
        }
        Column {
            x: boot.jp ? 470 : 96; y: 118
            spacing: -10
            LockDecode {
                go: boot.t > 0.05
                duration: 350
                target: "INITIALIZATION"
                color: boot.paper
                font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 64
                transform: Scale { xScale: 0.72 }
            }
            LockDecode {
                go: boot.t > 0.05
                duration: 350
                target: "SEQUENCE"
                color: boot.accent
                font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 64
                transform: Scale { xScale: 0.72 }
            }
        }

        // ---- three blocks, joined at the middle (after the MAGI) ----
        Shape {
            id: joins
            anchors.fill: parent
            opacity: boot.eout(boot.part(0.15, 0.18))
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.3); strokeWidth: 1; fillColor: "transparent"
                startX: 720; startY: 540
                PathLine { x: 720; y: 520 }
                PathMove { x: 720; y: 540 }
                PathLine { x: 640; y: 560 }
                PathMove { x: 720; y: 540 }
                PathLine { x: 800; y: 560 }
            }
        }
        Rectangle { x: 716; y: 536; width: 8; height: 8; radius: 4; color: boot.paper; opacity: joins.opacity }
        Repeater {
            model: [
                { name: "SHELL-1", jp: "殻", x: 520, y: 330, up: 0.95 },
                { name: "DISPLAY-2", jp: "表示", x: 300, y: 560, up: 1.5 },
                { name: "NODE-3", jp: "接続", x: 740, y: 560, up: 2.05 }
            ]
            delegate: Item {
                id: blk
                required property var modelData
                readonly property real bp: boot.eout(boot.part(0.15, 0.18))
                readonly property real lit: boot.part(modelData.up, 0.14)
                x: modelData.x; y: modelData.y
                width: 400; height: 190
                visible: bp > 0
                transform: Scale { xScale: blk.bp }
                Chamfer { anchors.fill: parent; fill: Qt.rgba(0.055, 0.067, 0.078, 0.92) }
                // the green, rolling in from below
                Item {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.height * boot.eout(blk.lit)
                    clip: true
                    Chamfer { y: -(blk.height - parent.height); width: blk.width; height: blk.height; fill: boot.green }
                }
                Chamfer {
                    anchors.fill: parent
                    stroke: blk.lit >= 1 ? boot.green : Qt.rgba(1, 1, 1, 0.78)
                    line: 2
                }
                Row {
                    x: 18; y: 14
                    spacing: 14
                    Text {
                        text: blk.modelData.name
                        color: blk.lit >= 0.6 ? boot.ink : boot.paper
                        font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 22
                    }
                    Text {
                        visible: boot.jp
                        text: blk.modelData.jp
                        color: blk.lit >= 0.6 ? boot.ink : boot.paper
                        font.family: boot.wired.jpSans; font.pixelSize: 22
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Column {
                    x: 18; y: 58
                    spacing: 6
                    visible: blk.lit < 0.6
                    Repeater {
                        model: 4
                        delegate: Text {
                            text: { boot.tick; return boot.hexLine() }
                            color: Qt.rgba(0.6, 0.62, 0.65, 0.7)
                            font.family: Theme.font; font.pixelSize: 17
                        }
                    }
                }
                Text {
                    x: 18; y: parent.height - 36
                    text: blk.lit < 0.6 ? "WAIT" : blk.modelData.up.toFixed(2)
                    color: blk.lit < 0.6 ? boot.accent : boot.ink
                    font.family: Theme.font; font.weight: blk.lit < 0.6 ? Font.Normal : Font.Bold
                    font.pixelSize: blk.lit < 0.6 ? 15 : 18
                }
            }
        }

        // ---- the boot log, down the right ----
        Item {
            x: 1260; y: 286
            width: 564
            visible: boot.t > 0.15
            Row {
                spacing: 14
                Text { text: "BOOT LOG"; color: boot.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 18 }
                Text { visible: boot.jp; text: "ログ"; color: boot.dim; font.family: boot.wired.jpSans; font.pixelSize: 18 }
            }
            Rectangle { y: 30; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.24) }
            Repeater {
                model: boot.log
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property real t0: 0.22 + index * boot.logStep
                    readonly property real typed: boot.part(t0, 0.1)
                    readonly property string full: (modelData[0] + "         ").slice(0, 9) + " " + modelData[1]
                    y: 44 + index * 32
                    width: parent.width; height: 26
                    visible: boot.t >= t0
                    Text { text: ">"; color: boot.accent; font.family: Theme.font; font.pixelSize: 18 }
                    Text {
                        x: 22
                        width: parent.width - 22 - 34
                        elide: Text.ElideRight
                        text: entry.full.slice(0, Math.ceil(entry.full.length * entry.typed))
                        color: entry.modelData[0] === "net" && !boot.wired.addr ? boot.second : boot.paper
                        font.family: Theme.font; font.pixelSize: 18
                    }
                    // its mark: outlined, then filled green
                    Rectangle {
                        x: parent.width - 16; y: 5
                        width: 14; height: 14
                        visible: entry.typed >= 1
                        color: boot.part(entry.t0 + 0.12, 0.06) >= 1 ? boot.green : "transparent"
                        border.width: 1
                        border.color: boot.part(entry.t0 + 0.12, 0.06) >= 1 ? boot.green : Qt.rgba(1, 1, 1, 0.55)
                    }
                }
            }
        }

        // ---- harmonics: two traces that start apart and come together ----
        Item {
            x: 96; y: 770
            visible: boot.t > 0.2
            Row {
                spacing: 14
                Text { text: "HARMONICS"; color: boot.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 16 }
                Text { visible: boot.jp; text: "同期"; color: boot.dim; font.family: boot.wired.jpSans; font.pixelSize: 16 }
            }
            Canvas {
                id: harm
                y: 30
                width: 1044; height: 160
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.07)
                    for (let k = 1; k < 4; k++) ctx.fillRect(0, k * 40, width, 1)
                    for (let k = 1; k < 12; k++) ctx.fillRect(k * 87, 0, 1, height)
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.28)
                    ctx.lineWidth = 1
                    ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
                    const T = boot.t
                    const settle = boot.ease(boot.part(0.3, boot.done - 0.3))
                    const mid = height / 2
                    const together = boot.part(boot.done - 0.05, 0.1)
                    const traces = [ { c: boot.accent, ph: 0 }, { c: boot.second, ph: 2.2 } ]
                    for (const tr of traces) {
                        const c = Qt.rgba(tr.c.r + (boot.green.r - tr.c.r) * together,
                                          tr.c.g + (boot.green.g - tr.c.g) * together,
                                          tr.c.b + (boot.green.b - tr.c.b) * together, 0.9)
                        ctx.strokeStyle = c
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        for (let x = 0; x <= width; x += 4) {
                            const u = x / width
                            let yv = Math.sin(u * 14 + T * 7 + tr.ph * (1 - settle)) * 44 * (0.6 + 0.4 * settle)
                            yv += (Math.random() - 0.5) * 70 * Math.pow(1 - settle, 1.5)
                            if (x === 0) ctx.moveTo(x, mid + yv); else ctx.lineTo(x, mid + yv)
                        }
                        ctx.stroke()
                    }
                }
            }
        }
        Connections {
            target: boot
            function onTChanged() { if (boot.visible) harm.requestPaint() }
        }

        // ---- the ratio, counting up, and its bar ----
        Item {
            x: 1260; y: 770
            visible: boot.t > 0.2
            readonly property real pct: 100 * boot.ease(boot.part(0.25, boot.done - 0.25))
            readonly property color col: boot.complete ? boot.green : boot.paper
            Text { text: "SYNC RATIO"; color: boot.paper; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 16 }
            Text {
                id: ratio
                y: 14
                // (padded to three digits: 007.7, 044.5, 100.0)
                readonly property real shown: Math.round(parent.pct * 10) / 10
                text: (shown < 10 ? "00" : shown < 100 ? "0" : "") + shown.toFixed(1)
                color: parent.col
                font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 120
                transform: Scale { xScale: 0.7 }
            }
            Text {
                x: ratio.contentWidth * 0.7 + 8; y: 92
                text: "%"
                color: parent.col
                font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 40
            }
            Row {
                y: 178
                spacing: 4
                Repeater {
                    model: 44
                    delegate: Rectangle {
                        required property int index
                        width: 564 / 44 - 4; height: 14
                        color: index < Math.floor(44 * parent.parent.pct / 100)
                               ? (boot.complete ? boot.green : boot.accent) : Qt.rgba(0.16, 0.17, 0.19, 1)
                    }
                }
            }
        }
    }
}
