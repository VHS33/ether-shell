import QtQuick
import QtQuick.Layouts
import Quickshell

// accent-coloured section heading between groups of cards
Text {
    property var app
    readonly property bool sectionLabel: true
    Layout.topMargin: 14
    Layout.bottomMargin: 6
    Layout.leftMargin: 18
    color: app.cBlue
    font.family: "Inter"
    font.pixelSize: app.fs(12)
    font.bold: true
}
