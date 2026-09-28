pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../lib/colour.mjs" as Colour

// The shell's colours.  The palette matugen makes from the wallpaper
// (~/.config/quickshell/colors.json), the colours everything draws with
// (cBg, cFg, cBlue the accent, cPeach, cGreen...), the accent rules (the
// wallpaper's own colour, readable: lib/colour.mjs, the same rule as
// setwall's), light or dark, the half-second fade when the theme changes,
// and the now-playing colours from the album art (mBlue...).  Use it
// anywhere as Theme.cBlue, Theme.scrim(0.4)... (import qs.services).
//
// The wallpaper's measured colours (wallSeed, wallSecond...) are written
// here by the wallpaper code, and the album art's (artAccent...) by the
// native plugin.  It tells the shell when a palette has loaded
// (paletteLoaded).  The shell passes in whether the native plugin is there
// (nativeOk).  Nothing here goes over the network.
Singleton {
    id: themeSvc

    property bool nativeOk: false
    signal paletteLoaded()

    // Palette generated from the wallpaper by matugen; falls back to
    // Catppuccin Mocha when no palette has been generated yet.
    property var pal: ({})


    function withAlpha(hex, aa) {
        if (!hex) return undefined
        return "#" + aa + hex.replace("#", "")
    }

    // every shell surface (bar pills, dock, sidebar, cards, popups)
    // takes one opacity from settings (bgOpacity), matching the
    // terminal's default so the whole desktop reads as one material
    function hexA(a) {
        const v = Math.round(Math.max(0, Math.min(1, a)) * 255)
        return (v < 16 ? "0" : "") + v.toString(16)
    }
    readonly property real bgA:
        Math.max(0.3, Math.min(1, Number(Config.cfg.bgOpacity) || 0.75))
    property color cBg:     withAlpha(pal.bg ?? "#1e1e2e", hexA(bgA))
    property color cCard:   withAlpha(pal.card ?? "#1e1e2e", hexA(bgA))
    property color cSurf:   pal.surf   ?? "#313244"
    property color cTile:   withAlpha(pal.tile, "33") ?? "#33313244"
    property color cBorder: pal.border ?? "#414356"
    property color cFg:     pal.fg     ?? "#cdd6f4"
    property color cDim:    pal.dim    ?? "#a6adc8"
    property color cFaint:  pal.faint  ?? "#6c7086"
    // ---- the accent: the wallpaper's own colour (Settings > Theme > Accent) ----
    // Material's dark themes always use a light version of the colour (its
    // tone 80), so an orange wallpaper gets a soft salmon accent.  "vivid"
    // (the default) uses the wallpaper's actual colour, adjusted only when it
    // wouldn't be readable: lightened (or darkened, on a light theme) just
    // until it has 4.5:1 contrast with the background, keeping its hue.  Text
    // on it is dark or light, whichever reads better.  Greyscale wallpapers,
    // and the monochrome and neutral styles, keep Material's colours.
    readonly property bool vividOn: Config.cfg.accentStyle !== "soft" && smartOn && wallSeed !== ""
                                    && wallWhy !== "no strong colour"
                                    && themeScheme !== "scheme-monochrome" && themeScheme !== "scheme-neutral"
    // The colour rules live in lib/colour.mjs: shared with the tests, and the
    // same calculation as setwall's awk, so the shell and every app agree.
    // These keep the names the rest of the shell uses.
    function hexOf(c) { return Qt.color(c).toString() }
    function contrast(a, b) { return Colour.contrast(hexOf(a), hexOf(b)) }
    function readableAccent(colour, bg) { return Qt.color(Colour.readableAccent(hexOf(colour), hexOf(bg))) }
    function textOn(accent, darkText, lightText) {
        return Colour.contrast(hexOf(accent), hexOf(darkText)) >= Colour.contrast(hexOf(accent), hexOf(lightText))
               ? darkText : lightText
    }
    // setwall works the accent out for every app (vivid or soft, by the same
    // rule) and writes it as pal.vivid; before a theme with it has been made,
    // the shell works it out itself
    property color cBlue: pal.vivid ?? (vividOn ? readableAccent(wallSeed, pal.bg ?? "#1e1e2e") : (pal.blue ?? "#89b4fa"))
    // The shell's third accent, from the picture itself.  Material builds the
    // third accent by turning the main colour round the colour wheel, which
    // often lands on a colour that isn't in the wallpaper (teal beside an
    // orange picture).  With the smart colour: the picture's own second
    // colour when it has one, otherwise a close neighbour of the main colour;
    // at the palette's own third-accent lightness, so it sits in the theme.
    // Monochrome and neutral keep theirs (their greys are the point).
    readonly property color palGreen:  pal.green  ?? "#a6e3a1"
    function thirdAccent(primary, tertiary, second, scheme) {
        return Qt.color(Colour.thirdAccent(hexOf(primary), hexOf(tertiary), second ? hexOf(second) : "", scheme, smartOn))
    }
    // second and third accents: with the vivid accent, the picture's own
    // second and third colours (setwall makes them readable); Material's
    // otherwise.  (thirdAccent for colour files from before these existed.)
    property color cGreen: pal.third ?? thirdAccent(pal.blue ?? "#89b4fa", palGreen, wallSecond, themeScheme)
    property color cPeach:  pal.second ?? pal.peach ?? "#fab387"
    // light mode swaps the three pastel "fixed" accents for darker
    // companions, which would otherwise wash out on a light background
    // Light, dark, or "auto": light for wallpapers that look bright (their
    // lightness, 0-100, measured by the native plugin; above 60 is light).
    // Without the plugin, auto stays dark.
    readonly property bool isLight: Config.cfg.themeMode === "light"
                                    || (Config.cfg.themeMode === "auto" && wallLightness > 60)
    property real wallLightness: -1
    property color cMauve:  (isLight ? pal.mauveL : pal.mauve) ?? "#cba6f7"
    property color cTeal:   (isLight ? pal.tealL : pal.teal)   ?? "#94e2d5"
    property color cRed:    pal.red    ?? "#f38ba8"
    property color cYellow: (isLight ? pal.yellowL : pal.yellow) ?? "#f9e2af"
    // text and icons drawn on top of an accent colour
    property color cOnAccent: pal.onVivid ?? (vividOn ? textOn(cBlue, pal.bg ?? "#1e1e2e", pal.fg ?? "#cdd6f4")
                                                      : (pal.onAccent ?? "#1e1e2e"))
    // Material's filled-but-deeper accent (the clock's group, tiles that
    // are on) and the text that sits on it.  Until matugen has written
    // them, a mix of the accent and the background stands in.
    property color cPrimC: pal.primaryC ?? Qt.tint(pal.bg ?? "#1e1e2e",
                                                    Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.35))
    property color cOnPrimC: pal.onPrimaryC ?? cFg

    // ---- theme changes fade instead of snapping ----
    // Each colour eases to its new value over about half a second.  Off
    // until the first palette has loaded, so the shell doesn't sweep in
    // from its fallback colours at every login.
    property bool colourFade: false
    Timer { id: fadeOn; interval: 800; onTriggered: themeSvc.colourFade = true }
    Behavior on cBg { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cCard { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cSurf { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cTile { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cBorder { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cFg { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cDim { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cFaint { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cBlue { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cGreen { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cPeach { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cMauve { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cTeal { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cRed { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cYellow { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cOnAccent { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cPrimC { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on cOnPrimC { enabled: themeSvc.colourFade; ColorAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    // dimming layers: the background colour at a given strength
    function scrim(a) { return withAlpha(pal.bg ?? "#1e1e2e", hexA(a)) }
    readonly property string font:   "JetBrainsMono Nerd Font"

    readonly property var themeSchemes: [
        "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
        "scheme-fidelity", "scheme-content", "scheme-fruit-salad",
        "scheme-rainbow", "scheme-neutral", "scheme-monochrome",
        "scheme-smart"
    ]
    // "auto": Ether Shell picks the style for each wallpaper (monochrome,
    // neutral, fidelity or tonal spot, from how colourful it is and how much
    // of its colour is one hue; measured by the native plugin)
    readonly property string themeScheme:
        Config.cfg.themeScheme === "auto" ? (wallScheme || "scheme-tonal-spot")
        : themeSchemes.indexOf(Config.cfg.themeScheme) >= 0 ? Config.cfg.themeScheme : "scheme-tonal-spot"
    property string wallScheme: ""
    property string wallSeed: ""
    property string wallSecond: ""
    property string wallThird: ""
    property string wallWhy: ""
    readonly property bool smartOn: themePrefer === "smart" && themeSvc.nativeOk
    property real wallColourfulness: -1
    readonly property var themePrefers: [ "smart", "dominant", 
        "saturation", "less-saturation", "darkness", "lightness", "value"
    ]
    readonly property string themePrefer:
        themePrefers.indexOf(Config.cfg.themePrefer) >= 0 ? Config.cfg.themePrefer : "smart"
    readonly property real themeContrast:
        Math.max(-1, Math.min(1, Number(Config.cfg.themeContrast) || 0))

    // ---- now-Media.playing colours ---------------------------------------------
    // While something plays, the media views (the media drawer, the bar's
    // media pill, quick settings' mini player and the island's song card)
    // take their accent colours from the album art, and fade back to the
    // wallpaper's when it stops.  The colours come from ArtColors in the
    // native plugin (via NativeStats.qml); without it, they stay the theme's.
    // Everything else keeps the wallpaper theme.
    property bool artValid: false
    property color artAccent: cBlue
    property color artOnAccent: cOnAccent
    property color artContainer: cPrimC
    property color artOnContainer: cOnPrimC
    readonly property bool darkTheme: (cBg.r * 0.299 + cBg.g * 0.587 + cBg.b * 0.114) < 0.5
    readonly property bool artOn: Config.cfg.artColors !== false && artValid && Media.playing
    // what the media views use
    property color mBlue: artOn ? artAccent : cBlue
    property color mOnAccent: artOn ? artOnAccent : cOnAccent
    property color mPrimC: artOn ? artContainer : cPrimC
    property color mOnPrimC: artOn ? artOnContainer : cOnPrimC
    Behavior on mBlue { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mOnAccent { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mPrimC { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on mOnPrimC { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }


    // read the matugen-generated palette at startup
    Process {
        id: palProc
        running: true
        command: ["sh", "-c",
            "cat ~/.config/quickshell/colors.json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t.length) return
                try {
                    themeSvc.pal = JSON.parse(t)
                    if (!themeSvc.colourFade) fadeOn.start()
                    themeSvc.paletteLoaded()             // the shell: the login screen shows the new look too
                } catch (e) {
                    console.log("palette parse failed:", e)
                }
            }
        }
    }

    function reloadPalette() { palProc.running = true }
}
