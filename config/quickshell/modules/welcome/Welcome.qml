import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.common.widgets
import qs.services
import "../../lib/screens.mjs" as ScreensLib
import qs.modules.settings

// ============================================================
//   WELCOME
//   A first-run setup: a few short pages over a dimmed desktop.
//   Shown by itself only on a new install (Config saw no settings
//   file, so welcomeDone was saved as false); any time after, from
//   the launcher (>welcome), `ether welcome` or Settings > About.
//   Every page can be skipped, and nothing changes until you pick
//   something; each choice uses the same calls as Settings.
//   Which page it's on is kept on app, so it carries on if the bar
//   (and this) moves to another screen.
// ============================================================
Variants {
    id: welcomeRoot
    property var app
    model: Quickshell.screens

    LazyLoader {
        id: perScreen
        required property var modelData
        active: modelData.name === app.mainScreen && app.welcomeShown

    PanelWindow {
        id: win
        readonly property var modelData: perScreen.modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        // (it covers the screen until finished or skipped, so it keeps the keys)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // ---- the screens: Hyprland's list (with names and refresh rates),
        // or Quickshell's own while that isn't in yet ----
        readonly property var mons: app.monInfo.length ? app.monInfo
            : Quickshell.screens.map(s => ({ name: s.name, desc: s.model && s.model !== "Unknown" ? s.model : "", w: s.width, h: s.height, hz: 0 }))

        // ---- the pages (Screens only with more than one) ----
        readonly property var pages: {
            const p = ["hello", "look", "text"]
            if (mons.length > 1) p.push("screens")
            p.push("weather", "where", "keys", "done")
            return p
        }
        readonly property int at: Math.max(0, Math.min(app.welcomePage, pages.length - 1))
        readonly property string page: pages[at]
        // (the keys back to the window first: the city box would keep them
        // on the next page; the Weather page takes them again as it opens)
        // (moving on while a screen change is waiting: it works, as you could
        // see to press it, so it's kept)
        function go(d) {
            keys.forceActiveFocus()
            if (app.revertLeft > 0) app.keepDisplays()
            app.welcomePage = Math.max(0, Math.min(pages.length - 1, at + d))
        }
        // done, or skipped: it won't show by itself again
        function finish(thenSettings) {
            app.setting("welcomeDone", true)
            app.welcomeShown = false
            app.welcomePage = 0
            if (thenSettings) app.settingsShown = true
        }

        // (keys go to the card unless something in it, the city search,
        // has them)
        Component.onCompleted: keys.forceActiveFocus()
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) win.finish(false)
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Right) {
                    if (win.page === "done") win.finish(false); else win.go(1)
                } else if (e.key === Qt.Key_Left) win.go(-1)
                else return
                e.accepted = true
            }
        }

        Rectangle {
            anchors.fill: parent
            color: app.scrim(0.6)
            // (clicks outside the card do nothing: setup is closed with Skip)
            MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(780, win.width - 80)
            height: Math.min(600, win.height - 80)
            radius: 32
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)
            opacity: 0
            scale: 0.96
            Component.onCompleted: { opacity = 1; scale = 1 }
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 18

                // ---- where you are: a dot per page, and Skip ----
                RowLayout {
                    Layout.fillWidth: true
                    Row {
                        spacing: 6
                        Repeater {
                            model: win.pages.length
                            delegate: Rectangle {
                                required property int index
                                width: index === win.at ? 22 : 8
                                height: 8
                                radius: 4
                                color: index <= win.at ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.15)
                                Behavior on width { NumberAnimation { duration: app.animQuick } }
                                Behavior on color { ColorAnimation { duration: app.animQuick } }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: win.page !== "done"
                        text: "Skip setup"
                        color: skipHov.hovered ? app.cFg : app.cDim
                        font.family: Theme.uiFont
                        font.pixelSize: app.fs(12)
                        HoverHandler { id: skipHov }
                        MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.finish(false) }
                    }
                }

                // ---- the page ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // -- hello --
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: win.page === "hello"
                        spacing: 14
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 76; implicitHeight: 76; radius: 24
                            color: app.cBlue
                            Text {
                                anchors.centerIn: parent
                                text: "auto_awesome"
                                color: app.cOnAccent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(36)
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Welcome to Ether Shell"
                            color: app.cFg
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(28)
                            font.bold: true
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 520
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "A minute of setup: your wallpaper and colours, your text and cursor, your screens and your weather, then where things are and the keys to know. Everything here can be changed later in Settings."
                            color: app.cDim
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(14)
                        }
                    }

                    // -- your look --
                    ColumnLayout {
                        anchors.fill: parent
                        visible: win.page === "look"
                        spacing: 12
                        WelcomeHeading { app: welcomeRoot.app; title: "Your look"; sub: "Pick a wallpaper: the whole desktop takes its colours from it." }
                        Flickable {
                            id: wallFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: wallGrid.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Grid {
                                id: wallGrid
                                width: wallFlick.width
                                columns: 4
                                spacing: 10
                                readonly property real cellW: (width - spacing * (columns - 1)) / columns
                                Repeater {
                                    model: app.wallpapers
                                    delegate: Rectangle {
                                        id: thumb
                                        required property var modelData
                                        readonly property bool isCurrent: modelData === app.currentWall
                                        width: wallGrid.cellW
                                        height: width * 9 / 16
                                        radius: 12
                                        clip: true
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                        border.width: isCurrent ? 3 : thHov.hovered ? 2 : 0
                                        border.color: isCurrent ? app.cBlue : app.cFg
                                        HoverHandler { id: thHov }
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: thumb.border.width
                                            source: "file://" + thumb.modelData
                                            sourceSize.width: 320
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: thumb.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: if (!thumb.isCurrent) app.applyWallpaper(thumb.modelData)
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: app.wallpapers.length === 0
                            text: "No wallpapers in ~/Pictures/wallpapers yet: add some there, then pick one in Settings, Wallpaper."
                            color: app.cDim
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(12)
                        }
                        RowLayout {
                            spacing: 14
                            Text {
                                text: "Light or dark"
                                color: app.cFg
                                font.family: Theme.uiFont
                                font.pixelSize: app.fs(13)
                                font.bold: true
                            }
                            Seg {
                                app: welcomeRoot.app
                                options: ["Dark", "Light", "Automatic"]
                                current: ["dark", "light", "auto"].indexOf(app.cfg.themeMode || "dark")
                                onPicked: i => app.setting("themeMode", ["dark", "light", "auto"][i])
                            }
                        }
                        Text {
                            text: "Automatic picks light or dark to suit each wallpaper."
                            color: app.cFaint
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(11)
                        }
                    }

                    // -- text and cursor: Settings' own pickers (FontPicker,
                    // CursorPicker), and the same settings --
                    ColumnLayout {
                        anchors.fill: parent
                        visible: win.page === "text"
                        spacing: 10
                        onVisibleChanged: if (visible) { Fonts.refresh(); Cursors.refresh() }
                        WelcomeHeading { app: welcomeRoot.app; title: "Text and cursor"; sub: "The font across the shell and your apps, how big text is, and your mouse pointer." }
                        Flickable {
                            id: textFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: textCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: textCol
                                width: textFlick.width
                                spacing: 12
                                Text {
                                    text: "Font"
                                    color: app.cFg
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(13)
                                    font.bold: true
                                }
                                FontPicker {
                                    app: welcomeRoot.app
                                    picks: Fonts.picksText
                                    all: Fonts.all
                                    current: Fonts.text
                                    sample: "Aa"
                                    onPicked: f => Fonts.setText(f)
                                }
                                ChoiceLine {
                                    app: welcomeRoot.app
                                    label: "Text size"
                                    choices: [0.9, 1, 1.1, 1.25].map(v => ({ k: v, t: Math.round(v * 100) + "%" }))
                                    current: app.cfg.fontScale ?? 1
                                    onPicked: k => app.setting("fontScale", k)
                                }
                                Text {
                                    Layout.topMargin: 6
                                    text: "Cursor"
                                    color: app.cFg
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(13)
                                    font.bold: true
                                }
                                CursorPicker { app: welcomeRoot.app }
                                ChoiceLine {
                                    app: welcomeRoot.app
                                    label: "Cursor size"
                                    choices: [{ k: 24, t: "Small" }, { k: 32, t: "Medium" }, { k: 40, t: "Large" }, { k: 48, t: "Huge" }]
                                    current: Cursors.size
                                    onPicked: k => Cursors.setSize(k)
                                }
                            }
                        }
                    }

                    // -- your screens: which gets the bar, each one's mode and
                    // scale, and where the other sits; applied with Settings'
                    // keep-or-undo countdown (Displays), so a screen that goes
                    // black comes back by itself --
                    ColumnLayout {
                        id: scr
                        anchors.fill: parent
                        visible: win.page === "screens"
                        spacing: 10
                        // what's chosen here, until Apply
                        property var draft: ({})
                        property var pos: ({})             // where each sits, dragged
                        property string selMon: ""
                        readonly property bool hasModes: app.monInfo.length > 0
                        function load() {
                            draft = ScreensLib.draftOf(app.monInfo)
                            pos = ScreensLib.positionsOf(app.monInfo)
                        }
                        onVisibleChanged: if (visible) { Displays.refreshMonitors(); load() }
                        // (also when the window is built on this page: giving
                        // another screen the bar moves the welcome there, afresh)
                        Component.onCompleted: if (visible) { Displays.refreshMonitors(); load() }
                        Connections { target: Displays; function onMonInfoChanged() { if (Displays.revertLeft === 0) scr.load() } }
                        readonly property bool dirty: hasModes && ScreensLib.changed(draft, app.monInfo, pos)
                        function apply() { app.applyDisplays(ScreensLib.toApply(draft, pos), "custom") }
                        // a new size (resolution, scale): the others settle around the main one
                        function change(d) { draft = d; pos = ScreensLib.settleAround(d, pos, app.mainScreen) }

                        WelcomeHeading { app: welcomeRoot.app; title: "Your screens"; sub: "Drag your screens to where they sit on your desk. Then pick each one's resolution, refresh rate and size, and which gets the bar." }
                        Flickable {
                            id: scrFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: scrCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: scrCol
                                width: scrFlick.width
                                spacing: 10
                                // where they sit: drag them (the same view as Settings, Displays)
                                MonitorLayout {
                                    visible: scr.hasModes && win.mons.length > 1
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 190
                                    app: welcomeRoot.app
                                    monitors: ScreensLib.tiles(scr.draft, scr.pos, app.mainScreen)
                                    selected: scr.selMon
                                    onMoved: (name, x, y) => scr.pos = ScreensLib.moved(scr.pos, name, x, y)
                                    onPicked: name => scr.selMon = name
                                }
                                Repeater {
                                    model: win.mons
                                    delegate: Rectangle {
                                        id: mon
                                        required property var modelData
                                        readonly property bool isMain: modelData.name === app.mainScreen
                                        readonly property var d: scr.draft[modelData.name] || null
                                        Layout.fillWidth: true
                                        implicitHeight: monCol.implicitHeight + 28
                                        radius: 18
                                        color: isMain ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.14) : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.05)
                                        border.width: isMain || modelData.name === scr.selMon ? 2 : 0
                                        border.color: isMain ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                        ColumnLayout {
                                            id: monCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                            spacing: 10
                                            // the screen, and whether it has the bar
                                            Item {
                                                Layout.fillWidth: true
                                                implicitHeight: 40
                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 12
                                                    Text {
                                                        text: "monitor"
                                                        color: mon.isMain ? app.cBlue : app.cDim
                                                        font.family: "Material Symbols Rounded"
                                                        font.pixelSize: app.fs(22)
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: mon.modelData.desc || mon.modelData.name
                                                            color: app.cFg
                                                            font.family: Theme.uiFont
                                                            font.pixelSize: app.fs(13)
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            text: mon.modelData.name + "  \u2022  " + mon.modelData.w + "\u00d7" + mon.modelData.h
                                                                  + (mon.modelData.hz > 0 ? " at " + Math.round(mon.modelData.hz) + " Hz" : "")
                                                                  + (mon.modelData.scale ? ", " + Math.round(mon.modelData.scale * 100) + "%" : "")
                                                            color: app.cDim
                                                            font.family: Theme.uiFont
                                                            font.pixelSize: app.fs(11)
                                                        }
                                                    }
                                                    Text {
                                                        text: mon.isMain ? "Gets the bar" : "Give it the bar"
                                                        color: mon.isMain ? app.cBlue : (barHov.hovered ? app.cFg : app.cDim)
                                                        font.family: Theme.uiFont
                                                        font.pixelSize: app.fs(12)
                                                        font.bold: mon.isMain
                                                        HoverHandler { id: barHov }
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: mon.isMain ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                    onClicked: if (!mon.isMain) app.setting("mainScreen", mon.modelData.name)
                                                }
                                            }
                                            // resolution, refresh rate, size (with Hyprland's list of modes)
                                            ChoiceLine {
                                                app: welcomeRoot.app
                                                visible: scr.hasModes && mon.d !== null
                                                label: "Resolution"
                                                choices: ScreensLib.resolutions(mon.modelData, 5).map(r => ({ k: r, t: r.replace("x", "\u00d7") }))
                                                current: mon.d ? mon.d.res : ""
                                                onPicked: k => scr.change(ScreensLib.withRes(scr.draft, mon.modelData.name, k, mon.modelData))
                                            }
                                            ChoiceLine {
                                                app: welcomeRoot.app
                                                visible: scr.hasModes && mon.d !== null
                                                label: "Refresh rate"
                                                choices: mon.d ? ScreensLib.rates(mon.modelData, mon.d.res).slice(0, 5).map(r => ({ k: r.mode, t: Math.round(r.hz) + " Hz" })) : []
                                                current: mon.d ? mon.d.mode : ""
                                                onPicked: k => scr.draft = ScreensLib.withField(scr.draft, mon.modelData.name, "mode", k)
                                            }
                                            ChoiceLine {
                                                app: welcomeRoot.app
                                                visible: scr.hasModes && mon.d !== null
                                                label: "Size"
                                                choices: [1, 1.25, 1.5, 1.75, 2].map(v => ({ k: v, t: Math.round(v * 100) + "%" }))
                                                current: mon.d ? mon.d.scale : 1
                                                onPicked: k => scr.change(ScreensLib.withField(scr.draft, mon.modelData.name, "scale", k))
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: !scr.hasModes
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Resolutions and refresh rates show once Hyprland lists your screens. They're also in Settings, Displays."
                                    color: app.cFaint
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(11)
                                }
                            }
                        }
                        // apply; the shell's own "Keep these display settings?"
                        // then shows (on every screen) and goes back by itself
                        // in 15 seconds unless kept
                        RowLayout {
                            Layout.fillWidth: true
                            visible: scr.dirty && app.revertLeft === 0
                            spacing: 10
                            Text {
                                Layout.fillWidth: true
                                text: "Not in use yet."
                                color: app.cDim
                                font.family: Theme.uiFont
                                font.pixelSize: app.fs(13)
                            }
                            WelcomeButton { app: welcomeRoot.app; primary: true; label: "Apply"; onClicked: scr.apply() }
                        }
                    }

                    // -- weather --
                    ColumnLayout {
                        anchors.fill: parent
                        visible: win.page === "weather"
                        // straight into the city box
                        onVisibleChanged: if (visible) city.forceActiveFocus()
                        spacing: 12
                        WelcomeHeading { app: welcomeRoot.app; title: "Weather"; sub: "For the forecast in the bar and the sidebar. Search your city, or skip this." }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 22
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                            border.width: city.activeFocus ? 1 : 0
                            border.color: app.cBlue
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 10
                                Text {
                                    text: Weather.wxSearching ? "progress_activity" : "search"
                                    color: app.cDim
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(18)
                                }
                                TextInput {
                                    id: city
                                    Layout.fillWidth: true
                                    color: app.cFg
                                    selectionColor: app.cBlue
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(14)
                                    clip: true
                                    onTextChanged: citySoon.restart()
                                    // Enter: the first place found; nothing typed, the next page
                                    onAccepted: {
                                        citySoon.stop()
                                        if (text.trim() === "") win.go(1)
                                        else if (Weather.wxResults.length) { Weather.setPlace(Weather.wxResults[0]); text = "" }
                                        else Weather.searchPlace(text)
                                    }
                                    Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }
                                    Text {
                                        visible: !city.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Your city"
                                        color: app.cFaint
                                        font: city.font
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: city.forceActiveFocus() }
                        }
                        // a pause in typing searches
                        Timer { id: citySoon; interval: 500; onTriggered: Weather.searchPlace(city.text) }
                        Repeater {
                            model: Weather.wxResults
                            delegate: Rectangle {
                                id: place
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 14
                                color: plHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.10) : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.04)
                                HoverHandler { id: plHov }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    Text {
                                        text: place.modelData.name
                                        color: app.cFg
                                        font.family: Theme.uiFont
                                        font.pixelSize: app.fs(13)
                                        font.bold: true
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: place.modelData.where
                                        color: app.cDim
                                        font.family: Theme.uiFont
                                        font.pixelSize: app.fs(12)
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { Weather.setPlace(place.modelData); city.text = ""; citySoon.stop(); keys.forceActiveFocus() }
                                }
                            }
                        }
                        RowLayout {
                            visible: Weather.wxResults.length === 0
                            spacing: 8
                            Text {
                                text: Weather.wxHasPlace ? "check_circle" : "location_off"
                                color: Weather.wxHasPlace ? app.cBlue : app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(16)
                            }
                            Text {
                                text: Weather.wxHasPlace ? "Forecast for " + Weather.wxPlace : "No place set yet"
                                color: Weather.wxHasPlace ? app.cFg : app.cFaint
                                font.family: Theme.uiFont
                                font.pixelSize: app.fs(13)
                            }
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            spacing: 14
                            Text {
                                text: "Temperatures in"
                                color: app.cFg
                                font.family: Theme.uiFont
                                font.pixelSize: app.fs(13)
                                font.bold: true
                            }
                            Seg {
                                app: welcomeRoot.app
                                options: ["°F", "°C"]
                                current: Weather.wxMetric ? 1 : 0
                                onPicked: i => app.setting("wxUnits", i === 1 ? "C" : "F")
                            }
                        }
                    }

                    // -- where things are, and the keys to know --
                    WelcomeWhere {
                        anchors.fill: parent
                        visible: win.page === "where"
                        app: welcomeRoot.app
                    }
                    WelcomeKeys {
                        anchors.fill: parent
                        visible: win.page === "keys"
                        app: welcomeRoot.app
                    }

                    // -- done --
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: win.page === "done"
                        spacing: 14
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 76; implicitHeight: 76; radius: 38
                            color: app.cBlue
                            Text {
                                anchors.centerIn: parent
                                text: "check"
                                color: app.cOnAccent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(38)
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "You're set"
                            color: app.cFg
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(28)
                            font.bold: true
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 520
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "Everything else is in Settings (SUPER + comma). To see this again, type >welcome in the launcher, or find it in Settings, About."
                            color: app.cDim
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(14)
                        }
                    }
                }

                // ---- back and next ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    WelcomeButton {
                        app: welcomeRoot.app
                        visible: win.at > 0
                        label: "Back"
                        onClicked: { win.go(-1); keys.forceActiveFocus() }
                    }
                    Item { Layout.fillWidth: true }
                    WelcomeButton {
                        app: welcomeRoot.app
                        visible: win.page === "done"
                        label: "Open Settings"
                        onClicked: win.finish(true)
                    }
                    WelcomeButton {
                        app: welcomeRoot.app
                        primary: true
                        label: win.page === "hello" ? "Start" : win.page === "done" ? "Start using it" : "Next"
                        onClicked: { if (win.page === "done") win.finish(false); else win.go(1); keys.forceActiveFocus() }
                    }
                }
            }
        }
    }
    }
}
