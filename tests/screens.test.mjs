// Your screens, for the welcome (config/quickshell/lib/screens.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { parseMode, resolutions, rates, draftOf, withRes, withField, sizeOf, positionsOf, moved, settleAround, tiles, toApply, changed } from "../config/quickshell/lib/screens.mjs"

// like Hyprland reports: a 3072x1728 240 Hz main screen, a 2560x1440 to its right
const MAIN = { name: "DP-1", w: 3072, h: 1728, hz: 239.99, scale: 1.5, x: 0, y: 0, transform: 0, vrr: 0,
    modes: ["3072x1728@239.99Hz", "3072x1728@144.00Hz", "3072x1728@60.00Hz", "2560x1440@239.97Hz", "2560x1440@240.00Hz", "1920x1080@60.00Hz"] }
const SIDE = { name: "DP-2", w: 2560, h: 1440, hz: 165.0, scale: 1, x: 2048, y: 0, transform: 0, vrr: 0,
    modes: ["2560x1440@165.00Hz", "2560x1440@144.00Hz", "2560x1440@59.95Hz", "1920x1080@60.00Hz"] }
const MONS = [MAIN, SIDE]

test("modes: parsed, resolutions biggest first, rates fastest first", () => {
    assert.deepEqual(parseMode("2560x1440@239.97Hz"), { w: 2560, h: 1440, hz: 239.97, mode: "2560x1440@239.97" })
    assert.equal(parseMode("nonsense"), null)
    assert.deepEqual(resolutions(MAIN), ["3072x1728", "2560x1440", "1920x1080"])
    assert.deepEqual(resolutions(MAIN, 2), ["3072x1728", "2560x1440"])
    assert.deepEqual(rates(MAIN, "3072x1728").map(r => Math.round(r.hz)), [240, 144, 60])
    // 239.97 and 240.00 are one "240 Hz", not two
    assert.deepEqual(rates(MAIN, "2560x1440").map(r => Math.round(r.hz)), [240])
    assert.deepEqual(resolutions({}), [])
})

test("what's in use now", () => {
    const d = draftOf(MONS)
    assert.deepEqual(d["DP-1"], { res: "3072x1728", mode: "3072x1728@239.99", scale: 1.5, transform: 0, vrr: 0 })
    assert.equal(d["DP-2"].mode, "2560x1440@165.00")
    assert.deepEqual(positionsOf(MONS), { "DP-1": { x: 0, y: 0 }, "DP-2": { x: 2048, y: 0 } })
    assert.equal(changed(d, MONS, positionsOf(MONS)), false)
})

test("changing one: a new resolution takes its fastest rate", () => {
    let d = draftOf(MONS)
    d = withRes(d, "DP-2", "1920x1080", SIDE)
    assert.equal(d["DP-2"].mode, "1920x1080@60.00")
    d = withField(d, "DP-1", "scale", 2)
    assert.equal(d["DP-1"].scale, 2)
    assert.equal(changed(d, MONS, positionsOf(MONS)), true)
    assert.equal(draftOf(MONS)["DP-1"].scale, 1.5)          // the original isn't touched
})

test("dragging: where it was dropped, everything from 0,0", () => {
    const pos = positionsOf(MONS)
    // DP-2 dragged to the left of DP-1 (snapped there by MonitorLayout)
    assert.deepEqual(moved(pos, "DP-2", -2560, 0), { "DP-1": { x: 2560, y: 0 }, "DP-2": { x: 0, y: 0 } })
    // under it
    assert.deepEqual(moved(pos, "DP-2", 0, 1152), { "DP-1": { x: 0, y: 0 }, "DP-2": { x: 0, y: 1152 } })
    assert.equal(changed(draftOf(MONS), MONS, moved(pos, "DP-2", 0, 1152)), true)   // moving it counts
    assert.deepEqual(pos["DP-2"], { x: 2048, y: 0 })        // the original isn't touched
})

test("a size change: the other settles beside the main one, no gap or overlap", () => {
    const pos = positionsOf(MONS)
    // DP-1 at 150% is 2048 wide; at 100% it's 3072, so DP-2 (on its right) moves out to 3072
    const d = withField(draftOf(MONS), "DP-1", "scale", 1)
    assert.deepEqual(sizeOf(d["DP-1"]), { w: 3072, h: 1728 })
    const p = settleAround(d, pos, "DP-1")
    assert.equal(p["DP-2"].x - p["DP-1"].x, 3072)
    // one screen: at 0,0
    assert.deepEqual(settleAround({ "DP-1": d["DP-1"] }, { "DP-1": { x: 500, y: 9 } }, "DP-1"), { "DP-1": { x: 0, y: 0 } })
})

test("the tiles to draw", () => {
    const t = tiles(draftOf(MONS), positionsOf(MONS), "DP-1")
    assert.deepEqual(t[0], { name: "DP-1", x: 0, y: 0, main: true, label: "3072\u00d71728", label2: "240 Hz \u00b7 150%", w: 2048, h: 1152 })
    assert.equal(t[1].main, false)
    assert.equal(t[1].w, 2560)
})

test("what's applied", () => {
    const d = draftOf(MONS)
    const out = toApply(d, moved(positionsOf(MONS), "DP-2", -2560, 0))
    assert.deepEqual(out["DP-2"], { mode: "2560x1440@165.00", position: "0x0", scale: 1, transform: 0, vrr: 0 })
    assert.equal(out["DP-1"].position, "2560x0")
})
