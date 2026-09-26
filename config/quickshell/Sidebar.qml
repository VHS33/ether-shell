import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// ============================================================
//   SIDEBAR
//   Top to bottom:
//     header      time, date, weather
//     quick tiles labelled toggles that show real state
//     actions     screenshot, wallpaper, settings, lock, power
//     sliders     output and microphone
//     media       only while something is playing
//     tabs        Calendar (with notifications below it) |
//                 Clipboard, filling whatever height is left
//
//   Same visual language as Settings: cards, Inter for words,
//   the Nerd Font only for glyphs.  Lists are Repeaters/ListViews
//   over plain-value arrays; live notification objects stay in
//   app.notifRefs.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // ---------------------------------------------------------
    //   building blocks
    // ---------------------------------------------------------

    // a labelled toggle: icon, title and state line; lit when `on`
    component Tile: Rectangle {
        id: tile
        property var app
        property string glyph: ""
        property string title: ""
        property string sub: ""
        property bool on: false
        property bool chevron: false
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 58
        radius: 18
        color: on ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
             : tHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: tHov }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: 19
                color: tile.on ? tile.app.cBlue : Qt.rgba(tile.app.cFg.r, tile.app.cFg.g, tile.app.cFg.b, 0.08)
                Behavior on color { ColorAnimation { duration: app.animQuick } }
                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.on ? tile.app.cOnAccent : tile.app.cDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(16)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    color: tile.app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.sub
                    color: tile.app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: tile.chevron
                text: "chevron_right"
                color: tile.app.cFaint
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(14)
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    // an image with properly rounded corners.  A Rectangle's `clip`
    // only cuts a square, so the corners are masked with MultiEffect.
    component RoundImage: Item {
        id: ri
        property alias source: riImg.source
        property real radius: 12
        property real imgOpacity: 1
        readonly property bool ready: riImg.status === Image.Ready

        Image {
            id: riImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Item {
            id: riMask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle {
                anchors.fill: parent
                radius: ri.radius
                color: "black"
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: riImg
            maskEnabled: true
            maskSource: riMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: ri.ready
            opacity: ri.imgOpacity
        }
    }

    // round icon button with a hover tint; `danger` turns red on hover
    component RoundBtn: Rectangle {
        id: rb
        property var app
        property string glyph: ""
        property bool danger: false
        property int size: 42
        signal clicked()

        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: rbHov.hovered ? (danger ? app.cRed : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12))
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: rbHov }

        Text {
            anchors.centerIn: parent
            text: rb.glyph
            color: rbHov.hovered && rb.danger ? rb.app.cOnAccent
                 : rbHov.hovered ? rb.app.cFg : rb.app.cDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: app.fs(17)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    // icon (click to mute) + slider + percentage, for a PipeWire node
    component VolRow: RowLayout {
        id: vr
        property var app
        property var au: null
        property string glyph: ""
        property string mutedGlyph: ""
        property color accent: app.cBlue
        readonly property real v: au?.volume ?? 0
        readonly property bool muted: au?.muted ?? false

        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: vrHov.hovered ? Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.12) : "transparent"
            HoverHandler { id: vrHov }
            Text {
                anchors.centerIn: parent
                text: vr.muted ? vr.mutedGlyph : vr.glyph
                color: vr.muted ? vr.app.cFaint : vr.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(16)
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (vr.au) vr.au.muted = !vr.au.muted
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 24

            Rectangle {
                id: vrTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: Qt.rgba(vr.app.cFg.r, vr.app.cFg.g, vr.app.cFg.b, 0.08)

                Rectangle {
                    width: vrTrack.width * Math.min(1, vr.v)
                    height: parent.height
                    radius: 4
                    color: vr.muted ? vr.app.cFaint : vr.accent
                }
            }
            Rectangle {
                width: 4
                height: 18
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(vrTrack.width - width, vrTrack.width * Math.min(1, vr.v) - 2))
                color: vr.muted ? vr.app.cFaint : vr.accent
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function set(x) {
                    if (!vr.au) return
                    vr.au.volume = Math.max(0, Math.min(1, x / width))
                    if (vr.au.muted) vr.au.muted = false
                }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x) }
                onWheel: w => {
                    if (!vr.au) return
                    vr.au.volume = Math.max(0, Math.min(1,
                        vr.au.volume + (w.angleDelta.y > 0 ? 0.02 : -0.02)))
                }
            }
        }

        Text {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: vr.muted ? "Muted" : Math.round(vr.v * 100) + "%"
            color: vr.app.cDim
            font.family: "Inter"
            font.pixelSize: app.fs(11)
        }
    }

    // brightness for both monitors together, through DDC/CI
    component BrightRow: RowLayout {
        id: br
        property var app
        readonly property real v: app.brightAvg / 100

        Layout.fillWidth: true
        spacing: 10

        Item {
            implicitWidth: 32
            implicitHeight: 32
            Text {
                anchors.centerIn: parent
                text: "light_mode"
                color: br.app.cYellow
                font.family: "Material Symbols Rounded"
                font.pixelSize: br.app.fs(16)
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 24
            Rectangle {
                id: brTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: Qt.rgba(br.app.cFg.r, br.app.cFg.g, br.app.cFg.b, 0.08)
                Rectangle {
                    width: brTrack.width * br.v
                    height: parent.height
                    radius: 4
                    color: br.app.cYellow
                }
            }
            Rectangle {
                width: 4
                height: 18
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(brTrack.width - width, brTrack.width * br.v - 2))
                color: br.app.cYellow
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function set(x) { br.app.setAllBright(100 * Math.max(0, Math.min(1, x / width))) }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x) }
                onWheel: w => br.app.setAllBright(br.app.brightAvg + (w.angleDelta.y > 0 ? 5 : -5))
            }
        }

        Text {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: br.app.brightAvg + "%"
            color: br.app.cDim
            font.family: "Inter"
            font.pixelSize: br.app.fs(11)
        }
    }

    // ---------------------------------------------------------
    //   the sidebar
    // ---------------------------------------------------------
    PanelWindow {
        id: winS
        required property var modelData
        screen: modelData
        // The window stays mapped and the card slides in and out.  Mapping
        // a new surface on every open (plus Hyprland's layer fade) is what
        // made opening lag.  Closed, the mask is empty, so clicks pass
        // straight through to the windows underneath.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.sidebarShown

        // the full height between the bar and the dock
        anchors { top: true; right: true; bottom: true }
        margins {
            top: app.barBottom + 6
            right: app.gap
            bottom: app.gap + app.dockSpace
        }
        implicitWidth: 400
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // the clipboard search box needs typing, but only while open
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        property Region shownMask: Region { x: 8; y: 8; width: winS.width - 16; height: winS.height - 16 }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource

        PwObjectTracker {
            objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
        }

        onOpenChanged: if (open) {
            clipSearch.text = ""
            if (app.sideTab === 1) clipSearch.forceActiveFocus()
            else keys.forceActiveFocus()
        }

        // close the sidebar, then run something once it's out of the way
        function closeThen(cmd) {
            app.sidebarShown = false
            app.run("sleep 0.3; " + cmd)
        }

        Rectangle {
            id: sideCard
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            width: parent.width - 16
            // slides in from the right edge
            x: winS.open ? 8 : parent.width + 8
            opacity: winS.open ? 1 : 0
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            radius: 24
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: app.sidebarShown = false
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // ================= HEADER =================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 4
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -2
                        // follows Settings > Bar > Time format; 12-hour
                        // gets a small AM/PM beside the time
                        Row {
                            spacing: 6
                            Text {
                                id: bigTime
                                // Qt only uses 12-hour "h" when AP is in the same
                                // format string, so format with it and keep the time
                                text: app.cfg.clock24h === true
                                      ? Qt.formatDateTime(app.now, "HH:mm")
                                      : Qt.formatDateTime(app.now, "h:mm AP").split(" ")[0]
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(38)
                                font.weight: Font.Light
                            }
                            Text {
                                visible: app.cfg.clock24h !== true
                                anchors.baseline: bigTime.baseline
                                text: Qt.formatDateTime(app.now, "AP")
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(15)
                            }
                        }
                        Text {
                            text: Qt.formatDateTime(app.now, "dddd, d MMMM")
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                        }
                    }

                    // weather; click to refresh
                    Item {
                        implicitWidth: wxRow.implicitWidth
                        implicitHeight: wxRow.implicitHeight

                        RowLayout {
                            id: wxRow
                            spacing: 8
                            Text {
                                text: app.wxOk ? app.wxSymbol(app.wxCond, app.wxDay) : "cloud_off"
                                color: app.cYellow
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(30)
                            }
                            ColumnLayout {
                                spacing: 0
                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: app.wxOk ? app.wxTemp : "\u2014"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(18)
                                    font.bold: true
                                }
                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    Layout.maximumWidth: 120
                                    text: app.wxOk ? app.wxCond : (app.wxHasPlace ? "No weather" : "Set location in Settings")
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.refreshWeather()
                        }
                    }
                }

                // ================= QUICK TILES =================
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    Tile {
                        app: rootV.app
                        readonly property bool isMuted: winS.sink?.audio?.muted ?? false
                        glyph: isMuted ? "volume_off" : "volume_up"
                        title: "Sound"
                        sub: isMuted ? "Muted" : Math.round((winS.sink?.audio?.volume ?? 0) * 100) + "%"
                        on: !isMuted
                        onClicked: { const a = winS.sink?.audio; if (a) a.muted = !a.muted }
                    }
                    Tile {
                        app: rootV.app
                        readonly property bool isMuted: winS.source?.audio?.muted ?? false
                        glyph: isMuted ? "mic_off" : "mic"
                        title: "Microphone"
                        sub: isMuted ? "Muted" : "On"
                        on: !isMuted
                        onClicked: { const a = winS.source?.audio; if (a) a.muted = !a.muted }
                    }
                    Tile {
                        app: rootV.app
                        glyph: app.netKind === "wifi" ? "wifi"
                             : app.netKind === "ethernet" ? "lan" : "wifi_off"
                        title: app.netKind === "wifi" ? "Wi-Fi"
                             : app.netKind === "ethernet" ? "Wired" : "Network"
                        sub: app.netName !== "" ? app.netName : "Not connected"
                        on: app.netKind !== ""
                        chevron: true
                        onClicked: winS.closeThen("nm-connection-editor")
                    }
                    Tile {
                        app: rootV.app
                        glyph: app.dnd ? "notifications_off" : "notifications"
                        title: "Do not disturb"
                        sub: app.dnd ? "Popups hidden" : "Off"
                        on: app.dnd
                        onClicked: app.dnd = !app.dnd
                    }
                    Tile {
                        app: rootV.app
                        Layout.columnSpan: 2
                        glyph: "dark_mode"
                        title: "Night light"
                        sub: app.nightLight ? "On, warmer colours" : "Off"
                        on: app.nightLight
                        onClicked: app.toggleNight()
                    }
                }

                // ================= ACTIONS =================
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Item { Layout.fillWidth: true }
                    RoundBtn {
                        app: rootV.app
                        glyph: "screenshot_region"
                        onClicked: winS.closeThen("$HOME/.local/bin/shot")
                    }
                    Item { Layout.fillWidth: true }
                    RoundBtn {
                        app: rootV.app
                        glyph: "wallpaper"
                        onClicked: { app.settingsPage = 3; app.settingsShown = true; app.sidebarShown = false }
                    }
                    Item { Layout.fillWidth: true }
                    RoundBtn {
                        app: rootV.app
                        glyph: "settings"
                        onClicked: { app.settingsShown = true; app.sidebarShown = false }
                    }
                    Item { Layout.fillWidth: true }
                    RoundBtn {
                        app: rootV.app
                        glyph: "lock"
                        onClicked: winS.closeThen("loginctl lock-session")
                    }
                    Item { Layout.fillWidth: true }
                    RoundBtn {
                        app: rootV.app
                        glyph: "power_settings_new"
                        danger: true
                        onClicked: { app.powerShown = true; app.sidebarShown = false }
                    }
                    Item { Layout.fillWidth: true }
                }

                // ================= SLIDERS =================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    VolRow {
                        app: rootV.app
                        au: winS.sink?.audio ?? null
                        glyph: "volume_up"
                        mutedGlyph: "volume_off"
                    }
                    VolRow {
                        app: rootV.app
                        au: winS.source?.audio ?? null
                        glyph: "mic"
                        mutedGlyph: "mic_off"
                        accent: rootV.app.cTeal
                    }
                    BrightRow {
                        app: rootV.app
                        visible: app.brightOk
                    }
                }

                // ================= MEDIA =================
                Rectangle {
                    Layout.fillWidth: true
                    visible: app.player !== null
                    implicitHeight: 84
                    radius: 18
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)

                    RoundImage {
                        anchors.fill: parent
                        radius: 18
                        imgOpacity: 0.25
                        source: app.player?.trackArtUrl ?? ""
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            implicitWidth: 60
                            implicitHeight: 60
                            radius: 12
                            color: app.cCard
                            RoundImage {
                                anchors.fill: parent
                                radius: 12
                                source: app.player?.trackArtUrl ?? ""
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !app.player?.trackArtUrl
                                text: "music_note"
                                color: app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(22)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: app.player?.trackTitle || "Nothing playing"
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(13)
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: app.player?.trackArtist ?? ""
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            model: [
                                { g: "skip_previous", a: "prev" },
                                { g: "",          a: "play" },
                                { g: "skip_next", a: "next" }
                            ]
                            delegate: Rectangle {
                                id: mBtn
                                required property var modelData
                                readonly property bool isPlay: modelData.a === "play"
                                implicitWidth: isPlay ? 40 : 32
                                implicitHeight: implicitWidth
                                radius: implicitWidth / 2
                                color: isPlay ? app.cBlue : mHov.hovered ? app.cCard : "transparent"
                                HoverHandler { id: mHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: mBtn.isPlay
                                        ? (app.player?.playbackState === MprisPlaybackState.Playing
                                            ? "pause" : "play_arrow")
                                        : mBtn.modelData.g
                                    color: mBtn.isPlay ? app.cOnAccent : app.cFg
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(mBtn.isPlay ? 18 : 15)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = app.player
                                        if (!p) return
                                        if (mBtn.modelData.a === "prev") p.previous()
                                        else if (mBtn.modelData.a === "next") p.next()
                                        else if (p.canTogglePlaying) p.togglePlaying()
                                    }
                                }
                            }
                        }
                    }
                }

                // ================= TABS =================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 20
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Repeater {
                            model: [
                                { t: "Calendar",  i: 0 },
                                { t: "Clipboard", i: 1 }
                            ]
                            delegate: Rectangle {
                                id: tabItem
                                required property var modelData
                                readonly property bool on: app.sideTab === modelData.i
                                readonly property int badge: modelData.i === 0 ? app.notifCount : 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 16
                                color: on ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                     : tabHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                                     : "transparent"
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                                HoverHandler { id: tabHov }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabItem.modelData.t
                                        color: tabItem.on ? app.cFg : app.cDim
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        font.bold: tabItem.on
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: tabItem.badge > 0
                                        implicitWidth: Math.max(18, bT.implicitWidth + 10)
                                        implicitHeight: 18
                                        radius: 9
                                        color: app.cBlue
                                        Text {
                                            id: bT
                                            anchors.centerIn: parent
                                            text: tabItem.badge
                                            color: app.cOnAccent
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(10)
                                            font.bold: true
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        app.sideTab = tabItem.modelData.i
                                        if (app.sideTab === 1) clipSearch.forceActiveFocus()
                                        else keys.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                // the tab's content fills whatever height is left
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ---------- calendar, with notifications below ----------
                    ColumnLayout {
                        anchors.fill: parent
                        visible: app.sideTab === 0
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            RoundBtn {
                                app: rootV.app
                                size: 32
                                glyph: "expand_more"
                                onClicked: app.monthOffset--
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Qt.formatDateTime(app.calBase, "MMMM yyyy")
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(15)
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.monthOffset = 0
                                }
                            }
                            Item { Layout.fillWidth: true }
                            RoundBtn {
                                app: rootV.app
                                size: 32
                                glyph: "chevron_right"
                                onClicked: app.monthOffset++
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 4
                            columnSpacing: 4

                            // weekday letters, starting on Sunday or Monday
                            Repeater {
                                model: 7
                                delegate: Text {
                                    required property int index
                                    readonly property int dow: (index + app.calWeekStart) % 7
                                    Layout.fillWidth: true
                                    text: ["S", "M", "T", "W", "T", "F", "S"][dow]
                                    color: (dow === 0 || dow === 6) ? app.cPeach : app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            Repeater {
                                model: app.calCells
                                delegate: Rectangle {
                                    id: dayCell
                                    required property var modelData
                                    readonly property bool sel: app.selectedKey === modelData.key
                                    readonly property bool marked: app.markedDays.indexOf(modelData.key) !== -1
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    // holidays get a soft tint behind the number
                                    readonly property bool isHol: modelData.hol !== ""
                                    color: modelData.today ? app.cBlue
                                         : sel ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                         : dHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                                         : isHol ? Qt.rgba(app.cPeach.r, app.cPeach.g, app.cPeach.b,
                                                           modelData.cur ? 0.18 : 0.08)
                                         : "transparent"
                                    border.width: sel && !modelData.today ? 1 : 0
                                    border.color: app.cBlue
                                    Behavior on color { ColorAnimation { duration: app.animQuick } }
                                    HoverHandler { id: dHov }
                                    Text {
                                        anchors.centerIn: parent
                                        text: dayCell.modelData.d
                                        color: dayCell.modelData.today ? app.cOnAccent
                                             : !dayCell.modelData.cur ? app.cFaint
                                             : dayCell.isHol ? app.cPeach : app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(13)
                                        font.bold: dayCell.modelData.today
                                    }
                                    // dots under the number: a note (blue), a mark (peach)
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                        spacing: 3
                                        Rectangle {
                                            visible: dayCell.modelData.noted
                                            width: 5; height: 5; radius: 2.5
                                            color: dayCell.modelData.today ? app.cOnAccent : app.cBlue
                                        }
                                        Rectangle {
                                            visible: dayCell.marked
                                            width: 5; height: 5; radius: 2.5
                                            color: dayCell.modelData.today ? app.cOnAccent : app.cPeach
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.dayClicked(dayCell.modelData.key)
                                    }
                                }
                            }
                        }

                        // today's holiday, when nothing is selected
                        Text {
                            Layout.fillWidth: true
                            readonly property string todayKey: Qt.formatDate(app.now, "yyyy-MM-dd")
                            visible: app.selectedKey === "" && app.holidayOn(todayKey) !== ""
                            text: "Today is " + app.holidayOn(todayKey)
                            color: app.cPeach
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // the selected day: holiday, notes, add a note, mark
                        Rectangle {
                            id: dayCard
                            Layout.fillWidth: true
                            visible: app.selectedKey !== ""
                            readonly property string key: app.selectedKey
                            readonly property string hol: key !== "" ? app.holidayOn(key) : ""
                            readonly property var notes: key !== "" ? app.notesOn(key) : []
                            readonly property bool isMarked: app.markedDays.indexOf(key) !== -1
                            property bool yearly: false
                            implicitHeight: dcCol.implicitHeight + 24
                            radius: 16
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

                            onKeyChanged: { noteIn.text = ""; yearly = false }

                            ColumnLayout {
                                id: dcCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: dayCard.key !== ""
                                              ? Qt.formatDate(new Date(dayCard.key + "T12:00:00"), "dddd d MMMM yyyy") : ""
                                        color: app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(13)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // mark / unmark the day
                                    Text {
                                        text: dayCard.isMarked ? "star" : "star"
                                        color: dayCard.isMarked ? app.cPeach : mkHov.hovered ? app.cFg : app.cFaint
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(16)
                                        HoverHandler { id: mkHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: app.toggleMark(dayCard.key)
                                        }
                                    }
                                }

                                // a holiday: its icon, then its name
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: dayCard.hol !== ""
                                    spacing: 6
                                    Text {
                                        Layout.alignment: Qt.AlignTop
                                        text: "celebration"
                                        color: app.cPeach
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(14)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: dayCard.hol
                                        color: app.cPeach
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                // notes on this day
                                Repeater {
                                    model: dayCard.notes
                                    delegate: RowLayout {
                                        id: noteRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.alignment: Qt.AlignTop
                                            text: noteRow.modelData.yearly ? "event_repeat" : "edit_note"
                                            color: app.cBlue
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(13)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: noteRow.modelData.text
                                                  + (noteRow.modelData.yearly ? "  (every year)" : "")
                                            color: app.cFg
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(12)
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignTop
                                            text: "close"
                                            color: ndHov.hovered ? app.cRed : app.cFaint
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(13)
                                            HoverHandler { id: ndHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: app.deleteDayNote(dayCard.key, noteRow.modelData.yearly)
                                            }
                                        }
                                    }
                                }

                                // add a note
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 6

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: 16
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                        border.width: noteIn.activeFocus ? 1 : 0
                                        border.color: app.cBlue
                                        TextInput {
                                            id: noteIn
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: app.cFg
                                            selectionColor: app.cBlue
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(12)
                                            clip: true
                                            onAccepted: {
                                                app.setDayNote(dayCard.key, text, dayCard.yearly)
                                                text = ""
                                            }
                                            Keys.onEscapePressed: {
                                                if (text !== "") text = ""
                                                else keys.forceActiveFocus()
                                            }
                                            Text {
                                                visible: !noteIn.text
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Add a note, then Enter"
                                                color: app.cFaint
                                                font: noteIn.font
                                            }
                                        }
                                    }

                                    // repeat every year on this date
                                    Rectangle {
                                        implicitWidth: yrT.implicitWidth + 20
                                        implicitHeight: 32
                                        radius: 16
                                        color: dayCard.yearly ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.26)
                                             : yrHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                                        border.width: dayCard.yearly ? 1 : 0
                                        border.color: app.cBlue
                                        HoverHandler { id: yrHov }
                                        Text {
                                            id: yrT
                                            anchors.centerIn: parent
                                            text: "Every year"
                                            color: dayCard.yearly ? app.cFg : app.cDim
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(11)
                                            font.bold: dayCard.yearly
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dayCard.yearly = !dayCard.yearly
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 2
                            implicitHeight: 1
                            color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            spacing: 8
                            Text {
                                text: "Notifications"
                                color: app.cFg
                                font.family: "Inter"
                                font.pixelSize: app.fs(13)
                                font.bold: true
                            }
                            Rectangle {
                                visible: app.notifCount > 0
                                implicitWidth: Math.max(18, ncT.implicitWidth + 10)
                                implicitHeight: 18
                                radius: 9
                                color: app.cBlue
                                Text {
                                    id: ncT
                                    anchors.centerIn: parent
                                    text: app.notifCount
                                    color: app.cOnAccent
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(10)
                                    font.bold: true
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: app.notifCount > 0
                                text: "Clear all"
                                color: clrHov.hovered ? app.cRed : app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                font.bold: true
                                HoverHandler { id: clrHov }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.clearNotifs()
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: app.notifCount > 0
                            clip: true
                            spacing: 6
                            boundsBehavior: Flickable.StopAtBounds
                            model: app.notifList

                            delegate: Rectangle {
                                id: nItem
                                required property var modelData
                                readonly property bool hasDefault:
                                    (modelData.actions || []).some(a => a.key === "default")
                                width: ListView.view.width
                                implicitHeight: nRow.implicitHeight + 24
                                radius: 16
                                color: nHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                                border.width: modelData.urgency >= 2 ? 1 : 0
                                border.color: app.cRed
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                                HoverHandler { id: nHov }

                                // clicking does what the app asked for on click
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: nItem.hasDefault ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (nItem.hasDefault) {
                                        app.invokeNotifAction(nItem.modelData.id, "default")
                                        app.sidebarShown = false
                                    }
                                }

                                RowLayout {
                                    id: nRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        radius: 10
                                        color: app.cCard
                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 20
                                            source: app.notifIcon(nItem.modelData)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: nItem.modelData.app
                                                color: app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(10)
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: !nHov.hovered
                                                text: nItem.modelData.when
                                                color: app.cFaint
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(10)
                                            }
                                            Text {
                                                visible: nHov.hovered
                                                text: "close"
                                                color: nxHov.hovered ? app.cRed : app.cDim
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(13)
                                                HoverHandler { id: nxHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -6
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: app.dismissNotif(nItem.modelData.id)
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: nItem.modelData.summary
                                            color: app.cFg
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(12)
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: nItem.modelData.body
                                            color: app.cDim
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(11)
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
                        }

                        // empty state
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: app.notifCount === 0
                            spacing: 6
                            Item { Layout.fillHeight: true }
                            // each line fills the width and centres its own
                            // text: a column only stretches if a child does
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: app.dnd ? "notifications_off" : "notifications"
                                color: app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(34)
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: "You're all caught up"
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(14)
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: app.dnd
                                text: "Do not disturb is on, so new ones won't pop up"
                                color: app.cFaint
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                                wrapMode: Text.WordWrap
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    // ---------- clipboard ----------
                    ColumnLayout {
                        id: clipTab
                        anchors.fill: parent
                        visible: app.sideTab === 1
                        spacing: 8

                        readonly property var shown: {
                            const q = clipSearch.text.trim().toLowerCase()
                            return q === "" ? app.clipItems
                                 : app.clipItems.filter(c => c.preview.toLowerCase().indexOf(q) !== -1)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: 18
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                border.width: clipSearch.activeFocus ? 1 : 0
                                border.color: app.cBlue

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8
                                    Text {
                                        text: "search"
                                        color: app.cFaint
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(14)
                                    }
                                    TextInput {
                                        id: clipSearch
                                        Layout.fillWidth: true
                                        color: app.cFg
                                        selectionColor: app.cBlue
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        clip: true
                                        Keys.onEscapePressed: {
                                            if (text !== "") text = ""
                                            else app.sidebarShown = false
                                        }
                                        // Enter copies the first match
                                        onAccepted: if (clipTab.shown.length) app.clipCopy(clipTab.shown[0].id)
                                        Text {
                                            visible: !clipSearch.text
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Search " + app.clipItems.length + " items"
                                            color: app.cFaint
                                            font: clipSearch.font
                                        }
                                    }
                                }
                            }

                            // wipe everything: the first click arms it
                            Rectangle {
                                id: wipeBtn
                                property bool armed: false
                                implicitWidth: armed ? wipeT.implicitWidth + 24 : 36
                                implicitHeight: 36
                                radius: 18
                                color: armed ? app.cRed
                                     : wHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
                                     : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
                                Behavior on implicitWidth { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                HoverHandler { id: wHov }
                                Text {
                                    id: wipeT
                                    anchors.centerIn: parent
                                    text: wipeBtn.armed ? "Clear all?" : "delete"
                                    color: wipeBtn.armed ? app.cOnAccent : app.cDim
                                    font.family: wipeBtn.armed ? "Inter" : "Material Symbols Rounded"
                                    font.pixelSize: app.fs(wipeBtn.armed ? 11 : 15)
                                    font.bold: wipeBtn.armed
                                }
                                Timer {
                                    id: wipeDisarm
                                    interval: 3000
                                    onTriggered: wipeBtn.armed = false
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (wipeBtn.armed) { app.clipWipe(); wipeBtn.armed = false }
                                        else { wipeBtn.armed = true; wipeDisarm.restart() }
                                    }
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: clipTab.shown.length > 0
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: clipTab.shown

                            delegate: Rectangle {
                                id: cItem
                                required property var modelData
                                // cliphist lists images as "[[ binary data 123 KiB png 1920x1080 ]]"
                                readonly property var bin:
                                    /^\[\[ binary data (.+?) (\w+) (\d+x\d+) \]\]/.exec(modelData.preview)
                                width: ListView.view.width
                                implicitHeight: cRow.implicitHeight + 18
                                radius: 12
                                color: cHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                                HoverHandler { id: cHov }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.clipCopy(cItem.modelData.id)
                                }

                                RowLayout {
                                    id: cRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Text {
                                        visible: cItem.bin !== null
                                        text: "wallpaper"
                                        color: app.cTeal
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(15)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: cItem.bin
                                              ? "Image, " + cItem.bin[2].toUpperCase() + " "
                                                + cItem.bin[3].replace("x", "\u00d7") + ", " + cItem.bin[1]
                                              : cItem.modelData.preview
                                        color: app.cFg
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(12)
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        opacity: cHov.hovered ? 1 : 0
                                        text: "close"
                                        color: cxHov.hovered ? app.cRed : app.cDim
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(13)
                                        HoverHandler { id: cxHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: app.clipDelete(cItem.modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: clipTab.shown.length === 0
                            text: app.clipItems.length === 0 ? "Nothing copied yet" : "No matches"
                            color: app.cFaint
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                }
            }
        }
    }
}
