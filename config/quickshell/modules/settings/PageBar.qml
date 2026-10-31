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
    visible: settingsWin.page === 4
    readonly property int pageNo: 4
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Clock" }

    Card {
        app: settingsRoot.app
        title: "Time format"
        desc: "Right now the bar reads " + Qt.formatDateTime(app.now, app.clockFormat).replace(/ +/g, " ")
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["12-hour", "24-hour"]
                current: app.cfg.clock24h === true ? 1 : 0
                onPicked: i => app.setting("clock24h", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Seconds"
        desc: "Adds seconds to the time."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.clockSeconds === true ? 1 : 0
                onPicked: i => app.setting("clockSeconds", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Date"
        desc: "Shows the weekday and date before the time."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.clockDate !== false ? 1 : 0
                onPicked: i => app.setting("clockDate", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Style" }

    Card {
        app: settingsRoot.app
        title: "Bar style"
        desc: app.barWrap
              ? "The bar runs along the whole top edge and curves into the screen's sides. Its sections open cards that hang straight from it."
              : app.barAttached
              ? "One long bar across the top. Its sections open cards that slide out from behind it."
              : "Three separate floating pills that grow into panels."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Long bar", "Wrap", "Islands"]
                current: app.barWrap ? 1 : app.barAttached ? 0 : 2
                onPicked: i => {
                    app.cardShown = false
                    app.quickShown = false
                    app.sysShown = false
                    app.aiShown = false
                    app.setting("barStyle", ["long", "wrap", "islands"][i])
                }
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Corners"
        desc: "How sharp the corners are, from square boxes to round pills, everywhere: the bar and its panels, the launcher, dock, notifications, on-screen popups, Settings, desktop widgets and the lock screen."
        trailing: [
            Slider {
                app: settingsRoot.app
                // 2 to 20 px, and all the way right: fully round
                from: 2
                to: 22
                tick: 4
                step: 2
                value: app.cornersRound ? 22 : app.cornerSq
                label: Math.round(value) >= 22 ? "Round" : Math.round(value) + " px"
                onMoved: v => app.setting("cornerRadius", Math.round(v) >= 22 ? 0 : Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Round", "Square"]
                current: app.cornersRound ? 0 : app.cornerSq === 6 ? 1 : -1
                onPicked: i => app.setting("cornerRadius", i === 1 ? 6 : 0)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Centre pill" }

    Card {
        app: settingsRoot.app
        title: "Clicking the centre pill"
        desc: app.barMorph
              ? "The pill itself grows into a panel with the media, the weather and this month. Esc or the arrow at its top shrinks it back."
              : "Opens the media card in its own panel under the bar."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Grow into a panel", "Card below"]
                current: app.barMorph ? 0 : 1
                onPicked: i => { app.cardShown = false; app.setting("barMorph", i === 0) }
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Clicking the clock"
        desc: app.rightMorph
              ? "The right pill grows into quick settings: toggles, sliders, outputs and notifications. The sidebar is still on SUPER+V."
              : "Opens the sidebar. Clicking the volume opens its own popover."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Grow into quick settings", "Open the sidebar"]
                current: app.rightMorph ? 0 : 1
                onPicked: i => { app.quickShown = false; app.setting("rightMorph", i === 0) }
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Clicking a stat"
        desc: app.leftMorph
              ? "The left pill grows into a system panel: live graphs and the busiest processes."
              : "Opens btop in your terminal (GPU opens nvidia-settings for an NVIDIA card, or LACT for an AMD one if you have it)."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Grow into a panel", "Open btop"]
                current: app.leftMorph ? 0 : 1
                onPicked: i => { app.sysShown = false; app.setting("leftMorph", i === 0) }
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Resource monitor" }

    Card {
        app: settingsRoot.app
        title: "Graphs"
        desc: "Each stat with its own mini graph, or every line together in one graph, each in its own colour, with the numbers after it in the same colours."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Separate", "One graph"]
                current: app.statOneGraph ? 1 : 0
                onPicked: i => app.setting("statLayout", i === 1 ? "one" : "separate")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Stat icons"
        desc: "The small icon in front of each stat."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.statIcons ? 1 : 0
                onPicked: i => app.setting("statIcons", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "CPU"
        desc: "How busy the processor is: a number, a mini graph of the last minute, or both. A graph's line takes the colour picked under it; Auto follows the wallpaper's colours."
        Seg {
            app: settingsRoot.app
            options: ["Off", "Number", "Graph", "Both"]
            current: ["off", "number", "graph", "both"].indexOf(app.statCpu)
            onPicked: i => app.setting("statCpu", ["off", "number", "graph", "both"][i])
        }
        ColourRow {
            app: settingsRoot.app
            visible: app.statCpu === "graph" || app.statCpu === "both"
            value: typeof app.cfg.statCpuColour === "string" ? app.cfg.statCpuColour : ""
            stat: "cpu"
            onPicked: v => app.setting("statCpuColour", v)
        }
    }

    Card {
        app: settingsRoot.app
        title: "Memory"
        desc: "How much memory is in use."
        Seg {
            app: settingsRoot.app
            options: ["Off", "Number", "Graph", "Both"]
            current: ["off", "number", "graph", "both"].indexOf(app.statMem)
            onPicked: i => app.setting("statMem", ["off", "number", "graph", "both"][i])
        }
        ColourRow {
            app: settingsRoot.app
            visible: app.statMem === "graph" || app.statMem === "both"
            value: typeof app.cfg.statMemColour === "string" ? app.cfg.statMemColour : ""
            stat: "mem"
            onPicked: v => app.setting("statMemColour", v)
        }
    }

    Card {
        app: settingsRoot.app
        title: "GPU load"
        desc: "How busy the graphics card is. Only shows when the card can be read (NVIDIA)."
        Seg {
            app: settingsRoot.app
            options: ["Off", "Number", "Graph", "Both"]
            current: ["off", "number", "graph", "both"].indexOf(app.statGpu)
            onPicked: i => app.setting("statGpu", ["off", "number", "graph", "both"][i])
        }
        ColourRow {
            app: settingsRoot.app
            visible: app.statGpu === "graph" || app.statGpu === "both"
            value: typeof app.cfg.statGpuColour === "string" ? app.cfg.statGpuColour : ""
            stat: "gpu"
            onPicked: v => app.setting("statGpuColour", v)
        }
    }

    Card {
        app: settingsRoot.app
        title: "GPU temperature"
        desc: "The graphics card's temperature. The number turns yellow from 70 and red from 80."
        Seg {
            app: settingsRoot.app
            options: ["Off", "Number", "Graph", "Both"]
            current: ["off", "number", "graph", "both"].indexOf(app.statTemp)
            onPicked: i => app.setting("statTemp", ["off", "number", "graph", "both"][i])
        }
        ColourRow {
            app: settingsRoot.app
            visible: app.statTemp === "graph" || app.statTemp === "both"
            value: typeof app.cfg.statTempColour === "string" ? app.cfg.statTempColour : ""
            stat: "temp"
            onPicked: v => app.setting("statTempColour", v)
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Modules" }

    Card {
        app: settingsRoot.app
        title: "Network speed"
        desc: "Download and upload rates beside the volume."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.barNet ? 1 : 0
                onPicked: i => app.setting("barNet", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Now playing"
        desc: "The track in the centre of the bar while something plays."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.barMedia ? 1 : 0
                onPicked: i => app.setting("barMedia", i === 1)
            }
        ]
    }
}
