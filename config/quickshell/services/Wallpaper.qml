pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Wallpapers: the list (~/Pictures/wallpapers, read while the Wallpaper
// page is open), each one's colours for the selector's swatches (matugen
// --dry-run, cached), applying one (measured by the native plugin first,
// then setwall themes everything), re-theming when a colour setting
// changes, a random one, the wallpaper in use, and the login screen's
// background.  Use it anywhere as Wallpaper.wallpapers,
// .applyWallpaper(path)... (import qs.services).
//
// The wallpaper's measured colours go to Theme.  The shell passes in the
// native plugin (nativeItem), the main screen (mainScreen) and whether the
// Wallpaper page is open (listing), and moves the desktop widgets when this
// says so (widgetsShouldMove).  Nothing here goes over the network.
Singleton {
    id: wallpaperSvc

    property var nativeItem: null
    property string mainScreen: ""
    property bool listing: false
    signal widgetsShouldMove()

    property var wallpapers: []
    Process { id: switchProc }
    Process { id: wallApply }
    Process { id: wallShow }

    // list the wallpaper folder whenever the Wallpaper page opens, so
    // newly added images show up without restarting the shell
    Process {
        id: wallList
        running: wallpaperSvc.listing
        command: ["sh", "-c",
            "find \"$HOME/Pictures/wallpapers\" -maxdepth 1 -type f "
            + "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' "
            + "-o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length)
                wallpaperSvc.wallpapers = lines
            }
        }
    }

    // ---- each wallpaper's colours, for the swatches in the selector ----
    // Worked out with matugen's --dry-run (nothing is changed), one
    // wallpaper at a time in the background, for the current style,
    // Theme.contrast, colour source and mode; cached in
    // ~/.cache/ether/palettes.json, so they're only worked out once.
    // wallPalettes: { path: [accent, secondary, tertiary, container, background] }
    // "auto" stays "auto" here: each wallpaper's swatches are worked out with
    // its own automatic choices (below), so they don't change with the
    // current wallpaper (which made every swatch take the current one's look)
    readonly property string paletteKey:
        (Config.cfg.themeScheme === "auto" ? "auto" : Theme.themeScheme) + "|" + Theme.themeContrast.toFixed(2) + "|"
        + Theme.themePrefer + "|" + (Config.cfg.themeMode === "auto" ? "auto" : (Theme.isLight ? "light" : "dark"))
        + (Config.cfg.accentStyle === "soft" ? "|soft" : "|vivid2")
    property var paletteCache: ({})      // { key: { path: [...] } }
    readonly property var wallPalettes: paletteCache[paletteKey] || ({})
    property var paletteQueue: []
    Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.cache/ether/palettes.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { try { const d = JSON.parse(text); if (d && typeof d === "object") wallpaperSvc.paletteCache = d } catch (e) {} }
        }
    }
    // the selector lists wallpapers when it opens: work out any missing
    onWallpapersChanged: queuePalettes()
    onPaletteKeyChanged: queuePalettes()
    function queuePalettes() {
        const have = paletteCache[paletteKey] || {}
        paletteQueue = wallpapers.filter(p => !have[p])
        if (!paletteProc.running) nextPalette()
    }
    function nextPalette() {
        if (!paletteQueue.length) return
        const path = paletteQueue[0]
        paletteQueue = paletteQueue.slice(1)
        // automatic choices: measure this wallpaper first, for its own light
        // or dark and its own style
        if ((Config.cfg.themeScheme === "auto" || Config.cfg.themeMode === "auto" || Theme.themePrefer === "smart") && wallpaperSvc.nativeItem) {
            paletteProbeWait.path = path
            paletteProbeWait.restart()
            wallpaperSvc.nativeItem.probe(path)
            return
        }
        runPalette(path, Theme.themeScheme, Theme.isLight ? "light" : "dark")
    }
    // the plugin has measured a wallpaper for its swatches (NativeStats.qml)
    function paletteProbed(path, lightness, scheme, seed, second, why, third) {
        if (!paletteProbeWait.running || paletteProbeWait.path !== path) return
        paletteProbeWait.stop()
        runPalette(path,
                   Config.cfg.themeScheme === "auto" ? (scheme || "scheme-tonal-spot") : Theme.themeScheme,
                   Config.cfg.themeMode === "auto" ? (lightness > 60 ? "light" : "dark") : (Theme.isLight ? "light" : "dark"),
                   Theme.themePrefer === "smart" ? seed : "", Theme.themePrefer === "smart" ? second : "", why,
                   Theme.themePrefer === "smart" ? third : "")
    }
    // a measurement that never arrives doesn't stall the queue
    Timer {
        id: paletteProbeWait
        property string path: ""
        interval: 3000
        onTriggered: wallpaperSvc.runPalette(path, Config.cfg.themeScheme === "auto" ? "scheme-tonal-spot" : Theme.themeScheme,
                                     Config.cfg.themeMode === "auto" ? "dark" : (Theme.isLight ? "light" : "dark"))
    }
    function runPalette(path, scheme, mode, seed, second, why, third) {
        paletteProc.path = path
        paletteProc.second = second || ""
        paletteProc.third = third || ""
        paletteProc.seed = seed || ""
        paletteProc.why = why || ""
        paletteProc.scheme = scheme
        paletteProc.key = paletteKey
        paletteProc.mode = mode
        // the smart colour: build from it; otherwise matugen picks from the image
        const from = seed ? ["color", "hex", seed] : ["image", path]
        const pick = seed ? [] : (Theme.themePrefer === "dominant" || Theme.themePrefer === "smart")
                                 ? ["--source-color-index", "0"] : ["--prefer", Theme.themePrefer]
        paletteProc.command = ["matugen"].concat(from).concat(["--dry-run", "-j", "hex", "-q",
                               "--type", scheme, "--Theme.contrast", Theme.themeContrast.toFixed(2)]).concat(pick)
                                .concat(["--mode", mode])
        paletteProc.running = true
    }
    Process {
        id: paletteProc
        property string path: ""
        property string key: ""
        property string mode: "dark"
        property string second: ""
        property string third: ""
        property string scheme: ""
        property string seed: ""
        property string why: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).colors
                    const m = paletteProc.mode
                    const pick = k => (c[k] && c[k][m] ? c[k][m].color : "")
                    const colours = ["primary", "secondary", "tertiary", "primary_container", "surface"].map(pick)
                    // the third dot as the shell will show it (Theme.thirdAccent), then
                    // the first: the vivid accent, from this wallpaper's own colour
                    if (colours.every(x => x)) {
                        colours[2] = Theme.thirdAccent(colours[0], colours[2], paletteProc.second, paletteProc.scheme).toString()
                        if (Config.cfg.accentStyle !== "soft" && paletteProc.seed !== ""
                                && paletteProc.scheme !== "scheme-monochrome" && paletteProc.scheme !== "scheme-neutral"
                                && paletteProc.why !== "no strong colour")
                        {
                            colours[0] = Theme.readableAccent(paletteProc.seed, colours[4]).toString()
                            // the picture's own second and third colours, as the theme will have them
                            if (paletteProc.second) colours[1] = Theme.readableAccent(paletteProc.second, colours[4]).toString()
                            if (paletteProc.third) colours[2] = Theme.readableAccent(paletteProc.third, colours[4]).toString()
                        }
                    }
                    if (colours.every(x => x)) {
                        const all = Object.assign({}, wallpaperSvc.paletteCache)
                        all[paletteProc.key] = Object.assign({}, all[paletteProc.key] || {})
                        all[paletteProc.key][paletteProc.path] = colours
                        wallpaperSvc.paletteCache = all
                        paletteSave.restart()
                    }
                } catch (e) {}
            }
        }
        onExited: wallpaperSvc.nextPalette()
    }
    Timer {
        id: paletteSave
        interval: 1500
        onTriggered: {
            // only the current settings' colours, and only wallpapers that still exist
            const keep = {}
            keep[wallpaperSvc.paletteKey] = {}
            const cur = wallpaperSvc.paletteCache[wallpaperSvc.paletteKey] || {}
            for (const p of wallpaperSvc.wallpapers) if (cur[p]) keep[wallpaperSvc.paletteKey][p] = cur[p]
            paletteWrite.command = ["sh", "-c",
                'd="$HOME/.cache/ether"; mkdir -p "$d"; printf "%s" "$1" > "$d/palettes.json.tmp" && mv "$d/palettes.json.tmp" "$d/palettes.json"',
                "sh", JSON.stringify(keep)]
            paletteWrite.running = true
        }
    }
    Process { id: paletteWrite }

    // the wallpaper picked while a theme was still being applied: done next
    property string wallPending: ""
    Connections {
        target: wallApply
        function onRunningChanged() {
            if (!wallApply.running && wallpaperSvc.wallPending !== "") {
                const p = wallpaperSvc.wallPending
                wallpaperSvc.wallPending = ""
                wallpaperSvc.applyWallpaperNow(p, true)      // already on screen: theme it
            }
        }
    }
    function applyWallpaper(path) {
        if (!path) return
        // still theming the one before: show this one now, theme it next
        // (the last one picked always wins, rather than clicks being lost)
        if (wallApply.running || wallWait.running) {
            wallPending = path
            wallpaperSvc.currentWall = path
            wallShow.command = [Quickshell.env("HOME") + "/.local/bin/setwall", "--show-only", path]
            wallShow.running = true
            if (wallWait.running) { wallWait.stop(); wallPending = ""; applyWallpaperNow(path, true) }
            return
        }
        applyWallpaperNow(path)
    }
    function applyWallpaperNow(path, shown) {
        wallpaperSvc.currentWall = path
        publishLoginSoon()
        // show it straight away; the colours follow (they fade in)
        if (!shown) {
            wallShow.command = [Quickshell.env("HOME") + "/.local/bin/setwall", "--show-only", path]
            wallShow.running = true
        }
        // the smart colour and automatic style need the wallpaper measured.
        // Already measured (the plugin remembers wallpapers it has seen, and
        // answers at once, before we'd even start waiting): theme it now.
        // Otherwise wait for the measurement (wallMeasured), a moment at most.
        const needsMeasure = (Config.cfg.themeMode === "auto" || Config.cfg.themeScheme === "auto" || Theme.themePrefer === "smart") && (wallpaperSvc.nativeItem !== null)
        if (needsMeasure && wallMeasuredFor !== path) { wallWait.path = path; wallWait.restart(); return }
        wallWait.stop()
        runSetwall(path)
    }
    // setwall, with the theme settings written first (the mode may just
    // have changed with the wallpaper)
    // the theme settings, then setwall --theme-only: one command for both a
    // new wallpaper (runSetwall) and a changed setting (flushTheme), so both
    // use the smart colour and neither replays the wallpaper's transition
    function setwallCommand(path) {
        // measured: the plugin's reading is for this wallpaper.  Otherwise
        // (it's late), no smart colour or automatic style from another
        // wallpaper: this one is themed from its own image, and again,
        // properly, when its measurement arrives (wallMeasured)
        const measured = wallMeasuredFor === path
        return ["sh", "-c",
            'f="$HOME/.config/matugen/shell-theme"; ' +
            // the smart colour's wallpaper, as a fingerprint (setwall runs this
            // file as shell code, so no raw path goes in it)
            'k=$(printf "%s" "$5" | md5sum | cut -c1-32); ' +
            'printf "TYPE=%s\\nCONTRAST=%s\\nPREFER=%s\\nMODE=%s\\nSEED=%s\\nSEED_FOR=%s\\nVIVID=%s\\nSECOND=%s\\nTHIRD=%s\\n" "$1" "$2" "$3" "$4" "$6" "$k" "$7" "$8" "$9" > "$f.tmp" && mv "$f.tmp" "$f"; ' +
            'exec "$HOME/.local/bin/setwall" --theme-only "$5"',
            "sh", measured ? Theme.themeScheme : (Config.cfg.themeScheme === "auto" ? "scheme-tonal-spot" : Theme.themeScheme),
            Theme.themeContrast.toFixed(2), Theme.themePrefer, Theme.isLight ? "light" : "dark", path,
            measured && Theme.smartOn ? Theme.wallSeed : "", measured && Theme.vividOn ? "1" : "0",
            measured && Theme.vividOn ? Theme.wallSecond : "", measured && Theme.vividOn ? Theme.wallThird : ""]
    }
    function runSetwall(path) {
        lastThemed = path
        lastThemedMeasured = wallMeasuredFor === path
        wallApply.command = setwallCommand(path)
        wallApply.running = true
        themeWatchdog.restart()
    }
    // a theme job that never finishes mustn't hold every later one up: after
    // 30 seconds it's stopped, and the queue moves on
    Timer {
        id: themeWatchdog
        interval: 30000
        onTriggered: {
            if (wallApply.running) { console.log("theme: a job took over 30 s; stopped it"); wallApply.running = false }
            if (themeProc.running) { console.log("theme: a settings job took over 30 s; stopped it"); themeProc.running = false }
        }
    }
    // the plugin has measured the wallpaper (NativeStats.qml calls this)
    function wallMeasured(lightness, scheme, colourfulness, seed, second, why, source, third) {
        Theme.wallLightness = lightness
        Theme.wallScheme = scheme || ""
        Theme.wallColourfulness = colourfulness
        Theme.wallSeed = seed || ""
        Theme.wallSecond = second || ""
        Theme.wallThird = third || ""
        Theme.wallWhy = why || ""
        wallMeasuredFor = source || ""
        // the wallpaper waiting for this: theme it now
        if (wallWait.running && wallWait.path === wallMeasuredFor) {
            wallWait.stop(); runSetwall(wallWait.path)
            if (Config.cfg.widgetsAuto === true) wallpaperSvc.widgetsShouldMove()
        }
        // it came too late, and the wallpaper was themed from the image
        // itself meanwhile: theme it again, properly, now (after the running
        // job, if there is one)
        else if (wallMeasuredFor === currentWall && lastThemed === currentWall && !lastThemedMeasured
                 && (Theme.themePrefer === "smart" || Config.cfg.themeScheme === "auto" || Config.cfg.themeMode === "auto")) {
            if (wallApply.running) wallPending = currentWall
            else runSetwall(currentWall)
        }
    }
    // which wallpaper the measurement above (Theme.wallSeed, wallScheme,
    // wallLightness...) belongs to: only ever used for that one
    property string wallMeasuredFor: ""
    property string lastThemed: ""
    property bool lastThemedMeasured: false

    // measured or not, don't wait longer than this
    Timer { id: wallWait; property string path: ""; interval: 2500; onTriggered: wallpaperSvc.runSetwall(path) }
    // ---- the login screen's background ----
    // Its own, shown before anyone signs in, so never your desktop's: Ether
    // Nightfall unless one is chosen here.  setwall copies it, with its
    // colours, into the login screen's folder (/var/lib/ether-greeter once
    // the login screen is installed; before that, where its preview looks).
    property string loginDir: Quickshell.env("HOME") + "/.cache/ether/greeter"
    Process {
        running: true
        command: ["test", "-w", "/var/lib/ether-greeter"]
        onExited: code => { if (code === 0) wallpaperSvc.loginDir = "/var/lib/ether-greeter" }
    }
    readonly property string loginDefault: Quickshell.env("HOME") + "/.config/ether-greeter/background.jpg"
    // "Your wallpaper" (the default): the login screen shows the wallpaper and
    // colours of whoever signed in last.  Each time this desktop's look
    // changes, it's shared: the wallpaper and the theme's colours, copied into
    // the login screen's folder.  "Its own" (a chosen picture) stops that.
    readonly property bool loginFollows: Config.cfg.loginFollow !== false
    function publishLoginSoon() { if (loginFollows) loginPublish.restart() }
    Timer {
        id: loginPublish
        interval: 1500                           // after the theme has settled
        onTriggered: {
            if (!wallpaperSvc.loginFollows || !wallpaperSvc.currentWall) return
            loginShare.command = ["sh", "-c",
                'd=$1; mkdir -p "$d" || exit 1; ' +
                'cp "$2" "$d/background.tmp" && mv -f "$d/background.tmp" "$d/background" && ' +
                'cp "$3" "$d/colors.tmp" && mv -f "$d/colors.tmp" "$d/colors.json" && ' +
                // which monitor gets the sign-in card
                'printf "{\\"mainScreen\\": \\"%s\\"}" "$4" > "$d/settings.tmp" && mv -f "$d/settings.tmp" "$d/settings.json" && ' +
                'chmod 644 "$d/background" "$d/colors.json" "$d/settings.json"',
                "sh", wallpaperSvc.loginDir, wallpaperSvc.currentWall, Quickshell.env("HOME") + "/.config/quickshell/colors.json",
                wallpaperSvc.mainScreen]
            loginShare.running = true
        }
    }
    Process { id: loginShare }
    function setLoginFollow(on) {
        Config.setting("loginFollow", on)
        if (on) loginPublish.restart()
        else setLoginBackground(Config.cfg.loginBackground || loginDefault)
    }
    property bool loginBusy: false
    property string loginError: ""
    function setLoginBackground(path) {
        loginBusy = true
        loginError = ""
        loginProc.command = [Quickshell.env("HOME") + "/.local/bin/setwall", "--login-background", path, loginDir]
        loginProc.running = true
        Config.setting("loginBackground", path === loginDefault ? "" : path)
        if (Config.cfg.loginFollow !== false) Config.setting("loginFollow", false)     // a picture of its own
    }
    Process {
        id: loginProc
        onExited: code => {
            wallpaperSvc.loginBusy = false
            if (code !== 0) wallpaperSvc.loginError = "Couldn't set it: is the login screen's folder writable?"
        }
    }
    Process { id: loginPreview }
    function previewLogin() {
        loginPreview.command = ["sh", "-c", "ETHER_GREETER_PREVIEW=1 setsid -f qs -p \"$HOME/.config/ether-greeter/greeter.qml\" >/dev/null 2>&1"]
        loginPreview.running = true
    }

    function randomWallpaper() {
        const pool = wallpaperSvc.wallpapers.filter(p => p !== wallpaperSvc.currentWall)
        if (pool.length) applyWallpaper(pool[Math.floor(Math.random() * pool.length)])
    }

    // the wallpaper in use, as setwall recorded it
    property string currentWall: ""
    readonly property bool wallBusy: wallApply.running
    Process {
        id: wallCurrent
        running: true
        command: ["sh", "-c", "cat ~/.cache/wallpaper 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: wallpaperSvc.currentWall = text.trim()
        }
    }



    property bool themeBusy: false

    // a Theme.contrast drag settles before matugen runs; each run re-renders
    // every app's colours, so it should happen once, not per pixel
    Timer {
        id: themeDebounce
        interval: 400
        onTriggered: wallpaperSvc.applyTheme()
    }

    property bool themePending: false
    // a colour setting changed: re-theme after a moment (several may come)
    function applyThemeSoon() { themeDebounce.restart() }
    function applyTheme() {
        themePending = true
        if (!themeProc.running) flushTheme()
    }
    function flushTheme() {
        if (!themePending) return
        themePending = false
        themeBusy = true
        if (!currentWall) { themeBusy = false; return }
        themeProc.command = setwallCommand(currentWall)
        themeProc.running = true
        themeWatchdog.restart()
    }
    Process {
        id: themeProc
        onExited: {
            // re-read the palette even if the post_hook didn't
            Theme.reloadPalette()
            wallpaperSvc.themeBusy = wallpaperSvc.themePending
            wallpaperSvc.flushTheme()
        }
    }

    // Hyprland reads ~/.config/hypr/shell-settings.lua, a plain
    // `return { ... }` table, near the top of hyprland.lua.  Only keys
    // the user has changed are written; hyprland.lua's own defaults
    // cover the rest.  It doesn't watch dofile()d files, so every
    // write is followed by `hyprctl reload`, debounced so a slider
    // drag reloads a few times rather than on every pixel.
}
