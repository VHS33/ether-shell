import QtQuick
import QtQuick.Layouts
import Quickshell

// segmented pill choice; the selected option gets a check
Row {
    id: seg
    property var app
    property var options: []
    property int current: -1
    property color accent: app.cBlue
    signal picked(int i)
    spacing: 2

    Repeater {
        model: seg.options
        delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool on: index === seg.current

            readonly property bool first: index === 0
            readonly property bool last: index === seg.options.length - 1
            implicitWidth: Math.max(104, segT.implicitWidth + (on ? 52 : 34))
            implicitHeight: 34
            topLeftRadius: first ? 17 : 5
            bottomLeftRadius: first ? 17 : 5
            topRightRadius: last ? 17 : 5
            bottomRightRadius: last ? 17 : 5
            color: on ? Qt.rgba(seg.accent.r, seg.accent.g, seg.accent.b, 0.26)
                 : segHov.hovered ? Qt.rgba(seg.app.cFg.r, seg.app.cFg.g, seg.app.cFg.b, 0.12)
                 : Qt.rgba(seg.app.cFg.r, seg.app.cFg.g, seg.app.cFg.b, 0.09)
            Behavior on color { ColorAnimation { duration: app.animQuick } }

            HoverHandler { id: segHov }

            Row {
                anchors.centerIn: parent
                spacing: 7
                Text {
                    visible: parent.parent.on
                    text: "check"
                    color: seg.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(13)
                }
                Text {
                    id: segT
                    text: modelData
                    color: parent.parent.on ? seg.app.cFg : seg.app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: seg.picked(index)
            }
        }
    }
}
