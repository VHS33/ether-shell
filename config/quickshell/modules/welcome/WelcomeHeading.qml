import QtQuick
import QtQuick.Layouts
import qs.services

// a welcome page's heading and what the page is for
ColumnLayout {
    id: h
    property var app
    property string title
    property string sub
    Layout.fillWidth: true
    spacing: 4
    Text {
        text: h.title
        color: h.app.cFg
        font.family: Theme.uiFont
        font.pixelSize: h.app.fs(22)
        font.bold: true
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: h.sub
        color: h.app.cDim
        font.family: Theme.uiFont
        font.pixelSize: h.app.fs(13)
    }
}
