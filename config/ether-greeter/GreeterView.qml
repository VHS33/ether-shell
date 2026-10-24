import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Ether Shell's login screen: what you see and type into.  Plain QtQuick,
// nothing about greetd, so it can be previewed and tested on its own; the
// wrapper (greeter.qml) connects it to greetd (or to a pretend login, in
// preview) and puts one on every screen.
//
//   signals: login(user, password, sessionIndex), respond(text), power(action)
//   the wrapper answers with: fail(message), askMore(prompt, echo),
//   info(message), and sets busy
Item {
    id: view

    // ---- from the wrapper ----
    property var pal: ({})                  // the desktop's colours (colors.json)
    property string wallpaper: ""           // file path of the desktop's wallpaper
    property bool main: true                // this screen has the login card
    property string lastUser: ""
    property var sessions: [ { name: "Hyprland", detail: "with UWSM" } ]
    property int sessionIndex: 0
    property bool capsLock: false
    property bool busy: false

    signal login(string user, string password, int sessionIndex)
    signal respond(string text)
    signal power(string action)

    // ---- colours, with fallbacks for a missing or unreadable colour file ----
    readonly property var p: (pal && typeof pal === "object") ? pal : ({})
    readonly property color cBg:     p.bg      ?? "#14161a"
    readonly property color cCard:   p.card    ?? "#1e2126"
    readonly property color cSurf:   p.surf    ?? "#282c32"
    readonly property color cBorder: p.border  ?? "#454a52"
    readonly property color cFg:     p.fg      ?? "#e3e5ea"
    readonly property color cDim:    p.dim     ?? "#b8bcc4"
    readonly property color cFaint:  p.faint   ?? "#868a92"
    readonly property color cAccent: p.vivid   ?? p.blue ?? "#8ab4f8"
    readonly property color cOnAcc:  p.onVivid ?? p.onAccent ?? "#14161a"
    readonly property color cRed:    p.red     ?? "#ffb4ab"

    // ---- what the card is saying ----
    property string message: ""
    property bool messageIsError: false
    property string extraPrompt: ""         // a second question (a code, a new password...)
    property bool extraEcho: false

    function fail(msg) {
        busy = false
        extraPrompt = ""
        message = msg && msg.length ? msg : "Wrong username or password"
        messageIsError = true
        password.text = ""
        password.forceActiveFocus()
        shake.restart()
    }
    function askMore(prompt, echo) {
        busy = false
        // "Verification code: " from PAM reads as "Verification code"
        extraPrompt = (prompt || "").replace(/[:\s]+$/, "") || "One more step"
        extraEcho = echo
        message = ""
        password.text = ""
        password.forceActiveFocus()
    }
    function info(msg) { message = msg; messageIsError = false }
    // ready to type the moment it appears
    Component.onCompleted: if (main) Qt.callLater(() => (lastUser !== "" ? password : username).forceActiveFocus())
    function submit() {
        if (busy) return
        if (extraPrompt !== "") { busy = true; view.respond(password.text); password.text = ""; return }
        if (username.text.trim() === "") { username.forceActiveFocus(); return }
        if (password.text === "") { password.forceActiveFocus(); return }
        message = ""
        busy = true
        view.login(username.text.trim(), password.text, sessionIndex)
    }

    // ---- the wallpaper, softly blurred and dimmed ----
    Rectangle { anchors.fill: parent; color: view.cBg }
    Image {
        id: wall
        anchors.fill: parent
        source: view.wallpaper ? "file://" + view.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920                 // plenty, blurred
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 0.1
    }
    Rectangle { anchors.fill: parent; color: view.cBg; opacity: wall.status === Image.Ready ? 0.55 : 1 }

    // ---- the time ----
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }
    Column {
        id: clock
        // a soft shadow, so the time reads over any wallpaper, bright ones too
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.55
            shadowBlur: 0.9
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }
        anchors.horizontalCenter: parent.horizontalCenter
        y: view.main ? parent.height * 0.16 : (parent.height - height) / 2
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(view.now, "hh:mm")
            color: view.cFg
            font.family: "Inter"
            font.weight: Font.Light
            font.pixelSize: Math.round(view.height * 0.11)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(view.now, "dddd d MMMM")
            color: view.cDim
            font.family: "Inter"
            font.pixelSize: Math.max(16, Math.round(view.height * 0.022))
        }
    }

    // ---- the card ----
    Rectangle {
        id: card
        visible: view.main
        width: 400
        height: cardCol.implicitHeight + 56
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shakeX
        y: clock.y + clock.height + parent.height * 0.06
        radius: 30
        color: Qt.rgba(view.cCard.r, view.cCard.g, view.cCard.b, 0.78)
        border.width: 1
        border.color: Qt.rgba(view.cBorder.r, view.cBorder.g, view.cBorder.b, 0.6)
        property real shakeX: 0
        SequentialAnimation {
            id: shake
            loops: 1
            NumberAnimation { target: card; property: "shakeX"; to: -14; duration: 50 }
            NumberAnimation { target: card; property: "shakeX"; to: 12; duration: 70 }
            NumberAnimation { target: card; property: "shakeX"; to: -8; duration: 70 }
            NumberAnimation { target: card; property: "shakeX"; to: 5; duration: 60 }
            NumberAnimation { target: card; property: "shakeX"; to: 0; duration: 60 }
        }

        ColumnLayout {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 12

            // the lock, in the accent
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 56; height: 56; radius: 28
                color: Qt.rgba(view.cAccent.r, view.cAccent.g, view.cAccent.b, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: view.busy ? "hourglass_top" : "lock"
                    color: view.cAccent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 28
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 6
                text: view.extraPrompt !== "" ? "One more step" : "Sign in"
                color: view.cFg
                font.family: "Inter"
                font.weight: Font.DemiBold
                font.pixelSize: 20
            }

            // username
            Field {
                id: userField
                Layout.fillWidth: true
                visible: view.extraPrompt === ""
                glyph: "person"
                input: username
                TextInput {
                    id: username
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: view.cFg
                    selectionColor: view.cAccent
                    selectedTextColor: view.cOnAcc
                    font.family: "Inter"
                    font.pixelSize: 16
                    enabled: !view.busy
                    text: view.lastUser
                    focus: view.lastUser === ""
                    Keys.onReturnPressed: password.forceActiveFocus()
                    Keys.onEnterPressed: password.forceActiveFocus()
                    Keys.onTabPressed: password.forceActiveFocus()
                    onTextEdited: view.message = ""
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: parent.text === ""
                        text: "Username"
                        color: view.cFaint
                        font: parent.font
                    }
                }
            }

            // password (or the second question)
            Field {
                id: passField
                Layout.fillWidth: true
                glyph: view.extraPrompt !== "" ? "pin" : "key"
                input: password
                trailing: go
                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.rightMargin: 44
                    verticalAlignment: TextInput.AlignVCenter
                    color: view.cFg
                    selectionColor: view.cAccent
                    selectedTextColor: view.cOnAcc
                    font.family: "Inter"
                    font.pixelSize: 16
                    enabled: !view.busy
                    echoMode: view.extraPrompt !== "" && view.extraEcho ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "\u2022"
                    focus: view.lastUser !== ""
                    Keys.onReturnPressed: view.submit()
                    Keys.onEnterPressed: view.submit()
                    Keys.onBacktabPressed: username.forceActiveFocus()
                    Keys.onEscapePressed: text = ""
                    onTextEdited: if (view.messageIsError) view.message = ""
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: parent.text === ""
                        text: view.extraPrompt !== "" ? view.extraPrompt : "Password"
                        color: view.cFaint
                        font: parent.font
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    id: go
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: goHover.hovered ? Qt.lighter(view.cAccent, 1.1) : view.cAccent
                    opacity: view.busy ? 0.5 : 1
                    Text {
                        anchors.centerIn: parent
                        text: "arrow_forward"
                        color: view.cOnAcc
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 22
                    }
                    HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: view.submit() }
                }
            }

            // what's happening: an error, caps lock, or signing in
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text !== ""
                text: view.busy ? "Signing in\u2026"
                      : view.message !== "" ? view.message
                      : view.capsLock ? "Caps Lock is on" : ""
                color: view.messageIsError && !view.busy ? view.cRed : view.cDim
                font.family: "Inter"
                font.pixelSize: 13
            }

            // the session: click to change
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                visible: view.extraPrompt === ""
                implicitWidth: sessRow.implicitWidth + 28
                implicitHeight: 34
                radius: 17
                color: sessHover.hovered ? Qt.rgba(view.cFg.r, view.cFg.g, view.cFg.b, 0.12) : Qt.rgba(view.cFg.r, view.cFg.g, view.cFg.b, 0.06)
                Row {
                    id: sessRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "desktop_windows"
                        color: view.cDim
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 16
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (view.sessions[view.sessionIndex] || {}).name || ""
                        color: view.cFg
                        font.family: "Inter"
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (view.sessions[view.sessionIndex] || {}).detail || ""
                        visible: text !== ""
                        color: view.cFaint
                        font.family: "Inter"
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: view.sessions.length > 1
                        text: "unfold_more"
                        color: view.cDim
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 16
                    }
                }
                HoverHandler { id: sessHover; cursorShape: view.sessions.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: if (!view.busy) view.sessionIndex = (view.sessionIndex + 1) % view.sessions.length }
            }
        }
    }

    // ---- restart and power off ----
    Row {
        visible: view.main
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 10
        Repeater {
            model: [ { g: "restart_alt", a: "reboot", t: "Restart" }, { g: "power_settings_new", a: "poweroff", t: "Power off" } ]
            delegate: Rectangle {
                required property var modelData
                width: 48; height: 48; radius: 24
                color: powHover.hovered ? Qt.rgba(view.cCard.r, view.cCard.g, view.cCard.b, 0.95) : Qt.rgba(view.cCard.r, view.cCard.g, view.cCard.b, 0.7)
                border.width: 1
                border.color: Qt.rgba(view.cBorder.r, view.cBorder.g, view.cBorder.b, 0.5)
                Text {
                    anchors.centerIn: parent
                    text: modelData.g
                    color: view.cFg
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 22
                }
                HoverHandler { id: powHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: view.power(modelData.a) }
            }
        }
    }

    // a rounded field with an icon
    component Field: Rectangle {
        id: f
        property string glyph: ""
        property Item input
        property Item trailing
        default property alias content: box.data
        implicitHeight: 52
        radius: 26
        color: Qt.rgba(view.cSurf.r, view.cSurf.g, view.cSurf.b, 0.9)
        border.width: input && input.activeFocus ? 2 : 1
        border.color: input && input.activeFocus ? view.cAccent : Qt.rgba(view.cBorder.r, view.cBorder.g, view.cBorder.b, 0.6)
        Text {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: f.glyph
            color: f.input && f.input.activeFocus ? view.cAccent : view.cDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
        }
        Item {
            id: box
            anchors { left: icon.right; leftMargin: 12; right: parent.right; rightMargin: 18; top: parent.top; bottom: parent.bottom }
        }
        TapHandler { onTapped: if (f.input) f.input.forceActiveFocus() }
    }
}
