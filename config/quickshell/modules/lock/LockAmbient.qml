import QtQuick
import QtQuick.Shapes

// The Neo lock screen's atmosphere, between the frosted wallpaper and
// everything on it: two soft glows in the theme's colours drifting very
// slowly, a faint dot grid, and one line of light sweeping down the screen
// as it locks.  The drift only runs while you're there (typing, or for a
// little while after locking): a locked screen left alone sits still and
// costs nothing.
Item {
    id: amb
    property var app
    property real enter: 0
    property bool awake: true               // drifting (LockView: input recently)
    readonly property color a1: app.cBlue
    readonly property color a2: app.cPeach

    // ---- two glows ----
    component Glow: Shape {
        id: g
        property color tint
        property real r: 420
        width: r * 2; height: r * 2
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: g.r; centerY: g.r; centerRadius: g.r
                focalX: g.r; focalY: g.r
                GradientStop { position: 0.0; color: Qt.rgba(g.tint.r, g.tint.g, g.tint.b, 0.30) }
                GradientStop { position: 0.55; color: Qt.rgba(g.tint.r, g.tint.g, g.tint.b, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(g.tint.r, g.tint.g, g.tint.b, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: g.width; y: 0 }
            PathLine { x: g.width; y: g.height }
            PathLine { x: 0; y: g.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Glow {
        id: g1
        tint: amb.a1
        r: Math.max(amb.width, amb.height) * 0.42
        property real t: 0
        x: amb.width * (0.12 + 0.18 * Math.sin(t * 2 * Math.PI)) - r
        y: amb.height * (0.30 + 0.12 * Math.cos(t * 2 * Math.PI)) - r
        opacity: amb.enter
        NumberAnimation on t { from: 0; to: 1; duration: 90000; loops: Animation.Infinite; running: amb.awake }
    }
    Glow {
        id: g2
        tint: amb.a2
        r: Math.max(amb.width, amb.height) * 0.36
        property real t: 0.5
        x: amb.width * (0.86 - 0.16 * Math.sin(t * 2 * Math.PI)) - r
        y: amb.height * (0.72 - 0.14 * Math.cos(t * 2 * Math.PI)) - r
        opacity: amb.enter * 0.85
        NumberAnimation on t { from: 0.5; to: 1.5; duration: 120000; loops: Animation.Infinite; running: amb.awake }
    }

    // ---- a faint dot grid, drawn once ----
    Canvas {
        anchors.fill: parent
        opacity: 0.55 * amb.enter
        renderStrategy: Canvas.Cooperative
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const step = 34
            const cx = width / 2, cy = height / 2, far = Math.hypot(cx, cy)
            for (let y = step / 2; y < height; y += step)
                for (let x = step / 2; x < width; x += step) {
                    // fading out towards the edges
                    const f = 1 - Math.hypot(x - cx, y - cy) / far
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.07 * f)
                    ctx.fillRect(x, y, 1.5, 1.5)
                }
        }
    }

    // ---- one line of light, down the screen as it locks ----
    Rectangle {
        width: parent.width
        height: 90
        y: parent.height * amb.enter - height
        visible: amb.enter > 0.02 && amb.enter < 0.99
        opacity: Math.sin(Math.PI * amb.enter) * 0.9
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.96; color: Qt.rgba(amb.a1.r, amb.a1.g, amb.a1.b, 0.18) }
            GradientStop { position: 1.0; color: Qt.rgba(amb.a1.r, amb.a1.g, amb.a1.b, 0.85) }
        }
    }
}
