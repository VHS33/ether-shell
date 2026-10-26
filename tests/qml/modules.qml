// Qt's own JavaScript engine loads the shared modules and gets the same
// answers as Node (tests/run.sh compares).
import QtQuick
import "../../config/quickshell/lib/colour.mjs" as Colour
import "../../config/quickshell/lib/text.mjs" as TextLib
// every other module too, so one Qt's engine can't read is caught here
// (it once read { ...object } spread, which Node accepts and Qt doesn't)
import "../../config/quickshell/lib/plugins.mjs" as PluginsLib
import "../../config/quickshell/lib/search.mjs" as SearchLib
import "../../config/quickshell/lib/layout.mjs" as LayoutLib
import "../../config/quickshell/lib/models.mjs" as ModelsLib
import "../../config/quickshell/lib/keybinds.mjs" as KeybindsLib
import "../../config/quickshell/lib/overlay.mjs" as OverlayLib
import "../../config/quickshell/lib/profiles.mjs" as ProfilesLib
import "../../config/quickshell/lib/windows.mjs" as WinLib
import "../../config/quickshell/lib/settingsindex.mjs" as SetIndex
import "../../config/quickshell/lib/screens.mjs" as ScreensLib
// the shipped plugins' own modules too
import "../../plugins/countdown/Countdown.mjs" as CountdownLib
QtObject {
    Component.onCompleted: {
        const out = {
            accents: [["#5d0d09", "#1a1110"], ["#2a568f", "#111318"], ["#d66c4c", "#fff8f6"], ["#808080", "#101010"]]
                     .map(p => Colour.readableAccent(p[0], p[1])),
            text: Colour.textOn("#d66c4c", "#1a110f", "#f1dfda"),
            third: Colour.thirdAccent("#d66c4c", "#c9c5a0", "#3e79a3", "scheme-content", true),
            typo: TextLib.oneTypo("firefox", "fierfox"),
            calc: TextLib.calc("2^10 + sqrt(16)"),
            fromQt: Colour.readableAccent(Qt.color("#5d0d09").toString(), Qt.color("#1a1110").toString()),
            // run, not only read: a function Qt's engine lacks (matchAll) only fails when called
            win: [WinLib.command("move to 4"), WinLib.bareTitle("YouTube \u2014 Mozilla Firefox", "Firefox")],
            scr: ScreensLib.tiles(ScreensLib.draftOf([{ name: "A", w: 2560, h: 1440, hz: 165, scale: 1, modes: ["2560x1440@165.00Hz", "1920x1080@60.00Hz"] }, { name: "B", w: 1920, h: 1080, hz: 60, scale: 1, modes: ["1920x1080@60.00Hz"] }]), { A: { x: 0, y: 0 }, B: { x: 2560, y: 0 } }, "A"),
            set: SetIndex.parsePage('readonly property int pageNo: 11\nSectionLabel { text: "Pointer" }\nCard {\n title: "Natural scrolling"\n Seg {\n options: ["Off", "On"]\n current: app.cfg.naturalScroll === true ? 1 : 0\n onPicked: i => app.setting("naturalScroll", i === 1)\n }\n}\n').entries
        }
        console.log("RESULT " + JSON.stringify(out))
        Qt.quit()
    }
}
