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
    id: aiPage
    width: parent.width
    visible: settingsWin.page === 22
    readonly property int pageNo: 22
    spacing: 4
    readonly property string p: app.aiProvider
    readonly property var info: app.aiProviders[p]
    onVisibleChanged: if (visible) app.refreshAiKeys()

    SectionLabel { app: settingsRoot.app; text: "Provider" }

    Card {
        app: settingsRoot.app
        title: "Who answers"
        desc: "Your messages are sent to this company, using your own API key. Each has its own key; switching keeps the others."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Anthropic", "Google", "OpenAI"]
                current: ["anthropic", "gemini", "openai"].indexOf(aiPage.p)
                onPicked: i => app.setting("aiProvider", ["anthropic", "gemini", "openai"][i])
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: aiPage.info.name + " (" + aiPage.info.product + ")" }

    Card {
        app: settingsRoot.app
        title: "API key"
        desc: app.aiKeys[aiPage.p]
              ? "A key is saved. It's kept in its own file that only you can read, never in the settings file."
              : "Create one at " + aiPage.info.keyUrl + ", then paste it here and press Save."

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: 12
                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                border.width: keyIn.activeFocus ? 2 : 0
                border.color: app.cBlue
                TextInput {
                    id: keyIn
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: app.cFg
                    selectionColor: app.cBlue
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                    clip: true
                    Keys.onReturnPressed: if (text.trim()) { app.saveAiKey(aiPage.p, text); text = "" }
                    Text {
                        visible: !keyIn.text && !keyIn.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: app.aiKeys[aiPage.p] ? "Paste a new key to replace it" : "Paste your API key"
                        color: app.cFaint
                        font: keyIn.font
                    }
                }
            }
            Rectangle {
                implicitWidth: saveT.implicitWidth + 28
                implicitHeight: 42
                radius: 12
                color: keyIn.text.trim() ? app.cBlue : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                Text {
                    id: saveT
                    anchors.centerIn: parent
                    text: "Save"
                    color: keyIn.text.trim() ? app.cOnAccent : app.cDim
                    font.family: "Inter"
                    font.weight: Font.DemiBold
                    font.pixelSize: app.fs(13)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (keyIn.text.trim()) { app.saveAiKey(aiPage.p, keyIn.text); keyIn.text = "" }
                }
            }
            Rectangle {
                visible: app.aiKeys[aiPage.p] === true
                implicitWidth: remT.implicitWidth + 28
                implicitHeight: 42
                radius: 12
                color: remHov.hovered ? app.cRed : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                HoverHandler { id: remHov }
                Text {
                    id: remT
                    anchors.centerIn: parent
                    text: "Remove"
                    color: remHov.hovered ? app.cOnAccent : app.cFg
                    font.family: "Inter"
                    font.weight: Font.DemiBold
                    font.pixelSize: app.fs(13)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: app.removeAiKey(aiPage.p)
                }
            }
        }
    }

    Card {
        app: settingsRoot.app
        title: "Model"
        desc: "Which of " + aiPage.info.name + "'s models to use. Leave empty for " + aiPage.info.model + ". Changes apply to your next message."

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: 12
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            border.width: modelIn.activeFocus ? 2 : 0
            border.color: app.cBlue
            TextInput {
                id: modelIn
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: app.cFg
                selectionColor: app.cBlue
                font.family: "Inter"
                font.pixelSize: app.fs(13)
                clip: true
                // only letters, numbers and . : _ - reach the request
                validator: RegularExpressionValidator { regularExpression: /[\w.:-]*/ }
                text: app.cfg["aiModel_" + aiPage.p] || ""
                onEditingFinished: {
                    const v = text.trim()
                    if (v === "") app.resetSetting("aiModel_" + aiPage.p)
                    else app.setting("aiModel_" + aiPage.p, v)
                }
                Text {
                    visible: !modelIn.text && !modelIn.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: aiPage.info.model
                    color: app.cFaint
                    font: modelIn.font
                }
            }
        }
    }
}
