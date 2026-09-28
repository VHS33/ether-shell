// Arranging monitors (config/quickshell/lib/layout.mjs).  With a desk like
// the one it was built for: a 4K screen at 125% (3072x1728 logical) and a
// 1440p one at 100%.
import { test } from "node:test"
import assert from "node:assert/strict"
import { logicalSize, snap, overlaps, normalise, settle } from "../config/quickshell/lib/layout.mjs"

const big = { name: "DP-1", x: 0, y: 1440, ...logicalSize(3840, 2160, 1.25, 0) }
const small = { w: 2560, h: 1440 }

test("the logical size: the mode over the scale, turned by rotation", () => {
    assert.deepEqual(logicalSize(3840, 2160, 1.25, 0), { w: 3072, h: 1728 })
    assert.deepEqual(logicalSize(2560, 1440, 1, 1), { w: 1440, h: 2560 })       // 90 degrees
    assert.deepEqual(logicalSize(2560, 1440, 1, 2), { w: 2560, h: 1440 })       // 180
})
test("dropped roughly above: it sits right on top, touching", () => {
    const p = snap(small, [big], 300, 100)
    assert.equal(p.y, big.y - small.h)
    assert.ok(p.x > big.x - small.w && p.x < big.x + big.w, "sharing the edge")
})
test("near the centre, it clicks into line with it", () => {
    const centre = Math.round((big.w - small.w) / 2)
    assert.deepEqual(snap(small, [big], centre + 60, 0), { x: centre, y: big.y - small.h })
})
test("near the left edge, it lines up with it", () => {
    assert.deepEqual(snap(small, [big], 90, 0), { x: 0, y: big.y - small.h })
})
test("further along, it stays where it was dropped (offset as you like)", () => {
    assert.deepEqual(snap(small, [big], 1500, 0), { x: 1500, y: big.y - small.h })
})
test("dropped to the right: beside it", () => {
    const p = snap(small, [big], 4000, 1500)
    assert.equal(p.x, big.x + big.w)
})
test("dropped on top of it: pushed to the nearest free side, never overlapping", () => {
    const p = snap(small, [big], 200, 1700)
    assert.equal(overlaps({ ...p, ...small }, big), false)
})
test("it never ends up only touching at a corner", () => {
    const p = snap(small, [big], -2600, -1500)
    const sharesX = p.x < big.x + big.w && big.x < p.x + small.w
    const sharesY = p.y < big.y + big.h && big.y < p.y + small.h
    assert.ok(sharesX || sharesY)
})
test("three monitors: the third finds room without overlapping either", () => {
    const b = { x: 0, y: 0, w: 2560, h: 1440 }
    const c = { w: 1080, h: 1920 }
    const p = snap(c, [big, b], 3000, 1400)
    for (const o of [big, b]) assert.equal(overlaps({ ...p, ...c }, o), false)
})
test("everything is moved so it starts at 0,0", () => {
    const n = normalise([{ name: "a", x: -2560, y: 0, w: 2560, h: 1440 }, { name: "b", x: 0, y: -300, w: 3072, h: 1728 }])
    assert.deepEqual(n.map(m => [m.x, m.y]), [[0, 300], [2560, 0]])
})
test("after the big screen's scale changes, the other settles back against it", () => {
    // DP-2 was on top; DP-1 goes from 125% to 150%, so it's smaller now
    const mons = [{ ...big }, { name: "DP-2", x: 256, y: 0, w: 2560, h: 1440 }]
    mons[0] = { ...mons[0], ...logicalSize(3840, 2160, 1.5, 0) }
    const s = settle(mons, "DP-1")
    const [a, b] = s
    assert.equal(overlaps(a, b), false)
    assert.equal(b.y + b.h, a.y, "still right on top, no gap")
})
test("rotating the second screen: it settles without overlapping", () => {
    const mons = [{ ...big }, { name: "DP-2", x: 0, y: 0, ...logicalSize(2560, 1440, 1, 1) }]
    const s = settle(mons, "DP-1")
    assert.equal(overlaps(s[0], s[1]), false)
})
