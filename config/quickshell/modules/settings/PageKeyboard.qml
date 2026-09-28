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
    visible: settingsWin.page === 10
    readonly property int pageNo: 10
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Key repeat" }

    Card {
        app: settingsRoot.app
        title: "Repeat delay"
        desc: "How long a key is held before it starts repeating."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 150
                to: 1000
                tick: 600
                step: 25
                value: app.cfg.repeatDelay
                label: Math.round(value) + " ms"
                onMoved: v => app.setting("repeatDelay", Math.round(v / 25) * 25)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.repeatDelay === undefined ? 0 : -1
                onPicked: app.resetSetting("repeatDelay")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Repeat rate"
        desc: "How many times a second a held key repeats once it starts."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 10
                to: 60
                tick: 25
                step: 1
                value: app.cfg.repeatRate
                label: Math.round(value) + " per second"
                onMoved: v => app.setting("repeatRate", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.repeatRate === undefined ? 0 : -1
                onPicked: app.resetSetting("repeatRate")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Try it"
        desc: "Click in the box and hold a key. Changes above apply a moment after you set them."

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: 12
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            border.width: tryIn.activeFocus ? 2 : 0
            border.color: app.cBlue

            TextInput {
                id: tryIn
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: app.cFg
                selectionColor: app.cBlue
                font.family: "Inter"
                font.pixelSize: app.fs(13)
                clip: true
                Keys.onEscapePressed: { text = ""; settingsKeys.forceActiveFocus() }

                Text {
                    visible: !tryIn.text && !tryIn.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Hold a key here"
                    color: app.cFaint
                    font: tryIn.font
                }
            }
        }
    }
}
