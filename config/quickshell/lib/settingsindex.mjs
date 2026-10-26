// Every setting in Settings, read from the page files themselves
// (modules/settings/Page*.qml), so the launcher can find them while Settings
// is closed, and a setting added to a page is found with nothing else to
// update.  Pure: text in, plain values out (tests/settingsindex.test.mjs).
//
// What's read from a page: its pageNo, each SectionLabel's text, and each
// Card's title and desc when they're written as plain text.  Left out: a card
// whose title is worked out while running (a monitor's name...), one of a
// list's copies (inside a Repeater...), and a message marked searchable: false.
// One that only shows sometimes (Game overlay's Layout, while it's on) is in:
// Settings opens at its page, where what turns it on is.
//
// A card is an on/off switch the launcher can flip when it holds nothing but
//     Seg { options: ["Off", "On"]; current: <one of the forms below>
//           onPicked: i => app.setting("<key>", i === 1) }
// with current read as
//     app.cfg.<key> === true ? 1 : 0     on only when set (off by default)
//     app.cfg.<key> !== false ? 1 : 0    on unless turned off (on by default)
//     app.<name> ? 1 : 0                 the shell's own copy of it
// Anything else (more choices, other steps when picked) only opens Settings.

// The pages, in Settings' order (its page numbers), with the file each is in
// and its icon.  Settings uses this list too.
export const PAGES = [
    { t: "General",        f: "PageGeneral",       g: "text_fields",          d: "File search, the clipboard, and text across the whole shell" },
    { t: "Glass",          f: "PageGlass",         g: "blur_on",              d: "How far the desktop shows through" },
    { t: "Theme",          f: "PageTheme",         g: "palette",              d: "How colours are drawn from the wallpaper" },
    { t: "Wallpaper",      f: "PageWallpaper",     g: "wallpaper",            d: "The image everything takes its colours from" },
    { t: "Bar",            f: "PageBar",           g: "toolbar",              d: "The clock and what the top bar shows" },
    { t: "Windows",        f: "PageWindows",       g: "web_asset",            d: "Spacing, shape and motion for app windows" },
    { t: "Dock",           f: "PageDock",          g: "dock_to_bottom",       d: "The window dock, along the bottom or down a side" },
    { t: "Notifications",  f: "PageNotifications", g: "notifications",        d: "Popups and on-screen indicators" },
    { t: "Idle",           f: "PageIdle",          g: "lock",                 d: "Locking, screens off and sleep when you step away; power saver on laptops" },
    { t: "Displays",       f: "PageDisplays",      g: "monitor",              d: "Arrange your screens by dragging, and each one's resolution, refresh, scale and rotation" },
    { t: "Keyboard",       f: "PageKeyboard",      g: "keyboard",             d: "How keys repeat when held" },
    { t: "Mouse",          f: "PageMouse",         g: "mouse",                d: "Pointer speed, scrolling and focus" },
    { t: "Output",         f: "PageOutput",        g: "speaker",              d: "Where sound plays and how loud it is" },
    { t: "Applications",   f: "PageApplications",  g: "apps",                 d: "Volume for each app that is playing sound" },
    { t: "Input",          f: "PageInput",         g: "mic",                  d: "Which microphone is used and its level" },
    { t: "Recording apps", f: "PageRecording",     g: "radio_button_checked", d: "Apps currently listening to a microphone" },
    { t: "Weather",        f: "PageWeather",       g: "partly_cloudy_day",    d: "Where the forecast is for, and its units" },
    { t: "Calendar",       f: "PageCalendar",      g: "calendar_month",       d: "Holidays and the first day of the week" },
    { t: "About",          f: "PageAbout",         g: "info",                 d: "This machine and the software running it" },
    { t: "Widgets",        f: "PageWidgets",       g: "widgets",              d: "Clocks, weather and more on the desktop, behind your windows" },
    { t: "Lock screen",    f: "PageLockScreen",    g: "lock_clock",           d: "What you see when the screen is locked" },
    { t: "Default apps",   f: "PageDefaultApps",   g: "apps",                 d: "Which terminal, file manager and browser open" },
    { t: "AI assistant",   f: "PageAssistant",     g: "smart_toy",            d: "Which AI answers in the assistant panel, and your key for it" },
    { t: "Plugins",        f: "PagePlugins",       g: "extension",            d: "Add-ons from other people (or you): bar items, launcher results, widgets and settings" },
    { t: "Keybinds",       f: "PageKeybinds",      g: "keyboard_command_key", d: "Every shortcut, and changing them" },
    { t: "Game overlay",   f: "PageGameOverlay",   g: "sports_esports",       d: "Frame rate, GPU and CPU on top of your games, in your theme" },
]

// a QML string as written ("..." with JS escapes) -> its text, or null
function unquote(lit) {
    try { return JSON.parse(lit) } catch (e) { }
    try { return JSON.parse(lit.replace(/\\'/g, "'")) } catch (e) { return null }
}

// the text of a property written as one plain string on its own line:
//     title: "Cursor size"          -> "Cursor size"
//     title: on ? "A" : "B"         -> null (worked out while running)
function plain(block, name) {
    const re = new RegExp("^[ \\t]*" + name + ":[ \\t]*(\"(?:[^\"\\\\]|\\\\.)*\")[ \\t]*;?[ \\t]*(?://.*)?$", "m")
    const m = block.match(re)
    return m ? unquote(m[1]) : null
}

// the text from an opening "{" to its matching "}", skipping strings and
// comments.  -> the index just past the "}", or -1
function closing(src, open) {
    let depth = 0
    for (let i = open; i < src.length; i++) {
        const c = src[i]
        if (c === '"' || c === "'") {
            for (i++; i < src.length && src[i] !== c; i++) if (src[i] === "\\") i++
        } else if (c === "/" && src[i + 1] === "/") {
            while (i < src.length && src[i] !== "\n") i++
        } else if (c === "/" && src[i + 1] === "*") {
            const e = src.indexOf("*/", i + 2)
            i = e < 0 ? src.length : e + 1
        } else if (c === "{") depth++
        else if (c === "}" && --depth === 0) return i + 1
    }
    return -1
}

// a card's own lines: its block without the blocks inside it
function ownLines(block) {
    let out = "", i = block.indexOf("{") + 1
    const end = block.lastIndexOf("}")
    while (i < end) {
        const j = block.indexOf("{", i)
        if (j < 0 || j >= end) { out += block.slice(i, end); break }
        out += block.slice(i, j)
        const k = closing(block, j)
        if (k < 0) break
        i = k
    }
    return out
}

// is the card a plain on/off switch?  -> { key, read: { kind, name } } or null
export function switchOf(block) {
    // (no matchAll or spread: Qt's JavaScript doesn't have them)
    const segRe = /\bSeg\s*\{/g
    const segs = []
    let sm
    while ((sm = segRe.exec(block))) segs.push(sm)
    if (segs.length !== 1) return null
    const s = segs[0].index + segs[0][0].length - 1
    const e = closing(block, s)
    if (e < 0) return null
    const seg = block.slice(s, e)
    if (!/^\s*options:\s*\[\s*"Off"\s*,\s*"On"\s*\]\s*$/m.test(seg)) return null
    const pick = seg.match(/^\s*onPicked:\s*i\s*=>\s*app\.setting\("([A-Za-z0-9_]+)",\s*i\s*===\s*1\)\s*$/m)
    if (!pick) return null
    const cur = (seg.match(/^\s*current:\s*(.+?)\s*$/m) || [])[1] || ""
    let m
    if ((m = cur.match(/^app\.cfg\.([A-Za-z0-9_]+)\s*===\s*true\s*\?\s*1\s*:\s*0$/)) && m[1] === pick[1])
        return { key: pick[1], read: { kind: "cfgTrue", name: m[1] } }
    if ((m = cur.match(/^app\.cfg\.([A-Za-z0-9_]+)\s*!==\s*false\s*\?\s*1\s*:\s*0$/)) && m[1] === pick[1])
        return { key: pick[1], read: { kind: "cfgNotFalse", name: m[1] } }
    if ((m = cur.match(/^app\.([A-Za-z0-9_]+)\s*\?\s*1\s*:\s*0$/)) && m[1] !== "cfg")
        return { key: pick[1], read: { kind: "app", name: m[1] } }
    return null
}

// every object in a file ("Type {" ... "}"), outermost first:
// [{ type, start, open, end }]
function objects(src) {
    const out = []
    const re = /\b([A-Z][A-Za-z0-9_.]*)\s*\{/g
    let m
    while ((m = re.exec(src))) {
        // skip ones inside strings or comments: closing() from the file's
        // start would be slow, so just check the line isn't a comment
        const lineStart = src.lastIndexOf("\n", m.index) + 1
        const before = src.slice(lineStart, m.index)
        if (/\/\/|^\s*\*/.test(before) || (before.split('"').length - 1) % 2 === 1) continue
        const open = m.index + m[0].length - 1
        const end = closing(src, open)
        if (end < 0) break
        out.push({ type: m[1], start: m.index, open, end })
    }
    return out
}

// one page file -> { pageNo, entries: [{ title, desc, section, pageNo, page, glyph, sw }] }
export function parsePage(src) {
    src = String(src ?? "")
    const no = src.match(/property\s+int\s+pageNo:\s*(\d+)/)
    const pageNo = no ? +no[1] : -1
    const pg = PAGES[pageNo] || { t: "", g: "settings" }
    const objs = objects(src)
    const entries = [], seen = {}
    let section = ""
    for (const o of objs) {
        const block = src.slice(o.start, o.end)
        if (o.type === "SectionLabel") {
            const t = plain(ownLines(block).replace(/;/g, "\n"), "text")
            if (t !== null) section = t
            continue
        }
        if (o.type !== "Card") continue
        const own = ownLines(block)
        const title = plain(own, "title")
        if (!title) continue
        // what it's inside (not the page itself, which shows and hides as a whole)
        const outer = objs.filter(p => p !== objs[0] && p.start < o.start && p.end >= o.end)
        // a message, not a setting ("Nothing is playing")
        if (/^[ \t]*searchable:[ \t]*false[ \t]*$/m.test(own)) continue
        // a copy per item of a list (a monitor, a plugin...): not one setting
        if (outer.some(p => p.type === "Repeater" || p.type === "Instantiator" || p.type === "Loader" || p.type === "Component")) continue
        const k = title.toLowerCase()
        if (seen[k]) continue
        seen[k] = true
        const e = { title, desc: plain(own, "desc") || "", section, pageNo, page: pg.t, glyph: pg.g }
        const sw = switchOf(block)
        if (sw) e.sw = sw
        entries.push(e)
    }
    return { pageNo, entries }
}

// is a switch on right now?  (app: the shell's root, or anything with cfg)
export function isOn(sw, app) {
    if (!sw || !app) return false
    const cfg = app.cfg || {}
    const r = sw.read
    if (r.kind === "cfgTrue") return cfg[r.name] === true
    if (r.kind === "cfgNotFalse") return cfg[r.name] !== false
    return !!app[r.name]
}

// a launcher row for a setting
export function row(e, app) {
    const out = {
        kind: "setting", title: e.title, glyph: e.glyph || "settings",
        sub: e.page + (e.section ? "  \u203a  " + e.section : ""),
        pageNo: e.pageNo, sw: e.sw || null, key: "set:" + e.pageNo + ":" + e.title,
    }
    // (the state is part of its key, so the row is redrawn when it's flipped)
    if (e.sw) { out.badge = isOn(e.sw, app) ? "On" : "Off"; out.key += ":" + out.badge }
    return out
}
