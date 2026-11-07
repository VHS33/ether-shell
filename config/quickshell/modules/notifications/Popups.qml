import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../lib/models.mjs" as Models
import qs.services

// ============================================================
//   NOTIFICATION POPUPS
//   Cards in the same language as Settings: the app's icon, a
//   name and time line, title and body in the UI font, the app's
//   own buttons, and a thin countdown along the bottom edge.
//
//   Entries in app.popups are plain values (id, app, icon,
//   summary, body, image, actions as {key, text}).  The live
//   Notification objects stay in app.notifRefs; buttons reach
//   them by id through app.invokeNotifAction.
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
        active: modelData.name === app.mainScreen

    PanelWindow {
        id: winN
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.popups.length > 0

        // bottom right, clearing the dock if it reaches this far
        anchors { bottom: true; right: true }
        margins { bottom: app.gap + app.dockSpaceRight(winN.modelData.width, winN.implicitWidth); right: app.gap }
        implicitWidth: 420
        implicitHeight: popCol.implicitHeight + 16
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Popups never take the keyboard on their own: Hyprland gives an
        // on-demand layer focus the moment it appears, which stole typing
        // from whatever window you were in.  The window only becomes
        // focusable while the pointer is over a popup with a reply box
        // (or that box is being typed in).
        property var replyHost: null
        WlrLayershell.keyboardFocus: replyHost !== null
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        mask: Region { x: 8; y: 8; width: winN.width - 16; height: winN.height - 16 }

        ColumnLayout {
            id: popCol
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.margins: 8
            spacing: 8

            Repeater {
                model: ScriptModel { values: Models.keyed(app.popups, n => n.id); objectProp: "_key" }

                delegate: Item {
                    id: pop
                    required property var modelData
                    readonly property bool crit: modelData.urgency >= 2
                    // every action with a label, the click action included
                    // (Discord's "View", which opens the DM)
                    readonly property var buttons:
                        (modelData.actions || []).filter(a => a.text !== "")
                    readonly property bool canReply: modelData.replyable === true
                    readonly property bool hasDefault:
                        (modelData.actions || []).some(a => a.key === "default")
                    readonly property int lifeMs: crit ? app.notifMs * 2 : app.notifMs

                    Layout.fillWidth: true
                    implicitHeight: app.wiredLook ? wcard.implicitHeight : card.implicitHeight

                    // slides in from the right
                    opacity: 0
                    transform: Translate { id: slide; x: 40 }
                    Component.onCompleted: enter.start()
                    Component.onDestruction: if (winN.replyHost === pop) winN.replyHost = null
                    ParallelAnimation {
                        id: enter
                        NumberAnimation { target: pop; property: "opacity"; to: 1; duration: app.animNormal; easing.type: Easing.OutCubic }
                        NumberAnimation { target: slide; property: "x"; to: 0; duration: app.animNormal; easing.type: Easing.OutCubic }
                    }

                    // the countdown holds while hovered or while typing a reply
                    readonly property bool held: app.wiredLook ? (wHov.hovered || wReply.activeFocus)
                                                               : (popHov.hovered || replyIn.activeFocus)

                    Timer {
                        interval: pop.lifeMs
                        running: !pop.held
                        onTriggered: app.dismissPopup(pop.modelData.id)
                    }

                    // ---- the Wired look (Settings > Theme > Look): a square
                    // window, the app in its title bar (red when urgent), mono
                    // type, square buttons, the countdown in segments ----
                    Rectangle {
                        id: wcard
                        visible: app.wiredLook
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: wBody.y + wBody.implicitHeight + 22
                        color: Qt.rgba(0.035, 0.043, 0.051, 0.92)
                        border.width: 1
                        border.color: pop.crit ? app.cRed : Qt.rgba(1, 1, 1, 0.36)
                        clip: true
                        readonly property color paper: "#eceef2"
                        readonly property color dim: Qt.rgba(0.6, 0.62, 0.65, 1)
                        readonly property color faint: Qt.rgba(0.38, 0.4, 0.44, 1)
                        readonly property color ink: "#0a0c0e"

                        HoverHandler {
                            id: wHov
                            onHoveredChanged: {
                                if (hovered && pop.canReply) winN.replyHost = pop
                                else if (!hovered && winN.replyHost === pop && !wReply.activeFocus)
                                    winN.replyHost = null
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pop.hasDefault) {
                                    app.invokeNotifAction(pop.modelData.id, "default")
                                } else {
                                    app.dismissPopup(pop.modelData.id)
                                    app.sidebarShown = true
                                }
                            }
                        }

                        // the title bar: the app, when, the boxes close it
                        Rectangle {
                            id: wTitle
                            width: parent.width; height: 22
                            color: pop.crit ? app.cRed : Qt.rgba(0.93, 0.94, 0.95, 0.9)
                            Text {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - wRight.width - 24
                                elide: Text.ElideRight
                                text: String(pop.modelData.app || "Notification").toUpperCase()
                                color: wcard.ink; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 12
                            }
                            Row {
                                id: wRight
                                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pop.modelData.when || ""
                                    color: Qt.rgba(0.24, 0.25, 0.27, 1); font.family: Theme.font; font.pixelSize: 11
                                }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Repeater { model: 3; delegate: Rectangle { width: 7; height: 7; color: "transparent"; border.width: 1; border.color: wcard.ink } }
                                }
                            }
                            MouseArea { anchors.right: parent.right; width: 40; height: parent.height; cursorShape: Qt.PointingHandCursor; onClicked: app.dismissPopup(pop.modelData.id) }
                        }
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 3; anchors.topMargin: 25
                            color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
                        }

                        RowLayout {
                            id: wBody
                            x: 14; y: 22 + 12
                            width: parent.width - 28
                            spacing: 12

                            // the app's icon, in a square
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 40
                                implicitHeight: 40
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 26
                                    source: app.notifIcon(pop.modelData)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: pop.modelData.summary
                                    color: wcard.paper
                                    font.family: Theme.font
                                    font.weight: Font.Bold
                                    font.pixelSize: app.fs(13)
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: pop.modelData.body
                                    color: wcard.dim
                                    font.family: Theme.font
                                    font.pixelSize: app.fs(12)
                                    lineHeight: 1.15
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }

                                // a reply, for apps that take one
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: pop.canReply
                                    implicitHeight: 30
                                    color: "transparent"
                                    border.width: 1
                                    border.color: wReply.activeFocus ? app.cBlue : Qt.rgba(1, 1, 1, 0.3)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 4
                                        spacing: 8
                                        Text { text: ">"; color: app.cBlue; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: app.fs(12) }
                                        TextInput {
                                            id: wReply
                                            Layout.fillWidth: true
                                            color: wcard.paper
                                            selectionColor: app.cBlue
                                            selectedTextColor: wcard.ink
                                            font.family: Theme.font
                                            font.pixelSize: app.fs(12)
                                            clip: true
                                            onAccepted: app.sendNotifReply(pop.modelData.id, text)
                                            onActiveFocusChanged: if (!activeFocus && !wHov.hovered && winN.replyHost === pop)
                                                winN.replyHost = null
                                            Keys.onEscapePressed: { text = ""; focus = false }
                                            Text {
                                                visible: !wReply.text
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: String(pop.modelData.replyHint || "reply").toLowerCase()
                                                color: wcard.faint
                                                font: wReply.font
                                            }
                                        }
                                        Rectangle {
                                            implicitWidth: sendT.implicitWidth + 16
                                            implicitHeight: 22
                                            color: wReply.text ? app.cBlue : "transparent"
                                            border.width: wReply.text ? 0 : 1
                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                            Text {
                                                id: sendT
                                                anchors.centerIn: parent
                                                text: "SEND"
                                                color: wReply.text ? wcard.ink : wcard.faint
                                                font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.sendNotifReply(pop.modelData.id, wReply.text)
                                            }
                                        }
                                    }
                                }

                                // the app's own buttons, as boxes
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: pop.buttons.length > 0
                                    spacing: 6
                                    Repeater {
                                        model: pop.buttons
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitWidth: wActT.implicitWidth + 22
                                            implicitHeight: 24
                                            color: wActHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.3)
                                            HoverHandler { id: wActHov }
                                            Text {
                                                id: wActT
                                                anchors.centerIn: parent
                                                text: String(modelData.text).toUpperCase()
                                                color: wcard.paper
                                                font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 11
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.invokeNotifAction(pop.modelData.id, modelData.key)
                                            }
                                        }
                                    }
                                }
                            }

                            // a picture it carries, in a square
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                visible: (pop.modelData.image ?? "") !== ""
                                implicitWidth: 64
                                implicitHeight: 64
                                color: Qt.rgba(1, 1, 1, 0.04)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    sourceSize.width: 480
                                    sourceSize.height: 480
                                    source: app.wiredLook ? (pop.modelData.image ?? "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }
                                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
                            }
                        }

                        // the countdown, in segments, paused while hovered
                        property real life: 1
                        NumberAnimation on life {
                            running: app.wiredLook && !pop.held
                            from: 1
                            to: 0
                            duration: pop.lifeMs
                        }
                        Row {
                            x: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                            spacing: 2
                            Repeater {
                                model: 30
                                delegate: Rectangle {
                                    required property int index
                                    width: (wcard.width - 28 - 29 * 2) / 30; height: 3
                                    color: index < Math.ceil(wcard.life * 30) ? (pop.crit ? app.cRed : app.cBlue)
                                                                               : Qt.rgba(0.15, 0.165, 0.18, 1)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: card
                        visible: !app.wiredLook
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: body.implicitHeight + 28
                        radius: app.rr(20)
                        color: app.cCard
                        border.width: 1
                        border.color: pop.crit ? app.cRed
                                    : Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)
                        clip: true

                        HoverHandler {
                            id: popHov
                            onHoveredChanged: {
                                if (hovered && pop.canReply) winN.replyHost = pop
                                else if (!hovered && winN.replyHost === pop && !replyIn.activeFocus)
                                    winN.replyHost = null
                            }
                        }

                        // clicking the card does what the app asked for on
                        // click; without one it opens the sidebar
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pop.hasDefault) {
                                    app.invokeNotifAction(pop.modelData.id, "default")
                                } else {
                                    app.dismissPopup(pop.modelData.id)
                                    app.sidebarShown = true
                                }
                            }
                        }

                        RowLayout {
                            id: body
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 12

                            // app icon
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: app.rr(12)
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 26
                                    source: app.notifIcon(pop.modelData)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: pop.modelData.app
                                        color: pop.crit ? app.cRed : app.cDim
                                        font.family: Theme.uiFont
                                        font.pixelSize: app.fs(11)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: !popHov.hovered
                                        text: pop.modelData.when
                                        color: app.cFaint
                                        font.family: Theme.uiFont
                                        font.pixelSize: app.fs(11)
                                    }
                                    // close, in place of the time while hovered
                                    Text {
                                        visible: popHov.hovered
                                        text: "close"
                                        color: xHov.hovered ? app.cFg : app.cDim
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(14)
                                        HoverHandler { id: xHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: app.dismissPopup(pop.modelData.id)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: pop.modelData.summary
                                    color: app.cFg
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(14)
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: pop.modelData.body
                                    color: app.cDim
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(12)
                                    lineHeight: 1.2
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }

                                // reply box, for apps that accept one
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: pop.canReply
                                    implicitHeight: 36
                                    radius: app.rr(18)
                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                    border.width: replyIn.activeFocus ? 1 : 0
                                    border.color: app.cBlue

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        TextInput {
                                            id: replyIn
                                            Layout.fillWidth: true
                                            color: app.cFg
                                            selectionColor: app.cBlue
                                            font.family: Theme.uiFont
                                            font.pixelSize: app.fs(12)
                                            clip: true
                                            onAccepted: app.sendNotifReply(pop.modelData.id, text)
                                            // done typing and the pointer has left: give focus back
                                            onActiveFocusChanged: if (!activeFocus && !popHov.hovered
                                                                      && winN.replyHost === pop)
                                                winN.replyHost = null
                                            Keys.onEscapePressed: { text = ""; focus = false }

                                            Text {
                                                visible: !replyIn.text
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: pop.modelData.replyHint || "Reply"
                                                color: app.cFaint
                                                font: replyIn.font
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: 26
                                            implicitHeight: 26
                                            radius: app.rr(13)
                                            color: replyIn.text ? app.cBlue : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "send"
                                                color: replyIn.text ? app.cOnAccent : app.cFaint
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(13)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.sendNotifReply(pop.modelData.id, replyIn.text)
                                            }
                                        }
                                    }
                                }

                                // the app's own buttons
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 6
                                    visible: pop.buttons.length > 0
                                    spacing: 6
                                    Repeater {
                                        model: pop.buttons
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitWidth: actT.implicitWidth + 28
                                            implicitHeight: 30
                                            radius: app.rr(15)
                                            color: actHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                                            Behavior on color { ColorAnimation { duration: app.animQuick } }
                                            HoverHandler { id: actHov }
                                            Text {
                                                id: actT
                                                anchors.centerIn: parent
                                                text: modelData.text
                                                color: app.cFg
                                                font.family: Theme.uiFont
                                                font.pixelSize: app.fs(12)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.invokeNotifAction(pop.modelData.id, modelData.key)
                                            }
                                        }
                                    }
                                }
                            }

                            // image the notification carries (screenshots,
                            // album art, avatars)
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                visible: (pop.modelData.image ?? "") !== ""
                                implicitWidth: 64
                                implicitHeight: 64
                                radius: app.rr(12)
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    // a screenshot here would otherwise be held at full size
                                    sourceSize.width: 480
                                    sourceSize.height: 480
                                    source: !app.wiredLook ? (pop.modelData.image ?? "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }
                            }
                        }

                        // countdown: a thin line along the bottom edge,
                        // paused while hovered
                        Rectangle {
                            id: lifeBar
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 20
                            anchors.bottomMargin: 6
                            height: 2
                            radius: app.rr(1)
                            color: pop.crit ? app.cRed : app.cBlue
                            opacity: 0.6
                            NumberAnimation on width {
                                running: !pop.held && !app.wiredLook
                                from: card.width - 40
                                to: 0
                                duration: pop.lifeMs
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
