import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// ============================================================
//   MEDIA CARD
//   Opens under the bar from the centre pill.  The artwork, large
//   and rounded, is also blurred into the card's background, so
//   each track tints it.  Full controls, a draggable seek bar, a
//   switcher when several apps are playing, the player's own
//   volume, and the cava visualiser along the bottom edge.
//
//   The window stays mapped while a player exists and the card
//   slides in; mapping a new surface each time is what made
//   panels lag.  Closed, the mask is empty and clicks pass through.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // part of the older pill style: only built when that's in use
        active: modelData.name === app.mainScreen && !app.barMorph

    PanelWindow {
        id: winM
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.player !== null && !app.barMorph
        readonly property bool open: app.cardShown
        readonly property var p: app.player

        anchors { top: true }
        margins { top: app.barBottom + 6 }
        implicitWidth: 580
        implicitHeight: card.implicitHeight + 16
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        property Region shownMask: Region { x: 8; y: 8; width: winM.width - 16; height: winM.height - 16 }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask


        Rectangle {
            id: card
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            y: winM.open ? 8 : -implicitHeight - 20
            opacity: winM.open ? 1 : 0
            visible: opacity > 0
            Behavior on y { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            implicitHeight: cardBody.implicitHeight
            radius: 28
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)

            MediaBody {
                id: cardBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                app: rootV.app
                radius: card.radius
            }
        }
    }
    }
}
