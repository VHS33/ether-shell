import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import "../../lib/text.mjs" as TextLib
import "../../lib/plugins.mjs" as Plugins
import "../../lib/models.mjs" as Models
import "../../lib/windows.mjs" as WinLib
import "../../lib/settingsindex.mjs" as SetIndex
import "../../lib/search.mjs" as SearchLib
import qs.services

// ============================================================
//   LAUNCHER  (tap SUPER)
//   One search box for everything.  Start typing for apps (ranked by
//   how often you open them) and the windows you have open, or start with:
//       #   your open windows (focus, move, float, fullscreen, close)
//       =   a calculator (maths without it works too)
//       :   emoji, copied when chosen
//       ;   clipboard history
//       >   commands: lock, restart, settings, night light...
//       ?   settings: find one, flip an on/off one, or open it in Settings
//   Anything else can go to a web search, the last row.  Plain words work
//   too: "ws 3" (go to workspace 3), "move 4" (the window you're on),
//   "close discord", "focus firefox".
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
        // only on the monitor it opens on (app.launcherScreen); opening it
        // on another one swaps it there
        active: modelData.name === app.launcherScreen && (used || app.launcherShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: lw
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.launcherScreen
        readonly property bool open: app.launcherShown
        // On the main monitor a click outside closes it through the bar's
        // full-screen catcher; other monitors have no bar, so there a
        // Hyprland focus grab does it (as the dock's menu does).  The grab
        // starts a moment after it opens, once the window is on screen: a
        // grab begun as the window appears could be cleared at once by
        // Hyprland, closing the launcher as it opened.
        property bool grabReady: false
        Timer {
            id: grabDelay
            interval: 150
            onTriggered: lw.grabReady = lw.open
        }
        Component.onCompleted: if (open) grabDelay.restart()   // built already open
        HyprlandFocusGrab {
            windows: [ lw ]
            active: lw.open && lw.grabReady && lw.modelData.name !== app.mainScreen
            onCleared: app.launcherShown = false
        }
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
            grabReady = false
            if (open) grabDelay.restart()
            if (open) {
                settingsWanted = true
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
            path: Qt.resolvedUrl("../../emoji.json").toString().replace("file://", "")
            blockLoading: false
            onLoaded: {
                try { lw.emoji = JSON.parse(text()) } catch (e) { lw.emoji = [] }
            }
        }

        // ---- every setting, read from Settings' page files (lib/settingsindex.mjs)
        // the first time the launcher opens; Settings itself needn't be open ----
        property bool settingsWanted: false
        property var pageTexts: ({})
        Instantiator {
            model: lw.settingsWanted ? SetIndex.PAGES : []
            delegate: FileView {
                required property var modelData
                required property int index
                path: Quickshell.shellPath("modules/settings/" + modelData.f + ".qml")
                blockLoading: false
                onLoaded: {
                    const m = Object.assign({}, lw.pageTexts)
                    m[index] = text()
                    lw.pageTexts = m
                }
            }
        }
        readonly property var settingsList: {
            const out = []
            for (let i = 0; i < SetIndex.PAGES.length; i++)
                if (pageTexts[i] !== undefined) for (const e of SetIndex.parsePage(pageTexts[i]).entries) out.push(e)
            return out
        }
        // a setting, as a row (its On/Off read now, so it changes as you flip it)
        function settingRow(e) { return SetIndex.row(e, app) }
        // open it in Settings, outlined for a moment
        function openSetting(r) {
            app.launcherShown = false
            app.settingsPage = r.pageNo
            app.settingsFocus = r.title
            app.settingsShown = true
        }
        // an on/off one: flip it, and stay open to show it changed
        function flipSetting(r) {
            if (!r.sw) { openSetting(r); return }
            app.setting(r.sw.key, !SetIndex.isOn(r.sw, app))
        }

        // ---- searching ----
        readonly property string q: search.text
        // a plugin's own prefix (Settings, Plugins): just its results
        readonly property var launchers: app.pluginLaunchers()
        readonly property var pluginHit: Plugins.prefixFor(q, launchers)
        readonly property string mode:
            pluginHit ? "plugin" :
            q.startsWith("#") ? "win" : q.startsWith("?") ? "set" :
            q.startsWith("=") ? "calc" : q.startsWith(":") ? "emoji"
            : q.startsWith(";") ? "clip" : q.startsWith(">") ? "cmd" : q.startsWith("@") ? "scene"
            : q.startsWith("/") ? "files" : "apps"
        readonly property string term: (mode === "apps" ? q : q.slice(1)).trim().toLowerCase()
        property int sel: 0
        // (headings can't be chosen: the selection steps over them)
        function selectable(i) { const r = results[i]; return !!r && r.kind !== "head" }
        function step(from, d) {
            let i = from
            for (let k = 0; k < results.length; k++) {
                i += d
                if (i < 0 || i >= results.length) return from
                if (selectable(i)) return i
            }
            return from
        }
        onResultsChanged: { if (!selectable(sel)) sel = step(-1, 1) === -1 ? 0 : step(-1, 1); closeArmed = "" }
        // (a moment later: what's typed changes first, and what it means (the
        // mode, which plugin, the term) only after; told straight away,
        // plugins got the previous search, one step behind)
        onQChanged: { sel = 0; Qt.callLater(feedPlugins) }
        // tell each plugin what's typed: the one whose prefix it is, or those
        // without a prefix while you search apps (from two letters); the rest
        // get nothing, and nothing while the launcher is closed
        function feedPlugins() {
            const open = app.launcherShown
            for (const l of launchers) {
                const p = app.pluginProviders[l.id]
                if (!p || p.query === undefined) continue
                const want = !open ? ""
                    : pluginHit ? (pluginHit.id === l.id ? pluginHit.term : "")
                    : (!l.prefix && mode === "apps" && term.length >= 2) ? q.trim() : ""
                if (p.query !== want) {
                    try { p.query = want } catch (e) { console.log("plugin " + l.id + ": " + e) }
                }
            }
        }
        Connections { target: app; function onLauncherShownChanged() { Qt.callLater(lw.feedPlugins) } function onPluginProvidersChanged() { Qt.callLater(lw.feedPlugins) } }
        // a plugin's results, checked (lib/plugins.mjs), as launcher rows
        function pluginRows(l, max) {
            const p = app.pluginProviders[l.id]
            const rs = p && Array.isArray(p.results) ? p.results : []
            const out = []
            for (const r of rs) {
                const c = Plugins.cleanResult(r)
                if (!c) continue
                out.push({ kind: "plugin", pid: l.id, res: c, title: c.title,
                           sub: (c.subtitle ? c.subtitle + "  \u2022  " : "") + l.title, glyph: c.icon || "extension" })
                if (out.length >= max) break
            }
            return out
        }

        // files: "/" searches only them; typing normally shows the best few
        // under your apps once there are three letters
        readonly property bool filesOn: app.nativeOk && app.cfg.fileSearch !== false
        // (to Apps itself: the shell's app.fileQuery is only a read-only copy,
        // so writing that did nothing and the search never got what's typed)
        Binding {
            target: Apps; property: "fileQuery"; restoreMode: Binding.RestoreNone
            value: lw.filesOn && app.launcherShown && (lw.mode === "files" || (lw.mode === "apps" && lw.term.length >= 3))
                   ? lw.term : ""
        }
        Binding { target: Apps; property: "fileLimit"; value: lw.mode === "files" ? 40 : 6; restoreMode: Binding.RestoreNone }
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
        function oneTypo(a, b) { return TextLib.oneTypo(a, b) }      // lib/text.mjs

        // maths: only numbers, operators, brackets and a few named
        // functions ever reach the evaluator
        function calc(expr) { return TextLib.calc(expr) }      // lib/text.mjs
        readonly property bool looksLikeMaths: /^[0-9.(\s]/.test(q) && /[0-9]\s*[-+*/^%]\s*[0-9(]/.test(q)

        // ---- your windows (Hyprland's own list, fresh when the launcher opens) ----
        // a window being moved (Ctrl+M): the list becomes its workspaces
        property var moving: null            // { addr, name, title }
        // Delete on a window asks first; the second press closes it
        property string closeArmed: ""
        Connections {
            target: app
            function onLauncherShownChanged() {
                if (app.launcherShown) Hyprland.refreshToplevels()
                else { lw.moving = null; lw.closeArmed = "" }
            }
        }
        // the app a window belongs to: its desktop entry by name first; Quickshell's
        // guess only when it really is that app (a guess for an app that isn't
        // installed was once an image viewer, and "New window" opened that)
        function entryForClass(cls) {
            if (!cls) return null
            const c = cls.toLowerCase(), last = c.split(".").pop()
            let e = DesktopEntries.byId(cls) || DesktopEntries.byId(c) || DesktopEntries.byId(cls + ".desktop") || null
            if (e) return e
            try { if (typeof DesktopEntries.heuristicLookup === "function") e = DesktopEntries.heuristicLookup(cls) } catch (err) {}
            if (!e) return null
            const id = (e.id || "").toLowerCase(), wm = (e.startupClass || "").toLowerCase(), nm = (e.name || "").toLowerCase()
            return wm === c || id === c || id.indexOf(last) !== -1 || nm.indexOf(last) !== -1 ? e : null
        }
        function monitorName(id) {
            for (const m of Hyprland.monitors.values) if (m.id === id) return m.name
            return ""
        }
        // every window: [{ addr, cls, name, title, ws, mon, icon, entry, focused }]
        function windowList() {
            const out = []
            const active = Hyprland.activeToplevel ? (Hyprland.activeToplevel.lastIpcObject?.address ?? "") : ""
            for (const t of Hyprland.toplevels.values) {
                const ipc = t.lastIpcObject
                if (!ipc || !ipc.address || ipc.mapped === false) continue
                const ws = ipc.workspace ? ipc.workspace.id : 0
                const e = lw.entryForClass(ipc.class || ipc.initialClass || "")
                out.push({ addr: ipc.address, cls: ipc.class || "", title: ipc.title || "",
                           name: e ? e.name : (ipc.class || "Window"), icon: e ? (e.icon || "") : "",
                           entry: e ? e.id : "", ws: ws, wsName: ipc.workspace ? (ipc.workspace.name || "") : "",
                           mon: lw.monitorName(ipc.monitor), focused: ipc.address === active })
            }
            return out
        }
        // (the matching, the rows and the plain words: lib/windows.mjs, tested
        // on their own)
        function windowRow(w, kind) { return WinLib.row(w, kind) }
        function matchingWindows(t, max) { return WinLib.match(lw.windowList(), t, max) }
        // what's on each workspace, for "Move to…" and "ws 3"
        function workspaceSummary(id) {
            let mon = ""
            for (const m of Hyprland.monitors.values) if (m.activeWorkspace && m.activeWorkspace.id === id) mon = m.name
            return WinLib.summary(lw.windowList(), id, mon)
        }
        function dsp(cmd) { Hyprland.dispatch(cmd) }
        function focusWin(addr) { dsp("hl.dsp.focus({ window = \"address:" + addr + "\" })") }
        function moveWin(addr, ws, follow) {
            dsp("hl.dsp.window.move({ workspace = " + ws + ", window = \"address:" + addr + "\", follow = " + (follow ? "true" : "false") + " })")
        }
        function closeWin(addr) { focusWin(addr); dsp("hl.dsp.window.close()") }
        function floatWin(addr) { focusWin(addr); dsp("hl.dsp.window.float({ action = \"toggle\" })") }
        function fullscreenWin(addr) { focusWin(addr); dsp("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })") }
        function goWorkspace(ws) { dsp("hl.dsp.focus({ workspace = " + ws + " })") }
        // a window's actions (the row under it, and their keys)
        function windowAction(a, r) {
            if (!r || !r.addr) return
            if (a === "move") { lw.moving = { addr: r.addr, title: r.title }; search.text = ""; lw.sel = 0; return }
            if (a === "close" && lw.closeArmed !== r.addr) { lw.closeArmed = r.addr; return }
            app.launcherShown = false
            if (a === "focus") lw.focusWin(r.addr)
            else if (a === "close") lw.closeWin(r.addr)
            else if (a === "float") lw.floatWin(r.addr)
            else if (a === "fullscreen") lw.fullscreenWin(r.addr)
            else if (a === "new") { const d = DesktopEntries.byId(r.entry); if (d) { app.launchEntry(d); app.noteLaunch(r.entry) } }
        }

        readonly property var commands: [
            { title: "Lock",                 glyph: "lock",               act: "lock" },
            { title: "Log out",              glyph: "logout",             act: "logout" },
            { title: "Restart",              glyph: "restart_alt",        act: "reboot" },
            { title: "Power off",            glyph: "power_settings_new", act: "poweroff" },
            { title: "Settings",             glyph: "settings",           act: "settings" },
            { title: "Welcome setup",        glyph: "waving_hand",        act: "welcome" },
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
            // moving a window: where to
            if (lw.moving) {
                out.push({ kind: "head", title: "Move " + lw.moving.title.split("  \u2014  ")[0] + " to" })
                const nums = []
                for (let i = 1; i <= 10; i++) nums.push(i)
                for (const n of nums.filter(n => t === "" || String(n).startsWith(t) || ("workspace " + n).indexOf(t) !== -1))
                    out.push({ kind: "moveto", ws: n, addr: lw.moving.addr, glyph: "grid_view",
                               title: "Workspace " + n, sub: lw.workspaceSummary(n) + "  \u2022  Shift+Enter goes there too",
                               badge: n === app.activeWorkspace ? "You're here" : "" })
                return out
            }
            if (mode === "win") {
                for (const w of lw.matchingWindows(t, 40)) out.push(lw.windowRow(w))
                return out
            }
            if (mode === "set") {
                // nothing typed: every setting, under its page
                if (t === "") {
                    let page = -1
                    for (const e of lw.settingsList) {
                        if (e.pageNo !== page) { page = e.pageNo; out.push({ kind: "head", title: e.page }) }
                        out.push(lw.settingRow(e))
                    }
                    return out
                }
                for (const e of SearchLib.search(lw.settingsList, t, 40)) out.push(lw.settingRow(e))
                return out
            }
            if (mode === "plugin") {
                const l = launchers.find(x => x.id === pluginHit.id)
                const rows = l ? pluginRows(l, 40) : []
                if (rows.length) return rows
                return [{ kind: "info", glyph: "extension",
                          title: pluginHit.term === "" ? "Type to search " + (l ? l.title : "") : "Nothing from " + (l ? l.title : "") + " yet",
                          sub: l ? "A plugin (Settings, Plugins)" : "" }]
            }
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

            // ---- plain words: workspaces and windows (lib/windows.mjs) ----
            const said = WinLib.command(q)
            if (said && said.type === "go")
                out.push({ kind: "gows", ws: said.ws, glyph: "grid_view", title: "Go to workspace " + said.ws, sub: lw.workspaceSummary(said.ws) })
            if (said && said.type === "move") {
                const here = Hyprland.activeToplevel ? Hyprland.activeToplevel.lastIpcObject : null
                if (here && here.address) {
                    const w = lw.windowList().find(x => x.addr === here.address)
                    const nm = w ? w.name : (here.class || "the window")
                    out.push({ kind: "moveto", ws: said.ws, addr: here.address, glyph: "move_down",
                               title: "Move " + nm + " to workspace " + said.ws, sub: "The window you're on  \u2022  you stay where you are" })
                    out.push({ kind: "movefollow", ws: said.ws, addr: here.address, glyph: "swap_horiz",
                               title: "Move " + nm + " to workspace " + said.ws + ", and go there", sub: "Follow it" })
                }
                out.push({ kind: "gows", ws: said.ws, glyph: "grid_view", title: "Go to workspace " + said.ws, sub: lw.workspaceSummary(said.ws) })
                return out
            }
            if (said && (said.type === "close" || said.type === "focus")) {
                const ws = lw.matchingWindows(said.what, 8)
                for (const w of ws) out.push(lw.windowRow(w, said.type === "close" ? "winclose" : "win"))
                if (ws.length) return out
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
            // your open windows first (from two letters): Enter goes to the one
            // that's open instead of starting another
            const wins = t.length >= 2 ? lw.matchingWindows(t, 4) : []
            if (wins.length) {
                out.push({ kind: "head", title: "Open windows" })
                for (const w of wins) out.push(lw.windowRow(w))
                if (scored.length) out.push({ kind: "head", title: "Apps" })
            }
            // with files to show, the top apps, then the files
            const files = t.length >= 3 && lw.filesOn ? lw.fileRows(6) : []
            for (const a of scored.slice(0, t === "" ? 24 : files.length ? 8 : 40))
                out.push({ kind: "app", title: a.title, sub: a.sub, icon: a.icon, id: a.id })
            for (const f of files) out.push(f)
            // plugins without a prefix: a few each, labelled with their name
            if (t.length >= 2)
                for (const l of launchers) if (!l.prefix) for (const r of pluginRows(l, 4)) out.push(r)
            // a few settings that match (from three letters)
            const sets = t.length >= 3 ? SearchLib.search(lw.settingsList, t, 3) : []
            if (sets.length) {
                out.push({ kind: "head", title: "Settings" })
                for (const e of sets) out.push(lw.settingRow(e))
            }
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
            if (!r || r.kind === "info" || r.kind === "head") return
            if (r.kind === "win") { lw.windowAction("focus", r); return }
            if (r.kind === "winclose") { app.launcherShown = false; lw.closeWin(r.addr); return }
            if (r.kind === "moveto" || r.kind === "movefollow") {
                app.launcherShown = false
                lw.moveWin(r.addr, r.ws, r.kind === "movefollow")
                lw.moving = null
                return
            }
            if (r.kind === "gows") { app.launcherShown = false; lw.goWorkspace(r.ws); return }
            if (r.kind === "setting") { lw.flipSetting(r); return }
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
                // the address goes to xdg-open as it is, not through sh: an
                // apostrophe in the search ("don't") used to end sh's quotes
                runner.command = ["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(q.trim())]
                runner.running = true
            } else if (r.kind === "scene") {
                app.sceneRestore(r.name)
            } else if (r.kind === "scenesave") {
                app.sceneSave(r.name)
            } else if (r.kind === "plugin") {
                // the plugin's own activate(), if it has one; otherwise what
                // the result says: copy, open or run (checked already)
                const p = app.pluginProviders[r.pid]
                if (p && typeof p.activate === "function") {
                    try { p.activate(r.res.data) } catch (e) { console.log("plugin " + r.pid + ": " + e) }
                } else if (r.res.copy !== undefined) app.pluginRun(r.pid, ["wl-copy", "--", r.res.copy])
                else if (r.res.open) app.pluginRun(r.pid, ["xdg-open", r.res.open])
                else if (r.res.run) app.pluginRun(r.pid, r.res.run)
            } else if (r.kind === "cmd") {
                const a = r.act
                if (a === "lock") sh("sleep 0.3; \"$HOME/.local/bin/lock\" || loginctl lock-session")
                else if (a === "logout" || a === "reboot" || a === "poweroff") app.powerShown = true
                else if (a === "settings") app.settingsShown = true
                else if (a === "welcome") app.openWelcome()
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
                            text: lw.mode === "plugin" ? "extension" : lw.mode === "calc" ? "calculate" : lw.mode === "emoji" ? "mood"
                                : lw.mode === "clip" ? "content_paste" : lw.mode === "cmd" ? "terminal"
                                : lw.mode === "scene" ? "view_quilt" : lw.mode === "set" ? "settings" : "search"
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
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(16)
                            clip: true
                            Text {
                                visible: !search.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: lw.moving ? "Which workspace? (a number, or pick one)" : "Search apps, windows and settings, or start with  #  ?  =  :  ;  >"
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                font: search.font
                            }
                            Keys.onPressed: e => {
                                const n = lw.results.length
                                const cur = lw.results[lw.sel]
                                const isWin = cur && cur.kind === "win"
                                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0
                                const shift = (e.modifiers & Qt.ShiftModifier) !== 0
                                if (e.key === Qt.Key_Escape) {
                                    if (lw.moving) { lw.moving = null; search.text = "" }
                                    else if (lw.closeArmed !== "") lw.closeArmed = ""
                                    else if (search.text !== "") search.text = ""
                                    else app.launcherShown = false
                                } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_Tab && !shift)) {
                                    lw.sel = lw.step(lw.sel, 1)
                                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) {
                                    lw.sel = lw.step(lw.sel, -1)
                                } else if (e.key === Qt.Key_PageDown) {
                                    let i = lw.sel; for (let k = 0; k < 6; k++) i = lw.step(i, 1); lw.sel = i
                                } else if (e.key === Qt.Key_PageUp) {
                                    let i = lw.sel; for (let k = 0; k < 6; k++) i = lw.step(i, -1); lw.sel = i
                                // ---- a window's actions ----
                                } else if (isWin && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && shift) {
                                    lw.windowAction("new", cur)
                                } else if (cur && cur.kind === "setting" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && shift) {
                                    lw.openSetting(cur)
                                } else if (isWin && ctrl && e.key === Qt.Key_M) {
                                    lw.windowAction("move", cur)
                                } else if (isWin && ctrl && e.key === Qt.Key_F) {
                                    lw.windowAction(shift ? "fullscreen" : "float", cur)
                                } else if (isWin && e.key === Qt.Key_Delete) {
                                    lw.windowAction("close", cur)
                                } else if (cur && cur.kind === "moveto" && lw.moving && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && shift) {
                                    app.launcherShown = false
                                    lw.moveWin(cur.addr, cur.ws, true)
                                    lw.moving = null
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
                // (more than fit across: the row slides to the one in use,
                // and scrolls with the wheel)
                Flickable {
                    id: chipsView
                    Layout.fillWidth: true
                    implicitHeight: 30
                    contentWidth: chipsRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    function showOn() {
                        for (let i = 0; i < chipsRep.count; i++) {
                            const c = chipsRep.itemAt(i)
                            if (!c || !c.on) continue
                            let x = contentX
                            if (c.x - 12 < x) x = c.x - 12
                            else if (c.x + c.width + 12 > x + width) x = c.x + c.width + 12 - width
                            chipsSlide.to = Math.max(0, Math.min(contentWidth - width, x))
                            chipsSlide.restart()
                        }
                    }
                    NumberAnimation { id: chipsSlide; target: chipsView; property: "contentX"; duration: app.dur(220); easing.type: Easing.OutCubic }
                    Connections { target: lw; function onModeChanged() { Qt.callLater(chipsView.showOn) } }
                    WheelHandler {
                        onWheel: e => {
                            const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x
                            chipsView.contentX = Math.max(0, Math.min(chipsView.contentWidth - chipsView.width, chipsView.contentX - d / 2))
                        }
                    }
                Row {
                    id: chipsRow
                    spacing: 6
                    Repeater {
                        id: chipsRep
                        model: [
                            { m: "apps",  label: "Apps",       p: "" },
                            { m: "win",   label: "Windows",    p: "#" },
                            { m: "set",   label: "Settings",   p: "?" },
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
                                    font.family: Theme.uiFont
                                    font.weight: Font.Medium
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    visible: chip.modelData.p !== ""
                                    text: chip.modelData.p
                                    color: chip.on ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.6)
                                                   : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                                    font.family: Theme.uiFont
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
                }

                // ---- the results ----
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: Models.keyed(lw.results, r => r.kind + ":" + (r.addr ? r.addr + ":" + (r.ws || "") : "") + (r.kind === "gows" || r.kind === "moveto" || r.kind === "movefollow" ? r.ws : "") + (r.key || r.id || r.path || r.pid || r.act || r.name || r.emoji || r.title)); objectProp: "_key" }
                    // the list moves its own choice along with a row when the
                    // results change (and stops following lw.sel), so put it back
                    currentIndex: lw.sel
                    onCurrentIndexChanged: if (currentIndex !== lw.sel) currentIndex = Qt.binding(() => lw.sel)
                    onCountChanged: if (currentIndex !== lw.sel) currentIndex = Qt.binding(() => lw.sel)
                    // keep the chosen row in sight (the list doesn't, as the
                    // highlight is placed by hand): on choosing, and as it grows
                    // glides there; a row that's growing is followed straight away
                    cacheBuffer: 600
                    function revealY() {
                        const it = itemAtIndex(lw.sel)
                        if (!it) return NaN
                        const pad = 4, top = originY, bot = originY + Math.max(0, contentHeight - height)
                        let y = contentY
                        // the first row: right at the top, so a heading over it shows
                        if (lw.step(lw.sel, -1) === lw.sel) y = originY
                        else if (it.y - pad < y) y = it.y - pad
                        else if (it.y + it.height + pad > y + height) y = it.y + it.height + pad - height
                        return Math.max(top, Math.min(bot, y))
                    }
                    function reveal(glide) {
                        if (lw.sel < 0 || lw.sel >= count) return
                        const y = revealY()
                        if (isNaN(y)) { scrollAnim.stop(); positionViewAtIndex(lw.sel, ListView.Contain); return }
                        if (Math.abs(y - contentY) < 0.5) return
                        if (glide) { scrollAnim.stop(); scrollAnim.to = y; scrollAnim.start() }
                        else if (!scrollAnim.running) contentY = y
                        else { scrollAnim.stop(); scrollAnim.to = y; scrollAnim.start() }
                    }
                    NumberAnimation { id: scrollAnim; target: list; property: "contentY"; duration: app.dur(220); easing.type: Easing.OutCubic }
                    Connections { target: lw; function onSelChanged() { Qt.callLater(list.reveal, true) } }
                    // follows the chosen row's own place and size, since rows
                    // grow (a window's actions) and are swapped as you type
                    highlightFollowsCurrentItem: false
                    highlight: Rectangle {
                        radius: 16
                        color: app.cPrimC
                        width: list.width
                        visible: list.currentItem !== null && !list.currentItem.isHead
                        y: list.currentItem ? list.currentItem.y : 0
                        height: list.currentItem ? list.currentItem.height : 0
                        Behavior on y { NumberAnimation { duration: app.dur(220); easing.type: Easing.OutCubic } }
                    }
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: index === lw.sel
                        readonly property bool isHead: modelData.kind === "head"
                        readonly property bool isWin: modelData.kind === "win"
                        // a window's actions show under it while it's chosen
                        readonly property bool showActs: isWin && current
                        width: ListView.view.width
                        height: isHead ? 30 : 52 + (showActs ? actFlow.height + 8 : 0)
                        Behavior on height { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        onHeightChanged: if (current) list.reveal(false)

                        // a heading: "Open windows", "Apps"
                        Text {
                            visible: row.isHead
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            text: row.modelData.title
                            color: app.cFaint
                            font.family: Theme.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: app.fs(11)
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.6
                        }

                        RowLayout {
                            visible: !row.isHead
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 52
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 12

                            Item {
                                implicitWidth: 34
                                implicitHeight: 34
                                IconImage {
                                    anchors.centerIn: parent
                                    readonly property bool hasIcon: row.modelData.kind === "app"
                                        || ((row.modelData.kind === "win" || row.modelData.kind === "winclose") && !!row.modelData.icon)
                                    visible: hasIcon
                                    implicitSize: 30
                                    source: hasIcon ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
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
                                             && !((row.modelData.kind === "win" || row.modelData.kind === "winclose") && !!row.modelData.icon)
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
                                    font.family: Theme.uiFont
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
                                    font.family: Theme.uiFont
                                    font.pixelSize: app.fs(11)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    textFormat: Text.PlainText
                                }
                            }
                            // a small tag on the right: "WS 2", "You're here"
                                Rectangle {
                                    visible: !!row.modelData.badge
                                    implicitWidth: badgeText.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 10
                                    color: row.current ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.14)
                                                       : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.07)
                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: row.modelData.badge || ""
                                        color: row.current ? app.cOnPrimC : app.cDim
                                        font.family: Theme.uiFont
                                        font.weight: Font.Medium
                                        font.pixelSize: app.fs(10)
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
                            visible: !row.isHead
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: lw.sel = row.index
                            onClicked: lw.activate(row.index)
                        }
                        // ---- the chosen window's actions ----
                        Flow {
                            id: actFlow
                            visible: row.showActs
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 50
                            anchors.leftMargin: 58
                            spacing: 6
                            Repeater {
                                model: row.showActs ? [
                                    { a: "focus",      g: "open_in_new",       t: "Focus",       k: "\u23ce" },
                                    { a: "move",       g: "move_down",         t: "Move to\u2026", k: "Ctrl+M" },
                                    { a: "float",      g: "picture_in_picture", t: "Float",       k: "Ctrl+F" },
                                    { a: "fullscreen", g: "fullscreen",        t: "Fullscreen",  k: "Ctrl+Shift+F" },
                                    { a: "new",        g: "add",               t: "New window",  k: "Shift+\u23ce" },
                                    { a: "close",      g: "close",             t: lw.closeArmed === row.modelData.addr ? "Press Delete again" : "Close", k: "Del" }
                                ] : []
                                delegate: Rectangle {
                                    id: act
                                    required property var modelData
                                    readonly property bool danger: modelData.a === "close"
                                    implicitWidth: actRow.implicitWidth + 20
                                    implicitHeight: 28
                                    radius: 14
                                    color: actHov.hovered ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.22)
                                         : modelData.a === "focus" ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.18)
                                         : Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.08)
                                    HoverHandler { id: actHov }
                                    Row {
                                        id: actRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: act.modelData.g
                                            color: act.danger ? app.cRed : app.cOnPrimC
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: app.fs(14)
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: act.modelData.t
                                            color: act.danger ? app.cRed : app.cOnPrimC
                                            font.family: Theme.uiFont
                                            font.weight: Font.Medium
                                            font.pixelSize: app.fs(11)
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: act.modelData.k
                                            color: Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.55)
                                            font.family: Theme.uiFont
                                            font.weight: Font.DemiBold
                                            font.pixelSize: app.fs(10)
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: lw.windowAction(act.modelData.a, row.modelData)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: lw.results.length === 0
                        text: lw.mode === "scene" ? "No scenes yet: type a name after @ to save this desktop"
                            : lw.mode === "clip" ? "Nothing copied yet"
                            : lw.mode === "emoji" && !lw.emoji.length ? "Loading emoji\u2026"
                            : lw.mode === "set" && !lw.settingsList.length ? "Loading settings\u2026"
                            : "Nothing matches"
                        color: app.cFaint
                        font.family: Theme.uiFont
                        font.pixelSize: app.fs(13)
                    }
                }

                // ---- hints ----
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lw.moving ? "Enter moves it   \u2022   Shift + Enter moves it and goes there   \u2022   Esc goes back"
                          : lw.results[lw.sel]?.kind === "win"
                          ? "Enter to go to it   \u2022   Ctrl + M to move it   \u2022   Delete to close it   \u2022   Esc to close"
                          : lw.results[lw.sel]?.kind === "setting"
                          ? (lw.results[lw.sel].sw ? "Enter turns it " + (lw.results[lw.sel].badge === "On" ? "off" : "on") + "   \u2022   Shift + Enter opens it in Settings   \u2022   Esc to close"
                                                   : "Enter opens it in Settings   \u2022   Esc to close")
                          : lw.results[lw.sel]?.kind === "file"
                          ? "Enter to open   \u2022   Alt + Enter to show it in its folder   \u2022   Esc to close"
                          : "\u2191 \u2193 to move   \u2022   Enter to open   \u2022   Esc to close"
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                    font.family: Theme.uiFont
                    font.pixelSize: app.fs(11)
                }
            }
        }
    }
    }
}
