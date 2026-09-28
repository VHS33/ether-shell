// profiles.mjs  (Ether Shell)
// Monitor profiles: a saved layout (each screen's mode, position, scale,
// rotation and variable refresh, and which screen is the main one) for one
// set of connected screens, used again whenever that set is connected.
// The shell imports this; the tests run it with Node.

export const MAX_PROFILES = 12

// One screen: its connector, model and serial number.  (Two monitors of the
// same model are told apart by their serials, or else their connectors.)
export function screenId(s) {
    return [s.name, s.model, s.serial].map(v => String(v ?? "").replace(/[|;]/g, " ").trim()).join("|")
}
// The screens connected, in any order, as one string
export function screensKey(screens) {
    return (Array.isArray(screens) ? screens : []).map(screenId).sort().join(";")
}

export function cleanName(n) {
    return typeof n === "string" ? n.replace(/\s+/g, " ").trim().slice(0, 30) : ""
}

function plainObject(v) { return !!v && typeof v === "object" && !Array.isArray(v) }

// A profile of the layout now.  `monitors` is as the Displays page applies
// it: { "DP-1": { mode, position, scale, transform, vrr } }.  -> or null
export function makeProfile(name, screens, monitors, main, second) {
    const nm = cleanName(name)
    if (!nm || !Array.isArray(screens) || !screens.length) return null
    const names = screens.map(s => String(s.name))
    const mons = {}
    for (const n of names) if (plainObject(monitors) && plainObject(monitors[n])) mons[n] = Object.assign({}, monitors[n])
    return {
        name: nm,
        key: screensKey(screens),
        screens: screens.map(s => ({ name: String(s.name), model: String(s.model ?? "") })),
        monitors: mons,
        main: names.indexOf(main) >= 0 ? main : "",
        second: names.indexOf(second) >= 0 && second !== main ? second : ""
    }
}

// The saved profiles, checked (settings.json can be edited by hand): one per
// set of screens, names unique (whatever their case), at most MAX_PROFILES.
export function readProfiles(v) {
    if (!Array.isArray(v)) return []
    const out = [], keys = new Set(), names = new Set()
    for (const p of v) {
        if (!plainObject(p)) continue
        const name = cleanName(p.name), key = typeof p.key === "string" ? p.key : ""
        if (!name || !key || keys.has(key) || names.has(name.toLowerCase())) continue
        keys.add(key); names.add(name.toLowerCase())
        out.push({
            name: name, key: key,
            screens: Array.isArray(p.screens)
                ? p.screens.filter(s => plainObject(s) && typeof s.name === "string").map(s => ({ name: s.name, model: String(s.model ?? "") }))
                : [],
            monitors: plainObject(p.monitors) ? p.monitors : {},
            main: typeof p.main === "string" ? p.main : "",
            second: typeof p.second === "string" ? p.second : ""
        })
        if (out.length >= MAX_PROFILES) break
    }
    return out
}

// Adding one replaces a profile for the same screens, or with the same name.
// -> { list, replaced: [names] }, or null when there's no room
export function addProfile(list, p) {
    const l = readProfiles(list)
    const rest = l.filter(q => q.key !== p.key && q.name.toLowerCase() !== p.name.toLowerCase())
    if (rest.length >= MAX_PROFILES) return null
    return { list: rest.concat([p]), replaced: l.filter(q => rest.indexOf(q) < 0).map(q => q.name) }
}
export function removeProfile(list, name) { return readProfiles(list).filter(q => q.name !== name) }
export function findProfile(list, key) { return readProfiles(list).find(q => q.key === key) || null }

// The settings a profile gives: its screens' entries over the others'
// (screens not connected keep theirs, for their own profiles).
export function profileMonitors(p, monitors) {
    return Object.assign({}, plainObject(monitors) ? monitors : {}, p.monitors)
}
// Whether the settings already are the profile's
export function profileInUse(p, monitors, main) {
    const m = plainObject(monitors) ? monitors : {}
    for (const n of Object.keys(p.monitors))
        if (JSON.stringify(m[n] ?? null) !== JSON.stringify(p.monitors[n])) return false
    return !p.main || p.main === main
}
