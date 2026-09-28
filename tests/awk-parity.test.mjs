// setwall's awk readable() and the shell's colour.mjs must agree exactly:
// the shell and every app would otherwise show slightly different accents.
// The awk program is taken from setwall itself, so this tests what ships.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { spawnSync } from "node:child_process"
import * as C from "../config/quickshell/lib/colour.mjs"

const setwall = readFileSync(new URL("../local/bin/setwall", import.meta.url), "utf8")
const fn = setwall.slice(setwall.indexOf("readable() {"))
const prog = fn.slice(fn.indexOf("'") + 1, fn.indexOf("\n'\n"))

test("setwall's awk and the shell give the same accent and text colour", () => {
    const bgs = [["#101417", "#e0e3e8"], ["#1a110f", "#f1dfda"], ["#fff8f6", "#231917"], ["#f9f9ff", "#191c20"]]
    const lines = []
    for (let h = 0; h < 360; h += 10)
        for (const s of [0.2, 0.6, 1])
            for (const l of [0.1, 0.35, 0.6, 0.9])
                for (const [bg, fg] of bgs) lines.push([C.fromHsl(h / 360, s, l), bg, fg])
    // one awk run per colour, as setwall does
    let checked = 0
    for (const [c, bg, fg] of lines) {
        const r = spawnSync("awk", ["-v", `seed=${c}`, "-v", `bg=${bg}`, "-v", `fg=${fg}`, prog], { encoding: "utf8" })
        assert.equal(r.status, 0, r.stderr)
        const [accent, text] = r.stdout.trim().split(" ")
        const js = C.readableAccent(c, bg)
        assert.equal(accent, js, `${c} on ${bg}: awk ${accent}, shell ${js}`)
        assert.equal(text, C.textOn(js, bg, fg), `text on ${js}`)
        checked++
    }
    assert.ok(checked > 400)
})
