// overlay.mjs  (Ether Shell)
// The in-game overlay: MangoHud, set up from Settings, Game overlay, and
// themed from the wallpaper.  This writes its MangoHud.conf.  Every
// measurement is set on or off explicitly, so nothing depends on MangoHud's
// own defaults (option names checked against MangoHud's example config).
// Settings imports this; the tests run it.

// what each layout shows
export const LAYOUTS = {
    fps:      ["fps"],
    standard: ["fps", "frametime", "frame_timing", "gpu_stats", "gpu_temp", "cpu_stats", "cpu_temp", "vram", "ram"],
    full:     ["fps", "frametime", "frame_timing", "gpu_stats", "gpu_temp", "gpu_core_clock", "gpu_power", "gpu_name",
               "cpu_stats", "cpu_temp", "cpu_mhz", "cpu_power", "vram", "ram", "resolution", "wine"],
}
const ALL = ["fps", "frametime", "frame_timing", "gpu_stats", "gpu_temp", "gpu_core_clock", "gpu_power", "gpu_name",
             "cpu_stats", "cpu_temp", "cpu_mhz", "cpu_power", "vram", "ram", "resolution", "wine", "throttling_status"]
export const POSITIONS = ["top-left", "top-center", "top-right", "bottom-left", "bottom-right"]
export const SIZES = { small: 18, normal: 22, large: 28 }
export const TOGGLE_KEY = "Shift_R+F12"            // MangoHud's own; shown in Settings

// "#d66c4c" (or a Qt colour's text) -> "D66C4C"; the fallback if it isn't one
function hex(c, fallback) {
    const m = /^#?([0-9a-fA-F]{6})$/.exec(String(c || "").trim())
    return m ? m[1].toUpperCase() : fallback
}

// o: { layout, position, size, hidden, font, colours: { bg, fg, accent, second, third, red, yellow } }
export function mangoConfig(o) {
    const layout = LAYOUTS[o.layout] ? o.layout : "standard"
    const on = LAYOUTS[layout]
    const c = o.colours || {}
    const accent = hex(c.accent, "D66C4C")
    const lines = [
        "# Written by Ether Shell (Settings, Game overlay): change it there.",
        "# A MangoHud.conf of your own from before is kept as MangoHud.conf.before-ether.",
        "",
        "position=" + (POSITIONS.includes(o.position) ? o.position : "top-left"),
        "font_size=" + (SIZES[o.size] || SIZES.normal),
    ]
    if (typeof o.font === "string" && /^\/[\w./ -]+\.(ttf|otf)$/i.test(o.font)) lines.push("font_file=" + o.font)
    lines.push(
        "round_corners=12",
        "background_alpha=0.55",
        "background_color=" + hex(c.bg, "1A110F"),
        "text_color=" + hex(c.fg, "F1DFDA"),
        "gpu_color=" + accent,
        "cpu_color=" + hex(c.second, "EBCBA5"),
        "vram_color=" + hex(c.third, "A5A09F"),
        "ram_color=" + hex(c.third, "A5A09F"),
        "frametime_color=" + accent,
        "text_outline=1",
        // the frame rate's colour: red below 30, yellow below 60, the accent above
        "fps_color_change",
        "fps_value=30,60",
        "fps_color=" + hex(c.red, "FFB4AB") + "," + hex(c.yellow, "FDFD09") + "," + accent,
        "toggle_hud=" + TOGGLE_KEY,
    )
    if (o.hidden) lines.push("no_display")
    lines.push("")
    if (layout === "fps") lines.push("fps_only=1")
    for (const k of ALL) lines.push(k + "=" + (on.includes(k) ? 1 : 0))
    return lines.join("\n") + "\n"
}
