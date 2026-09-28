import QtQuick

// Uptime: an example Ether Shell plugin.  A bar item gets the toolkit as
// `ether` (see PluginApi.qml): the theme's colours and fonts, ether.read()
// for a command's output, ether.notify() and more.
//
// Its size is what the bar makes room for (implicitWidth and implicitHeight).
// The click area sits beside the Row, not inside it: a Row sizes itself from
// what's in it, so something stretched to fill it inside would confuse that.
Item {
    id: item
    property var ether                 // given by Ether Shell
    property string up: "\u2026"
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "schedule"
            color: item.ether ? item.ether.accent : "white"
            font.family: item.ether ? item.ether.iconFont : ""
            font.pixelSize: 16
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: item.up
            color: item.ether ? item.ether.fg : "white"
            font.family: item.ether ? item.ether.font : ""
            font.pixelSize: item.ether ? item.ether.fs(12) : 12
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: item.ether.notify("Uptime", "Up " + item.up + " since the computer started")
    }

    // the seconds since the computer started, as "3d 4h", "5h 12m" or "7m"
    function refresh() {
        ether.read(["cat", "/proc/uptime"], out => {
            const s = Math.floor(parseFloat(out))
            if (!(s >= 0)) return
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
            item.up = d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m"
        })
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: item.refresh() }
}
