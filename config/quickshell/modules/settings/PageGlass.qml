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
    visible: settingsWin.page === 1
    readonly property int pageNo: 1
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Shell" }

    Card {
        app: settingsRoot.app
        title: "Shell panels"
        desc: "How solid the bar, dock, sidebar and panels are. Lower lets more of the blurred desktop through."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.3
                to: 1
                tick: 0.75
                step: 0.05
                value: app.bgA
                label: Math.round(value * 100) + "%"
                onMoved: v => app.setting("bgOpacity",
                                          Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.bgOpacity === undefined ? 0 : -1
                onPicked: app.resetSetting("bgOpacity")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Terminal" }

    Card {
        app: settingsRoot.app
        title: "Terminal background"
        desc: "How see-through kitty's background is. Text stays fully solid. Open terminals change straight away."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.3
                to: 1
                tick: 0.75
                step: 0.05
                value: app.termOpacity
                label: Math.round(value * 100) + "%"
                onMoved: v => app.setting("termOpacity",
                                          Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.termOpacity === undefined ? 0 : -1
                onPicked: app.resetSetting("termOpacity")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Windows" }

    Card {
        app: settingsRoot.app
        title: "Focused window"
        desc: "Opacity of the window you're using. Multiplies with an app's own transparency, so kitty at 75% here at 90% ends up lighter still."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.5
                to: 1
                tick: 1
                step: 0.05
                value: app.cfg.winActive
                label: Math.round(value * 100) + "%"
                onMoved: v => app.setting("winActive", Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.winActive === undefined ? 0 : -1
                onPicked: app.resetSetting("winActive")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Other windows"
        desc: "Opacity of every window that doesn't have focus. Lowering it makes the focused one stand out."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.5
                to: 1
                tick: 1
                step: 0.05
                value: app.cfg.winInactive
                label: Math.round(value * 100) + "%"
                onMoved: v => app.setting("winInactive", Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.winInactive === undefined ? 0 : -1
                onPicked: app.resetSetting("winInactive")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Blur" }

    Card {
        app: settingsRoot.app
        title: "Blur radius"
        desc: "How far the frost spreads behind every see-through surface. Larger looks softer and costs more GPU."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 1
                to: 16
                tick: 4
                step: 1
                value: app.cfg.blurSize
                label: Math.round(value)
                onMoved: v => app.setting("blurSize", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.blurSize === undefined ? 0 : -1
                onPicked: app.resetSetting("blurSize")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Blur passes"
        desc: "How many times the blur is applied. More passes give a smoother frost at a large radius; fewer can look blocky."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["1", "2", "3", "4"]
                current: app.cfg.blurPasses - 1
                onPicked: i => app.setting("blurPasses", i + 1)
            }
        ]
    }
}
