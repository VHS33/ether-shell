// The launcher's text rules (config/quickshell/lib/text.mjs).
import { test } from "node:test"
import assert from "node:assert/strict"
import { oneTypo, calc } from "../config/quickshell/lib/text.mjs"

test("one typo: wrong, missing, extra or swapped letter", () => {
    assert.ok(oneTypo("firefox", "firefox"))
    assert.ok(oneTypo("firefox", "firefix"))     // wrong
    assert.ok(oneTypo("firefox", "firefx"))      // missing
    assert.ok(oneTypo("firefox", "fireffox"))    // extra
    assert.ok(oneTypo("firefox", "fierfox"))     // swapped
    assert.ok(!oneTypo("firefox", "fiefx"))      // two
    assert.ok(!oneTypo("kitty", "dolphin"))
})
test("the calculator", () => {
    assert.equal(calc("2+2"), "4")
    assert.equal(calc("2 ^ 10"), "1024")
    assert.equal(calc("sqrt(16) + 1"), "5")
    assert.equal(calc("0.1+0.2"), "0.3")          // not 0.30000000000000004
    assert.equal(calc("3,5*2"), "7")               // a comma for a decimal point
    assert.equal(calc("1/0"), null)
    assert.equal(calc(""), null)
})
test("the calculator refuses anything that isn't maths", () => {
    // it evaluates what's typed, so nothing else may ever get through
    for (const bad of ["alert(1)", "process.exit()", "this", "constructor", "x=1", "[]+{}", "a;b", "`1`", "'1'"])
        assert.equal(calc(bad), null, bad)
})
