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
        cornerRadius: 0,                // Settings > Bar > Corners: 0 round, else 2-20 px (how sharp)
        tabbedWindows: false,           // several windows in one tile, with tabs (i3's tabbed layout)
        tabStyle:    "tabs",            // their tabs: "tabs" side by side, or "stacked"
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
        themePalette:  "picture",      // the whole palette from the picture (native plugin), or "material"
        // Theme Studio: colours picked by hand, per wallpaper ({ path: { main,
        // second, third } }), and for every wallpaper the accents' strength
        // and how strongly the backgrounds are tinted (1 = as found)
        studioPicks:    ({}),
        studioStrength: 1,
        studioTint:     1,
        // the active window's border: one colour ("single") or a gradient
        // into the third colour ("gradient"); its colour, "" for the main accent
        studioBorder:       "single",
        studioBorderColour: "",
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

        // Record 30 s back (quick settings): kept on across logins
        replayOn:      false,

        // fonts (Settings > General): "" is Inter for text, JetBrains Mono
        // for monospace (the terminal)
        uiFont:        "",
        monoFont:      "",

        // the mouse cursor (Settings > Mouse): "" leaves the system's theme
        cursorTheme:   "",
        cursorSize:    24,

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

    // ---- keeping the file safe ----
    // settings.json is read in the background at start-up.  Until that read
    // has finished, `loaded` is false and nothing is written: a change made
    // that early is kept here and merged with the file once it's read (the
    // change wins), so an early save can never replace the file with an
    // almost empty one.  A file that can't be understood is never written
    // over: it's renamed settings.json.broken-<date> and you're told.
    property bool loaded: false
    // no settings file at start-up: a new install (the welcome shows)
    property bool firstRun: false
    property bool earlyChanges: false      // something changed before `loaded`
    property var earlyResets: []           // keys reset before `loaded`
    property bool earlyResetAll: false

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
        if (!loaded) earlyResets = earlyResets.concat([key])
        save()
        settingChanged(key)
    }
    function resetAll() {
        user = ({})
        if (!loaded) { earlyResetAll = true; earlyResets = [] }
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
        if (!loaded) { earlyChanges = true; return }
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

    // the first read: the file's settings, then the early changes on top
    function afterFirstRead(fromFile) {
        let u = earlyResetAll ? ({}) : Object.assign({}, fromFile)
        for (const k of earlyResets) delete u[k]
        u = Object.assign(u, user)
        const changed = earlyChanges
        earlyChanges = false; earlyResets = []; earlyResetAll = false
        user = u
        loaded = true
        if (changed) save()
    }
    function tell(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Ether Shell", "-u", "critical",
                                 "-i", "dialog-warning", title, body])
    }

    // The first line says what happened: NONE (no file yet: a first run),
    // OK (the file follows), or ERR (it's there but couldn't be read).
    // A file that doesn't parse is moved aside before anything is saved.
    Process {
        id: settingsRead
        running: true
        command: ["sh", "-c",
            'f="$HOME/.config/quickshell/settings.json"; ' +
            'if [ ! -e "$f" ]; then echo NONE; ' +
            'elif c=$(cat "$f" 2>/dev/null); then printf "OK\\n%s" "$c"; ' +
            'else echo ERR; fi']
        stdout: StdioCollector {
            onStreamFinished: config.readDone(text)
        }
    }
    // the rename finishes before anything is saved, so it can only ever
    // move the broken file, never a newly saved one
    Process {
        id: setAside
        onExited: {
            if (!config.loaded) config.afterFirstRead({})
            else config.save()
        }
    }
    function readDone(text) {
        const nl = text.indexOf("\n")
        const head = (nl < 0 ? text : text.slice(0, nl)).trim()
        const body = nl < 0 ? "" : text.slice(nl + 1).trim()

        if (head === "NONE") {
            if (!loaded) { firstRun = true; afterFirstRead({}) }
            else user = ({})
            return
        }
        if (head !== "OK") {
            // there, but unreadable (permissions?).  At start-up: leave it
            // alone and don't save over it (`loaded` stays false); on a
            // reload: keep the settings already in use.
            console.log("settings.json couldn't be read")
            tell("Settings couldn't be read",
                 loaded ? "~/.config/quickshell/settings.json couldn't be opened. The settings already in use were kept."
                        : "~/.config/quickshell/settings.json is there but couldn't be opened. "
                          + "Using defaults for now; changes won't be saved until the shell restarts and can read it.")
            return
        }

        let o = null
        if (body.length) {
            try {
                const p = JSON.parse(body)
                if (p && typeof p === "object" && !Array.isArray(p)) o = p
            } catch (e) {
                console.log("settings.json parse failed:", e)
            }
        } else o = {}

        if (o !== null) {
            if (!loaded) afterFirstRead(o)
            else user = o
            return
        }

        // Not valid settings: keep the file as it is under a new name, so
        // nothing in it is lost, then carry on (defaults at start-up, or
        // the settings already in use after a reload) and save those.
        setAside.command = ["sh", "-c",
            'f="$HOME/.config/quickshell/settings.json"; ' +
            'mv "$f" "$f.broken-$(date +%Y%m%d-%H%M%S)"']
        setAside.running = true
        tell("Settings file couldn't be understood",
             "It was kept as settings.json.broken-<date> in ~/.config/quickshell. "
             + (loaded ? "The settings already in use were kept."
                       : "Using defaults for now. To get yours back, fix that file, "
                         + "rename it to settings.json and run: qs ipc call settings reload"))
    }
}
