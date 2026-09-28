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
    visible: settingsWin.page === 16
    readonly property int pageNo: 16
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Location" }

    Card {
        app: settingsRoot.app
        title: app.wxPlace
        desc: app.wxOk
              ? "Now " + app.wxTemp + ", " + app.wxCond.toLowerCase()
                + ". Search for a city below to change it."
              : "Search for a city below to change it."

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 38
            radius: 19
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            border.width: placeIn.activeFocus ? 1 : 0
            border.color: app.cBlue

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                Text {
                    text: "search"
                    color: app.cFaint
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: app.fs(14)
                }
                TextInput {
                    id: placeIn
                    Layout.fillWidth: true
                    color: app.cFg
                    selectionColor: app.cBlue
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                    clip: true
                    onAccepted: app.searchPlace(text)
                    Keys.onEscapePressed: { text = ""; settingsKeys.forceActiveFocus() }
                    Text {
                        visible: !placeIn.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Type a city, then Enter"
                        color: app.cFaint
                        font: placeIn.font
                    }
                }
                Text {
                    visible: app.wxSearching
                    text: "Searching\u2026"
                    color: app.cFaint
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                }
            }
        }

        Repeater {
            model: app.wxResults
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.name
                desc: modelData.where
                selected: false
                onChosen: { app.setPlace(modelData); placeIn.text = "" }
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Units" }

    Card {
        app: settingsRoot.app
        title: "Temperature and wind"
        desc: "Fahrenheit with miles per hour, or Celsius with kilometres per hour."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["\u00b0F, mph", "\u00b0C, km/h"]
                current: app.wxMetric ? 1 : 0
                onPicked: i => app.setting("wxUnits", i === 1 ? "C" : "F")
            }
        ]
    }
}
