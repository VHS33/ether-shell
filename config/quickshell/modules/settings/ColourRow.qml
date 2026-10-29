import QtQuick
import QtQuick.Layouts
import Quickshell

// A colour for a graph's line: Auto (the wallpaper's own accents, one per
// stat), one of the theme's colours, any colour picked by eye (the palette
// button), or one typed as #rrggbb.  `value` is what's saved: "auto", a
// colour's name or the hex; picking one emits picked(value).
ColumnLayout {
    id: cr
    property var app
    property string value: ""
    property string stat: "cpu"         // whose Auto colour to show
    signal picked(string value)
    spacing: 10

    readonly property string current: value !== "" ? value : "auto"
    readonly property bool custom: /^#[0-9a-fA-F]{6}$/.test(current)
    property bool pickerOpen: false

    RowLayout {
        spacing: 8

        // Auto: follows the wallpaper (its colour right now as the dot)
        Rectangle {
            readonly property bool on: cr.current === "auto"
            implicitWidth: autoRow.implicitWidth + 20
            implicitHeight: 30
            radius: cr.app.rr(15)
            color: on ? Qt.rgba(cr.app.cBlue.r, cr.app.cBlue.g, cr.app.cBlue.b, 0.22)
                 : autoHov.hovered ? Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.14)
                 : Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.09)
            border.width: on ? 2 : 0
            border.color: cr.app.cFg
            HoverHandler { id: autoHov }
            Row {
                id: autoRow
                anchors.centerIn: parent
                spacing: 7
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: cr.app.rr(7)
                    color: cr.app.statColour("auto", cr.stat)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Auto"
                    color: cr.app.cFg
                    font.family: cr.app.uiFont
                    font.pixelSize: cr.app.fs(13)
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cr.picked("auto")
            }
        }

        Repeater {
            model: cr.app.statColourNames
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: cr.current === modelData
                implicitWidth: 26
                implicitHeight: 26
                radius: cr.app.rr(13)
                color: cr.app.statColour(modelData, cr.stat)
                border.width: on ? 3 : swHov.hovered ? 2 : 0
                border.color: cr.app.cFg
                HoverHandler {
                    id: swHov
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cr.picked(modelData)
                }
            }
        }

        // any colour: type it, then Enter (or click away)
        Rectangle {
            implicitWidth: 104
            implicitHeight: 30
            radius: cr.app.rr(15)
            color: Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, hexIn.activeFocus ? 0.14 : 0.09)
            border.width: cr.custom ? 2 : 0
            border.color: cr.app.cFg

            Rectangle {
                id: hexDot
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: cr.app.rr(6)
                color: /^#[0-9a-fA-F]{6}$/.test(hexIn.text) ? hexIn.text : "transparent"
                border.width: 1
                border.color: Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.4)
            }
            TextInput {
                id: hexIn
                anchors.left: hexDot.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: cr.custom ? cr.current : ""
                color: cr.app.cFg
                font.family: cr.app.uiFont
                font.pixelSize: cr.app.fs(13)
                maximumLength: 7
                selectByMouse: true
                validator: RegularExpressionValidator {
                    regularExpression: /#?[0-9a-fA-F]{0,6}/
                }
                function apply() {
                    let t = text.trim();
                    if (t !== "" && t[0] !== "#")
                        t = "#" + t;
                    if (/^#[0-9a-fA-F]{6}$/.test(t))
                        cr.picked(t.toLowerCase());
                }
                onAccepted: apply()
                onEditingFinished: apply()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: hexIn.text === "" && !hexIn.activeFocus
                    text: "#rrggbb"
                    color: Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.4)
                    font: hexIn.font
                }
            }
        }

        // pick any colour by eye
        Rectangle {
            implicitWidth: 30
            implicitHeight: 30
            radius: cr.app.rr(15)
            color: cr.pickerOpen || palHov.hovered ? Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.16) : Qt.rgba(cr.app.cFg.r, cr.app.cFg.g, cr.app.cFg.b, 0.09)
            HoverHandler {
                id: palHov
            }
            Text {
                anchors.centerIn: parent
                text: "palette"
                color: cr.app.cFg
                font.family: "Material Symbols Rounded"
                font.pixelSize: cr.app.fs(17)
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!cr.pickerOpen)
                        picker.load(cr.app.statColour(cr.current, cr.stat));
                    cr.pickerOpen = !cr.pickerOpen;
                }
            }
        }
    }

    ColourPicker {
        id: picker
        app: cr.app
        visible: cr.pickerOpen
        onPicked: hex => cr.picked(hex)
    }
}
