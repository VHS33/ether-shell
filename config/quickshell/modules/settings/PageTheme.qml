import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 2
    readonly property int pageNo: 2
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Mode" }

    Card {
        app: settingsRoot.app
        title: "Appearance"
        desc: app.cfg.themeMode === "auto"
              ? (app.nativeOk
                 ? "Chosen by the wallpaper: light for bright ones, dark for the rest (this one is "
                   + (app.wallLightness < 0 ? "being measured" : app.isLight ? "bright, so light" : "dark enough for dark") + ")."
                 : "Auto needs the native plugin, which isn't built: re-run the installer. Until then it stays dark.")
              : "Light or dark palette from the same wallpaper, for the shell, terminal, launcher, lock screen and GTK and KDE apps. Auto picks by how bright the wallpaper is."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Dark", "Light", "Auto"]
                current: app.cfg.themeMode === "auto" ? 2 : app.isLight ? 1 : 0
                onPicked: i => app.setting("themeMode", ["dark", "light", "auto"][i])
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Colour style" }

    Card {
        app: settingsRoot.app
        title: "Style"
        desc: app.themeBusy
              ? "Applying to every app\u2026"
              : "How matugen turns the wallpaper into a palette. Picking one retints the shell, terminal, launcher, borders and apps."

        Repeater {
            model: [
                { k: "auto",               t: "Auto",        d: app.cfg.themeScheme === "auto" && app.wallScheme
                    ? "Picked for each wallpaper: this one is " + ({ "scheme-monochrome": "black and white, so monochrome",
                        "scheme-neutral": "muted, so neutral", "scheme-content": "mostly one bold colour, so content, which keeps close to it",
                        "scheme-fidelity": "mostly one bold colour, so fidelity",
                        "scheme-tonal-spot": "colourful and varied, so tonal spot" })[app.wallScheme] + "."
                    : app.nativeOk ? "Picked for each wallpaper, from how colourful it is and how much of it is one colour."
                    : "Needs the native plugin, which isn't built: re-run the installer. Until then, tonal spot." },
                { k: "scheme-tonal-spot",  t: "Tonal spot",  d: "Calm and balanced, with soft accents from the wallpaper's main colour." },
                { k: "scheme-vibrant",     t: "Vibrant",     d: "Saturated accents that pop more than the wallpaper itself." },
                { k: "scheme-expressive",  t: "Expressive",  d: "Shifts hues away from the wallpaper for a more playful contrast." },
                { k: "scheme-fidelity",    t: "Fidelity",    d: "Stays as close as it can to the wallpaper's actual colours." },
                { k: "scheme-content",     t: "Content",     d: "Like fidelity, tuned so images and artwork sit naturally beside it." },
                { k: "scheme-fruit-salad", t: "Fruit salad", d: "Bold, rotated hues, bright and mixed." },
                { k: "scheme-rainbow",     t: "Rainbow",     d: "Colourful accents over neutral backgrounds." },
                { k: "scheme-neutral",     t: "Neutral",     d: "Nearly grey, with just a hint of the wallpaper." },
                { k: "scheme-monochrome",  t: "Monochrome",  d: "Pure greys, no colour at all." },
                { k: "scheme-smart",       t: "matugen's choice", d: "matugen picks the style by itself. Auto, at the top, is Ether Shell's own choice, and reads the wallpaper better." }
            ]
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.t
                desc: modelData.d
                selected: (app.cfg.themeScheme === "auto" ? "auto" : app.themeScheme) === modelData.k
                onChosen: app.setting("themeScheme", modelData.k)
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Colour source" }

    Card {
        app: settingsRoot.app
        title: "Source colour"
        desc: "Most wallpapers hold several candidate colours. This decides which one the whole palette is built from."

        Repeater {
            model: [
                { k: "smart",           t: "Smart", d: !app.nativeOk
                    ? "Needs the native plugin, which isn't built: re-run the installer. Until then, most of the picture."
                    : app.themePrefer === "smart" && app.wallWhy
                    ? "Ether Shell's own pick for this wallpaper: " + (app.wallWhy === "no strong colour"
                          ? "it has no strong colour, so its own soft tint."
                          : "the colour of " + app.wallWhy + (app.wallSecond ? ", with its second colour as the third accent." : "."))
                    : "Ether Shell's own pick: the subject over the backdrop, skin tones set aside, borders ignored. Recommended." },
                { k: "dominant",        t: "Most of the picture", d: "The colour covering most of the wallpaper, scored as Material You does on Android. Palettes look like the wallpaper." },
                { k: "saturation",      t: "Most vivid",  d: "The most colourful part of the image, even a small detail (a light, a highlight), so different wallpapers can come out alike." },
                { k: "less-saturation", t: "Most muted",  d: "A softer, greyer colour from the image." },
                { k: "darkness",        t: "Darkest",     d: "Drawn from the image's deep tones." },
                { k: "lightness",       t: "Lightest",    d: "Drawn from the pale parts of the image." },
                { k: "value",           t: "Brightest",   d: "The most luminous colour, whatever its hue." }
            ]
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.t
                desc: modelData.d
                selected: app.themePrefer === modelData.k
                onChosen: app.setting("themePrefer", modelData.k)
            }
        }
    }

    Card {
        app: settingsRoot.app
        title: "Accent"
        desc: app.cfg.accentStyle === "soft"
              ? "A soft, lighter version of the wallpaper's colour, as Material You uses on Android."
              : "The wallpaper's own colour, as it is, everywhere: the shell, window borders, the terminal, your prompt, the lock screen, and GTK and KDE apps. Lightened only when it wouldn't be readable. Needs the Smart colour source; greyscale wallpapers keep soft accents."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Vivid", "Soft"]
                current: app.cfg.accentStyle === "soft" ? 1 : 0
                onPicked: i => app.setting("accentStyle", i === 1 ? "soft" : "vivid")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Now playing" }

    Card {
        app: settingsRoot.app
        title: "Colours from album art"
        desc: app.cfg.artColors === false
              ? "The media views keep your wallpaper's colours."
              : !app.nativeOk
              ? "Needs the native plugin, which isn't built: re-run the installer to build it. Until then the media views keep your wallpaper's colours."
              : "While something plays, the media drawer, the bar's media pill, the mini player and the island's song card take their colours from the album art, and fade back to your wallpaper's when it stops. Everything else keeps your wallpaper's colours."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.artColors !== false ? 1 : 0
                onPicked: i => app.setting("artColors", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Contrast" }

    Card {
        app: settingsRoot.app
        title: "Contrast"
        desc: "Pushes text and accents further from their backgrounds, or softens them. Applies a moment after you stop changing it."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: -1
                to: 1
                origin: 0
                tick: 0
                step: 0.1
                value: app.themeContrast
                label: Math.abs(value) < 0.05 ? "Standard"
                     : (value > 0 ? "+" : "") + value.toFixed(1)
                onMoved: v => app.setting("themeContrast",
                                          Math.round(v * 10) / 10)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.themeContrast === undefined ? 0 : -1
                onPicked: app.resetSetting("themeContrast")
            }
        ]
    }
}
