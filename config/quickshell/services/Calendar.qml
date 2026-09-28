pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The calendar's content: the month's days (calCells, for the month the
// shell passes in as monthOffset), public holidays, notes on days (once or
// every year: ~/.config/quickshell/day-notes.json), and marked days
// (~/.config/quickshell/marked-days.txt).  Use it anywhere as
// Calendar.calCells, .setDayNote(...)... (import qs.services).  Nothing
// here goes over the network.
Singleton {
    id: calSvc

    property int monthOffset: 0

    readonly property string notesPath: Quickshell.env("HOME") + "/.config/quickshell/marked-days.txt"
    property var markedDays: []

    // Major US holidays, worked out per year: fixed dates, "nth weekday
    // of the month" ones, and Easter.  Keyed "MM-DD".
    property var holCache: ({})
    readonly property bool calHolidays: Config.cfg.calHolidays !== false
    readonly property int calWeekStart: Config.cfg.calWeekStart === 1 ? 1 : 0   // 0 Sunday, 1 Monday
    function holidaysFor(y) {
        if (holCache[y]) return holCache[y]
        const out = {}
        const pad = n => (n < 10 ? "0" : "") + n
        const add = (m, d, name) => {
            const k = pad(m + 1) + "-" + pad(d)
            out[k] = out[k] ? out[k] + " and " + name : name
        }
        // nth weekday (0 Sun .. 6 Sat) of month m; n = -1 for the last
        const nth = (m, wd, n) => {
            if (n > 0) {
                const first = new Date(y, m, 1).getDay()
                return 1 + (wd - first + 7) % 7 + (n - 1) * 7
            }
            const lastD = new Date(y, m + 1, 0).getDate()
            const lastWd = new Date(y, m, lastD).getDay()
            return lastD - (lastWd - wd + 7) % 7
        }
        // Easter Sunday (anonymous Gregorian algorithm)
        const a = y % 19, b = Math.floor(y / 100), c = y % 100
        const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
        const g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
        const i = Math.floor(c / 4), k = c % 4
        const l = (32 + 2 * e + 2 * i - h - k) % 7
        const mm = Math.floor((a + 11 * h + 22 * l) / 451)
        const eMonth = Math.floor((h + l - 7 * mm + 114) / 31) - 1
        const eDay = ((h + l - 7 * mm + 114) % 31) + 1

        add(0, 1,  "New Year's Day")
        add(0, nth(0, 1, 3),  "Martin Luther King Jr. Day")
        add(1, 14, "Valentine's Day")
        add(1, nth(1, 1, 3),  "Presidents' Day")
        add(2, 17, "St. Patrick's Day")
        add(eMonth, eDay, "Easter")
        add(4, nth(4, 0, 2),  "Mother's Day")
        add(4, nth(4, 1, -1), "Memorial Day")
        add(5, nth(5, 0, 3),  "Father's Day")
        add(5, 19, "Juneteenth")
        add(6, 4,  "Independence Day")
        add(8, nth(8, 1, 1),  "Labor Day")
        add(9, nth(9, 1, 2),  "Indigenous Peoples' Day")
        add(9, 31, "Halloween")
        add(10, 11, "Veterans Day")
        add(10, nth(10, 4, 4), "Thanksgiving")
        add(11, 24, "Christmas Eve")
        add(11, 25, "Christmas Day")
        add(11, 31, "New Year's Eve")

        // stored by mutation, not reassignment: this runs inside the
        // calCells binding, and reassigning would make it re-run forever
        holCache[y] = out
        return out
    }
    function holidayOn(key) {
        if (!calHolidays) return ""
        return holidaysFor(parseInt(key.slice(0, 4)))[key.slice(5)] ?? ""
    }

    // ---- day notes ---------------------------------------------------
    // ~/.config/quickshell/day-notes.json:
    //   { "once":   { "2026-10-04": "Dentist" },
    //     "yearly": { "04-02": "Anniversary of 2001: A Space Odyssey" } }
    // A missing file starts with the April 2 note; once the file exists
    // it's whatever you've kept.
    readonly property var notesSeed: ({
        once: {},
        yearly: { "04-02": "Anniversary of 2001: A Space Odyssey (premiered 2 April 1968)" }
    })
    property var dayNotes: notesSeed

    Process {
        id: dayNotesRead
        running: true
        command: ["sh", "-c", "cat ~/.config/quickshell/day-notes.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) return
                try {
                    const o = JSON.parse(t)
                    calSvc.dayNotes = { once: o.once || {}, yearly: o.yearly || {} }
                } catch (e) {
                    console.log("day-notes.json parse failed, keeping defaults:", e)
                }
            }
        }
    }
    Process { id: dayNotesWrite }
    function saveDayNotes() {
        dayNotesWrite.command = ["sh", "-c",
            'f="$HOME/.config/quickshell/day-notes.json"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
            "sh", JSON.stringify(dayNotes, null, 2) + "\n"]
        dayNotesWrite.running = true
    }

    // every note on a day, yearly ones first: [{ text, yearly }]
    function notesOn(key) {
        const out = []
        const y = dayNotes.yearly[key.slice(5)]
        if (y) out.push({ text: y, yearly: true })
        const o = dayNotes.once[key]
        if (o) out.push({ text: o, yearly: false })
        return out
    }
    function setDayNote(key, text, yearly) {
        const t = text.trim()
        if (t === "") return
        const n = JSON.parse(JSON.stringify(dayNotes))
        if (yearly) n.yearly[key.slice(5)] = t
        else n.once[key] = t
        dayNotes = n
        saveDayNotes()
    }
    function deleteDayNote(key, yearly) {
        const n = JSON.parse(JSON.stringify(dayNotes))
        if (yearly) delete n.yearly[key.slice(5)]
        else delete n.once[key]
        dayNotes = n
        saveDayNotes()
    }

    readonly property var calBase: {
        const n = new Date()
        return new Date(n.getFullYear(), n.getMonth() + calSvc.monthOffset, 1)
    }

    readonly property var calCells: {
        const base = calSvc.calBase
        const y = base.getFullYear(), mo = base.getMonth()
        // days shown before the 1st, counting from the chosen week start
        const firstDow = (new Date(y, mo, 1).getDay() - calSvc.calWeekStart + 7) % 7
        const inMonth = new Date(y, mo + 1, 0).getDate()
        const prevLen = new Date(y, mo, 0).getDate()
        const now = new Date()
        const pad = n => (n < 10 ? "0" + n : "" + n)
        const key = (yy, mm, dd) => yy + "-" + pad(mm + 1) + "-" + pad(dd)

        const cells = []
        for (let i = firstDow - 1; i >= 0; i--) {
            const d = prevLen - i
            const pm = mo === 0 ? 11 : mo - 1
            const py = mo === 0 ? y - 1 : y
            const kk = key(py, pm, d)
            cells.push({ d: d, cur: false, today: false, key: kk,
                         hol: holidayOn(kk), noted: notesOn(kk).length > 0 })
        }
        for (let i = 1; i <= inMonth; i++) {
            const kk = key(y, mo, i)
            cells.push({
                d: i, cur: true,
                today: i === now.getDate() && mo === now.getMonth() && y === now.getFullYear(),
                key: kk, hol: holidayOn(kk), noted: notesOn(kk).length > 0
            })
        }
        let nx = 1
        while (cells.length < 42) {
            const nm = mo === 11 ? 0 : mo + 1
            const ny = mo === 11 ? y + 1 : y
            const kk = key(ny, nm, nx)
            cells.push({ d: nx, cur: false, today: false, key: kk,
                         hol: holidayOn(kk), noted: notesOn(kk).length > 0 })
            nx++
        }
        return cells
    }

    function saveMarks() {
        saveProc.command = ["sh", "-c",
            "printf '%s' '" + calSvc.markedDays.join(",") + "' > '" + calSvc.notesPath + "'"]
        saveProc.running = true
    }
    Process { id: saveProc }
    Process {
        id: loadProc
        command: ["sh", "-c", "cat '" + calSvc.notesPath + "' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                calSvc.markedDays = t.length ? t.split(",").filter(s => s.length) : []
            }
        }
    }
    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: loadProc.running = true
    }
}
