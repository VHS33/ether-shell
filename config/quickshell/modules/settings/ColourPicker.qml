import QtQuick
import QtQuick.Layouts
import Quickshell

// Pick a colour by eye: the rainbow strip chooses the hue, the square how
// strong and how bright it is.  Letting go of either sends picked("#rrggbb"),
// so there's no colour code to look up.
ColumnLayout {
    id: cp
    property var app
    signal picked(string hex)
    spacing: 10

    property real hue: 0
    property real sat: 1
    property real val: 1
    readonly property color current: Qt.hsva(hue, sat, val, 1)
    readonly property string hex: String(current).toLowerCase()

    // start from a colour (the one in use when the picker opens)
    function load(c) {
        const col = Qt.color(c)
        hue = col.hsvHue >= 0 ? col.hsvHue : hue
        sat = col.hsvSaturation
        val = col.hsvValue
    }

    // strength (left to right) and brightness (top to bottom)
    Rectangle {
        id: sv
        Layout.preferredWidth: 280
        Layout.preferredHeight: 150
        radius: cp.app.rr(12)
        color: Qt.hsva(cp.hue, 1, 1, 1)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ffffffff" }
                GradientStop { position: 1; color: "#00ffffff" }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "#00000000" }
                GradientStop { position: 1; color: "#ff000000" }
            }
        }
        Rectangle {
            width: 16
            height: 16
            radius: app.rr(8)
            x: cp.sat * sv.width - width / 2
            y: (1 - cp.val) * sv.height - height / 2
            color: cp.current
            border.width: 2
            border.color: cp.val > 0.6 && cp.sat < 0.4 ? "#202020" : "white"
        }
        MouseArea {
            anchors.fill: parent
            // keep the drag: Settings scrolls, and would take it over
            preventStealing: true
            cursorShape: Qt.CrossCursor
            function at(m) {
                cp.sat = Math.max(0, Math.min(1, m.x / width))
                cp.val = Math.max(0, Math.min(1, 1 - m.y / height))
            }
            onPressed: m => at(m)
            onPositionChanged: m => { if (pressed) at(m) }
            onReleased: cp.picked(cp.hex)
            onCanceled: cp.picked(cp.hex)
        }
    }

    // the hue
    Rectangle {
        id: hueBar
        Layout.preferredWidth: 280
        Layout.preferredHeight: 16
        radius: cp.app.rr(8)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0 / 6; color: "#ff0000" }
            GradientStop { position: 1 / 6; color: "#ffff00" }
            GradientStop { position: 2 / 6; color: "#00ff00" }
            GradientStop { position: 3 / 6; color: "#00ffff" }
            GradientStop { position: 4 / 6; color: "#0000ff" }
            GradientStop { position: 5 / 6; color: "#ff00ff" }
            GradientStop { position: 6 / 6; color: "#ff0000" }
        }
        Rectangle {
            width: 8
            height: parent.height + 6
            radius: cp.app.rr(4)
            anchors.verticalCenter: parent.verticalCenter
            x: cp.hue * hueBar.width - width / 2
            color: Qt.hsva(cp.hue, 1, 1, 1)
            border.width: 2
            border.color: "white"
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function at(m) { cp.hue = Math.max(0, Math.min(0.9999, (m.x - 4) / hueBar.width)) }
            onPressed: m => at(m)
            onPositionChanged: m => { if (pressed) at(m) }
            onReleased: cp.picked(cp.hex)
            onCanceled: cp.picked(cp.hex)
        }
    }

    // what it'll be
    RowLayout {
        spacing: 10
        Rectangle {
            implicitWidth: 34
            implicitHeight: 22
            radius: cp.app.rr(6)
            color: cp.current
            border.width: 1
            border.color: Qt.rgba(cp.app.cFg.r, cp.app.cFg.g, cp.app.cFg.b, 0.3)
        }
        Text {
            text: cp.hex
            color: cp.app.cFg
            font.family: cp.app.uiFont
            font.pixelSize: cp.app.fs(13)
        }
        Text {
            text: "Drag in the square and the strip; it's used when you let go."
            color: cp.app.cDim
            font.family: cp.app.uiFont
            font.pixelSize: cp.app.fs(12)
        }
    }
}
