import QtQuick
import qs.services

// A window on the Wired lock screen: a thin double frame on dark glass, and
// a light title bar with its name in English and Japanese (the Japanese
// only when a Japanese font is installed) and three little boxes at the
// right, like a 90s terminal's.  What it holds goes in `body`.  Drag it by
// its title bar to move it (it comes to the front); where it's left is
// kept in `spots` (the lock's, by title), so it's there again next time
// you lock, until the shell restarts.
Item {
    id: win
    property string title: ""
    property string jp: ""
    property bool showJp: true
    property color ink: "#0a0c0e"
    property var spots: null
    default property alias body: inner.data
    readonly property int bar: 22
    signal raised()


    Component.onCompleted: {
        const s = spots ? spots[title] : undefined
        if (s) { x = s.x; y = s.y }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.04, 0.05, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.35)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.11)
        }
    }
    Rectangle {
        id: titleBar
        width: parent.width; height: win.bar
        color: Qt.rgba(0.93, 0.94, 0.95, 0.88)
        // Moved by hand rather than with drag.target: it follows from the
        // very first movement, so a drag still lands when the screen is busy
        // and movements arrive bunched together.  Kept on the screen.
        MouseArea {
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point grab: Qt.point(0, 0)        // where in the window it was picked up
            function follow(mouse) {
                const p = mapToItem(win.parent, mouse.x, mouse.y)
                const maxX = win.parent ? win.parent.width - win.width : 0
                const maxY = win.parent ? win.parent.height - win.height : 0
                win.x = Math.max(0, Math.min(maxX, p.x - grab.x))
                win.y = Math.max(0, Math.min(maxY, p.y - grab.y))
            }
            onPressed: mouse => {
                const p = mapToItem(win.parent, mouse.x, mouse.y)
                grab = Qt.point(p.x - win.x, p.y - win.y)
                win.raised()
            }
            onPositionChanged: mouse => { if (pressed) follow(mouse) }
            onReleased: mouse => {
                follow(mouse)
                if (win.spots) win.spots[win.title] = { x: win.x, y: win.y }
            }
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                text: win.title
                color: win.ink
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: 15
            }
            Text {
                visible: win.showJp && win.jp !== ""
                text: win.jp
                color: win.ink
                font.family: "IPAexGothic"
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: 3
                delegate: Rectangle { width: 9; height: 9; color: "transparent"; border.width: 1; border.color: win.ink }
            }
        }
    }
    Item {
        id: inner
        anchors.fill: parent
        anchors.topMargin: win.bar
    }
}
