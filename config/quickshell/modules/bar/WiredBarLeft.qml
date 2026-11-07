import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.plugins
import qs.services

// The left pill's contents in the Wired look (Settings > Theme > Look):
// an ETHER block like a window's title bar (the assistant, as the sparkle
// is), the workspaces as square cells (the one showing a solid block, ones
// with windows outlined and underlined), the other monitor's as M2, the
// stats as a number and a small segmented bar each (click for the system
// drawer), plugins' items, and what has the keyboard.  Mono type, the
// wallpaper's colours.  Same data and actions as the standard pill.
Row {
    id: wb
    property var app
    property real scrX: 0                // this window's left edge on screen (for workspace previews)
    spacing: 8
    height: 24
    // the title: up to titleMax wide (the room before the centre pill), and
    // the pill as wide as it gets with the longest one (for its window)
    property real titleMax: 300
    readonly property real titleW: awText.width
    readonly property real widest: implicitWidth - awText.width + titleMax

    readonly property color accent: app.cBlue
    readonly property color second: app.cPeach
    readonly property color paper: "#eceef2"
    readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
    readonly property color faint: Qt.rgba(0.38, 0.4, 0.44, 1)
    readonly property color ink: "#0a0c0e"
    readonly property color off: Qt.rgba(0.15, 0.165, 0.18, 1)
    readonly property var families: Qt.fontFamilies()
    readonly property string jpFont: ["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "IPAGothic"]
                                     .find(f => families.indexOf(f) >= 0) || ""

    component Sep: Rectangle { width: 1; height: 16; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.2) }

    // a workspace cell
    component Cell: Rectangle {
        id: c
        property var ws
        property bool active: false
        property bool here: true
        property string screenName: ""
        property string label: ""
        width: 22; height: 22
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: active ? (here ? wb.accent : Qt.rgba(wb.accent.r, wb.accent.g, wb.accent.b, 0.4))
             : cHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        border.width: !active && ws && ws.occupied ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.3)
        Rectangle {
            visible: !c.active && c.ws && c.ws.occupied
            x: 4; width: parent.width - 8; height: 1
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            color: wb.accent
        }
        Text {
            anchors.centerIn: parent
            text: c.label
            color: c.active ? wb.ink : c.ws && c.ws.occupied ? wb.paper : wb.faint
            font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
        }
        HoverHandler {
            id: cHov
            onHoveredChanged: {
                if (!c.ws) return
                if (hovered) wb.app.wsHoverStart(c.ws.id, c.mapToItem(null, c.width / 2, 0).x + wb.scrX, c.screenName)
                else wb.app.wsHoverEnd(c.ws.id)
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                wb.app.wsHoverEnd(c.ws.id)
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + c.ws.id + " })")
            }
        }
    }

    // ---- ETHER, the assistant ----
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: etherRow.implicitWidth + 18; height: 22
        color: wb.app.aiShown ? wb.accent : aiHov.hovered ? "#ffffff" : Qt.rgba(0.93, 0.94, 0.95, 0.92)
        HoverHandler { id: aiHov }
        Row {
            id: etherRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: "ETHER"; color: wb.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12 }
            Text { visible: wb.jpFont !== ""; text: "エーテル"; color: wb.ink; font.family: wb.jpFont; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wb.app.aiShown = !wb.app.aiShown }
    }

    // ---- this monitor's workspaces ----
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Repeater {
            model: wb.app.workspacesFor(wb.app.mainScreen)
            delegate: Cell {
                required property var modelData
                required property int index
                ws: modelData
                label: String(index + 1)
                active: modelData.id === wb.app.mainActive
                here: !wb.app.secondFocused
                screenName: wb.app.mainScreen
            }
        }
    }

    // ---- the other monitor's ----
    Sep { visible: m2.visible }
    Row {
        id: m2
        visible: wb.app.secondScreen !== "" && wb.app.secondWorkspaces.length > 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text { text: "M2"; color: wb.dim; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter; rightPadding: 4 }
        Repeater {
            model: wb.app.workspacesFor(wb.app.secondScreen)
            delegate: Cell {
                required property var modelData
                required property int index
                ws: modelData
                label: String(index + 1)
                active: modelData.id === wb.app.secondActive
                here: wb.app.secondFocused
                screenName: wb.app.secondScreen
            }
        }
    }

    // ---- the stats: click for the system drawer ----
    Sep { visible: stats.visible }
    Item {
        id: stats
        visible: wb.app.statsAny
        anchors.verticalCenter: parent.verticalCenter
        width: statRow.implicitWidth + 8; height: 22
        Rectangle { anchors.fill: parent; color: stHov.hovered || wb.app.sysShown ? Qt.rgba(1, 1, 1, 0.07) : "transparent" }
        HoverHandler { id: stHov }
        Row {
            id: statRow
            anchors.centerIn: parent
            spacing: 14
            Repeater {
                model: [
                    { n: "CPU", v: wb.app.cpuPct, u: "%", on: wb.app.statCpu !== "off", c: wb.accent },
                    { n: "MEM", v: wb.app.memPct, u: "%", on: wb.app.statMem !== "off", c: wb.second },
                    { n: "GPU", v: wb.app.gpuPct, u: "%", on: wb.app.gpuOk && wb.app.statGpu !== "off", c: wb.accent },
                    { n: "TMP", v: wb.app.gpuTemp, u: "°", on: wb.app.gpuOk && wb.app.statTemp !== "off", c: wb.second }
                ]
                delegate: Row {
                    id: st
                    required property var modelData
                    visible: modelData.on
                    spacing: 6
                    Text { text: st.modelData.n; color: st.modelData.c; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: numM.advanceWidth
                        text: ("00" + Math.round(st.modelData.v)).slice(-3) + st.modelData.u
                        color: wb.paper; font.family: Theme.font; font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                        TextMetrics { id: numM; font.family: Theme.font; font.pixelSize: 11; text: "000%" }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: 9
                            delegate: Rectangle {
                                required property int index
                                width: 4; height: 7
                                color: index < Math.round(Math.max(0, Math.min(1, st.modelData.v / 100)) * 9) ? st.modelData.c : wb.off
                            }
                        }
                    }
                }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wb.app.sysShown = !wb.app.sysShown }
    }

    // ---- plugins' items for this side ----
    PluginBarItems { app: wb.app; side: "left"; anchors.verticalCenter: parent.verticalCenter }

    // ---- what has the keyboard ----
    Sep {}
    Row {
        id: aw
        readonly property var tl: ToplevelManager.activeToplevel
        readonly property string title: tl ? (tl.title || "") : ""
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text { text: ">"; color: wb.accent; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11 }
        Text {
            id: awText
            width: Math.min(implicitWidth, wb.titleMax)
            elide: Text.ElideRight
            text: aw.title || "desktop"
            color: aw.title ? wb.paper : wb.dim
            font.family: Theme.font; font.pixelSize: 11
        }
    }
}
