import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "lib/models.mjs" as Models

// ============================================================
//   LEFT PILL
//   Workspaces, then CPU / memory / GPU.  Scrolling anywhere on
//   the pill steps through workspaces.  Numbers sit in fixed-width
//   slots so the pill doesn't change width as they tick.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // one clickable stat: coloured glyph + fixed-width value, with a
    // hover highlight when it does something
    component Stat: Rectangle {
        id: st
        property var app
        property string glyph: ""
        property string value: ""
        property string widest: "100%"
        property color tint: app.cFg
        property bool clickable: false
        signal clicked()

        implicitWidth: stRow.implicitWidth + 14
        implicitHeight: 24
        radius: 12
        color: clickable && stHov.hovered
               ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11) : "transparent"
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: stHov }

        TextMetrics {
            id: stMetrics
            font.family: "Inter"
            font.pixelSize: st.app.fs(12)
            text: st.widest
        }

        Row {
            id: stRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: st.glyph
                color: st.tint
                font.family: "Material Symbols Rounded"
                font.pixelSize: st.app.fs(13)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: stMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: st.value
                color: st.app.cFg
                font.family: "Inter"
                font.pixelSize: st.app.fs(12)
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: st.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: st.clicked()
        }
    }

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // part of the older pill style: only built when that's in use
        active: modelData.name === app.mainScreen && !app.leftMorph

    PanelWindow {
        id: winL
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && !app.leftMorph

        anchors { top: true; left: true }
        margins { top: app.gap; left: app.gap }
        implicitWidth: leftRow.implicitWidth + 24
        implicitHeight: app.pillH
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // inset so the square blur corners hide under the rounded pill
        mask: Region { x: 6; y: 6; width: winL.width - 12; height: winL.height - 12 }

        Rectangle {
            anchors.fill: parent
            radius: app.pillH / 2
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)

            // scroll anywhere on the pill to change workspace
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: w => app.cycleWorkspace(w.angleDelta.y > 0 ? -1 : 1)
            }

            RowLayout {
                id: leftRow
                anchors.centerIn: parent
                spacing: 8

                // Workspace dots.  The active indicator is one pill that
                // slides between slots, so switching reads as movement.
                // Workspaces with windows are solid, empty ones a ring.
                Item {
                    id: wsStrip
                    readonly property int count: app.workspaceCount
                    readonly property int slot: 18
                    readonly property int gap: 2
                    readonly property int pitch: slot + gap
                    // -1 when focus is on the secondary monitor's workspace
                    readonly property int activeIndex:
                        app.mainWorkspaces.indexOf(app.activeWorkspace)

                    Layout.leftMargin: 4
                    implicitWidth: count * slot + (count - 1) * gap
                    implicitHeight: 18
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        width: 18
                        height: 10
                        radius: 5
                        x: wsStrip.activeIndex * wsStrip.pitch + (wsStrip.slot - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: app.cBlue
                        visible: wsStrip.activeIndex >= 0
                        Behavior on x {
                            NumberAnimation { duration: app.animNormal; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                        }
                    }

                    Repeater {
                        model: ScriptModel { values: Models.keyed(app.workspacesFor(app.mainScreen), w => w.id); objectProp: "_key" }

                        delegate: Item {
                            id: ws
                            required property var modelData
                            required property int index
                            readonly property bool active: modelData.id === app.activeWorkspace

                            x: index * wsStrip.pitch
                            width: wsStrip.slot
                            height: wsStrip.height

                            HoverHandler { id: wsHov }

                            Rectangle {
                                anchors.centerIn: parent
                                readonly property int d: wsHov.hovered ? 10 : 8
                                width: d
                                height: d
                                radius: d / 2
                                color: ws.modelData.occupied ? app.cDim : "transparent"
                                border.width: ws.modelData.occupied ? 0 : 1.5
                                border.color: app.cFaint
                                opacity: ws.active ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch(
                                    "hl.dsp.focus({ workspace = " + ws.modelData.id + " })")
                            }
                        }
                    }
                }

                Rectangle {
                    visible: app.barStats || (app.gpuOk && app.barGpu)
                    Layout.leftMargin: 4
                    Layout.rightMargin: 2
                    width: 1; height: 14
                    color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.8)
                }

                Stat {
                    app: rootV.app
                    visible: app.barStats
                    glyph: "memory"
                    value: app.cpuPct + "%"
                    tint: app.cGreen
                    clickable: true
                    onClicked: app.run(app.termCmd + " -e sh -c 'command -v btop >/dev/null && exec btop || exec top'")
                }
                Stat {
                    app: rootV.app
                    visible: app.barStats
                    glyph: "memory_alt"
                    value: app.memPct + "%"
                    tint: app.cPeach
                    clickable: true
                    onClicked: app.run(app.termCmd + " -e sh -c 'command -v btop >/dev/null && exec btop || exec top'")
                }
                Stat {
                    app: rootV.app
                    visible: app.gpuOk && app.barGpu
                    glyph: "developer_board"
                    value: app.gpuPct + "%"
                    tint: app.cMauve
                    clickable: true
                    onClicked: app.run("nvidia-settings")
                }
                Stat {
                    app: rootV.app
                    visible: app.gpuOk && app.barGpu
                    Layout.rightMargin: 2
                    glyph: "thermostat"
                    value: app.gpuTemp + "\u00b0"
                    widest: "100\u00b0"
                    tint: app.gpuTemp >= 80 ? app.cRed : app.gpuTemp >= 70 ? app.cPeach : app.cTeal
                }
            }
        }
    }
    }
}
