// Monitor profiles (config/quickshell/lib/profiles.mjs)
import { test } from "node:test"
import assert from "node:assert/strict"
import { screensKey, makeProfile, readProfiles, addProfile, removeProfile, findProfile,
         profileMonitors, profileInUse, MAX_PROFILES } from "../config/quickshell/lib/profiles.mjs"

const big = { name: "DP-1", model: "Odyssey G8", serial: "H1AK500000" }
const top = { name: "DP-2", model: "27GL850", serial: "007NTAB" }
const tv  = { name: "HDMI-A-1", model: "LG TV", serial: "" }
const mons = {
    "DP-1": { mode: "3840x2160@240.00", position: "0x1440", scale: 1.25, transform: 0, vrr: 2 },
    "DP-2": { mode: "2560x1440@143.97", position: "256x0", scale: 1, transform: 0, vrr: 0 }
}

test("the same screens give the same key, in any order; different ones don't", () => {
    assert.equal(screensKey([big, top]), screensKey([top, big]))
    assert.notEqual(screensKey([big, top]), screensKey([big]))
    assert.notEqual(screensKey([big, top]), screensKey([big, { ...top, serial: "OTHER" }]))   // another monitor, same model
    assert.notEqual(screensKey([big]), screensKey([{ ...big, name: "DP-3" }]))                // moved to another socket
    assert.equal(screensKey(null), "")
})
test("a profile keeps only its own screens' settings, and a main screen that's connected", () => {
    const p = makeProfile("  Desk  ", [big], mons, "DP-1", "DP-2")
    assert.equal(p.name, "Desk")
    assert.deepEqual(Object.keys(p.monitors), ["DP-1"])
    assert.equal(p.main, "DP-1")
    assert.equal(p.second, "")                           // DP-2 isn't in this profile
    assert.equal(makeProfile("", [big], mons, "DP-1"), null)
    assert.equal(makeProfile("Desk", [], mons, "DP-1"), null)
    assert.equal(makeProfile("x".repeat(50), [big], mons).name.length, 30)
})
test("saving replaces the profile for the same screens, or of the same name", () => {
    const desk = makeProfile("Desk", [big, top], mons, "DP-1", "DP-2")
    const tvp = makeProfile("TV", [big, tv], mons, "DP-1", "HDMI-A-1")
    let r = addProfile([], desk); r = addProfile(r.list, tvp)
    assert.deepEqual(r.list.map(p => p.name), ["Desk", "TV"])
    const again = addProfile(r.list, makeProfile("Desk 2", [top, big], mons, "DP-2", "DP-1"))   // same screens
    assert.deepEqual(again.list.map(p => p.name), ["TV", "Desk 2"])
    assert.deepEqual(again.replaced, ["Desk"])
    const renamed = addProfile(r.list, makeProfile("desk", [big], mons, "DP-1"))                // same name, any case
    assert.deepEqual(renamed.list.map(p => p.name), ["TV", "desk"])
    assert.deepEqual(removeProfile(r.list, "TV").map(p => p.name), ["Desk"])
})
test("there's a limit, but replacing still works when full", () => {
    let l = []
    for (let i = 0; i < MAX_PROFILES; i++) l = addProfile(l, makeProfile("P" + i, [{ name: "DP-" + i }], mons)).list
    assert.equal(addProfile(l, makeProfile("One more", [{ name: "X" }], mons)), null)
    assert.equal(addProfile(l, makeProfile("P3", [{ name: "DP-3" }], mons)).list.length, MAX_PROFILES)
})
test("the one for the screens now is found", () => {
    const l = addProfile([], makeProfile("Desk", [big, top], mons, "DP-1")).list
    assert.equal(findProfile(l, screensKey([top, big])).name, "Desk")
    assert.equal(findProfile(l, screensKey([big])), null)
})
test("using one sets its screens and leaves other screens' settings be", () => {
    const solo = makeProfile("Solo", [big], { "DP-1": { ...mons["DP-1"], position: "0x0" } }, "DP-1")
    const out = profileMonitors(solo, mons)
    assert.equal(out["DP-1"].position, "0x0")
    assert.deepEqual(out["DP-2"], mons["DP-2"])
    assert.equal(profileInUse(solo, mons, "DP-1"), false)
    assert.equal(profileInUse(solo, out, "DP-1"), true)
    assert.equal(profileInUse(solo, out, "DP-2"), false)          // another main screen
})
test("profiles edited by hand are checked", () => {
    const good = makeProfile("Desk", [big], mons, "DP-1")
    const l = readProfiles([good, null, "x", { name: "No key" }, { ...good, name: "Twin" }, { ...good, key: "k2", name: "DESK" },
                            { name: "Odd", key: "k3", monitors: [1, 2], screens: "no", main: 5 }])
    assert.deepEqual(l.map(p => p.name), ["Desk", "Odd"])
    assert.deepEqual(l[1].monitors, {}); assert.deepEqual(l[1].screens, []); assert.equal(l[1].main, "")
    assert.deepEqual(readProfiles("nope"), [])
})
