import QtQuick
import Quickshell

// ============================================================
//   ISLAND CATCHER
//   A transparent layer on every screen that sits just under the
//   three islands.  While one is open it takes the whole screen,
//   so a click anywhere outside closes it (and only closes it: the
//   click doesn't go on to whatever is underneath).  With nothing
//   open, its mask is empty and every click passes straight through.
//
//   Created just before the islands in shell.qml: layer surfaces
//   made later sit on top, so the islands stay clickable above it
//   and notification popups, created after, stay above everything.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: catcher
        required property var modelData
        screen: modelData
        readonly property bool active: app.cardShown || app.quickShown || app.sysShown || app.launcherShown
                                       || app.clipShown

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // everywhere, except the open drawer on the long bar: that's drawn
        // (and clicked) in BarStrip's window, which sits below this one
        property Region fullMask: Region {
            width: catcher.width
            height: catcher.height
            Region {
                intersection: Intersection.Subtract
                x: Math.round(app.drawerCurX)
                y: app.barBottom
                width: app.barAttached && app.drawerP > 0 ? Math.round(app.drawerCurW) : 0
                height: app.barAttached && app.drawerP > 0 ? Math.ceil(app.drawerCurH) : 0
            }
        }
        property Region noMask: Region { width: 0; height: 0 }
        mask: active ? fullMask : noMask

        MouseArea {
            anchors.fill: parent
            enabled: catcher.active
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: {
                app.cardShown = false
                app.quickShown = false
                app.sysShown = false
                app.launcherShown = false
                app.clipShown = false
            }
        }
    }
}
