import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Hyprland

// ============================================================
//   POWER MENU — full screen, nothing fires without a click here
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winP
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.powerShown

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: app.powerShown ? app.scrim(0.85) : "transparent"

        // no input at all while closed
        mask: Region {
            x: 0; y: 0
            width: app.powerShown ? winP.width : 0
            height: app.powerShown ? winP.height : 0
        }

        // click anywhere outside the card to back out
        MouseArea {
            anchors.fill: parent
            enabled: app.powerShown
            onClicked: app.powerShown = false
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 26
            visible: app.powerShown

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: app.userHost
                color: app.cDim
                font.family: app.font
                font.pixelSize: app.fs(14)
            }

            RowLayout {
                spacing: 18

                Repeater {
                    model: [
                        { g: "\u{f033e}", label: "Lock",     col: app.cBlue,
                          c: "hyprlock" },
                        { g: "\u{f04b2}", label: "Suspend",  col: app.cTeal,
                          c: "systemctl suspend" },
                        { g: "\u{f0343}", label: "Log out",  col: app.cYellow,
                          c: "hyprctl dispatch 'hl.dsp.exit()'" },
                        { g: "\u{f0709}", label: "Restart",  col: app.cPeach,
                          c: "systemctl reboot" },
                        { g: "\u{f0425}", label: "Shut down", col: app.cRed,
                          c: "systemctl poweroff" }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        implicitWidth: 132
                        implicitHeight: 132
                        radius: 22
                        color: pmHov.hovered ? modelData.col : app.cCard
                        border.width: 2
                        border.color: pmHov.hovered ? modelData.col : app.cBorder
                        scale: pmHov.hovered ? 1.05 : 1.0

                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        HoverHandler { id: pmHov }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.g
                                color: pmHov.hovered ? app.cOnAccent : modelData.col
                                font.family: app.font
                                font.pixelSize: app.fs(40)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: pmHov.hovered ? app.cOnAccent : app.cFg
                                font.family: app.font
                                font.pixelSize: app.fs(12)
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                app.powerShown = false
                                app.run(modelData.c)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 120
                implicitHeight: 36
                radius: 12
                color: canHov.hovered ? app.cSurf : "transparent"
                border.width: 1
                border.color: app.cBorder
                Behavior on color { ColorAnimation { duration: 130 } }
                HoverHandler { id: canHov }

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: app.cDim
                    font.family: app.font
                    font.pixelSize: app.fs(12)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: app.powerShown = false
                }
            }
        }
    }
}
