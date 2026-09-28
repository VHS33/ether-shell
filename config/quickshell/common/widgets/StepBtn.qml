import QtQuick
import QtQuick.Layouts
import Quickshell

// one round − or + button for the stepper below
Rectangle {
    id: sb
    property var app
    property string glyph: ""
    property bool enabledBtn: true
    property color accent
    signal step()

    implicitWidth: 32
    implicitHeight: 32
    radius: 16
    color: !enabledBtn ? "transparent"
         : sbMa.pressed ? Qt.rgba(accent.r, accent.g, accent.b, 0.35)
         : sbHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
         : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
    Behavior on color { ColorAnimation { duration: app.animQuick } }
    HoverHandler { id: sbHov }

    Text {
        anchors.centerIn: parent
        text: sb.glyph
        color: sb.enabledBtn ? sb.app.cFg : sb.app.cFaint
        opacity: sb.enabledBtn ? 1 : 0.5
        font.family: "Material Symbols Rounded"
        font.pixelSize: sb.app.fs(15)
    }

    // hold to repeat: a pause, then quick steps
    Timer {
        id: sbRepeat
        interval: 420
        repeat: true
        onTriggered: { interval = 70; if (sb.enabledBtn) sb.step() }
    }
    MouseArea {
        id: sbMa
        anchors.fill: parent
        enabled: sb.enabledBtn
        cursorShape: Qt.PointingHandCursor
        onPressed: { sb.step(); sbRepeat.interval = 420; sbRepeat.start() }
        onReleased: sbRepeat.stop()
        onCanceled: sbRepeat.stop()
    }
}
