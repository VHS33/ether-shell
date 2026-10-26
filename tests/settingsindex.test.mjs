// Every setting, read from Settings' page files (config/quickshell/lib/settingsindex.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { PAGES, parsePage, switchOf, isOn, row } from "../config/quickshell/lib/settingsindex.mjs"
import { search } from "../config/quickshell/lib/search.mjs"

const here = path.dirname(fileURLToPath(import.meta.url))
const pagesDir = path.join(here, "..", "config", "quickshell", "modules", "settings")
const read = f => fs.readFileSync(path.join(pagesDir, f + ".qml"), "utf8")
const all = () => PAGES.flatMap(p => parsePage(read(p.f)).entries)

const SAMPLE = `
import QtQuick
ColumnLayout {
    id: page
    readonly property int pageNo: 11
    visible: settingsWin.page === pageNo
    SectionLabel { app: settingsRoot.app; text: "Pointer" }
    Card {
        app: settingsRoot.app
        title: "Natural scrolling"
        desc: "Content moves the way your finger does \\u2014 like a phone."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.naturalScroll === true ? 1 : 0
                onPicked: i => app.setting("naturalScroll", i === 1)
            }
        ]
    }
    // Card { title: "Commented out" }
    Card {
        title: app.monName + " settings"
    }
    SectionLabel {
        app: settingsRoot.app
        text: "More"
    }
    Card {
        title: "Speed"
        visible: app.featureOn
        Seg { options: ["Slow", "Fast"]; onPicked: i => app.setting("speed", i) }
    }
    Card {
        title: "Nothing here"
        searchable: false
    }
    Repeater {
        model: 3
        delegate: Card { title: "A copy" }
    }
}`

test("a page: sections, cards, what's left out", () => {
    const r = parsePage(SAMPLE)
    assert.equal(r.pageNo, 11)
    assert.deepEqual(r.entries.map(e => e.title), ["Natural scrolling", "Speed"])
    const [a, b] = r.entries
    assert.equal(a.section, "Pointer")
    assert.equal(a.page, "Mouse")
    assert.equal(a.glyph, "mouse")
    assert.equal(a.desc, "Content moves the way your finger does — like a phone.")
    assert.deepEqual(a.sw, { key: "naturalScroll", read: { kind: "cfgTrue", name: "naturalScroll" } })
    // a section label over more than one line; a card that only shows sometimes is still found
    assert.equal(b.section, "More")
    assert.equal(b.sw, undefined)                       // more than on/off: it only opens Settings
})

test("on/off switches: only the plain ones", () => {
    const seg = (cur, pick, opts = '["Off", "On"]') =>
        `Card { title: "x"\n Seg {\n options: ${opts}\n current: ${cur}\n onPicked: ${pick}\n }\n}`
    const p = 'i => app.setting("k", i === 1)'
    assert.deepEqual(switchOf(seg("app.cfg.k === true ? 1 : 0", p)).read, { kind: "cfgTrue", name: "k" })
    assert.deepEqual(switchOf(seg("app.cfg.k !== false ? 1 : 0", p)).read, { kind: "cfgNotFalse", name: "k" })
    assert.deepEqual(switchOf(seg("app.barNet ? 1 : 0", p)).read, { kind: "app", name: "barNet" })
    // not plain: more choices, other steps, a different key read, reversed
    assert.equal(switchOf(seg("app.cfg.k === true ? 1 : 0", p, '["Off", "On", "Auto"]')), null)
    assert.equal(switchOf(seg("app.cfg.k === true ? 1 : 0", 'i => { app.setting("k", i === 1); app.go() }')), null)
    assert.equal(switchOf(seg("app.cfg.other === true ? 1 : 0", p)), null)
    assert.equal(switchOf(seg("app.cfg.k === false ? 1 : 0", p)), null)
    assert.equal(switchOf(seg("app.cfg.k === true ? 1 : 0", 'i => app.setting("k", i === 0)')), null)
    assert.equal(switchOf("Card { title: \"x\" }"), null)
})

test("whether a switch is on", () => {
    const t = { read: { kind: "cfgTrue", name: "k" } }, nf = { read: { kind: "cfgNotFalse", name: "k" } }
    assert.equal(isOn(t, { cfg: {} }), false)
    assert.equal(isOn(t, { cfg: { k: true } }), true)
    assert.equal(isOn(nf, { cfg: {} }), true)                 // on by default
    assert.equal(isOn(nf, { cfg: { k: false } }), false)
    assert.equal(isOn({ read: { kind: "app", name: "barNet" } }, { barNet: true, cfg: {} }), true)
    assert.equal(isOn(null, {}), false)
    const r = row(parsePage(SAMPLE).entries[0], { cfg: { naturalScroll: true } })
    assert.equal(r.kind, "setting")
    assert.equal(r.sub, "Mouse  ›  Pointer")
    assert.equal(r.badge, "On")
    assert.equal(row(parsePage(SAMPLE).entries[1], { cfg: {} }).badge, undefined)
})

test("the real pages: each file is there, at its page number", () => {
    assert.equal(PAGES.length, 26)
    PAGES.forEach((p, i) => {
        assert.ok(fs.existsSync(path.join(pagesDir, p.f + ".qml")), p.f + ".qml is missing")
        assert.equal(parsePage(read(p.f)).pageNo, i, p.f + " has a different pageNo from its place in PAGES")
    })
    // and every page file in the folder is one of them
    const files = fs.readdirSync(pagesDir).filter(f => /^Page.*\.qml$/.test(f)).map(f => f.slice(0, -4)).sort()
    assert.deepEqual(files, PAGES.map(p => p.f).sort())
})

test("the real pages: settings are found, messages aren't", () => {
    const es = all()
    assert.ok(es.length >= 90, "only " + es.length + " settings found")
    const find = (page, title) => es.find(e => e.page === page && e.title === title)
    assert.ok(find("Mouse", "Cursor size"))
    assert.ok(find("General", "Font"))
    assert.ok(find("Game overlay", "Layout"))           // only shows while the overlay is on: still found
    assert.equal(find("Mouse", "Natural scrolling").sw.key, "naturalScroll")
    for (const t of ["Nothing is playing", "No app is recording", "No widgets yet",
                     "MangoHud isn't installed", "Restart Steam once", "Keep these display settings?"])
        assert.equal(es.find(e => e.title === t), undefined, t + " is a message, not a setting")
    // no setting twice on one page
    const keys = es.map(e => e.pageNo + ":" + e.title.toLowerCase())
    assert.equal(new Set(keys).size, keys.length)
})

test("the real pages: every switch saves a real setting", () => {
    const shell = fs.readFileSync(path.join(here, "..", "config", "quickshell", "shell.qml"), "utf8")
    const sws = all().filter(e => e.sw)
    assert.ok(sws.length >= 10, "only " + sws.length + " switches found")
    for (const e of sws) {
        // what an "app" switch reads is one of the shell's own properties
        if (e.sw.read.kind === "app")
            assert.match(shell, new RegExp("property\\s+\\w+\\s+" + e.sw.read.name + "\\b"), e.title + ": app." + e.sw.read.name + " isn't in shell.qml")
    }
})

test("searching them", () => {
    const es = all()
    assert.equal(search(es, "cursor size")[0].title, "Cursor size")
    assert.equal(search(es, "natural scroll")[0].title, "Natural scrolling")
    assert.ok(search(es, "zzzzqqq").length === 0)
})
