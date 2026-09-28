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
    visible: settingsWin.page === 8
    readonly property int pageNo: 8
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "When you step away" }

    Card {
        app: settingsRoot.app
        title: "Lock the screen"
        desc: "Minutes without input before the lock screen comes up. Drag to the far left for never."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 60
                tick: 5
                step: 1
                value: app.idleLockMin
                label: Math.round(value) === 0 ? "Never"
                     : Math.round(value) + " min"
                onMoved: v => app.setting("idleLockMin", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.idleLockMin === undefined ? 0 : -1
                onPicked: app.resetSetting("idleLockMin")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Turn screens off"
        desc: "Minutes before both monitors go dark. Any key or mouse movement brings them back."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 60
                tick: 10
                step: 1
                value: app.idleScreenMin
                label: Math.round(value) === 0 ? "Never"
                     : Math.round(value) + " min"
                onMoved: v => app.setting("idleScreenMin", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.idleScreenMin === undefined ? 0 : -1
                onPicked: app.resetSetting("idleScreenMin")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Sleep"
        desc: "Minutes before the PC suspends. The screen locks first, so it wakes to the lock screen."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 60
                tick: 0
                step: 1
                value: app.idleSleepMin
                label: Math.round(value) === 0 ? "Never"
                     : Math.round(value) + " min"
                onMoved: v => app.setting("idleSleepMin", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.idleSleepMin === undefined ? 0 : -1
                onPicked: app.resetSetting("idleSleepMin")
            }
        ]
    }
}
