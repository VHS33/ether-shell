import QtQuick
import QtQuick.Layouts
import Quickshell

// round icon button, lit when `active`
Rectangle {
    id: ib
    property var app
    property string glyph: ""
    property bool active: false
    property color accent: app.cBlue
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    radius: 18
    color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.26)
         : ibHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
         : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
    Behavior on color { ColorAnimation { duration: app.animQuick } }

    HoverHandler { id: ibHov }

    Text {
        anchors.centerIn: parent
        text: ib.glyph
        color: ib.active ? ib.accent : ib.app.cDim
        font.family: "Material Symbols Rounded"
        font.pixelSize: app.fs(16)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: ib.clicked()
    }
}
