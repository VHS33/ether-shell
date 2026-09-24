import QtQuick
import QtQuick.Layouts
import Quickshell
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
    readonly property color cBg:     withAlpha(pal.bg ?? "#1e1e2e", hexA(bgA))
    readonly property color cCard:   withAlpha(pal.card ?? "#1e1e2e", hexA(bgA))
    readonly property color cSurf:   pal.surf   ?? "#313244"
    readonly property color cTile:   withAlpha(pal.tile, "33") ?? "#33313244"
    readonly property color cBorder: pal.border ?? "#414356"
    readonly property color cFg:     pal.fg     ?? "#cdd6f4"
    readonly property color cDim:    pal.dim    ?? "#a6adc8"
    readonly property color cFaint:  pal.faint  ?? "#6c7086"
    readonly property color cBlue:   pal.blue   ?? "#89b4fa"
    readonly property color cGreen:  pal.green  ?? "#a6e3a1"
    readonly property color cPeach:  pal.peach  ?? "#fab387"
    // light mode swaps the three pastel "fixed" accents for darker
    // companions, which would otherwise wash out on a light background
    readonly property bool isLight: cfg.themeMode === "light"
    readonly property color cMauve:  (isLight ? pal.mauveL : pal.mauve) ?? "#cba6f7"
    readonly property color cTeal:   (isLight ? pal.tealL : pal.teal)   ?? "#94e2d5"
    readonly property color cRed:    pal.red    ?? "#f38ba8"
    readonly property color cYellow: (isLight ? pal.yellowL : pal.yellow) ?? "#f9e2af"
    // text and icons drawn on top of an accent colour
    readonly property color cOnAccent: pal.onAccent ?? "#1e1e2e"
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
    readonly property int zoneH: 46
    readonly property int gap:   8

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

    function workspacesFor(screenName) {
        const live = {}
        for (const w of Hyprland.workspaces.values) {
            if (w.id > 0) live[w.id] = w
        }
        const out = []
        for (const id of root.mainWorkspaces) {
            const w = live[id]
            // a workspace with windows; the focused one exists even empty
            const wins = w ? (w.toplevels?.values?.length ?? 1) : 0
            out.push({ id: id, occupied: wins > 0 })
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
    function launchApp(id) {
        const e = DesktopEntries.byId(id)
        if (e) e.execute()
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
    onSidebarShownChanged: if (sidebarShown) sideRefresh.restart()
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
            }
        }
    }

    Process { id: clipAct }

    function clipCopy(id) {
        clipAct.command = ["sh", "-c",
            "cliphist decode " + id + " | wl-copy"]
        clipAct.running = true
        root.sidebarShown = false
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

                const out = []
                for (const b of raw) {
                    const key = b.key ?? ""
                    if (!key.length) continue

                    const parts = root.modString(b.modmask ?? 0)
                    parts.push(key.length === 1 ? key.toUpperCase() : key)

                    // a description if the bind has one, else something
                    // readable from the dispatcher
                    let label = b.description ?? ""
                    if (!label.length) {
                        const d = b.dispatcher ?? ""
                        label = d === "__lua" ? "(lua)" : d
                    }

                    out.push({ keys: parts.join(" + "), label: label })
                }
                root.cheatBinds = out
            }
        }
    }

    property bool osdShown: false
    property real osdValue: 0
    property bool osdMuted: false
    property bool osdReady: false

    function showOsd(vol, muted) {
        root.osdValue = vol
        root.osdMuted = muted
        if (!root.osdReady) {
            root.osdReady = true
            return
        }
        root.osdShown = true
        osdTimer.restart()
    }

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

    property string wxCond: ""
    property string wxTemp: ""
    property string wxFeel: ""
    property string wxHum: ""
    property string wxWind: ""
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

    readonly property var player: {
        const list = Mpris.players.values
        if (!list || list.length === 0) return null
        for (const p of list) {
            if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return list[0]
    }

    onPlayerChanged: if (!player) cardShown = false
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

    function wxGlyph(c) {
        const s = (c || "").toLowerCase()
        if (s.indexOf("thunder") !== -1) return "\u{f0e6}"
        if (s.indexOf("snow") !== -1 || s.indexOf("rime") !== -1) return "\u{f0f36}"
        if (s.indexOf("rain") !== -1 || s.indexOf("drizzle") !== -1 || s.indexOf("shower") !== -1) return "\u{f0f33}"
        if (s.indexOf("fog") !== -1) return "\u{f0591}"
        if (s.indexOf("cloud") !== -1 || s.indexOf("overcast") !== -1) return "\u{f0590}"
        if (s.indexOf("clear") !== -1) return "\u{f0599}"
        return "\u{f050f}"
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
        // the clipboard is a section of the sidebar now, so opening it
        // means opening the sidebar with that section unfolded
        function toggle(): void {
            if (root.sidebarShown && root.sideTab === 1) {
                root.sidebarShown = false
            } else {
                root.sideTab = 1
                root.sidebarShown = true
            }
        }
        function open(): void { root.sideTab = 1; root.sidebarShown = true }
        function close(): void { root.sidebarShown = false }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.overviewShown = !root.overviewShown }
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
    Widgets { app: root }
    Popups { app: root }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    // `clock` was an id, which the split modules cannot see; expose the
    // time as a root property instead so they can bind to app.now
    property date now: new Date()

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    Timer {
        interval: 500
        running: (root.cardShown || root.sidebarShown) && root.player !== null
        repeat: true; triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { cpuProc.running = true; memProc.running = true; netProc.running = true; gpuProc.running = true }
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

    function applyWallpaper(path) {
        if (!path || wallApply.running) return
        root.currentWall = path
        wallApply.command = [Quickshell.env("HOME") + "/.local/bin/setwall", path]
        wallApply.running = true
    }
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
        running: root.cardShown
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
    }
    Component.onCompleted: if (nightLight) applyNight()

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
        animSpeed: "anim_speed",
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

    Process {
        id: gpuProc
        command: ["sh", "-c",
            "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) { root.gpuOk = false; return }
                const p = t.split(",").map(s => parseFloat(s.trim()))
                if (p.length < 5 || isNaN(p[0])) { root.gpuOk = false; return }
                root.gpuPct    = Math.round(p[0])
                root.gpuTemp   = Math.round(p[1])
                root.gpuMemPct = p[3] > 0 ? Math.round(100 * p[2] / p[3]) : 0
                root.gpuWatts  = Math.round(p[4])
                root.gpuOk = true
            }
        }
    }

    Process {
        id: netProc
        command: ["sh", "-c",
            "cat /proc/net/dev | awk 'NR>2 {gsub(/:/,\"\"); if ($1 != \"lo\") {rx+=$2; tx+=$10}} END {print rx, tx}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/).map(Number)
                if (p.length < 2 || isNaN(p[0])) return
                const now = Date.now()
                if (root.lastNet) {
                    const dt = (now - root.lastNet.t) / 1000
                    if (dt > 0) {
                        root.netDown = root.fmtRate(Math.max(0, (p[0] - root.lastNet.rx) / dt))
                        root.netUp   = root.fmtRate(Math.max(0, (p[1] - root.lastNet.tx) / dt))
                    }
                }
                root.lastNet = { rx: p[0], tx: p[1], t: now }
            }
        }
    }
    Process { id: launchProc }
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
            + "wind_speed_10m,weather_code"
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
                    const c = JSON.parse(text).current
                    const u = root.wxMetric ? "\u00b0C" : "\u00b0F"
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

            root.notifList = [n].concat(root.notifList).slice(0, 50)
            if (!root.dnd) root.popups = root.popups.concat([n]).slice(-4)
        }
    }

    Process {
        id: cpuProc
        command: ["sh", "-c", "grep -m1 '^cpu ' /proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/).slice(1).map(Number)
                const total = f.reduce((a, b) => a + b, 0)
                const idle = f[3] + (f[4] || 0)
                if (root.lastCpu) {
                    const dt = total - root.lastCpu.total
                    const di = idle - root.lastCpu.idle
                    if (dt > 0) root.cpuPct = Math.round(100 * (dt - di) / dt)
                }
                root.lastCpu = { total: total, idle: idle }
            }
        }
    }

    Process {
        id: memProc
        command: ["sh", "-c", "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\", (t-a)*100/t}' /proc/meminfo"]
        stdout: StdioCollector { onStreamFinished: root.memPct = parseInt(text.trim()) || 0 }
    }
}

