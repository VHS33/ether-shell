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
    visible: settingsWin.page === 14
    readonly property int pageNo: 14
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Level" }

    Card {
        app: settingsRoot.app
        title: "Microphone volume"
        desc: settingsWin.nodeName(settingsWin.source)
        trailing: [
            Slider {
                app: settingsRoot.app
                accent: settingsRoot.app.cTeal
                to: settingsWin.maxVol
                tick: 1
                value: settingsWin.master(settingsWin.sourceAu)
                muted: settingsWin.sourceAu?.muted ?? false
                label: muted ? "Muted" : settingsWin.pct(value)
                onMoved: v => settingsWin.setMaster(settingsWin.sourceAu, v)
            },
            IconBtn {
                app: settingsRoot.app
                accent: settingsRoot.app.cRed
                active: settingsWin.sourceAu?.muted ?? false
                glyph: active ? "mic_off" : "mic"
                onClicked: if (settingsWin.sourceAu)
                    settingsWin.sourceAu.muted = !settingsWin.sourceAu.muted
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Device" }

    Card {
        app: settingsRoot.app
        title: "Input device"
        desc: "The microphone apps record from by default."

        Repeater {
            model: Pipewire.nodes
            delegate: DeviceRow {
                required property var modelData
                app: settingsRoot.app
                node: modelData
                isInput: true
                accent: settingsRoot.app.cTeal
                visible: settingsWin.isInDev(modelData)
                isDefault: modelData === settingsWin.source
                onChosen: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }
}
