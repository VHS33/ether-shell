import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// ============================================================
//   GAME WATCH
//   Notices games starting and stopping, and keeps the playtime history.
//
//   A window is a game when:
//     - its process has SteamAppId / SteamGameId set (Steam sets it for
//       every game it launches, native or Proton); the id gives the name
//       from Steam's own files;
//     - its class is steam_app_<id> (Proton) or gamescope; or
//     - its class is in cfg.gameClasses (marked from the playtime card).
//
//   While any game runs, app.gameRunning is true, and shell.qml applies
//   automatic game mode from that (never touching the user's own Game
//   mode or Do not disturb).  When a game's last window closes (after a
//   short grace, as launchers hand over to the game), the session ends:
//   it's added to ~/.local/state/ether/playtime.json and, when it lasted
//   a minute or more, shown in the island.
//
//   Sessions are plain values (rule: no live objects in JS state).
// ============================================================
Scope {
    id: gw
    property var app

    // ---- the games running now ----
    // { key: { key, name, appId, cls, start (ms), windows: [address, ...] } }
    property var sessions: ({})
    readonly property bool running: Object.keys(sessions).length > 0
    onRunningChanged: app.gameRunning = running

    // ---- the history ----
    // { games: { key: { name, appId, cls, total (s), sessions: [[startMs, secs], ...] } } }
    property var playtime: ({ games: {} })
    readonly property string file: Quickshell.env("HOME") + "/.local/state/ether/playtime.json"

    // Steam names, looked up once per id
    property var steamNames: ({})

    Process {
        id: loadPlay
        running: true
        command: ["sh", "-c", "cat \"$HOME/.local/state/ether/playtime.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d && typeof d.games === "object") gw.playtime = d
                } catch (e) {}
            }
        }
    }
    function savePlay() {
        savePlayProc.command = ["sh", "-c",
            'd="$HOME/.local/state/ether"; mkdir -p "$d"; ' +
            'printf "%s" "$1" > "$d/playtime.json.tmp" && mv "$d/playtime.json.tmp" "$d/playtime.json"',
            "sh", JSON.stringify(gw.playtime)]
        savePlayProc.running = true
    }
    Process { id: savePlayProc }

    // ---- telling games apart ----
    function classGameKey(cls) {
        const m = /^steam_app_(\d+)$/.exec(cls || "")
        if (m && m[1] !== "0") return { key: "steam:" + m[1], appId: m[1] }
        if ((cls || "").toLowerCase() === "gamescope") return { key: "class:gamescope", appId: "" }
        const marked = Array.isArray(app.cfg.gameClasses) ? app.cfg.gameClasses : []
        if (marked.indexOf(cls) !== -1) return { key: "class:" + cls, appId: "" }
        return null
    }

    // Windows are checked one at a time: find the process, then look for
    // Steam's id in its environment.
    property var queue: []           // [{ addr, cls, title }]
    property var pending: null
    function enqueue(addr, cls, title) {
        if (!addr) return
        const direct = classGameKey(cls)
        if (direct) { addWindow(direct, addr, cls, title); return }
        queue = queue.concat([{ addr: addr, cls: cls, title: title }])
        if (!pending) next()
    }
    function next() {
        if (!queue.length) { pending = null; return }
        pending = queue[0]
        queue = queue.slice(1)
        // the window's process id, from Hyprland's window list
        Hyprland.refreshToplevels()
        pidLater.restart()
    }
    Timer {
        id: pidLater
        interval: 350
        onTriggered: {
            const p = gw.pending
            if (!p) return
            let pid = 0
            for (const t of Hyprland.toplevels.values) {
                const ipc = t.lastIpcObject
                if (ipc && (ipc.address || "").replace(/^0x/, "") === p.addr) { pid = ipc.pid || 0; break }
            }
            if (!pid) { gw.next(); return }
            envCheck.command = ["sh", "-c",
                'tr "\\0" "\\n" < "/proc/$1/environ" 2>/dev/null | grep -m1 -E "^(SteamAppId|SteamGameId)=[1-9][0-9]*$" | cut -d= -f2',
                "sh", String(pid)]
            envCheck.running = true
        }
    }
    Process {
        id: envCheck
        stdout: StdioCollector {
            onStreamFinished: {
                const p = gw.pending
                const id = text.trim()
                if (p && /^[0-9]+$/.test(id)) gw.addWindow({ key: "steam:" + id, appId: id }, p.addr, p.cls, p.title)
                gw.next()
            }
        }
    }

    // ---- sessions ----
    function addWindow(k, addr, cls, title) {
        const s = Object.assign({}, sessions)
        const ex = s[k.key]
        if (ex) {
            if (ex.windows.indexOf(addr) === -1) s[k.key] = Object.assign({}, ex, { windows: ex.windows.concat([addr]) })
        } else {
            s[k.key] = { key: k.key, appId: k.appId, cls: cls,
                         name: k.appId ? (steamNames[k.appId] || title || cls) : (title || cls),
                         start: Date.now(), windows: [addr] }
            if (k.appId && !steamNames[k.appId]) lookupName(k.appId)
        }
        endLater.cancel(k.key)
        sessions = s
    }
    function removeWindow(addr) {
        for (const key in sessions) {
            const ses = sessions[key]
            const i = ses.windows.indexOf(addr)
            if (i === -1) continue
            const s = Object.assign({}, sessions)
            s[key] = Object.assign({}, ses, { windows: ses.windows.filter(a => a !== addr) })
            sessions = s
            // no windows left: end it shortly, unless a new one turns up
            // (launchers and splash screens hand over to the game)
            if (!s[key].windows.length) endLater.schedule(key)
        }
    }
    QtObject {
        id: endLater
        property var due: ({})           // key -> ms
        function schedule(key) { const d = Object.assign({}, due); d[key] = Date.now() + 4000; due = d; endTick.start() }
        function cancel(key) { if (due[key] !== undefined) { const d = Object.assign({}, due); delete d[key]; due = d } }
    }
    Timer {
        id: endTick
        interval: 1000
        repeat: true
        onTriggered: {
            const now = Date.now()
            let left = 0
            for (const key in endLater.due) {
                if (endLater.due[key] <= now) { endLater.cancel(key); gw.endSession(key) }
                else left++
            }
            if (!left) stop()
        }
    }
    function endSession(key) {
        const ses = sessions[key]
        if (!ses || ses.windows.length) return
        const s = Object.assign({}, sessions)
        delete s[key]
        sessions = s
        const secs = Math.round((Date.now() - ses.start) / 1000)
        if (secs < 30) return                   // a launcher or a crash on start
        // into the history
        const games = Object.assign({}, playtime.games)
        const g = Object.assign({ name: ses.name, appId: ses.appId, cls: ses.cls, total: 0, sessions: [] }, games[key] || {})
        g.name = ses.name || g.name
        g.total = (g.total || 0) + secs
        g.sessions = (g.sessions || []).concat([[ses.start, secs]]).slice(-200)
        games[key] = g
        playtime = { games: games }
        savePlay()
        // and the island, for anything a minute or longer
        if (secs >= 60)
            app.showIsland({ kind: "game", name: g.name, appId: ses.appId || "", cls: ses.cls || "",
                             secs: secs, week: weekSecs(key) }, 8000)
    }

    // this week's play for one game, in seconds
    function weekSecs(key) {
        const g = playtime.games[key]
        if (!g) return 0
        const since = Date.now() - 7 * 24 * 3600 * 1000
        let t = 0
        for (const s of g.sessions || []) if (s[0] >= since) t += s[1]
        return t
    }
    // the playtime card: this week's games, most played first
    readonly property var weekList: {
        const since = Date.now() - 7 * 24 * 3600 * 1000
        const out = []
        for (const key in playtime.games) {
            const g = playtime.games[key]
            let t = 0
            for (const s of g.sessions || []) if (s[0] >= since) t += s[1]
            if (t > 0) out.push({ key: key, name: g.name, appId: g.appId || "", cls: g.cls || "", week: t, total: g.total || 0 })
        }
        out.sort((a, b) => b.week - a.week)
        return out
    }
    onWeekListChanged: app.playWeek = weekList

    // ---- Steam's name for an id, from its own files ----
    function lookupName(id) {
        nameProc.queue.push(id)
        if (!nameProc.running) nameProc.nextName()
    }
    Process {
        id: nameProc
        property var queue: []
        property string current: ""
        function nextName() {
            if (!queue.length) return
            current = queue.shift()
            command = ["sh", "-c",
                's="$HOME/.local/share/Steam"; [ -d "$s" ] || s="$HOME/.steam/steam"; ' +
                'libs="$s $(grep -oE "\\"path\\"[[:space:]]+\\"[^\\"]+\\"" "$s/steamapps/libraryfolders.vdf" 2>/dev/null | cut -d\\" -f4)"; ' +
                'for d in $libs; do f="$d/steamapps/appmanifest_$1.acf"; ' +
                '[ -f "$f" ] && { grep -m1 -E "^[[:space:]]*\\"name\\"" "$f" | cut -d\\" -f4; exit 0; }; done',
                "sh", current]
            running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim()
                const id = nameProc.current
                if (name && id) {
                    const n = Object.assign({}, gw.steamNames); n[id] = name; gw.steamNames = n
                    // rename a running session that started with the window title
                    for (const key in gw.sessions) {
                        if (gw.sessions[key].appId === id) {
                            const s = Object.assign({}, gw.sessions)
                            s[key] = Object.assign({}, s[key], { name: name })
                            gw.sessions = s
                        }
                    }
                }
                nameProc.nextName()
            }
        }
    }

    // ---- Hyprland's window events ----
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                // ADDRESS,WORKSPACE,CLASS,TITLE (the title may itself hold commas)
                const parts = event.data.split(",")
                gw.enqueue(parts[0], parts[2] || "", parts.slice(3).join(","))
            } else if (event.name === "closewindow") {
                gw.removeWindow(event.data.trim())
            }
        }
    }

    // games already running when the shell starts (a restart mid-game)
    Timer {
        running: true
        interval: 1500
        onTriggered: {
            for (const t of Hyprland.toplevels.values) {
                const ipc = t.lastIpcObject
                if (ipc && ipc.address)
                    gw.enqueue(ipc.address.replace(/^0x/, ""), ipc.class || "", ipc.title || "")
            }
        }
    }
    Component.onCompleted: Hyprland.refreshToplevels()

    // ---- marking the focused window as a game (from the playtime card) ----
    function markFocused() {
        const t = Hyprland.activeToplevel
        const cls = t?.lastIpcObject?.class || t?.wayland?.appId || ""
        if (!cls) return
        const list = (Array.isArray(app.cfg.gameClasses) ? app.cfg.gameClasses : []).filter(c => c !== cls)
        app.setting("gameClasses", list.concat([cls]))
        const addr = (t?.lastIpcObject?.address || "").replace(/^0x/, "")
        if (addr) addWindow({ key: "class:" + cls, appId: "" }, addr, cls, t?.lastIpcObject?.title || cls)
    }
}
