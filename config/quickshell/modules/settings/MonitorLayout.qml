import QtQuick
import "../../lib/layout.mjs" as LayoutLib

// Your monitors, drawn to scale: drag one to where it sits on your desk, and
// it snaps edge to edge with its neighbours (lib/layout.mjs); click one to
// pick it.  Positions are Hyprland's logical pixels.
Item {
    id: canvas
    property var app
    property var monitors: []        // [{ name, x, y, w, h, label, label2, main }]
    property string selected: ""
    signal moved(string name, int x, int y)
    signal picked(string name)
    implicitHeight: 300

    // the view: the monitors' bounds fitted into the space, which holds still
    // while one is dragged (so nothing jumps under the pointer)
    property var frame: fit()
    property bool dragging: false
    function fit() {
        const ms = monitors
        if (!ms.length || width <= 0 || height <= 0) return { minX: 0, minY: 0, s: 0.05, ox: 0, oy: 0 }
        const minX = Math.min(...ms.map(m => m.x)), minY = Math.min(...ms.map(m => m.y))
        const bw = Math.max(...ms.map(m => m.x + m.w)) - minX, bh = Math.max(...ms.map(m => m.y + m.h)) - minY
        // room for a monitor's width either side, to drag it there
        const pad = Math.max(...ms.map(m => Math.max(m.w, m.h))) * 0.3
        const s = Math.min(width / (bw + 2 * pad), height / (bh + 2 * pad))
        return { minX: minX, minY: minY, s: s, ox: (width - bw * s) / 2, oy: (height - bh * s) / 2 }
    }
    function refit() { if (!dragging) frame = fit() }
    onMonitorsChanged: refit()
    onWidthChanged: refit()
    onHeightChanged: refit()

    // where a tile dropped at (px, py) lands, in Hyprland's coordinates
    function drop(name, px, py) {
        const m = monitors.find(q => q.name === name)
        if (!m) return
        const lx = (px - frame.ox) / frame.s + frame.minX, ly = (py - frame.oy) / frame.s + frame.minY
        const p = LayoutLib.snap(m, monitors.filter(q => q.name !== name), lx, ly)
        moved(name, p.x, p.y)
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: canvas.app ? Qt.rgba(canvas.app.cFg.r, canvas.app.cFg.g, canvas.app.cFg.b, 0.04) : "transparent"
    }

    Repeater {
        model: canvas.monitors
        delegate: Rectangle {
            id: tile
            required property var modelData
            readonly property bool sel: modelData.name === canvas.selected
            x: canvas.frame.ox + (modelData.x - canvas.frame.minX) * canvas.frame.s
            y: canvas.frame.oy + (modelData.y - canvas.frame.minY) * canvas.frame.s
            width: modelData.w * canvas.frame.s
            height: modelData.h * canvas.frame.s
            radius: 8
            color: Qt.rgba(canvas.app.cFg.r, canvas.app.cFg.g, canvas.app.cFg.b, drag.active ? 0.22 : sel ? 0.16 : 0.1)
            border.width: sel ? 2 : 1
            border.color: sel ? canvas.app.cBlue : Qt.rgba(canvas.app.cFg.r, canvas.app.cFg.g, canvas.app.cFg.b, 0.25)
            z: drag.active ? 10 : 0
            property alias drag: area.drag

            Column {
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.name
                    color: canvas.app.cFg
                    font.family: "Inter"
                    font.bold: true
                    font.pixelSize: canvas.app.fs(13)
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.label || ""
                    color: canvas.app.cDim
                    font.family: "Inter"
                    font.pixelSize: canvas.app.fs(11)
                    elide: Text.ElideRight
                    visible: tile.height > 50
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.label2 || ""
                    color: canvas.app.cFaint
                    font.family: "Inter"
                    font.pixelSize: canvas.app.fs(11)
                    elide: Text.ElideRight
                    visible: tile.height > 64 && text !== ""
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.modelData.main && tile.height > 70
                    width: mainText.implicitWidth + 14
                    height: 18
                    radius: 9
                    color: canvas.app.cBlue
                    Text {
                        id: mainText
                        anchors.centerIn: parent
                        text: "Main"
                        color: canvas.app.cOnAccent
                        font.family: "Inter"
                        font.bold: true
                        font.pixelSize: canvas.app.fs(10)
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: canvas.monitors.length > 1 ? tile : null
                drag.threshold: 4
                onPressed: { canvas.dragging = true; canvas.picked(tile.modelData.name) }
                onReleased: {
                    const wasDragged = drag.active || Math.abs(tile.x - (canvas.frame.ox + (tile.modelData.x - canvas.frame.minX) * canvas.frame.s)) > 1
                    canvas.dragging = false
                    if (wasDragged) canvas.drop(tile.modelData.name, tile.x, tile.y)
                    canvas.refit()
                    // back under the layout's control (a new position redraws it)
                    tile.x = Qt.binding(() => canvas.frame.ox + (tile.modelData.x - canvas.frame.minX) * canvas.frame.s)
                    tile.y = Qt.binding(() => canvas.frame.oy + (tile.modelData.y - canvas.frame.minY) * canvas.frame.s)
                }
            }
        }
    }
}
