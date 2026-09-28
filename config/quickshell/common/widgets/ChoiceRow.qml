import QtQuick
import QtQuick.Layouts
import Quickshell

// one option in a list of choices: title, a line of description,
// and a check when selected
Rectangle {
    id: cr
    property var app
    property string title: ""
    property string desc: ""
    property bool selected: false
    property color accent: app.cBlue
    signal chosen()

    Layout.fillWidth: true
    implicitHeight: crCol.implicitHeight + 20
    radius: 14
    color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
         : crHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
         : "transparent"
    Behavior on color { ColorAnimation { duration: app.animQuick } }

    HoverHandler { id: crHov }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        ColumnLayout {
            id: crCol
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: cr.title
                color: cr.app.cFg
                font.family: "Inter"
                font.pixelSize: app.fs(13)
                font.bold: cr.selected
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: cr.desc
                color: cr.app.cDim
                font.family: "Inter"
                font.pixelSize: app.fs(11)
                wrapMode: Text.WordWrap
            }
        }

        Text {
            visible: cr.selected
            text: "check"
            color: cr.accent
            font.family: "Material Symbols Rounded"
            font.pixelSize: app.fs(16)
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: cr.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!cr.selected) cr.chosen()
    }
}
