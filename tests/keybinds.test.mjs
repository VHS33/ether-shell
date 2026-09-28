// Changeable shortcuts (config/quickshell/lib/keybinds.mjs), and their
// agreement with hyprland.lua's key() calls.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { CATALOG, normalise, problem, effective, clash } from "../config/quickshell/lib/keybinds.mjs"

test("every shortcut in hyprland.lua is on the Keybinds page, with the same default", () => {
    const lua = readFileSync(new URL("../config/hypr/hyprland.lua", import.meta.url), "utf8")
    const found = {}
    // key("close", mainMod .. " + Q")  or  key("overview", "ALT + Tab")
    for (const m of lua.matchAll(/key\("([a-z_]+)", (mainMod \.\. )?"([^"]*)"\)/g))
        found[m[1]] = normalise((m[2] ? "SUPER" : "") + m[3])
    // the move and resize keys, one line for four directions
    for (const [pre, mods] of [["move_", "SUPER + SHIFT + "], ["resize_", "SUPER + CTRL + "]]) {
        assert.ok(lua.includes(`key("${pre}" .. d.key, mainMod .. " + ${mods.slice(8)}" .. d.key)`), pre + " line")
        for (const d of ["left", "right", "up", "down"]) found[pre + d] = mods + d
    }
    const page = Object.fromEntries(CATALOG.map(c => [c.id, c.def]))
    assert.deepEqual(found, page)
})
test("combos are spelled one way", () => {
    assert.equal(normalise("shift+super + q"), "SUPER + SHIFT + Q")
    assert.equal(normalise("Control + Alt + DELETE"), "CTRL + ALT + Delete")
    assert.equal(normalise("super + f5"), "SUPER + F5")
    assert.equal(normalise("SUPER + TAB"), "SUPER + Tab")
    assert.equal(normalise("SUPER + Q + W"), "")         // two keys
    assert.equal(normalise("SUPER"), "")                 // no key
    assert.equal(normalise("SUPER + ü"), "")             // not a key it knows
})
test("a shortcut needs a modifier, so typing still types", () => {
    assert.match(problem("Q"), /typing Q still types it/)
    assert.match(problem("SHIFT + Q"), /capital/)
    assert.equal(problem("F5"), "")                      // function keys are fine alone
    assert.equal(problem("Print"), "")
    assert.equal(problem("SUPER + W"), "")
})
test("a combo already in use is found, by what uses it", () => {
    assert.equal(clash("terminal", "SUPER + Q", {}), "Close window")
    assert.equal(clash("terminal", "SUPER + 3", {}), "Workspace 3")          // the fixed keys too
    assert.equal(clash("close", "SUPER + Q", {}), "")                         // its own key is fine
    // once close moves to SUPER + W, SUPER + Q is free
    assert.equal(clash("terminal", "SUPER + Q", { close: "SUPER + W" }), "")
    assert.equal(clash("terminal", "super+w", { close: "SUPER + W" }), "Close window")
})
test("changes apply by name; odd values keep the default", () => {
    const e = effective({ close: "super + w", terminal: "nonsense + + ", unknown: "SUPER + Z" })
    assert.equal(e.close, "SUPER + W")
    assert.equal(e.terminal, "SUPER + T")
    assert.equal(e.unknown, undefined)
})
