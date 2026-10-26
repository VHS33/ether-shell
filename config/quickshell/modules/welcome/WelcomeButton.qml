import QtQuick
import qs.services

// a pill button on the welcome pages; the main one in the accent
Rectangle {
    id: btn
    property var app
    property string label
    property bool primary: false
    signal clicked()
    implicitWidth: btnT.implicitWidth + 40
    implicitHeight: 40
    radius: 20
    color: primary ? (hov.hovered ? Qt.lighter(app.cBlue, 1.08) : app.cBlue)
         : hov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.14) : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
    HoverHandler { id: hov }
    Text {
        id: btnT
        anchors.centerIn: parent
        text: btn.label
        color: btn.primary ? btn.app.cOnAccent : btn.app.cFg
        font.family: Theme.uiFont
        font.pixelSize: btn.app.fs(13)
        font.bold: btn.primary
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
}
