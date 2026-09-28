// Searching Settings (config/quickshell/lib/search.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { search, scoreSetting, words } from "../config/quickshell/lib/search.mjs"

const S = [
    { page: "Displays", section: "", title: "Refresh rate", desc: "How many times a second the screen redraws" },
    { page: "Displays", section: "", title: "Scale", desc: "How big everything is drawn" },
    { page: "Glass", section: "", title: "Blur", desc: "How much the desktop behind is blurred" },
    { page: "Bar", section: "Clock", title: "24-hour clock", desc: "Show the time as 14:00 instead of 2:00 PM" },
    { page: "Output", section: "", title: "Volume", desc: "How loud sound plays" },
    { page: "Theme", section: "", title: "Accent", desc: "Vivid: the wallpaper's own colour. Soft: Material's lighter one" },
    { page: "Lock screen", section: "Login screen", title: "Background", desc: "Shown before anyone signs in" },
]
const titles = q => search(S, q).map(e => e.title)

test("a word finds the setting it names", () => {
    assert.equal(titles("blur")[0], "Blur")
    assert.equal(titles("volume")[0], "Volume")
})
test("the start of a word is enough", () => {
    assert.equal(titles("refr")[0], "Refresh rate")
    assert.equal(titles("acc")[0], "Accent")
})
test("one typo is forgiven in longer words", () => {
    assert.equal(titles("refesh")[0], "Refresh rate")
    assert.equal(titles("volumn")[0], "Volume")
})
test("every word typed must match", () => {
    assert.deepEqual(titles("clock 24"), ["24-hour clock"])
    assert.deepEqual(titles("clock volume"), [])
})
test("the page or section finds its settings", () => {
    assert.deepEqual(titles("displays"), ["Refresh rate", "Scale"])
    assert.equal(titles("login")[0], "Background")
})
test("titles count more than descriptions", () => {
    // "colour" is only in Accent's description; "clock" is 24-hour clock's title
    assert.ok(scoreSetting(S[3], "clock") > scoreSetting(S[5], "colour"))
})
test("case, accents and punctuation don't matter", () => {
    assert.deepEqual(words("Écran: 144 Hz"), ["ecran", "144", "hz"])
    assert.equal(titles("BLUR")[0], "Blur")
})
test("nothing typed, or nothing that matches, finds nothing", () => {
    assert.deepEqual(titles(""), []); assert.deepEqual(titles("   "), []); assert.deepEqual(titles("zzzz"), [])
})
