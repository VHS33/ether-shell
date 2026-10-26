// Your windows in the launcher (config/quickshell/lib/windows.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { score, match, wsLabel, row, summary, command } from "../config/quickshell/lib/windows.mjs"

const W = [
    { addr: "0xa1", cls: "firefox", name: "Firefox", title: "Ether Shell · GitHub", ws: 2, mon: "DP-1", icon: "firefox", entry: "firefox.desktop" },
    { addr: "0xa2", cls: "firefox", name: "Firefox", title: "YouTube", ws: 5, mon: "HDMI-A-1", icon: "firefox", entry: "firefox.desktop" },
    { addr: "0xb1", cls: "kitty", name: "kitty", title: "~/ether-shell", ws: 1, mon: "DP-1", focused: true },
    { addr: "0xc1", cls: "discord", name: "Discord", title: "#general", ws: 3, mon: "DP-1" },
    { addr: "0xd1", cls: "org.kde.dolphin", name: "Dolphin", title: "Downloads", ws: -98, wsName: "special:magic", mon: "DP-1" },
]

test("matching: app name first, then words, title, anywhere", () => {
    assert.equal(score(W[0], "fire"), 100)
    assert.equal(score(W[4], "dol"), 100)                 // the app's name, though its class is org.kde.dolphin
    assert.equal(score(W[0], "github"), 60)               // its title
    assert.equal(score(W[3], "gen"), 60)
    assert.equal(score(W[2], "itt"), 50)
    assert.equal(score(W[1], "zzz"), 0)
    assert.equal(score(W[1], ""), 1)
    assert.equal(score(W[1], "  FIRE "), 100)             // case and spaces don't matter
})

test("best first, the window you're on last, then by workspace", () => {
    assert.deepEqual(match(W, "fire").map(w => w.addr), ["0xa1", "0xa2"])
    // nothing typed: all of them, by workspace, the one you're on last
    assert.deepEqual(match(W, "").map(w => w.addr), ["0xd1", "0xa1", "0xc1", "0xa2", "0xb1"])
    const all = match(W, "")
    assert.equal(all[all.length - 1].addr, "0xb1")        // the focused one, last
    assert.equal(match(W, "fire", 1).length, 1)
    assert.deepEqual(match([], "x"), [])
    assert.deepEqual(match(undefined, "x"), [])
})

test("rows: name, title, where it is", () => {
    const r = row(W[0])
    assert.equal(r.kind, "win")
    assert.equal(r.title, "Firefox  —  Ether Shell · GitHub")
    assert.equal(r.sub, "Workspace 2  •  DP-1")
    assert.equal(r.badge, "WS 2")
    assert.equal(r.addr, "0xa1")
    assert.match(row(W[2]).sub, /the window you're on/)
    assert.equal(row(W[3], "winclose").title, "Close Discord  —  #general")
    // a hidden (special) workspace: named, no badge
    assert.equal(wsLabel(W[4]), "Hidden workspace (magic)")
    assert.equal(row(W[4]).badge, "")
    // the app's name isn't repeated at the end of the title
    assert.equal(row({ addr: "x", name: "Firefox", title: "YouTube — Mozilla Firefox", ws: 5 }).title, "Firefox  —  YouTube")
    assert.equal(row({ addr: "x", name: "Dolphin", title: "Downloads — Dolphin", ws: 4 }).title, "Dolphin  —  Downloads")
    assert.equal(row({ addr: "x", name: "Code", title: "main.rs - glassly - Visual Studio Code", ws: 4 }).title, "Code  —  main.rs - glassly")
    // only the app's own name is taken off, nothing else after a dash
    assert.equal(row({ addr: "x", name: "kitty", title: "nvim - notes.md", ws: 1 }).title, "kitty  —  nvim - notes.md")
    // a title the same as the name isn't repeated
    assert.equal(row({ addr: "x", name: "Steam", title: "Steam", ws: 4 }).title, "Steam")
    assert.equal(row({ addr: "x", cls: "foo", ws: 4 }).title, "foo")
})

test("what's on a workspace", () => {
    assert.equal(summary(W, 2, "DP-1"), "Firefox  •  DP-1")
    assert.equal(summary(W, 7), "Empty")
    const many = [1, 2, 3, 4, 5].map(i => ({ name: "App" + i, ws: 6 }))
    assert.equal(summary(many, 6), "App1, App2, App3 and 2 more")
})

test("plain words", () => {
    assert.deepEqual(command("ws 3"), { type: "go", ws: 3 })
    assert.deepEqual(command("ws3"), { type: "go", ws: 3 })
    assert.deepEqual(command("Workspace 10"), { type: "go", ws: 10 })
    assert.deepEqual(command("go to workspace 2"), { type: "go", ws: 2 })
    assert.deepEqual(command("move 4"), { type: "move", ws: 4 })
    assert.deepEqual(command("move to 4"), { type: "move", ws: 4 })
    assert.deepEqual(command("move to workspace 4"), { type: "move", ws: 4 })
    assert.deepEqual(command("  move   to   ws 4 "), { type: "move", ws: 4 })
    assert.deepEqual(command("close discord"), { type: "close", what: "discord" })
    assert.deepEqual(command("focus firefox"), { type: "focus", what: "firefox" })
    assert.deepEqual(command("switch to kitty"), { type: "focus", what: "kitty" })
    assert.deepEqual(command("go to firefox"), { type: "focus", what: "firefox" })
    // not commands: searched as usual
    assert.equal(command("firefox"), null)
    assert.equal(command("ws 0"), null)
    assert.equal(command("ws 123"), null)
    assert.equal(command("move"), null)
    assert.equal(command("close"), null)
    assert.equal(command("workspaces"), null)
    assert.equal(command(""), null)
})
