// Your windows in the launcher (modules/launcher/Launcher.qml): matching
// them to what's typed, how each one is shown, and reading plain-word
// commands ("ws 3", "move 4", "close discord").  Pure: plain values in,
// plain values out, so it's tested on its own (tests/windows.test.mjs).
//
// A window here is { addr, cls, name, title, ws, wsName, mon, icon, entry,
// focused }: from Hyprland's list, with its app's name and icon.

const words = s => s.split(/[\s\-_.]/)

// how well a window matches what's typed (0: not at all)
export function score(w, t) {
    t = (t || "").trim().toLowerCase()
    if (t === "") return 1
    const name = (w.name || "").toLowerCase()
    const cls = (w.cls || "").toLowerCase()
    const title = (w.title || "").toLowerCase()
    if (name.startsWith(t) || cls.startsWith(t)) return 100
    if (words(name).some(x => x.startsWith(t))) return 75
    if (title.indexOf(t) !== -1) return 60
    if (name.indexOf(t) !== -1 || cls.indexOf(t) !== -1) return 50
    return 0
}

// the best matches, best first: the window you're on after the others (you
// usually want to go somewhere else), then by workspace
export function match(list, t, max) {
    const scored = []
    for (const w of list || []) {
        const s = score(w, t)
        if (s > 0) scored.push({ s: s + (w.focused ? 0 : 1), w })
    }
    scored.sort((a, b) => b.s - a.s || (a.w.ws || 0) - (b.w.ws || 0))
    return scored.slice(0, max === undefined ? 40 : max).map(x => x.w)
}

// "Workspace 2", or a special (hidden) one by its name
export function wsLabel(w) {
    if ((w.ws || 0) < 0) {
        const n = (w.wsName || "").replace(/^special:?/, "")
        return "Hidden workspace" + (n ? " (" + n + ")" : "")
    }
    return "Workspace " + w.ws
}

// a window's title without its app's name tacked on the end, as most apps
// do ("YouTube — Mozilla Firefox" next to "Firefox" is just "YouTube")
export function bareTitle(title, name) {
    let t = (title || "").trim()
    const n = (name || "").trim().toLowerCase()
    if (!t || !n) return t
    const m = t.match(/^(.*\S)\s+[—–\-|·]\s+([^—–|·]+)$/)
    if (m && m[2].toLowerCase().indexOf(n) !== -1) t = m[1]
    return t
}

// a launcher row for a window
export function row(w, kind) {
    kind = kind || "win"
    const name = w.name || w.cls || "Window"
    const bare = bareTitle(w.title, name)
    const title = bare && bare.toLowerCase() !== name.toLowerCase() ? "  —  " + bare : ""
    return {
        kind, addr: w.addr, icon: w.icon || "", entry: w.entry || "", glyph: "web_asset", ws: w.ws,
        title: (kind === "winclose" ? "Close " : "") + name + title,
        sub: wsLabel(w) + (w.mon ? "  •  " + w.mon : "") + (w.focused ? "  •  the window you're on" : ""),
        badge: (w.ws || 0) > 0 ? "WS " + w.ws : "",
    }
}

// what's on a workspace, in a few words: "kitty, Firefox and 2 more"
export function summary(list, id, mon) {
    const names = (list || []).filter(w => w.ws === id).map(w => w.name || w.cls || "Window")
    const what = names.length
        ? names.slice(0, 3).join(", ") + (names.length > 3 ? " and " + (names.length - 3) + " more" : "")
        : "Empty"
    return what + (mon ? "  •  " + mon : "")
}

// plain words: { type: "go" | "move" | "close" | "focus", ws?, what? } or null
//   ws 3, workspace 3, go to workspace 3, go 3      go to workspace 3
//   move 4, move to 4, move to workspace 4          the window you're on
//   close discord                                    close it
//   focus firefox, switch to firefox                 go to it
export function command(raw) {
    const s = (raw || "").trim().toLowerCase().replace(/\s+/g, " ")
    let m = s.match(/^(?:ws|workspace|go to workspace|go to ws|go)\s?(\d{1,2})$/)
    if (m && +m[1] >= 1) return { type: "go", ws: +m[1] }
    m = s.match(/^move (?:to )?(?:ws ?|workspace )?(\d{1,2})$/)
    if (m && +m[1] >= 1) return { type: "move", ws: +m[1] }
    m = s.match(/^close (.+)$/)
    if (m) return { type: "close", what: m[1].trim() }
    m = s.match(/^(?:focus|switch to|go to) (.+)$/)
    if (m) return { type: "focus", what: m[1].trim() }
    return null
}
