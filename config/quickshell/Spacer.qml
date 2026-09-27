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
//   SPACER — only window that reserves space
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    PanelWindow {
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen

        anchors { top: true; left: true; right: true }
        implicitHeight: 1
        exclusiveZone: app.zoneH
        color: "transparent"

        mask: Region { width: 0; height: 0 }
    }
}
