import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 12
    readonly property int pageNo: 12
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Level" }

    Card {
        app: settingsRoot.app
        title: "Volume"
        desc: settingsWin.nodeName(settingsWin.sink)
        trailing: [
            Slider {
                app: settingsRoot.app
                to: settingsWin.maxVol
                tick: 1
                value: settingsWin.vol
                muted: settingsWin.sinkAu?.muted ?? false
                label: muted ? "Muted" : settingsWin.pct(value)
                onMoved: v => settingsWin.setMaster(settingsWin.sinkAu, v)
            },
            IconBtn {
                app: settingsRoot.app
                accent: settingsRoot.app.cRed
                active: settingsWin.sinkAu?.muted ?? false
                glyph: active ? "volume_off" : "volume_up"
                onClicked: if (settingsWin.sinkAu)
                    settingsWin.sinkAu.muted = !settingsWin.sinkAu.muted
            }
        ]
    }

    Card {
        app: settingsRoot.app
        visible: settingsWin.sinkCh === 2
        title: "Balance"
        desc: "Shifts sound between the left and right channels."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: -1
                to: 1
                origin: 0
                tick: 0
                step: 0.05
                value: settingsWin.bal
                label: Math.abs(value) < 0.02 ? "Centre"
                     : (value < 0 ? "Left " : "Right ")
                       + Math.round(Math.abs(value) * 100)
                onMoved: v => settingsWin.setBalance(v)
            },
            Seg {
                app: settingsRoot.app
                options: ["Centre"]
                current: Math.abs(settingsWin.bal) < 0.02 ? 0 : -1
                onPicked: settingsWin.setBalance(0)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Allow above 100%"
        desc: "Lets every volume in this panel go to 150%. Loud sources can clip."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: settingsWin.boost ? 1 : 0
                onPicked: i => {
                    settingsWin.boost = i === 1
                    if (!settingsWin.boost && settingsWin.vol > 1)
                        settingsWin.setMaster(settingsWin.sinkAu, 1)
                }
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Device" }

    Card {
        app: settingsRoot.app
        title: "Output device"
        desc: "Apps follow the device in use, unless you have moved one yourself."

        Repeater {
            model: Pipewire.nodes
            delegate: DeviceRow {
                required property var modelData
                app: settingsRoot.app
                node: modelData
                visible: settingsWin.isOutDev(modelData)
                isDefault: modelData === settingsWin.sink
                onChosen: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Advanced" }

    Card {
        app: settingsRoot.app
        title: "Ports and profiles"
        desc: "Switching a card's profile or port isn't covered here yet."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Open pavucontrol"]
                onPicked: app.run("pavucontrol")
            }
        ]
    }
}
