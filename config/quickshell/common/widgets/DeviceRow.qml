import QtQuick
import QtQuick.Layouts
import Quickshell

// one selectable output or input device
Rectangle {
    id: dr
    property var app
    property var node
    property bool isDefault: false
    property bool isInput: false
    property color accent: app.cBlue
    signal chosen()

    Layout.fillWidth: true
    implicitHeight: 54
    radius: 14
    color: isDefault ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
         : drHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
         : "transparent"
    Behavior on color { ColorAnimation { duration: app.animQuick } }

    readonly property string title:
        node?.nickname || node?.description || node?.name || "Unknown device"
    readonly property string sub: {
        const d = node?.description ?? ""
        return d !== "" && d !== title ? d : (node?.name ?? "")
    }
    readonly property string glyph: {
        const s = ((node?.description ?? "") + " " + (node?.name ?? "")).toLowerCase()
        if (isInput) return "mic"
        if (s.includes("hdmi") || s.includes("displayport")) return "monitor"
        if (s.includes("headphone") || s.includes("headset")) return "headphones"
        return "speaker"
    }

    HoverHandler { id: drHov }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: 11
            color: dr.isDefault ? dr.accent : Qt.rgba(dr.app.cFg.r, dr.app.cFg.g, dr.app.cFg.b, 0.08)
            Text {
                anchors.centerIn: parent
                text: dr.glyph
                color: dr.isDefault ? dr.app.cOnAccent : dr.app.cDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(16)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: dr.title
                color: dr.app.cFg
                font.family: "Inter"
                font.pixelSize: app.fs(13)
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: dr.sub
                color: dr.app.cFaint
                font.family: "Inter"
                font.pixelSize: app.fs(10)
                elide: Text.ElideRight
            }
        }

        Text {
            visible: dr.isDefault
            text: "In use"
            color: dr.accent
            font.family: "Inter"
            font.pixelSize: app.fs(11)
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: dr.isDefault ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!dr.isDefault) dr.chosen()
    }
}
