import QtQuick
import QtQuick.Layouts
import Quickshell

// ============================================================
//   KEYBIND CHEATSHEET  (SUPER + /)
//   Reads hyprctl binds directly, so it can never drift from
//   the real config.  Binds with a description show it; the
//   rest fall back to their dispatcher.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: winK
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.cheatShown

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: app.scrim(0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: app.cheatShown = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 200, 1100)
            height: Math.min(parent.height - 160, 760)
            radius: 22
            color: app.cCard
            border.width: 1
            border.color: app.cBorder

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "\u{f030c}"
                        color: app.cBlue
                        font.family: app.font
                        font.pixelSize: app.fs(20)
                    }
                    Text {
                        text: "Keybinds"
                        color: app.cFg
                        font.family: app.font
                        font.pixelSize: app.fs(20)
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: app.cheatBinds.length + " bound"
                        color: app.cFaint
                        font.family: app.font
                        font.pixelSize: app.fs(12)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: app.cBorder
                    opacity: 0.7
                }

                // three columns, filled top to bottom
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 22

                    Repeater {
                        model: 3

                        delegate: ColumnLayout {
                            required property int index
                            readonly property int per:
                                Math.ceil(app.cheatBinds.length / 3)

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            Repeater {
                                model: app.cheatBinds.slice(
                                    index * per, (index + 1) * per)

                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 132
                                        implicitHeight: 24
                                        radius: 8
                                        color: app.cTile

                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 10
                                            text: modelData.keys
                                            color: app.cBlue
                                            font.family: app.font
                                            font.pixelSize: app.fs(12)
                                            font.bold: true
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: app.cDim
                                        font.family: app.font
                                        font.pixelSize: app.fs(12)
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "click anywhere to close"
                    color: app.cFaint
                    font.family: app.font
                    font.pixelSize: app.fs(11)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
