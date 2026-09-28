pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Your settings.  ~/.config/quickshell/settings.json holds only what you've
// changed; everything else comes from `defaults`, so a missing or broken file
// changes nothing.  Read them anywhere as Config.cfg.<key> (import qs.common).
//
//   Config.setting(key, value)    change one, save, and tell the shell
//                                 (settingChanged), which passes it on to
//                                 Hyprland, kitty, the lock screen...
//   Config.resetSetting(key)      back to its default
//   Config.resetAll()             every setting back to its default
//   Config.update({ k: v, ... })  change several and save once, telling
//                                 nothing else (the caller does what's needed)
//   Config.reload()               read the file again (after editing it by
//                                 hand: qs ipc call settings reload)
//
// Nothing here goes over the network.
Singleton {
    id: config

    readonly property var defaults: ({
        fontScale:   1.0,     // 0.7 - 1.6
        bgOpacity:   0.75,    // 0.3 - 1.0, every shell surface
        osdMs:       1400,    // volume indicator on screen
        notifMs:     6000,    // popup life; critical ones get double
        dockEnabled: true,
        termOpacity: 0.75,    // kitty background, 0.3 - 1.0

        // Hyprland: these defaults must match the ones at the top of
        // hyprland.lua, which is what applies when a key is unset
        gapsIn:      4,
        gapsOut:     1,
        borderSize:  2,
        rounding:    12,
        winActive:   1.0,
        winInactive: 1.0,
        blurSize:    4,
        blurPasses:  3,
        animations:  true,
        animSpeed:   1.0,

        // matugen: colour style and contrast, used by setwall
        themeScheme:   "scheme-tonal-spot",
        themeContrast: 0,
        themePrefer:   "smart",        // Ether Shell's own pick: the subject, skin set aside (native plugin)
        themeMode:     "dark",
        nightLight:    false,

        // bar
        clock24h:     false,
        clockSeconds: false,
        clockDate:    true,
        barStats:     true,     // CPU and memory
        barGpu:       true,
        barNet:       true,
        barMedia:     true,     // now playing, centre of the bar

        // idle, in minutes; 0 means never
        idleLockMin:   5,
        idleScreenMin: 10,
        idleSleepMin:  0,

        // Hyprland input (also in hyprKeys below)
        repeatRate:    25,
        repeatDelay:   600,
        sensitivity:   0,
        accelFlat:     false,
        naturalScroll: false,
        followMouse:   true
    })

    property var user: ({})
    readonly property var cfg: Object.assign({}, defaults, user)

    // key: the one that changed, or "*" for all of them
    signal settingChanged(string key)

    function setting(key, value) {
        const o = Object.assign({}, user)
        o[key] = value
        user = o
        save()
        settingChanged(key)
    }
    function resetSetting(key) {
        const o = Object.assign({}, user)
        delete o[key]
        user = o
        save()
        settingChanged(key)
    }
    function resetAll() {
        user = ({})
        save()
        settingChanged("*")
    }
    function update(changes) {
        user = Object.assign({}, user, changes)
        save()
    }
    function reload() { settingsRead.running = true }

    // writes go through a temp file and a rename, one at a time, so a
    // slider being dragged never leaves a half-written file behind
    property string pending: ""
    function save() {
        pending = JSON.stringify(user, null, 2) + "\n"
        if (!settingsWrite.running) flush()
    }
    function flush() {
        if (pending === "") return
        settingsWrite.command = ["sh", "-c",
            'f="$HOME/.config/quickshell/settings.json"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
            "sh", pending]
        pending = ""
        settingsWrite.running = true
    }
    Process {
        id: settingsWrite
        onExited: config.flush()
    }
    Process {
        id: settingsRead
        running: true
        command: ["sh", "-c",
            "cat ~/.config/quickshell/settings.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) { config.user = ({}); return }
                try {
                    const o = JSON.parse(t)
                    if (o && typeof o === "object" && !Array.isArray(o))
                        config.user = o
                } catch (e) {
                    console.log("settings.json parse failed, using defaults:", e)
                }
            }
        }
    }
}
