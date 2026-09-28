// colour.mjs  (Ether Shell)
// The colour rules, in one place: the shell imports this, and the tests run
// it with Node.  setwall's awk readable() is the same calculation, step for
// step (the tests check they agree), so the shell and every app always get
// the same accent.  Colours in and out are "#rrggbb" strings ("#aarrggbb",
// as Qt writes a colour with transparency, is read too; the alpha is
// ignored).

export function rgbOf(hex) {
    let h = String(hex).trim().replace(/^#/, "")
    if (h.length === 8) h = h.slice(2)                       // Qt's #aarrggbb
    if (h.length === 3) h = h.split("").map(c => c + c).join("")
    if (!/^[0-9a-fA-F]{6}$/.test(h)) throw new Error("not a colour: " + hex)
    return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16) }
}
export function hexOf(rgb) {
    const two = v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")
    return "#" + two(rgb.r) + two(rgb.g) + two(rgb.b)
}

// WCAG relative luminance, and the contrast ratio of two colours
export function luminance(hex) {
    const { r, g, b } = rgbOf(hex)
    const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
export function contrast(a, b) {
    const la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// HSL, with hue -1 for greys (as Qt reports it)
export function hslOf(hex) {
    const { r, g, b } = rgbOf(hex)
    const R = r / 255, G = g / 255, B = b / 255
    const mx = Math.max(R, G, B), mn = Math.min(R, G, B), l = (mx + mn) / 2
    if (mx === mn) return { h: -1, s: 0, l }
    const d = mx - mn
    const s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    let h = mx === R ? (G - B) / d + (G < B ? 6 : 0) : mx === G ? (B - R) / d + 2 : (R - G) / d + 4
    return { h: h / 6, s, l }
}
export function fromHsl(h, s, l) {
    if (s === 0 || h < 0) { const v = Math.round(l * 255); return hexOf({ r: v, g: v, b: v }) }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    const hue = t => { if (t < 0) t += 1; if (t > 1) t -= 1
        return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p }
    return hexOf({ r: Math.round(hue(h + 1 / 3) * 255), g: Math.round(hue(h) * 255), b: Math.round(hue(h - 1 / 3) * 255) })
}

// The accent rule: the colour as it is, or lightened (darkened, on a light
// background) one step at a time, keeping its hue, just until it reads at
// 4.5:1 on the background.
export function readableAccent(colour, bg) {
    if (contrast(colour, bg) >= 4.5) return hexOf(rgbOf(colour))
    const dark = luminance(bg) < 0.18
    const { h, s } = hslOf(colour)
    let l = hslOf(colour).l, t = hexOf(rgbOf(colour))
    for (let i = 0; i < 100; i++) {         // the whole range: black or white always reads
        l = dark ? Math.min(1, l + 0.01) : Math.max(0, l - 0.01)
        t = fromHsl(h < 0 ? 0 : h, s, l)
        if (contrast(t, bg) >= 4.5) break
    }
    return t
}

// dark or light text on a colour, whichever reads better
export function textOn(colour, darkText, lightText) {
    return contrast(colour, darkText) >= contrast(colour, lightText) ? darkText : lightText
}

// The shell's third accent when the picture's own colours aren't in the
// theme yet: its second colour, or a close neighbour of the main one, at
// the palette's third-accent lightness.  (Monochrome and neutral keep their
// greys; without the smart colour, Material's own.)
export function thirdAccent(primary, tertiary, second, scheme, smart) {
    if (!smart || scheme === "scheme-monochrome" || scheme === "scheme-neutral") return hexOf(rgbOf(tertiary))
    const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
    const t = hslOf(tertiary)
    if (second) {
        const s2 = hslOf(second)
        if (s2.h >= 0) return fromHsl(s2.h, clamp(s2.s, 0.3, 0.62), t.l)
    }
    const p = hslOf(primary)
    if (p.h < 0) return hexOf(rgbOf(tertiary))
    return fromHsl((p.h + 28 / 360) % 1, clamp(Math.min(p.s, t.s + 0.15), 0.25, 0.6), t.l)
}
