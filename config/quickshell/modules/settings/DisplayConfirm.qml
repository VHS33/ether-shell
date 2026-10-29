import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// "Keep these display settings?"  After Apply on the Displays page the old
// settings come back by themselves after 15 seconds unless they're kept
// (services/Displays.qml), so a mode that leaves a screen black undoes
// itself.  This asks in the middle of every screen while the countdown
// runs, whether Settings is open, scrolled away, or on the other monitor.
// Enter keeps, Escape goes back.  Nothing here goes over the network.
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    LazyLoader {
        id: perScreen
        required property var modelData
        active: rootV.app.revertLeft > 0

    PanelWindow {
        id: dc
        readonly property var app: rootV.app
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // no anchors: the compositor centres it
        implicitWidth: 460
        implicitHeight: card.implicitHeight + 32
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell"
        // the main screen's copy takes the keyboard, for Enter and Escape
        WlrLayershell.keyboardFocus: modelData.name === app.mainScreen
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 16
            implicitHeight: col.implicitHeight + 40
            radius: app.rr(26)
            color: dc.app.cBg
            border.width: 1
            border.color: Qt.rgba(dc.app.cBorder.r, dc.app.cBorder.g, dc.app.cBorder.b, 0.6)
            focus: true
            Keys.onReturnPressed: dc.app.keepDisplays()
            Keys.onEnterPressed: dc.app.keepDisplays()
            Keys.onEscapePressed: dc.app.revertDisplays()

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 6

                Text {
                    text: "Keep these display settings?"
                    color: dc.app.cFg
                    font.family: Theme.uiFont
                    font.weight: Font.DemiBold
                    font.pixelSize: dc.app.fs(16)
                }
                Text {
                    Layout.fillWidth: true
                    text: "Going back to the previous settings in " + dc.app.revertLeft
                          + (dc.app.revertLeft === 1 ? " second." : " seconds.")
                    color: dc.app.cDim
                    font.family: Theme.uiFont
                    font.pixelSize: dc.app.fs(12)
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    Repeater {
                        // Go back, plain; Keep, filled (the one to press)
                        model: [{ t: "Go back", keep: false }, { t: "Keep", keep: true }]
                        delegate: Rectangle {
                            id: btn
                            required property var modelData
                            implicitWidth: label.implicitWidth + 36
                            implicitHeight: 38
                            radius: app.rr(19)
                            color: modelData.keep ? dc.app.cBlue
                                 : hov.hovered ? Qt.rgba(dc.app.cFg.r, dc.app.cFg.g, dc.app.cFg.b, 0.14)
                                 : Qt.rgba(dc.app.cFg.r, dc.app.cFg.g, dc.app.cFg.b, 0.08)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: btn.modelData.t
                                color: btn.modelData.keep ? dc.app.cOnAccent : dc.app.cFg
                                font.family: Theme.uiFont
                                font.weight: Font.DemiBold
                                font.pixelSize: dc.app.fs(13)
                            }
                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: btn.modelData.keep ? dc.app.keepDisplays() : dc.app.revertDisplays() }
                        }
                    }
                }
            }
        }
    }
    }
}
