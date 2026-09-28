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
    visible: settingsWin.page === 11
    readonly property int pageNo: 11
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Pointer" }

    Card {
        app: settingsRoot.app
        title: "Pointer speed"
        desc: "Faster or slower than the mouse's own speed. The middle leaves it unchanged."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: -1
                to: 1
                origin: 0
                tick: 0
                step: 0.05
                value: app.cfg.sensitivity
                label: Math.abs(value) < 0.025 ? "Unchanged" : (value > 0 ? "+" : "") + value.toFixed(2)
                onMoved: v => app.setting("sensitivity", Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.sensitivity === undefined ? 0 : -1
                onPicked: app.resetSetting("sensitivity")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Acceleration"
        desc: "Adaptive speeds the pointer up on quick flicks. Flat moves it the same distance however fast you move, which most people prefer for games."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Adaptive", "Flat"]
                current: app.cfg.accelFlat === true ? 1 : 0
                onPicked: i => app.setting("accelFlat", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Scrolling and focus" }

    Card {
        app: settingsRoot.app
        title: "Natural scrolling"
        desc: "Content moves the way your finger does, like a phone. Off is the traditional wheel direction."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.naturalScroll === true ? 1 : 0
                onPicked: i => app.setting("naturalScroll", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Window focus"
        desc: "Which window receives your typing. On click still scrolls whatever is under the pointer."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Follows mouse", "On click"]
                current: app.cfg.followMouse === false ? 1 : 0
                onPicked: i => app.setting("followMouse", i === 0)
            }
        ]
    }
}
