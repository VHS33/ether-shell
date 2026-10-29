import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
// its own folder (LockView, LockChip): loaded by path from shell.qml, it
// doesn't see them otherwise
import qs.modules.lock

// ============================================================
//   THE LOCK SCREEN
//   Drawn by the shell itself, on every screen, through the Wayland
//   session lock: while it's locked the compositor shows nothing else and
//   sends no input anywhere else.  Your password is checked through PAM,
//   the same way you log in (/etc/pam.d/login).
//
//   If the shell stops while locked, the screens stay locked (that's what
//   makes it safe): Hyprland is told to let a new lock take over
//   (misc.allow_session_lock_restore), and the shell, started again,
//   finds the mark it left and locks straight away.
//
//     qs ipc call lock lock        lock now
//     qs ipc call lock isLocked    true or false
//
//   The typed password lives only here, in memory, while you type, and is
//   cleared as soon as it's been checked.  Nothing goes over the network.
// ============================================================
Scope {
    id: lockRoot
    property var app

    // Locked or not, kept here: Quickshell 0.3.2 doesn't announce an unlock
    // (its WlSessionLock.locked doesn't signal the change), so nothing may
    // wait on that
    property bool isLocked: false
    readonly property bool locked: isLocked
    // what's typed, shared by every screen (typing on any of them adds to it)
    property string buffer: ""
    property bool busy: false            // checking it
    property string message: ""          // "Wrong password", or what PAM says
    property bool messageIsError: false
    property int fails: 0
    property bool capsLock: false
    signal wrong()                       // a wrong password: the field shakes
    // The verdict, shown on the password marks for a moment: "ok" (green,
    // "Authenticated", then it unlocks) or "fail" (red, "Authentication
    // failed").  heldLen keeps the marks on screen meanwhile; the password
    // itself is already gone from memory.
    property string result: ""
    property int heldLen: 0
    Timer { id: okHold; interval: 450; onTriggered: { lockRoot.unlocking = true; leave.restart() } }
    Timer { id: failHold; interval: 1100; onTriggered: { lockRoot.result = ""; lockRoot.heldLen = 0 } }

    // ---- the smooth lock and unlock ----
    // Just before locking, each screen is photographed (grim, into your
    // private runtime folder, deleted on unlock): the lock starts as your
    // desktop and blurs into the frosted glass.  Unlocking plays it back,
    // to the sharp desktop, and only then lets go, so the lock melts away.
    // Without a picture (grim missing, or locking again at start-up), it
    // fades in from black.
    property bool unlocking: false       // the way out is playing
    property bool hasShots: false
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // (each lock's screens are new, and LockView doesn't cache the picture,
    // so it's always this lock's.  A "?" added to tell them apart made it
    // load in the background, and the first moments of the lock were black)
    function shotFor(name) {
        return hasShots && name !== "" ? "file://" + runDir + "/ether-lock-shot-" + name + ".ppm" : ""
    }
    Process {
        id: shoot
        command: ["sh", "-c", 'for o in "$@"; do grim -t ppm -o "$o" "$XDG_RUNTIME_DIR/ether-lock-shot-$o.ppm" & done; wait',
                  "sh"].concat(Quickshell.screens.map(s => s.name))
        onExited: code => lockRoot.engage(code === 0)
    }
    // locking doesn't wait more than a moment for the pictures
    Timer { id: shootLimit; interval: 600; onTriggered: lockRoot.engage(false) }
    property bool engaged: false         // the session lock asked for (once per lock)
    function engage(withShots) {
        shootLimit.stop()
        if (engaged || !isLocked) return
        engaged = true
        hasShots = withShots
        sl.locked = true
    }
    Process { id: unshoot; command: ["sh", "-c", 'rm -f "$XDG_RUNTIME_DIR"/ether-lock-shot-*.ppm'] }
    Timer {
        id: leave
        interval: 560                     // the way out (LockView) takes this long
        onTriggered: lockRoot.release()
    }

    function lock() { lockNow(true) }
    function lockNow(withPicture) {
        if (isLocked) return
        buffer = ""; message = ""; messageIsError = false; fails = 0; busy = false
        result = ""; heldLen = 0
        unlocking = false
        markOn.running = true
        isLocked = true
        if (withPicture && !shoot.running) { shootLimit.start(); shoot.running = true }
        else engage(false)
    }
    // the right password: play the way out, then let go
    function unlockNow() {
        heldLen = buffer.length
        buffer = ""; busy = true; fails = 0
        failHold.stop()
        result = "ok"; message = "Authenticated"; messageIsError = false
        okHold.restart()
    }
    function release() {
        engaged = false
        sl.locked = false
        isLocked = false
        unlocking = false
        busy = false
        result = ""; heldLen = 0
        hasShots = false
        markOff.running = true
        unshoot.running = true
    }
    function type(text) {
        if (busy || !text) return
        if (result === "fail") { failHold.stop(); result = ""; heldLen = 0 }
        if (message !== "" && !busy) { message = ""; messageIsError = false }
        buffer += text
    }
    function backspace() { if (!busy) buffer = buffer.slice(0, -1) }
    function clear() { if (!busy) buffer = "" }
    function submit() {
        if (busy || buffer === "") return
        busy = true
        message = ""
        if (!pam.start()) { busy = false; message = "Couldn't check the password"; messageIsError = true }
    }
    // Caps Lock: asked of Hyprland as you type (Wayland doesn't tell a lock
    // screen directly)
    function checkCaps() { if (!caps.running) caps.running = true }
    Process {
        id: caps
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kb = JSON.parse(text).keyboards || []
                    lockRoot.capsLock = kb.some(k => k.main && k.capsLock) || kb.some(k => k.capsLock)
                } catch (e) { lockRoot.capsLock = false }
            }
        }
    }

    PamContext {
        id: pam
        // the system's own login rules (/etc/pam.d/login): the same
        // password, and the same lockout after too many tries, as logging in.
        // (A file of our own can't "include login": PAM then looks for
        // login inside our folder, and every try fails.)
        config: "login"
        // each message from PAM: a prompt for the password gets what was
        // typed (on every prompt, not just when one first appears: two in a
        // row would otherwise go unanswered); anything else is shown
        onPamMessage: {
            if (responseRequired) {
                respond(lockRoot.buffer)
            } else if (message !== "") {
                lockRoot.message = message
                lockRoot.messageIsError = messageIsError
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                lockRoot.unlockNow()
                return
            }
            lockRoot.busy = false
            lockRoot.heldLen = lockRoot.buffer.length
            lockRoot.buffer = ""
            lockRoot.fails++
            lockRoot.result = "fail"
            failHold.restart()
            // keep a message PAM gave (too many tries, say); otherwise ours
            if (!lockRoot.messageIsError || lockRoot.message === "")
                lockRoot.message = result === PamResult.Failed ? "Authentication failed" : "Couldn't check the password"
            lockRoot.messageIsError = true
            lockRoot.wrong()
        }
        onError: err => {
            lockRoot.busy = false
            lockRoot.buffer = ""
            lockRoot.message = "Couldn't check the password"
            lockRoot.messageIsError = true
            lockRoot.wrong()
        }
    }

    WlSessionLock {
        id: sl
        surface: Component {
            WlSessionLockSurface {
                id: surf
                color: "black"
                LockView {
                    anchors.fill: parent
                    app: lockRoot.app
                    lock: lockRoot
                    screenName: surf.screen ? surf.screen.name : ""
                }
            }
        }
    }

    // ---- staying locked across a restart ----
    // A mark in the runtime folder (gone at logout or reboot) while locked.
    readonly property string mark: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ether-locked"
    Process { id: markOn;  command: ["sh", "-c", 'touch "$1"', "sh", lockRoot.mark] }
    Process { id: markOff; command: ["rm", "-f", lockRoot.mark] }
    Process {
        id: markCheck
        running: true
        command: ["test", "-e", lockRoot.mark]
        // (straight away, no picture: the screen behind may be anything)
        onExited: code => { if (code === 0) lockRoot.lockNow(false) }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { lockRoot.lock() }
        // our own state, set the moment locking starts (Quickshell 0.3.2's
        // sl.locked only turns true once Hyprland confirms, a moment later,
        // so a check straight after locking said "not locked")
        function isLocked(): bool { return lockRoot.isLocked }
    }
}
