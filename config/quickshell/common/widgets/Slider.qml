import QtQuick
import QtQuick.Layouts
import Quickshell

// − value + stepper.  Still called Slider so every page that uses
// one keeps working unchanged: same from / to / step / value /
// label, and `moved(v)` fires with the new value.  Holding a button
// repeats; scrolling over it steps too.
RowLayout {
    id: sl
    property var app
    property real from: 0
    property real to: 1
    property real value: 0
    property real origin: from
    property real step: 0.02
    property real tick: -1
    property bool muted: false
    property color accent: app.cBlue
    property string label: ""
    signal moved(real v)

    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    spacing: 4

    // snap to the step grid so repeated presses land on round values
    function nudge(dir) {
        const n = Math.round((value - from) / step) + dir
        let v = from + n * step
        v = Math.max(from, Math.min(to, v))
        moved(Math.round(v * 10000) / 10000)
    }
    readonly property bool atMin: value <= from + step / 1000
    readonly property bool atMax: value >= to - step / 1000

    StepBtn {
        app: sl.app
        glyph: "remove"
        accent: sl.accent
        enabledBtn: !sl.atMin
        onStep: sl.nudge(-1)
    }

    Rectangle {
        implicitWidth: Math.max(72, slT.implicitWidth + 20)
        implicitHeight: 32
        radius: 16
        color: Qt.rgba(sl.accent.r, sl.accent.g, sl.accent.b, 0.14)
        Text {
            id: slT
            anchors.centerIn: parent
            text: sl.label
            color: sl.muted ? sl.app.cFaint : sl.app.cFg
            font.family: "Inter"
            font.pixelSize: sl.app.fs(12)
            font.bold: true
        }
        // scroll over the value to step
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: w => sl.nudge(w.angleDelta.y > 0 ? 1 : -1)
        }
    }

    StepBtn {
        app: sl.app
        glyph: "add"
        accent: sl.accent
        enabledBtn: !sl.atMax
        onStep: sl.nudge(1)
    }
}
