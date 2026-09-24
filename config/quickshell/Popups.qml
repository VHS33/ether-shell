import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

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

    PanelWindow {
        id: winN
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen && app.popups.length > 0

        // bottom right, clearing the dock
        anchors { bottom: true; right: true }
        margins { bottom: app.gap + app.dockSpace; right: app.gap }
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
                model: app.popups

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
                    implicitHeight: card.implicitHeight

                    // slides in from the right
                    opacity: 0
                    transform: Translate { id: slide; x: 40 }
                    Component.onCompleted: enter.start()
                    Component.onDestruction: if (winN.replyHost === pop) winN.replyHost = null
                    ParallelAnimation {
                        id: enter
                        NumberAnimation { target: pop; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: slide; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                    }

                    // the countdown holds while hovered or while typing a reply
                    readonly property bool held: popHov.hovered || replyIn.activeFocus

                    Timer {
                        interval: pop.lifeMs
                        running: !pop.held
                        onTriggered: app.dismissPopup(pop.modelData.id)
                    }

                    Rectangle {
                        id: card
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: body.implicitHeight + 28
                        radius: 20
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
                                radius: 12
                                color: app.cSurf
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
                                        font.family: "Noto Sans"
                                        font.pixelSize: app.fs(11)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: !popHov.hovered
                                        text: pop.modelData.when
                                        color: app.cFaint
                                        font.family: "Noto Sans"
                                        font.pixelSize: app.fs(11)
                                    }
                                    // close, in place of the time while hovered
                                    Text {
                                        visible: popHov.hovered
                                        text: "\u{f0156}"
                                        color: xHov.hovered ? app.cFg : app.cDim
                                        font.family: app.font
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
                                    font.family: "Noto Sans"
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
                                    font.family: "Noto Sans"
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
                                    radius: 18
                                    color: app.cSurf
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
                                            font.family: "Noto Sans"
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
                                            radius: 13
                                            color: replyIn.text ? app.cBlue : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "\u{f048a}"
                                                color: replyIn.text ? app.cOnAccent : app.cFaint
                                                font.family: app.font
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
                                            radius: 15
                                            color: actHov.hovered ? app.cSurf
                                                 : Qt.rgba(app.cSurf.r, app.cSurf.g, app.cSurf.b, 0.6)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            HoverHandler { id: actHov }
                                            Text {
                                                id: actT
                                                anchors.centerIn: parent
                                                text: modelData.text
                                                color: app.cFg
                                                font.family: "Noto Sans"
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
                                radius: 12
                                color: app.cSurf
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: pop.modelData.image ?? ""
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
                            radius: 1
                            color: pop.crit ? app.cRed : app.cBlue
                            opacity: 0.6
                            NumberAnimation on width {
                                running: !pop.held
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
