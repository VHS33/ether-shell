// Keys for lists that update in place (config/quickshell/lib/models.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { keyed } from "../config/quickshell/lib/models.mjs"

test("every item gets its key, the rest of it unchanged", () => {
    const out = keyed([{ id: "a", n: 1 }, { id: "b", n: 2 }], x => x.id)
    assert.deepEqual(out, [{ id: "a", n: 1, _key: "a" }, { id: "b", n: 2, _key: "b" }])
})
test("repeats are numbered, so every key is unique", () => {
    const out = keyed([{ name: "chrome" }, { name: "kitty" }, { name: "chrome" }, { name: "chrome" }], x => x.name)
    assert.deepEqual(out.map(x => x._key), ["chrome", "kitty", "chrome#1", "chrome#2"])
    assert.equal(new Set(out.map(x => x._key)).size, out.length)
})
test("the same list gives the same keys (so nothing is rebuilt)", () => {
    const list = [{ name: "chrome" }, { name: "chrome" }]
    assert.deepEqual(keyed(list, x => x.name), keyed(list.map(x => Object.assign({}, x)), x => x.name))
})
test("the original items aren't changed", () => {
    const item = { id: "a" }
    keyed([item], x => x.id)
    assert.deepEqual(item, { id: "a" })
})
test("nothing, or an empty list, gives an empty list", () => {
    assert.deepEqual(keyed(undefined, x => x), [])
    assert.deepEqual(keyed([], x => x), [])
})
