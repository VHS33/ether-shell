// Your screens, for the welcome's Screens page (modules/welcome): each one's
// resolutions and refresh rates, what's chosen now, where each sits (dragged
// in MonitorLayout, as in Settings, Displays), and the layout to apply.
// Positions and sizes come from layout.mjs, the same maths as Settings.
// Pure: plain values in, plain values out (tests/screens.test.mjs).
//
// A screen here is what Displays.monInfo holds: { name, desc, w, h, hz,
// scale, x, y, transform, vrr, modes: ["2560x1440@239.97Hz", ...] }.
import { logicalSize, normalise, settle } from "./layout.mjs"

// "2560x1440@239.97Hz" -> { w, h, hz, mode: "2560x1440@239.97" }, or null
export function parseMode(str) {
    const m = String(str).replace(/Hz$/, "").match(/^(\d+)x(\d+)@([\d.]+)$/)
    return m ? { w: +m[1], h: +m[2], hz: +m[3], mode: m[1] + "x" + m[2] + "@" + m[3] } : null
}

// its resolutions, biggest first: ["3072x1728", "2560x1440", ...]
export function resolutions(mon, max) {
    const seen = {}, out = []
    for (const s of (mon && mon.modes) || []) {
        const p = parseMode(s)
        if (!p) continue
        const k = p.w + "x" + p.h
        if (!seen[k]) { seen[k] = true; out.push({ k, a: p.w * p.h }) }
    }
    out.sort((a, b) => b.a - a.a)
    return out.map(r => r.k).slice(0, max === undefined ? 8 : max)
}

// the refresh rates at one resolution, fastest first (one of each, rounded:
// 239.97 and 240.00 are both "240 Hz", the more exact kept)
export function rates(mon, res) {
    const byHz = {}
    for (const s of (mon && mon.modes) || []) {
        const p = parseMode(s)
        if (!p || p.w + "x" + p.h !== res) continue
        const r = Math.round(p.hz)
        if (!byHz[r]) byHz[r] = p
    }
    return Object.keys(byHz).map(Number).sort((a, b) => b - a).map(r => byHz[r])
}

// what each screen uses now, as a draft to change:
// { name: { res, mode, scale, transform, vrr } }
export function draftOf(mons) {
    const d = {}
    for (const m of mons || []) {
        const rs = rates(m, m.w + "x" + m.h)
        let best = rs[0]
        for (const r of rs) if (Math.abs(r.hz - m.hz) < Math.abs(best.hz - m.hz)) best = r
        d[m.name] = { res: m.w + "x" + m.h, mode: best ? best.mode : m.w + "x" + m.h + "@" + Number(m.hz || 60).toFixed(2),
                      scale: m.scale || 1, transform: m.transform || 0, vrr: m.vrr || 0 }
    }
    return d
}

// a new resolution: the fastest rate there
export function withRes(draft, name, res, mon) {
    const d = JSON.parse(JSON.stringify(draft))
    if (!d[name]) return d
    d[name].res = res
    const rs = rates(mon, res)
    d[name].mode = rs.length ? rs[0].mode : res + "@60"
    return d
}
export function withField(draft, name, field, value) {
    const d = JSON.parse(JSON.stringify(draft))
    if (d[name]) d[name][field] = value
    return d
}

// a screen's size as the desktop counts it (the mode over the scale, turned)
export function sizeOf(entry) {
    const p = parseMode(entry.mode)
    return p ? logicalSize(p.w, p.h, entry.scale, entry.transform || 0) : { w: 0, h: 0 }
}

// where each one is now, starting at 0,0: { name: { x, y } }
export function positionsOf(mons) {
    const out = {}
    for (const m of normalise((mons || []).map(m => ({ name: m.name, x: m.x || 0, y: m.y || 0 })))) out[m.name] = { x: m.x, y: m.y }
    return out
}

// a screen dropped somewhere (already snapped edge to edge): the rest as they
// were, everything starting at 0,0 again
export function moved(pos, name, x, y) {
    const all = Object.keys(pos).map(n => ({ name: n, x: n === name ? x : pos[n].x, y: n === name ? y : pos[n].y }))
    const out = {}
    for (const m of normalise(all)) out[m.name] = { x: m.x, y: m.y }
    return out
}

// after a size change (resolution, scale): the others settle around the main
// screen, each on the side it was on, with no gap or overlap
export function settleAround(draft, pos, main) {
    const mons = Object.keys(draft).filter(n => pos[n]).map(n => Object.assign({ name: n, x: pos[n].x, y: pos[n].y }, sizeOf(draft[n])))
    const out = {}
    for (const m of settle(mons, main)) out[m.name] = { x: m.x, y: m.y }
    return out
}

// the tiles MonitorLayout draws: [{ name, x, y, w, h, label, label2, main }]
export function tiles(draft, pos, main) {
    return Object.keys(draft).filter(n => pos[n]).map(n => {
        const d = draft[n], p = parseMode(d.mode)
        return Object.assign({ name: n, x: pos[n].x, y: pos[n].y, main: n === main,
                               label: d.res.replace("x", "\u00d7"),
                               label2: (p ? Math.round(p.hz) + " Hz \u00b7 " : "") + Math.round(d.scale * 100) + "%" },
                             sizeOf(d))
    })
}

// what Displays.applyDisplays takes: { name: { mode, position: "XxY", scale, transform, vrr } }
export function toApply(draft, positions) {
    const out = {}
    for (const n of Object.keys(draft)) {
        const d = draft[n], p = positions[n] || { x: 0, y: 0 }
        out[n] = { mode: d.mode, position: Math.round(p.x) + "x" + Math.round(p.y), scale: d.scale,
                   transform: d.transform || 0, vrr: d.vrr || 0 }
    }
    return out
}

// does the draft, or where they sit, differ from what's in use?
export function changed(draft, mons, pos) {
    const now = draftOf(mons), where = positionsOf(mons)
    for (const n of Object.keys(draft)) {
        const a = draft[n], b = now[n]
        if (!b) continue
        if (a.mode !== b.mode || Math.abs(a.scale - b.scale) > 0.001) return true
        if (pos && pos[n] && where[n] && (pos[n].x !== where[n].x || pos[n].y !== where[n].y)) return true
    }
    return false
}
