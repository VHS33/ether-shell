import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// ============================================================
//   LAUNCHER  (tap SUPER)
//   One search box for everything.  Start typing for apps (ranked by
//   how often you open them), or start with:
//       =   a calculator (maths without it works too)
//       :   emoji, copied when chosen
//       ;   clipboard history
//       >   commands: lock, restart, settings, night light...
//   Anything else can go to a web search, the last row.
//
//   On the long bar it grows out of the bar's centre as a drawer,
//   the bar and drawer drawn as one shape by BarStrip; in the
//   islands style it's a card under the bar.
//
//   Results are plain values ({ kind, title, sub, ... }), never the
//   DesktopEntry objects themselves: live objects in JS arrays used
//   as models are what caused the earlier crashes.  Apps are looked
//   up by id when launched.
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
        // Built the first time it's opened, then kept for instant opening:
        // nothing sits in memory for a panel that's never used.
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.launcherShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: lw
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.launcherShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)
        // Its own floating card, centred a little above the middle of the
        // screen, whatever the bar style.  (It used to grow out of the long
        // bar as a drawer; `att` is kept false so that path stays unused.)
        readonly property bool att: false

        readonly property real openW: 680
        readonly property real openH: 470

        anchors { top: true }
        margins { top: 0 }
        implicitWidth: openW + 40
        // tall enough for the card at its place on screen
        readonly property real cardY: Math.round(modelData.height * 0.16)
        implicitHeight: cardY + openH + 40
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // on the long bar the search box lives in BarStrip's window, which
        // takes the keyboard; this window only needs it for the islands card
        WlrLayershell.keyboardFocus: open && !att ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // ---- where the drawer goes: the bar's centre ----
        readonly property real scrX: (modelData.width - width) / 2
        // clicks only reach the launcher while it's open
        property Region shownMask: Region { item: frame }
        property Region hiddenMask: Region { width: 0; height: 0 }
        // on the long bar the drawer takes its clicks in BarStrip's window
        mask: open && !att ? shownMask : hiddenMask

        onOpenChanged: {
            if (open) {
                search.text = app.launcherPrefill
                sel = 0
                search.forceActiveFocus()
            } else {
                app.launcherPrefill = ""
            }
        }
        // SUPER + V while it's already open: switch to the clipboard
        Connections {
            target: app
            function onLauncherPrefillNowChanged() {
                search.text = app.launcherPrefill
                lw.sel = 0
                search.forceActiveFocus()
            }
        }

        // ---- the emoji, read once, the first time they're needed ----
        property var emoji: []
        FileView {
            id: emojiFile
            // next to this file, wherever the shell is installed
            path: Qt.resolvedUrl("emoji.json").toString().replace("file://", "")
            blockLoading: false
            onLoaded: {
                try { lw.emoji = JSON.parse(text()) } catch (e) { lw.emoji = [] }
            }
        }

        // ---- searching ----
        readonly property string q: search.text
        readonly property string mode:
            q.startsWith("=") ? "calc" : q.startsWith(":") ? "emoji"
            : q.startsWith(";") ? "clip" : q.startsWith(">") ? "cmd" : q.startsWith("@") ? "scene"
            : q.startsWith("/") ? "files" : "apps"
        readonly property string term: (mode === "apps" ? q : q.slice(1)).trim().toLowerCase()
        property int sel: 0
        onQChanged: sel = 0

        // files: "/" searches only them; typing normally shows the best few
        // under your apps once there are three letters
        readonly property bool filesOn: app.nativeOk && app.cfg.fileSearch !== false
        Binding {
            target: app; property: "fileQuery"; restoreMode: Binding.RestoreNone
            value: lw.filesOn && app.launcherShown && (lw.mode === "files" || (lw.mode === "apps" && lw.term.length >= 3))
                   ? lw.term : ""
        }
        Binding { target: app; property: "fileLimit"; value: lw.mode === "files" ? 40 : 6; restoreMode: Binding.RestoreNone }
        readonly property var fileGlyphs: ({ folder: "folder", image: "image", video: "movie", audio: "music_note",
                                             pdf: "picture_as_pdf", code: "code", archive: "folder_zip",
                                             document: "description", file: "draft" })
        function fileRows(n) {
            // only results for what's typed now (a newer search may still be arriving)
            const rows = []
            if (app.fileResultsFor !== lw.term) return rows
            for (const f of app.fileResults.slice(0, n))
                rows.push({ kind: "file", title: f.name, sub: f.parent, glyph: lw.fileGlyphs[f.kind] || "draft", path: f.path })
            return rows
        }

        // one typo: a letter wrong, missing, extra or two swapped ("fierfox")
        function oneTypo(a, b) {
            if (Math.abs(a.length - b.length) > 1) return false
            let i = 0
            while (i < a.length && i < b.length && a[i] === b[i]) i++
            if (i === a.length && i === b.length) return true
            const rest = (x, y) => a.slice(x) === b.slice(y)
            return rest(i + 1, i + 1) || rest(i + 1, i) || rest(i, i + 1)
                || (a[i] === b[i + 1] && a[i + 1] === b[i] && rest(i + 2, i + 2))
        }

        // maths: only numbers, operators, brackets and a few named
        // functions ever reach the evaluator
        function calc(expr) {
            let e = expr.trim().toLowerCase().replace(/\s+/g, "")
            if (!e.length) return null
            if (!/^[0-9+\-*/%^().,a-z]*$/.test(e)) return null
            const fns = { sqrt: "Math.sqrt", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan",
                          log: "Math.log10", ln: "Math.log", abs: "Math.abs", round: "Math.round",
                          floor: "Math.floor", ceil: "Math.ceil", pi: "Math.PI", e: "Math.E" }
            const words = e.match(/[a-z]+/g) || []
            for (const w of words) if (!(w in fns)) return null
            e = e.replace(/[a-z]+/g, w => fns[w]).replace(/\^/g, "**").replace(/,/g, ".")
            try {
                const v = Function('"use strict"; return (' + e + ')')()
                if (typeof v !== "number" || !isFinite(v)) return null
                return Number.isInteger(v) ? String(v) : String(parseFloat(v.toPrecision(12)))
            } catch (err) { return null }
        }
        readonly property bool looksLikeMaths: /^[0-9.(\s]/.test(q) && /[0-9]\s*[-+*/^%]\s*[0-9(]/.test(q)

        readonly property var commands: [
            { title: "Lock",                 glyph: "lock",               act: "lock" },
            { title: "Log out",              glyph: "logout",             act: "logout" },
            { title: "Restart",              glyph: "restart_alt",        act: "reboot" },
            { title: "Power off",            glyph: "power_settings_new", act: "poweroff" },
            { title: "Settings",             glyph: "settings",           act: "settings" },
            { title: "Change wallpaper",     glyph: "wallpaper",          act: "wallpaper" },
            { title: "Screenshot a region",  glyph: "screenshot_region",  act: "shot" },
            { title: "Screenshot the screen",glyph: "screenshot_monitor", act: "shotfull" },
            { title: "Copy text from the screen", glyph: "document_scanner", act: "ocr" },
            { title: "Night light",          glyph: "dark_mode",          act: "night" },
            { title: "Do not disturb",       glyph: "notifications_off",  act: "dnd" },
            { title: "Keybinds",             glyph: "keyboard",           act: "cheat" },
            { title: "Power menu",           glyph: "power",              act: "power" }
        ]

        readonly property var results: {
            const t = term, out = []
            if (mode === "calc") {
                const v = calc(t)
                out.push({ kind: "calc", title: v !== null ? v : (t.length ? "\u2026" : "Type a sum"),
                           sub: v !== null ? t + "  \u2022  Enter copies it" : "e.g. 12*(3+4), sqrt(2), 2^10",
                           glyph: "calculate", value: v })
                return out
            }
            if (mode === "emoji") {
                const words = t.split(/\s+/).filter(w => w.length)
                for (const e of lw.emoji) {
                    if (words.every(w => e[2].indexOf(w) !== -1))
                        out.push({ kind: "emoji", title: e[1], sub: "Enter copies it", emoji: e[0] })
                    if (out.length >= 80) break
                }
                return out
            }
            if (mode === "clip") {
                for (const c of app.clipItems) {
                    if (t === "" || c.preview.toLowerCase().indexOf(t) !== -1)
                        out.push({ kind: "clip", title: c.preview, sub: "Enter copies it",
                                   glyph: "content_paste", id: c.id })
                    if (out.length >= 60) break
                }
                return out
            }
            if (mode === "scene") {
                const name = q.slice(1).trim()
                const exact = app.sceneList.some(sc => sc.name.toLowerCase() === t)
                // a new name: save the desktop as it
                if (name !== "" && !exact)
                    out.push({ kind: "scenesave", title: "Save this desktop as \u201c" + name + "\u201d",
                               sub: "Every window and the workspace it's on", name: name })
                for (const sc of app.sceneList)
                    if (t === "" || sc.name.toLowerCase().indexOf(t) !== -1)
                        out.push({ kind: "scene", title: sc.name, name: sc.name,
                                   sub: (sc.count === 1 ? "1 window" : sc.count + " windows")
                                        + "  \u2022  Enter restores, Ctrl+Enter saves over it, Delete removes it" })
                return out
            }
            if (mode === "files") {
                if (!lw.filesOn) {
                    out.push({ kind: "info", title: "File search is off", glyph: "search_off",
                               sub: app.nativeOk ? "Turn it on in Settings, Launcher" : "It needs the native plugin: re-run the installer" })
                    return out
                }
                if (t === "") {
                    out.push({ kind: "info", title: "Search your files", glyph: "search",
                               sub: app.fileCount ? app.fileCount.toLocaleString(Qt.locale(), "f", 0) + " files and folders in your home"
                                                  : "Indexing your home\u2026" })
                    return out
                }
                return lw.fileRows(40)
            }
            if (mode === "cmd") {
                for (const c of lw.commands)
                    if (t === "" || c.title.toLowerCase().indexOf(t) !== -1)
                        out.push({ kind: "cmd", title: c.title, sub: "Command", glyph: c.glyph, act: c.act })
                return out
            }

            // ---- apps ----
            // "timer 5m", "timer 90s": start one
            const tm = q.trim().match(/^timer\s+(.+)$/i)
            if (tm) {
                const secs = app.parseDur(tm[1])
                if (secs > 0)
                    out.push({ kind: "timer", title: "Start a " + app.fmtDur(secs) + " timer",
                               sub: "Shows in the bar while it runs", glyph: "hourglass_top", value: secs })
            }
            if (looksLikeMaths) {
                const v = calc(q)
                if (v !== null)
                    out.push({ kind: "calc", title: v, sub: q.trim() + "  \u2022  Enter copies it",
                               glyph: "calculate", value: v })
            }
            const counts = app.launchCounts
            const scored = []
            for (const d of DesktopEntries.applications.values) {
                if (d.noDisplay) continue
                const name = (d.name || "").toLowerCase()
                let s = 0
                if (t === "") s = 1
                else if (name.startsWith(t)) s = 100
                else if (name.split(/[\s\-_.]/).some(w => w.startsWith(t))) s = 75
                else if (name.indexOf(t) !== -1) s = 50
                else if (((d.genericName || "") + " " + (d.keywords || []).join(" ")
                          + " " + (d.comment || "")).toLowerCase().indexOf(t) !== -1) s = 25
                else {
                    // letters in order: "ff" finds Firefox
                    let i = 0
                    for (const ch of name) if (ch === t[i]) i++
                    if (i === t.length) s = 10
                    // one typo, for four letters or more: "fierfox", "spotfy"
                    else if (t.length >= 4 && (lw.oneTypo(t, name)
                             || name.split(/[\s\-_.]/).some(w => lw.oneTypo(t, w) || lw.oneTypo(t, w.slice(0, t.length)))))
                        s = 8
                }
                if (s === 0) continue
                const n = counts[d.id] || 0
                scored.push({ s: s + Math.log2(1 + n) * (t === "" ? 40 : 6), id: d.id,
                              title: d.name, sub: d.comment || d.genericName || "", icon: d.icon || "" })
            }
            scored.sort((a, b) => b.s - a.s || a.title.localeCompare(b.title))
            // with files to show, the top apps, then the files
            const files = t.length >= 3 && lw.filesOn ? lw.fileRows(6) : []
            for (const a of scored.slice(0, t === "" ? 24 : files.length ? 8 : 40))
                out.push({ kind: "app", title: a.title, sub: a.sub, icon: a.icon, id: a.id })
            for (const f of files) out.push(f)
            if (t !== "")
                out.push({ kind: "web", title: "Search the web for \u201c" + q.trim() + "\u201d",
                           sub: "Opens in your browser", glyph: "travel_explore" })
            return out
        }

        Process { id: runner }
        function sh(cmd) {
            runner.command = ["sh", "-c", cmd]
            runner.running = true
        }

        // the file, selected in your file manager (Dolphin, Nautilus...), or
        // its folder if none answers
        function reveal(path) {
            app.launcherShown = false
            runner.command = ["sh", "-c",
                'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call ' +
                '/org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems ' +
                'array:string:"file://$1" string:"" >/dev/null 2>&1 || xdg-open "$(dirname "$1")"',
                "sh", path]
            runner.running = true
        }
        function activate(i) {
            const r = results[i]
            if (!r || r.kind === "info") return
            app.launcherShown = false
            if (r.kind === "app") {
                const d = DesktopEntries.byId(r.id)
                if (d) { app.launchEntry(d); app.noteLaunch(r.id) }
            } else if (r.kind === "calc") {
                if (r.value !== null && r.value !== undefined)
                    sh("printf %s '" + String(r.value).replace(/'/g, "") + "' | wl-copy")
            } else if (r.kind === "emoji") {
                sh("printf %s '" + r.emoji + "' | wl-copy")
            } else if (r.kind === "clip") {
                app.clipCopy(r.id)
            } else if (r.kind === "timer") {
                app.startTimer(r.value)
            } else if (r.kind === "file") {
                runner.command = ["xdg-open", r.path]
                runner.running = true
            } else if (r.kind === "web") {
                sh("xdg-open 'https://duckduckgo.com/?q=" + encodeURIComponent(q.trim()) + "'")
            } else if (r.kind === "scene") {
                app.sceneRestore(r.name)
            } else if (r.kind === "scenesave") {
                app.sceneSave(r.name)
            } else if (r.kind === "cmd") {
                const a = r.act
                if (a === "lock") sh("sleep 0.3; loginctl lock-session")
                else if (a === "logout" || a === "reboot" || a === "poweroff") app.powerShown = true
                else if (a === "settings") app.settingsShown = true
                else if (a === "wallpaper") { app.settingsPage = 3; app.settingsShown = true }
                else if (a === "shot") sh("sleep 0.4; $HOME/.local/bin/shot")
                else if (a === "shotfull") sh("sleep 0.4; $HOME/.local/bin/shot full")
                else if (a === "ocr") sh("sleep 0.4; $HOME/.local/bin/ocr")
                else if (a === "night") app.toggleNight()
                else if (a === "dnd") app.dnd = !app.dnd
                else if (a === "cheat") app.cheatShown = true
                else if (a === "power") app.powerShown = true
            }
        }

        // ---- the drawer: on the long bar, grows out of its centre ----
        // The drawer's contents live in BarStrip's window, on the same
        // surface as the glass, so glass and contents are drawn together in
        // the same frame.  (Kept in this window, and positioned for it, only
        // until BarStrip has shown up.)
        Item { id: drawerHome; anchors.fill: parent }
        Item {
            id: drawerHost
            readonly property bool moved: lw.att && app.drawerLayer !== null
            parent: moved ? app.drawerLayer : drawerHome
            visible: lw.att && app.drawerWho === "launcher" && app.drawerP > 0
            x: moved ? app.drawerCurX : app.drawerCurX - lw.scrX
            y: app.barBottom
            width: app.drawerCurW
            height: app.drawerCurH
            clip: true
        }

        // ---- in the islands style: a card under the bar ----
        Rectangle {
            id: card
            visible: !lw.att && opacity > 0
            x: (lw.width - lw.openW) / 2
            y: lw.cardY
            width: lw.openW
            height: lw.openH
            radius: 26
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
            transformOrigin: Item.Top
            opacity: lw.open ? 1 : 0
            scale: lw.open ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
        }

        // what takes clicks while open: the drawer or the card
        Item {
            id: frame
            x: lw.att ? drawerHost.x : card.x
            y: lw.att ? drawerHost.y : card.y
            width: lw.att ? drawerHost.width : card.width
            height: lw.att ? drawerHost.height : card.height
        }

        // ================= the contents =================
        Item {
            id: body
            parent: lw.att ? drawerHost : card
            x: lw.att ? (lw.modelData.width - lw.openW) / 2 - app.drawerCurX : 0
            y: 0
            width: lw.openW
            height: lw.openH
            opacity: lw.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---- the search box ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: 26
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12
                        Text {
                            text: lw.mode === "calc" ? "calculate" : lw.mode === "emoji" ? "mood"
                                : lw.mode === "clip" ? "content_paste" : lw.mode === "cmd" ? "terminal"
                                : lw.mode === "scene" ? "view_quilt" : "search"
                            color: app.cBlue
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(22)
                        }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: app.cFg
                            selectionColor: app.cBlue
                            selectedTextColor: app.cOnAccent
                            font.family: "Inter"
                            font.pixelSize: app.fs(16)
                            clip: true
                            Text {
                                visible: !search.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search apps, or start with  =  :  ;  >"
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                font: search.font
                            }
                            Keys.onPressed: e => {
                                const n = lw.results.length
                                if (e.key === Qt.Key_Escape) {
                                    if (search.text !== "") search.text = ""
                                    else app.launcherShown = false
                                } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier))) {
                                    lw.sel = Math.min(n - 1, lw.sel + 1)
                                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) {
                                    lw.sel = Math.max(0, lw.sel - 1)
                                } else if (e.key === Qt.Key_PageDown) {
                                    lw.sel = Math.min(n - 1, lw.sel + 6)
                                } else if (e.key === Qt.Key_PageUp) {
                                    lw.sel = Math.max(0, lw.sel - 6)
                                } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                                           && (e.modifiers & Qt.ControlModifier) && lw.results[lw.sel]?.kind === "scene") {
                                    app.launcherShown = false
                                    app.sceneSave(lw.results[lw.sel].name)
                                } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                                           && (e.modifiers & Qt.AltModifier) && lw.results[lw.sel]?.kind === "file") {
                                    lw.reveal(lw.results[lw.sel].path)
                                } else if (e.key === Qt.Key_Delete && lw.results[lw.sel]?.kind === "scene") {
                                    app.sceneRemove(lw.results[lw.sel].name)
                                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                    lw.activate(lw.sel)
                                } else return
                                e.accepted = true
                            }
                        }
                    }
                }

                // ---- the modes, as chips; click one to switch ----
                Row {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { m: "apps",  label: "Apps",       p: "" },
                            { m: "calc",  label: "Calculator", p: "=" },
                            { m: "emoji", label: "Emoji",      p: ":" },
                            { m: "clip",  label: "Clipboard",  p: ";" },
                            { m: "cmd",   label: "Commands",   p: ">" },
                            { m: "scene", label: "Scenes",     p: "@" },
                            { m: "files", label: "Files",      p: "/" }
                        ]
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool on: lw.mode === modelData.m
                            implicitWidth: chipRow.implicitWidth + 22
                            implicitHeight: 30
                            radius: 15
                            color: on ? app.cPrimC
                                 : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                            HoverHandler { id: chipHov }
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: chip.modelData.label
                                    color: chip.on ? app.cOnPrimC : app.cDim
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    visible: chip.modelData.p !== ""
                                    text: chip.modelData.p
                                    color: chip.on ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.6)
                                                   : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                                    font.family: "Inter"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: app.fs(12)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const rest = lw.mode === "apps" ? search.text : search.text.slice(1)
                                    search.text = chip.modelData.p + rest
                                    search.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // ---- the results ----
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: lw.results
                    currentIndex: lw.sel
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: app.animQuick
                    highlight: Rectangle {
                        radius: 16
                        color: app.cPrimC
                    }
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: index === lw.sel
                        width: ListView.view.width
                        height: 52

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 12

                            Item {
                                implicitWidth: 34
                                implicitHeight: 34
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: row.modelData.kind === "app"
                                    implicitSize: 30
                                    source: row.modelData.kind === "app"
                                            ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.modelData.kind === "emoji"
                                    text: row.modelData.emoji || ""
                                    font.pixelSize: app.fs(24)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: row.modelData.kind !== "app" && row.modelData.kind !== "emoji"
                                    radius: 12
                                    color: row.current ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                    Text {
                                        anchors.centerIn: parent
                                        text: row.modelData.glyph || ""
                                        color: row.current ? app.cOnAccent : app.cFg
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(18)
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title
                                    color: row.current ? app.cOnPrimC : app.cFg
                                    font.family: "Inter"
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(row.modelData.kind === "calc" ? 17 : 13)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: row.modelData.sub || ""
                                    color: row.current ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.7)
                                                       : app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    textFormat: Text.PlainText
                                }
                            }
                            Text {
                                visible: row.current
                                text: "keyboard_return"
                                color: Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.6)
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(16)
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: lw.sel = row.index
                            onClicked: lw.activate(row.index)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: lw.results.length === 0
                        text: lw.mode === "scene" ? "No scenes yet: type a name after @ to save this desktop"
                            : lw.mode === "clip" ? "Nothing copied yet"
                            : lw.mode === "emoji" && !lw.emoji.length ? "Loading emoji\u2026"
                            : "Nothing matches"
                        color: app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(13)
                    }
                }

                // ---- hints ----
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lw.results[lw.sel]?.kind === "file"
                          ? "Enter to open   \u2022   Alt + Enter to show it in its folder   \u2022   Esc to close"
                          : "\u2191 \u2193 to move   \u2022   Enter to open   \u2022   Esc to close"
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                }
            }
        }
    }
    }
}
