pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Monitor brightness, over DDC/CI (the monitors' own controls), and night
// light (hyprsunset).  Use it anywhere as Brightness.bright, .setBright(name,
// v), .toggleNight()... (import qs.services).
//
// Brightness goes straight through the native plugin when it's there (the
// shell passes it in as nativeItem), or through ddcutil.  Which bus each
// monitor is on is saved in ~/.cache/ether/ddc-map, so ddcutil detect only
// runs when the monitors change.  setAllBright tells the shell (allChanged)
// so it can show the OSD.  Nothing here goes over the network.
Singleton {
    id: brightnessSvc

    property var nativeItem: null
    signal allChanged()

    // ---- brightness (DDC/CI) -----------------------------------------
    // External monitors are set through their own controls with
    // ddcutil.  `ddcutil detect` maps each connector to its I2C bus at
    // startup, since bus numbers can change between boots.  Reads happen
    // when the sidebar or Displays page opens; writes are queued so a
    // drag only sends the latest value (each DDC command is slow).
    property var monBus: ({})          // { "DP-1": 7, "DP-2": 8 }
    property var bright: ({})          // { "DP-1": 90, ... } 0-100
    readonly property bool brightOk: Object.keys(monBus).length > 0
    readonly property int brightAvg: {
        const v = Object.keys(bright).map(k => bright[k])
        return v.length ? Math.round(v.reduce((a, b) => a + b, 0) / v.length) : 0
    }

    // `ddcutil detect` probes every bus (a few seconds), and the answer is
    // nearly always the same on the same machine.  So it's saved with each
    // monitor's fingerprint (its EDID's checksum) and each bus's name, and at
    // start-up those are checked instead (a few small files, milliseconds).
    // The same monitors on the same buses: the saved answer.  Anything
    // different (a monitor swapped, added or removed; buses renumbered):
    // ddcutil detect, as before, and its answer saved for next time.
    //   ~/.cache/ether/ddc-map: connector|bus|edid md5|bus name, a line each
    readonly property string ddcMapFile: Quickshell.env("HOME") + "/.cache/ether/ddc-map"
    Process {
        id: ddcDetect
        running: true
        command: ["sh", "-c", brightnessSvc.ddcCheckScript, "sh", brightnessSvc.ddcMapFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                if (text.startsWith("SAVED\n")) {
                    for (const line of text.split("\n").slice(1)) {
                        const f = line.split("|")
                        if (f.length >= 2 && /^\d+$/.test(f[1])) map[f[0]] = parseInt(f[1])
                    }
                } else {
                    for (const block of text.split(/\n(?=Display \d)/)) {
                        const bus = /I2C bus:\s*\/dev\/i2c-(\d+)/.exec(block)
                        const con = /DRM_connector:\s*card\d+-(\S+)/.exec(block)
                        if (bus && con) map[con[1]] = parseInt(bus[1])
                    }
                    brightnessSvc.saveDdcMap(map)
                }
                brightnessSvc.monBus = map
                brightnessSvc.readBrightness()
            }
        }
    }
    // (SYS: for testing, a pretend /sys)
    readonly property string ddcCheckScript:
        'f=$1; sys=${ETHER_SYSFS:-/sys}; ' +
        // each monitor that's connected now, and its EDID checksum
        'now=""; for st in "$sys"/class/drm/card*-*/status; do ' +
        '  [ "$(cat "$st" 2>/dev/null)" = connected ] || continue; d=${st%/status}; c=${d##*/}; c=${c#card*-}; ' +
        '  now="$now$c|$(md5sum < "$d/edid" 2>/dev/null | cut -c1-32)\n"; done; ' +
        'if [ -s "$f" ]; then ok=1; saved=""; ' +
        '  while IFS="|" read -r con bus edid name; do ' +
        '    [ -n "$con" ] || continue; saved="$saved$con|$edid\n"; ' +
        '    [ "$bus" = - ] || [ "$(cat "$sys/bus/i2c/devices/i2c-$bus/name" 2>/dev/null)" = "$name" ] || ok=0; ' +
        '  done < "$f"; ' +
        // the same monitors, with the same fingerprints, and the same buses
        '  a=$(printf "$now" | sort); b=$(printf "$saved" | sort); ' +
        '  if [ "$ok" = 1 ] && [ -n "$a" ] && [ "$a" = "$b" ]; then echo SAVED; cat "$f"; exit 0; fi; ' +
        'fi; ddcutil detect 2>/dev/null'
    // the answer, saved with each monitor's fingerprint and its bus's name
    Process { id: ddcSave }
    function saveDdcMap(map) {
        const pairs = Object.keys(map).map(c => c + ":" + map[c])
        if (!pairs.length) return                       // nothing found: ask again next time
        ddcSave.command = ["sh", "-c",
            // every connected monitor: its bus, or "-" for one without
            // brightness control (a laptop's own screen), so it doesn't look
            // like a change at every start
            'f=$1; shift; sys=${ETHER_SYSFS:-/sys}; mkdir -p "$(dirname "$f")"; : > "$f.tmp"; ' +
            'for st in "$sys"/class/drm/card*-*/status; do ' +
            '  [ "$(cat "$st" 2>/dev/null)" = connected ] || continue; d=${st%/status}; c=${d##*/}; c=${c#card*-}; ' +
            '  b=-; for p in "$@"; do [ "${p%%:*}" = "$c" ] && b=${p##*:}; done; ' +
            '  e=$(md5sum < "$d/edid" 2>/dev/null | cut -c1-32); ' +
            '  n=""; [ "$b" = - ] || n=$(cat "$sys/bus/i2c/devices/i2c-$b/name" 2>/dev/null); ' +
            '  printf "%s|%s|%s|%s\n" "$c" "$b" "$e" "$n" >> "$f.tmp"; done; mv "$f.tmp" "$f"',
            "sh", ddcMapFile].concat(pairs)
        ddcSave.running = true
    }

    // ---- the native route: the plugin talks to the monitors directly ----
    // Much faster than a ddcutil run per change (about 50 ms, the protocol's
    // own pace), so the slider follows a drag.  A monitor it doesn't work
    // for (no access to its bus, no answer) is marked, and uses ddcutil from
    // then on, with the value you asked for sent again.
    property var ddcBad: ({})           // { bus: true }
    function ddcNative(bus) { return brightnessSvc.nativeItem !== null && !ddcBad[bus] }
    function monOfBus(bus) { return Object.keys(monBus).find(n => monBus[n] === bus) }
    function ddcGotBrightness(bus, percent) {
        const name = monOfBus(bus)
        if (name === undefined) return
        const b = Object.assign({}, bright); b[name] = percent; bright = b
    }
    function ddcFailed(bus) {
        const bad = Object.assign({}, ddcBad); bad[bus] = true; ddcBad = bad
        const name = monOfBus(bus)
        if (name === undefined) return
        console.log("brightness: the direct route doesn't work for " + name + " (bus " + bus + "); using ddcutil for it")
        // what you'd asked for, sent the slow way; then read it back
        if (bright[name] !== undefined) { const p = Object.assign({}, brightPending); p[name] = bright[name]; brightPending = p; brightDebounce.restart() }
        else readBrightness()
    }

    function readBrightness() {
        if (!brightOk) return
        const slow = Object.keys(monBus).filter(n => !ddcNative(monBus[n]))
        for (const n of Object.keys(monBus)) if (ddcNative(monBus[n])) brightnessSvc.nativeItem.ddcGet(monBus[n])
        if (!slow.length || ddcRead.running) return
        const cmds = slow.map(n =>
            'printf "%s " ' + n + '; ddcutil --bus ' + monBus[n] + ' getvcp 10 --brief 2>/dev/null || echo')
        ddcRead.command = ["sh", "-c", cmds.join("; ")]
        ddcRead.running = true
    }
    Process {
        id: ddcRead
        stdout: StdioCollector {
            onStreamFinished: {
                // lines look like "DP-1 VCP 10 C 90 100"
                const b = Object.assign({}, brightnessSvc.bright)
                for (const line of text.split("\n")) {
                    const m = /^(\S+) VCP 10 C (\d+) (\d+)/.exec(line.trim())
                    if (m) b[m[1]] = Math.round(100 * parseInt(m[2]) / Math.max(1, parseInt(m[3])))
                }
                brightnessSvc.bright = b
            }
        }
    }

    property var brightPending: ({})
    function setBright(name, v) {
        if (monBus[name] === undefined) return
        v = Math.max(0, Math.min(100, Math.round(v)))
        const b = Object.assign({}, bright); b[name] = v; bright = b
        // direct: straight to the plugin, which sends only the newest value
        if (ddcNative(monBus[name])) { brightnessSvc.nativeItem.ddcSet(monBus[name], v); return }
        const p = Object.assign({}, brightPending); p[name] = v; brightPending = p
        brightDebounce.restart()
    }
    function setAllBright(v) {
        for (const n of Object.keys(monBus)) setBright(n, v)
        allChanged()                        // the shell shows the OSD
    }
    Timer {
        id: brightDebounce
        interval: 120
        onTriggered: brightnessSvc.flushBright()
    }
    function flushBright() {
        const names = Object.keys(brightPending)
        if (!names.length || ddcWrite.running) return
        const cmds = names.map(n =>
            "ddcutil --bus " + monBus[n] + " setvcp 10 " + brightPending[n] + " --noverify 2>/dev/null")
        brightPending = ({})
        ddcWrite.command = ["sh", "-c", cmds.join("; ")]
        ddcWrite.running = true
    }
    Process {
        id: ddcWrite
        onExited: brightnessSvc.flushBright()
    }

    // ---- night light -------------------------------------------------
    // On runs hyprsunset at a fixed warmth; off stops it, which puts
    // the normal colours back.  Remembered across restarts.
    readonly property bool nightLight: Config.cfg.nightLight === true
    readonly property int nightTemp: 4000
    Process { id: nightProc }
    function applyNight() {
        nightProc.command = ["sh", "-c", nightLight
            ? "pgrep -x hyprsunset >/dev/null || setsid -f hyprsunset -t " + nightTemp + " >/dev/null 2>&1"
            : "pkill -x hyprsunset; true"]
        nightProc.running = true
    }
    function toggleNight() { Config.setting("nightLight", !nightLight) }
    // applied whenever the setting changes, the first reading of
    // settings.json at start-up included (a Component.onCompleted came
    // before that, so night light didn't come back after a restart)
    onNightLightChanged: applyNight()
}
