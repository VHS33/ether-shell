import QtQuick

// A line of the Neo lock screen that decodes itself: it starts as random
// characters, and they settle into the real text left to right, the way a
// readout locks on.  It decodes when `go` turns true (the lock settling),
// and again when its text changes, unless `quietUpdates` (the live
// readouts, which change every few seconds, just change).  No light, no
// flashing: only the characters themselves.
Text {
    id: dec
    property string target: ""
    property bool go: false
    property bool quietUpdates: false
    property int duration: 650
    readonly property string glyphs: "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#/<>=+*"
    property real progress: 0               // 0 all noise, 1 all real
    property bool done: false

    function scramble() {
        const n = target.length
        const fixed = Math.floor(n * progress)
        let out = ""
        for (let i = 0; i < n; i++) {
            const c = target.charAt(i)
            out += (i < fixed || c === " " || c === "/" || c === ":") ? c
                 : glyphs.charAt(Math.floor(Math.random() * glyphs.length))
        }
        text = out
    }
    function start() {
        done = false
        progress = 0
        run.restart()
        tick.restart()
        scramble()
    }
    onGoChanged: if (go) start()
    onTargetChanged: {
        if (!go) { text = ""; return }
        if (done && quietUpdates) text = target
        else start()
    }
    Component.onCompleted: text = go ? target : ""

    NumberAnimation {
        id: run
        target: dec; property: "progress"; from: 0; to: 1
        duration: dec.duration; easing.type: Easing.InOutQuad
        onStopped: { dec.done = true; tick.stop(); dec.text = dec.target }
    }
    Timer { id: tick; interval: 45; repeat: true; onTriggered: dec.scramble() }
}
