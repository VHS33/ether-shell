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
        source: view.app.currentWall ? "file://" + view.app.currentWall : ""
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

        Column {
            id: middle
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
            anchors.top: middle.bottom
            anchors.topMargin: Math.round(view.height * 0.06)
            width: 440
            height: cardCol.implicitHeight + 36
            radius: 32
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
                    radius: 27
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1
                    border.color: view.lock.messageIsError && view.lock.message !== ""
                                  ? Qt.rgba(view.app.cRed.r, view.app.cRed.g, view.app.cRed.b, 0.8)
                                  : Qt.rgba(1, 1, 1, 0.2)
                    Behavior on border.color { ColorAnimation { duration: 200 } }

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
                    // the typed characters, as dots; a hint while empty
                    Text {
                        anchors.centerIn: parent
                        visible: view.lock.buffer === "" && !view.lock.busy
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
                        spacing: 7
                        // at most what fits; the rest are still there
                        readonly property int shown: Math.min(view.lock.buffer.length, 22)
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
                                width: 9; height: 9; radius: 4.5
                                color: "white"
                                opacity: view.lock.busy ? 0.45 : 0.95
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                    // Enter, or busy while it's checked
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.lock.busy ? "progress_activity" : "arrow_forward"
                        color: Qt.rgba(1, 1, 1, view.lock.buffer !== "" || view.lock.busy ? 0.9 : 0.35)
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        // spins while busy, and sits straight again after
                        property real spin: 0
                        rotation: view.lock.busy ? spin : 0
                        NumberAnimation on spin {
                            running: view.lock.busy
                            from: 0; to: 360; duration: 900; loops: Animation.Infinite
                        }
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
                    text: view.lock.message !== "" ? view.lock.message
                        : view.lock.capsLock ? "Caps Lock is on" : ""
                    color: view.lock.messageIsError ? view.app.cRed : Qt.rgba(1, 1, 1, 0.7)
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
                        width: 56; height: 56; radius: 14
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
                            Rectangle { anchors.fill: parent; radius: 14; color: "black" }
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
                                radius: width / 2
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
