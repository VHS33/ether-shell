import QtQuick
import QtQuick.Layouts
import Quickshell

// One of Theme Studio's colours: Auto (Ether Shell's own pick, its colour as
// the dot), any colour found in the picture, any colour typed as #rrggbb,
// or any colour picked by eye (the palette button).  `value` is the choice
// ("" for Auto, otherwise "#rrggbb"); choosing emits picked(value).  The
// same controls as a graph's colour (ColourRow), with the picture's colours
// in place of the theme's.
ColumnLayout {
    id: row
    property var app
    property string value: ""
    property var colours: []              // the picture's, "#rrggbb" each
    property color autoColour: "transparent"
    signal picked(string value)
    spacing: 10

    readonly property bool custom: value !== "" && colours.indexOf(value) < 0
    property bool pickerOpen: false

    Flow {
        Layout.fillWidth: true
        spacing: 8

        // Auto, with the colour it gives right now
        Rectangle {
            readonly property bool on: row.value === ""
            width: autoRow.implicitWidth + 20
            height: 32
            radius: row.app.rr(16)
            color: on ? Qt.rgba(row.app.cBlue.r, row.app.cBlue.g, row.app.cBlue.b, 0.22)
                 : autoHov.hovered ? Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.14)
                 : Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.09)
            border.width: on ? 2 : 0
            border.color: row.app.cFg
            HoverHandler { id: autoHov }
            Row {
                id: autoRow
                anchors.centerIn: parent
                spacing: 7
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: row.app.rr(7)
                    color: row.autoColour
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Auto"
                    color: row.app.cFg
                    font.family: row.app.uiFont
                    font.pixelSize: row.app.fs(13)
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: row.picked("")
            }
        }

        // the picture's own colours
        Repeater {
            model: row.colours
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: row.value === modelData
                width: 32; height: 32; radius: row.app.rr(16)
                color: modelData
                border.width: on ? 3 : swHov.hovered ? 2 : 1
                border.color: on || swHov.hovered ? row.app.cFg : Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.2)
                HoverHandler { id: swHov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.picked(parent.on ? "" : parent.modelData)
                }
            }
        }

        // any colour: type it, then Enter (or click away)
        Rectangle {
            width: 104
            height: 32
            radius: row.app.rr(16)
            color: Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, hexIn.activeFocus ? 0.14 : 0.09)
            border.width: row.custom ? 2 : 0
            border.color: row.app.cFg
            Rectangle {
                id: hexDot
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: row.app.rr(6)
                color: /^#[0-9a-fA-F]{6}$/.test(hexIn.text) ? hexIn.text : "transparent"
                border.width: 1
                border.color: Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.4)
            }
            TextInput {
                id: hexIn
                anchors.left: hexDot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.custom ? row.value : ""
                color: row.app.cFg
                font.family: row.app.uiFont
                font.pixelSize: row.app.fs(13)
                maximumLength: 7
                selectByMouse: true
                validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                function apply() {
                    let t = text.trim()
                    if (t !== "" && t[0] !== "#") t = "#" + t
                    if (/^#[0-9a-fA-F]{6}$/.test(t)) row.picked(t.toLowerCase())
                }
                onAccepted: apply()
                onEditingFinished: apply()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: hexIn.text === "" && !hexIn.activeFocus
                    text: "#rrggbb"
                    color: Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.4)
                    font: hexIn.font
                }
            }
        }

        // pick any colour by eye
        Rectangle {
            width: 32; height: 32; radius: row.app.rr(16)
            color: row.pickerOpen || palHov.hovered ? Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.16)
                                                    : Qt.rgba(row.app.cFg.r, row.app.cFg.g, row.app.cFg.b, 0.09)
            HoverHandler { id: palHov }
            Text {
                anchors.centerIn: parent
                text: "palette"
                color: row.app.cFg
                font.family: "Material Symbols Rounded"
                font.pixelSize: row.app.fs(17)
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!row.pickerOpen) picker.load(row.value !== "" ? row.value : row.autoColour)
                    row.pickerOpen = !row.pickerOpen
                }
            }
        }
    }

    ColourPicker {
        id: picker
        app: row.app
        visible: row.pickerOpen
        onPicked: hex => row.picked(hex)
    }
}
