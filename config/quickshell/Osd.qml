import QtQuick
import QtQuick.Layouts
import Quickshell

// ============================================================
//   ON-SCREEN DISPLAY
//   One pill for volume, microphone, brightness and night light
//   (app.osdKind), low in the middle of the main screen.  It never
//   takes input: the mask is empty.  Another change while it's up
//   swaps the contents in place instead of stacking a second one.
//
//   Volume and the microphone come from watching PipeWire, so any
//   source of change shows it: keys, the sidebar, other apps.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winOsd
        required property var modelData
        screen: modelData
        // stays mapped on the main screen; the pill fades and slides
        visible: modelData.name === app.mainScreen

        anchors { bottom: true }
        margins { bottom: 150 }
        implicitWidth: 400
        implicitHeight: 96
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region { width: 0; height: 0 }

        readonly property string kind: app.osdKind
        readonly property bool off: app.osdMuted
        readonly property real value: app.osdValue
        readonly property bool hasBar: kind === "volume" || kind === "brightness"
                                       || (kind === "mic" && !off)

        readonly property color accent:
            kind === "brightness" || kind === "night" ? app.cYellow
            : kind === "mic" ? app.cTeal : app.cMauve

        readonly property string glyph: {
            if (kind === "mic") return off ? "mic_off" : "mic"
            if (kind === "night") return off ? "light_mode" : "dark_mode"
            if (kind === "brightness")
                return value < 0.34 ? "brightness_low" : value < 0.67 ? "brightness_medium" : "brightness_high"
            if (off) return "volume_off"
            return value === 0 ? "volume_mute" : value < 0.34 ? "volume_down"
                 : value < 0.67 ? "volume_down" : "volume_up"
        }
        readonly property string title: {
            if (kind === "mic") return off ? "Microphone muted" : "Microphone on"
            if (kind === "night") return off ? "Night light off" : "Night light on"
            if (kind === "brightness") return "Brightness"
            return off ? "Muted" : "Volume"
        }
        readonly property string amount:
            hasBar && !(kind === "volume" && off) ? Math.round(value * 100) + "%" : ""

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 12
            height: 76
            y: app.osdShown ? 6 : 22
            opacity: app.osdShown ? 1 : 0
            visible: opacity > 0
            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            radius: height / 2
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 24
                spacing: 14

                // the icon, in an accent circle (faint when muted or off)
                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 24
                    color: winOsd.off ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : winOsd.accent
                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                    Text {
                        anchors.centerIn: parent
                        text: winOsd.glyph
                        color: winOsd.off ? app.cDim : app.cOnAccent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(22)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: winOsd.title
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                            font.bold: true
                        }
                        Text {
                            visible: text !== ""
                            text: winOsd.amount
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: winOsd.hasBar
                        implicitHeight: 8
                        radius: 4
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                        Rectangle {
                            width: parent.width * (winOsd.kind === "volume" && winOsd.off ? 0 : winOsd.value)
                            height: parent.height
                            radius: 4
                            color: winOsd.accent
                            Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }
}
