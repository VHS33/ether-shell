pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Your settings, passed on to the programs that read them: Hyprland
// (~/.config/hypr/shell-settings.lua, then hyprctl reload), kitty (its
// opacity), the lock screen (hyprlock's settings), idle (hypridle's
// timings), the in-game overlay (MangoHud.conf, and Steam's launcher entry),
// and default apps (terminal, files, browser: xdg-mime).  It listens to
// Config's settingChanged itself.  Use it anywhere as Session.setDefaultApp
// (...), .syncAll()... (import qs.services).
//
// The shell passes in whether a game is running (autoGame) and the
// terminal's opacity (termOpacity).  Nothing here goes over the network.
Singleton {
    id: sessionSvc

    property bool autoGame: false
    // a game started or stopped: Hyprland's game mode follows
    onAutoGameChanged: applyHyprSoon()
    property real termOpacity: 0.75

    // ---- default apps --------------------------------------------------
    // Terminal and file manager feed hyprland.lua's SUPER+T / SUPER+E
    // (through shell-settings.lua); the file manager and browser also
    // become the system defaults through xdg-mime / xdg-settings.
    readonly property string termCmd: Config.cfg.appTerminalCmd || "kitty"

    // what xdg currently calls the default, read when the page opens
    property var xdgDefaults: ({ files: "", browser: "" })
    Process {
        id: xdgRead
        command: ["sh", "-c",
            'echo "files=$(xdg-mime query default inode/directory 2>/dev/null)"; '
            + 'echo "browser=$(xdg-settings get default-web-browser 2>/dev/null)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const o = { files: "", browser: "" }
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                sessionSvc.xdgDefaults = o
            }
        }
    }
    function refreshXdg() { xdgRead.running = true }

    // a desktop entry's command, without the %u / %F placeholders
    function entryCmd(e) {
        return String(e.execString || "").replace(/%[fFuUdDnNickvm]/g, "").replace(/\s+/g, " ").trim()
    }

    Process { id: xdgWrite }
    function setDefaultApp(role, entry) {
        const id = entry.id.endsWith(".desktop") ? entry.id : entry.id + ".desktop"
        if (role === "terminal") Config.update({ appTerminal: id, appTerminalCmd: entry.cmd })
        else if (role === "files") Config.update({ appFiles: id, appFilesCmd: entry.cmd })
        else Config.update({ appBrowser: id })
        if (role === "terminal" || role === "files") hyprDebounce.restart()
        if (role === "files")
            xdgWrite.command = ["xdg-mime", "default", id, "inode/directory"]
        else if (role === "browser")
            xdgWrite.command = ["xdg-settings", "set", "default-web-browser", id]
        if (role !== "terminal") xdgWrite.running = true
        xdgRefreshLater.restart()
    }
    Timer {
        id: xdgRefreshLater
        interval: 500
        onTriggered: sessionSvc.refreshXdg()
    }

    // ---- lock screen ---------------------------------------------------
    // hyprlock.conf sources ~/.config/hypr/hyprlock-settings.conf, which
    // the panel rewrites: clock command (follows the bar's 12/24-hour and
    // seconds settings), blur, dimming, greeting and now-playing line.
    readonly property int lockBlur: {
        const v = Number(Config.cfg.lockBlur)
        return Config.cfg.lockBlur !== undefined && isFinite(v) ? Math.max(0, Math.min(12, Math.round(v))) : 8
    }
    readonly property int lockDim: {
        const v = Number(Config.cfg.lockDim)
        return Config.cfg.lockDim !== undefined && isFinite(v) ? Math.max(20, Math.min(100, Math.round(v))) : 55
    }
    readonly property string lockGreetMode:
        ["time", "custom", "off"].indexOf(Config.cfg.lockGreetMode) >= 0 ? Config.cfg.lockGreetMode : "time"
    readonly property string lockGreetText: Config.cfg.lockGreetText || ""
    readonly property bool lockMedia: Config.cfg.lockMedia !== false

    function lockText() {
        const secs = Config.cfg.clockSeconds === true ? ":%S" : ""
        const clock = Config.cfg.clock24h === true
            ? "echo \"<span font_weight='200'>$(date +'%H:%M" + secs + "')</span>\""
            : "echo \"<span font_weight='200'>$(date +'%-I:%M" + secs + "')</span>"
              + "<span font_size='30pt' font_weight='400'> $(date +'%p')</span>\""
        // a custom greeting goes inside echo "...", so anything that would
        // end the string, expand, or start a hyprlang comment is dropped
        const safe = lockGreetText.replace(/["`$\\#\n\r]/g, "").trim()
        const who = "$(whoami)"
        const greet = lockGreetMode === "off" ? "true"
            : lockGreetMode === "custom" ? "echo \"" + (safe || "Welcome back") + "\""
            : "case $(date +%H) in 0[5-9]|1[01]) echo \"Good morning, " + who + "\";; "
              + "1[2-6]) echo \"Good afternoon, " + who + "\";; "
              + "1[7-9]|2[01]) echo \"Good evening, " + who + "\";; "
              + "*) echo \"Good night, " + who + "\";; esac"
        const media = lockMedia
            ? "playerctl metadata --format '{{title}}   {{artist}}' 2>/dev/null"
            : "true"
        return "# written by the quickshell settings panel (Desktop > Lock screen);\n"
             + "# change it there, hand edits are replaced.\n"
             + "$clock_cmd   = " + clock + "\n"
             + "$blur_passes = " + (lockBlur === 0 ? 0 : 3) + "\n"
             + "$blur_size   = " + Math.max(1, lockBlur) + "\n"
             + "$dim         = " + (lockDim / 100).toFixed(2) + "\n"
             + "$greet_cmd   = " + greet + "\n"
             + "$media_cmd   = " + media + "\n"
    }

    Timer {
        id: lockDebounce
        interval: 300
        onTriggered: {
            lockWrite.command = ["sh", "-c",
                'f="$HOME/.config/hypr/hyprlock-settings.conf"; printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"',
                "sh", sessionSvc.lockText()]
            lockWrite.running = true
        }
    }
    Process { id: lockWrite }

    // ---- idle --------------------------------------------------------
    // hypridle can't reload its config, so the panel regenerates the
    // whole of ~/.config/hypr/hypridle.conf and restarts it.  Only
    // written when an idle setting changes; minutes, 0 = never.
    function idleMin(key, def) {
        const v = Number(Config.cfg[key])
        return isFinite(v) ? Math.max(0, Math.min(240, Math.round(v))) : def
    }
    readonly property int idleLockMin:   idleMin("idleLockMin", 5)
    readonly property int idleScreenMin: idleMin("idleScreenMin", 10)
    readonly property int idleSleepMin:  idleMin("idleSleepMin", 0)

    function idleText() {
        const dpms = s => "hyprctl dispatch 'hl.dsp.dpms(\"" + s + "\")'"
        let t = "# written by the quickshell settings panel (Desktop > Idle);\n"
              + "# change it there, hand edits are replaced.  hyprlang, like hyprlock\n\n"
              + "general {\n"
              + "    lock_cmd         = pidof hyprlock || hyprlock\n"
              + "    before_sleep_cmd = loginctl lock-session\n"
              + "    after_sleep_cmd  = " + dpms("on") + "\n"
              + "}\n"
        if (idleLockMin > 0)
            t += "\n# lock\nlistener {\n"
               + "    timeout    = " + idleLockMin * 60 + "\n"
               + "    on-timeout = loginctl lock-session\n}\n"
        if (idleScreenMin > 0)
            t += "\n# screens off\nlistener {\n"
               + "    timeout    = " + idleScreenMin * 60 + "\n"
               + "    on-timeout = " + dpms("off") + "\n"
               + "    on-resume  = " + dpms("on") + "\n}\n"
        if (idleSleepMin > 0)
            t += "\n# sleep\nlistener {\n"
               + "    timeout    = " + idleSleepMin * 60 + "\n"
               + "    on-timeout = systemctl suspend\n}\n"
        return t
    }

    Timer {
        id: idleDebounce
        interval: 600
        onTriggered: sessionSvc.writeIdle()
    }

    property string pendingIdle: ""
    function writeIdle() {
        pendingIdle = idleText()
        if (!idleWrite.running) flushIdle()
    }
    function flushIdle() {
        if (pendingIdle === "") return
        idleWrite.command = ["sh", "-c",
            'f="$HOME/.config/hypr/hypridle.conf"; ' +
            'printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f"; ' +
            'pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1; true',
            "sh", pendingIdle]
        pendingIdle = ""
        idleWrite.running = true
    }
    Process {
        id: idleWrite
        onExited: sessionSvc.flushIdle()
    }

    // ---- the in-game overlay (Settings, Game overlay) ----
    // MangoHud, drawn inside games: its MangoHud.conf is written from the
    // settings and the theme (lib/overlay.mjs), again whenever either
    // changes.  A MangoHud.conf of your own is set aside once, as
    // MangoHud.conf.before-ether, and put back when the overlay is off.
    // "All Steam games": a copy of Steam's launcher entry, in
    // ~/.local/share/applications, starting it with MANGOHUD=1 (MangoHud
    // leaves Steam's own windows alone).  An entry of your own is left be.
    readonly property string gameHud: ["off", "steam", "choose"].indexOf(Config.cfg.gameHud) >= 0 ? Config.cfg.gameHud : "off"
    property bool mangoOk: false
    Process {
        id: mangoCheck
        running: true
        command: ["sh", "-c", "ls /usr/share/vulkan/implicit_layer.d/*[Mm]ango[Hh]ud*.json >/dev/null 2>&1 && echo yes"]
        stdout: StdioCollector { onStreamFinished: sessionSvc.mangoOk = text.trim() === "yes" }
    }
    function checkMango() { mangoCheck.running = true }
    readonly property string mangoConf: gameHud === "off" ? "" : Overlay.mangoConfig({
        layout: Config.cfg.gameHudLayout, position: Config.cfg.gameHudPos, size: Config.cfg.gameHudSize, hidden: Config.cfg.gameHudHidden === true,
        colours: { bg: String(Theme.cBg), fg: String(Theme.cFg), accent: String(Theme.cBlue), second: String(Theme.cPeach),
                   third: String(Theme.cGreen), red: String(Theme.cRed), yellow: String(Theme.cYellow) } })
    onMangoConfChanged: mangoLater.restart()
    onGameHudChanged: steamLater.restart()
    Timer { id: mangoLater; interval: 400; onTriggered: { mangoWrite.command = ["sh", "-c", sessionSvc.mangoScript, "sh", sessionSvc.mangoConf]; mangoWrite.running = true } }
    Timer { id: steamLater; interval: 400; onTriggered: { steamWrite.command = ["sh", "-c", sessionSvc.steamScript, "sh", sessionSvc.gameHud]; steamWrite.running = true } }
    Process { id: mangoWrite }
    Process { id: steamWrite }
    readonly property string mangoScript:
        'd="${ETHER_MANGO_DIR:-$HOME/.config/MangoHud}"; f="$d/MangoHud.conf"; ours="Written by Ether Shell"; ' +
        // off: ours goes, and yours comes back
        'if [ -z "$1" ]; then ' +
        '  if [ -f "$f" ] && head -1 "$f" | grep -q "$ours"; then rm -f "$f"; [ -f "$f.before-ether" ] && mv "$f.before-ether" "$f"; fi; exit 0; ' +
        'fi; mkdir -p "$d"; ' +
        // yours, kept (once)
        'if [ -f "$f" ] && ! head -1 "$f" | grep -q "$ours" && [ ! -e "$f.before-ether" ]; then mv "$f" "$f.before-ether"; fi; ' +
        'printf "%s" "$1" > "$f.tmp"; ' +
        // the shell's own font, if it can be found
        'font=$(fc-match -f "%{file}" "Inter:weight=500" 2>/dev/null); ' +
        'case "$font" in *Inter*.ttf|*Inter*.otf|*Inter*.TTF|*Inter*.OTF) printf "font_file=%s\n" "$font" >> "$f.tmp" ;; esac; ' +
        'mv "$f.tmp" "$f"'
    readonly property string steamScript:
        'o="${ETHER_APPS_DIR:-$HOME/.local/share/applications}/steam.desktop"; src="${ETHER_STEAM_ENTRY:-/usr/share/applications/steam.desktop}"; ' +
        'if [ "$1" = steam ]; then ' +
        '  [ -f "$src" ] || exit 0; ' +
        // one of your own: left be
        '  if [ -f "$o" ] && ! grep -q "^X-Ether-Overlay=true" "$o"; then exit 0; fi; ' +
        '  mkdir -p "$(dirname "$o")"; ' +
        // (no backslashes: they'd be eaten on the way to sed)
        '  [ "$(head -1 "$src")" = "[Desktop Entry]" ] || exit 0; ' +
        '  { echo "[Desktop Entry]"; echo "X-Ether-Overlay=true"; ' +
        '    tail -n +2 "$src" | sed -e "s|^Exec=env MANGOHUD=1 |Exec=|" -e "s|^Exec=|Exec=env MANGOHUD=1 |"; ' +
        '  } > "$o.tmp" && mv "$o.tmp" "$o"; ' +
        'else ' +
        '  if [ -f "$o" ] && grep -q "^X-Ether-Overlay=true" "$o"; then rm -f "$o"; fi; ' +
        'fi'
    // copying a command for you to paste (Settings, Game overlay)
    function copyText(t) { Quickshell.execDetached(["wl-copy", "--", String(t)]) }

    readonly property var hyprKeys: ({
        gapsIn: "gaps_in", gapsOut: "gaps_out", borderSize: "border_size",
        rounding: "rounding", winActive: "active_opacity",
        winInactive: "inactive_opacity", blurSize: "blur_size",
        blurPasses: "blur_passes", animations: "animations",
        animSpeed: "anim_speed", gameMode: "game_mode", wsAnim: "ws_anim",
        vrr: "vrr", directScanout: "direct_scanout",
        repeatRate: "repeat_rate", repeatDelay: "repeat_delay",
        sensitivity: "sensitivity", accelFlat: "accel_flat",
        naturalScroll: "natural_scroll", followMouse: "follow_mouse",
        monitors: "monitors",
        mainScreen: "main_output", secondScreen: "second_output",
        wsMain: "main_workspaces", wsSecond: "second_workspaces",
        appTerminalCmd: "terminal", appFilesCmd: "file_manager",
        keybinds: "keybinds"
    })
    // plain values to Lua: booleans, finite numbers, simple strings and
    // tables of them (the monitors table); anything else is dropped
    function luaVal(v) {
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "number") return isFinite(v) ? String(v) : null
        if (typeof v === "string")
            return /^[\w .@:+\/=,-]*$/.test(v) ? JSON.stringify(v) : null
        if (Array.isArray(v)) {
            const nums = v.filter(x => Number.isInteger(x))
            return "{ " + nums.join(", ") + " }"
        }
        if (v && typeof v === "object" && !Array.isArray(v)) {
            const parts = []
            for (const k in v) {
                const inner = luaVal(v[k])
                if (inner !== null && /^[\w-]+$/.test(k))
                    parts.push("[" + JSON.stringify(k) + "] = " + inner)
            }
            return "{ " + parts.join(", ") + " }"
        }
        return null
    }

    function hyprText() {
        const lines = []
        for (const k in hyprKeys) {
            const v = Config.user[k]
            if (v === undefined) continue
            const lv = luaVal(v)
            if (lv === null) continue
            lines.push("    " + hyprKeys[k] + " = " + lv + ",")
        }
        // automatic game mode, while a game runs (a later key wins in Lua)
        if (sessionSvc.autoGame) lines.push("    game_mode = true,   -- a game is running")
        return "-- written by the quickshell settings panel; change values there\n"
             + "return {\n" + lines.join("\n") + (lines.length ? "\n" : "") + "}\n"
    }

    Timer {
        id: hyprDebounce
        interval: 150
        onTriggered: sessionSvc.writeHypr()
    }

    property string pendingHypr: ""
    function writeHypr() {
        pendingHypr = hyprText()
        if (!hyprWrite.running) flushHypr()
    }
    function flushHypr() {
        if (pendingHypr === "") return
        hyprWrite.command = ["sh", "-c",
            'f="$HOME/.config/hypr/shell-settings.lua"; ' +
            'printf "%s" "$1" > "$f.tmp" && mv "$f.tmp" "$f" && hyprctl reload >/dev/null; true',
            "sh", pendingHypr]
        pendingHypr = ""
        hyprWrite.running = true
    }
    Process {
        id: hyprWrite
        onExited: sessionSvc.flushHypr()
    }

    property string pendingKitty: ""
    function writeKitty() {
        pendingKitty = sessionSvc.termOpacity.toFixed(2)
        if (!kittyWrite.running) flushKitty()
    }
    function flushKitty() {
        if (pendingKitty === "") return
        kittyWrite.command = ["sh", "-c",
            'f="$HOME/.config/kitty/shell-settings.conf"; ' +
            'printf "# written by the quickshell settings panel; change it there\\nbackground_opacity %s\\n" "$1" > "$f.tmp" ' +
            '&& mv "$f.tmp" "$f" && pkill -USR1 -x kitty; true',
            "sh", pendingKitty]
        pendingKitty = ""
        kittyWrite.running = true
    }
    Process {
        id: kittyWrite
        onExited: sessionSvc.flushKitty()
    }

    // every setting change: pass it on to the program that reads it
    Connections {
        target: Config
        function onSettingChanged(key) { sessionSvc.applyExternal(key) }
    }
    function applyExternal(key) {
        if (key === "termOpacity" || key === "*") writeKitty()
        if (key === "*" || key === "clock24h" || key === "clockSeconds" || key.startsWith("lock"))
            lockDebounce.restart()
        if (key === "*" || hyprKeys[key] !== undefined) hyprDebounce.restart()
        if (key === "*" || key === "idleLockMin" || key === "idleScreenMin"
                || key === "idleSleepMin")
            idleDebounce.restart()
        if (key === "*" || key === "themeScheme" || key === "themeContrast"
                || key === "themePrefer" || key === "themeMode" || key === "accentStyle")
            Wallpaper.applyThemeSoon()
    }

    // settings sync (qs ipc call settings sync): write everything again
    function syncAll() { writeHypr(); writeKitty(); lockDebounce.restart() }
    // Hyprland's settings changed in another way (game mode starting): write them soon
    function applyHyprSoon() { hyprDebounce.restart() }
}
