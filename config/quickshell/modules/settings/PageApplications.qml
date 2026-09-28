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
    visible: settingsWin.page === 13
    readonly property int pageNo: 13
    spacing: 4

    Card {
        app: settingsRoot.app
        visible: settingsWin.count(settingsWin.isPlay) === 0
        title: "Nothing is playing"
        desc: "Apps appear here while they play sound, each with its own volume."
    }

    Repeater {
        model: Pipewire.nodes
        delegate: StreamCard {
            required property var modelData
            app: settingsRoot.app
            node: modelData
            visible: settingsWin.isPlay(modelData)
            maxVol: settingsWin.maxVol
        }
    }
}
