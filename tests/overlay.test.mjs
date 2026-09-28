// The in-game overlay's MangoHud.conf (config/quickshell/lib/overlay.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { mangoConfig, LAYOUTS, TOGGLE_KEY } from "../config/quickshell/lib/overlay.mjs"

const colours = { bg: "#1a110f", fg: "#f1dfda", accent: "#d66c4c", second: "#ebcba5", third: "#a5a09f", red: "#ffb4ab", yellow: "#fdfd09" }
const conf = o => mangoConfig(Object.assign({ layout: "standard", position: "top-left", size: "normal", colours }, o))
const val = (text, key) => (text.split("\n").find(l => l.startsWith(key + "=")) || "").slice(key.length + 1)

test("the theme's colours, as MangoHud wants them (no #)", () => {
    const t = conf({})
    assert.equal(val(t, "background_color"), "1A110F")
    assert.equal(val(t, "gpu_color"), "D66C4C")
    assert.equal(val(t, "fps_color"), "FFB4AB,FDFD09,D66C4C")
})
test("each layout shows what it says, and turns everything else off", () => {
    for (const layout of Object.keys(LAYOUTS)) {
        const t = conf({ layout })
        for (const k of LAYOUTS[layout]) assert.equal(val(t, k), "1", layout + " " + k)
        assert.equal(val(t, "throttling_status"), "0", layout)          // one of MangoHud's defaults
    }
    assert.equal(val(conf({ layout: "fps" }), "fps_only"), "1")
    assert.equal(val(conf({ layout: "fps" }), "gpu_stats"), "0")
    assert.equal(val(conf({ layout: "standard" }), "fps_only"), "")
})
test("hidden until its key, or shown", () => {
    assert.ok(conf({ hidden: true }).split("\n").includes("no_display"))
    assert.ok(!conf({}).split("\n").includes("no_display"))
    assert.equal(val(conf({}), "toggle_hud"), TOGGLE_KEY)
})
test("odd settings fall back to sensible ones", () => {
    const t = conf({ layout: "huge", position: "middle-of-nowhere", size: "tiny", colours: { accent: "not a colour" } })
    assert.equal(val(t, "position"), "top-left")
    assert.equal(val(t, "font_size"), "22")
    assert.equal(val(t, "gpu_color"), "D66C4C")
    assert.equal(val(t, "fps"), "1")
})
test("a font file only when it's a real path to a font", () => {
    assert.equal(val(conf({ font: "/usr/share/fonts/inter/InterVariable.ttf" }), "font_file"), "/usr/share/fonts/inter/InterVariable.ttf")
    assert.equal(val(conf({ font: "rm -rf ~; x.ttf" }), "font_file"), "")
    assert.equal(val(conf({ font: "" }), "font_file"), "")
})
test("every option it writes is one MangoHud knows", async () => {
    // MangoHud's own example config, kept in tests/ (from its repository)
    const { readFileSync } = await import("node:fs")
    const known = readFileSync(new URL("./MangoHud.conf.example", import.meta.url), "utf8")
    for (const line of conf({ layout: "full", hidden: true, font: "/f.ttf" }).split("\n")) {
        const k = line.split("=")[0].trim()
        if (!k || k.startsWith("#")) continue
        assert.match(known, new RegExp("^#? ?" + k + "(=| |$)", "m"), k)
    }
})
