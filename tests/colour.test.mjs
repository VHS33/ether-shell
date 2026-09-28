// The colour rules (config/quickshell/lib/colour.mjs).   node --test tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import * as C from "../config/quickshell/lib/colour.mjs"

// accent, background -> what the shell showed (checked by hand against Qt
// and setwall's awk when the vivid accent was built)
const verified = [
    ["#d66c4c", "#1a110f", "#d66c4c"],  // already readable: unchanged
    ["#5d0d09", "#1a1110", "#eb372e"],  // the poppies' deep red, lightened
    ["#2a568f", "#111318", "#477fc9"],  // the hydrangea's blue, lightened
    ["#b83c26", "#1c100e", "#d6523b"],
    ["#fd933e", "#19120d", "#fd933e"],
    ["#69906b", "#101510", "#69906b"],
    ["#d66c4c", "#fff8f6", "#be4e2c"],  // a light theme: darkened
    ["#2a568f", "#f9f9ff", "#2a568f"],
    ["#fd3f51", "#1a1111", "#fd3f51"],
]
test("the accent rule gives the verified colours", () => {
    for (const [c, bg, want] of verified) assert.equal(C.readableAccent(c, bg), want, `${c} on ${bg}`)
})

// a spread of colours on typical theme backgrounds, dark and light
function* pairs() {
    const bgs = ["#101417", "#1a110f", "#131318", "#fff8f6", "#f9f9ff", "#fcfcfc"]
    for (let h = 0; h < 360; h += 15)
        for (const s of [0.15, 0.5, 0.95])
            for (const l of [0.08, 0.3, 0.55, 0.85])
                for (const bg of bgs) yield [C.fromHsl(h / 360, s, l), bg]
}
test("the accent always reads at 4.5:1 or better", () => {
    let n = 0
    for (const [c, bg] of pairs()) {
        const a = C.readableAccent(c, bg)
        assert.ok(C.contrast(a, bg) >= 4.5, `${c} on ${bg} gave ${a} at ${C.contrast(a, bg).toFixed(2)}:1`)
        n++
    }
    assert.ok(n > 800)
})
test("the accent keeps its hue", () => {
    for (const [c, bg] of pairs()) {
        const before = C.hslOf(c), after = C.hslOf(C.readableAccent(c, bg))
        if (before.h < 0 || before.s < 0.1 || after.l > 0.97 || after.l < 0.03) continue   // greys, and where hue fades out
        const d = Math.abs(((after.h - before.h) * 360 + 540) % 360 - 180)
        assert.ok(d < 6, `${c} on ${bg}: hue moved ${d.toFixed(1)} degrees`)
    }
})
test("a colour that already reads is left exactly as it is", () => {
    assert.equal(C.readableAccent("#ff8800", "#101010"), "#ff8800")
})
test("text on an accent: whichever reads better", () => {
    assert.equal(C.textOn("#d66c4c", "#1a110f", "#f1dfda"), "#1a110f")
    assert.equal(C.textOn("#2a3a8f", "#1a110f", "#f1dfda"), "#f1dfda")
})
test("contrast: black on white is 21:1, a colour on itself 1:1", () => {
    assert.equal(C.contrast("#000000", "#ffffff").toFixed(2), "21.00")
    assert.equal(C.contrast("#7b4a2e", "#7b4a2e"), 1)
})
test("colours as Qt writes them, with transparency, are read", () => {
    assert.deepEqual(C.rgbOf("#80d66c4c"), C.rgbOf("#d66c4c"))
    assert.throws(() => C.rgbOf("not a colour"))
})
test("the third accent: the picture's second colour, else a close neighbour", () => {
    const t = C.thirdAccent("#d66c4c", "#c9c5a0", "#3e79a3", "scheme-content", true)
    assert.ok(Math.abs(C.hslOf(t).h - C.hslOf("#3e79a3").h) < 0.02, "hue of the second colour")
    assert.ok(Math.abs(C.hslOf(t).l - C.hslOf("#c9c5a0").l) < 0.02, "lightness of the palette's third accent")
    const n = C.thirdAccent("#d66c4c", "#c9c5a0", "", "scheme-content", true)
    const d = ((C.hslOf(n).h - C.hslOf("#d66c4c").h) * 360 + 360) % 360
    assert.ok(Math.abs(d - 28) < 2, "28 degrees along")
    assert.equal(C.thirdAccent("#d66c4c", "#c9c5a0", "#3e79a3", "scheme-monochrome", true), "#c9c5a0")
    assert.equal(C.thirdAccent("#d66c4c", "#c9c5a0", "#3e79a3", "scheme-content", false), "#c9c5a0")
})
