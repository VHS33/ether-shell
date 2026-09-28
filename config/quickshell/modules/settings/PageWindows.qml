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
    visible: settingsWin.page === 5
    readonly property int pageNo: 5
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Spacing" }

    Card {
        app: settingsRoot.app
        title: "Gaps between windows"
        desc: "Space between tiled windows, in pixels."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 20
                tick: 4
                step: 1
                value: app.cfg.gapsIn
                label: Math.round(value) + " px"
                onMoved: v => app.setting("gapsIn", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.gapsIn === undefined ? 0 : -1
                onPicked: app.resetSetting("gapsIn")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Gaps at the screen edge"
        desc: "Space between windows and the edges of the screen."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 40
                tick: 1
                step: 1
                value: app.cfg.gapsOut
                label: Math.round(value) + " px"
                onMoved: v => app.setting("gapsOut", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.gapsOut === undefined ? 0 : -1
                onPicked: app.resetSetting("gapsOut")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Shape" }

    Card {
        app: settingsRoot.app
        title: "Corner rounding"
        desc: "Radius of window corners, in pixels. The shell's own panels keep their shape."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 24
                tick: 12
                step: 1
                value: app.cfg.rounding
                label: Math.round(value) + " px"
                onMoved: v => app.setting("rounding", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.rounding === undefined ? 0 : -1
                onPicked: app.resetSetting("rounding")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Border width"
        desc: "Thickness of the coloured border around windows. The colour follows the wallpaper."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 6
                tick: 2
                step: 1
                value: app.cfg.borderSize
                label: Math.round(value) + " px"
                onMoved: v => app.setting("borderSize", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.borderSize === undefined ? 0 : -1
                onPicked: app.resetSetting("borderSize")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Motion" }

    Card {
        app: settingsRoot.app
        title: "Animations"
        desc: "Windows, workspaces and layers slide and fade. Turning this off makes every change instant."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.animations === false ? 0 : 1
                onPicked: i => app.setting("animations", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Animation speed"
        desc: "Scales every animation together. 2× plays them in half the time."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.5
                to: 2
                tick: 1
                step: 0.1
                value: app.cfg.animSpeed
                label: value.toFixed(1) + "×"
                onMoved: v => app.setting("animSpeed", Math.round(v * 10) / 10)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.animSpeed === undefined ? 0 : -1
                onPicked: app.resetSetting("animSpeed")
            }
        ]
    }

    Card {
        id: wsAnimCard
        app: settingsRoot.app
        readonly property var styles: ["slide", "slidevert", "glide", "fade", "off"]
        readonly property int cur: Math.max(0, styles.indexOf(app.cfg.wsAnim || "slide"))
        title: "Switching workspaces"
        desc: ["Workspaces slide side to side, like moving along a row: higher numbers come in from the right.",
               "Workspaces slide up and down.",
               "A short slide with a fade: the new workspace drifts in gently.",
               "The old workspace fades out as the new one fades in.",
               "Workspaces change instantly."][cur]
              + (app.cfg.animations === false || app.gameMode ? " (Animations are off right now.)" : "")

        Seg {
            app: settingsRoot.app
            options: ["Slide", "Slide vertically", "Glide", "Fade", "Off"]
            current: wsAnimCard.cur
            onPicked: i => app.setting("wsAnim", wsAnimCard.styles[i])
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Gaming" }

    Card {
        app: settingsRoot.app
        title: "Automatic game mode"
        desc: app.cfg.autoGameMode !== false
              ? "When a game starts, animations and blur switch off and the shell does less in the background; everything comes back when it closes. Your own Game mode setting isn't touched. Steam games are recognised by themselves; mark others from the playtime card in the system drawer."
              : "Games are still recognised and their playtime kept, but the desktop doesn't change for them."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.autoGameMode !== false ? 1 : 0
                onPicked: i => app.setting("autoGameMode", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Notifications while gaming"
        desc: app.cfg.gameQuiet !== false
              ? "Held while a game runs: nothing pops up, and they're all waiting in quick settings afterwards. Do not disturb isn't changed."
              : "Shown as usual while a game runs."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Show", "Hold"]
                current: app.cfg.gameQuiet !== false ? 1 : 0
                onPicked: i => app.setting("gameQuiet", i === 1)
            }
        ]
    }

    Card {
        id: vrrCard
        app: settingsRoot.app
        // the choices, in order, as Hyprland's values
        readonly property var modes: [0, 2, 3, 1]
        readonly property int cur: Math.max(0, modes.indexOf(
            Number.isInteger(app.cfg.vrr) ? app.cfg.vrr : 2))
        title: "Variable refresh rate"
        desc: ["Off: the monitor always runs at its full refresh rate.",
               "G-SYNC / FreeSync for fullscreen windows: the monitor matches a game's frame rate, so dips don't stutter or tear. Off on the desktop, where some monitors flicker with it.",
               "Only for fullscreen windows that say they're games or video.",
               "Always on, including the desktop. Some monitors flicker with this."][cur]
        Seg {
            app: settingsRoot.app
            options: ["Off", "Fullscreen", "Games only", "Always"]
            current: vrrCard.cur
            onPicked: i => app.setting("vrr", vrrCard.modes[i])
        }
    }

    Card {
        id: scanCard
        app: settingsRoot.app
        readonly property var modes: [0, 2, 1]
        readonly property int cur: Math.max(0, modes.indexOf(
            Number.isInteger(app.cfg.directScanout) ? app.cfg.directScanout : 2))
        title: "Direct scanout"
        desc: ["Off: Hyprland composites every frame, even for fullscreen games.",
               "A fullscreen game's frames go straight to the monitor, skipping Hyprland: less input lag and GPU work. Only for windows that say they're games.",
               "Any fullscreen window's frames go straight to the monitor. If something flickers or looks wrong fullscreen, go back to Games."][cur]
        Seg {
            app: settingsRoot.app
            options: ["Off", "Games", "Any fullscreen"]
            current: scanCard.cur
            onPicked: i => app.setting("directScanout", scanCard.modes[i])
        }
    }
}
