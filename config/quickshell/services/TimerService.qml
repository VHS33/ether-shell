pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The timer and stopwatch: start, pause, resume, cancel; the time left and
// the time counted; "5m", "1h 30m" and the like understood; and, when a
// timer ends, a sound and a notification (or the island).  Use it anywhere
// as TimerService.timerLeft, .startTimer(sec)... (import qs.services).
//
// The shell passes in whether the island is on (islandOn) and shows the
// finished timer there (finishedForIsland).  Nothing here goes over the
// network.
Singleton {
    id: timerSvc

    property bool islandOn: false
    signal finishedForIsland(string len)

    property double timerEnd: 0          // when a running timer ends (ms)
    property int timerTotal: 0           // its length (s)
    property int timerHeld: 0            // seconds left while paused
    property int timerLeft: 0            // seconds left, for showing
    readonly property bool timerOn: timerEnd > 0 || timerHeld > 0
    readonly property bool timerPaused: timerEnd === 0 && timerHeld > 0
    property double swStart: 0           // when the stopwatch last started (ms)
    property double swBanked: 0          // time counted before that (ms)
    property bool swRunning: false
    property double swMs: 0              // elapsed, for showing
    readonly property bool swOn: swRunning || swBanked > 0

    function startTimer(sec) {
        sec = Math.max(1, Math.round(sec))
        timerTotal = sec
        timerHeld = 0
        timerEnd = Date.now() + sec * 1000
        timerLeft = sec
    }
    function pauseTimer() {
        if (timerEnd === 0) return
        timerHeld = Math.max(1, Math.ceil((timerEnd - Date.now()) / 1000))
        timerEnd = 0
    }
    function resumeTimer() {
        if (timerHeld <= 0) return
        timerEnd = Date.now() + timerHeld * 1000
        timerHeld = 0
    }
    function cancelTimer() { timerEnd = 0; timerHeld = 0; timerLeft = 0; timerTotal = 0 }
    function swToggle() {
        if (swRunning) { swBanked += Date.now() - swStart; swRunning = false }
        else { swStart = Date.now(); swRunning = true }
        swMs = swBanked
    }
    function swReset() { swRunning = false; swBanked = 0; swMs = 0 }
    // 75 -> "1:15", 3700 -> "1:01:40"
    function fmtDur(sec) {
        sec = Math.max(0, Math.floor(sec))
        const h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, x = sec % 60
        const p = v => (v < 10 ? "0" : "") + v
        return h > 0 ? h + ":" + p(m) + ":" + p(x) : m + ":" + p(x)
    }
    // "5m", "90s", "1h 30m", "2.5m" -> seconds; 0 when it isn't a length
    function parseDur(t) {
        let total = 0, found = false
        const re = /(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)?/gi
        let m
        while ((m = re.exec(t)) !== null) {
            if (m[0].trim() === "") { re.lastIndex++; continue }
            const n = parseFloat(m[1]), u = (m[2] || "m").toLowerCase()
            total += u.startsWith("h") ? n * 3600 : u.startsWith("s") ? n : n * 60
            found = true
        }
        return found ? Math.round(total) : 0
    }
    Timer {
        interval: 200
        repeat: true
        running: timerSvc.timerEnd > 0 || timerSvc.swRunning
        onTriggered: {
            const now = Date.now()
            if (timerSvc.timerEnd > 0) {
                timerSvc.timerLeft = Math.max(0, Math.ceil((timerSvc.timerEnd - now) / 1000))
                if (now >= timerSvc.timerEnd) timerSvc.timerDone()
            }
            if (timerSvc.swRunning) timerSvc.swMs = timerSvc.swBanked + now - timerSvc.swStart
        }
    }
    function timerDone() {
        const len = timerTotal
        cancelTimer()
        // in the island if it's there (it says so itself); otherwise a notification
        if (timerSvc.islandOn) timerSvc.finishedForIsland(fmtDur(len))
        timerAlert.command = ["sh", "-c",
            (timerSvc.islandOn ? '' : 'notify-send -a Timer -u critical -i alarm "Time\'s up" "Your $1 timer has finished"; ') +
            'for f in /usr/share/sounds/freedesktop/stereo/complete.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do ' +
            '[ -f "$f" ] && { pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null; break; }; done',
            "sh", fmtDur(len)]
        timerAlert.running = true
    }
    Process { id: timerAlert }
}
