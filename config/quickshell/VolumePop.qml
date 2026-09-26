import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// ============================================================
//   VOLUME POPOVER
//   Opens under the right pill from the volume segment: output
//   and mic sliders, and one-click output switching.  Closes when
//   the pointer has been away from it for a moment, on Esc, or
//   by clicking the volume segment again.
//
//   The output list is a Repeater over Pipewire.nodes with the
//   filter as `visible`: no live nodes in JS arrays.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    component VolRow: RowLayout {
        id: vr
        property var app
        property var au: null
        property string glyph: ""
        property string mutedGlyph: ""
        property color accent: app.cBlue
        readonly property real v: au?.volume ?? 0
        readonly property bool muted: au?.muted ?? false

        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: vrHov.hovered ? Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.12) : "transparent"
            HoverHandler { id: vrHov }
            Text {
                anchors.centerIn: parent
                text: vr.muted ? vr.mutedGlyph : vr.glyph
                color: vr.muted ? vr.app.cFaint : vr.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: vr.app.fs(16)
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (vr.au) vr.au.muted = !vr.au.muted
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 24
            Rectangle {
                id: vrTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.08)
                Rectangle {
                    width: vrTrack.width * Math.min(1, vr.v)
                    height: parent.height
                    radius: 4
                    color: vr.muted ? vr.app.cFaint : vr.accent
                }
            }
            Rectangle {
                width: 4
                height: 18
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(vrTrack.width - width, vrTrack.width * Math.min(1, vr.v) - 2))
                color: vr.muted ? vr.app.cFaint : vr.accent
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function set(x) {
                    if (!vr.au) return
                    vr.au.volume = Math.max(0, Math.min(1, x / width))
                    if (vr.au.muted) vr.au.muted = false
                }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x) }
                onWheel: w => {
                    if (!vr.au) return
                    vr.au.volume = Math.max(0, Math.min(1,
                        vr.au.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
                }
            }
        }

        Text {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: vr.muted ? "Muted" : Math.round(vr.v * 100) + "%"
            color: vr.app.cDim
            font.family: "Inter"
            font.pixelSize: vr.app.fs(11)
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
        active: modelData.name === app.mainScreen && !app.rightMorph

    PanelWindow {
        id: winV
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Stays mapped and animates itself: mapping a new surface on each
        // open lagged, and Hyprland's own layer fade fought the shell's.
        // Closed, nothing shows and the mask lets every click through.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.volPopShown

        anchors { top: true; right: true }
        margins { top: app.barBottom + 6; right: app.gap }
        implicitWidth: 360
        implicitHeight: card.implicitHeight + 16
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        property Region shownMask: Region { x: 8; y: 8; width: winV.width - 16; height: winV.height - 16 }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource

        PwObjectTracker {
            objects: winV.open ? Pipewire.nodes.values : []
        }

        onOpenChanged: if (open) { entered = false; keys.forceActiveFocus(); leaveTimer.stop() }

        // close once the pointer has been gone for a moment; it only
        // arms after the pointer has been over the popover once
        property bool entered: false
        Timer {
            id: leaveTimer
            interval: 700
            onTriggered: app.volPopShown = false
        }

        Rectangle {
            id: card
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            // drops down from the bar
            anchors.topMargin: winV.open ? 8 : -16
            opacity: winV.open ? 1 : 0
            visible: opacity > 0
            Behavior on anchors.topMargin { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            implicitHeight: col.implicitHeight + 32
            radius: 22
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) { winV.entered = true; leaveTimer.stop() }
                    else if (winV.entered) leaveTimer.restart()
                }
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: app.volPopShown = false
            }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "Sound"
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(15)
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: winV.sink?.nickname || winV.sink?.description || "No output"
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 16
                        color: gHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : "transparent"
                        HoverHandler { id: gHov }
                        Text {
                            anchors.centerIn: parent
                            text: "settings"
                            color: gHov.hovered ? app.cFg : app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(15)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                app.volPopShown = false
                                app.settingsPage = 12
                                app.settingsShown = true
                            }
                        }
                    }
                }

                VolRow {
                    app: rootV.app
                    au: winV.sink?.audio ?? null
                    glyph: "volume_up"
                    mutedGlyph: "volume_off"
                }
                VolRow {
                    app: rootV.app
                    au: winV.source?.audio ?? null
                    glyph: "mic"
                    mutedGlyph: "mic_off"
                    accent: rootV.app.cTeal
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)
                }

                Text {
                    text: "Output"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: Pipewire.nodes
                        delegate: Rectangle {
                            id: outRow
                            required property var modelData
                            readonly property bool isOut:
                                !!modelData && !!modelData.audio && modelData.isSink && !modelData.isStream
                            readonly property bool isDefault: modelData === winV.sink
                            visible: isOut
                            Layout.fillWidth: true
                            implicitHeight: isOut ? 38 : 0
                            radius: 12
                            color: isDefault ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.16)
                                 : oHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                            HoverHandler { id: oHov }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    Layout.fillWidth: true
                                    text: outRow.modelData?.nickname || outRow.modelData?.description
                                          || outRow.modelData?.name || "Output"
                                    color: outRow.isDefault ? app.cFg : app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                    font.bold: outRow.isDefault
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: outRow.isDefault
                                    text: "check"
                                    color: app.cBlue
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(14)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: outRow.isDefault ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: if (!outRow.isDefault) Pipewire.preferredDefaultAudioSink = outRow.modelData
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
