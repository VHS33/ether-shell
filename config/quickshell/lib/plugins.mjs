// plugins.mjs  (Ether Shell)
// Reading plugins: each is a folder in ~/.config/ether-shell/plugins with a
// plugin.json.  This checks each one strictly (they come from other people)
// and says, in plain words, why one can't be used.  The shell imports this;
// the tests run it with Node.

// The toolkit's version (PluginApi.qml).  A plugin written for a newer one
// is refused, with a note to update Ether Shell, rather than half-working.
export const API_VERSION = 1

const ID = /^[a-z0-9][a-z0-9-]{0,39}$/
// a plain file name inside the plugin's own folder: no paths, no "..", no
// hidden files
const FILE = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\.(qml|mjs)$/
// a launcher prefix: short, and not one of the launcher's own (= : ; > @ /)
const PREFIX = /^[!#$%&*+?~,a-z0-9][!#$%&*+?~,a-z0-9]{0,5}$/

function text(v, max) { return typeof v === "string" ? v.trim().slice(0, max) : "" }

// One plugin.json (its text) from the folder `folder` in `dir`.
// -> { id, name, description, version, author, api, dir, bar, ok, errors }
export function readManifest(folder, json, dir) {
    const p = { id: folder, name: folder, description: "", version: "", author: "", api: 0,
                dir: dir + "/" + folder, bar: null, launcher: null, widget: null, settings: null, ok: false, errors: [] }
    let m
    try { m = JSON.parse(json) } catch (e) { p.errors.push("its plugin.json isn't valid JSON"); return p }
    if (!m || typeof m !== "object" || Array.isArray(m)) { p.errors.push("its plugin.json isn't an object"); return p }

    if (!ID.test(folder)) p.errors.push("its folder name must be lower-case letters, digits and dashes")
    if (m.id !== folder) p.errors.push(`its "id" must be its folder's name ("${folder}")`)
    p.name = text(m.name, 60) || folder
    p.description = text(m.description, 300)
    p.version = text(m.version, 20)
    p.author = text(m.author, 60)

    p.api = Number.isInteger(m.api) ? m.api : 0
    if (p.api < 1) p.errors.push(`it must say which toolkit it's written for ("api": ${API_VERSION})`)
    else if (p.api > API_VERSION) p.errors.push(`it needs a newer Ether Shell (toolkit ${p.api}; this one has ${API_VERSION})`)

    const bar = m.bar
    if (bar !== undefined) {
        if (!bar || typeof bar !== "object") p.errors.push(`"bar" must be { "file": ..., "side": "left" or "right" }`)
        else if (typeof bar.file !== "string" || !FILE.test(bar.file) || !bar.file.endsWith(".qml"))
            p.errors.push(`its bar item must be a .qml file in its own folder`)
        else if (bar.side !== undefined && bar.side !== "left" && bar.side !== "right")
            p.errors.push(`its bar item's "side" must be "left" or "right"`)
        else p.bar = { file: bar.file, side: bar.side || "right" }
    }
    const la = m.launcher
    if (la !== undefined) {
        if (!la || typeof la !== "object") p.errors.push(`"launcher" must be { "file": ..., "prefix": ..., "title": ... }`)
        else if (typeof la.file !== "string" || !FILE.test(la.file) || !la.file.endsWith(".qml"))
            p.errors.push(`its launcher part must be a .qml file in its own folder`)
        else if (la.prefix !== undefined && !PREFIX.test(la.prefix))
            p.errors.push(`its launcher prefix must be 1 to 6 letters, digits or ! # $ % & * + ? ~ , and not start with one the launcher uses itself (= : ; > @ /)`)
        else p.launcher = { file: la.file, prefix: la.prefix || "", title: text(la.title, 40) || p.name }
    }
    const wi = m.widget
    if (wi !== undefined) {
        if (!wi || typeof wi !== "object" || typeof wi.file !== "string" || !FILE.test(wi.file) || !wi.file.endsWith(".qml"))
            p.errors.push(`its desktop widget must be a .qml file in its own folder`)
        else p.widget = { file: wi.file, name: text(wi.name, 40) || p.name, description: text(wi.description, 120) }
    }
    const st = m.settings
    if (st !== undefined) {
        if (!st || typeof st !== "object" || typeof st.file !== "string" || !FILE.test(st.file) || !st.file.endsWith(".qml"))
            p.errors.push(`its settings must be a .qml file in its own folder`)
        else p.settings = { file: st.file }
    }
    // (settings alone don't count: they're there to set up its other parts)
    if (!p.bar && !p.launcher && !p.widget) { if (!p.errors.length) p.errors.push("it doesn't add anything Ether Shell knows how to show") }

    p.ok = p.errors.length === 0
    return p
}

// What the shell's scan prints: for each plugin, \x1e + folder + \x1f + the
// plugin.json.  -> plugins, sorted by name, each checked
export function parseScan(out, dir) {
    const list = []
    for (const rec of String(out).split("\x1e")) {
        const cut = rec.indexOf("\x1f")
        if (cut <= 0) continue
        list.push(readManifest(rec.slice(0, cut), rec.slice(cut + 1), dir))
    }
    list.sort((a, b) => a.name.localeCompare(b.name))
    // two plugins wanting the same launcher prefix: the first (by name)
    // keeps it; the other is told so, and can't be used until one changes
    const taken = {}
    for (const p of list) {
        if (!p.ok || !p.launcher || !p.launcher.prefix) continue
        const pre = p.launcher.prefix
        if (taken[pre]) { p.errors.push(`its launcher prefix "${pre}" is already used by ${taken[pre]}`); p.ok = false }
        else taken[pre] = p.name
    }
    return list
}

// Which launcher part (if any) a search is for.  -> { id, term } for a
// plugin's prefix (the rest of what's typed), or null.  Longest prefix first,
// so "!wd" isn't taken for "!w".
export function prefixFor(query, launchers) {
    const q = String(query)
    let best = null
    for (const l of launchers)
        if (l.prefix && q.startsWith(l.prefix) && (!best || l.prefix.length > best.prefix.length)) best = l
    return best ? { id: best.id, term: q.slice(best.prefix.length).trim() } : null
}

// A result a plugin offers, checked: a title, and what choosing it does.
// -> the result, cleaned, or null
export function cleanResult(r) {
    if (!r || typeof r !== "object") return null
    const title = text(r.title, 200)
    if (!title) return null
    const out = { title: title, subtitle: text(r.subtitle, 200), icon: text(r.icon, 40), data: r }
    if (typeof r.copy === "string") out.copy = r.copy.slice(0, 100000)
    else if (typeof r.open === "string" && /^(https?|file|mailto):/i.test(r.open)) out.open = r.open
    else if (validCommand(r.run)) out.run = r.run.slice()
    return out
}

// A command a plugin asks to run: a list of plain strings, program first.
// (No shell: arguments are never interpreted.)
export function validCommand(cmd) {
    return Array.isArray(cmd) && cmd.length > 0 && cmd.length <= 64
        && cmd.every(a => typeof a === "string" && a.length <= 4096 && !a.includes("\0"))
        && cmd[0].length > 0
}
