import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// ============================================================
//   ON-SCREEN DISPLAY
//   Appears when the volume or mute state changes and fades out
//   on its own.  Driven by watching Pipewire rather than by the
//   keybinds, so it shows for any source of change — media keys,
//   the sidebar sliders, pavucontrol, another app.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winOsd
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.osdShown

        anchors { bottom: true }
        margins { bottom: 180 }
        implicitWidth: 320
        implicitHeight: 76
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        mask: Region { x: 0; y: 0; width: 0; height: 0 }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            radius: 20
            color: app.cCard
            border.width: 1
            border.color: app.cBorder

            // slides up slightly as it appears
            y: app.osdShown ? 0 : 10
            opacity: app.osdShown ? 1 : 0
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 14

                Text {
                    text: app.osdMuted ? "\u{f075f}"
                          : app.osdValue > 0.5 ? "\u{f057e}"
                          : app.osdValue > 0 ? "\u{f0580}"
                          : "\u{f0581}"
                    color: app.osdMuted ? app.cFaint : app.cMauve
                    font.family: app.font
                    font.pixelSize: app.fs(20)
                    Layout.preferredWidth: 24
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: app.cSurf

                    Rectangle {
                        width: parent.width * (app.osdMuted ? 0 : app.osdValue)
                        height: parent.height
                        radius: 3
                        color: app.cMauve
                        Behavior on width {
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Text {
                    text: app.osdMuted ? "muted"
                                       : Math.round(app.osdValue * 100) + "%"
                    color: app.cDim
                    font.family: app.font
                    font.pixelSize: app.fs(12)
                    Layout.preferredWidth: 46
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
