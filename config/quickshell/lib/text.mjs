// text.mjs  (Ether Shell)
// The launcher's text rules: typo-tolerant matching and the calculator.
// The launcher imports this; the tests run it with Node.

// one wrong, missing, extra or swapped letter
export function oneTypo(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false
    let i = 0
    while (i < a.length && i < b.length && a[i] === b[i]) i++
    if (i === a.length && i === b.length) return true
    const rest = (x, y) => a.slice(x) === b.slice(y)
    return rest(i + 1, i + 1) || rest(i + 1, i) || rest(i, i + 1)
        || (a[i] === b[i + 1] && a[i + 1] === b[i] && rest(i + 2, i + 2))
}

// maths: only numbers, operators, brackets and a few named functions ever
// reach the evaluator; anything else gives null
export function calc(expr) {
    let e = String(expr).trim().toLowerCase().replace(/\s+/g, "")
    if (!e.length) return null
    if (!/^[0-9+\-*/%^().,a-z]*$/.test(e)) return null
    const fns = { sqrt: "Math.sqrt", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan",
                  log: "Math.log10", ln: "Math.log", abs: "Math.abs", round: "Math.round",
                  floor: "Math.floor", ceil: "Math.ceil", pi: "Math.PI", e: "Math.E" }
    const words = e.match(/[a-z]+/g) || []
    for (const w of words) if (!(w in fns)) return null
    e = e.replace(/[a-z]+/g, w => fns[w]).replace(/\^/g, "**").replace(/,/g, ".")
    try {
        const v = Function('"use strict"; return (' + e + ')')()
        if (typeof v !== "number" || !isFinite(v)) return null
        return Number.isInteger(v) ? String(v) : String(parseFloat(v.toPrecision(12)))
    } catch (err) { return null }
}
