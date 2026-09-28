// Reading plugins (config/quickshell/lib/plugins.mjs): strict, since they
// come from other people.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readManifest, parseScan, validCommand, API_VERSION } from "../config/quickshell/lib/plugins.mjs"

const D = "/home/u/.config/ether-shell/plugins"
const good = { id: "uptime", name: "Uptime", description: "How long since boot", version: "1.0", author: "hal",
               api: 1, bar: { file: "Bar.qml", side: "left" } }
const read = (folder, m) => readManifest(folder, typeof m === "string" ? m : JSON.stringify(m), D)

test("a good plugin is read, with its folder and bar item", () => {
    const p = read("uptime", good)
    assert.equal(p.ok, true, p.errors.join("; "))
    assert.equal(p.dir, D + "/uptime")
    assert.deepEqual(p.bar, { file: "Bar.qml", side: "left" })
    assert.equal(read("uptime", { ...good, bar: { file: "Bar.qml" } }).bar.side, "right")   // the default side
})
test("its files must be in its own folder", () => {
    for (const file of ["../evil.qml", "/etc/x.qml", "sub/Bar.qml", ".hidden.qml", "Bar.js", "Bar.qml\n", ""])
        assert.equal(read("uptime", { ...good, bar: { file, side: "left" } }).ok, false, JSON.stringify(file))
})
test("its id must be its folder's name, in plain letters", () => {
    assert.equal(read("uptime", { ...good, id: "other" }).ok, false)
    assert.equal(read("Up Time", { ...good, id: "Up Time" }).ok, false)
    assert.equal(read("../x", { ...good, id: "../x" }).ok, false)
})
test("a plugin for a newer Ether Shell is refused, and says so", () => {
    const p = read("uptime", { ...good, api: API_VERSION + 1 })
    assert.equal(p.ok, false)
    assert.match(p.errors[0], /newer Ether Shell/)
    assert.equal(read("uptime", { ...good, api: undefined }).ok, false)
})
test("broken or empty plugin.json files get a plain reason", () => {
    assert.match(read("uptime", "{ not json").errors[0], /isn't valid JSON/)
    assert.match(read("uptime", "[1,2]").errors[0], /isn't an object/)
    assert.match(read("uptime", { id: "uptime", api: 1 }).errors[0], /doesn't add anything/)
    assert.equal(read("uptime", { ...good, bar: { file: "Bar.qml", side: "middle" } }).ok, false)
})
test("long names and descriptions are cut, not trusted", () => {
    const p = read("uptime", { ...good, name: "x".repeat(500), description: "y".repeat(5000) })
    assert.equal(p.name.length, 60); assert.equal(p.description.length, 300)
})
test("the shell's scan output: several plugins, sorted, each checked", () => {
    const out = "\x1euptime\x1f" + JSON.stringify(good) + "\x1ebroken\x1f{ nope" + "\x1eclock\x1f" + JSON.stringify({ ...good, id: "clock", name: "A clock" })
    const list = parseScan(out, D)
    assert.deepEqual(list.map(p => [p.id, p.ok]), [["clock", true], ["broken", false], ["uptime", true]])
    assert.deepEqual(parseScan("", D), [])
})
test("commands a plugin runs: a list of plain strings, never a shell line", () => {
    assert.ok(validCommand(["cat", "/proc/uptime"]))
    for (const bad of ["rm -rf ~", [], [""], [1, 2], ["a\0b"], null, ["x"].concat(Array(70).fill("y"))])
        assert.equal(validCommand(bad), false, JSON.stringify(bad))
})

test("every plugin shipped with Ether Shell passes the checker", async () => {
    const { readdirSync, readFileSync, existsSync } = await import("node:fs")
    const root = new URL("../plugins/", import.meta.url).pathname
    const folders = readdirSync(root).filter(d => existsSync(root + d + "/plugin.json"))
    assert.ok(folders.length >= 1)
    for (const d of folders) {
        const p = readManifest(d, readFileSync(root + d + "/plugin.json", "utf8"), root)
        assert.equal(p.ok, true, d + ": " + p.errors.join("; "))
        if (p.bar) assert.ok(existsSync(root + d + "/" + p.bar.file), d + ": its bar item's file is missing")
        if (p.launcher) assert.ok(existsSync(root + d + "/" + p.launcher.file), d + ": its launcher part's file is missing")
        if (p.widget) assert.ok(existsSync(root + d + "/" + p.widget.file), d + ": its widget's file is missing")
        if (p.settings) assert.ok(existsSync(root + d + "/" + p.settings.file), d + ": its settings' file is missing")
    }
})

import { prefixFor, cleanResult } from "../config/quickshell/lib/plugins.mjs"
const wiki = { id: "wikipedia", name: "Wikipedia", api: 1, launcher: { file: "Launcher.qml", prefix: "!w", title: "Wikipedia" } }

test("a launcher part is read, with its prefix and title", () => {
    const p = read("wikipedia", wiki)
    assert.equal(p.ok, true, p.errors.join("; "))
    assert.deepEqual(p.launcher, { file: "Launcher.qml", prefix: "!w", title: "Wikipedia" })
    assert.equal(read("wikipedia", { ...wiki, launcher: { file: "Launcher.qml" } }).launcher.prefix, "")   // no prefix: among the usual results
})
test("a prefix can't be one of the launcher's own, or long, or odd", () => {
    for (const prefix of ["=", ":x", ";", ">", "@a", "/f", "", "toolong7", "a b", "w\n"])
        assert.equal(read("wikipedia", { ...wiki, launcher: { file: "Launcher.qml", prefix } }).ok, false, JSON.stringify(prefix))
})
test("two plugins wanting the same prefix: the second is told", () => {
    const other = { ...wiki, id: "wiktionary", name: "Wiktionary" }
    const list = parseScan("\x1ewikipedia\x1f" + JSON.stringify(wiki) + "\x1ewiktionary\x1f" + JSON.stringify(other), D)
    assert.deepEqual(list.map(p => p.ok), [true, false])
    assert.match(list[1].errors[0], /already used by Wikipedia/)
})
test("which plugin a search is for: the longest prefix wins", () => {
    const ls = [{ id: "w", prefix: "!w" }, { id: "wd", prefix: "!wd" }, { id: "none", prefix: "" }]
    assert.deepEqual(prefixFor("!w linux", ls), { id: "w", term: "linux" })
    assert.deepEqual(prefixFor("!wd linux", ls), { id: "wd", term: "linux" })
    assert.equal(prefixFor("firefox", ls), null)
})
test("results are checked: a title, and only safe actions", () => {
    assert.equal(cleanResult({ subtitle: "no title" }), null)
    assert.equal(cleanResult("nope"), null)
    assert.equal(cleanResult({ title: "A", open: "https://en.wikipedia.org/wiki/A" }).open, "https://en.wikipedia.org/wiki/A")
    assert.equal(cleanResult({ title: "A", open: "javascript:alert(1)" }).open, undefined)
    assert.deepEqual(cleanResult({ title: "A", run: ["kitty", "-e", "man", "ls"] }).run, ["kitty", "-e", "man", "ls"])
    assert.equal(cleanResult({ title: "A", run: "rm -rf ~" }).run, undefined)
    assert.equal(cleanResult({ title: "x".repeat(900) }).title.length, 200)
})

test("a desktop widget and settings are read", () => {
    const m = { id: "countdown", name: "Countdown", api: 1,
                widget: { file: "Widget.qml", name: "Days until", description: "Counts down to a date" },
                settings: { file: "Settings.qml" } }
    const p = read("countdown", m)
    assert.equal(p.ok, true, p.errors.join("; "))
    assert.deepEqual(p.widget, { file: "Widget.qml", name: "Days until", description: "Counts down to a date" })
    assert.deepEqual(p.settings, { file: "Settings.qml" })
    assert.equal(read("countdown", { ...m, widget: { file: "Widget.qml" } }).widget.name, "Countdown")   // its own name, by default
})
test("a widget's or settings' file must be a .qml in its own folder", () => {
    for (const file of ["../w.qml", "sub/w.qml", "w.js", ""]) {
        assert.equal(read("countdown", { id: "countdown", api: 1, widget: { file } }).ok, false, "widget " + JSON.stringify(file))
        assert.equal(read("countdown", { id: "countdown", api: 1, widget: { file: "W.qml" }, settings: { file } }).ok, false, "settings " + JSON.stringify(file))
    }
})
test("settings alone don't make a plugin", () => {
    const p = read("countdown", { id: "countdown", api: 1, settings: { file: "Settings.qml" } })
    assert.equal(p.ok, false)
    assert.match(p.errors[0], /doesn't add anything/)
})
