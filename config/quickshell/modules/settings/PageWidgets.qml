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
    id: widgetsPage
    width: parent.width
    visible: settingsWin.page === 19
    readonly property int pageNo: 19
    spacing: 4

    readonly property var screenNames: Quickshell.screens.map(s => s.name)

    Card {
        app: settingsRoot.app
        title: "Arrange widgets"
        desc: "Lifts your widgets above your windows so you can drag them into place. Press Done or Esc when you're finished."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Arrange"]
                onPicked: { app.settingsShown = false; app.widgetEdit = true }
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Add a widget" }

    Card {
        app: settingsRoot.app
        title: "Available"
        desc: "Each one appears near the top left of the screen you pick. Add the same one more than once if you like."

        Repeater {
            model: app.widgetTypes
            delegate: RowLayout {
                id: addRow
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: addRow.modelData.name
                        color: app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(13)
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: addRow.modelData.desc
                        color: app.cDim
                        font.family: "Inter"
                        font.pixelSize: app.fs(11)
                        elide: Text.ElideRight
                    }
                }
                Seg {
                    app: settingsRoot.app
                    options: widgetsPage.screenNames.map(n => "Add to " + n)
                    onPicked: i => app.addWidget(addRow.modelData.type,
                                  widgetsPage.screenNames[i])
                }
            }
        }
    }

    Card {
        id: arrangeCard
        app: settingsRoot.app
        property string note: ""
        title: "Keep clear of the wallpaper"
        desc: note !== "" ? note
              : !app.nativeOk ? "Needs the native plugin, which isn't built: re-run the installer."
              : app.cfg.widgetsAuto === true
              ? "Each new wallpaper moves your widgets to its calmest places (sky, walls, soft blur), away from faces, buildings and busy detail. On a wallpaper that's busy everywhere, they stay put."
              : "Widgets stay wherever you put them. Turn this on to have them find the calm parts of each new wallpaper."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.widgetsAuto === true ? 1 : 0
                onPicked: i => { app.setting("widgetsAuto", i === 1); if (i === 1) app.arrangeWidgets() }
            },
            Seg {
                app: settingsRoot.app
                options: ["Arrange now"]
                current: -1
                onPicked: {
                    const n = app.arrangeWidgets()
                    arrangeCard.note = n < 0 ? "Couldn't read the wallpaper yet." : n === 0
                        ? "Nothing to move: they're already in the calmest places, or this wallpaper has none."
                        : (n === 1 ? "Moved 1 widget." : "Moved " + n + " widgets.")
                    noteClear.restart()
                }
            }
        ]
        Timer { id: noteClear; interval: 5000; onTriggered: arrangeCard.note = "" }
    }

    SectionLabel { app: settingsRoot.app; text: "On your desktop" }

    Card {
        app: settingsRoot.app
        visible: app.widgets.length === 0
        title: "No widgets yet"
        desc: "Add one above, then use Arrange to put it where you want it."
    }

    Repeater {
        model: app.widgets
        delegate: Card {
            id: wCard
            required property var modelData
            app: settingsRoot.app
            title: (app.widgetTypes.find(t => t.type === modelData.type)
                    || { name: String(modelData.type).startsWith("plugin:")
                               ? "A plugin's widget (" + String(modelData.type).slice(7) + ", switched off)" : modelData.type }).name
            desc: "On " + (modelData.screen || app.mainScreen)
            trailing: [
                Seg {
                    app: settingsRoot.app
                    visible: Quickshell.screens.length > 1
                    options: Quickshell.screens.map(s => s.name)
                    current: Quickshell.screens.map(s => s.name).indexOf(wCard.modelData.screen || app.mainScreen)
                    onPicked: i => app.updateWidget(wCard.modelData.id,
                                  { screen: Quickshell.screens[i].name })
                },
                Seg {
                    app: settingsRoot.app
                    options: ["Remove"]
                    onPicked: app.removeWidget(wCard.modelData.id)
                }
            ]

            // a note's text, edited in place
            Rectangle {
                Layout.fillWidth: true
                visible: wCard.modelData.type === "note"
                implicitHeight: Math.max(38, noteEdit.contentHeight + 20)
                radius: 14
                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                border.width: noteEdit.activeFocus ? 1 : 0
                border.color: app.cBlue
                TextEdit {
                    id: noteEdit
                    anchors.fill: parent
                    anchors.margins: 10
                    text: wCard.modelData.text || ""
                    color: app.cFg
                    selectionColor: app.cBlue
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                    wrapMode: TextEdit.Wrap
                    // saved when you click away
                    onActiveFocusChanged: if (!activeFocus && text !== (wCard.modelData.text || ""))
                        app.updateWidget(wCard.modelData.id, { text: text })
                }
            }
        }
    }
}
