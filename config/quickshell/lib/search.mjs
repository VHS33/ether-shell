// search.mjs  (Ether Shell)
// Searching Settings: which settings match what's typed, best first.  Every
// word typed has to match somewhere in a setting: its title counts most,
// then the page and section it's on, then its description.  A word matches
// the whole of a word or its start ("refr" finds "refresh"); words of four
// letters or more forgive one typo.  Settings imports this; the tests run it.
import { oneTypo } from "./text.mjs"

export function words(s) {
    return String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
        .split(/[^a-z0-9]+/).filter(Boolean)
}

// how well one typed word matches one word of a setting (0: not at all)
function wordScore(q, w) {
    if (w === q) return 3
    if (w.startsWith(q)) return 2
    if (q.length >= 4 && (oneTypo(q, w) || oneTypo(q, w.slice(0, q.length)))) return 1
    if (q.length >= 3 && w.includes(q)) return 0.5
    return 0
}
function best(q, ws) { let s = 0; for (const w of ws) s = Math.max(s, wordScore(q, w)); return s }

// entry: { title, desc, page, section }; 0 when it doesn't match
export function scoreSetting(entry, query) {
    const qs = words(query)
    if (!qs.length) return 0
    const t = words(entry.title), where = words(entry.page).concat(words(entry.section)), d = words(entry.desc)
    let total = 0
    for (const q of qs) {
        const s = Math.max(best(q, t) * 3, best(q, where) * 1.5, best(q, d))
        if (s === 0) return 0
        total += s
    }
    return total
}

// the matching entries, best first (ties keep Settings' own order)
export function search(entries, query, limit = 40) {
    return entries.map((e, i) => ({ e, i, s: scoreSetting(e, query) }))
        .filter(r => r.s > 0)
        .sort((a, b) => b.s - a.s || a.i - b.i)
        .slice(0, limit)
        .map(r => r.e)
}
