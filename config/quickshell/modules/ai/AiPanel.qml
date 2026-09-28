import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../lib/models.mjs" as Models

// ============================================================
//   AI ASSISTANT  (SUPER + A, or the sparkle at the bar's left)
//   A chat panel that slides in from the left edge and fills that
//   side of the screen, under the bar.  It talks to whichever
//   provider is chosen in Settings > AI assistant (Anthropic, Google
//   or OpenAI) with the user's own key; the requests themselves live
//   in shell.qml.  Replies stream in and are shown as Markdown.
//
//   Messages are plain values; the reply being written is shown
//   separately (app.aiStreaming) so the list doesn't rebuild on every
//   word.  Enter sends, Shift+Enter makes a new line, Esc closes.
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
        // Built the first time it's opened, kept while it's in use, and
        // released a while after it closes (the Timer in its window).
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.aiShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: aw

        // Released 10 minutes after it closes (it's rarely open): its memory
        // back.  Opening it again builds it afresh, a moment's work.
        Timer {
            interval: 600000
            running: !app.aiShown
            onTriggered: Qt.callLater(() => { perScreen.used = false })
        }
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.aiShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)
        readonly property var prov: app.aiProviders[app.aiProvider]
        // the setup screen: shown when there's no key for the chosen
        // provider, or when opened with the gear
        property bool setup: false
        readonly property bool hasKey: app.aiKeys[app.aiProvider] === true
        readonly property bool showSetup: setup || !hasKey
        // after Save, go straight to the chat once the key is on disk
        property bool justSaved: false
        Connections {
            target: app
            function onAiKeysChanged() {
                if (aw.justSaved && aw.hasKey) { aw.justSaved = false; aw.setup = false; input.forceActiveFocus() }
            }
        }
        readonly property var keyPages: ({
            anthropic: "https://console.anthropic.com/settings/keys",
            gemini: "https://aistudio.google.com/app/apikey",
            openai: "https://platform.openai.com/api-keys"
        })

        anchors { top: true; bottom: true; left: true }
        margins { top: app.barBottom + app.gap; bottom: app.gap; left: app.gap }
        implicitWidth: 500
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        property Region shownMask: Region { item: panel }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        onOpenChanged: {
            if (open) { if (showSetup) keyIn.forceActiveFocus(); else input.forceActiveFocus() }
            else setup = false
        }

        // it scrolls to the newest message as the reply grows
        function toBottom() { Qt.callLater(() => chat.positionViewAtEnd()) }
        Connections {
            target: app
            function onAiMessagesChanged() { aw.toBottom() }
            function onAiStreamingChanged() { aw.toBottom() }
        }

        Rectangle {
            id: panel
            width: parent.width
            height: parent.height
            x: aw.open ? 0 : -width - 24
            opacity: aw.open ? 1 : 0
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal } }
            radius: 26
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.45)

            Keys.onEscapePressed: app.aiShown = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---- header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 14
                        color: app.cPrimC
                        Text {
                            anchors.centerIn: parent
                            text: "auto_awesome"
                            color: app.cOnPrimC
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Assistant"
                            color: app.cFg
                            font.family: "Inter"
                            font.weight: Font.DemiBold
                            font.pixelSize: app.fs(15)
                        }
                        // the provider and model; click to change them
                        Text {
                            text: aw.prov.product + "  \u2022  " + app.aiModel
                            color: modelHov.hovered ? app.cBlue : app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                            HoverHandler { id: modelHov }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: aw.setup = true
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { g: "settings", tip: "setup" },
                            { g: "edit_square", tip: "new" },
                            { g: "close", tip: "close" }
                        ]
                        delegate: Rectangle {
                            id: hb
                            required property var modelData
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 12
                            color: hb.modelData.tip === "setup" && aw.setup ? app.cPrimC
                                 : hbHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                            HoverHandler { id: hbHov }
                            Text {
                                anchors.centerIn: parent
                                text: hb.modelData.g
                                color: app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(19)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (hb.modelData.tip === "setup") aw.setup = !aw.setup
                                    else if (hb.modelData.tip === "new") { app.aiNew(); aw.setup = false; input.forceActiveFocus() }
                                    else app.aiShown = false
                                }
                            }
                        }
                    }
                }

                // ---- the conversation ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // nothing yet: a greeting, and a few things to try
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        visible: app.aiMessages.length === 0 && !app.aiBusy && !aw.showSetup
                        spacing: 14
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "auto_awesome"
                            color: app.cBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(40)
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "What can I help with?"
                            color: app.cFg
                            font.family: "Inter"
                            font.weight: Font.Medium
                            font.pixelSize: app.fs(16)
                            wrapMode: Text.WordWrap
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [
                                    "Explain a Linux command",
                                    "Write a fish function",
                                    "Help me fix an error",
                                    "Summarise something for me"
                                ]
                                delegate: Rectangle {
                                    id: sug
                                    required property var modelData
                                    implicitWidth: sugT.implicitWidth + 24
                                    implicitHeight: 32
                                    radius: 16
                                    color: sugHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                                          : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                                    HoverHandler { id: sugHov }
                                    Text {
                                        id: sugT
                                        anchors.centerIn: parent
                                        text: sug.modelData
                                        color: app.cDim
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { input.text = sug.modelData + ": "; input.cursorPosition = input.length; input.forceActiveFocus() }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: chat
                        anchors.fill: parent
                        visible: !aw.showSetup
                        clip: true
                        spacing: 12
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel { values: Models.keyed(app.aiMessages, m => m.role); objectProp: "_key" }
                        delegate: Item {
                            id: msg
                            required property var modelData
                            readonly property bool mine: modelData.role === "user"
                            width: chat.width
                            implicitHeight: mine ? bubble.height : answer.implicitHeight

                            // yours: a bubble on the right
                            Rectangle {
                                id: bubble
                                visible: msg.mine
                                anchors.right: parent.right
                                width: Math.min(msg.width * 0.85, userT.implicitWidth + 28)
                                height: userT.implicitHeight + 20
                                radius: 18
                                color: app.cPrimC
                                Text {
                                    id: userT
                                    x: 14
                                    y: 10
                                    width: Math.min(implicitWidth, msg.width * 0.85 - 28)
                                    text: msg.modelData.text
                                    color: app.cOnPrimC
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                }
                            }
                            // theirs: plain on the panel, as Markdown, with a copy button
                            ColumnLayout {
                                id: answer
                                visible: !msg.mine
                                width: parent.width
                                spacing: 4
                                TextEdit {
                                    Layout.fillWidth: true
                                    readOnly: true
                                    selectByMouse: true
                                    text: msg.modelData.text
                                    textFormat: msg.modelData.error ? TextEdit.PlainText : TextEdit.MarkdownText
                                    color: msg.modelData.error ? app.cRed : app.cFg
                                    selectionColor: app.cBlue
                                    selectedTextColor: app.cOnAccent
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    wrapMode: TextEdit.Wrap
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                                Rectangle {
                                    visible: !msg.modelData.error
                                    implicitWidth: cpRow.implicitWidth + 16
                                    implicitHeight: 24
                                    radius: 12
                                    color: cpHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                                    HoverHandler { id: cpHov }
                                    property bool copied: false
                                    Row {
                                        id: cpRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: parent.parent.copied ? "check" : "content_copy"
                                            color: app.cDim
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(13)
                                        }
                                        Text {
                                            text: parent.parent.copied ? "Copied" : "Copy"
                                            color: app.cDim
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(11)
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            copier.command = ["wl-copy", "--", msg.modelData.text]
                                            copier.running = true
                                            parent.copied = true
                                            copiedReset.restart()
                                        }
                                    }
                                    Timer {
                                        id: copiedReset
                                        interval: 1500
                                        onTriggered: parent.copied = false
                                    }
                                }
                            }
                        }

                        // the reply being written
                        footer: Item {
                            width: chat.width
                            implicitHeight: app.aiBusy ? liveCol.implicitHeight + 12 : 0
                            visible: app.aiBusy
                            ColumnLayout {
                                id: liveCol
                                y: 12
                                width: parent.width
                                spacing: 4
                                TextEdit {
                                    Layout.fillWidth: true
                                    visible: app.aiStreaming !== ""
                                    readOnly: true
                                    text: app.aiStreaming
                                    textFormat: TextEdit.MarkdownText
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    wrapMode: TextEdit.Wrap
                                }
                                // thinking: three dots that pulse
                                Row {
                                    visible: app.aiStreaming === ""
                                    spacing: 5
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle {
                                            required property int index
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: app.cBlue
                                            SequentialAnimation on opacity {
                                                running: app.aiBusy && app.aiStreaming === ""
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: index * 150 }
                                                NumberAnimation { from: 0.25; to: 1; duration: 350 }
                                                NumberAnimation { from: 1; to: 0.25; duration: 350 }
                                                PauseAnimation { duration: (2 - index) * 150 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ================= setup =================
                    Flickable {
                        anchors.fill: parent
                        visible: aw.showSetup
                        contentHeight: setupCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: setupCol
                            width: parent.width
                            spacing: 12

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                text: aw.hasKey ? "Assistant settings" : "Set up your assistant"
                                color: app.cFg
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(18)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Choose who answers, then add your API key for them. Keys stay on this computer, in a file only you can read."
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                wrapMode: Text.WordWrap
                            }

                            // 1. who answers
                            Text {
                                Layout.topMargin: 4
                                text: "1  Choose a provider"
                                color: app.cDim
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(11)
                            }
                            Repeater {
                                model: ["anthropic", "gemini", "openai"]
                                delegate: Rectangle {
                                    id: pc
                                    required property var modelData
                                    readonly property var info: app.aiProviders[modelData]
                                    readonly property bool chosen: app.aiProvider === modelData
                                    readonly property bool saved: app.aiKeys[modelData] === true
                                    Layout.fillWidth: true
                                    implicitHeight: 60
                                    radius: 18
                                    color: chosen ? app.cPrimC
                                         : pcHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                         : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    HoverHandler { id: pcHov }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 14
                                        spacing: 12
                                        // a lettered badge for each company
                                        Rectangle {
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            radius: 12
                                            color: pc.chosen ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                            Text {
                                                anchors.centerIn: parent
                                                text: pc.info.product.charAt(0)
                                                color: pc.chosen ? app.cOnAccent : app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.Bold
                                                font.pixelSize: app.fs(15)
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: pc.info.product
                                                color: pc.chosen ? app.cOnPrimC : app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.DemiBold
                                                font.pixelSize: app.fs(13)
                                            }
                                            Text {
                                                text: "by " + pc.info.name
                                                color: pc.chosen ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.7) : app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                        }
                                        Rectangle {
                                            visible: pc.saved
                                            implicitWidth: kT.implicitWidth + 16
                                            implicitHeight: 22
                                            radius: 11
                                            color: Qt.rgba(app.cGreen.r, app.cGreen.g, app.cGreen.b, 0.2)
                                            Text {
                                                id: kT
                                                anchors.centerIn: parent
                                                text: "Key saved"
                                                color: pc.chosen ? app.cOnPrimC : app.cGreen
                                                font.family: "Inter"
                                                font.weight: Font.Medium
                                                font.pixelSize: app.fs(10)
                                            }
                                        }
                                        Text {
                                            text: pc.chosen ? "radio_button_checked" : "radio_button_unchecked"
                                            color: pc.chosen ? app.cOnPrimC : app.cDim
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(20)
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.setting("aiProvider", pc.modelData)
                                    }
                                }
                            }

                            // 2. a key for them
                            Text {
                                Layout.topMargin: 8
                                text: "2  " + (aw.hasKey ? "Your " + aw.prov.name + " key" : "Add your " + aw.prov.name + " API key")
                                color: app.cDim
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(11)
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: getRow.implicitHeight + 20
                                radius: 16
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                                visible: !aw.hasKey
                                RowLayout {
                                    id: getRow
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    anchors.leftMargin: 14
                                    spacing: 10
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Don't have one? Create a key on " + aw.prov.name + "'s site, then copy it."
                                        color: app.cDim
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        wrapMode: Text.WordWrap
                                    }
                                    Rectangle {
                                        implicitWidth: gkRow.implicitWidth + 22
                                        implicitHeight: 34
                                        radius: 17
                                        color: gkHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.16)
                                                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                        HoverHandler { id: gkHov }
                                        Row {
                                            id: gkRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Get a key"
                                                color: app.cFg
                                                font.family: "Inter"
                                                font.weight: Font.Medium
                                                font.pixelSize: app.fs(12)
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "open_in_new"
                                                color: app.cFg
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(14)
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally(aw.keyPages[app.aiProvider])
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: 16
                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                    border.width: keyIn.activeFocus ? 1 : 0
                                    border.color: app.cBlue
                                    Text {
                                        id: keyIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "key"
                                        color: app.cDim
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(18)
                                    }
                                    TextInput {
                                        id: keyIn
                                        anchors.left: keyIcon.right
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        echoMode: TextInput.Password
                                        color: app.cFg
                                        selectionColor: app.cBlue
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(13)
                                        clip: true
                                        function save() {
                                            if (!text.trim()) return
                                            aw.justSaved = true
                                            app.saveAiKey(app.aiProvider, text)
                                            text = ""
                                        }
                                        Keys.onReturnPressed: save()
                                        Keys.onEnterPressed: save()
                                        Text {
                                            visible: !keyIn.text
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: aw.hasKey ? "Paste a new key to replace it" : "Paste your key here"
                                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                            font: keyIn.font
                                        }
                                    }
                                }
                                Rectangle {
                                    implicitWidth: svT.implicitWidth + 30
                                    implicitHeight: 46
                                    radius: 16
                                    color: keyIn.text.trim() ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    Text {
                                        id: svT
                                        anchors.centerIn: parent
                                        text: "Save"
                                        color: keyIn.text.trim() ? app.cOnAccent : app.cDim
                                        font.family: "Inter"
                                        font.weight: Font.DemiBold
                                        font.pixelSize: app.fs(13)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: keyIn.save()
                                    }
                                }
                            }
                            // a saved key: remove it
                            Text {
                                visible: aw.hasKey
                                text: "Remove this key"
                                color: rmHov.hovered ? app.cRed : app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                font.underline: rmHov.hovered
                                HoverHandler { id: rmHov }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.removeAiKey(app.aiProvider)
                                }
                            }

                            // 3. optional: the model
                            Text {
                                Layout.topMargin: 8
                                text: "3  Model (optional)"
                                color: app.cDim
                                font.family: "Inter"
                                font.weight: Font.DemiBold
                                font.pixelSize: app.fs(11)
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 16
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                border.width: mIn.activeFocus ? 1 : 0
                                border.color: app.cBlue
                                TextInput {
                                    id: mIn
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: app.cFg
                                    selectionColor: app.cBlue
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(13)
                                    clip: true
                                    // only letters, numbers and . : _ - reach the request
                                    validator: RegularExpressionValidator { regularExpression: /[\w.:-]*/ }
                                    text: app.cfg["aiModel_" + app.aiProvider] || ""
                                    onEditingFinished: {
                                        const v = text.trim()
                                        if (v === "") app.resetSetting("aiModel_" + app.aiProvider)
                                        else app.setting("aiModel_" + app.aiProvider, v)
                                    }
                                    Text {
                                        visible: !mIn.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: aw.prov.model + " (the default)"
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                        font: mIn.font
                                    }
                                }
                            }

                            // back to the chat, once there's a key
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 8
                                visible: aw.hasKey && aw.setup
                                implicitWidth: dnT.implicitWidth + 36
                                implicitHeight: 40
                                radius: 20
                                color: app.cBlue
                                Text {
                                    id: dnT
                                    anchors.centerIn: parent
                                    text: "Done"
                                    color: app.cOnAccent
                                    font.family: "Inter"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: app.fs(13)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { aw.setup = false; input.forceActiveFocus() }
                                }
                            }
                        }
                    }
                }

                // ---- what you're writing ----
                Rectangle {
                    Layout.fillWidth: true
                    visible: !aw.showSetup
                    implicitHeight: Math.min(160, input.implicitHeight + 24)
                    radius: 22
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    border.width: input.activeFocus ? 1 : 0
                    border.color: Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.6)

                    Flickable {
                        id: inFlick
                        anchors.left: parent.left
                        anchors.right: sendBtn.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        contentHeight: input.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        TextEdit {
                            id: input
                            width: inFlick.width
                            color: app.cFg
                            selectionColor: app.cBlue
                            selectedTextColor: app.cOnAccent
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                            wrapMode: TextEdit.Wrap
                            onCursorRectangleChanged: {
                                const r = cursorRectangle
                                if (r.y < inFlick.contentY) inFlick.contentY = r.y
                                else if (r.y + r.height > inFlick.contentY + inFlick.height)
                                    inFlick.contentY = r.y + r.height - inFlick.height
                            }
                            Keys.onPressed: e => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                                        && !(e.modifiers & Qt.ShiftModifier)) {
                                    if (!app.aiBusy && text.trim() !== "") {
                                        app.aiSend(text)
                                        text = ""
                                    }
                                    e.accepted = true
                                } else if (e.key === Qt.Key_Escape) {
                                    app.aiShown = false
                                    e.accepted = true
                                }
                            }
                            Text {
                                visible: !input.text
                                text: "Ask anything\u2026"
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                font: input.font
                            }
                        }
                    }

                    // send, or stop while a reply is being written
                    Rectangle {
                        id: sendBtn
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 7
                        width: 36
                        height: 36
                        radius: 18
                        readonly property bool can: app.aiBusy || input.text.trim() !== ""
                        color: can ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        Text {
                            anchors.centerIn: parent
                            text: app.aiBusy ? "stop" : "arrow_upward"
                            color: sendBtn.can ? app.cOnAccent : app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (app.aiBusy) app.aiStop()
                                else if (input.text.trim() !== "") { app.aiSend(input.text); input.text = "" }
                                input.forceActiveFocus()
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !aw.showSetup
                    text: "Messages go to " + aw.prov.name + ". Enter sends, Shift+Enter for a new line."
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                    font.family: "Inter"
                    font.pixelSize: app.fs(10)
                }
            }
        }

        Process { id: copier }
    }
    }
}
