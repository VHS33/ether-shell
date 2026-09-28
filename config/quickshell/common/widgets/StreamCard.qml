import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// one application's stream: icon, name, what it is playing,
// mute, and its own volume
Rectangle {
    id: sc
    property var app
    property var node
    property real maxVol: 1
    property color accent: app.cBlue

    readonly property var au: node?.audio ?? null
    readonly property bool muted: au?.muted ?? false
    readonly property var props: node?.properties ?? ({})
    readonly property string appName:
        props["application.name"] || node?.description || node?.name || "Application"
    readonly property string mediaName: {
        const m = props["media.name"] ?? ""
        return m !== appName ? m : ""
    }

    Layout.fillWidth: true
    implicitHeight: scRow.implicitHeight + 30
    radius: 18
    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

    RowLayout {
        id: scRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        Rectangle {
            implicitWidth: 46
            implicitHeight: 46
            radius: 14
            color: Qt.rgba(sc.app.cFg.r, sc.app.cFg.g, sc.app.cFg.b, 0.08)
            IconImage {
                anchors.centerIn: parent
                implicitSize: 28
                source: sc.app.iconFor(sc.props["application.icon-name"]
                                       || sc.props["application.process.binary"]
                                       || sc.appName)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: sc.appName
                color: sc.app.cFg
                font.family: "Inter"
                font.pixelSize: app.fs(13)
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: sc.mediaName
                color: sc.app.cDim
                font.family: "Inter"
                font.pixelSize: app.fs(11)
                elide: Text.ElideRight
            }

            Slider {
                app: sc.app
                to: sc.maxVol
                tick: 1
                value: sc.au?.volume ?? 0
                muted: sc.au?.muted ?? false
                accent: sc.accent
                label: sc.muted ? "Muted" : Math.round(value * 100) + "%"
                onMoved: v => {
                    if (!sc.au) return
                    sc.au.volume = v
                    if (v > 0 && sc.au.muted) sc.au.muted = false
                }
            }
        }

        IconBtn {
            app: sc.app
            accent: sc.app.cRed
            active: sc.au?.muted ?? false
            glyph: active ? "volume_off" : "volume_up"
            onClicked: if (sc.au) sc.au.muted = !sc.au.muted
        }
    }
}
