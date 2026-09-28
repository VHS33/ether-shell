import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Hyprland
import "lib/colour.mjs" as Colour
import "lib/plugins.mjs" as Plugins
import "lib/models.mjs" as Models
import "lib/keybinds.mjs" as Keybinds
import "lib/overlay.mjs" as Overlay
import "lib/profiles.mjs" as Profiles
import qs.common
import qs.services
import qs.modules.bar
import qs.modules.dock
import qs.modules.launcher
import qs.modules.overview
import qs.modules.ai
import qs.modules.cheatsheet
import qs.modules.clipboard
import qs.modules.media
import qs.modules.notifications
import qs.modules.osd
import qs.modules.power
import qs.modules.sidebar
import qs.modules.settings
import qs.modules.games
import qs.modules.plugins
import qs.modules.scenes
import qs.modules.widgets

ShellRoot {
    id: root


    // ---- weather: services/Weather.qml (a singleton; newer code uses
    //      Weather.<name> directly).  Passed on under the old names. ----
    readonly property var wxHasPlace: Weather.wxHasPlace
    readonly property var wxLat: Weather.wxLat
    readonly property var wxLon: Weather.wxLon
    readonly property var wxPlace: Weather.wxPlace
    readonly property var wxMetric: Weather.wxMetric
    readonly property var wxCond: Weather.wxCond
    readonly property var wxTemp: Weather.wxTemp
    readonly property var wxFeel: Weather.wxFeel
    readonly property var wxHum: Weather.wxHum
    readonly property var wxWind: Weather.wxWind
    readonly property var wxHours: Weather.wxHours
    readonly property var wxHi: Weather.wxHi
    readonly property var wxLo: Weather.wxLo
    readonly property var wxDay: Weather.wxDay
    readonly property var wxOk: Weather.wxOk
    readonly property var wxResults: Weather.wxResults
    readonly property var wxSearching: Weather.wxSearching
    function refreshWeather() { Weather.refreshWeather() }
    function wxSymbol(c, day) { return Weather.wxSymbol(c, day) }
    function searchPlace(q) { Weather.searchPlace(q) }
    function setPlace(r) { Weather.setPlace(r) }

    // ---- colours: services/Theme.qml (a singleton; newer code uses
    //      Theme.<name> directly).  Passed on under the old names. ----
    readonly property color artAccent: Theme.artAccent
    readonly property color artContainer: Theme.artContainer
    readonly property color artOnAccent: Theme.artOnAccent
    readonly property color artOnContainer: Theme.artOnContainer
    readonly property var artValid: Theme.artValid
    readonly property color cBg: Theme.cBg
    readonly property color cBlue: Theme.cBlue
    readonly property color cBorder: Theme.cBorder
    readonly property color cCard: Theme.cCard
    readonly property color cDim: Theme.cDim
    readonly property color cFaint: Theme.cFaint
    readonly property color cFg: Theme.cFg
    readonly property color cGreen: Theme.cGreen
    readonly property color cMauve: Theme.cMauve
    readonly property color cOnAccent: Theme.cOnAccent
    readonly property color cOnPrimC: Theme.cOnPrimC
    readonly property color cPeach: Theme.cPeach
    readonly property color cPrimC: Theme.cPrimC
    readonly property color cRed: Theme.cRed
    readonly property color cSurf: Theme.cSurf
    readonly property color cTeal: Theme.cTeal
    readonly property color cTile: Theme.cTile
    readonly property color cYellow: Theme.cYellow
    readonly property color mBlue: Theme.mBlue
    readonly property color mOnAccent: Theme.mOnAccent
    readonly property var bgA: Theme.bgA
    readonly property var colourFade: Theme.colourFade
    readonly property var darkTheme: Theme.darkTheme
    readonly property var font: Theme.font
    readonly property var isLight: Theme.isLight
    readonly property var pal: Theme.pal
    readonly property var smartOn: Theme.smartOn
    readonly property var themeContrast: Theme.themeContrast
    readonly property var themePrefer: Theme.themePrefer
    readonly property var themeScheme: Theme.themeScheme
    readonly property var vividOn: Theme.vividOn
    readonly property var wallColourfulness: Theme.wallColourfulness
    readonly property var wallLightness: Theme.wallLightness
    readonly property var wallScheme: Theme.wallScheme
    readonly property var wallSecond: Theme.wallSecond
    readonly property var wallSeed: Theme.wallSeed
    readonly property var wallThird: Theme.wallThird
    readonly property var wallWhy: Theme.wallWhy
    function contrast(a, b) { return Theme.contrast(a, b) }
    function readableAccent(colour, bg) { return Theme.readableAccent(colour, bg) }
    function reloadPalette() { return Theme.reloadPalette() }
    function scrim(a) { return Theme.scrim(a) }
    function thirdAccent(primary, tertiary, second, scheme) { return Theme.thirdAccent(primary, tertiary, second, scheme) }
    Binding { target: Theme; property: "nativeOk"; value: root.nativeOk }
    Connections {
        target: Theme
        function onPaletteLoaded() { root.publishLoginSoon() }
    }

    // ---- this machine --------------------------------------------------
    // The monitor the bar, sidebar, dock and panels live on: set on the
    // Displays page, otherwise the first screen Quickshell sees.
    readonly property string mainScreen: {
        const names = Quickshell.screens.map(s => s.name)
        return names.indexOf(cfg.mainScreen) >= 0 ? cfg.mainScreen : (names[0] ?? "")
    }
    property string hostName: ""
    readonly property string userHost: (Quickshell.env("USER") || "") + (hostName ? "@" + hostName : "")
    Process {
        running: true
        command: ["sh", "-c", "cat /etc/hostname 2>/dev/null || hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
    }

    readonly property int pillH: 34
    readonly property int gap:   8

    // ---- bar style ---------------------------------------------------
    // "long": one long pill floating just below the top edge, its
    // sections opening cards that slide out from behind it.  "islands":
    // three separate floating pills.  Settings > Bar > Bar style.
    // (barAttached is the long bar: the sections sit on a shared bar.)
    readonly property bool barAttached: cfg.barStyle !== "islands"
    readonly property int barTop: gap                 // the long bar's distance from the top
    readonly property int barH: 38                    // its height
    readonly property int drawerGap: 6                // between the bar and a card
    // the space reserved at the top of the main screen
    readonly property int zoneH: barAttached ? barTop + barH + 4 : 46
    // where things that hang below the bar start
    readonly property int barBottom: barAttached ? barTop + barH : gap + pillH

    // ---- the drawer: one shape with the long bar ------------------------
    // Each section publishes where its drawer goes, in screen coordinates
    // ({ x, w, h, cx, secW }: the drawer's final left edge, width and
    // height, and the section's centre and width).  BarStrip draws the
    // bar and the open drawer as one outline; the section's own window
    // draws the drawer's contents, clipped to the same growing shape.
    property var leftGeom: null
    property var centerGeom: null
    property var rightGeom: null
    readonly property string drawerNow: !barAttached ? ""
        : cardShown ? "center" : quickShown ? "right" : sysShown ? "left"
        : islandShown ? "island" : ""
    readonly property var drawerNowGeom:
        drawerNow === "island" ? islandGeom
        : drawerNow === "center" ? centerGeom : drawerNow === "right" ? rightGeom
        : drawerNow === "left" ? leftGeom : null
    // the drawer being shown or put away, kept while it closes
    property string drawerWho: ""
    property var drawerGeom: null
    // BarStrip's layer for the open drawer's contents: they're drawn in the
    // same window as the glass, so the two can never fall out of step
    property var drawerLayer: null
    property real drawerP: 0          // 0 closed, 1 fully open

    // Where the drawer is heading: 0 closed, 1 open.  BarStrip animates
    // drawerP toward it on its own render loop, in step with the screen's
    // refresh, and writes each step back here for the sections' windows.
    // drawerRestart asks it to start again from closed (switching drawers).
    property real drawerTo: 0
    property int drawerRestart: 0
    function animateDrawer(to) {
        drawerTo = to
        if (!motionOn) drawerP = to
    }
    // ---- the dynamic island --------------------------------------------------
    // On the long bar, the centre briefly grows a small drawer to show what
    // just happened (a notification, a volume or brightness change, the next
    // song, a timer finishing) and draws it back in.  It's a fifth kind of
    // drawer, drawn by BarStrip like the others, but the lowest: it never
    // interrupts a real drawer, and one opening puts it away.
    // islandData is plain values: { kind: "notif" | "osd" | "track" | "timer", ... }
    readonly property bool islandOn: barAttached
    // notifications in the island: off unless chosen in Settings
    readonly property bool islandNotifs: islandOn && cfg.islandNotifs === true
    readonly property bool islandOsd: islandOn && cfg.islandOsd !== false
    property bool islandShown: false
    property var islandData: ({})
    property var islandGeom: null
    readonly property real mainScreenW: Quickshell.screens.find(s => s.name === mainScreen)?.width ?? 1920
    readonly property real mainScreenH: Quickshell.screens.find(s => s.name === mainScreen)?.height ?? 1080
    function showIsland(d, ms) {
        if (!islandOn || cardShown || quickShown || sysShown || launcherShown) return
        const w = d.kind === "notif" ? 460 : d.kind === "track" ? 420 : d.kind === "timer" ? 380
                : d.kind === "game" ? 440 : d.kind === "scene" ? 400 : 330
        // a different kind of event folds the island away and grows it again
        if (islandShown && islandData.kind !== d.kind) drawerRestart++
        islandData = d
        islandGeom = { x: Math.round((mainScreenW - w) / 2), w: w, h: 62,
                       cx: mainScreenW / 2, secW: 140, flush: "" }
        islandShown = true
        islandHide.interval = ms
        if (!islandHeld) islandHide.restart()
    }
    function hideIsland() { islandHide.stop(); islandShown = false; islandHeld = false }
    // it waits while the mouse is over it
    property bool islandHeld: false
    function holdIsland(on) {
        islandHeld = on
        if (on) islandHide.stop()
        else if (islandShown) { islandHide.interval = 1500; islandHide.restart() }
    }
    Timer { id: islandHide; onTriggered: root.islandShown = false }
    // the next song: once it has settled, and only while something plays
    Timer {
        id: trackIslandLater
        interval: 700
        onTriggered: {
            const p = root.player
            if (!p || !root.osdLive || root.cardShown || root.gameRunning || p.playbackState !== MprisPlaybackState.Playing) return
            if (!(p.trackTitle || "")) return
            root.showIsland({ kind: "track", title: p.trackTitle || "", artist: p.trackArtist || "",
                              art: p.trackArtUrl || "", app: p.identity || "" }, 3500)
        }
    }

    // ---- drawer diagnostics ----
    // Every open, close and switch is logged (to /tmp/qs.log when started
    // the usual way), and `qs ipc call drawer state` prints what the shell
    // believes right now; `reset` forces every drawer shut.
    property real drawerStripP: 0          // BarStrip's own progress, for the log
    // Drawer logging, only with ETHER_DEBUG=1 (the log lives in RAM, under
    // /run, so it shouldn't grow all day).  `qs ipc call drawer state` works
    // either way.
    readonly property bool debugLog: Quickshell.env("ETHER_DEBUG") === "1"
    function drawerLog(what) {
        if (!debugLog) return
        console.log("drawer: " + what + " | now=" + (drawerNow || "-") + " who=" + (drawerWho || "-")
                    + " to=" + drawerTo + " p=" + drawerP.toFixed(3) + " strip=" + drawerStripP.toFixed(3)
                    + " card=" + cardShown + " quick=" + quickShown + " sys=" + sysShown
                    + " launcher=" + launcherShown + " h=" + (drawerGeom ? Math.round(drawerGeom.h) : 0))
    }
    IpcHandler {
        target: "drawer"
        function state(): string {
            return JSON.stringify({ now: root.drawerNow, who: root.drawerWho, to: root.drawerTo,
                p: root.drawerP, strip: root.drawerStripP, curH: root.drawerCurH,
                card: root.cardShown, quick: root.quickShown, sys: root.sysShown,
                launcher: root.launcherShown, attached: root.barAttached,
                geomH: root.drawerGeom ? root.drawerGeom.h : null })
        }
        function reset(): void {
            root.drawerLog("reset asked for")
            root.cardShown = false
            root.quickShown = false
            root.sysShown = false
            root.launcherShown = false
            root.drawerTo = 0
            root.drawerP = 0
            root.drawerRestart++
        }
    }

    onDrawerNowChanged: {
        drawerLog("drawerNow changed")
        if (drawerNow !== "" && drawerNow !== "island" && islandShown) { islandHide.stop(); islandShown = false }
        if (drawerNow !== "") {
            const switching = drawerWho !== "" && drawerWho !== drawerNow && drawerP > 0
            drawerWho = drawerNow
            if (drawerNowGeom) drawerGeom = drawerNowGeom
            if (switching) drawerRestart++
            animateDrawer(1)
        } else {
            animateDrawer(0)
        }
    }
    // safety net: if nothing is meant to be open but the drawer still is,
    // a moment after it should have closed, close it
    Timer {
        interval: root.animNormal + 350
        running: root.drawerNow === "" && root.drawerP > 0
        onTriggered: if (root.drawerNow === "") {
            root.drawerLog("safety net closed a stranded drawer")
            root.drawerP = 0
        }
    }
    onDrawerNowGeomChanged: if (drawerNow !== "" && drawerNowGeom) drawerGeom = drawerNowGeom

    // The shape right now.  The centre drawer widens out from its
    // section's centre; the left and right ones run flush down the bar's
    // end and widen inward from it.  All extend downward at the same time.
    readonly property string drawerFlush: drawerGeom ? (drawerGeom.flush || "") : ""
    readonly property real drawerStartL: !drawerGeom ? 0
        : drawerFlush === "left" ? drawerGeom.x : drawerGeom.cx - drawerGeom.secW * 0.25
    readonly property real drawerStartR: !drawerGeom ? 0
        : drawerFlush === "right" ? drawerGeom.x + drawerGeom.w : drawerGeom.cx + drawerGeom.secW * 0.25
    readonly property real drawerCurX: !drawerGeom ? 0
        : drawerStartL + (drawerGeom.x - drawerStartL) * drawerP
    readonly property real drawerCurW: !drawerGeom ? 0
        : drawerStartR + (drawerGeom.x + drawerGeom.w - drawerStartR) * drawerP - drawerCurX
    readonly property real drawerCurH: drawerGeom ? drawerGeom.h * drawerP : 0


    // ---- the machine's readings: services/System.qml (a singleton; newer
    //      code uses System.<name> directly).  Passed on under the old names. ----
    readonly property var cpuPct: System.cpuPct
    readonly property var gpuPct: System.gpuPct
    readonly property var gpuTemp: System.gpuTemp
    readonly property var gpuMemPct: System.gpuMemPct
    readonly property var gpuWatts: System.gpuWatts
    readonly property var gpuOk: System.gpuOk
    readonly property var netDown: System.netDown
    readonly property var netUp: System.netUp
    readonly property var memPct: System.memPct
    readonly property var cpuHist: System.cpuHist
    readonly property var memHist: System.memHist
    readonly property var gpuHist: System.gpuHist
    readonly property var tempHist: System.tempHist
    readonly property var topProcs: System.topProcs
    readonly property var aboutInfo: System.aboutInfo
    readonly property var uptimeText: System.uptimeText
    function fmtRate(bps) { return System.fmtRate(bps) }
    function refreshAbout() { System.refreshAbout() }
    Binding { target: System; property: "watchProcesses"; value: root.sysShown }

    // Each monitor owns a block of five workspaces: DP-1 gets 1-5, DP-2 gets
    // 6-10.  Hyprland creates them on demand, so the bar shows all five and
    // marks which ones actually have windows.
    // Workspace 6 belongs to the secondary monitor: it exists, but it is
    // not shown in the bar or the overview and cannot be switched to from
    // them.  Everything else lives on the main monitor.
    // the workspaces the bar and overview show, in order; the keys 1-9
    // then 0 walk the same list.  Default 1-10.
    readonly property var mainWorkspaces: {
        const w = cfg.wsMain
        if (Array.isArray(w)) {
            const ok = w.filter(x => Number.isInteger(x) && x > 0)
            if (ok.length) return ok
        }
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }
    readonly property int workspaceCount: mainWorkspaces.length

    // ---- the second monitor's workspaces -----------------------------------
    // The other monitor (Settings > Displays) has workspaces of its own,
    // shown on the bar as a second set numbered 1-5.  SUPER + number goes
    // to the focused monitor's own workspaces (see the "ws" IPC below).
    readonly property string secondScreen: {
        const names = Quickshell.screens.map(s => s.name)
        if (names.indexOf(cfg.secondScreen) >= 0 && cfg.secondScreen !== mainScreen) return cfg.secondScreen
        return names.find(n => n !== mainScreen) ?? ""
    }
    readonly property var secondWorkspaces: {
        const w = cfg.wsSecond
        if (Array.isArray(w)) {
            const ok = w.filter(x => Number.isInteger(x) && x > 0)
            if (ok.length) return ok
        }
        return [11, 12, 13, 14, 15]
    }
    // the workspace showing on the second monitor, and whether it has focus
    readonly property int secondActive: {
        const m = Hyprland.monitors.values.find(m => m.name === secondScreen)
        return m && m.activeWorkspace ? m.activeWorkspace.id : -1
    }
    // the workspace showing on the main monitor, whichever monitor has focus
    readonly property int mainActive: {
        const m = Hyprland.monitors.values.find(m => m.name === mainScreen)
        return m && m.activeWorkspace ? m.activeWorkspace.id : activeWorkspace
    }
    readonly property bool secondFocused: (Hyprland.focusedMonitor?.name ?? "") === secondScreen && secondScreen !== ""

    // the app to show for each workspace: its first window's, which stays the
    // same as focus moves (following the focused window swapped the icon
    // back and forth on every click).  Plain strings, keyed by id.
    readonly property var wsApps: {
        const out = {}
        for (const w of Hyprland.workspaces.values) {
            if (w.id <= 0) continue
            for (const t of (w.toplevels?.values ?? [])) {
                const id = t.wayland?.appId ?? ""
                if (id) { out[w.id] = id; break }
            }
        }
        return out
    }

    // ---- workspace previews ------------------------------------------------
    // The workspace the mouse is resting on in the bar, where (the middle of
    // its slot, in screen coordinates) and on which monitor's list; -1 when
    // none.  WsPreview.qml shows a live miniature of it after a moment.
    property int wsHoverId: -1
    property real wsHoverX: 0
    property string wsHoverScreen: ""
    function wsHoverStart(id, x, screenName) {
        wsHoverId = id
        wsHoverX = x
        wsHoverScreen = screenName
    }
    function wsHoverEnd(id) { if (wsHoverId === id) wsHoverId = -1 }

    // SUPER + number and SUPER + SHIFT + number: the focused monitor's own
    // workspaces.  Hyprland fixes its binds when the config loads and can't
    // ask which monitor has focus, so the keys ask the shell.
    IpcHandler {
        target: "ws"
        function go(n: int): void {
            const list = root.secondFocused ? root.secondWorkspaces : root.mainWorkspaces
            const id = list[n - 1]
            if (id !== undefined) Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
        }
        function send(n: int): void {
            const list = root.secondFocused ? root.secondWorkspaces : root.mainWorkspaces
            const id = list[n - 1]
            if (id !== undefined) Hyprland.dispatch("hl.dsp.window.move({ workspace = " + id + " })")
        }
    }

    function workspacesFor(screenName) {
        const live = {}
        for (const w of Hyprland.workspaces.values) {
            if (w.id > 0) live[w.id] = w
        }
        const out = []
        const ids = screenName !== "" && screenName === root.secondScreen ? root.secondWorkspaces : root.mainWorkspaces
        for (const id of ids) {
            const w = live[id]
            // a workspace with windows; the focused one exists even empty
            const wins = w ? (w.toplevels?.values?.length ?? 1) : 0
            out.push({ id: id, occupied: wins > 0, app: root.wsApps[id] || "" })
        }
        return out
    }

    readonly property int activeWorkspace: Hyprland.focusedWorkspace?.id ?? 1

    property bool cardShown: false
    // the volume popover under the right pill
    property bool volPopShown: false

    // ---- dock: size, auto-hide, pinned apps ------------------------------
    readonly property int dockIcon: {
        const v = Number(cfg.dockIcon)
        return cfg.dockIcon !== undefined && isFinite(v) ? Math.max(20, Math.min(44, Math.round(v))) : 26
    }
    // when the dock hides: "never", "always" (until the pointer reaches the
    // screen's edge), or "windows" (only while a window overlaps it).  The
    // older on/off setting carries over.
    readonly property string dockHide: ["never", "always", "windows"].indexOf(cfg.dockHide) >= 0 ? cfg.dockHide
                                       : (cfg.dockAutoHide === true ? "always" : "never")
    // it can hide (so it doesn't keep windows out of its space)
    readonly property bool dockAutoHide: dockHide !== "never"
    // on every screen, or just the main one
    readonly property bool dockAllScreens: cfg.dockAllScreens === true

    // ---- "windows": does a window overlap the dock? ----
    // rect: the dock's area, in the same logical pixels Hyprland uses.  Any
    // window on the screen's current workspace that overlaps it counts; a
    // fullscreen one always does.
    function dockCovered(screenName, rect) {
        let ws = -999
        for (const m of Hyprland.monitors.values)
            if (m.name === screenName) ws = m.activeWorkspace ? m.activeWorkspace.id : -999
        for (const t of Hyprland.toplevels.values) {
            const o = t?.lastIpcObject
            if (!o || !o.at || !o.size || (o.workspace?.id ?? -1000) !== ws) continue
            if (o.fullscreen && o.fullscreen !== 0) return true
            const x = o.at[0], y = o.at[1], w = o.size[0], h = o.size[1]
            if (x < rect.x + rect.w && rect.x < x + w && y < rect.y + rect.h && rect.y < y + h) return true
        }
        return false
    }
    // window details (where each is) kept fresh while that mode is on: after
    // window events, and every 1.5 s for floating windows being dragged
    // (Hyprland doesn't announce those).  A request over its socket, not a
    // program started.
    Connections {
        target: Hyprland
        enabled: root.dockHide === "windows" && root.dockEnabled
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen",
                 "workspace", "workspacev2", "activewindow", "activewindowv2", "focusedmon"].indexOf(event.name) >= 0)
                dockRefresh.restart()
        }
    }
    Timer { id: dockRefresh; interval: 120; onTriggered: Hyprland.refreshToplevels() }
    Timer {
        interval: 1500
        repeat: true
        running: root.dockHide === "windows" && root.dockEnabled
        onTriggered: Hyprland.refreshToplevels()
    }

    // ---- badges: notifications waiting, by dock item ----
    // matched by the app's desktop file where it gives one, else by name
    readonly property var dockBadges: {
        const out = {}
        const items = dockItems
        for (const n of notifList) {
            const desk = normId(n.desktop || "").toLowerCase()
            const name = String(n.app || "").toLowerCase()
            for (const it of items) {
                const id = String(it.id || "").toLowerCase()
                // "com.spotify.Client" and "spotify" are the same app: one
                // name is a part of the other (parts of four letters or
                // more, so short fragments don't match by chance)
                const part = (a, b) => b.length >= 4 && a.split(".").indexOf(b) >= 0
                const byDesk = desk && id && (desk === id || part(desk, id) || part(id, desk))
                const byName = name && (name === String(it.name).toLowerCase() || name === String(it.cls).toLowerCase())
                if (byDesk || byName) {
                    out[it.key] = (out[it.key] || 0) + 1
                    break
                }
            }
        }
        return out
    }
    // which edge of the screen the dock sits on: "bottom", "left" or "right"
    readonly property string dockEdge: ["bottom", "left", "right"].indexOf(cfg.dockEdge) >= 0 ? cfg.dockEdge : "bottom"
    // space the dock takes at the bottom, for things that sit above it
    // (none when it's down a side)
    readonly property int dockSpace: (dockEnabled && !dockAutoHide && dockEdge === "bottom") ? dockIcon + 28 + gap : 0
    // desktop entry ids, without ".desktop"
    readonly property var dockPinned: Array.isArray(cfg.dockPinned) ? cfg.dockPinned : []

    function normId(id) { return String(id || "").replace(/\.desktop$/, "") }

    // the desktop entry for a window class, by the same steps as iconFor.
    // Returns a live object: use it and let it go, never store it.
    function entryFor(cls) {
        const raw = (cls || "").trim()
        if (!raw) return null
        const low = raw.toLowerCase()
        const ov = root.iconOverrides[low]
        if (ov) { const e0 = DesktopEntries.byId(ov); if (e0) return e0 }
        for (const t of [raw, low, low.replace(/_/g, "-"), low.split(".").pop()]) {
            const e = DesktopEntries.byId(t)
            if (e) return e
        }
        const all = DesktopEntries.applications?.values ?? []
        for (const e of all)
            if ((e.startupClass || "").toLowerCase() === low) return e
        for (const e of all) {
            const id = (e.id || "").toLowerCase()
            if (id === low || id.endsWith("." + low)) return e
        }
        return null
    }

    // Pinned apps first, in pinned order, then running apps that aren't
    // pinned.  Plain values only; windows are referenced by address.
    readonly property var dockItems: {
        const groups = root.dockGroups
        const items = []
        const byPin = {}
        for (const id of root.dockPinned) {
            const e = DesktopEntries.byId(id)
            if (!e) continue
            const it = { key: "pin:" + id, id: id, cls: "", name: String(e.name || id),
                         icon: Quickshell.iconPath(e.icon, true) || Quickshell.iconPath("application-x-executable"),
                         pinned: true, running: false, addrs: [], act: 0, here: 0, n: 0 }
            byPin[id] = it
            items.push(it)
        }
        for (const g of groups) {
            const e = root.entryFor(g.cls)
            const id = e ? root.normId(e.id) : ""
            const pin = id !== "" ? byPin[id] : undefined
            if (pin) {
                pin.cls = g.cls; pin.running = true; pin.addrs = g.addrs
                pin.act = g.act; pin.here = g.here; pin.n = g.n
            } else {
                items.push({ key: "win:" + g.cls, id: id, cls: g.cls,
                             name: e ? String(e.name || g.cls) : g.cls,
                             icon: root.iconFor(g.cls), pinned: false, running: true,
                             addrs: g.addrs, act: g.act, here: g.here, n: g.n })
            }
        }
        return items
    }

    function togglePin(item) {
        const id = item.id || root.normId(root.entryFor(item.cls)?.id)
        if (!id) return false
        const list = root.dockPinned.slice()
        const i = list.indexOf(id)
        if (i >= 0) list.splice(i, 1)
        else list.push(id)
        setting("dockPinned", list)
        return true
    }
    function launchApp(id) { launchEntry(DesktopEntries.byId(id)) }

    // Apps opened from the shell start as its children, so they'd inherit
    // its environment.  The start-up script may keep the shell itself on
    // NVIDIA's driver alone (__EGL_VENDOR_LIBRARY_FILENAMES); apps must not
    // inherit that, so they start exactly as they would from anywhere else.
    // Under UWSM, apps start as their own systemd units (through uwsm-app, its
    // fast client, or uwsm app): contained, stopped cleanly at log out, with
    // their own memory and CPU accounting.  Otherwise they start as before.
    property var appLauncher: []
    Process {
        running: true
        command: ["sh", "-c", "h=$(pgrep -xo Hyprland); command -v uwsm >/dev/null && [ -n \"$h\" ] && grep -q wayland-wm@ /proc/$h/cgroup 2>/dev/null || exit 0; " +
                              "if command -v uwsm-app >/dev/null; then echo uwsm-app; else echo uwsm; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.appLauncher = t === "uwsm-app" ? ["uwsm-app", "--"] : t === "uwsm" ? ["uwsm", "app", "--"] : []
            }
        }
    }
    function launchEntry(e) {
        if (!e) return
        try {
            let cmd = e.command ? Array.from(e.command) : []
            if (!cmd.length) { e.execute(); return }
            if (e.runInTerminal) cmd = [cfg.appTerminalCmd || "kitty", "-e"].concat(cmd)
            Quickshell.execDetached({
                command: root.appLauncher.concat(cmd),
                workingDirectory: e.workingDirectory || Quickshell.env("HOME"),
                environment: root.appEnv
            })
        } catch (err) {
            // older Quickshell without this form: start it the plain way
            e.execute()
        }
    }

    // ---- desktop widgets ---------------------------------------------
    // cfg.widgets: [{ id, type, screen, x, y, text? }], plain values.
    // Arrange mode lifts them above windows so they can be dragged.
    property bool widgetEdit: false
    // the built-in ones, then those from plugins that are on (type
    // "plugin:<its id>", drawn in the same kind of card, see Widgets.qml)
    readonly property var widgetTypes: builtinWidgetTypes.concat(
        plugins.filter(p => p.ok && p.widget && pluginEnabled(p.id) && !pluginErrors[p.id])
               .map(p => ({ type: "plugin:" + p.id, name: p.widget.name, desc: p.widget.description || p.description, plugin: true })))
    // a plugin widget's plugin, if it's on and working (null otherwise: its
    // widgets simply aren't shown, and come back when it's switched on)
    function pluginWidgetInfo(type) {
        const t = String(type || "")
        if (!t.startsWith("plugin:")) return null
        const id = t.slice(7)
        const p = plugins.find(x => x.id === id)
        return p && p.ok && p.widget && pluginEnabled(id) && !pluginErrors[id] ? { id: id, dir: p.dir, file: p.widget.file } : null
    }
    readonly property var builtinWidgetTypes: [
        { type: "clock",    name: "Clock",    desc: "The time and date, large" },
        { type: "weather",  name: "Weather",  desc: "Conditions for your location" },
        { type: "calendar", name: "Calendar", desc: "This month, with holidays and today" },
        { type: "system",   name: "System",   desc: "CPU, memory, GPU and temperature" },
        { type: "media",    name: "Media",    desc: "What's playing, with controls" },
        { type: "note",     name: "Note",     desc: "A sticky note with your own text" }
    ]
    readonly property var widgets: Array.isArray(cfg.widgets) ? cfg.widgets : []

    function addWidget(type, screen) {
        const list = widgets.slice()
        const n = list.filter(w => (w.screen || app.mainScreen) === screen).length
        list.push({ id: String(Date.now()), type: type, screen: screen,
                    x: 96 + n * 40, y: 120 + n * 40,
                    text: type === "note" ? "Write your note in Settings, Widgets" : undefined })
        setting("widgets", list)
    }
    function removeWidget(id) {
        setting("widgets", widgets.filter(w => w.id !== id))
    }
    function updateWidget(id, fields) {
        setting("widgets", widgets.map(w => w.id === id ? Object.assign({}, w, fields) : w))
    }

    // step through the main workspaces from the bar (scroll wheel)
    function cycleWorkspace(dir) {
        const list = root.mainWorkspaces
        let i = list.indexOf(root.activeWorkspace)
        if (i < 0) i = 0
        const next = list[(i + dir + list.length) % list.length]
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + next + " })")
    }
    property bool calShown: false
    property bool sidebarShown: false
    // the sidebar's lower half: 0 calendar with notifications, 1 clipboard
    property int sideTab: 0
    property bool dnd: false
    property bool powerShown: false
    property bool wallShown: false
    property bool overviewShown: false
    property int overviewStep: 0      // bumped by Alt+Tab while open

    // ---- on-screen display -------------------------------------------
    // Watches the sink rather than the keybinds, so it shows for any
    // source of volume change.  The first reading after startup is
    // ignored, or the OSD would flash every time quickshell restarts.
    // ---- plugins ------------------------------------------------------
    // Each plugin is a folder in ~/.config/ether-shell/plugins with a
    // plugin.json (read and checked strictly by lib/plugins.mjs).  They're
    // off until switched on in Settings, Plugins.  A plugin that fails to
    // load is set aside for now, with its error shown there; the rest of the
    // shell carries on.  Plugins get their toolkit as PluginApi.qml.
    readonly property string pluginsDir: Quickshell.env("HOME") + "/.config/ether-shell/plugins"
    property var plugins: []
    property var pluginErrors: ({})
    readonly property var pluginsOn: Array.isArray(cfg.pluginsEnabled) ? cfg.pluginsEnabled : []
    function pluginEnabled(id) { return pluginsOn.indexOf(id) >= 0 }
    function setPluginEnabled(id, on) {
        const l = pluginsOn.filter(x => x !== id)
        if (on) l.push(id)
        const e = Object.assign({}, pluginErrors); delete e[id]; pluginErrors = e     // a fresh try
        setting("pluginsEnabled", l)
    }
    function pluginBarItems(side) {
        return plugins.filter(p => p.ok && p.bar && p.bar.side === side && pluginEnabled(p.id) && !pluginErrors[p.id])
                      .map(p => ({ id: p.id, dir: p.dir, file: p.bar.file }))
    }
    // ---- plugins' launcher parts: loaded once each, kept ready while
    // they're on, and told what's typed (Launcher.qml) ----
    function pluginLaunchers() {
        return plugins.filter(p => p.ok && p.launcher && pluginEnabled(p.id) && !pluginErrors[p.id])
                      .map(p => ({ id: p.id, dir: p.dir, file: p.launcher.file, prefix: p.launcher.prefix, title: p.launcher.title }))
    }
    property var pluginProviders: ({})              // id -> the loaded launcher part
    function setProvider(id, obj) {
        const o = Object.assign({}, pluginProviders)
        if (obj) o[id] = obj; else delete o[id]
        pluginProviders = o
    }
    Instantiator {
        model: ScriptModel { values: Models.keyed(root.pluginLaunchers(), p => p.id); objectProp: "_key" }
        delegate: QtObject {
            id: holder
            required property var modelData
            property QtObject api: PluginApi { app: root; pluginId: holder.modelData.id; dir: holder.modelData.dir }
            property QtObject obj: null
            Component.onCompleted: {
                const c = Qt.createComponent("file://" + modelData.dir + "/" + modelData.file)
                if (c.status !== Component.Ready) {
                    root.pluginFailed(modelData.id, c.status === Component.Error ? c.errorString() : "its launcher part didn't load")
                    return
                }
                obj = c.createObject(holder, { ether: api })
                if (!obj) { root.pluginFailed(modelData.id, "its launcher part couldn't be created"); return }
                root.setProvider(modelData.id, obj)
            }
            Component.onDestruction: {
                root.setProvider(modelData.id, null)
                if (obj) obj.destroy()
            }
        }
    }

    function pluginFailed(id, message) {
        const e = Object.assign({}, pluginErrors)
        e[id] = String(message).trim().slice(0, 600)
        pluginErrors = e
        console.log("plugin " + id + " set aside: " + e[id])
    }
    function pluginSetting(id, key, value) {
        const all = JSON.parse(JSON.stringify(cfg.pluginSettings || {}))
        all[id] = all[id] || {}
        all[id][String(key)] = value
        setting("pluginSettings", all)
    }
    // a command a plugin runs: a list of plain strings, never a shell line
    function pluginRun(id, command) {
        if (!Plugins.validCommand(command)) { console.log("plugin " + id + ": not a command: " + JSON.stringify(command)); return }
        Quickshell.execDetached({ command: command })
    }
    // ...and one whose output it wants (at most 16 at a time)
    property int pluginReads: 0
    function pluginRead(id, command, callback) {
        if (!Plugins.validCommand(command) || typeof callback !== "function") { console.log("plugin " + id + ": not a command: " + JSON.stringify(command)); return }
        if (pluginReads >= 16) { console.log("plugin " + id + ": too many commands at once"); return }
        pluginReads++
        pluginReader.createObject(root, { command: command, callback: callback, pluginId: id }).running = true
    }
    Component {
        id: pluginReader
        Process {
            id: pr
            property var callback
            property string pluginId
            property int code: 0
            onExited: code => pr.code = code
            stdout: StdioCollector {
                onStreamFinished: {
                    try { pr.callback(text, pr.code) }
                    catch (e) { console.log("plugin " + pr.pluginId + ": " + e) }
                    root.pluginReads = Math.max(0, root.pluginReads - 1)
                    pr.destroy()
                }
            }
        }
    }
    function scanPlugins() { pluginScan.running = true }
    // Settings, Plugins, "Check plugins": the folder read again, and any
    // plugin set aside after an error given another try
    function reloadPlugins() { pluginErrors = ({}); scanPlugins() }
    Process { id: pluginFolder }
    function openPluginsFolder() {
        pluginFolder.command = ["sh", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "sh", pluginsDir]
        pluginFolder.running = true
    }
    Process {
        id: pluginScan
        running: true
        command: ["sh", "-c", 'for d in "$1"/*/; do [ -f "$d/plugin.json" ] || continue; ' +
                              'printf "\\036%s\\037" "$(basename "$d")"; head -c 65536 "$d/plugin.json"; done', "sh", root.pluginsDir]
        stdout: StdioCollector { onStreamFinished: root.plugins = Plugins.parseScan(text, root.pluginsDir) }
    }
    IpcHandler {
        target: "plugins"
        // look for plugins again (and give set-aside ones another try)
        function reload(): void { root.reloadPlugins() }
        // `ether plugin list`: a line per plugin, as the Plugins page sees
        // them: id|state|name|what it adds, or why it can't be used
        // (state: on, off, set-aside, unusable)
        function list(): string {
            return root.plugins.map(p => {
                const state = !p.ok ? "unusable" : root.pluginErrors[p.id] ? "set-aside" : root.pluginEnabled(p.id) ? "on" : "off"
                const adds = [p.bar ? "bar item (" + p.bar.side + ")" : "",
                              p.launcher ? "launcher" + (p.launcher.prefix ? " (" + p.launcher.prefix + ")" : "") : "",
                              p.widget ? "widget" : "", p.settings ? "settings" : ""].filter(x => x).join(", ")
                const why = !p.ok ? p.errors.join("; ") : root.pluginErrors[p.id] ? String(root.pluginErrors[p.id]).split("\n")[0] : adds
                return [p.id, state, p.name, why].map(x => String(x).replace(/[|\n]/g, " ")).join("|")
            }).join("\n")
        }
    }

    // ---- clipboard history -------------------------------------------
    // Entries are { id, preview } plain strings.  Natively (the plugin talks
    // to the compositor's clipboard; see NativeStats.qml) the history keeps
    // itself up to date; otherwise cliphist keeps it, fed by wl-paste
    // watchers this shell starts only then, and is asked when needed.


    // refreshes wait until the sidebar has slid in, so they don't compete
    // with the opening frames
    onSidebarShownChanged: if (sidebarShown) { sideRefresh.restart(); Notifications.notifUnseen = 0 }
    Timer {
        id: sideRefresh
        interval: 260
        onTriggered: root.refreshSidebar()
    }
    function refreshSidebar() {
        readBrightness()
        root.readClipboard()
        NetworkService.refreshNet()
    }




    // ---- keybind cheatsheet ------------------------------------------
    // Read from hyprctl rather than maintained by hand, so it cannot
    // drift from the real config.
    // settings panel; the audio pages live inside it
    property bool settingsShown: false
    // 0 general, 1 glass, 2 theme, 3 wallpaper, 4 bar, 5 windows,
    // 6 dock, 7 notifications, 8 idle, 9 displays, 10 keyboard,
    // 11 mouse, 12 output, 13 apps, 14 input, 15 recording,
    // 16 weather, 17 calendar, 18 about, 19 widgets, 20 lock screen,
    // 21 default apps
    property int settingsPage: 0

    property bool cheatShown: false
    onCheatShownChanged: if (cheatShown) Shortcuts.refreshCheat()
    // ---- motion ----------------------------------------------------------
    // Every animation in the shell takes its length from here, so the
    // desktop moves as one: three speeds, one curve, all following
    // Settings > Windows > Animation speed, and nothing moves when
    // animations are off there.
    readonly property bool motionOn: cfg.animations !== false && !gameMode
    readonly property real motionScale:
        Math.max(0.25, Math.min(4, Number(cfg.animSpeed) || 1))
    readonly property int animQuick: dur(140)     // hovers, colours, small changes
    readonly property int animNormal: dur(240)    // panels opening and closing
    readonly property int animSlow: dur(360)      // big movements
    readonly property int easeOut: Easing.OutCubic
    function dur(ms) { return motionOn ? Math.round(ms / motionScale) : 0 }

    // ---- on-screen display ----------------------------------------------
    // One bubble for volume, microphone, brightness and night light.
    // osdKind says which; osdValue is 0-1; osdMuted means muted / off.
    property bool osdShown: false
    property string osdKind: "volume"
    property real osdValue: 0
    property bool osdMuted: false
    // PipeWire reports its starting state as "changes" while the shell
    // loads; nothing shows until that has settled
    property bool osdLive: false
    Timer {
        running: true
        interval: 2500
        onTriggered: root.osdLive = true
    }

    function showOsdOf(kind, value, muted) {
        root.osdKind = kind
        root.osdValue = Math.max(0, Math.min(1, value))
        root.osdMuted = muted
        if (!root.osdLive) return
        // in the island when it can take it; otherwise the usual pop-up
        if (root.islandOsd && !root.cardShown && !root.quickShown && !root.sysShown && !root.launcherShown) {
            root.showIsland({ kind: "osd", osdKind: kind, value: root.osdValue, muted: muted }, root.osdMs)
            return
        }
        root.osdShown = true
        osdTimer.restart()
    }
    function showOsd(vol, muted) { showOsdOf("volume", vol, muted) }

    Timer {
        id: osdTimer
        interval: root.osdMs
        onTriggered: root.osdShown = false
    }

    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            root.showOsd(Audio.sink.audio.volume,
                         Audio.sink.audio.muted)
        }
        function onMutedChanged() {
            root.showOsd(Audio.sink.audio.volume,
                         Audio.sink.audio.muted)
        }
    }

    // the microphone only shows when it's muted or unmuted, from anywhere
    Connections {
        target: Audio.source?.audio ?? null
        function onMutedChanged() {
            const a = Audio.source.audio
            root.showOsdOf("mic", a.volume, a.muted)
        }
    }

    // window positions come from Hyprland's IPC snapshot; refresh it each
    // time the overview opens so previews sit where the windows really are
    onOverviewShownChanged: {
        if (overviewShown) {
            Hyprland.refreshToplevels()
            root.sidebarShown = false
            root.cardShown = false
        }
    }


    // ---- notifications: services/Notifications.qml (a singleton; newer
    //      code uses it directly).  Passed on under the old names. ----
    readonly property var notifList: Notifications.notifList
    readonly property var popups: Notifications.popups
    readonly property var notifRefs: Notifications.notifRefs
    readonly property var notifCount: Notifications.notifCount
    readonly property var notifGroups: Notifications.notifGroups
    readonly property var notifUnseen: Notifications.notifUnseen
    readonly property var notifLoaded: Notifications.notifLoaded
    readonly property var notifSeq: Notifications.notifSeq
    function dismissPopup(id) { Notifications.dismissPopup(id) }
    function invokeNotifAction(id, key) { Notifications.invokeNotifAction(id, key) }
    function sendNotifReply(id, text) { Notifications.sendNotifReply(id, text) }
    function dismissGroup(appName) { Notifications.dismissGroup(appName) }
    function notifWhen(n) { return Notifications.notifWhen(n) }
    function dismissNotif(id) { Notifications.dismissNotif(id) }
    function clearNotifs() { Notifications.clearNotifs() }
    Binding { target: Notifications; property: "quiet"; value: root.quietNow }
    Binding { target: Notifications; property: "islandNotifs"; value: root.islandNotifs }
    Binding { target: Notifications; property: "panelsOpen"; value: root.quickShown || root.sidebarShown }
    // one arrived for the island: show it there
    Connections {
        target: Notifications
        function onArrivedForIsland(n) {
            root.showIsland({ kind: "notif", id: n.id, app: n.app, summary: n.summary, body: n.body,
                              icon: root.notifIcon(n), urgent: n.urgency >= 2,
                              canOpen: (n.actions || []).some(a => a.key === "default") },
                            n.urgency >= 2 ? 8000 : 4500)
        }
    }

    // an icon for a notification: a file path, an icon name, or the
    // sending app's own icon
    function notifIcon(n) {
        const ic = n.icon || ""
        if (ic.startsWith("/")) return "file://" + ic
        if (ic.startsWith("file:") || ic.startsWith("image:")) return ic
        if (ic !== "") {
            const p = Quickshell.iconPath(ic, true)
            if (p) return p
        }
        return iconFor(n.desktop || n.app)
    }
    property int monthOffset: 0
    property string selectedKey: ""

    // Hyprland publishes its client list natively, so the dock no longer
    // needs the KWin script and journal tail it used on Plasma.
    //
    // No window titles in here: they change all the time (a browser tab, the
    // next song, a terminal command), and each change used to rebuild the
    // whole dock, every icon recreated.  The menu and tooltips read them
    // when they're shown (windowsOf).
    readonly property var dockGroups: {
        const out = []
        const idx = {}
        const active = Hyprland.activeToplevel

        const here = root.activeWorkspace

        for (const t of Hyprland.toplevels.values) {
            if (!t) continue
            const ipc = t.lastIpcObject
            const cls = ipc?.class ?? ""
            if (!cls.length) continue
            const k = cls.toLowerCase()

            // a window counts as "here" if it sits on the workspace you
            // are currently looking at; everything else is dimmed rather
            // than hidden, so the dock stays a complete answer to
            // "what do I have open?"
            const onThis = (ipc?.workspace?.id ?? -1) === here

            if (idx[k] === undefined) {
                idx[k] = out.length
                out.push({
                    cls: cls,
                    addrs: [t.lastIpcObject?.address ?? ""],
                    act: t === active ? 1 : 0,
                    here: onThis ? 1 : 0,
                    n: 1
                })
            } else {
                const g = out[idx[k]]
                g.addrs.push(t.lastIpcObject?.address ?? "")
                g.n += 1
                if (t === active) g.act = 1
                if (onThis) g.here = 1
            }
        }
        return out
    }

    // an app's windows, read when they're shown (the dock's menu and
    // tooltips): [{ addr, title, ws, active }]
    function windowsOf(addrs) {
        const out = []
        const active = Hyprland.activeToplevel
        for (const t of Hyprland.toplevels.values) {
            const a = t?.lastIpcObject?.address ?? ""
            if (!a || addrs.indexOf(a) < 0) continue
            out.push({ addr: a, title: String(t.title || ""), ws: t.lastIpcObject?.workspace?.name ?? "", active: t === active })
        }
        return out
    }
    // an app's windows themselves, for live previews (the dock, on hover)
    function toplevelsOf(addrs) {
        const out = []
        for (const t of Hyprland.toplevels.values) {
            const a = t?.lastIpcObject?.address ?? ""
            if (a && addrs.indexOf(a) >= 0) out.push(t)
        }
        return out
    }
    // a pinned app moved to another place in the dock (or a running one
    // pinned right there), `index` counting the pinned apps as they are now
    function movePin(item, index) {
        const id = item.id || root.normId(root.entryFor(item.cls)?.id)
        if (!id) return false
        const list = root.dockPinned.slice()
        const from = list.indexOf(id)
        if (from >= 0) {
            list.splice(from, 1)
            if (from < index) index--
        }
        list.splice(Math.max(0, Math.min(index, list.length)), 0, id)
        if (JSON.stringify(list) !== JSON.stringify(root.dockPinned)) setting("dockPinned", list)
        return true
    }
    function focusWindow(addr) {
        if (addr) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }
    // asks the app to close it (so it can save first), like SUPER + Q
    function closeWindow(addr) {
        if (addr) Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + addr + "\" })")
    }
    // one of an app's own actions (its desktop file's: "New private
    // window" and so on), started the way apps are
    function launchAction(id, index) {
        const e = DesktopEntries.byId(id)
        const a = e && e.actions ? e.actions[index] : null
        if (!a) return
        try {
            const cmd = a.command ? Array.from(a.command) : []
            if (!cmd.length) { a.execute(); return }
            Quickshell.execDetached({ command: root.appLauncher.concat(cmd),
                                      workingDirectory: e.workingDirectory || Quickshell.env("HOME"),
                                      environment: root.appEnv })
        } catch (err) { a.execute() }
    }
    // an app started from the dock: its icon pulses until a window appears
    // (or 15 seconds pass)
    property var dockStarting: ({})
    function dockLaunch(id) {
        const s = Object.assign({}, dockStarting); s[id] = Date.now(); dockStarting = s
        startingTimeout.restart()
        launchApp(id)
    }
    function dockStarted(id) {
        if (dockStarting[id] === undefined) return
        const s = Object.assign({}, dockStarting); delete s[id]; dockStarting = s
    }
    Timer {
        id: startingTimeout
        interval: 15000
        onTriggered: root.dockStarting = ({})
    }
    // a started app has a window now
    onDockItemsChanged: {
        for (const it of dockItems) if (it.running && it.id && dockStarting[it.id] !== undefined) dockStarted(it.id)
    }

    property var cycleIdx: ({})

    function cycleGroup(cls, addrs, back) {
        const k = (cls || "?").toLowerCase()
        const cur = root.cycleIdx[k] === undefined ? -1 : root.cycleIdx[k]
        const next = back ? (cur < 0 ? addrs.length - 1 : (cur - 1 + addrs.length) % addrs.length) : (cur + 1) % addrs.length
        const m = root.cycleIdx
        m[k] = next
        root.cycleIdx = m

        const addr = addrs[next]
        if (addr) {
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:"
                              + addr + "\" })")
        }
    }

    // ---- sound and media: services/Audio.qml and Media.qml (singletons;
    //      newer code uses them directly).  Passed on under the old names. ----
    readonly property var pickedPlayer: Media.pickedPlayer
    readonly property var player: Media.player
    readonly property var playerList: Media.playerList
    readonly property var playing: Media.playing
    readonly property var lyricsOn: Media.lyricsOn
    readonly property var lyrics: Media.lyrics
    readonly property var lyricsPlain: Media.lyricsPlain
    readonly property var lyricsState: Media.lyricsState
    readonly property var lyricIndex: Media.lyricIndex
    readonly property var cavaBars: Media.cavaBars
    function fmtTime(sec) { return Media.fmtTime(sec) }
    function fetchLyrics() { Media.fetchLyrics() }
    Binding { target: Media; property: "drawerOpen"; value: root.cardShown }
    Binding { target: Media; property: "sidebarOpen"; value: root.sidebarShown }
    Binding { target: Media; property: "nativeOk"; value: root.nativeOk }
    Connections {
        target: Media
        function onTrackKeyChanged() { trackIslandLater.restart() }
    }

    onPlayerChanged: if (!player) cardShown = false

    // one island open at a time: opening one closes the others
    onCardShownChanged: if (cardShown) {
        quickShown = false; sysShown = false; launcherShown = false
        Media.fetchLyricsSoon()
    }
    onQuickShownChanged: if (quickShown) {
        BluetoothService.check()             // an adapter plugged in since?
        cardShown = false; sysShown = false; launcherShown = false
        Notifications.notifUnseen = 0
        quickSettle.restart()
    }
    // Brightness (ddcutil, slow), network, Wi-Fi, Bluetooth and the
    // clipboard are read once quick settings has finished opening, so the
    // opening animation has the machine to itself.
    Timer {
        id: quickSettle
        interval: Math.round(root.animSlow * 1.3) + 40
        onTriggered: if (root.quickShown) {
            root.refreshSidebar()
            root.refreshWifi(false)
            root.refreshBt()
        }
    }

    // ---- game mode and keep awake ---------------------------------------
    // Game mode: blur, shadows and animations off everywhere (Hyprland
    // through shell-settings.lua, the shell through motionOn).  Keep
    // awake: holds a systemd idle inhibitor, which hypridle honours, so
    // the screen doesn't lock or blank while it's on.
    // ---- games (GameWatch.qml) ------------------------------------------
    // gameRunning: a game is running now.  Automatic game mode then applies
    // everything Game mode does, without changing the user's own setting;
    // notifications are held (still kept in history) without touching Do
    // not disturb.  Both can be switched off in Settings > Windows > Gaming.
    property bool gameRunning: false
    property var playWeek: []                 // this week's games, for the playtime card
    readonly property bool autoGame: gameRunning && cfg.autoGameMode !== false
    readonly property bool quietNow: dnd || (gameRunning && cfg.gameQuiet !== false)
    function markGame() { gameWatch.markFocused() }

    // ---- scenes (Scenes.qml): saved desktops ----
    property var sceneList: []                // [{ name, count, saved }], newest first
    function sceneSave(name) { scenesObj.save(name) }
    function sceneRestore(name) { scenesObj.restore(name) }
    function sceneRemove(name) { scenesObj.remove(name) }
    // "2 h 13 min", "45 min", "under a minute"
    function fmtPlay(secs) {
        const m = Math.round(secs / 60)
        if (m < 1) return "under a minute"
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), r = m % 60
        return r ? h + " h " + r + " min" : h + " h"
    }

    readonly property bool gameMode: cfg.gameMode === true || autoGame
    function toggleGameMode() { setting("gameMode", !gameMode) }
    property bool keepAwake: false
    Process {
        running: root.keepAwake
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=Ether Shell",
                  "--why=Keep awake is on", "sleep", "infinity"]
    }

    // ---- the network and Bluetooth: services/NetworkService.qml and
    //      BluetoothService.qml (singletons; newer code uses them
    //      directly).  Passed on under the old names. ----
    readonly property var wifiHas: NetworkService.wifiHas
    readonly property var wifiOn: NetworkService.wifiOn
    readonly property var wifiList: NetworkService.wifiList
    readonly property var wifiBusy: NetworkService.wifiBusy
    readonly property var wifiAskPw: NetworkService.wifiAskPw
    readonly property var wifiError: NetworkService.wifiError
    readonly property var netKind: NetworkService.netKind
    readonly property var netName: NetworkService.netName
    readonly property var netNativeOn: NetworkService.netNativeOn
    readonly property var btHas: BluetoothService.btHas
    readonly property var btOn: BluetoothService.btOn
    readonly property var btList: BluetoothService.btList
    readonly property var btScanning: BluetoothService.btScanning
    readonly property var btBusy: BluetoothService.btBusy
    readonly property var btNativeOn: BluetoothService.btNativeOn
    function refreshWifi(rescan) { NetworkService.refreshWifi(rescan) }
    function wifiToggle() { NetworkService.wifiToggle() }
    function wifiConnect(ssid, pw) { NetworkService.wifiConnect(ssid, pw) }
    function wifiDisconnect(ssid) { NetworkService.wifiDisconnect(ssid) }
    function wifiCancelPw() { NetworkService.wifiCancelPw() }
    function refreshBt() { BluetoothService.refreshBt() }
    function btToggle() { BluetoothService.btToggle() }
    function btScan() { BluetoothService.btScan() }
    function btConnect(mac, paired) { BluetoothService.btConnect(mac, paired) }
    function btDisconnect(mac) { BluetoothService.btDisconnect(mac) }

    // ---- AI assistant -----------------------------------------------------
    // A chat with whichever provider the user picks in Settings: Anthropic,
    // Google or OpenAI, with their own API key.  Keys live one per file in
    // ~/.config/ether/ai/, readable only by the user, and are written
    // through stdin, so they never show up in a process list.  Requests
    // stream, so replies appear as they're written.
    property bool aiShown: false
    onAiShownChanged: if (aiShown) { sysShown = false; refreshAiKeys() }
    IpcHandler {
        target: "ai"
        function toggle(): void { root.aiShown = !root.aiShown }
        function open(): void { root.aiShown = true }
        function close(): void { root.aiShown = false }
    }
    // ---- timer and stopwatch ---------------------------------------------
    // Times are kept against the clock (when it ends, when it started), not
    // counted by ticks, so they stay right even if the shell is busy.  The
    // tick only refreshes what's shown.

    // ---- launcher --------------------------------------------------------
    // SUPER (tapped) or `qs ipc call launcher toggle`.  It grows out of the
    // centre of the long bar like the other drawers; in the islands style
    // it's a card under the bar.
    property bool launcherShown: false
    property var launcherGeom: null
    onLauncherShownChanged: if (launcherShown) {
        cardShown = false; quickShown = false; sysShown = false
        root.readClipboard()          // fresh clipboard history for ;
    }
    // how often each app has been opened from the launcher, for ranking
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherShown = !root.launcherShown }
        function open(): void { root.launcherShown = true }
        function close(): void { root.launcherShown = false }
        // SUPER + V: straight into clipboard history (the launcher's ; mode)
        function clipboard(): void { root.launcherInMode(";") }
        // SUPER + period: straight into emoji
        function emoji(): void { root.launcherInMode(":") }
    }
    // what the search box starts with when the launcher opens (";" for the
    // clipboard); cleared once used
    property string launcherPrefill: ""
    // open the launcher in one mode; the same key again closes it
    function launcherInMode(prefix) {
        if (launcherShown && launcherPrefill === prefix) { launcherShown = false; return }
        launcherPrefill = prefix
        if (launcherShown) launcherPrefillNow++
        else launcherShown = true
    }
    property int launcherPrefillNow: 0
    onCalShownChanged: if (!calShown) { monthOffset = 0; selectedKey = "" }




    function toggleMark(key) {
        if (root.markedDays.indexOf(key) === -1)
            root.markedDays = root.markedDays.concat([key])
        else
            root.markedDays = root.markedDays.filter(k => k !== key)
        saveMarks()
    }

    // clicking a day selects it and opens its details (notes, holiday,
    // mark); clicking it again closes them
    function dayClicked(key) {
        root.selectedKey = root.selectedKey === key ? "" : key
    }

    IpcHandler {
        target: "audio"
        function toggle(): void {
            if (root.settingsShown && root.settingsPage === 12) {
                root.settingsShown = false
            } else {
                root.settingsPage = 12
                root.settingsShown = true
            }
        }
        function open(): void { root.settingsPage = 12; root.settingsShown = true }
        function close(): void { root.settingsShown = false }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.cheatShown = !root.cheatShown }
        function open(): void { root.cheatShown = true }
        function close(): void { root.cheatShown = false }
    }

    IpcHandler {
        target: "clipboard"
        // SUPER + V: the clipboard panel down the right side (ClipPanel.qml)
        function toggle(): void { root.clipShown = !root.clipShown }
        function open(): void { root.clipShown = true }
        function close(): void { root.clipShown = false }
    }

    // ---- the clipboard panel ----------------------------------------------
    // History comes from cliphist (clipItems).  Copied pictures show as
    // thumbnails: each is decoded once into ~/.cache/ether/clip/ and reused;
    // clipThumbVer changes when new ones are ready.
    property bool clipShown: false
    onClipShownChanged: if (clipShown) {
        launcherShown = false
        root.readClipboard()
    }
    // "[[ binary data 55 KiB png 1920x1080 ]]" -> { ext: "png", size: "1920x1080" }
    IpcHandler {
        target: "overview"
        // Alt+Tab while it's already open steps to the next workspace
        // (releasing Alt then goes there), like a window switcher
        function toggle(): void {
            if (root.overviewShown) root.overviewStep++
            else root.overviewShown = true
        }
        function open(): void { root.overviewShown = true }
        function close(): void { root.overviewShown = false }
    }

    IpcHandler {
        target: "sidebar"
        function toggle(): void { root.sidebarShown = !root.sidebarShown }
        function open(): void { root.sidebarShown = true }
        function close(): void { root.sidebarShown = false }
    }


    Spacer { app: root }
    // the attached strip, created first so everything else sits above it
    BarStrip { app: root }
    BarLeft { app: root }
    BarCenter { app: root }
    BarRight { app: root }
    MediaCard { app: root }
    Sidebar { app: root }
    Dock { app: root }
    PowerMenu { app: root }
    Overview { app: root }
    Osd { app: root }
    Cheatsheet { app: root }
    SettingsPanel { app: root }
    VolumePop { app: root }
    // under the islands, so a click outside one closes it
    CenterIsland { app: root }
    Launcher { app: root }
    RightIsland { app: root }
    LeftIsland { app: root }
    WsPreview { app: root }
    AiPanel { app: root }
    ClipPanel { app: root }
    GameWatch { id: gameWatch; app: root }
    Scenes { id: scenesObj; app: root }
    Widgets { app: root }
    Popups { app: root }


    // `clock` was an id, which the split modules cannot see; expose the
    // time as a root property instead so they can bind to app.now
    property date now: new Date()

    // The time only moves on when the minute changes (or every second if
    // the clock shows seconds): everything built from it, the calendars
    // included, would otherwise be worked out again every second.
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            const d = new Date()
            if (root.cfg.clockSeconds === true || d.getMinutes() !== root.now.getMinutes()
                    || d.getHours() !== root.now.getHours() || d.getDate() !== root.now.getDate())
                root.now = d
        }
    }


    // ---- the native readers, when the plugin is installed ----
    // NativeStats.qml imports Ether.Native (built from native/ by the
    // installer).  If it loads, it does the stats and the visualiser, and the
    // readers above never start.  If not, it fails to load, and they do.
    Loader {
        id: nativeLoader
        source: "services/NativeStats.qml"
        onLoaded: { item.home = Quickshell.env("HOME"); item.app = root }
        onStatusChanged: if (status === Loader.Error) System.startFallbackReaders()
    }
    readonly property bool nativeOk: nativeLoader.status === Loader.Ready

    property bool sysShown: false
    onSysShownChanged: if (sysShown) {
        aiShown = false
        System.refreshUptime()
        cardShown = false
        quickShown = false
        launcherShown = false
    }


    // SUPER + N: quick settings.  SUPER + X: the power menu.
    IpcHandler {
        target: "quick"
        function toggle(): void { root.quickShown = !root.quickShown }
    }
    IpcHandler {
        target: "power"
        function toggle(): void { root.powerShown = !root.powerShown }
    }

    // SUPER + H: the wallpaper selector (Settings, on its Wallpaper page)
    IpcHandler {
        target: "wallpaper"
        function toggle(): void {
            if (root.settingsShown && root.settingsPage === 3) root.settingsShown = false
            else { root.settingsPage = 3; root.settingsShown = true }
        }
        function open(): void { root.settingsPage = 3; root.settingsShown = true }
        function random(): void { root.randomWallpaper() }
        // setwall hands wallpapers over here, so they're measured and themed
        // exactly like one picked in the selector
        function set(path: string): void { root.applyWallpaper(path) }
        // re-measure and re-theme the current wallpaper
        function reapply(): void { if (root.currentWall) root.applyWallpaper(root.currentWall) }
    }

    // ---- wallpapers: services/Wallpaper.qml (a singleton; newer code uses
    //      Wallpaper.<name> directly).  Passed on under the old names. ----
    readonly property var currentWall: Wallpaper.currentWall
    readonly property var loginBusy: Wallpaper.loginBusy
    readonly property var loginDefault: Wallpaper.loginDefault
    readonly property var loginError: Wallpaper.loginError
    readonly property var loginFollows: Wallpaper.loginFollows
    readonly property var themeBusy: Wallpaper.themeBusy
    readonly property var wallBusy: Wallpaper.wallBusy
    readonly property var wallPalettes: Wallpaper.wallPalettes
    readonly property var wallpapers: Wallpaper.wallpapers
    function applyWallpaper(path) { return Wallpaper.applyWallpaper(path) }
    function paletteProbed(path, lightness, scheme, seed, second, why, third) { return Wallpaper.paletteProbed(path, lightness, scheme, seed, second, why, third) }
    function previewLogin() { return Wallpaper.previewLogin() }
    function publishLoginSoon() { return Wallpaper.publishLoginSoon() }
    function randomWallpaper() { return Wallpaper.randomWallpaper() }
    function setLoginBackground(path) { return Wallpaper.setLoginBackground(path) }
    function setLoginFollow(on) { return Wallpaper.setLoginFollow(on) }
    function wallMeasured(lightness, scheme, colourfulness, seed, second, why, source, third) { return Wallpaper.wallMeasured(lightness, scheme, colourfulness, seed, second, why, source, third) }
    Binding { target: Wallpaper; property: "nativeItem"; value: root.nativeOk ? nativeLoader.item : null }
    Binding { target: Wallpaper; property: "mainScreen"; value: root.mainScreen }
    Binding { target: Wallpaper; property: "listing"; value: root.settingsShown && root.settingsPage === 3 }
    Connections {
        target: Wallpaper
        function onWidgetsShouldMove() { arrangeLater.restart() }
    }

    // ---- widgets that keep clear of the wallpaper's subject ----
    // With cfg.widgetsAuto on, a new wallpaper moves the main screen's widgets
    // to its calmest places (skies, walls, soft blur; not faces, buildings or
    // foliage), most important first, clear of each other, the bar and the
    // dock.  Only to places that are genuinely calm: on a wallpaper that's
    // busy everywhere, they stay where they are.
    property var widgetSizes: ({})            // { id: [w, h] }, reported by the widgets
    function noteWidgetSize(id, w, h) {
        if (!id || w <= 0 || h <= 0) return
        const cur = widgetSizes[id]
        if (cur && cur[0] === w && cur[1] === h) return
        const s = Object.assign({}, widgetSizes); s[id] = [w, h]; widgetSizes = s
    }
    readonly property var widgetOrder: ["clock", "weather", "calendar", "media", "system", "note"]
    Timer { id: arrangeLater; interval: 400; onTriggered: root.arrangeWidgets() }
    // returns how many widgets moved, or -1 when it can't (no plugin, not measured yet)
    function arrangeWidgets() {
        if (!nativeOk || !nativeLoader.item) return -1
        const mine = widgets.filter(w => (w.screen || mainScreen) === mainScreen)
            .slice().sort((a, b) => widgetOrder.indexOf(a.type) - widgetOrder.indexOf(b.type))
        if (!mine.length) return 0
        const sizes = mine.map(w => widgetSizes[w.id] || [360, 200])
        const spots = nativeLoader.item.calmSpots(sizes, Math.round(mainScreenW), Math.round(mainScreenH),
                                                  Math.round(barBottom + 24), dockEnabled ? 120 : 32, 48)
        if (!spots || !spots.length) return -1
        const moves = {}
        let n = 0
        mine.forEach((w, i) => {
            const s = spots[i]
            if (s && s.busy <= 8 && (Math.abs(s.x - w.x) > 4 || Math.abs(s.y - w.y) > 4)) { moves[w.id] = s; n++ }
        })
        if (n) setting("widgets", widgets.map(w => moves[w.id] ? Object.assign({}, w, { x: moves[w.id].x, y: moves[w.id].y }) : w))
        return n
    }
    // (Choosing Auto in Settings re-themes through the usual setting change;
    // a new wallpaper through wallWait above.  The first measurement at
    // startup changes nothing: the theme on disk already matches it.)
    // ---- settings: common/Config.qml (a singleton; newer code reads
    //      Config.cfg directly).  Passed on under the old names. ----
    readonly property var cfgDefaults: Config.defaults
    readonly property var cfgUser: Config.user
    readonly property var cfg: Config.cfg

    readonly property bool barStats: cfg.barStats !== false
    readonly property bool barGpu:   cfg.barGpu !== false
    readonly property bool barNet:   cfg.barNet !== false
    readonly property bool barMedia: cfg.barMedia !== false
    // the centre pill grows into a panel (CenterIsland), or opens the
    // separate card under the bar (BarCenter + MediaCard)
    readonly property bool barMorph: cfg.barMorph !== false
    // the right pill grows into quick settings (RightIsland), or the
    // clock opens the sidebar and the volume its popover (BarRight)
    readonly property bool rightMorph: cfg.rightMorph !== false
    // the left pill grows into the system panel (LeftIsland), or its
    // stats open btop (BarLeft)
    readonly property bool leftMorph: cfg.leftMorph !== false
    property bool quickShown: false
    readonly property string clockFormat:
        (cfg.clockDate !== false ? "ddd d MMM   " : "")
        + (cfg.clock24h === true ? "HH:mm" : "h:mm")
        + (cfg.clockSeconds === true ? ":ss" : "")
        + (cfg.clock24h === true ? "" : " AP")

    // clamped reads, so a hand-edited file can't set something absurd
    readonly property int osdMs:
        Math.max(500, Math.min(5000, Number(cfg.osdMs) || 1400))
    readonly property int notifMs:
        Math.max(2000, Math.min(30000, Number(cfg.notifMs) || 6000))
    readonly property bool dockEnabled: cfg.dockEnabled !== false
    readonly property real termOpacity:
        Math.max(0.3, Math.min(1, Number(cfg.termOpacity) || 0.75))

    function fs(px) {
        const k = Math.max(0.7, Math.min(1.6, Number(cfg.fontScale) || 1))
        return Math.round(px * k)
    }

    function setting(key, value) { Config.setting(key, value) }
    function resetSetting(key) { Config.resetSetting(key) }
    function resetAllSettings() { Config.resetAll() }

    // Settings that belong to other programs.  kitty reads
    // ~/.config/kitty/shell-settings.conf (included at the end of
    // kitty.conf) and reloads it on SIGUSR1; the live opacity change
    // needs `dynamic_background_opacity yes` in kitty.conf.

    // ---- the assistant, apps and the cheatsheet: services/Assistant.qml,
    //      Apps.qml and Shortcuts.qml (singletons; newer code uses them
    //      directly).  Passed on under the old names. ----
    readonly property var aiBusy: Assistant.aiBusy
    readonly property var aiKeys: Assistant.aiKeys
    readonly property var aiMessages: Assistant.aiMessages
    readonly property var aiModel: Assistant.aiModel
    function aiNew() { return Assistant.aiNew() }
    readonly property var aiProvider: Assistant.aiProvider
    readonly property var aiProviders: Assistant.aiProviders
    function aiSend(text) { return Assistant.aiSend(text) }
    function aiStop() { return Assistant.aiStop() }
    readonly property var aiStreaming: Assistant.aiStreaming
    function refreshAiKeys() { return Assistant.refreshAiKeys() }
    function removeAiKey(p) { return Assistant.removeAiKey(p) }
    function saveAiKey(p, key) { return Assistant.saveAiKey(p, key) }
    readonly property var appEnv: Apps.appEnv
    readonly property var fileCount: Apps.fileCount
    readonly property var fileLimit: Apps.fileLimit
    readonly property var fileQuery: Apps.fileQuery
    readonly property var fileResults: Apps.fileResults
    readonly property var fileResultsFor: Apps.fileResultsFor
    function iconFor(cls) { return Apps.iconFor(cls) }
    readonly property var iconOverrides: Apps.iconOverrides
    readonly property var launchCounts: Apps.launchCounts
    function noteLaunch(id) { return Apps.noteLaunch(id) }
    function run(cmd) { return Apps.run(cmd) }
    readonly property var cheatBinds: Shortcuts.cheatBinds
    Binding { target: Apps; property: "nativeItem"; value: root.nativeOk ? nativeLoader.item : null }

    // ---- clipboard, timer and calendar: services/Clipboard.qml,
    //      TimerService.qml and Calendar.qml (singletons; newer code uses
    //      them directly).  Passed on under the old names. ----
    function clipCopy(id) { return Clipboard.clipCopy(id) }
    function clipDelete(id) { return Clipboard.clipDelete(id) }
    function clipImageInfo(preview) { return Clipboard.clipImageInfo(preview) }
    readonly property var clipItems: Clipboard.clipItems
    readonly property var clipNativeOn: Clipboard.clipNativeOn
    readonly property var clipThumbDir: Clipboard.clipThumbDir
    readonly property var clipThumbVer: Clipboard.clipThumbVer
    function clipWipe() { return Clipboard.clipWipe() }
    function readClipboard() { return Clipboard.readClipboard() }
    function cancelTimer() { return TimerService.cancelTimer() }
    function fmtDur(sec) { return TimerService.fmtDur(sec) }
    function parseDur(t) { return TimerService.parseDur(t) }
    function pauseTimer() { return TimerService.pauseTimer() }
    function resumeTimer() { return TimerService.resumeTimer() }
    function startTimer(sec) { return TimerService.startTimer(sec) }
    readonly property var swMs: TimerService.swMs
    readonly property var swOn: TimerService.swOn
    function swReset() { return TimerService.swReset() }
    readonly property var swRunning: TimerService.swRunning
    function swToggle() { return TimerService.swToggle() }
    readonly property var timerHeld: TimerService.timerHeld
    readonly property var timerLeft: TimerService.timerLeft
    readonly property var timerOn: TimerService.timerOn
    readonly property var timerPaused: TimerService.timerPaused
    readonly property var timerTotal: TimerService.timerTotal
    readonly property var calBase: Calendar.calBase
    readonly property var calCells: Calendar.calCells
    readonly property var calHolidays: Calendar.calHolidays
    readonly property var calWeekStart: Calendar.calWeekStart
    function deleteDayNote(key, yearly) { return Calendar.deleteDayNote(key, yearly) }
    function holidayOn(key) { return Calendar.holidayOn(key) }
    readonly property var markedDays: Calendar.markedDays
    function notesOn(key) { return Calendar.notesOn(key) }
    function saveMarks() { return Calendar.saveMarks() }
    function setDayNote(key, text, yearly) { return Calendar.setDayNote(key, text, yearly) }
    Binding { target: Clipboard; property: "nativeItem"; value: root.nativeOk ? nativeLoader.item : null }
    Binding { target: Clipboard; property: "panelOpen"; value: root.clipShown }
    Binding { target: TimerService; property: "islandOn"; value: root.islandOn }
    Binding { target: Calendar; property: "monthOffset"; value: root.monthOffset }
    Connections {
        target: Clipboard
        function onCopied() { root.sidebarShown = false; root.clipShown = false }
    }
    Connections {
        target: TimerService
        function onFinishedForIsland(len) { root.showIsland({ kind: "timer", len: len }, 10000) }
    }

    // ---- settings passed on to other programs, and shortcuts:
    //      services/Session.qml and Shortcuts.qml (singletons; newer code
    //      uses them directly).  Passed on under the old names. ----
    function checkMango() { return Session.checkMango() }
    function copyText(t) { return Session.copyText(t) }
    function entryCmd(e) { return Session.entryCmd(e) }
    readonly property var gameHud: Session.gameHud
    readonly property var idleLockMin: Session.idleLockMin
    readonly property var idleScreenMin: Session.idleScreenMin
    readonly property var idleSleepMin: Session.idleSleepMin
    readonly property var lockBlur: Session.lockBlur
    readonly property var lockDim: Session.lockDim
    readonly property var lockGreetMode: Session.lockGreetMode
    readonly property var lockGreetText: Session.lockGreetText
    readonly property var lockMedia: Session.lockMedia
    readonly property var mangoOk: Session.mangoOk
    function refreshXdg() { return Session.refreshXdg() }
    function setDefaultApp(role, entry) { return Session.setDefaultApp(role, entry) }
    readonly property var termCmd: Session.termCmd
    function writeHypr() { return Session.writeHypr() }
    readonly property var xdgDefaults: Session.xdgDefaults
    function captureKeys(on) { return Shortcuts.captureKeys(on) }
    readonly property var keybinds: Shortcuts.keybinds
    readonly property var keysCapturing: Shortcuts.keysCapturing
    function resetKeybind(id) { return Shortcuts.resetKeybind(id) }
    function resetKeybinds() { return Shortcuts.resetKeybinds() }
    function setKeybind(id, combo) { return Shortcuts.setKeybind(id, combo) }
    Binding { target: Session; property: "autoGame"; value: root.autoGame }
    Binding { target: Session; property: "termOpacity"; value: root.termOpacity }

    // ---- screens: services/Displays.qml and Brightness.qml (singletons;
    //      newer code uses them directly).  Passed on under the old names. ----
    readonly property var monBus: Brightness.monBus
    readonly property var bright: Brightness.bright
    readonly property var brightOk: Brightness.brightOk
    readonly property var brightAvg: Brightness.brightAvg
    readonly property var nightLight: Brightness.nightLight
    readonly property var monInfo: Displays.monInfo
    readonly property var revertLeft: Displays.revertLeft
    readonly property var monProfiles: Displays.monProfiles
    readonly property var screensNowList: Displays.screensNowList
    readonly property var screensNow: Displays.screensNow
    readonly property var profileNowInUse: Displays.profileNowInUse
    readonly property var profilesAuto: Displays.profilesAuto
    function readBrightness() { Brightness.readBrightness() }
    function setBright(name, v) { Brightness.setBright(name, v) }
    function setAllBright(v) { Brightness.setAllBright(v) }
    function ddcGotBrightness(bus, percent) { Brightness.ddcGotBrightness(bus, percent) }
    function ddcFailed(bus) { Brightness.ddcFailed(bus) }
    function toggleNight() {
        Brightness.toggleNight()
        showOsdOf("night", nightLight ? 1 : 0, !nightLight)
    }
    function refreshMonitors() { Displays.refreshMonitors() }
    function applyDisplays(monitors, arrange) { Displays.applyDisplays(monitors, arrange) }
    function keepDisplays() { Displays.keepDisplays() }
    function revertDisplays() { Displays.revertDisplays() }
    function saveMonProfile(name, monitors) { return Displays.saveMonProfile(name, monitors) }
    function deleteMonProfile(name) { Displays.deleteMonProfile(name) }
    function useMonProfile(p) { Displays.useMonProfile(p) }
    Binding { target: Brightness; property: "nativeItem"; value: root.nativeOk ? nativeLoader.item : null }
    Binding { target: Displays; property: "mainScreen"; value: root.mainScreen }
    Binding { target: Displays; property: "secondScreen"; value: root.secondScreen }
    Connections {
        target: Brightness
        function onAllChanged() { root.showOsdOf("brightness", Brightness.brightAvg / 100, false) }
    }
    onSettingsShownChanged: {
        if (settingsShown && settingsPage === 9) { refreshMonitors(); readBrightness() }
        if (settingsShown && settingsPage === 18) refreshAbout()
        if (settingsShown && settingsPage === 21) refreshXdg()
    }
    onSettingsPageChanged: {
        if (settingsShown && settingsPage === 9) { refreshMonitors(); readBrightness() }
        if (settingsShown && settingsPage === 18) refreshAbout()
        if (settingsShown && settingsPage === 21) refreshXdg()
    }

    // ---- theme -------------------------------------------------------
    // The panel writes ~/.config/matugen/shell-theme (TYPE= and
    // CONTRAST=, sourced by setwall) and re-runs setwall on the current
    // wallpaper.  matugen's quickshell post_hook calls `theme reload`,
    // which re-reads colors.json in place instead of restarting.
    // Ether Shell's own choice of colour (the colour source "smart", the
    // default): the plugin's pick, the picture's second colour family if it
    // has one, and what the pick is (the subject, the backdrop...)
    // ---- file search (the launcher asks, the native plugin answers) ----
    IpcHandler {
        target: "theme"
        function reload(): void { Theme.reloadPalette() }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.settingsShown = !root.settingsShown }
        function open(): void { root.settingsShown = true }
        function close(): void { root.settingsShown = false }
        function reload(): void { Config.reload() }
        function sync(): void {
            Session.syncAll()
        }
    }



    onPowerShownChanged: if (powerShown) System.refreshUptime()

    // real notification daemon — owns org.freedesktop.Notifications

}

