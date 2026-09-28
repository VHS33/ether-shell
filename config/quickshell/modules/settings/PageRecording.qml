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
    visible: settingsWin.page === 15
    readonly property int pageNo: 15
    spacing: 4

    Card {
        app: settingsRoot.app
        visible: settingsWin.count(settingsWin.isRec) === 0
        title: "No app is recording"
        desc: "Apps appear here while they use a microphone, each with its own input level."
    }

    Repeater {
        model: Pipewire.nodes
        delegate: StreamCard {
            required property var modelData
            app: settingsRoot.app
            node: modelData
            accent: settingsRoot.app.cTeal
            visible: settingsWin.isRec(modelData)
            maxVol: settingsWin.maxVol
        }
    }
}
