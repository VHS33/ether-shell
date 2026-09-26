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

ShellRoot {
    id: root

    // Palette generated from the wallpaper by matugen; falls back to
    // Catppuccin Mocha when no palette has been generated yet.
    property var pal: ({})

    // cava spectrum, 28 bars of 0-100; only runs while the media card is
    // open so nothing is burning CPU in the background
    property var cavaBars: new Array(28).fill(0)

    function withAlpha(hex, aa) {
        if (!hex) return undefined
        return "#" + aa + hex.replace("#", "")
    }

    // every shell surface (bar pills, dock, sidebar, cards, popups)
    // takes one opacity from settings (bgOpacity), matching the
    // terminal's default so the whole desktop reads as one material
    function hexA(a) {
        const v = Math.round(Math.max(0, Math.min(1, a)) * 255)
        return (v < 16 ? "0" : "") + v.toString(16)
    }
    readonly property real bgA:
        Math.max(0.3, Math.min(1, Number(cfg.bgOpacity) || 0.75))
    property color cBg:     withAlpha(pal.bg ?? "#1e1e2e", hexA(bgA))
    property color cCard:   withAlpha(pal.card ?? "#1e1e2e", hexA(bgA))
    property color cSurf:   pal.surf   ?? "#313244"
    property color cTile:   withAlpha(pal.tile, "33") ?? "#33313244"
    property color cBorder: pal.border ?? "#414356"
    property color cFg:     pal.fg     ?? "#cdd6f4"
    property color cDim:    pal.dim    ?? "#a6adc8"
    property color cFaint:  pal.faint  ?? "#6c7086"
    property color cBlue:   pal.blue   ?? "#89b4fa"
    property color cGreen:  pal.green  ?? "#a6e3a1"
    property color cPeach:  pal.peach  ?? "#fab387"
    // light mode swaps the three pastel "fixed" accents for darker
    // companions, which would otherwise wash out on a light background
    // Light, dark, or "auto": light for wallpapers that look bright (their
    // lightness, 0-100, measured by the native plugin; above 60 is light).
    // Without the plugin, auto stays dark.
    readonly property bool isLight: cfg.themeMode === "light"
                                    || (cfg.themeMode === "auto" && wallLightness > 60)
    property real wallLightness: -1
    property color cMauve:  (isLight ? pal.mauveL : pal.mauve) ?? "#cba6f7"
    property color cTeal:   (isLight ? pal.tealL : pal.teal)   ?? "#94e2d5"
    property color cRed:    pal.red    ?? "#f38ba8"
    property color cYellow: (isLight ? pal.yellowL : pal.yellow) ?? "#f9e2af"
    // text and icons drawn on top of an accent colour
    property color cOnAccent: pal.onAccent ?? "#1e1e2e"
    // Material's filled-but-deeper accent (the clock's group, tiles that
    // are on) and the text that sits on it.  Until matugen has written
    // them, a mix of the accent and the background stands in.
    property color cPrimC: pal.primaryC ?? Qt.tint(pal.bg ?? "#1e1e2e",
                                                    Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.35))
    property color cOnPrimC: pal.onPrimaryC ?? cFg

    // ---- theme changes fade instead of snapping ----
    // Each colour eases to its new value over about half a second.  Off
    // until the first palette has loaded, so the shell doesn't sweep in
    // from its fallback colours at every login.
    property bool colourFade: false
    Timer { id: fadeOn; interval: 800; onTriggered: root.colourFade = true }
    Behavior on cBg { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cCard { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cSurf { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cTile { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cBorder { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cFg { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cDim { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cFaint { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cBlue { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cGreen { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cPeach { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cMauve { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cTeal { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cRed { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cYellow { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cOnAccent { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cPrimC { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cOnPrimC { enabled: root.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    // dimming layers: the background colour at a given strength
    function scrim(a) { return withAlpha(pal.bg ?? "#1e1e2e", hexA(a)) }
    readonly property string font:   "JetBrainsMono Nerd Font"

    // weather location and units come from Settings > Weather
    // no location until one is set: a fresh install shouldn't guess
    readonly property bool wxHasPlace: cfg.wxLat !== undefined && isFinite(Number(cfg.wxLat))
                                       && cfg.wxLon !== undefined && isFinite(Number(cfg.wxLon))
    readonly property real wxLat: wxHasPlace ? Number(cfg.wxLat) : 0
    readonly property real wxLon: wxHasPlace ? Number(cfg.wxLon) : 0
    readonly property string wxPlace: wxHasPlace ? (cfg.wxPlace || "Your location") : "No location set"
    readonly property bool wxMetric: cfg.wxUnits === "C"
    readonly property string notesPath: Quickshell.env("HOME") + "/.config/quickshell/marked-days.txt"

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

    property int cpuPct: 0
    property int gpuPct: 0
    property int gpuTemp: 0
    property int gpuMemPct: 0
    property int gpuWatts: 0
    property bool gpuOk: false

    property string netDown: "0"
    property string netUp: "0"
    property var lastNet: null

    // "0.4 KB/s", "85 KB/s", "1.2 MB/s": always a unit per second
    function fmtRate(bps) {
        const k = bps / 1024
        if (k < 10) return k.toFixed(1) + " KB/s"
        if (k < 1000) return Math.round(k) + " KB/s"
        return (k / 1024).toFixed(1) + " MB/s"
    }

    property int memPct: 0
    property var lastCpu: null

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
    readonly property bool dockAutoHide: cfg.dockAutoHide === true
    // space the dock takes at the bottom, for things that sit above it
    readonly property int dockSpace: (dockEnabled && !dockAutoHide) ? dockIcon + 28 + gap : 0
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
                         pinned: true, running: false, addrs: [], titles: [], act: 0, here: 0, n: 0 }
            byPin[id] = it
            items.push(it)
        }
        for (const g of groups) {
            const e = root.entryFor(g.cls)
            const id = e ? root.normId(e.id) : ""
            const pin = id !== "" ? byPin[id] : undefined
            if (pin) {
                pin.cls = g.cls; pin.running = true; pin.addrs = g.addrs; pin.titles = g.titles
                pin.act = g.act; pin.here = g.here; pin.n = g.n
            } else {
                items.push({ key: "win:" + g.cls, id: id, cls: g.cls,
                             name: e ? String(e.name || g.cls) : g.cls,
                             icon: root.iconFor(g.cls), pinned: false, running: true,
                             addrs: g.addrs, titles: g.titles, act: g.act, here: g.here, n: g.n })
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
    readonly property var appEnv: ({ "__EGL_VENDOR_LIBRARY_FILENAMES": null })
    function launchEntry(e) {
        if (!e) return
        try {
            let cmd = e.command ? Array.from(e.command) : []
            if (!cmd.length) { e.execute(); return }
            if (e.runInTerminal) cmd = [cfg.appTerminalCmd || "kitty", "-e"].concat(cmd)
            Quickshell.execDetached({
                command: cmd,
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
    readonly property var widgetTypes: [
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
    // ---- clipboard history -------------------------------------------
    // Entries are { id, preview } plain strings; cliphist keeps the real
    // contents, which can include anything, so nothing is stored here.
    property var clipItems: []


    // refreshes wait until the sidebar has slid in, so they don't compete
    // with the opening frames
    onSidebarShownChanged: if (sidebarShown) { sideRefresh.restart(); notifUnseen = 0 }
    Timer {
        id: sideRefresh
        interval: 260
        onTriggered: root.refreshSidebar()
    }
    function refreshSidebar() {
        readBrightness()
        clipProc.running = true
        netStatProc.running = true
    }

    // ---- network, for the sidebar's network tile ----------------------
    // The first connected device from NetworkManager: its kind and the
    // connection's name.  Refreshed whenever the sidebar opens.
    property string netKind: ""        // "wifi", "ethernet" or ""
    property string netName: ""
    Process {
        id: netStatProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let kind = "", name = ""
                for (const line of text.split("\n")) {
                    const f = line.split(":")
                    if (f.length < 3 || f[1] !== "connected") continue
                    if (f[0] === "wifi" || f[0] === "ethernet") {
                        kind = f[0]
                        name = f.slice(2).join(":")
                        break
                    }
                }
                root.netKind = kind
                root.netName = name
            }
        }
    }

    function refreshWeather() { if (wxHasPlace) wxProc.running = true }

    // ---- about -------------------------------------------------------
    // one snapshot of the machine, taken when Settings > About opens
    property var aboutInfo: ({})
    Process {
        id: aboutProc
        command: ["sh", "-c",
            'echo "host=$(cat /etc/hostname 2>/dev/null)"; '
            + '. /etc/os-release 2>/dev/null; echo "os=$PRETTY_NAME"; '
            + 'echo "kernel=$(uname -r)"; '
            + 'echo "cpu=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed "s/^ *//")"; '
            + 'echo "cores=$(nproc)"; '
            + 'echo "gpu=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"; '
            + 'echo "ram=$(( ($(awk \'/MemTotal/ {print $2}\' /proc/meminfo) + 524288) / 1048576 )) GB"; '
            + 'echo "uptime=$(uptime -p | sed "s/^up //")"; '
            + 'echo "hyprland=$(hyprctl version -j 2>/dev/null | grep -m1 \"tag\" | cut -d\\\" -f4)"; '
            + 'echo "quickshell=$(qs --version 2>/dev/null | head -1)"; '
            + 'echo "shell=$(basename "$SHELL")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                root.aboutInfo = o
            }
        }
    }
    function refreshAbout() { aboutProc.running = true }

    // place search for Settings > Weather, through Open-Meteo's geocoder;
    // results are plain values
    property var wxResults: []
    property bool wxSearching: false
    function searchPlace(q) {
        q = q.trim()
        if (q === "") { wxResults = []; return }
        wxSearching = true
        geoProc.command = ["sh", "-c",
            'curl -s --max-time 10 -G "https://geocoding-api.open-meteo.com/v1/search" '
            + '--data-urlencode "name=$1" -d count=6 -d language=en -d format=json',
            "sh", q]
        geoProc.running = true
    }
    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.wxSearching = false
                try {
                    const r = JSON.parse(text).results || []
                    root.wxResults = r.map(x => ({
                        name: x.name,
                        where: [x.admin1, x.country].filter(v => v).join(", "),
                        lat: x.latitude,
                        lon: x.longitude
                    }))
                } catch (e) {
                    root.wxResults = []
                }
            }
        }
    }
    function setPlace(r) {
        const o = Object.assign({}, cfgUser)
        o.wxLat = r.lat
        o.wxLon = r.lon
        o.wxPlace = r.name + (r.where ? ", " + r.where.split(", ")[0] : "")
        cfgUser = o
        saveSettings()
        wxResults = []
        wxRefreshLater.restart()
    }
    // the location or units changed: fetch once the new values are in
    Timer {
        id: wxRefreshLater
        interval: 300
        onTriggered: root.refreshWeather()
    }

    Process {
        id: clipProc
        command: ["sh", "-c", "cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    if (!line.length) continue
                    const tab = line.indexOf("\t")
                    if (tab === -1) continue
                    out.push({
                        id: line.slice(0, tab),
                        preview: line.slice(tab + 1)
                    })
                }
                root.clipItems = out
                if (root.clipShown) root.makeClipThumbs()
            }
        }
    }

    Process { id: clipAct }

    function clipCopy(id) {
        clipAct.command = ["sh", "-c",
            "cliphist decode " + id + " | wl-copy"]
        clipAct.running = true
        root.sidebarShown = false
        root.clipShown = false
    }

    function clipDelete(id) {
        clipAct.command = ["sh", "-c",
            "cliphist list | grep -m1 '^" + id + "\t' | cliphist delete"]
        clipAct.running = true
        clipRefresh.restart()
    }

    function clipWipe() {
        clipAct.command = ["sh", "-c", "cliphist wipe"]
        clipAct.running = true
        clipRefresh.restart()
    }

    Timer {
        id: clipRefresh
        interval: 120
        onTriggered: clipProc.running = true
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
    property var cheatBinds: []

    onCheatShownChanged: if (cheatShown) cheatProc.running = true

    readonly property var modNames: [
        [64, "SUPER"], [8, "ALT"], [4, "CTRL"], [1, "SHIFT"]
    ]

    function modString(mask) {
        const out = []
        for (const [bit, name] of root.modNames) {
            if (mask & bit) out.push(name)
        }
        return out
    }

    Process {
        id: cheatProc
        command: ["sh", "-c", "hyprctl binds -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = []
                try {
                    raw = JSON.parse(text)
                } catch (e) {
                    console.log("cheatsheet: could not parse binds:", e)
                    return
                }

                // key names people recognise
                const pretty = {
                    "SUPER_L": "SUPER (tap)", "slash": "/", "Tab": "Tab",
                    "mouse:272": "Left drag", "mouse:273": "Right drag",
                    "mouse_down": "Scroll down", "mouse_up": "Scroll up",
                    "left": "\u2190", "right": "\u2192", "up": "\u2191", "down": "\u2193",
                    "XF86AudioRaiseVolume": "Volume up key", "XF86AudioLowerVolume": "Volume down key",
                    "XF86AudioMute": "Mute key", "XF86AudioMicMute": "Mic mute key",
                    "XF86MonBrightnessUp": "Brightness up key", "XF86MonBrightnessDown": "Brightness down key",
                    "XF86AudioNext": "Next key", "XF86AudioPrev": "Previous key",
                    "XF86AudioPlay": "Play key", "XF86AudioPause": "Pause key"
                }
                // which group a bind belongs to, from its description
                const groupOf = l => {
                    if (/^(Go to|Send window to) workspace|workspace|overview/i.test(l)) return "Workspaces"
                    if (/screenshot/i.test(l)) return "Screenshots"
                    if (/volume|mute|brightness|track|play|pause/i.test(l)) return "Media"
                    if (/window|float|pseudotile|split|focus|drag|resize|fullscreen|maximi/i.test(l)) return "Windows"
                    if (/terminal|file manager|app menu|launcher/i.test(l)) return "Apps"
                    return "Shell"
                }

                const out = []
                const seen = {}
                for (const b of raw) {
                    const key = b.key ?? ""
                    if (!key.length) continue

                    let label = b.description ?? ""
                    if (!label.length) {
                        const d = b.dispatcher ?? ""
                        label = d === "__lua" ? "(lua)" : d
                    }

                    const mods = root.modString(b.modmask ?? 0)
                    // SUPER_L is the tap itself, not a modifier plus a key
                    let keys = key === "SUPER_L" ? ["SUPER (tap)"]
                             : mods.concat([pretty[key] ?? (key.length === 1 ? key.toUpperCase() : key)])

                    // twenty workspace binds become two rows
                    if (/^Workspace \d+$/.test(label)) {
                        label = "Go to workspace"
                        keys = mods.concat(["1 \u2026 0"])
                    } else if (/^Send to workspace \d+$/.test(label)) {
                        label = "Send window to workspace"
                        keys = mods.concat(["1 \u2026 0"])
                    }

                    const id = keys.join("+") + "|" + label
                    if (seen[id]) continue
                    seen[id] = true
                    out.push({ keys: keys, label: label, group: groupOf(label) })
                }
                root.cheatBinds = out
            }
        }
    }

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
        target: Pipewire.defaultAudioSink?.audio ?? null
        function onVolumeChanged() {
            root.showOsd(Pipewire.defaultAudioSink.audio.volume,
                         Pipewire.defaultAudioSink.audio.muted)
        }
        function onMutedChanged() {
            root.showOsd(Pipewire.defaultAudioSink.audio.volume,
                         Pipewire.defaultAudioSink.audio.muted)
        }
    }

    // the microphone only shows when it's muted or unmuted, from anywhere
    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null
        function onMutedChanged() {
            const a = Pipewire.defaultAudioSource.audio
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
    property var wallpapers: []

    property string uptimeText: ""

    property var notifList: []
    property var popups: []

    function dismissPopup(id) {
        root.popups = root.popups.filter(n => n.id !== id)
    }

    // run one of a notification's buttons ("Reply", "Open", the click
    // action "default", ...) through the live object, then clear it
    function invokeNotifAction(id, key) {
        const obj = root.notifRefs[id]
        if (obj) {
            try {
                for (const a of (obj.actions || []))
                    if (String(a.identifier) === key) { a.invoke(); break }
            } catch (e) {}
        }
        dismissNotif(id)
    }

    // send a typed reply back to the app that asked for one
    function sendNotifReply(id, text) {
        const obj = root.notifRefs[id]
        if (obj && text.trim() !== "") {
            try { obj.sendInlineReply(text) } catch (e) {
                console.log("inline reply failed:", e)
            }
        }
        dismissNotif(id)
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
    property int notifSeq: 0

    // Live Notification objects, keyed by our id.  They must NOT go inside
    // notifList/popups: those arrays are list models, and when the server
    // destroys an expired notification, a model entry still pointing at it
    // makes Qt segfault the next time it builds a delegate from that entry.
    // Model entries hold only plain values; the object is looked up here.
    property var notifRefs: ({})
    readonly property int notifCount: notifList.length

    // ---- grouped by app, and history ------------------------------------
    // Groups are worked out from notifList: { app, icon, items } with the
    // newest group first and each group's newest item first.
    readonly property var notifGroups: {
        const idx = {}, out = []
        for (const n of notifList) {
            const k = n.app || "notification"
            if (idx[k] === undefined) { idx[k] = out.length; out.push({ app: k, items: [] }) }
            out[idx[k]].items.push(n)
        }
        return out
    }
    function dismissGroup(appName) {
        for (const n of notifList.filter(x => (x.app || "notification") === appName)) {
            const obj = notifRefs[n.id]
            if (obj) { try { obj.dismiss() } catch (e) {} }
        }
        notifList = notifList.filter(x => (x.app || "notification") !== appName)
        popups = popups.filter(x => (x.app || "notification") !== appName)
    }
    // when it arrived: the time today, the day before that
    function notifWhen(n) {
        if (!n.ts) return n.when || ""
        const d = new Date(n.ts), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.formatDateTime(d, cfg.clock24h === true ? "HH:mm" : "h:mm AP")
        return Qt.formatDateTime(d, "ddd d")
    }
    // arrived since quick settings or the sidebar was last opened
    property int notifUnseen: 0

    // Saved to ~/.local/state/ether/notifications.json (the newest 100),
    // and read back at startup.  Saved ones come back without their
    // buttons: the app that sent them has moved on.
    property bool notifLoaded: false
    Process {
        running: true
        // (the project was called Aether; its folder is moved across once)
        command: ["sh", "-c", "s=\"$HOME/.local/state\"; " +
            "[ -d \"$s/aether\" ] && [ ! -e \"$s/ether\" ] && mv \"$s/aether\" \"$s/ether\"; " +
            "cat \"$s/ether/notifications.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const saved = JSON.parse(text)
                    if (Array.isArray(saved)) {
                        const old = saved.map(n => Object.assign({}, n, { saved: true, actions: [], replyable: false }))
                        let top = root.notifSeq
                        for (const n of old) top = Math.max(top, n.id || 0)
                        root.notifSeq = top
                        root.notifList = root.notifList.concat(old).slice(0, 100)
                    }
                } catch (e) {}
                root.notifLoaded = true
            }
        }
    }
    onNotifListChanged: if (notifLoaded) notifSave.restart()
    Timer {
        id: notifSave
        interval: 800
        onTriggered: {
            notifWrite.command = ["sh", "-c",
                'd="$HOME/.local/state/ether"; mkdir -p "$d"; ' +
                'printf "%s" "$1" > "$d/notifications.json.tmp" && mv "$d/notifications.json.tmp" "$d/notifications.json"',
                "sh", JSON.stringify(root.notifList.slice(0, 100))]
            notifWrite.running = true
        }
    }
    Process { id: notifWrite }

    property string wxCond: ""
    property string wxTemp: ""
    property string wxFeel: ""
    property string wxHum: ""
    property string wxWind: ""
    // the next twelve hours ({ time, temp, cond, day, rain }, plain values),
    // today's high and low, and whether it's daytime where you are
    property var wxHours: []
    property string wxHi: ""
    property string wxLo: ""
    property bool wxDay: true
    property bool   wxOk: false

    property int monthOffset: 0
    property string selectedKey: ""
    property var markedDays: []

    // Hyprland publishes its client list natively, so the dock no longer
    // needs the KWin script and journal tail it used on Plasma.
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
                    titles: [t.title ?? ""],
                    act: t === active ? 1 : 0,
                    here: onThis ? 1 : 0,
                    n: 1
                })
            } else {
                const g = out[idx[k]]
                g.addrs.push(t.lastIpcObject?.address ?? "")
                g.titles.push(t.title ?? "")
                g.n += 1
                if (t === active) g.act = 1
                if (onThis) g.here = 1
            }
        }
        return out
    }

    property var cycleIdx: ({})

    function cycleGroup(cls, addrs) {
        const k = (cls || "?").toLowerCase()
        const cur = root.cycleIdx[k] === undefined ? -1 : root.cycleIdx[k]
        const next = (cur + 1) % addrs.length
        const m = root.cycleIdx
        m[k] = next
        root.cycleIdx = m

        const addr = addrs[next]
        if (addr) {
            Hyprland.dispatch("hl.dsp.focus({ window = \"address:"
                              + addr + "\" })")
        }
    }

    // The player everything controls: the one picked in the media card
    // if it's still around, else whichever is playing, else the first.
    property string pickedPlayer: ""
    readonly property var player: {
        const list = Mpris.players.values
        if (!list || list.length === 0) return null
        if (pickedPlayer !== "")
            for (const p of list) if (p.dbusName === pickedPlayer) return p
        for (const p of list) {
            if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return list[0]
    }
    // every player, as plain values for the card's switcher
    readonly property var playerList: (Mpris.players.values || []).map(p => ({
        key: p.dbusName, name: p.identity || p.dbusName,
        playing: p.playbackState === MprisPlaybackState.Playing
    }))

    onPlayerChanged: if (!player) cardShown = false

    // one island open at a time: opening one closes the others
    onCardShownChanged: if (cardShown) {
        quickShown = false; sysShown = false; launcherShown = false
        lyricsLater.restart()
    }
    onQuickShownChanged: if (quickShown) {
        cardShown = false; sysShown = false; launcherShown = false
        notifUnseen = 0
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
    onAutoGameChanged: hyprDebounce.restart()
    function markGame() { gameWatch.markFocused() }

    // ---- now-playing colours ---------------------------------------------
    // While something plays, the media views (the media drawer, the bar's
    // media pill, quick settings' mini player and the island's song card)
    // take their accent colours from the album art, and fade back to the
    // wallpaper's when it stops.  The colours come from ArtColors in the
    // native plugin (via NativeStats.qml); without it, they stay the theme's.
    // Everything else keeps the wallpaper theme.
    property bool artValid: false
    property color artAccent: cBlue
    property color artOnAccent: cOnAccent
    property color artContainer: cPrimC
    property color artOnContainer: cOnPrimC
    readonly property bool darkTheme: (cBg.r * 0.299 + cBg.g * 0.587 + cBg.b * 0.114) < 0.5
    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property bool artOn: cfg.artColors !== false && artValid && playing
    // what the media views use
    property color mBlue: artOn ? artAccent : cBlue
    property color mOnAccent: artOn ? artOnAccent : cOnAccent
    property color mPrimC: artOn ? artContainer : cPrimC
    property color mOnPrimC: artOn ? artOnContainer : cOnPrimC
    Behavior on mBlue { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mOnAccent { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mPrimC { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mOnPrimC { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }

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

    // ---- Wi-Fi (NetworkManager) ------------------------------------------
    // Lists are plain values.  Connecting runs nmcli with its arguments
    // as a list, never through a shell, so a network name or password
    // can't be mistaken for a command.
    property bool wifiHas: false
    property bool wifiOn: false
    property var wifiList: []            // { ssid, signal, secure, active }
    property string wifiBusy: ""         // the network being joined
    property string wifiAskPw: ""        // the network that needs a password
    property string wifiError: ""
    function refreshWifi(rescan) {
        wifiScan.command = ["sh", "-c",
            "nmcli -t -f TYPE device | grep -qx wifi && echo HAS; " +
            "echo \"RADIO $(nmcli radio wifi)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan " +
            (rescan ? "yes" : "auto") + " 2>/dev/null | sed 's/^/NET /'"]
        wifiScan.running = true
    }
    Process {
        id: wifiScan
        stdout: StdioCollector {
            onStreamFinished: {
                let has = false, on = false
                const seen = {}, out = []
                for (const line of text.split("\n")) {
                    if (line === "HAS") has = true
                    else if (line.startsWith("RADIO ")) on = line.slice(6).trim() === "enabled"
                    else if (line.startsWith("NET ")) {
                        const f = root.nmFields(line.slice(4))
                        if (f.length < 4 || !f[1]) continue
                        const n = { active: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0,
                                    secure: f[3] !== "" && f[3] !== "--" }
                        if (seen[n.ssid] !== undefined) {
                            const o = out[seen[n.ssid]]
                            if (n.active || n.signal > o.signal) out[seen[n.ssid]] = n
                            continue
                        }
                        seen[n.ssid] = out.length
                        out.push(n)
                    }
                }
                out.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
                root.wifiHas = has
                root.wifiOn = on
                root.wifiList = out
            }
        }
    }
    Process {
        id: wifiAct
        stdout: StdioCollector { id: wifiActOut }
        stderr: StdioCollector { id: wifiActErr }
        onExited: code => {
            const msg = (wifiActErr.text + " " + wifiActOut.text).toLowerCase()
            if (code !== 0 && root.wifiBusy !== "") {
                if (/secret|password|802-11-wireless-security/.test(msg)) root.wifiAskPw = root.wifiBusy
                else root.wifiError = "Couldn't join " + root.wifiBusy
            } else {
                root.wifiAskPw = ""
                root.wifiError = ""
            }
            root.wifiBusy = ""
            root.refreshWifi(false)
            netStatProc.running = true
        }
    }
    // nmcli -t separates fields with ":" and escapes any inside a field
    // (a network called "Cafe: 2" comes out as "Cafe\: 2")
    function nmFields(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur)
        return out
    }
    function wifiToggle() {
        wifiAct.command = ["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]
        wifiAct.running = true
    }
    function wifiConnect(ssid, pw) {
        wifiBusy = ssid
        wifiError = ""
        wifiAct.command = pw ? ["nmcli", "device", "wifi", "connect", ssid, "password", pw]
                             : ["nmcli", "device", "wifi", "connect", ssid]
        wifiAct.running = true
    }
    function wifiDisconnect(ssid) {
        wifiAct.command = ["nmcli", "connection", "down", "id", ssid]
        wifiAct.running = true
    }

    // ---- Bluetooth (bluetoothctl) -----------------------------------------
    property bool btHas: false
    property bool btOn: false
    property var btList: []              // { mac, name, paired, connected }
    property bool btScanning: false
    property string btBusy: ""
    function refreshBt() {
        btRead.command = ["sh", "-c",
            "bluetoothctl list 2>/dev/null | grep -q Controller && echo HAS; " +
            "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo ON; " +
            "bluetoothctl devices Paired 2>/dev/null | sed 's/^Device /PAIRED /'; " +
            "bluetoothctl devices Connected 2>/dev/null | sed 's/^Device /CONN /'; " +
            "bluetoothctl devices 2>/dev/null | sed 's/^Device /SEEN /'"]
        btRead.running = true
    }
    Process {
        id: btRead
        stdout: StdioCollector {
            onStreamFinished: {
                let has = false, on = false
                const dev = {}, order = []
                for (const line of text.split("\n")) {
                    if (line === "HAS") { has = true; continue }
                    if (line === "ON") { on = true; continue }
                    const m = line.match(/^(PAIRED|CONN|SEEN) ([0-9A-F:]{17}) ?(.*)$/)
                    if (!m) continue
                    if (!dev[m[2]]) { dev[m[2]] = { mac: m[2], name: m[3] || m[2], paired: false, connected: false }; order.push(m[2]) }
                    if (m[1] === "PAIRED") dev[m[2]].paired = true
                    if (m[1] === "CONN") dev[m[2]].connected = true
                }
                // connected first, then paired, then everything else nearby;
                // unnamed devices (just an address) are left out
                const out = order.map(k => dev[k]).filter(d => d.paired || !/^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name))
                out.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
                root.btHas = has
                root.btOn = on
                root.btList = out
            }
        }
    }
    Process {
        id: btAct
        onExited: { root.btBusy = ""; root.refreshBt() }
    }
    Process {
        id: btScanProc
        command: ["bluetoothctl", "--timeout", "12", "scan", "on"]
        onExited: { root.btScanning = false; root.refreshBt() }
    }
    Timer {
        // while scanning, show devices as they're found
        interval: 2000; repeat: true
        running: root.btScanning
        onTriggered: root.refreshBt()
    }
    function btToggle() {
        btAct.command = ["bluetoothctl", "power", btOn ? "off" : "on"]
        btAct.running = true
    }
    function btScan() {
        if (btScanning) return
        btScanning = true
        btScanProc.running = true
    }
    function btConnect(mac, paired) {
        if (!/^[0-9A-F:]{17}$/i.test(mac)) return
        btBusy = mac
        btAct.command = paired ? ["bluetoothctl", "connect", mac]
            : ["sh", "-c", "bluetoothctl pair \"$1\" && bluetoothctl trust \"$1\" && bluetoothctl connect \"$1\"", "sh", mac]
        btAct.running = true
    }
    function btDisconnect(mac) {
        if (!/^[0-9A-F:]{17}$/i.test(mac)) return
        btBusy = mac
        btAct.command = ["bluetoothctl", "disconnect", mac]
        btAct.running = true
    }

    // ---- synced lyrics (LRCLIB) -------------------------------------------
    // Fetched from lrclib.net, a free lyrics database with no key, only
    // while the media drawer is open and only once per song.  The artist
    // and title go to curl as arguments, never pasted into a command.
    // lyrics: [{ t: seconds, text }], plain values.
    readonly property bool lyricsOn: cfg.lyricsShown !== false
    property var lyrics: []
    property string lyricsPlain: ""
    property string lyricsState: ""        // loading, synced, plain, none
    property string lyricsKey: ""
    property var lyricsCache: ({})
    readonly property string trackKey: player
        ? (player.trackArtist || "") + "\u0001" + (player.trackTitle || "") : ""
    // the line being sung: the last one that has started
    readonly property int lyricIndex: {
        if (lyricsState !== "synced" || !player) return -1
        const pos = player.position + 0.25
        let lo = 0, hi = lyrics.length - 1, ans = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lyrics[mid].t <= pos) { ans = mid; lo = mid + 1 } else hi = mid - 1
        }
        return ans
    }
    function parseLrc(lrc) {
        const out = []
        for (const line of (lrc || "").split("\n")) {
            const stamps = line.match(/\[(\d+):(\d+(?:\.\d+)?)\]/g)
            if (!stamps) continue
            const text = line.replace(/\[[^\]]*\]/g, "").trim()
            for (const st of stamps) {
                const m = st.match(/\[(\d+):(\d+(?:\.\d+)?)\]/)
                out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: text })
            }
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }
    function showLyrics(entry) {
        lyrics = entry.synced
        lyricsPlain = entry.plain
        lyricsState = entry.synced.length ? "synced" : entry.plain ? "plain" : "none"
    }
    function fetchLyrics() {
        if (!player || trackKey === "" || !lyricsOn) return
        if (trackKey === lyricsKey && lyricsState !== "") return
        lyricsKey = trackKey
        const hit = lyricsCache[trackKey]
        if (hit) { showLyrics(hit); return }
        lyrics = []
        lyricsPlain = ""
        lyricsState = "loading"
        lyricsProc.key = trackKey
        lyricsProc.command = ["sh", "-c",
            'UA="Ether Shell (github.com/VHS33/ether-shell)"; ' +
            'r=$(curl -s --max-time 8 -A "$UA" -G "https://lrclib.net/api/get" ' +
            '--data-urlencode "artist_name=$1" --data-urlencode "track_name=$2" ' +
            '--data-urlencode "album_name=$3" --data-urlencode "duration=$4"); ' +
            'case "$r" in *yncedLyrics*|*lainLyrics*) printf "%s" "$r"; exit 0;; esac; ' +
            'curl -s --max-time 8 -A "$UA" -G "https://lrclib.net/api/search" ' +
            '--data-urlencode "track_name=$2" --data-urlencode "artist_name=$1"',
            "sh", player.trackArtist || "", player.trackTitle || "", player.trackAlbum || "",
            String(Math.round(player.length || 0))]
        lyricsProc.running = true
    }
    Process {
        id: lyricsProc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let entry = { synced: [], plain: "" }
                try {
                    let j = JSON.parse(text)
                    // the search gives a list: prefer one with timings
                    if (Array.isArray(j)) j = j.find(x => x && x.syncedLyrics) || j.find(x => x && x.plainLyrics) || {}
                    entry = { synced: root.parseLrc(j.syncedLyrics || ""), plain: (j.plainLyrics || "").trim() }
                } catch (e) {}
                const c = Object.assign({}, root.lyricsCache)
                c[lyricsProc.key] = entry
                const keys = Object.keys(c)
                if (keys.length > 40) delete c[keys[0]]
                root.lyricsCache = c
                if (lyricsProc.key === root.lyricsKey) root.showLyrics(entry)
            }
        }
    }
    // a new song, or the media drawer opening: fetch (once) after a beat
    onTrackKeyChanged: { lyricsLater.restart(); trackIslandLater.restart() }
    Timer {
        id: lyricsLater
        interval: 400
        onTriggered: if (root.cardShown) root.fetchLyrics()
    }

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
    readonly property var aiProviders: ({
        anthropic: { name: "Anthropic", product: "Claude", model: "claude-sonnet-5",
                     keyUrl: "console.anthropic.com" },
        gemini:    { name: "Google", product: "Gemini", model: "gemini-2.5-flash",
                     keyUrl: "aistudio.google.com" },
        openai:    { name: "OpenAI", product: "ChatGPT", model: "gpt-4.1-mini",
                     keyUrl: "platform.openai.com" }
    })
    readonly property string aiProvider: aiProviders[cfg.aiProvider] ? cfg.aiProvider : "anthropic"
    function aiModelFor(p) { return cfg["aiModel_" + p] || aiProviders[p].model }
    readonly property string aiModel: aiModelFor(aiProvider)
    readonly property string aiSystem:
        "You are the assistant built into Ether Shell, a desktop shell on the user's Arch Linux " +
        "computer running Hyprland. Be concise and practical. Use Markdown for lists and code. " +
        "The user's shell is fish."

    // which providers have a key saved
    property var aiKeys: ({})
    function refreshAiKeys() { aiKeyList.running = true }
    Process {
        id: aiKeyList
        running: true
        // (the project was called Aether; its folder is moved across once)
        command: ["sh", "-c", "c=\"$HOME/.config\"; " +
            "[ -d \"$c/aether\" ] && [ ! -e \"$c/ether\" ] && mv \"$c/aether\" \"$c/ether\"; " +
            "ls \"$c/ether/ai\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = {}
                for (const f of text.split("\n")) if (f.endsWith(".key")) k[f.slice(0, -4)] = true
                root.aiKeys = k
            }
        }
    }
    property string aiKeyPending: ""
    Process {
        id: aiKeyWrite
        stdinEnabled: true
        onStarted: { write(root.aiKeyPending); root.aiKeyPending = ""; stdinEnabled = false }
        onExited: { stdinEnabled = true; root.refreshAiKeys() }
    }
    function saveAiKey(p, key) {
        key = (key || "").trim()
        if (!aiProviders[p] || key === "") return
        aiKeyPending = key
        aiKeyWrite.command = ["sh", "-c",
            'umask 077; d="$HOME/.config/ether/ai"; mkdir -p "$d"; cat > "$d/$1.key"', "sh", p]
        aiKeyWrite.running = true
    }
    Process { id: aiKeyRemove; onExited: root.refreshAiKeys() }
    function removeAiKey(p) {
        if (!aiProviders[p]) return
        aiKeyRemove.command = ["sh", "-c", 'rm -f "$HOME/.config/ether/ai/$1.key"', "sh", p]
        aiKeyRemove.running = true
    }

    // the conversation: plain values; the reply being written is kept apart
    // so the list doesn't rebuild on every word
    property var aiMessages: []          // { role: "user" | "assistant", text, error }
    property string aiStreaming: ""
    property bool aiBusy: false
    property string aiRaw: ""            // anything that wasn't a stream event (errors)
    function aiNew() {
        if (aiBusy) aiStop()
        aiMessages = []
        aiStreaming = ""
    }
    function aiStop() {
        if (!aiBusy) return
        aiProc.running = false
    }
    function aiBody() {
        const p = aiProvider, msgs = aiMessages.filter(m => !m.error)
        if (p === "gemini")
            return JSON.stringify({
                systemInstruction: { parts: [{ text: aiSystem }] },
                contents: msgs.map(m => ({ role: m.role === "assistant" ? "model" : "user",
                                           parts: [{ text: m.text }] })) })
        if (p === "openai")
            return JSON.stringify({ model: aiModel, stream: true,
                messages: [{ role: "system", content: aiSystem }]
                          .concat(msgs.map(m => ({ role: m.role, content: m.text }))) })
        return JSON.stringify({ model: aiModel, max_tokens: 4096, stream: true, system: aiSystem,
                                messages: msgs.map(m => ({ role: m.role, content: m.text })) })
    }
    function aiSend(text) {
        text = (text || "").trim()
        if (text === "" || aiBusy) return
        aiMessages = aiMessages.concat([{ role: "user", text: text }])
        aiStreaming = ""
        aiRaw = ""
        aiBusy = true
        aiPendingBody = aiBody()
        aiProc.command = ["sh", "-c",
            'p="$1"; model="$2"; k=$(cat "$HOME/.config/ether/ai/$p.key" 2>/dev/null); ' +
            '[ -n "$k" ] || { echo ETHER_NOKEY; exit 0; }; ' +
            'h=$(mktemp); trap \'rm -f "$h"\' EXIT; ' +
            'case "$p" in ' +
            '  anthropic) printf "x-api-key: %s\\nanthropic-version: 2023-06-01\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://api.anthropic.com/v1/messages";; ' +
            '  openai)    printf "Authorization: Bearer %s\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://api.openai.com/v1/chat/completions";; ' +
            '  gemini)    printf "x-goog-api-key: %s\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse";; ' +
            'esac; ' +
            'curl -sN --max-time 180 -H @"$h" --data-binary @- "$url"',
            "sh", aiProvider, /^[\w.:-]+$/.test(aiModel) ? aiModel : aiProviders[aiProvider].model]
        aiProc.running = true
    }
    property string aiPendingBody: ""
    Process {
        id: aiProc
        stdinEnabled: true
        onStarted: { write(root.aiPendingBody); root.aiPendingBody = ""; stdinEnabled = false }
        stdout: SplitParser {
            onRead: line => {
                if (line === "ETHER_NOKEY") {
                    root.aiRaw = "ETHER_NOKEY"
                    return
                }
                if (!line.startsWith("data:")) {
                    if (line.trim() !== "" && !line.startsWith("event:")) root.aiRaw += line + "\n"
                    return
                }
                const payload = line.slice(5).trim()
                if (payload === "" || payload === "[DONE]") return
                try {
                    const j = JSON.parse(payload)
                    let d = ""
                    if (root.aiProvider === "anthropic") {
                        if (j.type === "content_block_delta" && j.delta) d = j.delta.text || ""
                        else if (j.type === "error") root.aiRaw += payload
                    } else if (root.aiProvider === "openai") {
                        d = j.choices && j.choices[0] && j.choices[0].delta ? (j.choices[0].delta.content || "") : ""
                        if (j.error) root.aiRaw += payload
                    } else {
                        const parts = j.candidates && j.candidates[0] && j.candidates[0].content
                                      ? (j.candidates[0].content.parts || []) : []
                        d = parts.map(p => p.text || "").join("")
                        if (j.error) root.aiRaw += payload
                    }
                    if (d) root.aiStreaming += d
                } catch (e) {}
            }
        }
        onExited: {
            stdinEnabled = true
            let msg = null
            if (root.aiStreaming !== "") {
                msg = { role: "assistant", text: root.aiStreaming }
            } else if (root.aiRaw === "ETHER_NOKEY") {
                msg = { role: "assistant", error: true,
                        text: "No API key saved for " + root.aiProviders[root.aiProvider].name
                              + ". Add one in Settings, under AI assistant." }
            } else {
                let why = ""
                try {
                    const j = JSON.parse(root.aiRaw.trim())
                    why = (j.error && (j.error.message || j.error)) || j.message || ""
                } catch (e) {
                    why = root.aiRaw.trim().slice(0, 300)
                }
                msg = { role: "assistant", error: true,
                        text: why ? "The request failed: " + why
                                  : "No reply came back. Check your connection and API key." }
            }
            root.aiMessages = root.aiMessages.concat([msg])
            root.aiStreaming = ""
            root.aiBusy = false
        }
    }

    // ---- timer and stopwatch ---------------------------------------------
    // Times are kept against the clock (when it ends, when it started), not
    // counted by ticks, so they stay right even if the shell is busy.  The
    // tick only refreshes what's shown.
    property double timerEnd: 0          // when a running timer ends (ms)
    property int timerTotal: 0           // its length (s)
    property int timerHeld: 0            // seconds left while paused
    property int timerLeft: 0            // seconds left, for showing
    readonly property bool timerOn: timerEnd > 0 || timerHeld > 0
    readonly property bool timerPaused: timerEnd === 0 && timerHeld > 0
    property double swStart: 0           // when the stopwatch last started (ms)
    property double swBanked: 0          // time counted before that (ms)
    property bool swRunning: false
    property double swMs: 0              // elapsed, for showing
    readonly property bool swOn: swRunning || swBanked > 0

    function startTimer(sec) {
        sec = Math.max(1, Math.round(sec))
        timerTotal = sec
        timerHeld = 0
        timerEnd = Date.now() + sec * 1000
        timerLeft = sec
    }
    function pauseTimer() {
        if (timerEnd === 0) return
        timerHeld = Math.max(1, Math.ceil((timerEnd - Date.now()) / 1000))
        timerEnd = 0
    }
    function resumeTimer() {
        if (timerHeld <= 0) return
        timerEnd = Date.now() + timerHeld * 1000
        timerHeld = 0
    }
    function cancelTimer() { timerEnd = 0; timerHeld = 0; timerLeft = 0; timerTotal = 0 }
    function swToggle() {
        if (swRunning) { swBanked += Date.now() - swStart; swRunning = false }
        else { swStart = Date.now(); swRunning = true }
        swMs = swBanked
    }
    function swReset() { swRunning = false; swBanked = 0; swMs = 0 }
    // 75 -> "1:15", 3700 -> "1:01:40"
    function fmtDur(sec) {
        sec = Math.max(0, Math.floor(sec))
        const h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, x = sec % 60
        const p = v => (v < 10 ? "0" : "") + v
        return h > 0 ? h + ":" + p(m) + ":" + p(x) : m + ":" + p(x)
    }
    // "5m", "90s", "1h 30m", "2.5m" -> seconds; 0 when it isn't a length
    function parseDur(t) {
        let total = 0, found = false
        const re = /(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)?/gi
        let m
        while ((m = re.exec(t)) !== null) {
            if (m[0].trim() === "") { re.lastIndex++; continue }
            const n = parseFloat(m[1]), u = (m[2] || "m").toLowerCase()
            total += u.startsWith("h") ? n * 3600 : u.startsWith("s") ? n : n * 60
            found = true
        }
        return found ? Math.round(total) : 0
    }
    Timer {
        interval: 200
        repeat: true
        running: root.timerEnd > 0 || root.swRunning
        onTriggered: {
            const now = Date.now()
            if (root.timerEnd > 0) {
                root.timerLeft = Math.max(0, Math.ceil((root.timerEnd - now) / 1000))
                if (now >= root.timerEnd) root.timerDone()
            }
            if (root.swRunning) root.swMs = root.swBanked + now - root.swStart
        }
    }
    function timerDone() {
        const len = timerTotal
        cancelTimer()
        // in the island if it's there (it says so itself); otherwise a notification
        if (islandOn) showIsland({ kind: "timer", len: fmtDur(len) }, 10000)
        timerAlert.command = ["sh", "-c",
            (islandOn ? '' : 'notify-send -a Timer -u critical -i alarm "Time\'s up" "Your $1 timer has finished"; ') +
            'for f in /usr/share/sounds/freedesktop/stereo/complete.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do ' +
            '[ -f "$f" ] && { pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null; break; }; done',
            "sh", fmtDur(len)]
        timerAlert.running = true
    }
    Process { id: timerAlert }

    // ---- launcher --------------------------------------------------------
    // SUPER (tapped) or `qs ipc call launcher toggle`.  It grows out of the
    // centre of the long bar like the other drawers; in the islands style
    // it's a card under the bar.
    property bool launcherShown: false
    property var launcherGeom: null
    onLauncherShownChanged: if (launcherShown) {
        cardShown = false; quickShown = false; sysShown = false
        clipProc.running = true          // fresh clipboard history for ;
    }
    // how often each app has been opened from the launcher, for ranking
    readonly property var launchCounts: cfg.launchCounts ?? ({})
    function noteLaunch(id) {
        const c = Object.assign({}, launchCounts)
        c[id] = (c[id] || 0) + 1
        setting("launchCounts", c)
    }
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

    function fmtTime(sec) {
        if (!sec || sec < 0 || !isFinite(sec)) return "0:00"
        const s = Math.floor(sec % 60)
        const m = Math.floor(sec / 60) % 60
        const h = Math.floor(sec / 3600)
        const pad = n => (n < 10 ? "0" + n : "" + n)
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
    }

    function run(cmd) {
        launchProc.command = ["sh", "-c", cmd]
        launchProc.running = true
    }

    function dismissNotif(id) {
        const obj = root.notifRefs[id]
        if (obj) {
            try { obj.dismiss() } catch (e) {}
        }
        root.notifList = root.notifList.filter(n => n.id !== id)
        root.popups = root.popups.filter(n => n.id !== id)
    }

    function clearNotifs() {
        for (const k in root.notifRefs) {
            try { root.notifRefs[k].dismiss() } catch (e) {}
        }
        root.notifRefs = ({})
        root.notifList = []
        root.popups = []
    }

    function saveMarks() {
        saveProc.command = ["sh", "-c",
            "printf '%s' '" + root.markedDays.join(",") + "' > '" + root.notesPath + "'"]
        saveProc.running = true
    }

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

    // ---- holidays ----------------------------------------------------
    // Major US holidays, worked out per year: fixed dates, "nth weekday
    // of the month" ones, and Easter.  Keyed "MM-DD".
    property var holCache: ({})
    readonly property bool calHolidays: cfg.calHolidays !== false
    readonly property int calWeekStart: cfg.calWeekStart === 1 ? 1 : 0   // 0 Sunday, 1 Monday
    function holidaysFor(y) {
        if (holCache[y]) return holCache[y]
        const out = {}
        const pad = n => (n < 10 ? "0" : "") + n
        const add = (m, d, name) => {
            const k = pad(m + 1) + "-" + pad(d)
            out[k] = out[k] ? out[k] + " and " + name : name
        }
        // nth weekday (0 Sun .. 6 Sat) of month m; n = -1 for the last
        const nth = (m, wd, n) => {
            if (n > 0) {
                const first = new Date(y, m, 1).getDay()
                return 1 + (wd - first + 7) % 7 + (n - 1) * 7
            }
            const lastD = new Date(y, m + 1, 0).getDate()
            const lastWd = new Date(y, m, lastD).getDay()
            return lastD - (lastWd - wd + 7) % 7
        }
        // Easter Sunday (anonymous Gregorian algorithm)
        const a = y % 19, b = Math.floor(y / 100), c = y % 100
        const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
        const g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
        const i = Math.floor(c / 4), k = c % 4
        const l = (32 + 2 * e + 2 * i - h - k) % 7
        const mm = Math.floor((a + 11 * h + 22 * l) / 451)
        const eMonth = Math.floor((h + l - 7 * mm + 114) / 31) - 1
        const eDay = ((h + l - 7 * mm + 114) % 31) + 1

        add(0, 1,  "New Year's Day")
        add(0, nth(0, 1, 3),  "Martin Luther King Jr. Day")
        add(1, 14, "Valentine's Day")
        add(1, nth(1, 1, 3),  "Presidents' Day")
        add(2, 17, "St. Patrick's Day")
        add(eMonth, eDay, "Easter")
        add(4, nth(4, 0, 2),  "Mother's Day")
        add(4, nth(4, 1, -1), "Memorial Day")
        add(5, nth(5, 0, 3),  "Father's Day")
        add(5, 19, "Juneteenth")
        add(6, 4,  "Independence Day")
        add(8, nth(8, 1, 1),  "Labor Day")
        add(9, nth(9, 1, 2),  "Indigenous Peoples' Day")
        add(9, 31, "Halloween")
        add(10, 11, "Veterans Day")
        add(10, nth(10, 4, 4), "Thanksgiving")
        add(11, 24, "Christmas Eve")
        add(11, 25, "Christmas Day")
        add(11, 31, "New Year's Eve")

        // stored by mutation, not reassignment: this runs inside the
        // calCells binding, and reassigning would make it re-run forever
        holCache[y] = out
        return out
    }
    function holidayOn(key) {
        if (!calHolidays) return ""
        return holidaysFor(parseInt(key.slice(0, 4)))[key.slice(5)] ?? ""
    }

    // ---- day notes ---------------------------------------------------
    // ~/.config/quickshell/day-notes.json:
    //   { "once":   { "2026-10-04": "Dentist" },
    //     "yearly": { "04-02": "Anniversary of 2001: A Space Odyssey" } }
    // A missing file starts with the April 2 note; once the file exists
    // it's whatever you've kept.
    readonly property var notesSeed: ({
        once: {},
        yearly: { "04-02": "Anniversary of 2001: A Space Odyssey (premiered 2 April 1968)" }
    })
    property var dayNotes: notesSeed

    Process {
        id: dayNotesRead
        running: true
        command: ["sh", "-c", "cat ~/.config/quickshell/day-notes.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) return
                try {
                    const o = JSON.parse(t)
                    root.dayNotes = { once: o.once || {}, yearly: o.yearly || {} }
                } catch (e) {
                    console.log("day-notes.json parse failed, keeping defaults:", e)
                }
            }
        }
    }
    Process { id: dayNotesWrite }
    function saveDayNotes() {
        dayNotesWrite.command = ["sh", "-c",
            'f="$HOME/.config/quickshell/day-notes.json"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
            "sh", JSON.stringify(dayNotes, null, 2) + "\n"]
        dayNotesWrite.running = true
    }

    // every note on a day, yearly ones first: [{ text, yearly }]
    function notesOn(key) {
        const out = []
        const y = dayNotes.yearly[key.slice(5)]
        if (y) out.push({ text: y, yearly: true })
        const o = dayNotes.once[key]
        if (o) out.push({ text: o, yearly: false })
        return out
    }
    function setDayNote(key, text, yearly) {
        const t = text.trim()
        if (t === "") return
        const n = JSON.parse(JSON.stringify(dayNotes))
        if (yearly) n.yearly[key.slice(5)] = t
        else n.once[key] = t
        dayNotes = n
        saveDayNotes()
    }
    function deleteDayNote(key, yearly) {
        const n = JSON.parse(JSON.stringify(dayNotes))
        if (yearly) delete n.yearly[key.slice(5)]
        else delete n.once[key]
        dayNotes = n
        saveDayNotes()
    }

    readonly property var calBase: {
        const n = new Date()
        return new Date(n.getFullYear(), n.getMonth() + root.monthOffset, 1)
    }

    readonly property var calCells: {
        const base = root.calBase
        const y = base.getFullYear(), mo = base.getMonth()
        // days shown before the 1st, counting from the chosen week start
        const firstDow = (new Date(y, mo, 1).getDay() - root.calWeekStart + 7) % 7
        const inMonth = new Date(y, mo + 1, 0).getDate()
        const prevLen = new Date(y, mo, 0).getDate()
        const now = new Date()
        const pad = n => (n < 10 ? "0" + n : "" + n)
        const key = (yy, mm, dd) => yy + "-" + pad(mm + 1) + "-" + pad(dd)

        const cells = []
        for (let i = firstDow - 1; i >= 0; i--) {
            const d = prevLen - i
            const pm = mo === 0 ? 11 : mo - 1
            const py = mo === 0 ? y - 1 : y
            const kk = key(py, pm, d)
            cells.push({ d: d, cur: false, today: false, key: kk,
                         hol: holidayOn(kk), noted: notesOn(kk).length > 0 })
        }
        for (let i = 1; i <= inMonth; i++) {
            const kk = key(y, mo, i)
            cells.push({
                d: i, cur: true,
                today: i === now.getDate() && mo === now.getMonth() && y === now.getFullYear(),
                key: kk, hol: holidayOn(kk), noted: notesOn(kk).length > 0
            })
        }
        let nx = 1
        while (cells.length < 42) {
            const nm = mo === 11 ? 0 : mo + 1
            const ny = mo === 11 ? y + 1 : y
            const kk = key(ny, nm, nx)
            cells.push({ d: nx, cur: false, today: false, key: kk,
                         hol: holidayOn(kk), noted: notesOn(kk).length > 0 })
            nx++
        }
        return cells
    }

    // the same, as a Material Symbol, with night versions
    function wxSymbol(c, day) {
        const s = (c || "").toLowerCase()
        if (s.indexOf("thunder") !== -1) return "thunderstorm"
        if (s.indexOf("snow") !== -1 || s.indexOf("rime") !== -1) return "weather_snowy"
        if (s.indexOf("rain") !== -1 || s.indexOf("drizzle") !== -1 || s.indexOf("shower") !== -1) return "rainy"
        if (s.indexOf("fog") !== -1) return "foggy"
        if (s.indexOf("overcast") !== -1) return "cloud"
        if (s.indexOf("cloud") !== -1 || s.indexOf("mainly") !== -1)
            return day === false ? "partly_cloudy_night" : "partly_cloudy_day"
        if (s.indexOf("clear") !== -1) return day === false ? "clear_night" : "sunny"
        return "cloud"
    }

    // manual overrides for apps whose window class doesn't match their
    // .desktop file id
    readonly property var iconOverrides: ({
        "spotify":            "spotify",
        "discord":            "discord",
        "vesktop":            "vesktop",
        "code":               "code",
        "code-oss":           "code-oss",
        "steam":              "steam",
        "steam_app":          "steam",
        "thunar":             "thunar",
        "org.kde.dolphin":    "org.kde.dolphin",
        "kitty":              "kitty",
        "firefox":            "firefox",
        "librewolf":          "librewolf",
        "chromium":           "chromium",
        "obsidian":           "obsidian",
        "lutris":             "lutris",
        "heroic":             "heroic",
        "pavucontrol":        "pavucontrol",
        "systemsettings":     "systemsettings"
    })

    function iconFor(cls) {
        const raw = (cls || "").trim()
        if (!raw) return Quickshell.iconPath("application-x-executable")
        const low = raw.toLowerCase()

        // 1. explicit override
        const ov = root.iconOverrides[low]
        if (ov) {
            const e0 = DesktopEntries.byId(ov)
            if (e0) return Quickshell.iconPath(e0.icon, true)
            const p0 = Quickshell.iconPath(ov, true)
            if (p0) return p0
        }

        // 2. straight desktop-entry lookups
        const tries = [raw, low, low.replace(/_/g, "-"), low.split(".").pop()]
        for (const t of tries) {
            const e = DesktopEntries.byId(t)
            if (e) return Quickshell.iconPath(e.icon, true)
        }

        // 3. scan every entry for a matching StartupWMClass or id tail
        const all = DesktopEntries.applications?.values ?? []
        for (const e of all) {
            const sc = (e.startupClass || "").toLowerCase()
            if (sc && sc === low) return Quickshell.iconPath(e.icon, true)
        }
        for (const e of all) {
            const id = (e.id || "").toLowerCase()
            if (id === low || id.endsWith("." + low))
                return Quickshell.iconPath(e.icon, true)
        }

        // 4. icon theme by name, then generic
        const p = Quickshell.iconPath(low, true)
        if (p) return p
        return Quickshell.iconPath("application-x-executable")
    }

    // kept so anything already calling `qs ipc call audio ...` still
    // works: it opens Settings on the Output page
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
        clipProc.running = true
    }
    // "[[ binary data 55 KiB png 1920x1080 ]]" -> { ext: "png", size: "1920x1080" }
    function clipImageInfo(preview) {
        const m = (preview || "").match(/^\[\[ binary data (.+?) (png|jpe?g|bmp|webp|gif)(?: (\d+x\d+))? \]\]$/i)
        return m ? { ext: m[2].toLowerCase(), size: m[3] || "", bytes: m[1] } : null
    }
    readonly property string clipThumbDir: Quickshell.env("HOME") + "/.cache/ether/clip"
    property int clipThumbVer: 0
    function makeClipThumbs() {
        const args = []
        for (const c of clipItems.slice(0, 60)) {
            const info = clipImageInfo(c.preview)
            if (info && /^[0-9]+$/.test(c.id)) args.push(c.id + ":" + info.ext)
        }
        if (!args.length) return
        clipThumbProc.command = ["sh", "-c",
            'd="$HOME/.cache/ether/clip"; mkdir -p "$d"; ' +
            'for x in "$@"; do id=${x%%:*}; ext=${x#*:}; ' +
            '[ -s "$d/$id.$ext" ] || cliphist decode "$id" > "$d/$id.$ext" 2>/dev/null; done',
            "sh"].concat(args)
        clipThumbProc.running = true
    }
    Process {
        id: clipThumbProc
        onExited: root.clipThumbVer++
    }

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

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

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

    Timer {
        // the track position: every half second while a media view is
        // open, every second otherwise, for the pill's progress line
        // four times a second while lyrics are following along
        interval: root.cardShown && root.lyricsState === "synced" && root.lyricsOn ? 250
                : (root.cardShown || root.sidebarShown) ? 500 : 1000
        running: root.player !== null
        repeat: true; triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }

    // ---- system stats -----------------------------------------------------
    // Two long-running readers instead of launching four commands (nine
    // programs) every 2 seconds.  statsProc loops by itself, reading
    // /proc/stat, /proc/meminfo and /proc/net/dev with the shell's own
    // built-ins, so the only thing it starts is `sleep`.  gpuStream is one
    // nvidia-smi in its looping mode, which keeps the driver awake between
    // readings instead of waking it from scratch each time.  If either
    // stops, it's started again a few seconds later.
    Process {
        id: statsProc
        command: ["sh", "-c",
            'while :; do ' +
            '  read -r _ u n s i w q sq st _ < /proc/stat; ' +
            '  t=0; a=0; ' +
            '  while read -r k v _; do case $k in MemTotal:) t=$v;; MemAvailable:) a=$v; break;; esac; done < /proc/meminfo; ' +
            '  rx=0; tx=0; ' +
            '  { read -r _; read -r _; while read -r line; do ' +
            '      name=${line%%:*}; set -- $name; name=$1; [ "$name" = lo ] && continue; ' +
            '      set -- ${line#*:}; rx=$((rx + $1)); tx=$((tx + $9)); ' +
            '    done; } < /proc/net/dev; ' +
            '  echo "S $u $n $s $i $w $q $sq $st $t $a $rx $tx"; ' +
            '  sleep 2; ' +
            'done']
        stdout: SplitParser {
            onRead: line => {
                const f = line.trim().split(/\s+/)
                if (f[0] !== "S" || f.length < 13) return
                const v = f.slice(1).map(Number)
                // cpu: busy share of the time since the last reading
                const total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7]
                const idle = v[3] + v[4]
                if (root.lastCpu) {
                    const dt = total - root.lastCpu.total, di = idle - root.lastCpu.idle
                    if (dt > 0) root.cpuPct = Math.round(100 * (dt - di) / dt)
                }
                root.lastCpu = { total: total, idle: idle }
                // memory in use
                if (v[8] > 0) root.memPct = Math.round((v[8] - v[9]) * 100 / v[8])
                // network: bytes per second since the last reading
                const now = Date.now()
                if (root.lastNet) {
                    const secs = (now - root.lastNet.t) / 1000
                    if (secs > 0) {
                        root.netDown = root.fmtRate(Math.max(0, (v[10] - root.lastNet.rx) / secs))
                        root.netUp   = root.fmtRate(Math.max(0, (v[11] - root.lastNet.tx) / secs))
                    }
                }
                root.lastNet = { rx: v[10], tx: v[11], t: now }
                root.recordStats()
            }
        }
        onExited: statsRestart.restart()
    }
    Timer { id: statsRestart; interval: 3000; onTriggered: statsProc.running = true }

    Process {
        id: gpuStream
        command: ["sh", "-c",
            "command -v nvidia-smi >/dev/null || exit 0; " +
            "exec nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw " +
            "--format=csv,noheader,nounits -lms 2000 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                const p = line.split(",").map(x => parseFloat(x.trim()))
                if (p.length < 5 || isNaN(p[0])) return
                root.gpuPct    = Math.round(p[0])
                root.gpuTemp   = Math.round(p[1])
                root.gpuMemPct = p[3] > 0 ? Math.round(100 * p[2] / p[3]) : 0
                root.gpuWatts  = Math.round(p[4])
                root.gpuOk = true
            }
        }
        // no NVIDIA card, or the driver went away: try again in a while
        onExited: { root.gpuOk = false; gpuRestart.restart() }
    }
    Timer { id: gpuRestart; interval: 15000; onTriggered: gpuStream.running = true }

    // ---- the native readers, when the plugin is installed ----
    // NativeStats.qml imports Ether.Native (built from native/ by the
    // installer).  If it loads, it does the stats and the visualiser, and the
    // readers above never start.  If not, it fails to load, and they do.
    Loader {
        id: nativeLoader
        source: "NativeStats.qml"
        onLoaded: { item.home = Quickshell.env("HOME"); item.app = root }
        onStatusChanged: if (status === Loader.Error) root.startFallbackReaders()
    }
    readonly property bool nativeOk: nativeLoader.status === Loader.Ready
    function startFallbackReaders() {
        statsProc.running = true
        gpuStream.running = true
    }

    // ---- stats history, for the system panel's graphs ----------------
    // The last 60 readings of each (two minutes at one every 2 s), as
    // plain numbers.  Sampled on the clock rather than on change, so a
    // flat line is still a line and the graphs keep an even pace.
    property var cpuHist: []
    property var memHist: []
    property var gpuHist: []
    property var tempHist: []
    function recordStats() {
        const push = (a, v) => { const b = a.slice(-59); b.push(v); return b }
        cpuHist = push(cpuHist, cpuPct)
        memHist = push(memHist, memPct)
        if (gpuOk) {
            gpuHist = push(gpuHist, gpuPct)
            tempHist = push(tempHist, gpuTemp)
        }
    }

    // the busiest processes, read only while the system panel is open
    property bool sysShown: false
    property var topProcs: []
    Process {
        id: procsProc
        command: ["sh", "-c", "ps -eo comm,%cpu,%mem --sort=-%cpu --no-headers | head -5"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/)
                    if (f.length < 3) continue
                    const mem = parseFloat(f.pop()), cpu = parseFloat(f.pop())
                    out.push({ name: f.join(" "), cpu: cpu || 0, mem: mem || 0 })
                }
                root.topProcs = out
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.sysShown
        onTriggered: procsProc.running = true
    }
    onSysShownChanged: if (sysShown) {
        aiShown = false
        upProc.running = true
        cardShown = false
        quickShown = false
        launcherShown = false
    }

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: upProc.running = true
    }

    Timer {
        interval: 900000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }

    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: loadProc.running = true
    }

    Process { id: switchProc }
    Process { id: wallApply }

    // list the wallpaper folder whenever the Wallpaper page opens, so
    // newly added images show up without restarting the shell
    Process {
        id: wallList
        running: root.settingsShown && root.settingsPage === 3
        command: ["sh", "-c",
            "find \"$HOME/Pictures/wallpapers\" -maxdepth 1 -type f "
            + "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' "
            + "-o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length)
                root.wallpapers = lines
            }
        }
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
    }

    // ---- each wallpaper's colours, for the swatches in the selector ----
    // Worked out with matugen's --dry-run (nothing is changed), one
    // wallpaper at a time in the background, for the current style,
    // contrast, colour source and mode; cached in
    // ~/.cache/ether/palettes.json, so they're only worked out once.
    // wallPalettes: { path: [accent, secondary, tertiary, container, background] }
    readonly property string paletteKey: themeScheme + "|" + themeContrast.toFixed(2) + "|"
                                         + themePrefer + "|" + (isLight ? "light" : "dark")
    property var paletteCache: ({})      // { key: { path: [...] } }
    readonly property var wallPalettes: paletteCache[paletteKey] || ({})
    property var paletteQueue: []
    Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.cache/ether/palettes.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { try { const d = JSON.parse(text); if (d && typeof d === "object") root.paletteCache = d } catch (e) {} }
        }
    }
    // the selector lists wallpapers when it opens: work out any missing
    onWallpapersChanged: queuePalettes()
    onPaletteKeyChanged: queuePalettes()
    function queuePalettes() {
        const have = paletteCache[paletteKey] || {}
        paletteQueue = wallpapers.filter(p => !have[p])
        if (!paletteProc.running) nextPalette()
    }
    function nextPalette() {
        if (!paletteQueue.length) return
        const path = paletteQueue[0]
        paletteQueue = paletteQueue.slice(1)
        paletteProc.path = path
        paletteProc.key = paletteKey
        paletteProc.command = ["matugen", "image", path, "--dry-run", "-j", "hex", "-q",
                               "--type", themeScheme, "--contrast", themeContrast.toFixed(2),
                               "--prefer", themePrefer, "--mode", isLight ? "light" : "dark"]
        paletteProc.running = true
    }
    Process {
        id: paletteProc
        property string path: ""
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).colors
                    const m = paletteProc.key.endsWith("light") ? "light" : "dark"
                    const pick = k => (c[k] && c[k][m] ? c[k][m].color : "")
                    const colours = ["primary", "secondary", "tertiary", "primary_container", "surface"].map(pick)
                    if (colours.every(x => x)) {
                        const all = Object.assign({}, root.paletteCache)
                        all[paletteProc.key] = Object.assign({}, all[paletteProc.key] || {})
                        all[paletteProc.key][paletteProc.path] = colours
                        root.paletteCache = all
                        paletteSave.restart()
                    }
                } catch (e) {}
            }
        }
        onExited: root.nextPalette()
    }
    Timer {
        id: paletteSave
        interval: 1500
        onTriggered: {
            // only the current settings' colours, and only wallpapers that still exist
            const keep = {}
            keep[root.paletteKey] = {}
            const cur = root.paletteCache[root.paletteKey] || {}
            for (const p of root.wallpapers) if (cur[p]) keep[root.paletteKey][p] = cur[p]
            paletteWrite.command = ["sh", "-c",
                'd="$HOME/.cache/ether"; mkdir -p "$d"; printf "%s" "$1" > "$d/palettes.json.tmp" && mv "$d/palettes.json.tmp" "$d/palettes.json"',
                "sh", JSON.stringify(keep)]
            paletteWrite.running = true
        }
    }
    Process { id: paletteWrite }

    function applyWallpaper(path) {
        if (!path || wallApply.running) return
        root.currentWall = path
        // automatic light or dark: measure the new wallpaper first (a
        // moment), so it's themed in the right mode from the start
        if (cfg.themeMode === "auto" && nativeOk) { wallWait.path = path; wallWait.restart(); return }
        runSetwall(path)
    }
    // setwall, with the theme settings written first (the mode may just
    // have changed with the wallpaper)
    function runSetwall(path) {
        wallApply.command = ["sh", "-c",
            'f="$HOME/.config/matugen/shell-theme"; ' +
            'printf "TYPE=%s\\nCONTRAST=%s\\nPREFER=%s\\nMODE=%s\\n" "$1" "$2" "$3" "$4" > "$f.tmp" && mv "$f.tmp" "$f"; ' +
            'exec "$HOME/.local/bin/setwall" "$5"',
            "sh", themeScheme, themeContrast.toFixed(2), themePrefer, isLight ? "light" : "dark", path]
        wallApply.running = true
    }
    // the plugin has measured the wallpaper (NativeStats.qml calls this)
    function wallMeasured(lightness) {
        wallLightness = lightness
        if (wallWait.running) { wallWait.stop(); runSetwall(wallWait.path) }
    }
    // measured or not, don't wait longer than this
    Timer { id: wallWait; property string path: ""; interval: 1500; onTriggered: root.runSetwall(path) }
    // (Choosing Auto in Settings re-themes through the usual setting change;
    // a new wallpaper through wallWait above.  The first measurement at
    // startup changes nothing: the theme on disk already matches it.)
    function randomWallpaper() {
        const pool = root.wallpapers.filter(p => p !== root.currentWall)
        if (pool.length) applyWallpaper(pool[Math.floor(Math.random() * pool.length)])
    }

    // the wallpaper in use, as setwall recorded it
    property string currentWall: ""
    readonly property bool wallBusy: wallApply.running
    Process {
        id: wallCurrent
        running: true
        command: ["sh", "-c", "cat ~/.cache/wallpaper 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: root.currentWall = text.trim()
        }
    }

    Process {
        id: cavaProc
        // the native reader does this when the plugin is installed
        running: root.cardShown && !root.nativeOk
        command: ["cava", "-p", Quickshell.env("HOME")
                  + "/.config/cava/quickshell.conf"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const out = []
                for (let i = 0; i < 28; i++) {
                    const v = parseInt(parts[i])
                    out.push(isNaN(v) ? 0 : v)
                }
                root.cavaBars = out
            }
        }
        onRunningChanged: {
            if (!running) root.cavaBars = new Array(28).fill(0)
        }
    }

    // read the matugen-generated palette at startup
    Process {
        id: palProc
        running: true
        command: ["sh", "-c",
            "cat ~/.config/quickshell/colors.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) return
                try {
                    root.pal = JSON.parse(t)
                    if (!root.colourFade) fadeOn.start()
                } catch (e) {
                    console.log("palette parse failed:", e)
                }
            }
        }
    }

    // ---- settings ------------------------------------------------------
    // ~/.config/quickshell/settings.json holds only what has been
    // changed; everything else comes from cfgDefaults, so a missing or
    // broken file changes nothing.  Modules read app.cfg.<key> and
    // size text with app.fs(px).  The settings page writes through
    // setting(); after hand-editing the file, run
    //   qs ipc call settings reload
    readonly property var cfgDefaults: ({
        fontScale:   1.0,     // 0.7 - 1.6
        bgOpacity:   0.75,    // 0.3 - 1.0, every shell surface
        osdMs:       1400,    // volume indicator on screen
        notifMs:     6000,    // popup life; critical ones get double
        dockEnabled: true,
        termOpacity: 0.75,    // kitty background, 0.3 - 1.0

        // Hyprland: these defaults must match the ones at the top of
        // hyprland.lua, which is what applies when a key is unset
        gapsIn:      4,
        gapsOut:     1,
        borderSize:  2,
        rounding:    12,
        winActive:   1.0,
        winInactive: 1.0,
        blurSize:    4,
        blurPasses:  3,
        animations:  true,
        animSpeed:   1.0,

        // matugen: colour style and contrast, used by setwall
        themeScheme:   "scheme-tonal-spot",
        themeContrast: 0,
        themePrefer:   "saturation",
        themeMode:     "dark",
        nightLight:    false,

        // bar
        clock24h:     false,
        clockSeconds: false,
        clockDate:    true,
        barStats:     true,     // CPU and memory
        barGpu:       true,
        barNet:       true,
        barMedia:     true,     // now playing, centre of the bar

        // idle, in minutes; 0 means never
        idleLockMin:   5,
        idleScreenMin: 10,
        idleSleepMin:  0,

        // Hyprland input (also in hyprKeys below)
        repeatRate:    25,
        repeatDelay:   600,
        sensitivity:   0,
        accelFlat:     false,
        naturalScroll: false,
        followMouse:   true
    })

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
    property var cfgUser: ({})
    readonly property var cfg: Object.assign({}, cfgDefaults, cfgUser)

    function fs(px) {
        const k = Math.max(0.7, Math.min(1.6, Number(cfg.fontScale) || 1))
        return Math.round(px * k)
    }

    function setting(key, value) {
        const o = Object.assign({}, cfgUser)
        o[key] = value
        cfgUser = o
        saveSettings()
        applyExternal(key)
    }
    function resetSetting(key) {
        const o = Object.assign({}, cfgUser)
        delete o[key]
        cfgUser = o
        saveSettings()
        applyExternal(key)
    }
    function resetAllSettings() {
        cfgUser = ({})
        saveSettings()
        applyExternal("*")
    }

    // Settings that belong to other programs.  kitty reads
    // ~/.config/kitty/shell-settings.conf (included at the end of
    // kitty.conf) and reloads it on SIGUSR1; the live opacity change
    // needs `dynamic_background_opacity yes` in kitty.conf.
    function applyExternal(key) {
        if (key === "termOpacity" || key === "*") writeKitty()
        if (key === "*" || key === "wxUnits" || key === "wxLat") wxRefreshLater.restart()
        if (key === "*" || key === "clock24h" || key === "clockSeconds" || key.startsWith("lock"))
            lockDebounce.restart()
        if (key === "*" || hyprKeys[key] !== undefined) hyprDebounce.restart()
        if (key === "*" || key === "idleLockMin" || key === "idleScreenMin"
                || key === "idleSleepMin")
            idleDebounce.restart()
        if (key === "*" || key === "themeScheme" || key === "themeContrast"
                || key === "themePrefer" || key === "themeMode")
            themeDebounce.restart()
    }

    // ---- brightness (DDC/CI) -----------------------------------------
    // External monitors are set through their own controls with
    // ddcutil.  `ddcutil detect` maps each connector to its I2C bus at
    // startup, since bus numbers can change between boots.  Reads happen
    // when the sidebar or Displays page opens; writes are queued so a
    // drag only sends the latest value (each DDC command is slow).
    property var monBus: ({})          // { "DP-1": 7, "DP-2": 8 }
    property var bright: ({})          // { "DP-1": 90, ... } 0-100
    readonly property bool brightOk: Object.keys(monBus).length > 0
    readonly property int brightAvg: {
        const v = Object.keys(bright).map(k => bright[k])
        return v.length ? Math.round(v.reduce((a, b) => a + b, 0) / v.length) : 0
    }

    Process {
        id: ddcDetect
        running: true
        command: ["sh", "-c", "ddcutil detect 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const block of text.split(/\n(?=Display \d)/)) {
                    const bus = /I2C bus:\s*\/dev\/i2c-(\d+)/.exec(block)
                    const con = /DRM_connector:\s*card\d+-(\S+)/.exec(block)
                    if (bus && con) map[con[1]] = parseInt(bus[1])
                }
                root.monBus = map
                root.readBrightness()
            }
        }
    }

    function readBrightness() {
        if (!brightOk || ddcRead.running) return
        const cmds = Object.keys(monBus).map(n =>
            'printf "%s " ' + n + '; ddcutil --bus ' + monBus[n] + ' getvcp 10 --brief 2>/dev/null || echo')
        ddcRead.command = ["sh", "-c", cmds.join("; ")]
        ddcRead.running = true
    }
    Process {
        id: ddcRead
        stdout: StdioCollector {
            onStreamFinished: {
                // lines look like "DP-1 VCP 10 C 90 100"
                const b = Object.assign({}, root.bright)
                for (const line of text.split("\n")) {
                    const m = /^(\S+) VCP 10 C (\d+) (\d+)/.exec(line.trim())
                    if (m) b[m[1]] = Math.round(100 * parseInt(m[2]) / Math.max(1, parseInt(m[3])))
                }
                root.bright = b
            }
        }
    }

    property var brightPending: ({})
    function setBright(name, v) {
        if (monBus[name] === undefined) return
        v = Math.max(0, Math.min(100, Math.round(v)))
        const b = Object.assign({}, bright); b[name] = v; bright = b
        const p = Object.assign({}, brightPending); p[name] = v; brightPending = p
        brightDebounce.restart()
    }
    function setAllBright(v) {
        for (const n of Object.keys(monBus)) setBright(n, v)
        showOsdOf("brightness", brightAvg / 100, false)
    }
    Timer {
        id: brightDebounce
        interval: 120
        onTriggered: root.flushBright()
    }
    function flushBright() {
        const names = Object.keys(brightPending)
        if (!names.length || ddcWrite.running) return
        const cmds = names.map(n =>
            "ddcutil --bus " + monBus[n] + " setvcp 10 " + brightPending[n] + " --noverify 2>/dev/null")
        brightPending = ({})
        ddcWrite.command = ["sh", "-c", cmds.join("; ")]
        ddcWrite.running = true
    }
    Process {
        id: ddcWrite
        onExited: root.flushBright()
    }

    // ---- night light -------------------------------------------------
    // On runs hyprsunset at a fixed warmth; off stops it, which puts
    // the normal colours back.  Remembered across restarts.
    readonly property bool nightLight: cfg.nightLight === true
    readonly property int nightTemp: 4000
    Process { id: nightProc }
    function applyNight() {
        nightProc.command = ["sh", "-c", nightLight
            ? "pgrep -x hyprsunset >/dev/null || setsid -f hyprsunset -t " + nightTemp + " >/dev/null 2>&1"
            : "pkill -x hyprsunset; true"]
        nightProc.running = true
    }
    function toggleNight() {
        setting("nightLight", !nightLight)
        applyNight()
        showOsdOf("night", nightLight ? 1 : 0, !nightLight)
    }
    Component.onCompleted: {
        if (nightLight) applyNight()
    }

    // ---- displays ----------------------------------------------------
    // monInfo: plain values from `hyprctl monitors all -j`, refreshed
    // whenever the Displays page opens.  Never live objects.
    property var monInfo: []
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monInfo = JSON.parse(text).map(m => ({
                        name:  m.name,
                        desc:  ((m.make || "") + " " + (m.model || "")).trim() || m.description || "",
                        w:     m.width,
                        h:     m.height,
                        hz:    m.refreshRate,
                        scale: m.scale,
                        modes: (m.availableModes || []).map(x => String(x))
                    }))
                } catch (e) {
                    console.log("hyprctl monitors parse failed:", e)
                }
            }
        }
    }
    function refreshMonitors() { monProc.running = true }
    // the Displays page reads modes and brightness each time it opens
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

    // Apply, then keep or revert.  The countdown lives here rather than
    // in the panel, so it still runs if the screen showing the panel
    // goes dark.
    property var displayBackup: undefined
    property bool displayHadUser: false
    property int revertLeft: 0

    property var arrangeBackup: undefined
    function applyDisplays(monitors, arrange) {
        if (revertLeft === 0) {
            displayHadUser = cfgUser.monitors !== undefined
            displayBackup = displayHadUser
                ? JSON.parse(JSON.stringify(cfgUser.monitors)) : undefined
            arrangeBackup = cfgUser.monitorsArrange
        }
        setting("monitorsArrange", arrange)
        setting("monitors", monitors)
        revertLeft = 15
        revertTimer.restart()
    }
    function keepDisplays() {
        revertTimer.stop()
        revertLeft = 0
        displayBackup = undefined
        refreshMonitors()
    }
    function revertDisplays() {
        revertTimer.stop()
        revertLeft = 0
        if (arrangeBackup === undefined) resetSetting("monitorsArrange")
        else setting("monitorsArrange", arrangeBackup)
        if (displayHadUser) setting("monitors", displayBackup)
        else resetSetting("monitors")
        displayBackup = undefined
        monRefreshLater.restart()
    }
    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.revertLeft -= 1
            if (root.revertLeft <= 0) root.revertDisplays()
        }
    }
    // Hyprland needs a moment after the reload before it reports the
    // restored modes
    Timer {
        id: monRefreshLater
        interval: 1200
        onTriggered: root.refreshMonitors()
    }

    // ---- default apps --------------------------------------------------
    // Terminal and file manager feed hyprland.lua's SUPER+T / SUPER+E
    // (through shell-settings.lua); the file manager and browser also
    // become the system defaults through xdg-mime / xdg-settings.
    readonly property string termCmd: cfg.appTerminalCmd || "kitty"

    // what xdg currently calls the default, read when the page opens
    property var xdgDefaults: ({ files: "", browser: "" })
    Process {
        id: xdgRead
        command: ["sh", "-c",
            'echo "files=$(xdg-mime query default inode/directory 2>/dev/null)"; '
            + 'echo "browser=$(xdg-settings get default-web-browser 2>/dev/null)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const o = { files: "", browser: "" }
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                root.xdgDefaults = o
            }
        }
    }
    function refreshXdg() { xdgRead.running = true }

    // a desktop entry's command, without the %u / %F placeholders
    function entryCmd(e) {
        return String(e.execString || "").replace(/%[fFuUdDnNickvm]/g, "").replace(/\s+/g, " ").trim()
    }

    Process { id: xdgWrite }
    function setDefaultApp(role, entry) {
        const id = entry.id.endsWith(".desktop") ? entry.id : entry.id + ".desktop"
        const o = Object.assign({}, cfgUser)
        if (role === "terminal") {
            o.appTerminal = id
            o.appTerminalCmd = entry.cmd
        } else if (role === "files") {
            o.appFiles = id
            o.appFilesCmd = entry.cmd
        } else {
            o.appBrowser = id
        }
        cfgUser = o
        saveSettings()
        if (role === "terminal" || role === "files") hyprDebounce.restart()
        if (role === "files")
            xdgWrite.command = ["xdg-mime", "default", id, "inode/directory"]
        else if (role === "browser")
            xdgWrite.command = ["xdg-settings", "set", "default-web-browser", id]
        if (role !== "terminal") xdgWrite.running = true
        xdgRefreshLater.restart()
    }
    Timer {
        id: xdgRefreshLater
        interval: 500
        onTriggered: root.refreshXdg()
    }

    // ---- lock screen ---------------------------------------------------
    // hyprlock.conf sources ~/.config/hypr/hyprlock-settings.conf, which
    // the panel rewrites: clock command (follows the bar's 12/24-hour and
    // seconds settings), blur, dimming, greeting and now-playing line.
    readonly property int lockBlur: {
        const v = Number(cfg.lockBlur)
        return cfg.lockBlur !== undefined && isFinite(v) ? Math.max(0, Math.min(12, Math.round(v))) : 8
    }
    readonly property int lockDim: {
        const v = Number(cfg.lockDim)
        return cfg.lockDim !== undefined && isFinite(v) ? Math.max(20, Math.min(100, Math.round(v))) : 55
    }
    readonly property string lockGreetMode:
        ["time", "custom", "off"].indexOf(cfg.lockGreetMode) >= 0 ? cfg.lockGreetMode : "time"
    readonly property string lockGreetText: cfg.lockGreetText || ""
    readonly property bool lockMedia: cfg.lockMedia !== false

    function lockText() {
        const secs = cfg.clockSeconds === true ? ":%S" : ""
        const clock = cfg.clock24h === true
            ? "echo \"<span font_weight='200'>$(date +'%H:%M" + secs + "')</span>\""
            : "echo \"<span font_weight='200'>$(date +'%-I:%M" + secs + "')</span>"
              + "<span font_size='30pt' font_weight='400'> $(date +'%p')</span>\""
        // a custom greeting goes inside echo "...", so anything that would
        // end the string, expand, or start a hyprlang comment is dropped
        const safe = lockGreetText.replace(/["`$\\#\n\r]/g, "").trim()
        const who = "$(whoami)"
        const greet = lockGreetMode === "off" ? "true"
            : lockGreetMode === "custom" ? "echo \"" + (safe || "Welcome back") + "\""
            : "case $(date +%H) in 0[5-9]|1[01]) echo \"Good morning, " + who + "\";; "
              + "1[2-6]) echo \"Good afternoon, " + who + "\";; "
              + "1[7-9]|2[01]) echo \"Good evening, " + who + "\";; "
              + "*) echo \"Good night, " + who + "\";; esac"
        const media = lockMedia
            ? "playerctl metadata --format '{{title}}   {{artist}}' 2>/dev/null"
            : "true"
        return "# written by the quickshell settings panel (Desktop > Lock screen);\n"
             + "# change it there, hand edits are replaced.\n"
             + "$clock_cmd   = " + clock + "\n"
             + "$blur_passes = " + (lockBlur === 0 ? 0 : 3) + "\n"
             + "$blur_size   = " + Math.max(1, lockBlur) + "\n"
             + "$dim         = " + (lockDim / 100).toFixed(2) + "\n"
             + "$greet_cmd   = " + greet + "\n"
             + "$media_cmd   = " + media + "\n"
    }

    Timer {
        id: lockDebounce
        interval: 300
        onTriggered: {
            lockWrite.command = ["sh", "-c",
                'f="$HOME/.config/hypr/hyprlock-settings.conf"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
                "sh", root.lockText()]
            lockWrite.running = true
        }
    }
    Process { id: lockWrite }

    // ---- idle --------------------------------------------------------
    // hypridle can't reload its config, so the panel regenerates the
    // whole of ~/.config/hypr/hypridle.conf and restarts it.  Only
    // written when an idle setting changes; minutes, 0 = never.
    function idleMin(key, def) {
        const v = Number(cfg[key])
        return isFinite(v) ? Math.max(0, Math.min(240, Math.round(v))) : def
    }
    readonly property int idleLockMin:   idleMin("idleLockMin", 5)
    readonly property int idleScreenMin: idleMin("idleScreenMin", 10)
    readonly property int idleSleepMin:  idleMin("idleSleepMin", 0)

    function idleText() {
        const dpms = s => "hyprctl dispatch 'hl.dsp.dpms(\"" + s + "\")'"
        let t = "# written by the quickshell settings panel (Desktop > Idle);\n"
              + "# change it there, hand edits are replaced.  hyprlang, like hyprlock\n\n"
              + "general {\n"
              + "    lock_cmd         = pidof hyprlock || hyprlock\n"
              + "    before_sleep_cmd = loginctl lock-session\n"
              + "    after_sleep_cmd  = " + dpms("on") + "\n"
              + "}\n"
        if (idleLockMin > 0)
            t += "\n# lock\nlistener {\n"
               + "    timeout    = " + idleLockMin * 60 + "\n"
               + "    on-timeout = loginctl lock-session\n}\n"
        if (idleScreenMin > 0)
            t += "\n# screens off\nlistener {\n"
               + "    timeout    = " + idleScreenMin * 60 + "\n"
               + "    on-timeout = " + dpms("off") + "\n"
               + "    on-resume  = " + dpms("on") + "\n}\n"
        if (idleSleepMin > 0)
            t += "\n# sleep\nlistener {\n"
               + "    timeout    = " + idleSleepMin * 60 + "\n"
               + "    on-timeout = systemctl suspend\n}\n"
        return t
    }

    Timer {
        id: idleDebounce
        interval: 600
        onTriggered: root.writeIdle()
    }

    property string pendingIdle: ""
    function writeIdle() {
        pendingIdle = idleText()
        if (!idleWrite.running) flushIdle()
    }
    function flushIdle() {
        if (pendingIdle === "") return
        idleWrite.command = ["sh", "-c",
            'f="$HOME/.config/hypr/hypridle.conf"; ' +
            'printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"; ' +
            'pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1; true',
            "sh", pendingIdle]
        pendingIdle = ""
        idleWrite.running = true
    }
    Process {
        id: idleWrite
        onExited: root.flushIdle()
    }

    // ---- theme -------------------------------------------------------
    // The panel writes ~/.config/matugen/shell-theme (TYPE= and
    // CONTRAST=, sourced by setwall) and re-runs setwall on the current
    // wallpaper.  matugen's quickshell post_hook calls `theme reload`,
    // which re-reads colors.json in place instead of restarting.
    readonly property var themeSchemes: [
        "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
        "scheme-fidelity", "scheme-content", "scheme-fruit-salad",
        "scheme-rainbow", "scheme-neutral", "scheme-monochrome",
        "scheme-smart"
    ]
    readonly property string themeScheme:
        themeSchemes.indexOf(cfg.themeScheme) >= 0 ? cfg.themeScheme : "scheme-tonal-spot"
    readonly property var themePrefers: [
        "saturation", "less-saturation", "darkness", "lightness", "value"
    ]
    readonly property string themePrefer:
        themePrefers.indexOf(cfg.themePrefer) >= 0 ? cfg.themePrefer : "saturation"
    readonly property real themeContrast:
        Math.max(-1, Math.min(1, Number(cfg.themeContrast) || 0))
    property bool themeBusy: false

    // a contrast drag settles before matugen runs; each run re-renders
    // every app's colours, so it should happen once, not per pixel
    Timer {
        id: themeDebounce
        interval: 400
        onTriggered: root.applyTheme()
    }

    property bool themePending: false
    function applyTheme() {
        themePending = true
        if (!themeProc.running) flushTheme()
    }
    function flushTheme() {
        if (!themePending) return
        themePending = false
        themeBusy = true
        themeProc.command = ["sh", "-c",
            'f="$HOME/.config/matugen/shell-theme"; ' +
            'printf "TYPE=%s\\nCONTRAST=%s\\nPREFER=%s\\nMODE=%s\\n" "$1" "$2" "$3" "$4" > "$f.tmp" && mv "$f.tmp" "$f"; ' +
            'img=$(cat "$HOME/.cache/wallpaper" 2>/dev/null); ' +
            '[ -f "$img" ] && "$HOME/.local/bin/setwall" "$img"; true',
            "sh", themeScheme, themeContrast.toFixed(2), themePrefer,
            isLight ? "light" : "dark"]
        themeProc.running = true
    }
    Process {
        id: themeProc
        onExited: {
            // re-read the palette even if the post_hook didn't
            palProc.running = true
            root.themeBusy = root.themePending
            root.flushTheme()
        }
    }

    // Hyprland reads ~/.config/hypr/shell-settings.lua, a plain
    // `return { ... }` table, near the top of hyprland.lua.  Only keys
    // the user has changed are written; hyprland.lua's own defaults
    // cover the rest.  It doesn't watch dofile()d files, so every
    // write is followed by `hyprctl reload`, debounced so a slider
    // drag reloads a few times rather than on every pixel.
    readonly property var hyprKeys: ({
        gapsIn: "gaps_in", gapsOut: "gaps_out", borderSize: "border_size",
        rounding: "rounding", winActive: "active_opacity",
        winInactive: "inactive_opacity", blurSize: "blur_size",
        blurPasses: "blur_passes", animations: "animations",
        animSpeed: "anim_speed", gameMode: "game_mode", wsAnim: "ws_anim",
        vrr: "vrr", directScanout: "direct_scanout",
        repeatRate: "repeat_rate", repeatDelay: "repeat_delay",
        sensitivity: "sensitivity", accelFlat: "accel_flat",
        naturalScroll: "natural_scroll", followMouse: "follow_mouse",
        monitors: "monitors",
        mainScreen: "main_output", secondScreen: "second_output",
        wsMain: "main_workspaces", wsSecond: "second_workspaces",
        appTerminalCmd: "terminal", appFilesCmd: "file_manager"
    })

    // plain values to Lua: booleans, finite numbers, simple strings and
    // tables of them (the monitors table); anything else is dropped
    function luaVal(v) {
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "number") return isFinite(v) ? String(v) : null
        if (typeof v === "string")
            return /^[\w .@:+\/=,-]*$/.test(v) ? JSON.stringify(v) : null
        if (Array.isArray(v)) {
            const nums = v.filter(x => Number.isInteger(x))
            return "{ " + nums.join(", ") + " }"
        }
        if (v && typeof v === "object" && !Array.isArray(v)) {
            const parts = []
            for (const k in v) {
                const inner = luaVal(v[k])
                if (inner !== null && /^[\w-]+$/.test(k))
                    parts.push("[" + JSON.stringify(k) + "] = " + inner)
            }
            return "{ " + parts.join(", ") + " }"
        }
        return null
    }

    function hyprText() {
        const lines = []
        for (const k in hyprKeys) {
            const v = cfgUser[k]
            if (v === undefined) continue
            const lv = luaVal(v)
            if (lv === null) continue
            lines.push("    " + hyprKeys[k] + " = " + lv + ",")
        }
        // automatic game mode, while a game runs (a later key wins in Lua)
        if (autoGame) lines.push("    game_mode = true,   -- a game is running")
        return "-- written by the quickshell settings panel; change values there\n"
             + "return {\n" + lines.join("\n") + (lines.length ? "\n" : "") + "}\n"
    }

    Timer {
        id: hyprDebounce
        interval: 150
        onTriggered: root.writeHypr()
    }

    property string pendingHypr: ""
    function writeHypr() {
        pendingHypr = hyprText()
        if (!hyprWrite.running) flushHypr()
    }
    function flushHypr() {
        if (pendingHypr === "") return
        hyprWrite.command = ["sh", "-c",
            'f="$HOME/.config/hypr/shell-settings.lua"; ' +
            'printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f" && hyprctl reload >/dev/null; true',
            "sh", pendingHypr]
        pendingHypr = ""
        hyprWrite.running = true
    }
    Process {
        id: hyprWrite
        onExited: root.flushHypr()
    }

    property string pendingKitty: ""
    function writeKitty() {
        pendingKitty = termOpacity.toFixed(2)
        if (!kittyWrite.running) flushKitty()
    }
    function flushKitty() {
        if (pendingKitty === "") return
        kittyWrite.command = ["sh", "-c",
            'f="$HOME/.config/kitty/shell-settings.conf"; ' +
            'printf "# written by the quickshell settings panel; change it there\\nbackground_opacity %s\\n" "$1" > "$f.tmp" ' +
            '&& mv "$f.tmp" "$f" && pkill -USR1 -x kitty; true',
            "sh", pendingKitty]
        pendingKitty = ""
        kittyWrite.running = true
    }
    Process {
        id: kittyWrite
        onExited: root.flushKitty()
    }

    // writes go through a temp file and a rename, one at a time, so a
    // slider being dragged never leaves a half-written file behind
    property string pendingSettings: ""
    function saveSettings() {
        pendingSettings = JSON.stringify(cfgUser, null, 2) + "\n"
        if (!settingsWrite.running) flushSettings()
    }
    function flushSettings() {
        if (pendingSettings === "") return
        settingsWrite.command = ["sh", "-c",
            'f="$HOME/.config/quickshell/settings.json"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
            "sh", pendingSettings]
        pendingSettings = ""
        settingsWrite.running = true
    }
    Process {
        id: settingsWrite
        onExited: root.flushSettings()
    }

    Process {
        id: settingsRead
        running: true
        command: ["sh", "-c",
            "cat ~/.config/quickshell/settings.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) { root.cfgUser = ({}); return }
                try {
                    const o = JSON.parse(t)
                    if (o && typeof o === "object" && !Array.isArray(o))
                        root.cfgUser = o
                } catch (e) {
                    console.log("settings.json parse failed, using defaults:", e)
                }
            }
        }
    }

    IpcHandler {
        target: "theme"
        function reload(): void { palProc.running = true }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.settingsShown = !root.settingsShown }
        function open(): void { root.settingsShown = true }
        function close(): void { root.settingsShown = false }
        function reload(): void { settingsRead.running = true }
        function sync(): void {
            root.writeHypr()
            root.writeKitty()
            lockDebounce.restart()
        }
    }

    Process { id: launchProc; environment: root.appEnv }
    Process { id: saveProc }

    Process {
        id: loadProc
        command: ["sh", "-c", "cat '" + root.notesPath + "' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.markedDays = t.length ? t.split(",").filter(s => s.length) : []
            }
        }
    }

    Process {
        id: wxProc
        command: ["sh", "-c",
            "curl -s --max-time 12 'https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root.wxLat + "&longitude=" + root.wxLon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
            + "wind_speed_10m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day&forecast_hours=13"
            + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
            + (root.wxMetric ? "&temperature_unit=celsius&wind_speed_unit=kmh'"
                             : "&temperature_unit=fahrenheit&wind_speed_unit=mph'")]
        stdout: StdioCollector {
            readonly property var codes: ({
                0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
                45: "Fog", 48: "Rime fog", 51: "Light drizzle", 53: "Drizzle",
                55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
                61: "Light rain", 63: "Rain", 65: "Heavy rain",
                66: "Freezing rain", 67: "Freezing rain", 71: "Light snow",
                73: "Snow", 75: "Heavy snow", 77: "Snow grains", 80: "Light showers",
                81: "Showers", 82: "Heavy showers", 85: "Snow showers",
                86: "Snow showers", 95: "Thunderstorm", 96: "Thunderstorm",
                99: "Thunderstorm"
            })
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    const c = j.current
                    const u = root.wxMetric ? "\u00b0C" : "\u00b0F"
                    root.wxDay = c.is_day !== 0
                    // the hours ahead, starting with the one we're in
                    const h = j.hourly || {}
                    const hours = []
                    for (let i = 0; i < (h.time || []).length && hours.length < 12; i++) {
                        const hr = parseInt(h.time[i].slice(11, 13))
                        const label = i === 0 ? "Now"
                            : root.cfg.clock24h === true ? (hr < 10 ? "0" : "") + hr
                            : ((hr % 12) || 12) + (hr < 12 ? " AM" : " PM")
                        hours.push({ time: label, temp: Math.round(h.temperature_2m[i]) + "\u00b0",
                                     cond: codes[h.weather_code[i]] || "", day: h.is_day[i] !== 0,
                                     rain: h.precipitation_probability ? (h.precipitation_probability[i] || 0) : 0 })
                    }
                    root.wxHours = hours
                    const d = j.daily || {}
                    root.wxHi = d.temperature_2m_max ? Math.round(d.temperature_2m_max[0]) + "\u00b0" : ""
                    root.wxLo = d.temperature_2m_min ? Math.round(d.temperature_2m_min[0]) + "\u00b0" : ""
                    root.wxTemp = Math.round(c.temperature_2m) + u
                    root.wxFeel = Math.round(c.apparent_temperature) + u
                    root.wxHum  = c.relative_humidity_2m + "%"
                    root.wxWind = Math.round(c.wind_speed_10m) + (root.wxMetric ? " km/h" : " mph")
                    root.wxCond = codes[c.weather_code] || "Unknown"
                    root.wxOk = true
                } catch (e) {
                    root.wxOk = false
                }
            }
        }
    }

    onPowerShownChanged: if (powerShown) upProc.running = true
    Process {
        id: upProc
        command: ["uptime", "-p"]
        stdout: StdioCollector { onStreamFinished: root.uptimeText = text.trim() }
    }

    // real notification daemon — owns org.freedesktop.Notifications
    NotificationServer {
        id: notifServer

        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: true

        onNotification: notif => {
            notif.tracked = true

            const crit = (notif.urgency === NotificationUrgency.Critical) ? 2 : 1
            // actions are copied out as plain values; the live objects stay
            // behind in notifRefs and are looked up by id when clicked
            const acts = []
            for (const a of (notif.actions || []))
                acts.push({ key: String(a.identifier), text: String(a.text || "") })
            const n = {
                id: ++root.notifSeq,
                app: notif.appName || "notification",
                icon: notif.appIcon || "",
                desktop: notif.desktopEntry || "",
                summary: notif.summary || "",
                body: notif.body || "",
                urgency: crit,
                image: notif.image || "",
                actions: acts,
                // apps that accept a typed reply (KDE Connect, some chat
                // clients); Discord doesn't offer one
                replyable: notif.hasInlineReply === true,
                replyHint: notif.inlineReplyPlaceholder || "",
                ts: Date.now(),
                when: Qt.formatDateTime(new Date(), root.cfg.clock24h === true ? "HH:mm" : "h:mm AP")
            }

            const id = n.id
            const refs = root.notifRefs
            refs[id] = notif
            root.notifRefs = refs

            // when the server drops it, forget the object immediately so
            // nothing can reach a destroyed pointer through notifRefs
            notif.closed.connect(() => {
                const r = root.notifRefs
                delete r[id]
                root.notifRefs = r
            })

            root.notifList = [n].concat(root.notifList).slice(0, 100)
            if (!root.quickShown && !root.sidebarShown) root.notifUnseen++
            if (!root.quietNow) {
                // the island shows it; ones with buttons or a reply box still
                // get their pop-up too, since the island has no room for those
                const needsPopup = !root.islandNotifs || n.replyable
                    || (n.actions || []).some(a => a.key !== "default")
                if (needsPopup) root.popups = root.popups.concat([n]).slice(-4)
                if (root.islandNotifs)
                    root.showIsland({ kind: "notif", id: n.id, app: n.app, summary: n.summary, body: n.body,
                                      icon: root.notifIcon(n), urgent: n.urgency >= 2,
                                      canOpen: (n.actions || []).some(a => a.key === "default") },
                                    n.urgency >= 2 ? 8000 : 4500)
            }
        }
    }

}

