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
    visible: settingsWin.page === 25
    readonly property int pageNo: 25
    spacing: 4

    Card {
        app: settingsRoot.app
        title: "Game overlay"
        desc: "Frame rate, frame times, GPU and CPU load and temperatures, drawn over your games by MangoHud, in your theme's colours. Right SHIFT + F12 shows or hides it in a game."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "All Steam games", "Games I choose"]
                current: ["off", "steam", "choose"].indexOf(app.gameHud)
                onPicked: i => app.setting("gameHud", ["off", "steam", "choose"][i])
            }
        ]
    }

    Card {
        app: settingsRoot.app
        visible: app.gameHud !== "off" && !app.mangoOk
        color: Qt.rgba(app.cRed.r, app.cRed.g, app.cRed.b, 0.14)
        title: "MangoHud isn't installed"
        desc: "It draws the overlay. Install it (both parts, for 64 and 32-bit games): sudo pacman -S mangohud lib32-mangohud"
        trailing: [
            Seg { app: settingsRoot.app; options: ["Copy the command"]; current: -1; onPicked: app.copyText("sudo pacman -S mangohud lib32-mangohud") }
        ]
    }
    Card {
        app: settingsRoot.app
        visible: app.gameHud === "steam"
        title: "Restart Steam once"
        desc: "Then every game Steam starts has the overlay (Steam's own windows don't). Start Steam from the launcher or the dock; if it starts with your computer, quit it and start it again from there."
    }
    Card {
        app: settingsRoot.app
        visible: app.gameHud === "choose"
        title: "Choosing games"
        desc: "In Steam, a game's Properties, then Launch options: put mangohud %command% there. For other launchers, start the game with mangohud in front."
        trailing: [
            Seg { app: settingsRoot.app; options: ["Copy"]; current: -1; onPicked: app.copyText("mangohud %command%") }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "What it shows"; visible: app.gameHud !== "off" }
    Card {
        app: settingsRoot.app
        visible: app.gameHud !== "off"
        title: "Layout"
        desc: (app.cfg.gameHudLayout || "standard") === "fps" ? "Just the frame rate: small, out of the way."
              : app.cfg.gameHudLayout === "full" ? "Everything: clocks, power, the GPU's name, resolution and Proton's version too."
              : "Frame rate and frame times, GPU and CPU load and temperatures, video and main memory."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Frame rate", "Standard", "Everything"]
                current: Math.max(0, ["fps", "standard", "full"].indexOf(app.cfg.gameHudLayout || "standard"))
                onPicked: i => app.setting("gameHudLayout", ["fps", "standard", "full"][i])
            }
        ]
    }
    Card {
        app: settingsRoot.app
        visible: app.gameHud !== "off"
        title: "Where"
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Top left", "Top centre", "Top right", "Bottom left", "Bottom right"]
                current: Math.max(0, ["top-left", "top-center", "top-right", "bottom-left", "bottom-right"].indexOf(app.cfg.gameHudPos || "top-left"))
                onPicked: i => app.setting("gameHudPos", ["top-left", "top-center", "top-right", "bottom-left", "bottom-right"][i])
            }
        ]
    }
    Card {
        app: settingsRoot.app
        visible: app.gameHud !== "off"
        title: "Size"
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Small", "Normal", "Large"]
                current: Math.max(0, ["small", "normal", "large"].indexOf(app.cfg.gameHudSize || "normal"))
                onPicked: i => app.setting("gameHudSize", ["small", "normal", "large"][i])
            }
        ]
    }
    Card {
        app: settingsRoot.app
        visible: app.gameHud !== "off"
        title: "When a game starts"
        desc: app.cfg.gameHudHidden === true ? "Hidden until you press right SHIFT + F12." : "Showing; right SHIFT + F12 hides it."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Showing", "Hidden"]
                current: app.cfg.gameHudHidden === true ? 1 : 0
                onPicked: i => app.setting("gameHudHidden", i === 1)
            }
        ]
    }
}
