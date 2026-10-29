import QtQuick
import QtQuick.Layouts
import qs.services

// A card for each installed cursor theme (its own arrow, hand and text
// cursors), the one in use highlighted.  Settings > Mouse and the welcome.
ColumnLayout {
    property var app
    Layout.fillWidth: true
    spacing: 10

    // a card for each installed theme: its own arrow, hand and text cursors
    Flow {
        id: curGrid
        Layout.fillWidth: true
        spacing: 8
        readonly property int cols: width > 640 ? 4 : width > 420 ? 3 : 2
        readonly property real cardW: Math.floor((width - spacing * (cols - 1)) / cols)
        Repeater {
            model: Cursors.themes
            delegate: Rectangle {
                id: ct
                required property var modelData
                readonly property bool isCurrent: modelData.id === Cursors.current
                width: curGrid.cardW
                height: 96
                radius: app.rr(14)
                color: isCurrent ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                     : ctHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.10)
                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.05)
                border.width: isCurrent ? 2 : 0
                border.color: app.cBlue
                Behavior on color { ColorAnimation { duration: app.animQuick } }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    spacing: 14
                    Repeater {
                        model: ["arrow", "hand", "text"]
                        Image {
                            required property string modelData
                            width: 32; height: 32
                            // (with when it was made: a remade preview, Ether in a
                            // new colour, is loaded again rather than the old copy)
                            source: "file://" + ct.modelData.previews + "/" + modelData + ".png?" + ct.modelData.made
                            sourceSize: Qt.size(48, 48)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            cache: false
                            asynchronous: true
                        }
                    }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                    horizontalAlignment: Text.AlignHCenter
                    text: ct.modelData.name
                    elide: Text.ElideRight
                    color: ct.isCurrent ? app.cBlue : app.cFg
                    font.family: Theme.uiFont
                    font.weight: Font.Medium
                    font.pixelSize: app.fs(12)
                }
                HoverHandler { id: ctHov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: ct.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!ct.isCurrent) Cursors.pick(ct.modelData.id)
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: Cursors.loaded && Cursors.themes.length === 0
        text: "No cursor themes found. Install one (for example: sudo pacman -S capitaine-cursors), then open this page again."
        wrapMode: Text.WordWrap
        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.6)
        font.family: Theme.uiFont
        font.pixelSize: app.fs(12)
    }
}
