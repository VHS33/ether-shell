import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common.widgets
import qs.common
import qs.services

// Theme Studio: the palette from your wallpaper, shown before it's used, and
// yours to adjust.  Pick any of the three accents from the colours found in
// the picture, make the accents stronger or softer, and the backgrounds more
// or less tinted; the preview follows as you go, and Apply themes everything
// with it.  Picks belong to the wallpaper they were made for (another
// wallpaper's colours are different); strength and tint apply to all.
ColumnLayout {
    id: studio
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 26
    readonly property int pageNo: 26
    spacing: 4

    readonly property var nat: Wallpaper.nativeItem
    readonly property string wall: app.currentWall || ""
    // ready once the plugin has read this wallpaper
    readonly property bool ready: Theme.pictureOn && nat !== null && Wallpaper.wallMeasuredFor === wall && wall !== ""

    // what's being tried; saved only on Apply
    property var draft: ({ main: "", second: "", third: "", base: "", strength: 1, tint: 1, border: "single", borderColour: "" })
    // what's saved for this wallpaper, as text (to tell whether the draft differs)
    property string savedJson: ""
    function load() {
        const s = Theme.studioFor(wall)
        savedJson = JSON.stringify(s)
        draft = s
    }
    function set(k, v) { const d = Object.assign({}, draft); d[k] = v; draft = d }
    onVisibleChanged: if (visible) load()
    onWallChanged: load()
    Component.onCompleted: load()
    // reloaded when the settings change under it (another window, a sync)
    Connections {
        target: Config
        function onSettingChanged(key) {
            if (key === "*" || key.indexOf("studio") === 0) studio.savedJson = JSON.stringify(Theme.studioFor(studio.wall))
        }
    }

    readonly property bool dirty: JSON.stringify(draft) !== savedJson
    readonly property bool automatic: draft.main === "" && draft.second === "" && draft.third === "" && draft.base === ""
                                      && draft.borderColour === ""
                                      && Math.abs(draft.strength - 1) < 0.001 && Math.abs(draft.tint - 1) < 0.001

    // the colours found in the picture, and the palette as it would come out
    readonly property var colours: ready ? nat.wallColours() : []
    readonly property var pal: ready ? nat.wallPalette(!app.isLight, app.themeContrast, draft) : ({})
    function pc(k, fallback) { return pal && pal[k] ? pal[k] : fallback }
    // what Auto gives for one choice, the others as they are
    function autoFor(k, role) {
        if (!ready) return "transparent"
        const d = Object.assign({}, draft); d[k] = ""
        const p = nat.wallPalette(!app.isLight, app.themeContrast, d)
        return p && p[role] ? p[role] : "transparent"
    }

    function apply() {
        const all = Object.assign({}, (typeof app.cfg.studioPicks === "object" && app.cfg.studioPicks) || {})
        if (draft.main || draft.second || draft.third || draft.base)
            all[wall] = { main: draft.main, second: draft.second, third: draft.third, base: draft.base }
        else
            delete all[wall]
        app.setting("studioPicks", all)
        app.setting("studioStrength", Math.round(draft.strength * 100) / 100)
        app.setting("studioTint", Math.round(draft.tint * 100) / 100)
        app.setting("studioBorder", draft.border === "gradient" ? "gradient" : "single")
        app.setting("studioBorderColour", draft.borderColour || "")
    }
    // the active window's border, as it would come out
    readonly property color borderStart: draft.borderColour !== "" ? draft.borderColour : pc("vivid_value", app.cBlue)
    readonly property color borderEnd: draft.border === "gradient" ? pc("third_value", app.cGreen) : borderStart

    SectionLabel { app: settingsRoot.app; text: "Preview" }

    Card {
        app: settingsRoot.app
        searchable: false
        visible: !studio.ready
        title: !Theme.pictureOn ? "Theme Studio works with the palette from the picture"
             : studio.wall === "" ? "No wallpaper yet" : "Reading the wallpaper…"
        desc: !Theme.pictureOn
              ? "It adjusts Ether Shell's own palette from your wallpaper. Turn on Palette: From the picture (and the Smart colour source) in Theme."
              : studio.wall === "" ? "Pick a wallpaper first; its colours show up here." : "A moment while its colours are found."
        trailing: [
            Seg {
                app: settingsRoot.app
                visible: !Theme.pictureOn
                options: ["Turn it on"]
                current: -1
                onPicked: { app.setting("themePalette", "picture"); app.setting("themePrefer", "smart") }
            }
        ]
    }

    // the wallpaper with a bar in the palette being tried, and its colours
    Card {
        app: settingsRoot.app
        searchable: false
        visible: studio.ready
        title: studio.dirty ? "Not applied yet" : studio.automatic ? "As Ether Shell picked it" : "Your adjusted palette"
        desc: studio.dirty ? "This is how it will look. Apply (below) to use it everywhere." : ""

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 9 / 16
            radius: app.rr(12)
            color: studio.pc("surface", "#111111")
            clip: true
            Image {
                anchors.fill: parent
                source: app.currentStill ? "file://" + app.currentStill : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 640
            }
            // the bar
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                height: 34
                radius: app.rrPill(17)
                color: studio.pc("surface", "#111111")
                opacity: 0.94
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 18; radius: app.rrPill(9)
                        color: studio.pc("vivid_value", app.cBlue)
                        Text {
                            anchors.centerIn: parent
                            text: "1"
                            color: studio.pc("on_vivid_value", "#000000")
                            font.family: app.uiFont
                            font.pixelSize: app.fs(11)
                            font.bold: true
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "2  3  4"
                        color: studio.pc("on_surface_variant", app.cDim)
                        font.family: app.uiFont
                        font.pixelSize: app.fs(12)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: statRow.implicitWidth + 18; height: 24; radius: app.rrPill(12)
                        color: studio.pc("surface_container_high", "#222222")
                        Row {
                            id: statRow
                            anchors.centerIn: parent
                            spacing: 10
                            Text { text: "CPU 12%"; color: studio.pc("vivid_value", app.cBlue); font.family: app.uiFont; font.pixelSize: app.fs(12) }
                            Text { text: "MEM 40%"; color: studio.pc("second_value", app.cPeach); font.family: app.uiFont; font.pixelSize: app.fs(12) }
                            Text { text: "GPU 7%"; color: studio.pc("third_value", app.cGreen); font.family: app.uiFont; font.pixelSize: app.fs(12) }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: clockT.implicitWidth + 20; height: 24; radius: app.rrPill(12)
                    color: studio.pc("surface_container_high", "#222222")
                    Text {
                        id: clockT
                        anchors.centerIn: parent
                        text: Qt.formatTime(app.now, app.cfg.clock24h === true ? "HH:mm" : "h:mm AP")
                        color: studio.pc("on_surface", app.cFg)
                        font.family: app.uiFont
                        font.pixelSize: app.fs(12)
                    }
                }
            }
            // the active window's border (one colour, or a gradient), round
            // a card as an app would draw it
            Rectangle {
                anchors.fill: winCard
                anchors.margins: -2
                radius: winCard.radius + 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(studio.borderStart.r, studio.borderStart.g, studio.borderStart.b, 0.6) }
                    GradientStop { position: 1; color: Qt.rgba(studio.borderEnd.r, studio.borderEnd.g, studio.borderEnd.b, 0.6) }
                }
            }
            Rectangle {
                id: winCard
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                width: Math.min(parent.width * 0.42, 230)
                height: cardCol.implicitHeight + 24
                radius: app.rr(14)
                color: studio.pc("surface_container", "#1a1a1a")
                Column {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 6
                    Text { text: "A window"; color: studio.pc("on_surface", app.cFg); font.family: app.uiFont; font.pixelSize: app.fs(13); font.bold: true }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: "Text, and the softer text under it."; color: studio.pc("on_surface_variant", app.cDim); font.family: app.uiFont; font.pixelSize: app.fs(11) }
                    Row {
                        spacing: 6
                        Rectangle {
                            width: okT.implicitWidth + 20; height: 24; radius: app.rrPill(12)
                            color: studio.pc("vivid_value", app.cBlue)
                            Text { id: okT; anchors.centerIn: parent; text: "Button"; color: studio.pc("on_vivid_value", "#000"); font.family: app.uiFont; font.pixelSize: app.fs(11); font.bold: true }
                        }
                        Rectangle {
                            width: tagT.implicitWidth + 16; height: 24; radius: app.rrPill(12)
                            color: studio.pc("secondary_container", "#333")
                            Text { id: tagT; anchors.centerIn: parent; text: "Tag"; color: studio.pc("on_secondary_container", app.cFg); font.family: app.uiFont; font.pixelSize: app.fs(11) }
                        }
                    }
                }
            }
        }

        // the palette, as swatches
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { k: "surface", t: "Background" }, { k: "surface_container_high", t: "Raised" },
                    { k: "on_surface", t: "Text" }, { k: "vivid_value", t: "Main" },
                    { k: "second_value", t: "Second" }, { k: "third_value", t: "Third" }
                ]
                delegate: Column {
                    required property var modelData
                    spacing: 4
                    Rectangle {
                        width: 58; height: 30; radius: app.rr(8)
                        color: studio.pc(modelData.k, "transparent")
                        border.width: 1
                        border.color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.18)
                    }
                    Text {
                        text: modelData.t
                        color: app.cDim
                        font.family: app.uiFont
                        font.pixelSize: app.fs(10)
                    }
                }
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Accents"; visible: studio.ready }

    // one card per accent: Auto, or any colour found in the picture
    Repeater {
        model: [
            { k: "main",   p: "vivid_value",  t: "Main colour",   d: "The active workspace, buttons, highlights and window borders." },
            { k: "second", p: "second_value", t: "Second colour", d: "Graph lines, links, and the apps' second accent." },
            { k: "third",  p: "third_value",  t: "Third colour",  d: "The third graph line, and the apps' third accent." }
        ]
        delegate: Card {
            id: slotCard
            required property var modelData
            app: settingsRoot.app
            visible: studio.ready
            title: modelData.t
            desc: modelData.d + " Any colour you pick is kept readable."
            trailing: [
                Rectangle {
                    width: 34; height: 34; radius: app.rr(17)
                    color: studio.pc(slotCard.modelData.p, "transparent")
                    border.width: 1
                    border.color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.25)
                }
            ]
            StudioColourRow {
                Layout.fillWidth: true
                app: settingsRoot.app
                value: studio.draft[slotCard.modelData.k]
                colours: studio.colours
                autoColour: studio.autoFor(slotCard.modelData.k, slotCard.modelData.p)
                onPicked: v => studio.set(slotCard.modelData.k, v)
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Feel"; visible: studio.ready }

    Card {
        app: settingsRoot.app
        visible: studio.ready
        title: "Accent strength"
        desc: "Softer or stronger accents than the picture's own. They're always kept readable. For every wallpaper."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.5
                to: 1.6
                origin: 1
                tick: 1
                step: 0.05
                value: studio.draft.strength
                label: Math.abs(value - 1) < 0.01 ? "As found" : Math.round(value * 100) + "%"
                onMoved: v => studio.set("strength", Math.round(v * 20) / 20)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        visible: studio.ready
        title: "Background colour"
        desc: "The tone the backgrounds, panels and text take on. Auto is the picture's own backdrop. Kept dark (or light) whatever you pick; Background tint sets how strongly."
        trailing: [
            Rectangle {
                width: 34; height: 34; radius: app.rr(17)
                color: studio.pc("surface_container_highest", "transparent")
                border.width: 1
                border.color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.25)
            }
        ]
        StudioColourRow {
            Layout.fillWidth: true
            app: settingsRoot.app
            value: studio.draft.base
            colours: studio.colours
            autoColour: studio.autoFor("base", "surface_variant")
            onPicked: v => studio.set("base", v)
        }
    }

    Card {
        app: settingsRoot.app
        visible: studio.ready
        title: "Background tint"
        desc: "How much the backgrounds take on the picture's tone: none (neutral grey) to stronger than found. For every wallpaper."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 2.5
                origin: 1
                tick: 1
                step: 0.1
                value: studio.draft.tint
                label: value < 0.05 ? "Neutral" : Math.abs(value - 1) < 0.05 ? "As found" : Math.round(value * 100) + "%"
                onMoved: v => studio.set("tint", Math.round(v * 10) / 10)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Window borders" }

    Card {
        app: settingsRoot.app
        title: "Active window border"
        desc: studio.draft.border === "gradient"
              ? "A gradient from the colour below into the third colour."
              : "One colour all the way round. Auto is the main colour; or pick your own. For every wallpaper."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["One colour", "Gradient"]
                current: studio.draft.border === "gradient" ? 1 : 0
                onPicked: i => studio.set("border", i === 1 ? "gradient" : "single")
            }
        ]
        StudioColourRow {
            Layout.fillWidth: true
            app: settingsRoot.app
            value: studio.draft.borderColour
            colours: studio.colours
            autoColour: studio.pc("vivid_value", app.cBlue)
            onPicked: v => studio.set("borderColour", v)
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Use it" }

    Card {
        app: settingsRoot.app
        title: "Apply"
        desc: studio.dirty ? "Themes the shell, terminal, launcher, borders and apps with the palette above."
                             : "The palette above is the one in use."
        trailing: [
            Seg {
                app: settingsRoot.app
                visible: studio.dirty
                options: ["Undo changes"]
                current: -1
                onPicked: studio.load()
            },
            Seg {
                app: settingsRoot.app
                options: ["Apply"]
                current: studio.dirty ? 0 : -1
                opacity: studio.dirty ? 1 : 0.45
                onPicked: if (studio.dirty) studio.apply()
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Back to automatic"
        desc: "Forgets the colours picked for this wallpaper, sets strength and tint back to as found, and the window border back to one colour, the main one."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Reset"]
                current: -1
                opacity: studio.automatic && !studio.dirty ? 0.45 : 1
                onPicked: { studio.draft = { main: "", second: "", third: "", base: "", strength: 1, tint: 1, border: "single", borderColour: "" }; studio.apply() }
            }
        ]
    }
}
