import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// ============================================================
//   SCENES
//   A scene is a saved desktop: every window's app and workspace, and the
//   workspace each monitor was showing.  Restoring one:
//     - apps already open are moved to their saved workspaces;
//     - apps that aren't running are started, and each new window is sent
//       to its workspace as it appears;
//     - several windows of one app are matched up in order, starting more
//       copies when the scene has more;
//     - each monitor goes back to the workspace it was showing.
//   Nothing is ever closed: windows not in the scene are left alone.
//
//   Launcher: @ lists scenes; @name + Enter restores it (or saves the
//   desktop as it, when there's no such scene); Ctrl+Enter saves over one;
//   Delete removes one.  IPC: qs ipc call scene save|restore|delete <name>.
//   Stored in ~/.local/state/ether/scenes.json, as plain values.
// ============================================================
Scope {
    id: sc
    property var app

    // { name: { saved: ms, windows: [{ cls, title, ws, entry }], shown: [ws, ...] } }
    property var scenes: ({})
    readonly property var list: Object.keys(scenes).sort((a, b) => scenes[b].saved - scenes[a].saved)
        .map(n => ({ name: n, count: scenes[n].windows.length, saved: scenes[n].saved }))
    onListChanged: app.sceneList = list

    Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.local/state/ether/scenes.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d && typeof d.scenes === "object") sc.scenes = d.scenes
                } catch (e) {}
            }
        }
    }
    function store() {
        storeProc.command = ["sh", "-c",
            'd="$HOME/.local/state/ether"; mkdir -p "$d"; ' +
            'printf "%s" "$1" > "$d/scenes.json.tmp" && mv "$d/scenes.json.tmp" "$d/scenes.json"',
            "sh", JSON.stringify({ scenes: sc.scenes })]
        storeProc.running = true
    }
    Process { id: storeProc }

    // ---- which app a window belongs to, to start it again later ----
    function entryFor(cls) {
        if (!cls) return ""
        let e = null
        try { if (typeof DesktopEntries.heuristicLookup === "function") e = DesktopEntries.heuristicLookup(cls) } catch (err) {}
        if (!e) e = DesktopEntries.byId(cls) || DesktopEntries.byId(cls.toLowerCase())
        return e ? e.id : ""
    }

    // ---- the plan: pure, so it can be tested on its own ----
    // saved:   [{ cls, ws, entry }]          (the scene)
    // current: [{ addr, cls, ws }]           (windows open now)
    // gives    { moves: [{ addr, ws }], launches: [{ entry, cls, ws }] }
    // Windows of one app are matched in order, preferring ones already on
    // the right workspace so as little as possible moves.
    function plan(saved, current) {
        const moves = [], launches = []
        const byCls = {}
        for (const w of current) (byCls[w.cls] = byCls[w.cls] || []).push(w)
        const want = {}
        for (const w of saved) (want[w.cls] = want[w.cls] || []).push(w)
        for (const cls in want) {
            const avail = (byCls[cls] || []).slice()
            const left = []
            // first, windows already where they belong
            for (const w of want[cls]) {
                const i = avail.findIndex(a => a.ws === w.ws)
                if (i !== -1) avail.splice(i, 1)
                else left.push(w)
            }
            // then move others of that app, and start more for the rest
            for (const w of left) {
                const a = avail.shift()
                if (a) moves.push({ addr: a.addr, ws: w.ws })
                else if (w.entry) launches.push({ entry: w.entry, cls: cls, ws: w.ws })
            }
        }
        return { moves: moves, launches: launches }
    }

    // ---- saving ----
    property string savingAs: ""
    function save(name) {
        name = (name || "").trim()
        if (!name) return
        savingAs = name
        Hyprland.refreshToplevels()
        saveLater.restart()
    }
    Timer {
        id: saveLater
        interval: 400
        onTriggered: {
            const wins = []
            for (const t of Hyprland.toplevels.values) {
                const ipc = t.lastIpcObject
                if (!ipc || !ipc.class) continue
                const ws = ipc.workspace ? ipc.workspace.id : 0
                if (ws <= 0) continue                    // special and hidden workspaces aren't kept
                wins.push({ cls: ipc.class, title: ipc.title || "", ws: ws, entry: sc.entryFor(ipc.class) })
            }
            const shown = []
            for (const m of Hyprland.monitors.values)
                if (m.activeWorkspace && m.activeWorkspace.id > 0) shown.push(m.activeWorkspace.id)
            const s = Object.assign({}, sc.scenes)
            s[sc.savingAs] = { saved: Date.now(), windows: wins, shown: shown }
            sc.scenes = s
            sc.store()
            app.showIsland({ kind: "scene", name: sc.savingAs, verb: "Saved",
                             detail: wins.length === 1 ? "1 window" : wins.length + " windows" }, 3500)
        }
    }

    function remove(name) {
        if (!scenes[name]) return
        const s = Object.assign({}, scenes)
        delete s[name]
        scenes = s
        store()
    }

    // ---- restoring ----
    property var pending: []          // [{ cls, ws, until }]: new windows still to place
    property var restoreShown: []
    function restore(name) {
        const scene = scenes[name]
        if (!scene) return
        restoring = { name: name, scene: scene }
        Hyprland.refreshToplevels()
        restoreLater.restart()
    }
    property var restoring: null
    Timer {
        id: restoreLater
        interval: 400
        onTriggered: {
            const r = sc.restoring
            if (!r) return
            const current = []
            for (const t of Hyprland.toplevels.values) {
                const ipc = t.lastIpcObject
                if (!ipc || !ipc.class || !ipc.address) continue
                current.push({ addr: ipc.address.replace(/^0x/, ""), cls: ipc.class,
                               ws: ipc.workspace ? ipc.workspace.id : 0 })
            }
            const p = sc.plan(r.scene.windows, current)
            for (const m of p.moves) sc.moveWindow(m.addr, m.ws)
            const until = Date.now() + 30000
            sc.pending = p.launches.map(l => ({ cls: l.cls, ws: l.ws, until: until }))
            for (const l of p.launches) {
                const e = DesktopEntries.byId(l.entry)
                if (e) app.launchEntry(e)
            }
            sc.restoreShown = r.scene.shown || []
            // show each monitor's workspace now, and again once new windows have landed
            sc.showSaved()
            if (p.launches.length) settle.restart()
            app.showIsland({ kind: "scene", name: r.name, verb: "Restored",
                             detail: [p.moves.length ? (p.moves.length === 1 ? "1 window moved" : p.moves.length + " windows moved") : "",
                                      p.launches.length ? (p.launches.length === 1 ? "1 app started" : p.launches.length + " apps started") : ""]
                                     .filter(x => x).join("  \u2022  ") || "Already in place" }, 3500)
            sc.restoring = null
        }
    }
    function moveWindow(addr, ws) {
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + addr + "\" })")
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " + ws + ", follow = false })")
    }
    function showSaved() {
        for (const ws of restoreShown) Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws + " })")
    }
    Timer {
        id: settle
        interval: 6000
        onTriggered: sc.showSaved()
    }

    // a new window from a restore goes to its workspace
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" || !sc.pending.length) return
            const parts = event.data.split(",")
            const addr = parts[0], cls = parts[2] || ""
            const now = Date.now()
            const live = sc.pending.filter(p => p.until > now)
            const i = live.findIndex(p => p.cls === cls)
            if (i !== -1) {
                sc.moveWindow(addr, live[i].ws)
                live.splice(i, 1)
            }
            sc.pending = live
        }
    }

    // ---- scripts and keybinds ----
    IpcHandler {
        target: "scene"
        function save(name: string): void { sc.save(name) }
        function restore(name: string): void { sc.restore(name) }
        function remove(name: string): void { sc.remove(name) }
        function list(): string { return sc.list.map(s => s.name).join("\n") }
    }
}
