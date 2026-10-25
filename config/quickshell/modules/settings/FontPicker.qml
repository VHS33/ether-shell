import QtQuick
import QtQuick.Layouts
import qs.services

// Font cards (each "Aa" and its name, in that font; the one in use
// highlighted), then a search of every other font installed.
// Settings > General > Fonts, once for text and once for the terminal.
ColumnLayout {
    id: fp
    property var app
    property var picks: []          // the cards
    property var all: []            // what the search looks through
    property string current: ""
    property string sample: "Aa"
    signal picked(string family)

    Layout.fillWidth: true
    spacing: 10

    Flow {
        id: grid
        Layout.fillWidth: true
        spacing: 8
        readonly property int cols: width > 640 ? 4 : width > 420 ? 3 : 2
        readonly property real cardW: Math.floor((width - spacing * (cols - 1)) / cols)
        Repeater {
            model: fp.picks
            delegate: Rectangle {
                id: fc
                required property string modelData
                readonly property bool isCurrent: modelData === fp.current
                width: grid.cardW
                height: 86
                radius: 14
                color: isCurrent ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                     : fcHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.10)
                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.05)
                border.width: isCurrent ? 2 : 0
                border.color: app.cBlue
                Behavior on color { ColorAnimation { duration: app.animQuick } }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    text: fp.sample
                    color: fc.isCurrent ? app.cBlue : app.cFg
                    font.family: fc.modelData
                    font.pixelSize: app.fs(26)
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                    horizontalAlignment: Text.AlignHCenter
                    text: fc.modelData
                    elide: Text.ElideRight
                    color: fc.isCurrent ? app.cBlue : app.cFg
                    font.family: fc.modelData
                    font.pixelSize: app.fs(12)
                }
                HoverHandler { id: fcHov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: fc.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!fc.isCurrent) fp.picked(fc.modelData)
                }
            }
        }
    }

    // ---- any other font: type to find it ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 19
        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
        border.width: findIn.activeFocus ? 1 : 0
        border.color: app.cBlue
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8
            Text {
                text: "search"
                color: app.cFaint
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(14)
            }
            TextInput {
                id: findIn
                Layout.fillWidth: true
                color: app.cFg
                selectionColor: app.cBlue
                font.family: Theme.uiFont
                font.pixelSize: app.fs(12)
                clip: true
                Keys.onEscapePressed: text = ""
                onAccepted: if (found.length > 0) { fp.picked(found[0]); text = "" }
                Text {
                    visible: !findIn.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Another font: type its name (" + fp.all.length + " installed)"
                    color: app.cFaint
                    font: findIn.font
                }
                readonly property var found: {
                    const q = text.trim().toLowerCase()
                    if (q === "") return []
                    return fp.all.filter(f => f.toLowerCase().indexOf(q) >= 0).slice(0, 8)
                }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: findIn.found.length > 0
        Repeater {
            model: findIn.found
            delegate: Rectangle {
                id: hit
                required property string modelData
                readonly property bool isCurrent: modelData === fp.current
                width: hitText.implicitWidth + 26
                height: 32
                radius: 16
                color: isCurrent ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                     : hitHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                Text {
                    id: hitText
                    anchors.centerIn: parent
                    text: hit.modelData
                    color: hit.isCurrent ? app.cBlue : app.cFg
                    font.family: hit.modelData
                    font.pixelSize: app.fs(13)
                }
                HoverHandler { id: hitHov }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { fp.picked(hit.modelData); findIn.text = "" }
                }
            }
        }
    }
}
