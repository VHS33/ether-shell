// layout.mjs  (Ether Shell)
// Arranging monitors: where one lands when it's dragged.  Positions are in
// Hyprland's logical pixels (the mode divided by the scale, and turned by a
// quarter-turn rotation), with y growing downwards, as Hyprland counts.
//
// A dropped monitor snaps edge to edge with the nearest of its neighbours,
// never overlapping one.  Along the shared edge it can sit anywhere, but it
// clicks into line with the neighbour's start, end or centre when it's close.
// Settings imports this; the tests run it.  (No { ...object } spread: Qt's
// JavaScript engine doesn't read it.)

// the logical size: the mode over the scale, turned by a quarter-turn rotation
export function logicalSize(pw, ph, scale, transform) {
    const w = Math.round(pw / scale), h = Math.round(ph / scale)
    return (transform % 2 === 1) ? { w: h, h: w } : { w, h }
}

export function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

// how close to a neighbour's start, end or centre clicks into line with it
const align = size => Math.max(40, Math.round(size * 0.12))

// the positions along one edge: kept where it was dropped (sharing at least
// part of the edge), or in line with the neighbour when that's close
function along(pos, len, oPos, oLen) {
    const lo = oPos - len + 1, hi = oPos + oLen - 1                 // still touching
    let p = Math.min(hi, Math.max(lo, Math.round(pos)))
    // the nearest of them (on similar-sized screens they're close together)
    let best = null
    for (const t of [oPos, oPos + oLen - len, Math.round(oPos + (oLen - len) / 2)])
        if (Math.abs(p - t) <= align(Math.min(len, oLen)) && (best === null || Math.abs(p - t) < Math.abs(p - best))) best = t
    return best === null ? p : best
}

// where `m` ({ w, h }) lands when dropped with its top-left at (x, y), among
// `others` ([{ x, y, w, h }])
export function snap(m, others, x, y) {
    if (!others.length) return { x: 0, y: 0 }
    let best = null
    for (const o of others) {
        const cands = [
            { x: o.x + o.w, y: along(y, m.h, o.y, o.h) },         // to its right
            { x: o.x - m.w, y: along(y, m.h, o.y, o.h) },         // to its left
            { x: along(x, m.w, o.x, o.w), y: o.y + o.h },         // below it
            { x: along(x, m.w, o.x, o.w), y: o.y - m.h },         // above it
        ]
        for (const c of cands) {
            if (others.some(q => overlaps({ x: c.x, y: c.y, w: m.w, h: m.h }, q))) continue
            const d = Math.hypot(c.x - x, c.y - y)
            if (!best || d < best.d) best = { x: c.x, y: c.y, d }
        }
    }
    return best ? { x: best.x, y: best.y } : { x: others[0].x + others[0].w, y: others[0].y }
}

// everything moved so the top-left monitor starts at 0,0 (Hyprland is happy
// either way; round numbers read better)
export function normalise(mons) {
    if (!mons.length) return mons
    const mx = Math.min(...mons.map(m => m.x)), my = Math.min(...mons.map(m => m.y))
    return mons.map(m => Object.assign({}, m, { x: m.x - mx, y: m.y - my }))
}

// after a monitor changes size (resolution, scale, rotation): the others
// settle around the anchor (the main monitor) again, nearest first, each on
// the side it was on, so no gap or overlap appears
export function settle(mons, anchor) {
    const a = mons.find(m => m.name === anchor) || mons[0]
    if (!a) return mons
    const placed = [a]
    const rest = mons.filter(m => m !== a)
        .sort((p, q) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y))
    for (const m of rest) {
        const p = snap(m, placed, m.x, m.y)
        placed.push(Object.assign({}, m, { x: p.x, y: p.y }))
    }
    return normalise(mons.map(m => placed.find(p => p.name === m.name)))
}
