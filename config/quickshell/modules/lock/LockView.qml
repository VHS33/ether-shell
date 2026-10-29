import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.services

// One screen of the lock (Lock.qml makes one for each): your wallpaper as
// frosted glass; along the top, the weather, the battery and how many
// notifications came in; the date, clock and greeting; and a glass card
// with the password field and, while something's playing, its controls.
// What's typed on any screen goes into the one shared field.
// The blur, brightness, greeting and media are Settings > Lock screen's.
Item {
    id: view
    property var app
    property var lock
    property string screenName: ""

    readonly property real blur: Session.lockBlur / 12          // 0..1

    readonly property real dim: Math.max(0, Math.min(0.9, 1 - Session.lockDim / 100))
    readonly property var player: Session.lockMedia ? Media.player : null
    // Settings > Bar > Corners reaches the lock too: round pills and
    // circles, or square boxes with small corners and, for the password,
    // bars instead of dots
    readonly property bool square: view.app.squareCorners === true
    function rr(r) { return view.app.rr ? view.app.rr(r) : r }
    // Settings > Lock screen > Style: "neo" (a heads-up display in the
    // theme's colours: LockAmbient, LockNeoClock) or "classic"
    readonly property bool neo: Session.lockStyle === "neo"
    // the Neo glows drift only while you're here: typing, or the first
    // moments after locking; left alone, the screen goes still
    property bool awake: true
    Timer { id: sleepT; interval: 45000; running: true; onTriggered: view.awake = false }
    function stir() { view.awake = true; sleepT.restart() }
    readonly property string greetText: {
        if (Session.lockGreetMode === "off") return ""
        if (Session.lockGreetMode === "custom") return Session.lockGreetText.trim() || "Welcome back"
        const h = view.app.now.getHours()
        const who = Quickshell.env("USER") || ""
        return (h >= 5 && h < 12 ? "Good morning" : h >= 12 && h < 17 ? "Good afternoon"
                : h >= 17 && h < 22 ? "Good evening" : "Good night") + (who ? ", " + who : "")
    }
    // the verdict's colours, the same on any theme (the lock is always dark
    // glass): a clear green for in, a clear red for wrong
    readonly property color okColour: "#4ade80"
    readonly property color failColour: "#f87171"
    readonly property string result: view.lock.result
    readonly property color verdict: result === "ok" ? okColour : result === "fail" ? failColour : "white"
    readonly property color glassFill: Qt.rgba(1, 1, 1, 0.09)
    readonly property color glassEdge: Qt.rgba(1, 1, 1, 0.16)

    // ---- in and out: 0 = your desktop, 1 = locked ----
    // Locking, the desktop (its picture, taken just before) blurs and fades
    // into the frosted wallpaper while the clock and card rise in; the right
    // password plays it back, and the lock lets go as it ends (Lock.qml
    // waits for it), so you're back on the desktop you left.
    property real enter: 0
    NumberAnimation {
        id: comeIn
        target: view; property: "enter"; to: 1
        duration: 750; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: goOut
        target: view; property: "enter"; to: 0
        duration: 520; easing.type: Easing.InOutCubic
    }
    Component.onCompleted: comeIn.start()
    Connections {
        target: view.lock
        function onUnlockingChanged() {
            if (view.lock.unlocking) { comeIn.stop(); goOut.start() }
        }
    }

    // ---- your desktop, as it was when you locked ----
    Image {
        id: shot
        anchors.fill: parent
        source: view.lock.shotFor(view.screenName)
        fillMode: Image.Stretch
        cache: false
        asynchronous: false               // there on the very first frame
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: shot
        visible: shot.status === Image.Ready
        blurEnabled: true
        // frosting over quickly at first, before the wallpaper shows through
        blur: Math.max(view.blur, 0.5) * Math.min(1, view.enter * 2.2)
        blurMax: 64
        autoPaddingEnabled: false
    }

    // ---- the frosted wallpaper ----
    Image {
        id: wall
        anchors.fill: parent
        // (a moving wallpaper's still: it's frosted, and the lock stays still)
        source: view.app.currentStill ? "file://" + view.app.currentStill : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // a screen-sized copy is plenty under a blur
        sourceSize.width: Math.max(1, view.width)
        visible: false
    }
    MultiEffect {
        id: frost
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        opacity: view.enter
        blurEnabled: view.blur > 0
        blur: view.blur
        blurMax: 64
        autoPaddingEnabled: false
        saturation: 0.15
    }
    // darker, so the words read on any wallpaper
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: view.dim * view.enter
    }
    // Neo: glows, a dot grid and a line of light as it locks
    LockAmbient {
        anchors.fill: parent
        visible: view.neo
        app: view.app
        enter: view.enter
        awake: view.awake && view.neo
    }

    // everything else fades in
    Item {
        id: content
        anchors.fill: parent
        focus: true
        opacity: view.enter
        // rising in, settling back down on the way out
        transform: Translate { y: Math.round((1 - view.enter) * 36) }

        // ---- typing ----
        Keys.onPressed: ev => {
            view.stir()
            view.lock.checkCaps()
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) view.lock.submit()
            else if (ev.key === Qt.Key_Backspace)
                (ev.modifiers & Qt.ControlModifier) ? view.lock.clear() : view.lock.backspace()
            else if (ev.key === Qt.Key_Escape) view.lock.clear()
            else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_U) view.lock.clear()
            else if (ev.text !== "" && !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                     && ev.text.charCodeAt(0) >= 32) view.lock.type(ev.text)
            ev.accepted = true
        }

        // ---- along the top: weather, battery, notifications ----
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 28
            anchors.rightMargin: 32
            spacing: 10
            LockChip {
                app: view.app
                icon: Weather.wxSymbol(Weather.wxCond, Weather.wxDay)
                label: Weather.wxOk ? Weather.wxTemp + "  " + Weather.wxCond : ""
            }
            LockChip {
                app: view.app
                icon: Battery.icon
                label: Battery.present ? Battery.percent + "%" : ""
                tint: Battery.low ? view.app.cRed : "white"
                // the battery lies on its side, like the bar's (the bolt doesn't)
                iconRotation: Battery.charging ? 0 : 90
            }
            LockChip {
                app: view.app
                icon: "notifications"
                label: Notifications.notifUnseen > 0
                       ? Notifications.notifUnseen + (Notifications.notifUnseen === 1 ? " notification" : " notifications")
                       : ""
            }
        }

        // Neo: the clock as a heads-up display
        LockNeoClock {
            id: neoClock
            visible: view.neo
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(view.height * 0.13)
            width: implicitWidth
            height: implicitHeight
            app: view.app
            enter: view.enter
            square: view.square
            greeting: view.greetText
            clockSize: Math.round(Math.min(view.height * 0.17, 190))
        }

        Column {
            id: middle
            visible: !view.neo
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(view.height * 0.13)
            spacing: 0

            // the date
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(view.app.now, "dddd, d MMMM")
                color: Qt.rgba(1, 1, 1, 0.85)
                font.family: Theme.uiFont
                font.weight: Font.Medium
                font.pixelSize: view.app.fs(20)
            }
            // the clock, large and light, with AM/PM small beside it
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    id: clockText
                    // (Qt only counts hours in twelves when AM/PM is in the
                    // same format, so it's asked for and then left off)
                    text: view.app.cfg.clock24h === true ? Qt.formatTime(view.app.now, "HH:mm")
                                                        : Qt.formatTime(view.app.now, "h:mm AP").split(" ")[0]
                    color: "white"
                    font.family: Theme.uiFont
                    font.weight: Font.ExtraLight
                    font.pixelSize: Math.round(Math.min(view.height * 0.17, 190))
                }
                Text {
                    visible: view.app.cfg.clock24h !== true
                    anchors.baseline: clockText.baseline
                    text: Qt.formatTime(view.app.now, "AP")
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font.family: Theme.uiFont
                    font.weight: Font.Normal
                    font.pixelSize: Math.round(clockText.font.pixelSize * 0.22)
                }
            }
            // the greeting
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Session.lockGreetMode !== "off"
                readonly property int h: view.app.now.getHours()
                readonly property string who: Quickshell.env("USER") || ""
                text: Session.lockGreetMode === "custom" ? (Session.lockGreetText.trim() || "Welcome back")
                    : (h >= 5 && h < 12 ? "Good morning" : h >= 12 && h < 17 ? "Good afternoon"
                       : h >= 17 && h < 22 ? "Good evening" : "Good night") + (who ? ", " + who : "")
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: Theme.uiFont
                font.pixelSize: view.app.fs(17)
            }
        }

        // ---- the glass card: password, then what's playing ----
        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: view.neo ? neoClock.bottom : middle.bottom
            anchors.topMargin: Math.round(view.height * 0.06) - (view.neo ? 36 : 0)
            width: 440
            height: cardCol.implicitHeight + 36
            radius: view.rr(32)
            color: view.glassFill
            border.width: 1
            border.color: view.glassEdge
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Column {
                id: cardCol
                anchors.top: parent.top
                anchors.topMargin: 18
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 36
                spacing: 10

                Rectangle {
                    id: field
                    width: parent.width
                    height: 54
                    // square: a touch smaller than the card's, as it sits inside it
                    radius: view.square ? Math.max(2, view.rr(27) - 2) : 27
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1
                    border.color: view.result !== "" ? Qt.rgba(view.verdict.r, view.verdict.g, view.verdict.b, 0.85)
                                  : view.lock.messageIsError && view.lock.message !== ""
                                  ? Qt.rgba(view.app.cRed.r, view.app.cRed.g, view.app.cRed.b, 0.8)
                                  : Qt.rgba(1, 1, 1, 0.2)
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // Neo: a line along the bottom that charges as you type,
                    // and runs while the password is checked
                    Rectangle {
                        visible: view.neo
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: (parent.width - 2 * parent.radius) * (view.result !== "" ? 1 : Math.min(1, view.lock.buffer.length / 14))
                        height: 2
                        radius: 1
                        color: view.result !== "" ? view.verdict : view.app.cBlue
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                    // shakes on a wrong password
                    transform: Translate { id: shakeT; x: 0 }
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 50; easing.type: Easing.OutQuad }
                        NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
                        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
                        NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 50 }
                        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50; easing.type: Easing.OutQuad }
                    }
                    Connections { target: view.lock; function onWrong() { shake.restart() } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: "lock"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                    }
                    // the typed characters, as dots (bars when square); a hint while empty
                    Text {
                        anchors.centerIn: parent
                        visible: view.lock.buffer === "" && !view.lock.busy && view.result === ""
                        text: "Enter your password"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Theme.uiFont
                        font.pixelSize: view.app.fs(14)
                    }
                    // A fixed set of dots, each shown while there's a character
                    // for it: only the new one grows in, and the others slide
                    // over to keep the row centred.  (Made from the count alone,
                    // every dot was rebuilt on each key and popped in again,
                    // which flashed.)
                    Row {
                        id: dots
                        anchors.centerIn: parent
                        // square: wider bars, closer together
                        spacing: view.square ? 3 : 7
                        // at most what fits; the rest are still there
                        readonly property int fit: Math.max(1, Math.floor((field.width - 104 + spacing) / ((view.square ? 12 : 9) + spacing)))
                        readonly property int shown: Math.min(view.result !== "" ? view.lock.heldLen : view.lock.buffer.length, 22, fit)
                        add: Transition {
                            NumberAnimation { property: "scale"; from: 0; to: 1; duration: 150; easing.type: Easing.OutBack }
                        }
                        move: Transition {
                            NumberAnimation { property: "x"; duration: 120; easing.type: Easing.OutCubic }
                        }
                        Repeater {
                            model: 22
                            Rectangle {
                                required property int index
                                visible: index < dots.shown
                                width: view.square ? 12 : 9
                                height: view.square ? 18 : 9
                                radius: view.square ? 1.5 : 4.5
                                id: mark
                                // lit as the scan passes over it, while checking
                                readonly property bool lit: scan.running
                                    && Math.abs(dots.x + mark.x + mark.width / 2 - scan.pos) < 12
                                color: lit ? view.app.cBlue : view.verdict
                                opacity: lit ? 1 : view.lock.busy && view.result === "" ? 0.45 : 0.95
                                // instant while scanning (the light passes quickly); a
                                // short fade into the verdict's colour
                                Behavior on opacity { enabled: !scan.running; NumberAnimation { duration: 150 } }
                                Behavior on color { enabled: !scan.running; ColorAnimation { duration: 150 } }
                                scale: lit ? 1.25 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }
                        }
                    }
                    // While the password is checked: a bar of light sweeping
                    // back and forth over the marks, scanning them
                    Item {
                        id: scan
                        anchors.fill: parent
                        readonly property bool running: view.lock.busy && view.result === "" && dots.shown > 0
                        visible: running
                        clip: true
                        // where the bar is, across the field (sweeping a
                        // little past the first and last mark)
                        property real t: 0
                        readonly property real from: dots.x - 22
                        readonly property real to: dots.x + dots.width + 22
                        readonly property real pos: from + (to - from) * t
                        property bool forward: true
                        SequentialAnimation on t {
                            running: scan.running
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 620; easing.type: Easing.InOutSine }
                            ScriptAction { script: scan.forward = false }
                            NumberAnimation { from: 1; to: 0; duration: 620; easing.type: Easing.InOutSine }
                            ScriptAction { script: scan.forward = true }
                        }
                        onRunningChanged: if (running) { t = 0; forward = true }
                        // the glow it leaves behind
                        Rectangle {
                            readonly property real w: 70
                            x: scan.forward ? scan.pos - w : scan.pos
                            width: w
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 9
                            radius: view.square ? 2 : 6
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: scan.forward ? "transparent" : Qt.rgba(view.app.cBlue.r, view.app.cBlue.g, view.app.cBlue.b, 0.28) }
                                GradientStop { position: 1; color: scan.forward ? Qt.rgba(view.app.cBlue.r, view.app.cBlue.g, view.app.cBlue.b, 0.28) : "transparent" }
                            }
                        }
                        // the bar
                        Rectangle {
                            x: scan.pos - width / 2
                            width: 2
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            radius: 1
                            color: view.app.cBlue
                        }
                    }
                    // Enter (dimmed while it's checked)
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: "arrow_forward"
                        color: Qt.rgba(1, 1, 1, view.lock.buffer !== "" && !view.lock.busy ? 0.9 : 0.35)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.lock.submit()
                        }
                    }
                }

                // what went wrong, or Caps Lock
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: text === "" ? 0 : 18
                    Behavior on height { NumberAnimation { duration: 160 } }
                    readonly property string raw: view.lock.message !== "" ? view.lock.message
                        : view.lock.capsLock ? "Caps Lock is on" : ""
                    text: view.neo ? raw.toUpperCase() : raw
                    font.letterSpacing: view.neo ? 2.5 : 0
                    color: view.result !== "" ? view.verdict
                         : view.lock.messageIsError ? view.app.cRed : Qt.rgba(1, 1, 1, 0.7)
                    font.family: Theme.uiFont
                    font.weight: Font.Medium
                    font.pixelSize: view.app.fs(13)
                }

                // ---- what's playing: art, title, artist, controls ----
                Item {
                    id: media
                    width: parent.width
                    visible: view.player !== null && (view.player.trackTitle || "") !== ""
                    height: visible ? 64 : 0

                    // the album art, or a note while there's none
                    Rectangle {
                        id: artBox
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56; height: 56; radius: view.rr(14)
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            anchors.centerIn: parent
                            visible: art.status !== Image.Ready
                            text: "music_note"
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 24
                        }
                        Image {
                            id: art
                            anchors.fill: parent
                            source: view.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 112
                            visible: false
                        }
                        Item {
                            id: artMask
                            anchors.fill: parent
                            layer.enabled: true
                            visible: false
                            Rectangle { anchors.fill: parent; radius: view.rr(14); color: "black" }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: art
                            maskEnabled: true
                            maskSource: artMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            visible: art.status === Image.Ready
                        }
                    }
                    Column {
                        anchors.left: artBox.right
                        anchors.leftMargin: 14
                        anchors.right: controls.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: view.player?.trackTitle ?? ""
                            color: "white"
                            font.family: Theme.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: view.app.fs(14)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: view.player?.trackArtist ?? ""
                            color: Qt.rgba(1, 1, 1, 0.65)
                            font.family: Theme.uiFont
                            font.pixelSize: view.app.fs(12)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: [
                                { g: "skip_previous", a: "prev" },
                                { g: "", a: "play" },
                                { g: "skip_next", a: "next" }
                            ]
                            Rectangle {
                                id: mBtn
                                required property var modelData
                                readonly property bool isPlay: modelData.a === "play"
                                width: isPlay ? 44 : 36
                                height: width
                                radius: view.rr(width / 2)
                                anchors.verticalCenter: parent.verticalCenter
                                color: isPlay ? "white"
                                     : mHov.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: mHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: mBtn.isPlay ? (Media.playing ? "pause" : "play_arrow") : mBtn.modelData.g
                                    color: mBtn.isPlay ? "#1b1b1f" : "white"
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: mBtn.isPlay ? 24 : 22
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = view.player
                                        if (!p) return
                                        if (mBtn.modelData.a === "prev") { if (p.canGoPrevious) p.previous() }
                                        else if (mBtn.modelData.a === "next") { if (p.canGoNext) p.next() }
                                        else if (p.canTogglePlaying) p.togglePlaying()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
