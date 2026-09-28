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
    visible: settingsWin.page === 7
    readonly property int pageNo: 7
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "The bar's island" }

    Card {
        app: settingsRoot.app
        title: "Notifications"
        desc: !app.barAttached
              ? "The island needs the long bar (Settings > Bar > Bar style)."
              : app.cfg.islandNotifs === true
              ? "New notifications grow out of the middle of the bar for a few seconds. Ones with buttons or a reply box still get a popup too."
              : "New notifications appear as popups."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["In the bar", "As popups"]
                current: app.cfg.islandNotifs === true ? 0 : 1
                onPicked: i => app.setting("islandNotifs", i === 0)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Volume and brightness"
        desc: !app.barAttached
              ? "The island needs the long bar (Settings > Bar > Bar style)."
              : app.cfg.islandOsd !== false
              ? "Changes to volume, the microphone, brightness and night light show in the middle of the bar."
              : "Changes show in a pop-up near the bottom of the screen."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["In the bar", "As a pop-up"]
                current: app.cfg.islandOsd !== false ? 0 : 1
                onPicked: i => app.setting("islandOsd", i === 0)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Popups" }

    Card {
        app: settingsRoot.app
        title: "Popup duration"
        desc: "How long a notification stays before it goes to the sidebar. Critical ones stay twice as long, and hovering pauses the countdown."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 2
                to: 20
                tick: 6
                step: 0.5
                value: app.notifMs / 1000
                label: (Math.round(value * 2) / 2) + " s"
                onMoved: v => app.setting("notifMs",
                                          Math.round(v * 2) * 500)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.notifMs === undefined ? 0 : -1
                onPicked: app.resetSetting("notifMs")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "On-screen indicators" }

    Card {
        app: settingsRoot.app
        title: "Volume indicator"
        desc: "How long the volume indicator stays up after the level changes."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.5
                to: 5
                tick: 1.4
                step: 0.1
                value: app.osdMs / 1000
                label: value.toFixed(1) + " s"
                onMoved: v => app.setting("osdMs",
                                          Math.round(v * 10) * 100)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.osdMs === undefined ? 0 : -1
                onPicked: app.resetSetting("osdMs")
            }
        ]
    }
}
