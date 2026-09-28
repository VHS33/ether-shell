import QtQuick
import QtQuick.Layouts
import Quickshell

// small pill in a wrapping row of choices
Rectangle {
    id: chip
    property var app
    property string text: ""
    property bool selected: false
    signal picked()

    implicitWidth: chipT.implicitWidth + 26
    implicitHeight: 32
    radius: 16
    color: selected ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.26)
         : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
         : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
    border.width: selected ? 1 : 0
    border.color: app.cBlue
    Behavior on color { ColorAnimation { duration: app.animQuick } }

    HoverHandler { id: chipHov }

    Text {
        id: chipT
        anchors.centerIn: parent
        text: chip.text
        color: chip.selected ? chip.app.cFg : chip.app.cDim
        font.family: "Inter"
        font.pixelSize: app.fs(12)
        font.bold: chip.selected
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.picked()
    }
}
