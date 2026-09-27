import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// ============================================================
//   POWER MENU
//   A centred card: who and how long it's been up, then five
//   actions, each with its key (L, S, E, R, P).  Log out, restart
//   and power off count down five seconds first, with Cancel and
//   "Now", so a slipped click can't end the session.  Esc or a
//   click outside the card backs out.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // Built the first time it's opened, then kept for instant opening:
        // nothing sits in memory for a panel that's never used.
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.powerShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: winP
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Stays mapped and animates itself: mapping a new surface on each
        // open lagged, and Hyprland's own layer fade fought the shell's.
        // Closed, nothing shows and the mask lets every click through.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.powerShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        property Region shownMask: Region { width: winP.width; height: winP.height }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        readonly property var actions: [
            { key: "L", label: "Lock",      g: "lock", col: app.cBlue,   c: "loginctl lock-session", wait: false },
            { key: "S", label: "Suspend",   g: "bedtime", col: app.cTeal,   c: "systemctl suspend",     wait: false },
            { key: "E", label: "Log out",   g: "logout", col: app.cYellow, c: "hyprctl dispatch 'hl.dsp.exit()'", wait: true },
            { key: "R", label: "Restart",   g: "restart_alt", col: app.cPeach,  c: "systemctl reboot",      wait: true },
            { key: "P", label: "Power off", g: "power_settings_new", col: app.cRed,    c: "systemctl poweroff",    wait: true }
        ]

        // ---- the countdown for actions that end the session ----
        property int pending: -1          // index into actions, -1 = none
        property int secsLeft: 0

        onOpenChanged: {
            pending = -1
            countdown.stop()
            if (open) keys.forceActiveFocus()
        }

        function close() { app.powerShown = false }
        function run(i) {
            const a = actions[i]
            if (!a) return
            close()
            app.run("sleep 0.2; " + a.c)
        }
        function choose(i) {
            const a = actions[i]
            if (!a) return
            if (a.wait) { pending = i; secsLeft = 5; countdown.restart() }
            else run(i)
        }
        Timer {
            id: countdown
            interval: 1000
            repeat: true
            onTriggered: {
                winP.secsLeft -= 1
                if (winP.secsLeft <= 0) { stop(); winP.run(winP.pending) }
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) {
                    if (winP.pending >= 0) { countdown.stop(); winP.pending = -1 }
                    else winP.close()
                } else if (winP.pending >= 0) {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        countdown.stop(); winP.run(winP.pending)
                    } else return
                } else {
                    const i = winP.actions.findIndex(a => e.text.toUpperCase() === a.key)
                    if (i < 0) return
                    winP.choose(i)
                }
                e.accepted = true
            }
        }

        // the dimmed backdrop fades with the panel
        Rectangle {
            anchors.fill: parent
            color: app.scrim(0.6)
            opacity: winP.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
        }

        // click outside the card to back out
        MouseArea {
            anchors.fill: parent
            onClicked: winP.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: col.implicitWidth + 56
            height: col.implicitHeight + 52
            radius: 32
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)
            opacity: winP.open ? 1 : 0
            scale: winP.open ? 1 : 0.95
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

            // keep clicks on the card from closing it
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors.centerIn: parent
                spacing: 24

                // ---- who, and for how long ----
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    Rectangle {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: 24
                        color: app.cBlue
                        Text {
                            anchors.centerIn: parent
                            text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                            color: app.cOnAccent
                            font.family: "Inter"
                            font.pixelSize: app.fs(20)
                            font.bold: true
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: app.userHost
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(15)
                            font.bold: true
                        }
                        Text {
                            visible: text !== ""
                            text: app.uptimeText ? app.uptimeText.replace(/^up /, "Up ") : ""
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                        }
                    }
                }

                // ---- the five actions ----
                RowLayout {
                    visible: winP.pending < 0
                    spacing: 14

                    Repeater {
                        model: winP.actions

                        delegate: Rectangle {
                            id: act
                            required property var modelData
                            required property int index

                            implicitWidth: 128
                            implicitHeight: 136
                            radius: 26
                            color: aHov.hovered ? Qt.rgba(modelData.col.r, modelData.col.g, modelData.col.b, 0.18)
                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                            border.width: aHov.hovered ? 2 : 0
                            border.color: modelData.col
                            scale: aMa.pressed ? 0.96 : 1
                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                            Behavior on scale { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }

                            HoverHandler { id: aHov }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 54
                                    implicitHeight: 54
                                    radius: 27
                                    color: aHov.hovered ? act.modelData.col
                                         : Qt.rgba(act.modelData.col.r, act.modelData.col.g, act.modelData.col.b, 0.2)
                                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: act.modelData.g
                                        color: aHov.hovered ? app.cOnAccent : act.modelData.col
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(26)
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: act.modelData.label
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    font.bold: true
                                }
                                // its key
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 24
                                    implicitHeight: 20
                                    radius: 6
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.9)
                                    Text {
                                        anchors.centerIn: parent
                                        text: act.modelData.key
                                        color: app.cDim
                                        font.family: app.font
                                        font.pixelSize: app.fs(10)
                                    }
                                }
                            }

                            MouseArea {
                                id: aMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: winP.choose(act.index)
                            }
                        }
                    }
                }

                // ---- countdown ----
                ColumnLayout {
                    visible: winP.pending >= 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 5 * 128 + 4 * 14
                    spacing: 18
                    readonly property var a: winP.actions[winP.pending] ?? null

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: parent.a ? parent.a.label + " in " + winP.secsLeft : ""
                        color: app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(26)
                        font.bold: true
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                        Rectangle {
                            width: parent.width * winP.secsLeft / 5
                            height: parent.height
                            radius: 4
                            color: parent.parent.a ? parent.parent.a.col : app.cBlue
                            Behavior on width { NumberAnimation { duration: 950 } }
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            radius: 20
                            color: cHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                            HoverHandler { id: cHov }
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(13)
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { countdown.stop(); winP.pending = -1 }
                            }
                        }
                        Rectangle {
                            implicitWidth: 120
                            implicitHeight: 40
                            radius: 20
                            readonly property color c: parent.parent.a ? parent.parent.a.col : app.cBlue
                            color: nHov.hovered ? Qt.lighter(c, 1.1) : c
                            HoverHandler { id: nHov }
                            Text {
                                anchors.centerIn: parent
                                text: "Now"
                                color: app.cOnAccent
                                font.family: "Inter"
                                font.pixelSize: app.fs(13)
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { countdown.stop(); winP.run(winP.pending) }
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: winP.pending >= 0 ? "Esc to cancel, Enter to do it now"
                                            : "Press a key or click.  Esc closes."
                    color: app.cFaint
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                }
            }
        }
    }
    }
}
