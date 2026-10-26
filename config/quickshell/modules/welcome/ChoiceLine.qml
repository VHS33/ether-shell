import QtQuick
import QtQuick.Layouts
import qs.common.widgets
import qs.services

// a label and a row of choices (chips), one picked: { k, t } each
RowLayout {
    id: line
    property string label
    property var choices: []
    property var current
    signal picked(var k)
    Layout.fillWidth: true
    spacing: 12
    Text {
        Layout.preferredWidth: 130
        text: line.label
        color: line.app.cDim
        font.family: Theme.uiFont
        font.pixelSize: line.app.fs(12)
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: line.choices
            delegate: Chip {
                required property var modelData
                app: line.app
                text: modelData.t
                selected: modelData.k === line.current
                onPicked: line.picked(modelData.k)
            }
        }
    }
    property var app
}
