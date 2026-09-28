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
        desc: app.barAttached
              ? "One long bar across the top. Its sections open cards that slide out from behind it."
              : "Three separate floating pills that grow into panels."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Long bar", "Islands"]
                current: app.barAttached ? 0 : 1
                onPicked: i => {
                    app.cardShown = false
                    app.quickShown = false
                    app.sysShown = false
                    app.setting("barStyle", i === 0 ? "long" : "islands")
                }
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
              : "Opens btop in your terminal (GPU opens nvidia-settings)."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Grow into a panel", "Open btop"]
                current: app.leftMorph ? 0 : 1
                onPicked: i => { app.sysShown = false; app.setting("leftMorph", i === 0) }
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Modules" }

    Card {
        app: settingsRoot.app
        title: "CPU and memory"
        desc: "Usage percentages beside the workspaces."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.barStats ? 1 : 0
                onPicked: i => app.setting("barStats", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "GPU"
        desc: "Load and temperature. Only appears when nvidia-smi can read the card."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.barGpu ? 1 : 0
                onPicked: i => app.setting("barGpu", i === 1)
            }
        ]
    }

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
