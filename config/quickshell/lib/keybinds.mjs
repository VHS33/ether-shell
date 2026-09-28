// keybinds.mjs  (Ether Shell)
// The shortcuts Settings, Keybinds can change: each has a name, and its
// default (the same as in hyprland.lua's key() calls; a test keeps them in
// step).  Changes are saved as { name: "SUPER + W" } and handed to Hyprland
// through shell-settings.lua.  Settings imports this; the tests run it.

export const CATALOG = [
    // apps
    { id: "terminal",       group: "Apps",        label: "Terminal",                  def: "SUPER + T" },
    { id: "files",          group: "Apps",        label: "File manager",              def: "SUPER + E" },
    { id: "app_menu",       group: "Apps",        label: "App menu (rofi)",           def: "SUPER + R" },
    // windows
    { id: "close",          group: "Windows",     label: "Close window",              def: "SUPER + Q" },
    { id: "close_alt",      group: "Windows",     label: "Close window (second key)", def: "SUPER + C" },
    { id: "fullscreen",     group: "Windows",     label: "Fullscreen",                def: "SUPER + F" },
    { id: "maximise",       group: "Windows",     label: "Maximise",                  def: "SUPER + SHIFT + F" },
    { id: "float",          group: "Windows",     label: "Floating on or off",        def: "SUPER + SHIFT + V" },
    { id: "pseudo",         group: "Windows",     label: "Pseudotile",                def: "SUPER + P" },
    { id: "split",          group: "Windows",     label: "Split direction",           def: "SUPER + J" },
    { id: "focus_left",     group: "Windows",     label: "Focus left",                def: "SUPER + left" },
    { id: "focus_right",    group: "Windows",     label: "Focus right",               def: "SUPER + right" },
    { id: "focus_up",       group: "Windows",     label: "Focus up",                  def: "SUPER + up" },
    { id: "focus_down",     group: "Windows",     label: "Focus down",                def: "SUPER + down" },
    { id: "move_left",      group: "Windows",     label: "Move window left",          def: "SUPER + SHIFT + left" },
    { id: "move_right",     group: "Windows",     label: "Move window right",         def: "SUPER + SHIFT + right" },
    { id: "move_up",        group: "Windows",     label: "Move window up",            def: "SUPER + SHIFT + up" },
    { id: "move_down",      group: "Windows",     label: "Move window down",          def: "SUPER + SHIFT + down" },
    { id: "resize_left",    group: "Windows",     label: "Resize window left",        def: "SUPER + CTRL + left" },
    { id: "resize_right",   group: "Windows",     label: "Resize window right",       def: "SUPER + CTRL + right" },
    { id: "resize_up",      group: "Windows",     label: "Resize window up",          def: "SUPER + CTRL + up" },
    { id: "resize_down",    group: "Windows",     label: "Resize window down",        def: "SUPER + CTRL + down" },
    { id: "last_workspace", group: "Windows",     label: "Last workspace",            def: "SUPER + Tab" },
    // Ether Shell
    { id: "overview",       group: "Ether Shell", label: "Workspace overview",        def: "ALT + Tab" },
    { id: "clipboard",      group: "Ether Shell", label: "Clipboard history",         def: "SUPER + V" },
    { id: "ai",             group: "Ether Shell", label: "AI assistant",              def: "SUPER + A" },
    { id: "cheatsheet",     group: "Ether Shell", label: "Keybind cheatsheet",        def: "SUPER + slash" },
    { id: "quick",          group: "Ether Shell", label: "Quick settings",            def: "SUPER + N" },
    { id: "settings",       group: "Ether Shell", label: "Settings",                  def: "SUPER + comma" },
    { id: "emoji",          group: "Ether Shell", label: "Emoji picker",              def: "SUPER + period" },
    { id: "wallpaper",      group: "Ether Shell", label: "Wallpaper selector",        def: "SUPER + H" },
    { id: "power",          group: "Ether Shell", label: "Power menu",                def: "SUPER + X" },
    { id: "lock",           group: "Ether Shell", label: "Lock screen",               def: "SUPER + L" },
    // screenshots
    { id: "shot",           group: "Screenshots", label: "Screenshot a region",       def: "SUPER + S" },
    { id: "shot_full",      group: "Screenshots", label: "Screenshot the screen",     def: "SUPER + SHIFT + S" },
    { id: "ocr",            group: "Screenshots", label: "Copy text from the screen", def: "SUPER + SHIFT + T" },
]

// shortcuts that can't be changed here, but can't be taken either
export const FIXED = [
    ...Array.from({ length: 10 }, (_, i) => ({ combo: "SUPER + " + i, label: "Workspace " + (i === 0 ? 10 : i) })),
    ...Array.from({ length: 10 }, (_, i) => ({ combo: "SUPER + SHIFT + " + i, label: "Send to workspace " + (i === 0 ? 10 : i) })),
]

const MODS = ["SUPER", "CTRL", "ALT", "SHIFT"]
// keys spelled as Hyprland spells them
const NAMES = { left: "left", right: "right", up: "up", down: "down", tab: "Tab", return: "Return", space: "space",
                comma: "comma", period: "period", slash: "slash", backslash: "backslash", semicolon: "semicolon",
                apostrophe: "apostrophe", minus: "minus", equal: "equal", grave: "grave", bracketleft: "bracketleft",
                bracketright: "bracketright", home: "Home", end: "End", prior: "Prior", next: "Next",
                delete: "Delete", insert: "Insert", backspace: "BackSpace", print: "Print", escape: "Escape" }

// "shift+super + q" -> "SUPER + SHIFT + Q": the modifiers in one order, the
// key spelled as Hyprland spells it; "" when it isn't a single key with
// modifiers
export function normalise(combo) {
    const parts = String(combo || "").split("+").map(p => p.trim()).filter(p => p)
    const mods = [], keys = []
    for (const p of parts) {
        const u = p.toUpperCase()
        const m = u === "META" || u === "WIN" || u === "MOD4" ? "SUPER" : u === "CONTROL" ? "CTRL" : u
        if (MODS.includes(m)) { if (!mods.includes(m)) mods.push(m) }
        else keys.push(p)
    }
    if (keys.length !== 1) return ""
    let k = keys[0]
    if (/^[a-z]$/i.test(k)) k = k.toUpperCase()
    else if (/^f([1-9]|1\d|2[0-4])$/i.test(k)) k = k.toUpperCase()
    else if (/^\d$/.test(k)) k = k
    else if (NAMES[k.toLowerCase()]) k = NAMES[k.toLowerCase()]
    else return ""
    return MODS.filter(m => mods.includes(m)).concat([k]).join(" + ")
}

// why a combo can't be used ("" when it can)
export function problem(combo) {
    const n = normalise(combo)
    if (!n) return "That isn't a key Hyprland knows"
    const parts = n.split(" + ")
    const key = parts[parts.length - 1]
    if (parts.length === 1 && !/^F\d+$/.test(key) && key !== "Print")
        return "Add SUPER, CTRL or ALT, so typing " + key + " still types it"
    if (parts.length === 2 && parts[0] === "SHIFT" && !/^F\d+$/.test(key))
        return "SHIFT alone isn't enough: SHIFT + " + key + " types a capital or a symbol"
    return ""
}

// every shortcut as it is now: { id: combo }
export function effective(overrides) {
    const o = overrides || {}
    const out = {}
    for (const c of CATALOG) out[c.id] = normalise(o[c.id]) || c.def
    return out
}

// what already uses a combo (other than `id` itself): its label, or ""
export function clash(id, combo, overrides) {
    const n = normalise(combo)
    const now = effective(overrides)
    for (const c of CATALOG) if (c.id !== id && now[c.id] === n) return c.label
    for (const f of FIXED) if (f.combo === n) return f.label
    return ""
}
