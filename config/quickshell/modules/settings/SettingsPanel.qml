import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import "../../lib/search.mjs" as SearchLib
import "../../lib/layout.mjs" as LayoutLib
import "../../lib/models.mjs" as Models
import "../../lib/keybinds.mjs" as Keybinds
import qs.modules.plugins
import qs.common.widgets

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
        // Built the first time it's opened, kept while it's in use, and
        // released a while after it closes (the Timer in its window).
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.settingsShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: win

        // Released 3 minutes after it closes (it's rarely open): its memory
        // back.  Opening it again builds it afresh, a moment's work.
        Timer {
            interval: 180000
            running: !app.settingsShown
            onTriggered: Qt.callLater(() => { perScreen.used = false })
        }
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

        // ---- Keybinds: waiting for a new shortcut ----
        // Hyprland switches to an empty keymap meanwhile (app.captureKeys), so
        // the keys arrive here; Escape, 10 seconds, or closing Settings stop it.
        property string kbCapture: ""
        property string kbError: ""
        function startKeyCapture(id) {
            kbError = ""
            kbCapture = id
            app.captureKeys(true)
            keys.forceActiveFocus()
            kbTimeout.restart()
        }
        function endKeyCapture() {
            if (kbCapture === "") return
            kbCapture = ""
            kbTimeout.stop()
            if (app.keysCapturing) app.captureKeys(false)
        }
        Timer { id: kbTimeout; interval: 10000; onTriggered: win.endKeyCapture() }
        Connections {
            target: app
            function onKeysCapturingChanged() { if (!app.keysCapturing && win.kbCapture !== "") { win.kbCapture = ""; kbTimeout.stop() } }
            function onSettingsShownChanged() { if (!app.settingsShown) win.endKeyCapture() }
            function onSettingsPageChanged() { win.endKeyCapture() }
        }
        // a key as Hyprland names it ("" for a modifier on its own).  With
        // SHIFT held, Qt reports the symbol; this gives back the key itself.
        function keyName(e) {
            const k = e.key
            if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
            if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
            if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1)
            const named = {}
            named[Qt.Key_Left] = "left"; named[Qt.Key_Right] = "right"; named[Qt.Key_Up] = "up"; named[Qt.Key_Down] = "down"
            named[Qt.Key_Tab] = "Tab"; named[Qt.Key_Backtab] = "Tab"; named[Qt.Key_Return] = "Return"; named[Qt.Key_Enter] = "Return"
            named[Qt.Key_Space] = "space"; named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End"
            named[Qt.Key_PageUp] = "Prior"; named[Qt.Key_PageDown] = "Next"; named[Qt.Key_Delete] = "Delete"
            named[Qt.Key_Insert] = "Insert"; named[Qt.Key_Backspace] = "BackSpace"; named[Qt.Key_Print] = "Print"
            named[Qt.Key_Comma] = "comma"; named[Qt.Key_Less] = "comma"; named[Qt.Key_Period] = "period"; named[Qt.Key_Greater] = "period"
            named[Qt.Key_Slash] = "slash"; named[Qt.Key_Question] = "slash"; named[Qt.Key_Semicolon] = "semicolon"; named[Qt.Key_Colon] = "semicolon"
            named[Qt.Key_Apostrophe] = "apostrophe"; named[Qt.Key_QuoteDbl] = "apostrophe"; named[Qt.Key_Minus] = "minus"; named[Qt.Key_Underscore] = "minus"
            named[Qt.Key_Equal] = "equal"; named[Qt.Key_Plus] = "equal"; named[Qt.Key_QuoteLeft] = "grave"; named[Qt.Key_AsciiTilde] = "grave"
            named[Qt.Key_BracketLeft] = "bracketleft"; named[Qt.Key_BraceLeft] = "bracketleft"
            named[Qt.Key_BracketRight] = "bracketright"; named[Qt.Key_BraceRight] = "bracketright"
            named[Qt.Key_Backslash] = "backslash"; named[Qt.Key_Bar] = "backslash"
            // SHIFT + a digit arrives as its symbol (on a US layout)
            const shifted = "!@#$%^&*()"
            if (e.text && shifted.indexOf(e.text) >= 0) return String((shifted.indexOf(e.text) + 1) % 10)
            return named[k] || ""
        }
        function takeKey(e) {
            if (e.key === Qt.Key_Escape && !(e.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier))) { endKeyCapture(); return }
            const name = keyName(e)
            if (name === "") return                                   // a modifier alone: wait for the key
            const mods = []
            if (e.modifiers & Qt.MetaModifier) mods.push("SUPER")
            if (e.modifiers & Qt.ControlModifier) mods.push("CTRL")
            if (e.modifiers & Qt.AltModifier) mods.push("ALT")
            if (e.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
            const combo = Keybinds.normalise(mods.concat([name]).join(" + "))
            if (!combo) { kbError = "That key can't be used for a shortcut"; return }
            const p = Keybinds.problem(combo)
            if (p) { kbError = p; return }
            const used = Keybinds.clash(kbCapture, combo, app.keybinds)
            if (used) { kbError = combo + " is already " + used + ": change that first, or press other keys"; return }
            app.setKeybind(kbCapture, combo)
            endKeyCapture()
        }

        // ---- search: every setting card on every page, by its title,
        // description, page and section (so new settings are found too)
        property string query: ""
        property var results: []
        property int resultIndex: 0
        onQueryChanged: runSearch()
        function searchIndex() {
            const out = []
            for (let i = 0; i < pagesCol.children.length; i++) {
                const pg = pagesCol.children[i]
                if (pg.pageNo === undefined) continue
                let section = ""
                const walk = it => {
                    for (let k = 0; k < it.children.length; k++) {
                        const c = it.children[k]
                        if (c.sectionLabel) { section = c.text; continue }
                        if (c.settingCard && c.title) {
                            out.push({ title: c.title, desc: c.desc, section: section,
                                       page: (win.pages[pg.pageNo] || {}).t || "", pageNo: pg.pageNo, item: c })
                        }
                        walk(c)
                    }
                }
                walk(pg)
            }
            return out
        }
        function runSearch() {
            results = query.trim() === "" ? [] : SearchLib.search(searchIndex(), query, 40)
            resultIndex = 0
        }
        // open its page, scroll it into view, outline it for a moment
        function openResult(r) {
            if (!r) return
            app.settingsPage = r.pageNo
            goTo.target = r.item
            goTo.restart()
        }
        Timer {
            id: goTo
            property var target: null
            interval: 60                    // once the page has laid out
            onTriggered: {
                if (!target) return
                const y = target.mapToItem(pagesCol, 0, 0).y - 16
                flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
                target.flash = true
            }
        }
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
            { t: "Dock",           d: "The window dock, along the bottom or down a side" },
            { t: "Notifications",  d: "Popups and on-screen indicators" },
            { t: "Idle",           d: "Locking, screens off and sleep when you step away" },
            { t: "Displays",       d: "Arrange your screens by dragging, and each one's resolution, refresh, scale and rotation" },
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
            { t: "AI assistant",   d: "Which AI answers in the assistant panel, and your key for it" },
            { t: "Plugins",        d: "Add-ons from other people (or you): bar items, launcher results, widgets and settings" },
            { t: "Keybinds",       d: "Every shortcut, and changing them" },
            { t: "Game overlay",   d: "Frame rate, GPU and CPU on top of your games, in your theme" }
        ]

        // (one handler only: a second one stops the whole panel loading)
        onPageChanged: {
            flick.contentY = 0
            if (page === 25) app.checkMango()          // Game overlay: is MangoHud there?
        }

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
                              scale: m.scale, x: m.x || 0, y: m.y || 0,
                              transform: m.transform || 0, vrr: m.vrr || 0 }
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
            // a new size (resolution, scale, rotation): the others settle
            // around the main monitor again, with no gap or overlap
            if (field === "res" || field === "mode" || field === "scale" || field === "transform")
                settleDraft(d)
            draft = d
        }
        // ---- the arrangement: each monitor's logical size and position ----
        function logicalOf(d) {
            const p = parseMode(d.mode)
            return p ? LayoutLib.logicalSize(p.w, p.h, d.scale, d.transform || 0) : { w: 0, h: 0 }
        }
        function settleDraft(d) {
            const mons = Object.keys(d).map(n => Object.assign({ name: n, x: d[n].x || 0, y: d[n].y || 0 }, logicalOf(d[n])))
            for (const m of LayoutLib.settle(mons, mainMon)) { d[m.name].x = m.x; d[m.name].y = m.y }
        }
        // the tiles for the drag area
        function monTiles() {
            return Object.keys(draft).map(n => {
                const d = draft[n], p = parseMode(d.mode)
                return Object.assign({ name: n, x: d.x || 0, y: d.y || 0, main: n === mainMon,
                                       label: d.res.replace("x", "\u00d7"),
                                       label2: (p ? Math.round(p.hz) + " Hz \u00b7 " : "") + Math.round(d.scale * 100) + "%" },
                                     logicalOf(d))
            })
        }
        // one dragged somewhere (already snapped): everything starts at 0,0 again
        function moveMon(name, x, y) {
            const d = JSON.parse(JSON.stringify(draft))
            if (!d[name]) return
            d[name].x = x; d[name].y = y
            const mons = LayoutLib.normalise(Object.keys(d).map(n => ({ name: n, x: d[n].x, y: d[n].y, w: 0, h: 0 })))
            for (const m of mons) { d[m.name].x = m.x; d[m.name].y = m.y }
            draft = d
        }
        property string selMon: ""
        function draftDirty() {
            for (const m of app.monInfo) {
                const d = draft[m.name]
                if (!d) continue
                if (d.res !== m.w + "x" + m.h || Math.abs(d.scale - m.scale) > 0.001) return true
                const p = parseMode(d.mode)
                if (p && Math.abs(p.hz - m.hz) > 0.5) return true
                if ((d.x || 0) !== (m.x || 0) || (d.y || 0) !== (m.y || 0)) return true
                if ((d.transform || 0) !== (m.transform || 0) || (d.vrr || 0) !== (m.vrr || 0)) return true
            }
            return false
        }
        // logical size, which is what positions are measured in
        function logical(name) {
            const d = draft[name]
            const p = d ? parseMode(d.mode) : null
            if (!p) return { w: 0, h: 0 }
            return { w: Math.round(p.w / d.scale), h: Math.round(p.h / d.scale) }
        }
        function applyDraft() {
            const out = {}
            for (const n of Object.keys(draft)) {
                const d = draft[n]
                out[n] = { mode: d.mode, position: Math.round(d.x || 0) + "x" + Math.round(d.y || 0), scale: d.scale,
                           transform: d.transform || 0, vrr: d.vrr || 0 }
            }
            app.applyDisplays(out, "custom")
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
                    // choosing a new shortcut: every key goes to that
                    if (win.kbCapture !== "") { win.takeKey(e); e.accepted = true; return }
                    if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) {
                        searchField.forceActiveFocus()
                    } else if (e.text && /^[a-zA-Z\u00c0-\u024f]$/.test(e.text) && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                        searchField.forceActiveFocus()
                        searchField.text += e.text
                    } else if (e.key === Qt.Key_Escape) {
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

                    // ---- search ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        implicitHeight: 38
                        radius: 19
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, searchField.activeFocus ? 0.12 : 0.07)
                        border.width: searchField.activeFocus ? 1 : 0
                        border.color: app.cBlue
                        Text {
                            id: searchGlyph
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            color: searchField.activeFocus ? app.cBlue : app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                        }
                        TextInput {
                            id: searchField
                            anchors { left: searchGlyph.right; leftMargin: 8; right: clearBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            color: app.cFg
                            selectionColor: app.cBlue
                            selectedTextColor: app.cOnAccent
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                            clip: true
                            onTextChanged: win.query = text
                            Keys.onPressed: e => {
                                if (e.key === Qt.Key_Down) win.resultIndex = Math.min(win.results.length - 1, win.resultIndex + 1)
                                else if (e.key === Qt.Key_Up) win.resultIndex = Math.max(0, win.resultIndex - 1)
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.openResult(win.results[win.resultIndex])
                                else if (e.key === Qt.Key_Escape) { if (text !== "") text = ""; else keys.forceActiveFocus() }
                                else return
                                e.accepted = true
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: parent.text === ""
                                text: "Search settings"
                                color: app.cFaint
                                font: parent.font
                            }
                        }
                        Text {
                            id: clearBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchField.text !== ""
                            text: "close"
                            color: app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 16
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: searchField.text = "" }
                        }
                    }

                    // ---- what matches, while searching (in place of the pages) ----
                    Flickable {
                        id: resultsFlick
                        visible: win.query.trim() !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: resultsCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ColumnLayout {
                            id: resultsCol
                            width: resultsFlick.width
                            spacing: 2
                            Text {
                                visible: win.results.length === 0
                                Layout.fillWidth: true
                                Layout.margins: 12
                                wrapMode: Text.WordWrap
                                text: "Nothing matches \u201c" + win.query.trim() + "\u201d"
                                color: app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(12)
                            }
                            Repeater {
                                model: ScriptModel { values: Models.keyed(win.results, r => r.pageNo + ":" + r.section + ":" + r.title); objectProp: "_key" }
                                delegate: Rectangle {
                                    id: res
                                    required property var modelData
                                    required property int index
                                    readonly property bool on: index === win.resultIndex
                                    Layout.fillWidth: true
                                    implicitHeight: resText.implicitHeight + 14
                                    radius: 12
                                    color: on ? Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.22)
                                         : resHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08) : "transparent"
                                    HoverHandler { id: resHov }
                                    Column {
                                        id: resText
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: res.modelData.title
                                            color: res.on ? app.cFg : app.cDim
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(13)
                                            font.bold: res.on
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: res.modelData.page + (res.modelData.section ? "  \u203a  " + res.modelData.section : "")
                                            color: app.cFaint
                                            font.family: "Inter"
                                            font.pixelSize: app.fs(11)
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { win.resultIndex = res.index; win.openResult(res.modelData) }
                                    }
                                }
                            }
                        }
                    }

                    // the page list scrolls on its own if it outgrows the
                    // window, so the header and Reset all never get pushed off
                    Flickable {
                        id: navFlick
                        visible: win.query.trim() === ""
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
                                    { i: 24, t: "Keybinds",       g: "keyboard_command_key" },
                                    { i: 11, t: "Mouse",          g: "mouse" },
                                    { sec: "Sound" },
                                    { i: 12, t: "Output",         g: "speaker" },
                                    { i: 13, t: "Applications",   g: "apps" },
                                    { i: 14, t: "Input",          g: "mic" },
                                    { i: 15, t: "Recording apps", g: "radio_button_checked" },
                                    { sec: "System" },
                                    { i: 16, t: "Weather",        g: "partly_cloudy_day" },
                                    { i: 17, t: "Calendar",       g: "calendar_month" },
                                    { i: 25, t: "Game overlay",   g: "sports_esports" },
                                    { i: 21, t: "Default apps",   g: "apps" },
                                    { i: 22, t: "AI assistant",   g: "smart_toy" },
                                    { i: 23, t: "Plugins",        g: "extension" },
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
                                    PageGeneral { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= GLASS =================
                                    PageGlass { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= THEME =================
                                    PageTheme { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= WALLPAPER =================
                                    PageWallpaper { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= BAR =================
                                    PageBar { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= WINDOWS =================
                                    PageWindows { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= DOCK =================
                                    PageDock { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= NOTIFICATIONS =================
                                    PageNotifications { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= IDLE =================
                                    PageIdle { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= DISPLAYS =================
                                    PageDisplays { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= KEYBOARD =================
                                    PageKeyboard { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= MOUSE =================
                                    PageMouse { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= WEATHER =================
                                    PageWeather { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= CALENDAR =================
                                    PageCalendar { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= ABOUT =================
                                    PageAbout { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= WIDGETS =================
                                    PageWidgets { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= GAME OVERLAY =================
                                    PageGameOverlay { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= KEYBINDS =================
                                    PageKeybinds { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= PLUGINS =================
                                    PagePlugins { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= LOCK SCREEN =================
                                    PageLockScreen { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= AI ASSISTANT =================
                                    PageAssistant { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= DEFAULT APPS =================
                                    PageDefaultApps { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= OUTPUT =================
                                    PageOutput { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= APPLICATIONS =================
                                    PageApplications { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= INPUT =================
                                    PageInput { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }

                                    // ================= RECORDING APPS =================
                                    PageRecording { app: rootV.app; settingsWin: win; settingsRoot: rootV; settingsKeys: keys }
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
