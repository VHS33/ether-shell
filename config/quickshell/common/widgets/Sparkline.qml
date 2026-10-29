import QtQuick
import QtQuick.Shapes

// A line graph of recent readings, newest on the right: the bar's mini
// graphs and the system panel's big ones.  Drawn by Qt's shape renderer
// rather than painted in JavaScript, so a new reading only moves a few
// points, and nothing is worked out or drawn while it's hidden.
Item {
    id: sp
    property var points: []          // the readings, oldest first
    property int count: 30           // how many of the latest to show
    property real maxValue: 100
    property color color: "white"
    property bool fill: false        // a soft area under the line
    property real lineWidth: 1.5

    // the line, in this item's own coordinates (empty while hidden)
    readonly property var line: {
        const all = sp.points
        if (!sp.visible || !all || all.length < 2 || width <= 0 || height <= 0) return []
        const pts = all.length > count ? all.slice(all.length - count) : all
        const n = pts.length, step = width / Math.max(1, count - 1)
        const x0 = width - (n - 1) * step, pad = lineWidth / 2 + 0.5
        const out = []
        for (let i = 0; i < n; i++) {
            const v = Math.max(0, Math.min(1, (pts[i] || 0) / maxValue))
            out.push(Qt.point(x0 + i * step, height - pad - v * (height - 2 * pad)))
        }
        return out
    }
    // the area: the line, closed along the bottom
    readonly property var area: line.length < 2 ? []
        : [Qt.point(line[0].x, height)].concat(line, [Qt.point(line[line.length - 1].x, height)])

    Shape {
        anchors.fill: parent
        visible: sp.line.length > 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                y1: 0
                y2: sp.height
                GradientStop { position: 0; color: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, sp.fill ? 0.38 : 0) }
                GradientStop { position: 1; color: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, sp.fill ? 0.02 : 0) }
            }
            PathPolyline { path: sp.fill ? sp.area : [] }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: sp.color
            strokeWidth: sp.lineWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: sp.line }
        }
    }
}
