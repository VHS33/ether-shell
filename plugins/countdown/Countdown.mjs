// The counting, shared by the widget and its settings (and tested on its own).

// "2026-12-25" -> a Date at the start of that day, or null
export function parseDay(s) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || "").trim())
    if (!m) return null
    const d = new Date(+m[1], +m[2] - 1, +m[3])
    return d.getMonth() === +m[2] - 1 && d.getDate() === +m[3] ? d : null      // no 31 February
}
// whole days from `now`'s day to `day` (0: today; negative: gone by)
export function daysUntil(day, now) {
    const a = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    return Math.round((day - a) / 86400000)
}
// the next New Year's Day, the default
export function nextNewYear(now) {
    return String(now.getFullYear() + 1) + "-01-01"
}
