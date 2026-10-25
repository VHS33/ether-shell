import QtQuick
import qs.services

// A small tonal pill for the lock screen's status row (weather, battery,
// notifications): an icon and a label, hidden while the label is empty.
Rectangle {
    id: chip
    property var app
    property string icon: ""
    property string label: ""
    property color tint: "white"
    property real iconRotation: 0
    visible: label !== ""
    implicitWidth: chipRow.implicitWidth + 26
    implicitHeight: 34
    radius: 17
    color: Qt.rgba(1, 1, 1, 0.09)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.16)
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 7
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            rotation: chip.iconRotation
            color: chip.tint
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            color: Qt.rgba(1, 1, 1, 0.9)
            font.family: Theme.uiFont
            font.weight: Font.Medium
            font.pixelSize: chip.app ? chip.app.fs(13) : 13
        }
    }
}
