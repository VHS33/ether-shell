pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.common
import "../lib/keybinds.mjs" as KeybindsLib

// Your keyboard shortcuts (Settings > Keybinds): the changes you've made
// (only those are saved; hyprland.lua has the defaults, and
// lib/keybinds.mjs the list), changing and resetting them, and taking keys
// while you press a new one (Hyprland is switched to an empty submap,
// "ether-keys", so the keys reach Settings instead of firing).  Use it
// anywhere as Shortcuts.keybinds, .setKeybind(id, combo)... (import
// qs.services).  Also the cheatsheet's list: every bind Hyprland has now
// (hyprctl binds -j), read when it opens (refreshCheat).  Nothing here goes
// over the network.
Singleton {
    id: shortcutsSvc

    // ---- keybinds (Settings, Keybinds) ----
    // Only changes are saved, by each shortcut's name (lib/keybinds.mjs);
    // Hyprland reads them from shell-settings.lua (key() in hyprland.lua).
    readonly property var keybinds: Config.cfg.keybinds && typeof Config.cfg.keybinds === "object" ? Config.cfg.keybinds : ({})
    function setKeybind(id, combo) {
        const o = Object.assign({}, keybinds)
        const n = KeybindsLib.normalise(combo)
        const c = KeybindsLib.CATALOG.find(x => x.id === id)
        if (!c || !n) return
        if (n === c.def) delete o[id]; else o[id] = n
        Config.setting("keybinds", o)
    }
    function resetKeybind(id) {
        const o = Object.assign({}, keybinds); delete o[id]
        if (Object.keys(o).length) Config.setting("keybinds", o); else Config.resetSetting("keybinds")
    }
    function resetKeybinds() { Config.resetSetting("keybinds") }
    // While Settings waits for a new shortcut, Hyprland uses its empty keymap
    // ("ether-keys"), so the keys reach Settings.  keysCapturing turns false
    // if something else switches it back (Escape, in that keymap).
    property bool keysCapturing: false
    function captureKeys(on) {
        keysCapturing = on
        Hyprland.dispatch(on ? 'hl.dsp.submap("ether-keys")' : 'hl.dsp.submap("reset")')
    }
    Connections {
        target: Hyprland
        enabled: shortcutsSvc.keysCapturing
        function onRawEvent(event) {
            if (event.name === "submap" && String(event.data || "") !== "ether-keys") shortcutsSvc.keysCapturing = false
        }
    }

    // ---- the cheatsheet (SUPER + /): every bind Hyprland has now ----
    property var cheatBinds: []

    function refreshCheat() { cheatProc.running = true }

    readonly property var modNames: [
        [64, "SUPER"], [8, "ALT"], [4, "CTRL"], [1, "SHIFT"]
    ]

    function modString(mask) {
        const out = []
        for (const [bit, name] of shortcutsSvc.modNames) {
            if (mask & bit) out.push(name)
        }
        return out
    }

    Process {
        id: cheatProc
        command: ["sh", "-c", "hyprctl binds -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = []
                try {
                    raw = JSON.parse(text)
                } catch (e) {
                    console.log("cheatsheet: could not parse binds:", e)
                    return
                }

                // key names people recognise
                const pretty = {
                    "SUPER_L": "SUPER (tap)", "slash": "/", "Tab": "Tab",
                    "mouse:272": "Left drag", "mouse:273": "Right drag",
                    "mouse_down": "Scroll down", "mouse_up": "Scroll up",
                    "left": "\u2190", "right": "\u2192", "up": "\u2191", "down": "\u2193",
                    "XF86AudioRaiseVolume": "Volume up key", "XF86AudioLowerVolume": "Volume down key",
                    "XF86AudioMute": "Mute key", "XF86AudioMicMute": "Mic mute key",
                    "XF86MonBrightnessUp": "Brightness up key", "XF86MonBrightnessDown": "Brightness down key",
                    "XF86AudioNext": "Next key", "XF86AudioPrev": "Previous key",
                    "XF86AudioPlay": "Play key", "XF86AudioPause": "Pause key"
                }
                // which group a bind belongs to, from its description
                const groupOf = l => {
                    if (/^(Go to|Send window to) workspace|workspace|overview/i.test(l)) return "Workspaces"
                    if (/screenshot|text from the screen/i.test(l)) return "Screenshots"
                    if (/volume|mute|brightness|track|play|pause/i.test(l)) return "Media"
                    if (/window|float|pseudotile|split|focus|drag|resize|fullscreen|maximi/i.test(l)) return "Windows"
                    if (/terminal|file manager|app menu|launcher/i.test(l)) return "Apps"
                    return "Shell"
                }

                const out = []
                const seen = {}
                for (const b of raw) {
                    const key = b.key ?? ""
                    if (!key.length) continue

                    let label = b.description ?? ""
                    if (!label.length) {
                        const d = b.dispatcher ?? ""
                        label = d === "__lua" ? "(lua)" : d
                    }

                    const mods = shortcutsSvc.modString(b.modmask ?? 0)
                    // SUPER_L is the tap itself, not a modifier plus a key
                    let keys = key === "SUPER_L" ? ["SUPER (tap)"]
                             : mods.concat([pretty[key] ?? (key.length === 1 ? key.toUpperCase() : key)])

                    // twenty workspace binds become two rows
                    if (/^Workspace \d+$/.test(label)) {
                        label = "Go to workspace"
                        keys = mods.concat(["1 \u2026 0"])
                    } else if (/^Send to workspace \d+$/.test(label)) {
                        label = "Send window to workspace"
                        keys = mods.concat(["1 \u2026 0"])
                    }

                    const id = keys.join("+") + "|" + label
                    if (seen[id]) continue
                    seen[id] = true
                    out.push({ keys: keys, label: label, group: groupOf(label) })
                }
                shortcutsSvc.cheatBinds = out
            }
        }
    }
}
