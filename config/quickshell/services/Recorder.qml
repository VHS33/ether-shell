pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Screen recording (~/.local/bin/record, with gpu-screen-recorder): whether
// it's recording, and for how long.  The record command tells the shell
// each time it starts or stops (qs ipc call recorder update); the shell also
// looks for itself when it starts, and every few seconds while recording
// (in case the recorder stopped on its own).
// Record 30 s back (quick settings): the last 30 seconds kept in memory, so
// a recording starts 30 seconds before the press (and SUPER + SHIFT + C saves
// just them): .replaying, .setReplay(on); it stays on across logins (the
// replayOn setting), started again when the shell starts.
// Use it anywhere as Recorder.recording, .elapsed ("1:05"), .toggle(),
// .replaying (import qs.services).  Nothing goes over the network.
Singleton {
    id: rec

    property bool recording: false
    property bool replaying: false
    property int seconds: 0
    readonly property string elapsed: {
        const h = Math.floor(seconds / 3600), m = Math.floor(seconds / 60) % 60, s = seconds % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(s).padStart(2, "0")
    }
    // gpu-screen-recorder is installed (the tile says so if it isn't)
    property bool available: true

    readonly property string cmd: Quickshell.env("HOME") + "/.local/bin/record"

    function toggle() {
        toggler.command = ["sh", "-c", 'sleep 0.4; exec "$1" toggle', "sh", cmd]
        toggler.running = true
    }
    function stop() {
        toggler.command = [cmd, "stop"]
        toggler.running = true
    }
    function update() { if (!asker.running) asker.running = true }
    // save the last 30 seconds (SUPER + SHIFT + C does the same)
    function saveClip() {
        clipper.command = [cmd, "clip"]
        clipper.running = true
    }
    Process { id: clipper }
    // Record 30 s back on or off, remembered for next time
    function setReplay(on) {
        Config.setting("replayOn", on)
        replayer.command = [cmd, "replay", on ? "on" : "off"]
        replayer.running = true
    }
    // at login (the shell starting), back on if it was on
    function resume() {
        if (Config.cfg.replayOn === true && available && !replaying && !replayer.running) {
            replayer.command = [cmd, "replay", "on"]
            replayer.running = true
        }
    }
    Connections {
        target: Config
        function onLoadedChanged() { if (Config.loaded) resumeSoon.start() }
    }
    // (after the first look, so one already running isn't started twice)
    Timer { id: resumeSoon; interval: 1500; onTriggered: rec.resume() }
    Process { id: replayer; onExited: rec.update() }

    Process { id: toggler }
    Process {
        id: asker
        command: [rec.cmd, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const t = (lines[0] || "").split(" ")
                rec.recording = t[0] === "recording"
                if (rec.recording) rec.seconds = Math.max(0, parseInt(t[1]) || 0)
                rec.replaying = lines.indexOf("replay") > 0
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v gpu-screen-recorder"]
        onExited: code => rec.available = code === 0
    }
    Component.onCompleted: { update(); if (Config.loaded) resumeSoon.start() }

    // the clock, while recording; and a look every few seconds
    Timer {
        interval: 1000; repeat: true
        running: rec.recording
        onTriggered: {
            rec.seconds++
            if (rec.seconds % 5 === 0) rec.update()
        }
    }
    // while only replay is on, a look now and then (in case it stopped)
    Timer {
        interval: 10000; repeat: true
        running: rec.replaying && !rec.recording
        onTriggered: rec.update()
    }

    IpcHandler {
        target: "recorder"
        function update(): void { rec.update() }
        function toggle(): void { rec.toggle() }
        function replay(on: bool): void { rec.setReplay(on) }
    }
}
