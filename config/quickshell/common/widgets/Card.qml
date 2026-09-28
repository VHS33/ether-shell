import QtQuick
import QtQuick.Layouts
import Quickshell

// a titled card; children go in the body, `trailing` sits
// at the right of the title row
Rectangle {
    id: card
    property var app
    property string title: ""
    property string desc: ""
    default property alias body: bodyCol.data
    property alias trailing: trail.data

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 34
    radius: 18
    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

    // search finds settings by these (see win.searchIndex)
    readonly property bool settingCard: true
    // a moment's outline, when search brings you here
    property bool flash: false
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 2
        border.color: card.app ? card.app.cBlue : "white"
        opacity: card.flash ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 350 } }
    }
    Timer { running: card.flash; interval: 1600; onTriggered: card.flash = false }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 17
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 18
            visible: card.title !== "" || trail.children.length > 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.title
                    color: card.app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(14)
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.desc
                    color: card.app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                }
            }

            RowLayout { id: trail; spacing: 8 }
        }

        ColumnLayout {
            id: bodyCol
            Layout.fillWidth: true
            spacing: 4
            visible: children.length > 0
        }
    }
}
