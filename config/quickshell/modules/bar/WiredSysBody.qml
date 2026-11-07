import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.services

// The system drawer in the Wired style (Settings > Theme > Drawers), after
// the Wired lock screen: a light title bar, then CPU, memory, GPU and its
// temperature as heavy numbers beside thin traces on a grid, the busiest
// processes with segmented bars, and this week's playtime.  Mono type, the
// wallpaper's colours, Japanese beside the English when there's a font for
// it.  Same data and buttons as the standard drawer.
Item {
    id: ws
    property var app
    signal close()

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

    // uptime the terminal way: "up 2 hours, 5 minutes" is "2H 05M"
    function shortUptime(s) {
        const n = unit => { const m = String(s).match(new RegExp("(\\d+)\\s+" + unit)); return m ? parseInt(m[1]) : 0 }
        const d = n("year") * 365 + n("week") * 7 + n("day"), h = n("hour"), m = n("minute")
        const two = v => (v < 10 ? "0" : "") + v
        if (d > 0) return d + "D " + two(h) + "H " + two(m) + "M"
        if (h > 0) return h + "H " + two(m) + "M"
        return m + "M"
    }
    function pad3(v) { return ("00" + Math.round(v)).slice(-3) }

    implicitHeight: body.y + body.implicitHeight + 18

    // ---- a section's name, in the main colour, and in Japanese ----
    component Label: Row {
        property string en: ""
        property string ja: ""
        spacing: 8
        Text { text: parent.en; color: ws.accent; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        Text { visible: ws.jp && parent.ja !== ""; text: parent.ja; color: ws.dim; font.family: ws.jpFont; font.pixelSize: 11 }
    }
    // ---- a bar of little blocks, so many lit ----
    component Segs: Row {
        property real frac: 0
        property int count: 12
        property color colour: ws.accent
        property real segW: 6
        spacing: 2
        Repeater {
            model: parent.count
            delegate: Rectangle {
                required property int index
                width: parent.segW; height: 7
                color: index < Math.round(parent.frac * parent.count) ? parent.colour : ws.off
            }
        }
    }
    // ---- a line between sections ----
    component Rule: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.16) }

    // ---- the title bar ----
    Rectangle {
        id: titleBar
        width: parent.width; height: 22
        color: Qt.rgba(0.93, 0.94, 0.95, 0.9)
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text { text: "SYS"; color: ws.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 13 }
            Text { visible: ws.jp; text: "状態"; color: ws.ink; font.family: ws.jpFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            anchors.right: boxes.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: ws.app.uptimeText ? "UP " + ws.shortUptime(ws.app.uptimeText) : ""
            color: Qt.rgba(0.24, 0.25, 0.27, 1)
            font.family: Theme.font; font.pixelSize: 12
        }
        // the three boxes; they close it
        Row {
            id: boxes
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: 3
                delegate: Rectangle { width: 7; height: 7; color: "transparent"; border.width: 1; border.color: ws.ink }
            }
        }
        MouseArea {
            anchors.right: parent.right; width: 40; height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: ws.close()
        }
    }
    // the inner line of the double frame
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        anchors.topMargin: titleBar.height + 3
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
    }

    Column {
        id: body
        x: 16; y: titleBar.height + 14
        width: parent.width - 32
        spacing: 14

        // ---- the four readings: a heavy number, a trace on a grid ----
        Grid {
            id: cells
            width: parent.width
            columns: 2
            columnSpacing: 14
            rowSpacing: 16
            Repeater {
                model: [
                    { en: "CPU", ja: "演算", v: ws.app.cpuPct, unit: "%", pts: ws.app.cpuHist, max: 100, c: ws.accent, on: true },
                    { en: "MEMORY", ja: "記憶", v: ws.app.memPct, unit: "%", pts: ws.app.memHist, max: 100, c: ws.second, on: true },
                    { en: "GPU", ja: "描画", v: ws.app.gpuPct, unit: "%", pts: ws.app.gpuHist, max: 100, c: ws.accent, on: ws.app.gpuOk },
                    { en: "GPU TEMP", ja: "温度", v: ws.app.gpuTemp, unit: "°C", pts: ws.app.tempHist, max: 100, c: ws.second, on: ws.app.gpuOk }
                ]
                delegate: Item {
                    id: cell
                    required property var modelData
                    visible: modelData.on
                    width: (cells.width - cells.columnSpacing) / 2
                    height: 96
                    Label { en: cell.modelData.en; ja: cell.modelData.ja }
                    // the number, out of register like the lock's clock
                    Item {
                        id: num
                        y: 18
                        width: 86; height: 46
                        Repeater {
                            model: [ { d: -1.5, c: Qt.rgba(1, 0.27, 0.24, 0.5) }, { d: 1.5, c: Qt.rgba(0.24, 0.78, 0.9, 0.5) }, { d: 0, c: ws.paper } ]
                            delegate: Text {
                                required property var modelData
                                x: modelData.d
                                text: ws.pad3(cell.modelData.v)
                                color: modelData.c
                                font.family: Theme.uiFont; font.weight: Font.Black; font.pixelSize: 40
                                transform: Scale { xScale: 0.72 }
                            }
                        }
                    }
                    Text {
                        x: 66; y: 42
                        text: cell.modelData.unit
                        color: ws.dim
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    // the trace: a grid, a frame and the line, as shapes (they
                    // draw in whichever window the drawer is in; on the long bar
                    // that's the bar's own)
                    Item {
                        id: tr
                        x: 92; y: 18
                        width: cell.width - 92; height: 70
                        Repeater {
                            model: 3
                            delegate: Rectangle { required property int index; y: Math.round((index + 1) * tr.height / 4); width: tr.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
                        }
                        Repeater {
                            model: 7
                            delegate: Rectangle { required property int index; x: Math.round((index + 1) * tr.width / 8); width: 1; height: tr.height; color: Qt.rgba(1, 1, 1, 0.06) }
                        }
                        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18) }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Qt.rgba(cell.modelData.c.r, cell.modelData.c.g, cell.modelData.c.b, 0.92)
                                strokeWidth: 1.4
                                fillColor: "transparent"
                                PathPolyline {
                                    path: {
                                        const p = cell.modelData.pts || []
                                        const out = []
                                        for (let i = 0; i < p.length; i++)
                                            out.push(Qt.point(p.length > 1 ? i * (tr.width - 2) / (p.length - 1) + 1 : 1,
                                                              tr.height - 2 - Math.max(0, Math.min(1, p[i] / cell.modelData.max)) * (tr.height - 4)))
                                        return out
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rule {}

        // ---- the busiest processes ----
        Item {
            width: parent.width
            height: 22 + Math.max(1, procs.count) * 20
            Label { en: "BUSIEST"; ja: "負荷" }
            Text { x: parent.width - 336; text: "CPU"; color: ws.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
            Text { x: parent.width - 156; text: "MEM"; color: ws.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
            Repeater {
                id: procs
                model: ws.app.topProcs.slice(0, 5)
                delegate: Item {
                    id: pr
                    required property var modelData
                    required property int index
                    y: 22 + index * 20
                    width: parent.width; height: 18
                    Text {
                        width: parent.width - 350
                        elide: Text.ElideRight
                        text: pr.modelData.name
                        color: ws.paper
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    Segs { x: parent.width - 336; y: 5; frac: pr.modelData.cpu / 100; colour: ws.accent }
                    Text { x: parent.width - 240; width: 50; horizontalAlignment: Text.AlignRight; text: pr.modelData.cpu.toFixed(1); color: ws.dim; font.family: Theme.font; font.pixelSize: 11 }
                    Segs { x: parent.width - 156; y: 5; frac: Math.min(1, pr.modelData.mem / 33); colour: ws.second }
                    Text { x: parent.width - 60; width: 50; horizontalAlignment: Text.AlignRight; text: pr.modelData.mem.toFixed(1); color: ws.dim; font.family: Theme.font; font.pixelSize: 11 }
                }
            }
            Text {
                y: 22
                visible: procs.count === 0
                text: "> reading…"
                color: ws.faint
                font.family: Theme.font; font.pixelSize: 12
            }
        }

        Rule {}

        // ---- this week's games ----
        Item {
            id: play
            width: parent.width
            readonly property var games: ws.app.playWeek.slice(0, 5)
            readonly property real total: ws.app.playWeek.reduce((t, g) => t + g.week, 0)
            readonly property real most: games.length ? Math.max(...games.map(g => g.week)) : 1
            height: 22 + (ws.app.gameRunning ? 24 : 0) + Math.max(1, games.length) * 20 + 40
            Label { en: "PLAYTIME"; ja: "遊戯時間" }
            Text {
                anchors.right: parent.right
                text: (play.total > 0 ? ws.app.fmtPlay(play.total) : "0h") + " THIS WEEK"
                color: ws.dim
                font.family: Theme.font; font.pixelSize: 11
            }
            Text {
                y: 22
                visible: ws.app.gameRunning
                text: ws.app.gameMode ? "> playing now  game mode on" : "> playing now"
                color: ws.accent
                font.family: Theme.font; font.pixelSize: 12
            }
            Repeater {
                model: play.games
                delegate: Item {
                    id: gm
                    required property var modelData
                    required property int index
                    y: 22 + (ws.app.gameRunning ? 24 : 0) + index * 20
                    width: play.width; height: 18
                    Text {
                        width: parent.width - 230
                        elide: Text.ElideRight
                        text: gm.modelData.name
                        color: ws.paper
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    Segs { x: parent.width - 216; y: 5; frac: gm.modelData.week / play.most; count: 16 }
                    Text { anchors.right: parent.right; text: ws.app.fmtPlay(gm.modelData.week); color: ws.dim; font.family: Theme.font; font.pixelSize: 11 }
                }
            }
            Text {
                y: 22 + (ws.app.gameRunning ? 24 : 0)
                visible: play.games.length === 0
                text: "games you play show up here"
                color: ws.faint
                font.family: Theme.font; font.pixelSize: 11
            }
            // buttons: count the last window as a game, and btop
            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                spacing: 8
                Repeater {
                    model: [ { t: "COUNT LAST WINDOW", act: "mark" }, { t: "OPEN BTOP", act: "btop" } ]
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        width: btnT.implicitWidth + 28; height: 26
                        color: btnHov.hovered ? Qt.rgba(ws.accent.r, ws.accent.g, ws.accent.b, 0.14) : "transparent"
                        border.width: 1
                        border.color: btn.modelData.act === "btop" ? ws.accent : Qt.rgba(1, 1, 1, 0.3)
                        HoverHandler { id: btnHov }
                        Text {
                            id: btnT
                            anchors.centerIn: parent
                            text: btn.modelData.t
                            color: btn.modelData.act === "btop" ? ws.accent : ws.paper
                            font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (btn.modelData.act === "mark") { ws.app.markGame(); return }
                                ws.close()
                                ws.app.run(ws.app.termCmd + " -e sh -c 'command -v btop >/dev/null && exec btop || exec top'")
                            }
                        }
                    }
                }
            }
        }
    }
}
