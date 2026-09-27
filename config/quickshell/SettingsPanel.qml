import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// ============================================================
//   SETTINGS
//   The shell's settings panel, laid out like a settings app:
//   navigation on the left, cards on the right.  Appearance pages
//   write settings.json through app.setting(); the Sound pages
//   drive PipeWire directly.
//
//   A layer surface, not a toplevel, so Hyprland never tiles or
//   snaps it — drag it by either header.  Close with the X, Esc,
//   or `qs ipc call settings toggle`.
//
//   Every audio list is a Repeater over Pipewire.nodes with the
//   filter applied as `visible`.  Nothing live is ever copied into
//   a JS array used as a model — that is what caused the segfaults.
//   count() builds a throwaway array for .length only.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // ---------------------------------------------------------
    //   building blocks
    // ---------------------------------------------------------

    // a titled card; children go in the body, `trailing` sits
    // at the right of the title row
    component Card: Rectangle {
        id: card
        property var app
        property string title: ""
        property string desc: ""
        default property alias body: bodyCol.data
        property alias trailing: trail.data

        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 34
        radius: 18
        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 17
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 18
                visible: card.title !== "" || trail.children.length > 0

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.title
                        color: card.app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(14)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.desc
                        color: card.app.cDim
                        font.family: "Inter"
                        font.pixelSize: app.fs(11)
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }
                }

                RowLayout { id: trail; spacing: 8 }
            }

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: 4
                visible: children.length > 0
            }
        }
    }

    // accent-coloured section heading between groups of cards
    component SectionLabel: Text {
        property var app
        Layout.topMargin: 14
        Layout.bottomMargin: 6
        Layout.leftMargin: 18
        color: app.cBlue
        font.family: "Inter"
        font.pixelSize: app.fs(12)
        font.bold: true
    }

    // one round − or + button for the stepper below
    component StepBtn: Rectangle {
        id: sb
        property var app
        property string glyph: ""
        property bool enabledBtn: true
        property color accent
        signal step()

        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: !enabledBtn ? "transparent"
             : sbMa.pressed ? Qt.rgba(accent.r, accent.g, accent.b, 0.35)
             : sbHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
        Behavior on color { ColorAnimation { duration: app.animQuick } }
        HoverHandler { id: sbHov }

        Text {
            anchors.centerIn: parent
            text: sb.glyph
            color: sb.enabledBtn ? sb.app.cFg : sb.app.cFaint
            opacity: sb.enabledBtn ? 1 : 0.5
            font.family: "Material Symbols Rounded"
            font.pixelSize: sb.app.fs(15)
        }

        // hold to repeat: a pause, then quick steps
        Timer {
            id: sbRepeat
            interval: 420
            repeat: true
            onTriggered: { interval = 70; if (sb.enabledBtn) sb.step() }
        }
        MouseArea {
            id: sbMa
            anchors.fill: parent
            enabled: sb.enabledBtn
            cursorShape: Qt.PointingHandCursor
            onPressed: { sb.step(); sbRepeat.interval = 420; sbRepeat.start() }
            onReleased: sbRepeat.stop()
            onCanceled: sbRepeat.stop()
        }
    }

    // − value + stepper.  Still called Slider so every page that uses
    // one keeps working unchanged: same from / to / step / value /
    // label, and `moved(v)` fires with the new value.  Holding a button
    // repeats; scrolling over it steps too.
    component Slider: RowLayout {
        id: sl
        property var app
        property real from: 0
        property real to: 1
        property real value: 0
        property real origin: from
        property real step: 0.02
        property real tick: -1
        property bool muted: false
        property color accent: app.cBlue
        property string label: ""
        signal moved(real v)

        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        spacing: 4

        // snap to the step grid so repeated presses land on round values
        function nudge(dir) {
            const n = Math.round((value - from) / step) + dir
            let v = from + n * step
            v = Math.max(from, Math.min(to, v))
            moved(Math.round(v * 10000) / 10000)
        }
        readonly property bool atMin: value <= from + step / 1000
        readonly property bool atMax: value >= to - step / 1000

        StepBtn {
            app: sl.app
            glyph: "remove"
            accent: sl.accent
            enabledBtn: !sl.atMin
            onStep: sl.nudge(-1)
        }

        Rectangle {
            implicitWidth: Math.max(72, slT.implicitWidth + 20)
            implicitHeight: 32
            radius: 16
            color: Qt.rgba(sl.accent.r, sl.accent.g, sl.accent.b, 0.14)
            Text {
                id: slT
                anchors.centerIn: parent
                text: sl.label
                color: sl.muted ? sl.app.cFaint : sl.app.cFg
                font.family: "Inter"
                font.pixelSize: sl.app.fs(12)
                font.bold: true
            }
            // scroll over the value to step
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: w => sl.nudge(w.angleDelta.y > 0 ? 1 : -1)
            }
        }

        StepBtn {
            app: sl.app
            glyph: "add"
            accent: sl.accent
            enabledBtn: !sl.atMax
            onStep: sl.nudge(1)
        }
    }

    // segmented pill choice; the selected option gets a check
    component Seg: Row {
        id: seg
        property var app
        property var options: []
        property int current: -1
        property color accent: app.cBlue
        signal picked(int i)
        spacing: 2

        Repeater {
            model: seg.options
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool on: index === seg.current

                readonly property bool first: index === 0
                readonly property bool last: index === seg.options.length - 1
                implicitWidth: Math.max(104, segT.implicitWidth + (on ? 52 : 34))
                implicitHeight: 34
                topLeftRadius: first ? 17 : 5
                bottomLeftRadius: first ? 17 : 5
                topRightRadius: last ? 17 : 5
                bottomRightRadius: last ? 17 : 5
                color: on ? Qt.rgba(seg.accent.r, seg.accent.g, seg.accent.b, 0.26)
                     : segHov.hovered ? Qt.rgba(seg.app.cFg.r, seg.app.cFg.g, seg.app.cFg.b, 0.12)
                     : Qt.rgba(seg.app.cFg.r, seg.app.cFg.g, seg.app.cFg.b, 0.09)
                Behavior on color { ColorAnimation { duration: app.animQuick } }

                HoverHandler { id: segHov }

                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        visible: parent.parent.on
                        text: "check"
                        color: seg.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(13)
                    }
                    Text {
                        id: segT
                        text: modelData
                        color: parent.parent.on ? seg.app.cFg : seg.app.cDim
                        font.family: "Inter"
                        font.pixelSize: app.fs(12)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(index)
                }
            }
        }
    }

    // small pill in a wrapping row of choices
    component Chip: Rectangle {
        id: chip
        property var app
        property string text: ""
        property bool selected: false
        signal picked()

        implicitWidth: chipT.implicitWidth + 26
        implicitHeight: 32
        radius: 16
        color: selected ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.26)
             : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
        border.width: selected ? 1 : 0
        border.color: app.cBlue
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: chipHov }

        Text {
            id: chipT
            anchors.centerIn: parent
            text: chip.text
            color: chip.selected ? chip.app.cFg : chip.app.cDim
            font.family: "Inter"
            font.pixelSize: app.fs(12)
            font.bold: chip.selected
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    // round icon button, lit when `active`
    component IconBtn: Rectangle {
        id: ib
        property var app
        property string glyph: ""
        property bool active: false
        property color accent: app.cBlue
        signal clicked()

        implicitWidth: 36
        implicitHeight: 36
        radius: 18
        color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.26)
             : ibHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12)
             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: ibHov }

        Text {
            anchors.centerIn: parent
            text: ib.glyph
            color: ib.active ? ib.accent : ib.app.cDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: app.fs(16)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // one option in a list of choices: title, a line of description,
    // and a check when selected
    component ChoiceRow: Rectangle {
        id: cr
        property var app
        property string title: ""
        property string desc: ""
        property bool selected: false
        property color accent: app.cBlue
        signal chosen()

        Layout.fillWidth: true
        implicitHeight: crCol.implicitHeight + 20
        radius: 14
        color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
             : crHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
             : "transparent"
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        HoverHandler { id: crHov }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            ColumnLayout {
                id: crCol
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: cr.title
                    color: cr.app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    font.bold: cr.selected
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: cr.desc
                    color: cr.app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: cr.selected
                text: "check"
                color: cr.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: app.fs(16)
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: cr.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!cr.selected) cr.chosen()
        }
    }

    // one selectable output or input device
    component DeviceRow: Rectangle {
        id: dr
        property var app
        property var node
        property bool isDefault: false
        property bool isInput: false
        property color accent: app.cBlue
        signal chosen()

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 14
        color: isDefault ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
             : drHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
             : "transparent"
        Behavior on color { ColorAnimation { duration: app.animQuick } }

        readonly property string title:
            node?.nickname || node?.description || node?.name || "Unknown device"
        readonly property string sub: {
            const d = node?.description ?? ""
            return d !== "" && d !== title ? d : (node?.name ?? "")
        }
        readonly property string glyph: {
            const s = ((node?.description ?? "") + " " + (node?.name ?? "")).toLowerCase()
            if (isInput) return "mic"
            if (s.includes("hdmi") || s.includes("displayport")) return "monitor"
            if (s.includes("headphone") || s.includes("headset")) return "headphones"
            return "speaker"
        }

        HoverHandler { id: drHov }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: 11
                color: dr.isDefault ? dr.accent : Qt.rgba(dr.app.cFg.r, dr.app.cFg.g, dr.app.cFg.b, 0.08)
                Text {
                    anchors.centerIn: parent
                    text: dr.glyph
                    color: dr.isDefault ? dr.app.cOnAccent : dr.app.cDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(16)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: dr.title
                    color: dr.app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: dr.sub
                    color: dr.app.cFaint
                    font.family: "Inter"
                    font.pixelSize: app.fs(10)
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: dr.isDefault
                text: "In use"
                color: dr.accent
                font.family: "Inter"
                font.pixelSize: app.fs(11)
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: dr.isDefault ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!dr.isDefault) dr.chosen()
        }
    }

    // one application's stream: icon, name, what it is playing,
    // mute, and its own volume
    component StreamCard: Rectangle {
        id: sc
        property var app
        property var node
        property real maxVol: 1
        property color accent: app.cBlue

        readonly property var au: node?.audio ?? null
        readonly property bool muted: au?.muted ?? false
        readonly property var props: node?.properties ?? ({})
        readonly property string appName:
            props["application.name"] || node?.description || node?.name || "Application"
        readonly property string mediaName: {
            const m = props["media.name"] ?? ""
            return m !== appName ? m : ""
        }

        Layout.fillWidth: true
        implicitHeight: scRow.implicitHeight + 30
        radius: 18
        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.09)

        RowLayout {
            id: scRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            Rectangle {
                implicitWidth: 46
                implicitHeight: 46
                radius: 14
                color: Qt.rgba(sc.app.cFg.r, sc.app.cFg.g, sc.app.cFg.b, 0.08)
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 28
                    source: sc.app.iconFor(sc.props["application.icon-name"]
                                           || sc.props["application.process.binary"]
                                           || sc.appName)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: sc.appName
                    color: sc.app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: sc.mediaName
                    color: sc.app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    elide: Text.ElideRight
                }

                Slider {
                    app: sc.app
                    to: sc.maxVol
                    tick: 1
                    value: sc.au?.volume ?? 0
                    muted: sc.au?.muted ?? false
                    accent: sc.accent
                    label: sc.muted ? "Muted" : Math.round(value * 100) + "%"
                    onMoved: v => {
                        if (!sc.au) return
                        sc.au.volume = v
                        if (v > 0 && sc.au.muted) sc.au.muted = false
                    }
                }
            }

            IconBtn {
                app: sc.app
                accent: sc.app.cRed
                active: sc.au?.muted ?? false
                glyph: active ? "volume_off" : "volume_up"
                onClicked: if (sc.au) sc.au.muted = !sc.au.muted
            }
        }
    }

    // ---------------------------------------------------------
    //   the panel
    // ---------------------------------------------------------
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
        active: modelData.name === app.mainScreen && (used || app.settingsShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: win
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Stays mapped and animates itself: mapping a new surface on each
        // open lagged, and Hyprland's own layer fade fought the shell's.
        // Closed, nothing shows and the mask lets every click through.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.settingsShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)

        // A transparent full-screen layer with the card moving inside
        // it.  Moving the surface itself made every drag event arrive
        // relative to where the compositor had not yet put it, which
        // is what made it shake.  The mask lets clicks outside the
        // card fall through to the windows underneath.
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        property Region shownMask: Region { item: card }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        // tall enough for every page in the navigation, but never
        // taller than the screen it's on
        readonly property int cardW: 900
        readonly property int cardH: Math.min(820, height - 80)

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // starts centred; dragging breaks the binding and it
        // stays wherever you leave it until quickshell restarts
        property real posX: Math.round((width - cardW) / 2)
        property real posY: Math.round((height - cardH) / 2)

        function moveTo(x, y) {
            posX = Math.round(Math.max(0, Math.min(width - cardW, x)))
            posY = Math.round(Math.max(0, Math.min(height - cardH, y)))
        }

        // ---- state ----
        readonly property int page: app.settingsPage
        property bool boost: false
        readonly property real maxVol: boost ? 1.5 : 1.0

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource
        readonly property var sinkAu: sink?.audio ?? null
        readonly property var sourceAu: source?.audio ?? null

        readonly property var pages: [
            { t: "General",        d: "File search, the clipboard, and text across the whole shell" },
            { t: "Glass",          d: "How far the desktop shows through" },
            { t: "Theme",          d: "How colours are drawn from the wallpaper" },
            { t: "Wallpaper",      d: "The image everything takes its colours from" },
            { t: "Bar",            d: "The clock and what the top bar shows" },
            { t: "Windows",        d: "Spacing, shape and motion for app windows" },
            { t: "Dock",           d: "The window dock along the bottom edge" },
            { t: "Notifications",  d: "Popups and on-screen indicators" },
            { t: "Idle",           d: "Locking, screens off and sleep when you step away" },
            { t: "Displays",       d: "Resolution, refresh rate, scale and layout" },
            { t: "Keyboard",       d: "How keys repeat when held" },
            { t: "Mouse",          d: "Pointer speed, scrolling and focus" },
            { t: "Output",         d: "Where sound plays and how loud it is" },
            { t: "Applications",   d: "Volume for each app that is playing sound" },
            { t: "Input",          d: "Which microphone is used and its level" },
            { t: "Recording apps", d: "Apps currently listening to a microphone" },
            { t: "Weather",        d: "Where the forecast is for, and its units" },
            { t: "Calendar",       d: "Holidays and the first day of the week" },
            { t: "About",          d: "This machine and the software running it" },
            { t: "Widgets",        d: "Clocks, weather and more on the desktop, behind your windows" },
            { t: "Lock screen",    d: "What you see when the screen is locked" },
            { t: "Default apps",   d: "Which terminal, file manager and browser open" },
            { t: "AI assistant",   d: "Which AI answers in the assistant panel, and your key for it" }
        ]

        onPageChanged: flick.contentY = 0

        // ---- displays draft ----
        // A plain-value copy of each monitor's chosen mode and scale,
        // edited freely and only sent to Hyprland on Apply.
        property var draft: ({})
        property string arrange: "above"      // where the second screen sits
        readonly property string mainMon: app.mainScreen
        readonly property var scales: [1, 1.25, 1.5, 1.75, 2]

        function parseMode(str) {
            const m = String(str).replace(/Hz$/, "").match(/^(\d+)x(\d+)@([\d.]+)$/)
            return m ? { w: +m[1], h: +m[2], hz: +m[3], mode: m[1] + "x" + m[2] + "@" + m[3] } : null
        }
        function resList(mon) {
            const seen = {}, out = []
            for (const s of mon.modes) {
                const p = parseMode(s)
                if (!p) continue
                const k = p.w + "x" + p.h
                if (!seen[k]) { seen[k] = true; out.push({ w: p.w, h: p.h, key: k }) }
            }
            return out.sort((a, b) => b.w * b.h - a.w * a.h).slice(0, 8)
        }
        function rateList(mon, res) {
            const out = []
            for (const s of mon.modes) {
                const p = parseMode(s)
                if (p && p.w + "x" + p.h === res) out.push(p)
            }
            return out.sort((a, b) => b.hz - a.hz)
        }
        function loadDraft() {
            const d = {}
            for (const m of app.monInfo) {
                const rates = rateList(m, m.w + "x" + m.h)
                let best = rates[0]
                for (const r of rates)
                    if (Math.abs(r.hz - m.hz) < Math.abs(best.hz - m.hz)) best = r
                d[m.name] = { res: m.w + "x" + m.h,
                              mode: best ? best.mode : m.w + "x" + m.h + "@" + m.hz.toFixed(2),
                              scale: m.scale }
            }
            draft = d
            const saved = app.cfg.monitorsArrange
            arrange = ["above", "below", "left", "right"].indexOf(saved) >= 0 ? saved : "above"
        }
        function setDraft(name, field, value) {
            const d = JSON.parse(JSON.stringify(draft))
            if (!d[name]) return
            d[name][field] = value
            if (field === "res") {
                const mon = app.monInfo.find(m => m.name === name)
                const rates = mon ? rateList(mon, value) : []
                d[name].mode = rates.length ? rates[0].mode : value + "@60"
            }
            draft = d
        }
        function draftDirty() {
            for (const m of app.monInfo) {
                const d = draft[m.name]
                if (!d) continue
                if (d.res !== m.w + "x" + m.h || Math.abs(d.scale - m.scale) > 0.001) return true
                const p = parseMode(d.mode)
                if (p && Math.abs(p.hz - m.hz) > 0.5) return true
            }
            return arrange !== (app.cfg.monitorsArrange || "above")
        }
        // logical size, which is what positions are measured in
        function logical(name) {
            const d = draft[name]
            const p = d ? parseMode(d.mode) : null
            if (!p) return { w: 0, h: 0 }
            return { w: Math.round(p.w / d.scale), h: Math.round(p.h / d.scale) }
        }
        function applyDraft() {
            const names = Object.keys(draft)
            const other = names.find(n => n !== mainMon)
            const pos = {}
            pos[mainMon] = "0x0"
            if (other) {
                const a = logical(mainMon), b = logical(other)
                if (arrange === "above")      { pos[other] = "0x0";          pos[mainMon] = "0x" + b.h }
                else if (arrange === "below") { pos[mainMon] = "0x0";        pos[other] = "0x" + a.h }
                else if (arrange === "left")  { pos[other] = "0x0";          pos[mainMon] = b.w + "x0" }
                else                          { pos[mainMon] = "0x0";        pos[other] = a.w + "x0" }
            }
            const out = {}
            for (const n of names)
                out[n] = { mode: draft[n].mode, position: pos[n] || "0x0", scale: draft[n].scale }
            app.applyDisplays(out, arrange)
        }
        Connections {
            target: app
            function onMonInfoChanged() { win.loadDraft() }
        }

        // ---- node filters (audio only: webcams and the MIDI
        //      bridge are PipeWire nodes too, and have no audio) ----
        function isOutDev(n) { return !!n && !!n.audio && n.isSink && !n.isStream }
        function isInDev(n)  { return !!n && !!n.audio && !n.isSink && !n.isStream }
        function isPlay(n)   { return !!n && !!n.audio && n.isSink && n.isStream }
        // listening to a microphone: an input stream that isn't capturing an
        // output (the visualiser, and anything else that listens to what the
        // speakers play, sets stream.capture.sink, and uses no microphone)
        function isRec(n)    { return !!n && !!n.audio && !n.isSink && n.isStream
                                      && !(n.properties && n.properties["stream.capture.sink"] === "true") }
        function count(fn)   { return Pipewire.nodes.values.filter(fn).length }

        // ---- volume with balance preserved ----
        function vols(au) {
            if (!au) return [0]
            return (au.volumes && au.volumes.length) ? au.volumes : [au.volume]
        }
        function master(au) { return au ? Math.max.apply(null, vols(au)) : 0 }
        function balance(au) {
            const v = au?.volumes
            if (!v || v.length !== 2) return 0
            const m = Math.max(v[0], v[1])
            return m > 0 ? (v[1] - v[0]) / m : 0
        }
        function applyBal(m, b) {
            return [m * (1 - Math.max(0, b)), m * (1 + Math.min(0, b))]
        }
        // The output's level and balance are read AND written with
        // pactl.  Quickshell reports channel volumes on a different
        // scale from pactl, so mixing the two made every balance move
        // read back louder than it wrote.  vol and bal are the panel's
        // copy, refreshed from pactl on open and on outside changes.
        property real vol: 0
        property real bal: 0
        property int sinkCh: 2
        onOpenChanged: if (open) readSink()

        function readSink() { if (!readProc.running) readProc.running = true }

        Process {
            id: readProc
            command: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/(\d+)%/g)
                    if (!m || !m.length) return
                    const v = m.map(x => parseInt(x) / 100)
                    win.sinkCh = v.length >= 2 ? 2 : 1
                    if (v.length >= 2) {
                        const hi = Math.max(v[0], v[1])
                        win.vol = hi
                        win.bal = hi > 0 ? (v[1] - v[0]) / hi : 0
                    } else {
                        win.vol = v[0]
                        win.bal = 0
                    }
                }
            }
        }

        // media keys, the sidebar slider or other apps changing the
        // output while the panel is open; our own writes are ignored
        // for a moment so a drag doesn't fight its own echo
        Process {
            running: win.open
            command: ["stdbuf", "-oL", "pactl", "subscribe"]
            stdout: SplitParser {
                onRead: line => {
                    if ((line.includes(" on sink ") || line.includes(" on server "))
                            && !quiet.running)
                        win.readSink()
                }
            }
        }
        Timer { id: quiet; interval: 400 }

        property var pendingVol: null
        function writeSink() {
            const v = applyBal(vol, bal)
            pendingVol = sinkCh === 2
                ? [Math.round(v[0] * 100) + "%", Math.round(v[1] * 100) + "%"]
                : [Math.round(vol * 100) + "%"]
            quiet.restart()
            if (!volProc.running) flushVol()
        }
        function flushVol() {
            if (!pendingVol) return
            volProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@"]
                              .concat(pendingVol)
            pendingVol = null
            volProc.running = true
        }

        // one pactl at a time; a fast drag only sends the latest value
        Process {
            id: volProc
            onExited: win.flushVol()
        }

        function setMaster(au, x) {
            if (!au) return
            if (au === sinkAu) {
                vol = x
                writeSink()
            } else {
                au.volume = x
            }
            if (x > 0 && au.muted) au.muted = false
        }
        function setBalance(b) {
            bal = Math.abs(b) < 0.04 ? 0 : b
            writeSink()
        }
        function pct(v) { return Math.round(v * 100) + "%" }
        function nodeName(n) {
            return n?.nickname || n?.description || n?.name || "No device"
        }

        // bind every node's volume, mute and channels while open
        PwObjectTracker {
            objects: win.open ? Pipewire.nodes.values : []
        }

        Rectangle {
            id: card
            x: win.posX
            y: win.posY
            width: win.cardW
            height: win.cardH
            opacity: win.open ? 1 : 0
            scale: win.open ? 1 : 0.95
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            radius: 24
            color: app.cCard
            border.width: 1
            border.color: app.cBorder

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) {
                        app.settingsShown = false
                    } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        app.settingsPage = e.key - Qt.Key_1
                    } else if (e.key === Qt.Key_0) {
                        app.settingsPage = 9
                    } else return
                    e.accepted = true
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                // ================= NAVIGATION =================
                ColumnLayout {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 220
                    Layout.maximumWidth: 220
                    Layout.fillHeight: true
                    spacing: 2

                    // header, doubles as a drag handle
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 64

                        MouseArea {
                            anchors.fill: parent
                            property real ox: 0
                            property real oy: 0
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            onPressed: m => {
                                const p = mapToItem(null, m.x, m.y)
                                ox = p.x - win.posX
                                oy = p.y - win.posY
                                keys.forceActiveFocus()
                            }
                            onPositionChanged: m => {
                                if (!pressed) return
                                const p = mapToItem(null, m.x, m.y)
                                win.moveTo(p.x - ox, p.y - oy)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            spacing: 12

                            Rectangle {
                                implicitWidth: 38
                                implicitHeight: 38
                                radius: 12
                                color: app.cBlue
                                Text {
                                    anchors.centerIn: parent
                                    text: "settings"
                                    color: app.cOnAccent
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: app.fs(18)
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: "Settings"
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(15)
                                    font.bold: true
                                }
                                Text {
                                    text: "Shell preferences"
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // the page list scrolls on its own if it outgrows the
                    // window, so the header and Reset all never get pushed off
                    Flickable {
                        id: navFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: navCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: navCol
                            width: navFlick.width
                            spacing: 2

                            Repeater {
                                model: [
                                    { sec: "Appearance" },
                                    { i: 0, t: "General",        g: "text_fields" },
                                    { i: 1, t: "Glass",          g: "blur_on" },
                                    { i: 2, t: "Theme",          g: "palette" },
                                    { i: 3, t: "Wallpaper",      g: "wallpaper" },
                                    { sec: "Desktop" },
                                    { i: 4, t: "Bar",            g: "toolbar" },
                                    { i: 5, t: "Windows",        g: "web_asset" },
                                    { i: 6, t: "Dock",           g: "dock_to_bottom" },
                                    { i: 7, t: "Notifications",  g: "notifications" },
                                    { i: 8, t: "Idle",           g: "lock" },
                                    { i: 20, t: "Lock screen",   g: "lock_clock" },
                                    { i: 19, t: "Widgets",       g: "widgets" },
                                    { sec: "Devices" },
                                    { i: 9, t: "Displays",       g: "monitor" },
                                    { i: 10, t: "Keyboard",       g: "keyboard" },
                                    { i: 11, t: "Mouse",          g: "mouse" },
                                    { sec: "Sound" },
                                    { i: 12, t: "Output",         g: "speaker" },
                                    { i: 13, t: "Applications",   g: "apps" },
                                    { i: 14, t: "Input",          g: "mic" },
                                    { i: 15, t: "Recording apps", g: "radio_button_checked" },
                                    { sec: "System" },
                                    { i: 16, t: "Weather",        g: "partly_cloudy_day" },
                                    { i: 17, t: "Calendar",       g: "calendar_month" },
                                    { i: 21, t: "Default apps",   g: "apps" },
                                    { i: 22, t: "AI assistant",   g: "smart_toy" },
                                    { i: 18, t: "About",          g: "info" }
                                ]

                                delegate: Item {
                                    id: navItem
                                    required property var modelData
                                    readonly property bool isSec: modelData.sec !== undefined
                                    readonly property bool on: !isSec && win.page === modelData.i
                                    readonly property int badge:
                                        isSec ? 0
                                        : modelData.i === 13 ? win.count(win.isPlay)
                                        : modelData.i === 15 ? win.count(win.isRec)
                                        : 0

                                    Layout.fillWidth: true
                                    implicitHeight: isSec ? 34 : 44

                                    Text {
                                        visible: navItem.isSec
                                        anchors.left: parent.left
                                        anchors.leftMargin: 16
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 6
                                        text: navItem.modelData.sec ?? ""
                                        color: app.cFaint
                                        font.family: "Inter"
                                        font.pixelSize: app.fs(11)
                                    }

                                    Rectangle {
                                        visible: !navItem.isSec
                                        anchors.fill: parent
                                        radius: 22
                                        color: navItem.on ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                                             : navHov.hovered ? app.cTile : "transparent"
                                        Behavior on color { ColorAnimation { duration: app.animQuick } }

                                        HoverHandler { id: navHov }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 16
                                            anchors.rightMargin: 14
                                            spacing: 14

                                            Text {
                                                text: navItem.modelData.g ?? ""
                                                color: navItem.on ? app.cBlue : app.cDim
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: app.fs(16)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: navItem.modelData.t ?? ""
                                                color: navItem.on ? app.cFg : app.cDim
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(13)
                                                font.bold: navItem.on
                                            }
                                            Rectangle {
                                                visible: navItem.badge > 0
                                                implicitWidth: Math.max(22, badgeT.implicitWidth + 12)
                                                implicitHeight: 20
                                                radius: 10
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                Text {
                                                    id: badgeT
                                                    anchors.centerIn: parent
                                                    text: navItem.badge
                                                    color: app.cDim
                                                    font.family: "Inter"
                                                    font.pixelSize: app.fs(10)
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { app.settingsPage = navItem.modelData.i; keys.forceActiveFocus() }
                                        }
                                    }
                                }
                            }

                        }
                    }


                    // returns every setting to its default; the first
                    // click arms it, a second within 3 s confirms
                    Text {
                        id: resetAll
                        property bool armed: false
                        Layout.leftMargin: 16
                        Layout.bottomMargin: 12
                        text: armed ? "Click again to reset everything" : "Reset all"
                        color: armed ? app.cRed : resetHov.hovered ? app.cFg : app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(11)
                        font.bold: armed
                        HoverHandler { id: resetHov }
                        Timer {
                            id: disarm
                            interval: 3000
                            onTriggered: resetAll.armed = false
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (resetAll.armed) {
                                    app.resetAllSettings()
                                    resetAll.armed = false
                                    disarm.stop()
                                } else {
                                    resetAll.armed = true
                                    disarm.restart()
                                }
                            }
                        }
                    }
                }

                // ================= CONTENT =================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 18
                    color: app.isLight ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(0, 0, 0, 0.18)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 26
                        anchors.rightMargin: 16
                        anchors.topMargin: 20
                        anchors.bottomMargin: 12
                        spacing: 14

                        // page header, also a drag handle
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 56

                            MouseArea {
                                anchors.fill: parent
                                property real ox: 0
                                property real oy: 0
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                onPressed: m => {
                                    const p = mapToItem(null, m.x, m.y)
                                    ox = p.x - win.posX
                                    oy = p.y - win.posY
                                    keys.forceActiveFocus()
                                }
                                onPositionChanged: m => {
                                    if (!pressed) return
                                    const p = mapToItem(null, m.x, m.y)
                                    win.moveTo(p.x - ox, p.y - oy)
                                }
                            }

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Text {
                                    text: win.pages[win.page].t
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(22)
                                    font.bold: true
                                }
                                Text {
                                    text: win.pages[win.page].d
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.top: parent.top
                                anchors.topMargin: 2
                                text: "close"
                                color: closeHov.hovered ? app.cFg : app.cDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(20)
                                HoverHandler { id: closeHov }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.settingsShown = false
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Flickable {
                                id: flick
                                anchors.fill: parent
                                anchors.rightMargin: 14
                                contentWidth: width
                                contentHeight: pagesCol.implicitHeight + 8
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: pagesCol
                                    width: flick.width

                                    // ================= GENERAL =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 0
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Launcher" }

                                        Card {
                                            app: rootV.app
                                            title: "File search"
                                            desc: !app.nativeOk ? "Needs the native plugin, which isn't built: re-run the installer."
                                                  : app.cfg.fileSearch === false
                                                  ? "Off: the launcher only finds apps, and nothing is indexed."
                                                  : "The launcher finds your files as you type (start with / for files only). "
                                                    + (app.fileCount ? app.fileCount.toLocaleString(Qt.locale(), "f", 0) + " files and folders in your home, kept up to date as they change. "
                                                                     : "Indexing your home\u2026 ")
                                                    + "Hidden folders, caches and dependency folders are left out."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.fileSearch === false ? 0 : 1
                                                    onPicked: i => app.setting("fileSearch", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Clipboard" }

                                        Card {
                                            app: rootV.app
                                            title: "Keep copies when apps close"
                                            desc: !app.clipNativeOn
                                                  ? "Needs the native clipboard, which isn't running: re-run the installer."
                                                  : app.cfg.clipPersist === false
                                                  ? "Off: when you close the app you copied from, what you copied goes with it (how Wayland works on its own)."
                                                  : "When you close the app you copied from, your copy stays on the clipboard. Copies a password manager marks secret are never kept."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.clipPersist === false ? 0 : 1
                                                    onPicked: i => app.setting("clipPersist", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Text" }

                                        Card {
                                            app: rootV.app
                                            title: "Text size"
                                            desc: "Scales every label in the bar, dock, sidebar and panels. Takes effect straight away."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.8
                                                    to: 1.4
                                                    tick: 1
                                                    step: 0.05
                                                    value: app.cfg.fontScale ?? 1
                                                    label: Math.round(value * 100) + "%"
                                                    onMoved: v => app.setting("fontScale",
                                                                              Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.fontScale === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("fontScale")
                                                }
                                            ]
                                        }

                                    }

                                    // ================= GLASS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 1
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Shell" }

                                        Card {
                                            app: rootV.app
                                            title: "Shell panels"
                                            desc: "How solid the bar, dock, sidebar and panels are. Lower lets more of the blurred desktop through."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.3
                                                    to: 1
                                                    tick: 0.75
                                                    step: 0.05
                                                    value: app.bgA
                                                    label: Math.round(value * 100) + "%"
                                                    onMoved: v => app.setting("bgOpacity",
                                                                              Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.bgOpacity === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("bgOpacity")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Terminal" }

                                        Card {
                                            app: rootV.app
                                            title: "Terminal background"
                                            desc: "How see-through kitty's background is. Text stays fully solid. Open terminals change straight away."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.3
                                                    to: 1
                                                    tick: 0.75
                                                    step: 0.05
                                                    value: app.termOpacity
                                                    label: Math.round(value * 100) + "%"
                                                    onMoved: v => app.setting("termOpacity",
                                                                              Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.termOpacity === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("termOpacity")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Windows" }

                                        Card {
                                            app: rootV.app
                                            title: "Focused window"
                                            desc: "Opacity of the window you're using. Multiplies with an app's own transparency, so kitty at 75% here at 90% ends up lighter still."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.5
                                                    to: 1
                                                    tick: 1
                                                    step: 0.05
                                                    value: app.cfg.winActive
                                                    label: Math.round(value * 100) + "%"
                                                    onMoved: v => app.setting("winActive", Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.winActive === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("winActive")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Other windows"
                                            desc: "Opacity of every window that doesn't have focus. Lowering it makes the focused one stand out."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.5
                                                    to: 1
                                                    tick: 1
                                                    step: 0.05
                                                    value: app.cfg.winInactive
                                                    label: Math.round(value * 100) + "%"
                                                    onMoved: v => app.setting("winInactive", Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.winInactive === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("winInactive")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Blur" }

                                        Card {
                                            app: rootV.app
                                            title: "Blur radius"
                                            desc: "How far the frost spreads behind every see-through surface. Larger looks softer and costs more GPU."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 1
                                                    to: 16
                                                    tick: 4
                                                    step: 1
                                                    value: app.cfg.blurSize
                                                    label: Math.round(value)
                                                    onMoved: v => app.setting("blurSize", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.blurSize === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("blurSize")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Blur passes"
                                            desc: "How many times the blur is applied. More passes give a smoother frost at a large radius; fewer can look blocky."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["1", "2", "3", "4"]
                                                    current: app.cfg.blurPasses - 1
                                                    onPicked: i => app.setting("blurPasses", i + 1)
                                                }
                                            ]
                                        }
                                    }

                                    // ================= THEME =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 2
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Mode" }

                                        Card {
                                            app: rootV.app
                                            title: "Appearance"
                                            desc: app.cfg.themeMode === "auto"
                                                  ? (app.nativeOk
                                                     ? "Chosen by the wallpaper: light for bright ones, dark for the rest (this one is "
                                                       + (app.wallLightness < 0 ? "being measured" : app.isLight ? "bright, so light" : "dark enough for dark") + ")."
                                                     : "Auto needs the native plugin, which isn't built: re-run the installer. Until then it stays dark.")
                                                  : "Light or dark palette from the same wallpaper, for the shell, terminal, launcher, lock screen and GTK and KDE apps. Auto picks by how bright the wallpaper is."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Dark", "Light", "Auto"]
                                                    current: app.cfg.themeMode === "auto" ? 2 : app.isLight ? 1 : 0
                                                    onPicked: i => app.setting("themeMode", ["dark", "light", "auto"][i])
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Colour style" }

                                        Card {
                                            app: rootV.app
                                            title: "Style"
                                            desc: app.themeBusy
                                                  ? "Applying to every app\u2026"
                                                  : "How matugen turns the wallpaper into a palette. Picking one retints the shell, terminal, launcher, borders and apps."

                                            Repeater {
                                                model: [
                                                    { k: "auto",               t: "Auto",        d: app.cfg.themeScheme === "auto" && app.wallScheme
                                                        ? "Picked for each wallpaper: this one is " + ({ "scheme-monochrome": "black and white, so monochrome",
                                                            "scheme-neutral": "muted, so neutral", "scheme-content": "mostly one bold colour, so content, which keeps close to it",
                                                            "scheme-fidelity": "mostly one bold colour, so fidelity",
                                                            "scheme-tonal-spot": "colourful and varied, so tonal spot" })[app.wallScheme] + "."
                                                        : app.nativeOk ? "Picked for each wallpaper, from how colourful it is and how much of it is one colour."
                                                        : "Needs the native plugin, which isn't built: re-run the installer. Until then, tonal spot." },
                                                    { k: "scheme-tonal-spot",  t: "Tonal spot",  d: "Calm and balanced, with soft accents from the wallpaper's main colour." },
                                                    { k: "scheme-vibrant",     t: "Vibrant",     d: "Saturated accents that pop more than the wallpaper itself." },
                                                    { k: "scheme-expressive",  t: "Expressive",  d: "Shifts hues away from the wallpaper for a more playful contrast." },
                                                    { k: "scheme-fidelity",    t: "Fidelity",    d: "Stays as close as it can to the wallpaper's actual colours." },
                                                    { k: "scheme-content",     t: "Content",     d: "Like fidelity, tuned so images and artwork sit naturally beside it." },
                                                    { k: "scheme-fruit-salad", t: "Fruit salad", d: "Bold, rotated hues, bright and mixed." },
                                                    { k: "scheme-rainbow",     t: "Rainbow",     d: "Colourful accents over neutral backgrounds." },
                                                    { k: "scheme-neutral",     t: "Neutral",     d: "Nearly grey, with just a hint of the wallpaper." },
                                                    { k: "scheme-monochrome",  t: "Monochrome",  d: "Pure greys, no colour at all." },
                                                    { k: "scheme-smart",       t: "matugen's choice", d: "matugen picks the style by itself. Auto, at the top, is Ether Shell's own choice, and reads the wallpaper better." }
                                                ]
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.t
                                                    desc: modelData.d
                                                    selected: (app.cfg.themeScheme === "auto" ? "auto" : app.themeScheme) === modelData.k
                                                    onChosen: app.setting("themeScheme", modelData.k)
                                                }
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Colour source" }

                                        Card {
                                            app: rootV.app
                                            title: "Source colour"
                                            desc: "Most wallpapers hold several candidate colours. This decides which one the whole palette is built from."

                                            Repeater {
                                                model: [
                                                    { k: "smart",           t: "Smart", d: !app.nativeOk
                                                        ? "Needs the native plugin, which isn't built: re-run the installer. Until then, most of the picture."
                                                        : app.themePrefer === "smart" && app.wallWhy
                                                        ? "Ether Shell's own pick for this wallpaper: " + (app.wallWhy === "no strong colour"
                                                              ? "it has no strong colour, so its own soft tint."
                                                              : "the colour of " + app.wallWhy + (app.wallSecond ? ", with its second colour as the third accent." : "."))
                                                        : "Ether Shell's own pick: the subject over the backdrop, skin tones set aside, borders ignored. Recommended." },
                                                    { k: "dominant",        t: "Most of the picture", d: "The colour covering most of the wallpaper, scored as Material You does on Android. Palettes look like the wallpaper." },
                                                    { k: "saturation",      t: "Most vivid",  d: "The most colourful part of the image, even a small detail (a light, a highlight), so different wallpapers can come out alike." },
                                                    { k: "less-saturation", t: "Most muted",  d: "A softer, greyer colour from the image." },
                                                    { k: "darkness",        t: "Darkest",     d: "Drawn from the image's deep tones." },
                                                    { k: "lightness",       t: "Lightest",    d: "Drawn from the pale parts of the image." },
                                                    { k: "value",           t: "Brightest",   d: "The most luminous colour, whatever its hue." }
                                                ]
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.t
                                                    desc: modelData.d
                                                    selected: app.themePrefer === modelData.k
                                                    onChosen: app.setting("themePrefer", modelData.k)
                                                }
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Accent"
                                            desc: app.cfg.accentStyle === "soft"
                                                  ? "A soft, lighter version of the wallpaper's colour, as Material You uses on Android."
                                                  : "The wallpaper's own colour, as it is, everywhere: the shell, window borders, the terminal, your prompt, the lock screen, and GTK and KDE apps. Lightened only when it wouldn't be readable. Needs the Smart colour source; greyscale wallpapers keep soft accents."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Vivid", "Soft"]
                                                    current: app.cfg.accentStyle === "soft" ? 1 : 0
                                                    onPicked: i => app.setting("accentStyle", i === 1 ? "soft" : "vivid")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Now playing" }

                                        Card {
                                            app: rootV.app
                                            title: "Colours from album art"
                                            desc: app.cfg.artColors === false
                                                  ? "The media views keep your wallpaper's colours."
                                                  : !app.nativeOk
                                                  ? "Needs the native plugin, which isn't built: re-run the installer to build it. Until then the media views keep your wallpaper's colours."
                                                  : "While something plays, the media drawer, the bar's media pill, the mini player and the island's song card take their colours from the album art, and fade back to your wallpaper's when it stops. Everything else keeps your wallpaper's colours."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.artColors !== false ? 1 : 0
                                                    onPicked: i => app.setting("artColors", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Contrast" }

                                        Card {
                                            app: rootV.app
                                            title: "Contrast"
                                            desc: "Pushes text and accents further from their backgrounds, or softens them. Applies a moment after you stop changing it."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: -1
                                                    to: 1
                                                    origin: 0
                                                    tick: 0
                                                    step: 0.1
                                                    value: app.themeContrast
                                                    label: Math.abs(value) < 0.05 ? "Standard"
                                                         : (value > 0 ? "+" : "") + value.toFixed(1)
                                                    onMoved: v => app.setting("themeContrast",
                                                                              Math.round(v * 10) / 10)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.themeContrast === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("themeContrast")
                                                }
                                            ]
                                        }
                                    }

                                    // ================= WALLPAPER =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 3
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Current" }

                                        Card {
                                            app: rootV.app
                                            title: app.currentWall !== ""
                                                   ? app.currentWall.split("/").pop()
                                                   : "No wallpaper set yet"
                                            desc: app.wallBusy
                                                  ? "Applying and retinting every app\u2026"
                                                  : "Picking an image below sets it and rebuilds the palette with your Theme settings."

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                implicitHeight: width * 9 / 16
                                                radius: 14
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                clip: true
                                                visible: app.currentWall !== ""

                                                Image {
                                                    anchors.fill: parent
                                                    source: app.currentWall !== "" ? "file://" + app.currentWall : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    sourceSize.width: 1200
                                                    opacity: app.wallBusy ? 0.5 : 1
                                                    Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Library" }

                                        Card {
                                            app: rootV.app
                                            title: app.wallpapers.length + (app.wallpapers.length === 1 ? " image" : " images")
                                            desc: app.wallpapers.length > 0
                                                  ? "From ~/Pictures/wallpapers. New files show up the next time this page opens."
                                                  : "Put images in ~/Pictures/wallpapers and reopen this page."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Random", "Open folder"]
                                                    onPicked: i => {
                                                        if (i === 0) app.randomWallpaper()
                                                        else app.run("xdg-open \"$HOME/Pictures/wallpapers\"")
                                                    }
                                                }
                                            ]

                                            Grid {
                                                id: wallGrid
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                columns: 3
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
                                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                        clip: true
                                                        border.width: isCurrent ? 3 : thHov.hovered ? 2 : 0
                                                        border.color: isCurrent ? app.cBlue : app.cFg

                                                        HoverHandler { id: thHov }

                                                        Image {
                                                            anchors.fill: parent
                                                            anchors.margins: thumb.border.width
                                                            source: "file://" + thumb.modelData
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            cache: true
                                                            sourceSize.width: 360
                                                        }

                                                        // the colours this wallpaper would give
                                                        Rectangle {
                                                            readonly property var colours: app.wallPalettes[thumb.modelData] || []
                                                            visible: colours.length > 0
                                                            anchors.left: parent.left
                                                            anchors.top: parent.top
                                                            anchors.margins: 8
                                                            width: swRow.implicitWidth + 10
                                                            height: 20
                                                            radius: 10
                                                            color: Qt.rgba(0, 0, 0, 0.45)
                                                            Row {
                                                                id: swRow
                                                                anchors.centerIn: parent
                                                                spacing: 3
                                                                Repeater {
                                                                    model: parent.parent.colours
                                                                    delegate: Rectangle {
                                                                        required property var modelData
                                                                        width: 12; height: 12; radius: 6
                                                                        color: modelData
                                                                        border.width: 1
                                                                        border.color: Qt.rgba(1, 1, 1, 0.35)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // check on the one in use
                                                        Rectangle {
                                                            visible: thumb.isCurrent
                                                            anchors.right: parent.right
                                                            anchors.top: parent.top
                                                            anchors.margins: 8
                                                            width: 24; height: 24; radius: 12
                                                            color: app.cBlue
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "check"
                                                                color: app.cOnAccent
                                                                font.family: "Material Symbols Rounded"
                                                                font.pixelSize: app.fs(13)
                                                            }
                                                        }

                                                        // file name while hovered
                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.bottom: parent.bottom
                                                            height: 26
                                                            color: Qt.rgba(0, 0, 0, 0.55)
                                                            opacity: thHov.hovered ? 1 : 0
                                                            Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                width: parent.width - 14
                                                                text: String(thumb.modelData).split("/").pop()
                                                                color: "white"
                                                                font.family: "Inter"
                                                                font.pixelSize: app.fs(10)
                                                                elide: Text.ElideMiddle
                                                                horizontalAlignment: Text.AlignHCenter
                                                            }
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
                                    }

                                    // ================= BAR =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 4
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Clock" }

                                        Card {
                                            app: rootV.app
                                            title: "Time format"
                                            desc: "Right now the bar reads " + Qt.formatDateTime(app.now, app.clockFormat).replace(/ +/g, " ")
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["12-hour", "24-hour"]
                                                    current: app.cfg.clock24h === true ? 1 : 0
                                                    onPicked: i => app.setting("clock24h", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Seconds"
                                            desc: "Adds seconds to the time."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.clockSeconds === true ? 1 : 0
                                                    onPicked: i => app.setting("clockSeconds", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Date"
                                            desc: "Shows the weekday and date before the time."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.clockDate !== false ? 1 : 0
                                                    onPicked: i => app.setting("clockDate", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Style" }

                                        Card {
                                            app: rootV.app
                                            title: "Bar style"
                                            desc: app.barAttached
                                                  ? "One long bar across the top. Its sections open cards that slide out from behind it."
                                                  : "Three separate floating pills that grow into panels."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Long bar", "Islands"]
                                                    current: app.barAttached ? 0 : 1
                                                    onPicked: i => {
                                                        app.cardShown = false
                                                        app.quickShown = false
                                                        app.sysShown = false
                                                        app.setting("barStyle", i === 0 ? "long" : "islands")
                                                    }
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Centre pill" }

                                        Card {
                                            app: rootV.app
                                            title: "Clicking the centre pill"
                                            desc: app.barMorph
                                                  ? "The pill itself grows into a panel with the media, the weather and this month. Esc or the arrow at its top shrinks it back."
                                                  : "Opens the media card in its own panel under the bar."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Grow into a panel", "Card below"]
                                                    current: app.barMorph ? 0 : 1
                                                    onPicked: i => { app.cardShown = false; app.setting("barMorph", i === 0) }
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Clicking the clock"
                                            desc: app.rightMorph
                                                  ? "The right pill grows into quick settings: toggles, sliders, outputs and notifications. The sidebar is still on SUPER+V."
                                                  : "Opens the sidebar. Clicking the volume opens its own popover."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Grow into quick settings", "Open the sidebar"]
                                                    current: app.rightMorph ? 0 : 1
                                                    onPicked: i => { app.quickShown = false; app.setting("rightMorph", i === 0) }
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Clicking a stat"
                                            desc: app.leftMorph
                                                  ? "The left pill grows into a system panel: live graphs and the busiest processes."
                                                  : "Opens btop in your terminal (GPU opens nvidia-settings)."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Grow into a panel", "Open btop"]
                                                    current: app.leftMorph ? 0 : 1
                                                    onPicked: i => { app.sysShown = false; app.setting("leftMorph", i === 0) }
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Modules" }

                                        Card {
                                            app: rootV.app
                                            title: "CPU and memory"
                                            desc: "Usage percentages beside the workspaces."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.barStats ? 1 : 0
                                                    onPicked: i => app.setting("barStats", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "GPU"
                                            desc: "Load and temperature. Only appears when nvidia-smi can read the card."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.barGpu ? 1 : 0
                                                    onPicked: i => app.setting("barGpu", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Network speed"
                                            desc: "Download and upload rates beside the volume."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.barNet ? 1 : 0
                                                    onPicked: i => app.setting("barNet", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Now playing"
                                            desc: "The track in the centre of the bar while something plays."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.barMedia ? 1 : 0
                                                    onPicked: i => app.setting("barMedia", i === 1)
                                                }
                                            ]
                                        }
                                    }

                                    // ================= WINDOWS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 5
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Spacing" }

                                        Card {
                                            app: rootV.app
                                            title: "Gaps between windows"
                                            desc: "Space between tiled windows, in pixels."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 20
                                                    tick: 4
                                                    step: 1
                                                    value: app.cfg.gapsIn
                                                    label: Math.round(value) + " px"
                                                    onMoved: v => app.setting("gapsIn", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.gapsIn === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("gapsIn")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Gaps at the screen edge"
                                            desc: "Space between windows and the edges of the screen."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 40
                                                    tick: 1
                                                    step: 1
                                                    value: app.cfg.gapsOut
                                                    label: Math.round(value) + " px"
                                                    onMoved: v => app.setting("gapsOut", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.gapsOut === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("gapsOut")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Shape" }

                                        Card {
                                            app: rootV.app
                                            title: "Corner rounding"
                                            desc: "Radius of window corners, in pixels. The shell's own panels keep their shape."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 24
                                                    tick: 12
                                                    step: 1
                                                    value: app.cfg.rounding
                                                    label: Math.round(value) + " px"
                                                    onMoved: v => app.setting("rounding", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.rounding === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("rounding")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Border width"
                                            desc: "Thickness of the coloured border around windows. The colour follows the wallpaper."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 6
                                                    tick: 2
                                                    step: 1
                                                    value: app.cfg.borderSize
                                                    label: Math.round(value) + " px"
                                                    onMoved: v => app.setting("borderSize", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.borderSize === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("borderSize")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Motion" }

                                        Card {
                                            app: rootV.app
                                            title: "Animations"
                                            desc: "Windows, workspaces and layers slide and fade. Turning this off makes every change instant."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.animations === false ? 0 : 1
                                                    onPicked: i => app.setting("animations", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Animation speed"
                                            desc: "Scales every animation together. 2× plays them in half the time."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.5
                                                    to: 2
                                                    tick: 1
                                                    step: 0.1
                                                    value: app.cfg.animSpeed
                                                    label: value.toFixed(1) + "×"
                                                    onMoved: v => app.setting("animSpeed", Math.round(v * 10) / 10)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.animSpeed === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("animSpeed")
                                                }
                                            ]
                                        }

                                        Card {
                                            id: wsAnimCard
                                            app: rootV.app
                                            readonly property var styles: ["slide", "slidevert", "glide", "fade", "off"]
                                            readonly property int cur: Math.max(0, styles.indexOf(app.cfg.wsAnim || "slide"))
                                            title: "Switching workspaces"
                                            desc: ["Workspaces slide side to side, like moving along a row: higher numbers come in from the right.",
                                                   "Workspaces slide up and down.",
                                                   "A short slide with a fade: the new workspace drifts in gently.",
                                                   "The old workspace fades out as the new one fades in.",
                                                   "Workspaces change instantly."][cur]
                                                  + (app.cfg.animations === false || app.gameMode ? " (Animations are off right now.)" : "")

                                            Seg {
                                                app: rootV.app
                                                options: ["Slide", "Slide vertically", "Glide", "Fade", "Off"]
                                                current: wsAnimCard.cur
                                                onPicked: i => app.setting("wsAnim", wsAnimCard.styles[i])
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Gaming" }

                                        Card {
                                            app: rootV.app
                                            title: "Automatic game mode"
                                            desc: app.cfg.autoGameMode !== false
                                                  ? "When a game starts, animations and blur switch off and the shell does less in the background; everything comes back when it closes. Your own Game mode setting isn't touched. Steam games are recognised by themselves; mark others from the playtime card in the system drawer."
                                                  : "Games are still recognised and their playtime kept, but the desktop doesn't change for them."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.autoGameMode !== false ? 1 : 0
                                                    onPicked: i => app.setting("autoGameMode", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Notifications while gaming"
                                            desc: app.cfg.gameQuiet !== false
                                                  ? "Held while a game runs: nothing pops up, and they're all waiting in quick settings afterwards. Do not disturb isn't changed."
                                                  : "Shown as usual while a game runs."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Show", "Hold"]
                                                    current: app.cfg.gameQuiet !== false ? 1 : 0
                                                    onPicked: i => app.setting("gameQuiet", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            id: vrrCard
                                            app: rootV.app
                                            // the choices, in order, as Hyprland's values
                                            readonly property var modes: [0, 2, 3, 1]
                                            readonly property int cur: Math.max(0, modes.indexOf(
                                                Number.isInteger(app.cfg.vrr) ? app.cfg.vrr : 2))
                                            title: "Variable refresh rate"
                                            desc: ["Off: the monitor always runs at its full refresh rate.",
                                                   "G-SYNC / FreeSync for fullscreen windows: the monitor matches a game's frame rate, so dips don't stutter or tear. Off on the desktop, where some monitors flicker with it.",
                                                   "Only for fullscreen windows that say they're games or video.",
                                                   "Always on, including the desktop. Some monitors flicker with this."][cur]
                                            Seg {
                                                app: rootV.app
                                                options: ["Off", "Fullscreen", "Games only", "Always"]
                                                current: vrrCard.cur
                                                onPicked: i => app.setting("vrr", vrrCard.modes[i])
                                            }
                                        }

                                        Card {
                                            id: scanCard
                                            app: rootV.app
                                            readonly property var modes: [0, 2, 1]
                                            readonly property int cur: Math.max(0, modes.indexOf(
                                                Number.isInteger(app.cfg.directScanout) ? app.cfg.directScanout : 2))
                                            title: "Direct scanout"
                                            desc: ["Off: Hyprland composites every frame, even for fullscreen games.",
                                                   "A fullscreen game's frames go straight to the monitor, skipping Hyprland: less input lag and GPU work. Only for windows that say they're games.",
                                                   "Any fullscreen window's frames go straight to the monitor. If something flickers or looks wrong fullscreen, go back to Games."][cur]
                                            Seg {
                                                app: rootV.app
                                                options: ["Off", "Games", "Any fullscreen"]
                                                current: scanCard.cur
                                                onPicked: i => app.setting("directScanout", scanCard.modes[i])
                                            }
                                        }
                                    }

                                    // ================= DOCK =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 6
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Visibility" }

                                        Card {
                                            app: rootV.app
                                            title: "Show dock"
                                            desc: "When it's off, the space it reserves is given back and windows use the full height of the screen."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.dockEnabled ? 1 : 0
                                                    onPicked: i => app.setting("dockEnabled", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Icon size"
                                            desc: "How big the app icons are. The dock grows or shrinks around them."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 20
                                                    to: 44
                                                    step: 2
                                                    value: app.dockIcon
                                                    label: Math.round(value) + " px"
                                                    onMoved: v => app.setting("dockIcon", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.dockIcon === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("dockIcon")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Auto-hide"
                                            desc: "Slides the dock away until your pointer touches the bottom edge of the screen. Windows get the full height meanwhile."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.dockAutoHide ? 1 : 0
                                                    onPicked: i => app.setting("dockAutoHide", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Pinned apps" }

                                        Card {
                                            app: rootV.app
                                            title: app.dockPinned.length ? app.dockPinned.length + (app.dockPinned.length === 1 ? " app pinned" : " apps pinned") : "Nothing pinned yet"
                                            desc: "Right-click any app in the dock to pin it. Pinned apps stay in the dock when closed, and clicking one launches it."

                                            Repeater {
                                                model: app.dockPinned
                                                delegate: RowLayout {
                                                    id: pinRow
                                                    required property var modelData
                                                    readonly property var entry: DesktopEntries.byId(modelData)
                                                    Layout.fillWidth: true
                                                    spacing: 10
                                                    IconImage {
                                                        implicitSize: 24
                                                        source: pinRow.entry ? Quickshell.iconPath(pinRow.entry.icon, true) : ""
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: pinRow.entry ? pinRow.entry.name : pinRow.modelData + " (not installed)"
                                                        color: app.cFg
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                        elide: Text.ElideRight
                                                    }
                                                    Seg {
                                                        app: rootV.app
                                                        options: ["Unpin"]
                                                        onPicked: app.setting("dockPinned", app.dockPinned.filter(x => x !== pinRow.modelData))
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ================= NOTIFICATIONS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 7
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "The bar's island" }

                                        Card {
                                            app: rootV.app
                                            title: "Notifications"
                                            desc: !app.barAttached
                                                  ? "The island needs the long bar (Settings > Bar > Bar style)."
                                                  : app.cfg.islandNotifs === true
                                                  ? "New notifications grow out of the middle of the bar for a few seconds. Ones with buttons or a reply box still get a popup too."
                                                  : "New notifications appear as popups."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["In the bar", "As popups"]
                                                    current: app.cfg.islandNotifs === true ? 0 : 1
                                                    onPicked: i => app.setting("islandNotifs", i === 0)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Volume and brightness"
                                            desc: !app.barAttached
                                                  ? "The island needs the long bar (Settings > Bar > Bar style)."
                                                  : app.cfg.islandOsd !== false
                                                  ? "Changes to volume, the microphone, brightness and night light show in the middle of the bar."
                                                  : "Changes show in a pop-up near the bottom of the screen."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["In the bar", "As a pop-up"]
                                                    current: app.cfg.islandOsd !== false ? 0 : 1
                                                    onPicked: i => app.setting("islandOsd", i === 0)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Popups" }

                                        Card {
                                            app: rootV.app
                                            title: "Popup duration"
                                            desc: "How long a notification stays before it goes to the sidebar. Critical ones stay twice as long, and hovering pauses the countdown."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 2
                                                    to: 20
                                                    tick: 6
                                                    step: 0.5
                                                    value: app.notifMs / 1000
                                                    label: (Math.round(value * 2) / 2) + " s"
                                                    onMoved: v => app.setting("notifMs",
                                                                              Math.round(v * 2) * 500)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.notifMs === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("notifMs")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "On-screen indicators" }

                                        Card {
                                            app: rootV.app
                                            title: "Volume indicator"
                                            desc: "How long the volume indicator stays up after the level changes."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0.5
                                                    to: 5
                                                    tick: 1.4
                                                    step: 0.1
                                                    value: app.osdMs / 1000
                                                    label: value.toFixed(1) + " s"
                                                    onMoved: v => app.setting("osdMs",
                                                                              Math.round(v * 10) * 100)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.osdMs === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("osdMs")
                                                }
                                            ]
                                        }
                                    }

                                    // ================= IDLE =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 8
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "When you step away" }

                                        Card {
                                            app: rootV.app
                                            title: "Lock the screen"
                                            desc: "Minutes without input before the lock screen comes up. Drag to the far left for never."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 60
                                                    tick: 5
                                                    step: 1
                                                    value: app.idleLockMin
                                                    label: Math.round(value) === 0 ? "Never"
                                                         : Math.round(value) + " min"
                                                    onMoved: v => app.setting("idleLockMin", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.idleLockMin === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("idleLockMin")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Turn screens off"
                                            desc: "Minutes before both monitors go dark. Any key or mouse movement brings them back."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 60
                                                    tick: 10
                                                    step: 1
                                                    value: app.idleScreenMin
                                                    label: Math.round(value) === 0 ? "Never"
                                                         : Math.round(value) + " min"
                                                    onMoved: v => app.setting("idleScreenMin", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.idleScreenMin === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("idleScreenMin")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Sleep"
                                            desc: "Minutes before the PC suspends. The screen locks first, so it wakes to the lock screen."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 60
                                                    tick: 0
                                                    step: 1
                                                    value: app.idleSleepMin
                                                    label: Math.round(value) === 0 ? "Never"
                                                         : Math.round(value) + " min"
                                                    onMoved: v => app.setting("idleSleepMin", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.idleSleepMin === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("idleSleepMin")
                                                }
                                            ]
                                        }
                                    }

                                    // ================= DISPLAYS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 9
                                        spacing: 4

                                        // the confirmation, shown after Apply
                                        Card {
                                            app: rootV.app
                                            visible: app.revertLeft > 0
                                            color: Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.18)
                                            title: "Keep these display settings?"
                                            desc: "Reverting to the previous settings in " + app.revertLeft
                                                  + (app.revertLeft === 1 ? " second." : " seconds.")
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Revert", "Keep"]
                                                    current: 1
                                                    onPicked: i => i === 1 ? app.keepDisplays() : app.revertDisplays()
                                                }
                                            ]
                                        }

                                        Repeater {
                                            model: app.monInfo
                                            delegate: ColumnLayout {
                                                id: monSec
                                                required property var modelData
                                                readonly property var d: win.draft[modelData.name] ?? null
                                                Layout.fillWidth: true
                                                spacing: 4

                                                SectionLabel {
                                                    app: rootV.app
                                                    text: monSec.modelData.name
                                                          + (monSec.modelData.name === win.mainMon ? ", main" : "")
                                                }

                                                Card {
                                                    app: rootV.app
                                                    title: monSec.modelData.desc || monSec.modelData.name
                                                    desc: "Running at " + monSec.modelData.w + "\u00d7" + monSec.modelData.h
                                                          + ", " + Math.round(monSec.modelData.hz) + " Hz, "
                                                          + Math.round(monSec.modelData.scale * 100) + "% scale."

                                                    Text {
                                                        text: "Resolution"
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                        font.bold: true
                                                        Layout.topMargin: 4
                                                    }
                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Repeater {
                                                            model: win.resList(monSec.modelData)
                                                            delegate: Chip {
                                                                required property var modelData
                                                                app: rootV.app
                                                                text: modelData.w + "\u00d7" + modelData.h
                                                                selected: monSec.d !== null && monSec.d.res === modelData.key
                                                                onPicked: win.setDraft(monSec.modelData.name, "res", modelData.key)
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        text: "Refresh rate"
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                        font.bold: true
                                                        Layout.topMargin: 6
                                                    }
                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Repeater {
                                                            model: monSec.d ? win.rateList(monSec.modelData, monSec.d.res) : []
                                                            delegate: Chip {
                                                                required property var modelData
                                                                app: rootV.app
                                                                text: (Math.round(modelData.hz * 100) / 100) + " Hz"
                                                                selected: monSec.d !== null && monSec.d.mode === modelData.mode
                                                                onPicked: win.setDraft(monSec.modelData.name, "mode", modelData.mode)
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        visible: app.monBus[monSec.modelData.name] !== undefined
                                                        text: "Brightness"
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                        font.bold: true
                                                        Layout.topMargin: 6
                                                    }
                                                    Slider {
                                                        app: rootV.app
                                                        visible: app.monBus[monSec.modelData.name] !== undefined
                                                        accent: rootV.app.cYellow
                                                        from: 0
                                                        to: 100
                                                        step: 5
                                                        value: app.bright[monSec.modelData.name] ?? 0
                                                        label: Math.round(value) + "%"
                                                        onMoved: v => app.setBright(monSec.modelData.name, v)
                                                    }

                                                    Text {
                                                        text: "Scale"
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                        font.bold: true
                                                        Layout.topMargin: 6
                                                    }
                                                    Seg {
                                                        app: rootV.app
                                                        options: win.scales.map(x => Math.round(x * 100) + "%")
                                                        current: monSec.d ? win.scales.findIndex(x => Math.abs(x - monSec.d.scale) < 0.01) : -1
                                                        onPicked: i => win.setDraft(monSec.modelData.name, "scale", win.scales[i])
                                                    }
                                                }
                                            }
                                        }

                                        SectionLabel {
                                            app: rootV.app
                                            visible: app.monInfo.length > 1
                                            text: "Main monitor"
                                        }

                                        Card {
                                            app: rootV.app
                                            visible: app.monInfo.length > 1
                                            title: "Shell lives on"
                                            desc: "The monitor with the bar, dock, sidebar, notifications and panels."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: app.monInfo.map(m => m.name)
                                                    current: app.monInfo.map(m => m.name).indexOf(app.mainScreen)
                                                    onPicked: i => app.setting("mainScreen", app.monInfo[i].name)
                                                }
                                            ]
                                        }

                                        SectionLabel {
                                            app: rootV.app
                                            visible: app.monInfo.length === 2
                                            text: "Arrangement"
                                        }

                                        Card {
                                            app: rootV.app
                                            visible: app.monInfo.length === 2
                                            title: "Second screen"
                                            desc: "Where the other monitor sits relative to " + win.mainMon
                                                  + ". Positions are worked out from the resolutions and scales, so the screens always meet edge to edge."

                                            Seg {
                                                app: rootV.app
                                                options: ["Above", "Below", "Left", "Right"]
                                                current: ["above", "below", "left", "right"].indexOf(win.arrange)
                                                onPicked: i => win.arrange = ["above", "below", "left", "right"][i]
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            visible: app.revertLeft === 0
                                            title: win.draftDirty() ? "Ready to apply" : "No changes"
                                            desc: "Nothing changes until you apply. You then have 15 seconds to keep the new settings before they revert on their own."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: win.draftDirty() ? ["Undo changes", "Apply"] : ["Apply"]
                                                    onPicked: i => {
                                                        if (win.draftDirty() && i === 0) win.loadDraft()
                                                        else if (win.draftDirty()) win.applyDraft()
                                                    }
                                                }
                                            ]
                                        }
                                    }

                                    // ================= KEYBOARD =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 10
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Key repeat" }

                                        Card {
                                            app: rootV.app
                                            title: "Repeat delay"
                                            desc: "How long a key is held before it starts repeating."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 150
                                                    to: 1000
                                                    tick: 600
                                                    step: 25
                                                    value: app.cfg.repeatDelay
                                                    label: Math.round(value) + " ms"
                                                    onMoved: v => app.setting("repeatDelay", Math.round(v / 25) * 25)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.repeatDelay === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("repeatDelay")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Repeat rate"
                                            desc: "How many times a second a held key repeats once it starts."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 10
                                                    to: 60
                                                    tick: 25
                                                    step: 1
                                                    value: app.cfg.repeatRate
                                                    label: Math.round(value) + " per second"
                                                    onMoved: v => app.setting("repeatRate", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.repeatRate === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("repeatRate")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Try it"
                                            desc: "Click in the box and hold a key. Changes above apply a moment after you set them."

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 42
                                                radius: 12
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                border.width: tryIn.activeFocus ? 2 : 0
                                                border.color: app.cBlue

                                                TextInput {
                                                    id: tryIn
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    color: app.cFg
                                                    selectionColor: app.cBlue
                                                    font.family: "Inter"
                                                    font.pixelSize: app.fs(13)
                                                    clip: true
                                                    Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }

                                                    Text {
                                                        visible: !tryIn.text && !tryIn.activeFocus
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "Hold a key here"
                                                        color: app.cFaint
                                                        font: tryIn.font
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ================= MOUSE =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 11
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Pointer" }

                                        Card {
                                            app: rootV.app
                                            title: "Pointer speed"
                                            desc: "Faster or slower than the mouse's own speed. The middle leaves it unchanged."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: -1
                                                    to: 1
                                                    origin: 0
                                                    tick: 0
                                                    step: 0.05
                                                    value: app.cfg.sensitivity
                                                    label: Math.abs(value) < 0.025 ? "Unchanged" : (value > 0 ? "+" : "") + value.toFixed(2)
                                                    onMoved: v => app.setting("sensitivity", Math.round(v * 20) / 20)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.sensitivity === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("sensitivity")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Acceleration"
                                            desc: "Adaptive speeds the pointer up on quick flicks. Flat moves it the same distance however fast you move, which most people prefer for games."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Adaptive", "Flat"]
                                                    current: app.cfg.accelFlat === true ? 1 : 0
                                                    onPicked: i => app.setting("accelFlat", i === 1)
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Scrolling and focus" }

                                        Card {
                                            app: rootV.app
                                            title: "Natural scrolling"
                                            desc: "Content moves the way your finger does, like a phone. Off is the traditional wheel direction."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.naturalScroll === true ? 1 : 0
                                                    onPicked: i => app.setting("naturalScroll", i === 1)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Window focus"
                                            desc: "Which window receives your typing. On click still scrolls whatever is under the pointer."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Follows mouse", "On click"]
                                                    current: app.cfg.followMouse === false ? 1 : 0
                                                    onPicked: i => app.setting("followMouse", i === 0)
                                                }
                                            ]
                                        }
                                    }

                                    // ================= WEATHER =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 16
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Location" }

                                        Card {
                                            app: rootV.app
                                            title: app.wxPlace
                                            desc: app.wxOk
                                                  ? "Now " + app.wxTemp + ", " + app.wxCond.toLowerCase()
                                                    + ". Search for a city below to change it."
                                                  : "Search for a city below to change it."

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                implicitHeight: 38
                                                radius: 19
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                border.width: placeIn.activeFocus ? 1 : 0
                                                border.color: app.cBlue

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 8
                                                    Text {
                                                        text: "search"
                                                        color: app.cFaint
                                                        font.family: "Material Symbols Rounded"
                                                        font.pixelSize: app.fs(14)
                                                    }
                                                    TextInput {
                                                        id: placeIn
                                                        Layout.fillWidth: true
                                                        color: app.cFg
                                                        selectionColor: app.cBlue
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                        clip: true
                                                        onAccepted: app.searchPlace(text)
                                                        Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }
                                                        Text {
                                                            visible: !placeIn.text
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "Type a city, then Enter"
                                                            color: app.cFaint
                                                            font: placeIn.font
                                                        }
                                                    }
                                                    Text {
                                                        visible: app.wxSearching
                                                        text: "Searching\u2026"
                                                        color: app.cFaint
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(11)
                                                    }
                                                }
                                            }

                                            Repeater {
                                                model: app.wxResults
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.name
                                                    desc: modelData.where
                                                    selected: false
                                                    onChosen: { app.setPlace(modelData); placeIn.text = "" }
                                                }
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Units" }

                                        Card {
                                            app: rootV.app
                                            title: "Temperature and wind"
                                            desc: "Fahrenheit with miles per hour, or Celsius with kilometres per hour."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["\u00b0F, mph", "\u00b0C, km/h"]
                                                    current: app.wxMetric ? 1 : 0
                                                    onPicked: i => app.setting("wxUnits", i === 1 ? "C" : "F")
                                                }
                                            ]
                                        }
                                    }

                                    // ================= CALENDAR =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 17
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Holidays" }

                                        Card {
                                            app: rootV.app
                                            title: "Show holidays"
                                            desc: "Tints the day behind major US holidays and names them when you select the day."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.calHolidays ? 1 : 0
                                                    onPicked: i => app.setting("calHolidays", i === 1)
                                                }
                                            ]
                                        }


                                        SectionLabel { app: rootV.app; text: "Layout" }

                                        Card {
                                            app: rootV.app
                                            title: "Week starts on"
                                            desc: "The first column of the calendar in the sidebar."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Sunday", "Monday"]
                                                    current: app.calWeekStart
                                                    onPicked: i => app.setting("calWeekStart", i)
                                                }
                                            ]
                                        }
                                    }

                                    // ================= ABOUT =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 18
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "This machine" }

                                        Card {
                                            app: rootV.app
                                            title: app.aboutInfo.host || "\u2026"
                                            desc: app.aboutInfo.os || ""

                                            Repeater {
                                                model: [
                                                    { k: "CPU",        v: (app.aboutInfo.cpu || "") + (app.aboutInfo.cores ? ", " + app.aboutInfo.cores + " threads" : "") },
                                                    { k: "GPU",        v: app.aboutInfo.gpu || "" },
                                                    { k: "Memory",     v: app.aboutInfo.ram || "" },
                                                    { k: "Kernel",     v: app.aboutInfo.kernel || "" },
                                                    { k: "Uptime",     v: app.aboutInfo.uptime || "" },
                                                    { k: "Displays",   v: app.monInfo.map(m => m.name + " " + m.w + "\u00d7" + m.h + " at " + Math.round(m.hz) + " Hz").join(", ") }
                                                ]
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    visible: modelData.v !== ""
                                                    spacing: 12
                                                    Text {
                                                        Layout.preferredWidth: 90
                                                        text: modelData.k
                                                        color: app.cDim
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.v
                                                        color: app.cFg
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Software" }

                                        Card {
                                            app: rootV.app
                                            title: "Desktop"
                                            desc: "Hyprland " + (app.aboutInfo.hyprland || "?")
                                                  + ", " + (app.aboutInfo.quickshell || "Quickshell")
                                                  + (app.aboutInfo.shell ? ", " + app.aboutInfo.shell + " shell" : "")
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Copy details", "Open config"]
                                                    onPicked: i => {
                                                        const a = app.aboutInfo
                                                        if (i === 0) {
                                                            const lines = [a.host, a.os, "CPU: " + a.cpu, "GPU: " + a.gpu,
                                                                           "RAM: " + a.ram, "Kernel: " + a.kernel,
                                                                           "Hyprland " + a.hyprland, a.quickshell]
                                                            app.run("printf '%s\\n' " + lines.map(x =>
                                                                "'" + String(x ?? "").replace(/'/g, "") + "'").join(" ") + " | wl-copy")
                                                        }
                                                        else
                                                            app.run("xdg-open \"$HOME/.config/quickshell\"")
                                                    }
                                                }
                                            ]
                                        }
                                    }

                                    // ================= WIDGETS =================
                                    ColumnLayout {
                                        id: widgetsPage
                                        width: parent.width
                                        visible: win.page === 19
                                        spacing: 4

                                        readonly property var screenNames: Quickshell.screens.map(s => s.name)

                                        Card {
                                            app: rootV.app
                                            title: "Arrange widgets"
                                            desc: "Lifts your widgets above your windows so you can drag them into place. Press Done or Esc when you're finished."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Arrange"]
                                                    onPicked: { app.settingsShown = false; app.widgetEdit = true }
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Add a widget" }

                                        Card {
                                            app: rootV.app
                                            title: "Available"
                                            desc: "Each one appears near the top left of the screen you pick. Add the same one more than once if you like."

                                            Repeater {
                                                model: app.widgetTypes
                                                delegate: RowLayout {
                                                    id: addRow
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: 4
                                                    spacing: 10
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        Text {
                                                            text: addRow.modelData.name
                                                            color: app.cFg
                                                            font.family: "Inter"
                                                            font.pixelSize: app.fs(13)
                                                            font.bold: true
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: addRow.modelData.desc
                                                            color: app.cDim
                                                            font.family: "Inter"
                                                            font.pixelSize: app.fs(11)
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    Seg {
                                                        app: rootV.app
                                                        options: widgetsPage.screenNames.map(n => "Add to " + n)
                                                        onPicked: i => app.addWidget(addRow.modelData.type,
                                                                      widgetsPage.screenNames[i])
                                                    }
                                                }
                                            }
                                        }

                                        Card {
                                            id: arrangeCard
                                            app: rootV.app
                                            property string note: ""
                                            title: "Keep clear of the wallpaper"
                                            desc: note !== "" ? note
                                                  : !app.nativeOk ? "Needs the native plugin, which isn't built: re-run the installer."
                                                  : app.cfg.widgetsAuto === true
                                                  ? "Each new wallpaper moves your widgets to its calmest places (sky, walls, soft blur), away from faces, buildings and busy detail. On a wallpaper that's busy everywhere, they stay put."
                                                  : "Widgets stay wherever you put them. Turn this on to have them find the calm parts of each new wallpaper."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.cfg.widgetsAuto === true ? 1 : 0
                                                    onPicked: i => { app.setting("widgetsAuto", i === 1); if (i === 1) app.arrangeWidgets() }
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Arrange now"]
                                                    current: -1
                                                    onPicked: {
                                                        const n = app.arrangeWidgets()
                                                        arrangeCard.note = n < 0 ? "Couldn't read the wallpaper yet." : n === 0
                                                            ? "Nothing to move: they're already in the calmest places, or this wallpaper has none."
                                                            : (n === 1 ? "Moved 1 widget." : "Moved " + n + " widgets.")
                                                        noteClear.restart()
                                                    }
                                                }
                                            ]
                                            Timer { id: noteClear; interval: 5000; onTriggered: arrangeCard.note = "" }
                                        }

                                        SectionLabel { app: rootV.app; text: "On your desktop" }

                                        Card {
                                            app: rootV.app
                                            visible: app.widgets.length === 0
                                            title: "No widgets yet"
                                            desc: "Add one above, then use Arrange to put it where you want it."
                                        }

                                        Repeater {
                                            model: app.widgets
                                            delegate: Card {
                                                id: wCard
                                                required property var modelData
                                                app: rootV.app
                                                title: (app.widgetTypes.find(t => t.type === modelData.type) || { name: modelData.type }).name
                                                desc: "On " + (modelData.screen || app.mainScreen)
                                                trailing: [
                                                    Seg {
                                                        app: rootV.app
                                                        visible: Quickshell.screens.length > 1
                                                        options: Quickshell.screens.map(s => s.name)
                                                        current: Quickshell.screens.map(s => s.name).indexOf(wCard.modelData.screen || app.mainScreen)
                                                        onPicked: i => app.updateWidget(wCard.modelData.id,
                                                                      { screen: Quickshell.screens[i].name })
                                                    },
                                                    Seg {
                                                        app: rootV.app
                                                        options: ["Remove"]
                                                        onPicked: app.removeWidget(wCard.modelData.id)
                                                    }
                                                ]

                                                // a note's text, edited in place
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    visible: wCard.modelData.type === "note"
                                                    implicitHeight: Math.max(38, noteEdit.contentHeight + 20)
                                                    radius: 14
                                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                    border.width: noteEdit.activeFocus ? 1 : 0
                                                    border.color: app.cBlue
                                                    TextEdit {
                                                        id: noteEdit
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        text: wCard.modelData.text || ""
                                                        color: app.cFg
                                                        selectionColor: app.cBlue
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                        wrapMode: TextEdit.Wrap
                                                        // saved when you click away
                                                        onActiveFocusChanged: if (!activeFocus && text !== (wCard.modelData.text || ""))
                                                            app.updateWidget(wCard.modelData.id, { text: text })
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ================= LOCK SCREEN =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 20
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Login screen" }

                                        Card {
                                            app: rootV.app
                                            title: "Background"
                                            desc: app.loginBusy ? "Setting it\u2026"
                                                  : app.loginError !== "" ? app.loginError
                                                  : app.loginFollows
                                                  ? "The wallpaper and colours of whoever signed in last: on your own computer, always your current look."
                                                  : "A background of its own, whoever signed in last. Its colours come from it."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Your wallpaper", "Its own"]
                                                    current: app.loginFollows ? 0 : 1
                                                    onPicked: i => app.setLoginFollow(i === 0)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Preview"]
                                                    current: -1
                                                    onPicked: app.previewLogin()
                                                }
                                            ]
                                        }
                                        // Ether Nightfall, then your wallpapers (for "Its own")
                                        Flow {
                                            visible: !app.loginFollows
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 4
                                            Layout.bottomMargin: 10
                                            spacing: 8
                                            Repeater {
                                                model: [app.loginDefault].concat(app.wallpapers.slice(0, 23))
                                                delegate: Rectangle {
                                                    id: lthumb
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool isCurrent: index === 0 ? !app.cfg.loginBackground
                                                                                                  : app.cfg.loginBackground === modelData
                                                    width: 132; height: 74; radius: 10
                                                    color: app.cCard
                                                    border.width: isCurrent ? 3 : 0
                                                    border.color: app.cBlue
                                                    clip: true
                                                    Image {
                                                        anchors.fill: parent
                                                        anchors.margins: lthumb.isCurrent ? 3 : 0
                                                        source: "file://" + lthumb.modelData
                                                        sourceSize.width: 264
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                    }
                                                    Rectangle {
                                                        visible: lthumb.index === 0
                                                        anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                                                        width: lbl.implicitWidth + 12; height: 18; radius: 9
                                                        color: Qt.rgba(0, 0, 0, 0.55)
                                                        Text { id: lbl; anchors.centerIn: parent; text: "Ether default"; color: "white"; font.family: "Inter"; font.pixelSize: app.fs(10) }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: lthumb.isCurrent || app.loginBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                        onClicked: if (!lthumb.isCurrent && !app.loginBusy) app.setLoginBackground(lthumb.modelData)
                                                    }
                                                }
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Preview"
                                            desc: "Locks the screen now so you can see your changes. Your password unlocks it as usual. The clock follows Bar, Time format."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Lock now"]
                                                    onPicked: { app.settingsShown = false; app.run("sleep 0.4; loginctl lock-session") }
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Background" }

                                        Card {
                                            app: rootV.app
                                            title: "Blur"
                                            desc: "How soft your wallpaper is behind the clock. Zero shows it sharp."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 0
                                                    to: 12
                                                    step: 1
                                                    value: app.lockBlur
                                                    label: Math.round(value) === 0 ? "Sharp" : Math.round(value)
                                                    onMoved: v => app.setting("lockBlur", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.lockBlur === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("lockBlur")
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Brightness"
                                            desc: "How bright the wallpaper is kept. Lower makes the clock and text stand out more."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: 20
                                                    to: 100
                                                    step: 5
                                                    value: app.lockDim
                                                    label: Math.round(value) + "%"
                                                    onMoved: v => app.setting("lockDim", Math.round(v))
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Default"]
                                                    current: app.cfgUser.lockDim === undefined ? 0 : -1
                                                    onPicked: app.resetSetting("lockDim")
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Text" }

                                        Card {
                                            app: rootV.app
                                            title: "Greeting"
                                            desc: app.lockGreetMode === "time"
                                                  ? "Good morning, afternoon, evening or night, with your user name."
                                                  : app.lockGreetMode === "custom"
                                                  ? "Your own line under the clock. Type it below and press Enter."
                                                  : "No line under the clock."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Time of day", "Custom", "Off"]
                                                    current: ["time", "custom", "off"].indexOf(app.lockGreetMode)
                                                    onPicked: i => app.setting("lockGreetMode", ["time", "custom", "off"][i])
                                                }
                                            ]

                                            Rectangle {
                                                Layout.fillWidth: true
                                                visible: app.lockGreetMode === "custom"
                                                implicitHeight: 38
                                                radius: 19
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                border.width: greetIn.activeFocus ? 1 : 0
                                                border.color: app.cBlue
                                                TextInput {
                                                    id: greetIn
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    text: app.lockGreetText
                                                    color: app.cFg
                                                    selectionColor: app.cBlue
                                                    font.family: "Inter"
                                                    font.pixelSize: app.fs(12)
                                                    clip: true
                                                    maximumLength: 80
                                                    onAccepted: { app.setting("lockGreetText", text); keys.forceActiveFocus() }
                                                    onActiveFocusChanged: if (!activeFocus && text !== app.lockGreetText)
                                                        app.setting("lockGreetText", text)
                                                    Text {
                                                        visible: !greetIn.text
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "Welcome back"
                                                        color: app.cFaint
                                                        font: greetIn.font
                                                    }
                                                }
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Now playing"
                                            desc: "Shows the current track near the bottom while music is playing."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: app.lockMedia ? 1 : 0
                                                    onPicked: i => app.setting("lockMedia", i === 1)
                                                }
                                            ]
                                        }
                                    }

                                    // ================= AI ASSISTANT =================
                                    ColumnLayout {
                                        id: aiPage
                                        width: parent.width
                                        visible: win.page === 22
                                        spacing: 4
                                        readonly property string p: app.aiProvider
                                        readonly property var info: app.aiProviders[p]
                                        onVisibleChanged: if (visible) app.refreshAiKeys()

                                        SectionLabel { app: rootV.app; text: "Provider" }

                                        Card {
                                            app: rootV.app
                                            title: "Who answers"
                                            desc: "Your messages are sent to this company, using your own API key. Each has its own key; switching keeps the others."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Anthropic", "Google", "OpenAI"]
                                                    current: ["anthropic", "gemini", "openai"].indexOf(aiPage.p)
                                                    onPicked: i => app.setting("aiProvider", ["anthropic", "gemini", "openai"][i])
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: aiPage.info.name + " (" + aiPage.info.product + ")" }

                                        Card {
                                            app: rootV.app
                                            title: "API key"
                                            desc: app.aiKeys[aiPage.p]
                                                  ? "A key is saved. It's kept in its own file that only you can read, never in the settings file."
                                                  : "Create one at " + aiPage.info.keyUrl + ", then paste it here and press Save."

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 42
                                                    radius: 12
                                                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                    border.width: keyIn.activeFocus ? 2 : 0
                                                    border.color: app.cBlue
                                                    TextInput {
                                                        id: keyIn
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 14
                                                        anchors.rightMargin: 14
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        echoMode: TextInput.Password
                                                        color: app.cFg
                                                        selectionColor: app.cBlue
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(13)
                                                        clip: true
                                                        Keys.onReturnPressed: if (text.trim()) { app.saveAiKey(aiPage.p, text); text = "" }
                                                        Text {
                                                            visible: !keyIn.text && !keyIn.activeFocus
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: app.aiKeys[aiPage.p] ? "Paste a new key to replace it" : "Paste your API key"
                                                            color: app.cFaint
                                                            font: keyIn.font
                                                        }
                                                    }
                                                }
                                                Rectangle {
                                                    implicitWidth: saveT.implicitWidth + 28
                                                    implicitHeight: 42
                                                    radius: 12
                                                    color: keyIn.text.trim() ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                    Text {
                                                        id: saveT
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
                                                        onClicked: if (keyIn.text.trim()) { app.saveAiKey(aiPage.p, keyIn.text); keyIn.text = "" }
                                                    }
                                                }
                                                Rectangle {
                                                    visible: app.aiKeys[aiPage.p] === true
                                                    implicitWidth: remT.implicitWidth + 28
                                                    implicitHeight: 42
                                                    radius: 12
                                                    color: remHov.hovered ? app.cRed : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                    HoverHandler { id: remHov }
                                                    Text {
                                                        id: remT
                                                        anchors.centerIn: parent
                                                        text: "Remove"
                                                        color: remHov.hovered ? app.cOnAccent : app.cFg
                                                        font.family: "Inter"
                                                        font.weight: Font.DemiBold
                                                        font.pixelSize: app.fs(13)
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: app.removeAiKey(aiPage.p)
                                                    }
                                                }
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Model"
                                            desc: "Which of " + aiPage.info.name + "'s models to use. Leave empty for " + aiPage.info.model + ". Changes apply to your next message."

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 42
                                                radius: 12
                                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                                border.width: modelIn.activeFocus ? 2 : 0
                                                border.color: app.cBlue
                                                TextInput {
                                                    id: modelIn
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    color: app.cFg
                                                    selectionColor: app.cBlue
                                                    font.family: "Inter"
                                                    font.pixelSize: app.fs(13)
                                                    clip: true
                                                    // only letters, numbers and . : _ - reach the request
                                                    validator: RegularExpressionValidator { regularExpression: /[\w.:-]*/ }
                                                    text: app.cfg["aiModel_" + aiPage.p] || ""
                                                    onEditingFinished: {
                                                        const v = text.trim()
                                                        if (v === "") app.resetSetting("aiModel_" + aiPage.p)
                                                        else app.setting("aiModel_" + aiPage.p, v)
                                                    }
                                                    Text {
                                                        visible: !modelIn.text && !modelIn.activeFocus
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: aiPage.info.model
                                                        color: app.cFaint
                                                        font: modelIn.font
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ================= DEFAULT APPS =================
                                    ColumnLayout {
                                        id: appsPage
                                        width: parent.width
                                        visible: win.page === 21
                                        spacing: 4

                                        // installed apps as plain values, read from their
                                        // desktop files by category
                                        function listFor(cat) {
                                            const seen = {}
                                            const out = []
                                            for (const e of DesktopEntries.applications.values) {
                                                if (!e || e.noDisplay) continue
                                                const cats = e.categories || []
                                                if (cats.indexOf(cat) === -1) continue
                                                const id = String(e.id).endsWith(".desktop") ? String(e.id) : e.id + ".desktop"
                                                if (seen[id]) continue
                                                seen[id] = true
                                                out.push({ id: id, name: String(e.name), cmd: app.entryCmd(e) })
                                            }
                                            return out.sort((a, b) => a.name.localeCompare(b.name))
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Terminal"
                                            desc: "Opens on SUPER+T, and wherever the shell opens a terminal, such as clicking CPU in the bar."

                                            Repeater {
                                                model: appsPage.listFor("TerminalEmulator")
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.name
                                                    desc: modelData.cmd
                                                    selected: (app.cfg.appTerminal || "kitty.desktop") === modelData.id
                                                    onChosen: app.setDefaultApp("terminal", modelData)
                                                }
                                            }
                                            Text {
                                                visible: appsPage.listFor("TerminalEmulator").length === 0
                                                text: "None installed that declare themselves as one."
                                                color: app.cFaint
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "File manager"
                                            desc: "Opens on SUPER+E, and becomes the default for opening folders everywhere."

                                            Repeater {
                                                model: appsPage.listFor("FileManager")
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.name
                                                    desc: modelData.cmd
                                                    selected: app.xdgDefaults.files === modelData.id
                                                    onChosen: app.setDefaultApp("files", modelData)
                                                }
                                            }
                                            Text {
                                                visible: appsPage.listFor("FileManager").length === 0
                                                text: "None installed that declare themselves as one."
                                                color: app.cFaint
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Web browser"
                                            desc: "The default for opening links from any app."

                                            Repeater {
                                                model: appsPage.listFor("WebBrowser")
                                                delegate: ChoiceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    title: modelData.name
                                                    desc: modelData.cmd
                                                    selected: app.xdgDefaults.browser === modelData.id
                                                    onChosen: app.setDefaultApp("browser", modelData)
                                                }
                                            }
                                            Text {
                                                visible: appsPage.listFor("WebBrowser").length === 0
                                                text: "None installed that declare themselves as one."
                                                color: app.cFaint
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(11)
                                            }
                                        }
                                    }

                                    // ================= OUTPUT =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 12
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Level" }

                                        Card {
                                            app: rootV.app
                                            title: "Volume"
                                            desc: win.nodeName(win.sink)
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    to: win.maxVol
                                                    tick: 1
                                                    value: win.vol
                                                    muted: win.sinkAu?.muted ?? false
                                                    label: muted ? "Muted" : win.pct(value)
                                                    onMoved: v => win.setMaster(win.sinkAu, v)
                                                },
                                                IconBtn {
                                                    app: rootV.app
                                                    accent: rootV.app.cRed
                                                    active: win.sinkAu?.muted ?? false
                                                    glyph: active ? "volume_off" : "volume_up"
                                                    onClicked: if (win.sinkAu)
                                                        win.sinkAu.muted = !win.sinkAu.muted
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            visible: win.sinkCh === 2
                                            title: "Balance"
                                            desc: "Shifts sound between the left and right channels."
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    from: -1
                                                    to: 1
                                                    origin: 0
                                                    tick: 0
                                                    step: 0.05
                                                    value: win.bal
                                                    label: Math.abs(value) < 0.02 ? "Centre"
                                                         : (value < 0 ? "Left " : "Right ")
                                                           + Math.round(Math.abs(value) * 100)
                                                    onMoved: v => win.setBalance(v)
                                                },
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Centre"]
                                                    current: Math.abs(win.bal) < 0.02 ? 0 : -1
                                                    onPicked: win.setBalance(0)
                                                }
                                            ]
                                        }

                                        Card {
                                            app: rootV.app
                                            title: "Allow above 100%"
                                            desc: "Lets every volume in this panel go to 150%. Loud sources can clip."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Off", "On"]
                                                    current: win.boost ? 1 : 0
                                                    onPicked: i => {
                                                        win.boost = i === 1
                                                        if (!win.boost && win.vol > 1)
                                                            win.setMaster(win.sinkAu, 1)
                                                    }
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Device" }

                                        Card {
                                            app: rootV.app
                                            title: "Output device"
                                            desc: "Apps follow the device in use, unless you have moved one yourself."

                                            Repeater {
                                                model: Pipewire.nodes
                                                delegate: DeviceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    node: modelData
                                                    visible: win.isOutDev(modelData)
                                                    isDefault: modelData === win.sink
                                                    onChosen: Pipewire.preferredDefaultAudioSink = modelData
                                                }
                                            }
                                        }

                                        SectionLabel { app: rootV.app; text: "Advanced" }

                                        Card {
                                            app: rootV.app
                                            title: "Ports and profiles"
                                            desc: "Switching a card's profile or port isn't covered here yet."
                                            trailing: [
                                                Seg {
                                                    app: rootV.app
                                                    options: ["Open pavucontrol"]
                                                    onPicked: app.run("pavucontrol")
                                                }
                                            ]
                                        }
                                    }

                                    // ================= APPLICATIONS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 13
                                        spacing: 4

                                        Card {
                                            app: rootV.app
                                            visible: win.count(win.isPlay) === 0
                                            title: "Nothing is playing"
                                            desc: "Apps appear here while they play sound, each with its own volume."
                                        }

                                        Repeater {
                                            model: Pipewire.nodes
                                            delegate: StreamCard {
                                                required property var modelData
                                                app: rootV.app
                                                node: modelData
                                                visible: win.isPlay(modelData)
                                                maxVol: win.maxVol
                                            }
                                        }
                                    }

                                    // ================= INPUT =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 14
                                        spacing: 4

                                        SectionLabel { app: rootV.app; text: "Level" }

                                        Card {
                                            app: rootV.app
                                            title: "Microphone volume"
                                            desc: win.nodeName(win.source)
                                            trailing: [
                                                Slider {
                                                    app: rootV.app
                                                    accent: rootV.app.cTeal
                                                    to: win.maxVol
                                                    tick: 1
                                                    value: win.master(win.sourceAu)
                                                    muted: win.sourceAu?.muted ?? false
                                                    label: muted ? "Muted" : win.pct(value)
                                                    onMoved: v => win.setMaster(win.sourceAu, v)
                                                },
                                                IconBtn {
                                                    app: rootV.app
                                                    accent: rootV.app.cRed
                                                    active: win.sourceAu?.muted ?? false
                                                    glyph: active ? "mic_off" : "mic"
                                                    onClicked: if (win.sourceAu)
                                                        win.sourceAu.muted = !win.sourceAu.muted
                                                }
                                            ]
                                        }

                                        SectionLabel { app: rootV.app; text: "Device" }

                                        Card {
                                            app: rootV.app
                                            title: "Input device"
                                            desc: "The microphone apps record from by default."

                                            Repeater {
                                                model: Pipewire.nodes
                                                delegate: DeviceRow {
                                                    required property var modelData
                                                    app: rootV.app
                                                    node: modelData
                                                    isInput: true
                                                    accent: rootV.app.cTeal
                                                    visible: win.isInDev(modelData)
                                                    isDefault: modelData === win.source
                                                    onChosen: Pipewire.preferredDefaultAudioSource = modelData
                                                }
                                            }
                                        }
                                    }

                                    // ================= RECORDING APPS =================
                                    ColumnLayout {
                                        width: parent.width
                                        visible: win.page === 15
                                        spacing: 4

                                        Card {
                                            app: rootV.app
                                            visible: win.count(win.isRec) === 0
                                            title: "No app is recording"
                                            desc: "Apps appear here while they use a microphone, each with its own input level."
                                        }

                                        Repeater {
                                            model: Pipewire.nodes
                                            delegate: StreamCard {
                                                required property var modelData
                                                app: rootV.app
                                                node: modelData
                                                accent: rootV.app.cTeal
                                                visible: win.isRec(modelData)
                                                maxVol: win.maxVol
                                            }
                                        }
                                    }
                                }
                            }

                            // scroll position indicator
                            Rectangle {
                                visible: flick.contentHeight > flick.height
                                anchors.right: parent.right
                                width: 4
                                radius: 2
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                y: flick.visibleArea.yPosition * flick.height
                                height: Math.max(30, flick.visibleArea.heightRatio * flick.height)
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
