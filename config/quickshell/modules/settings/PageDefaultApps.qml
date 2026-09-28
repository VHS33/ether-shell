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
    id: appsPage
    width: parent.width
    visible: settingsWin.page === 21
    readonly property int pageNo: 21
    spacing: 4

    // installed apps as plain values, read from their
    // desktop files by category
    function listFor(cat) {
        const seen = {}
        const out = []
        for (const e of DesktopEntries.applications.values) {
            if (!e || e.noDisplay) continue
            const cats = e.categories || []
            if (cats.indexOf(cat) === -1) continue
            const id = String(e.id).endsWith(".desktop") ? String(e.id) : e.id + ".desktop"
            if (seen[id]) continue
            seen[id] = true
            out.push({ id: id, name: String(e.name), cmd: app.entryCmd(e) })
        }
        return out.sort((a, b) => a.name.localeCompare(b.name))
    }

    Card {
        app: settingsRoot.app
        title: "Terminal"
        desc: "Opens on SUPER+T, and wherever the shell opens a terminal, such as clicking CPU in the bar."

        Repeater {
            model: appsPage.listFor("TerminalEmulator")
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.name
                desc: modelData.cmd
                selected: (app.cfg.appTerminal || "kitty.desktop") === modelData.id
                onChosen: app.setDefaultApp("terminal", modelData)
            }
        }
        Text {
            visible: appsPage.listFor("TerminalEmulator").length === 0
            text: "None installed that declare themselves as one."
            color: app.cFaint
            font.family: "Inter"
            font.pixelSize: app.fs(11)
        }
    }

    Card {
        app: settingsRoot.app
        title: "File manager"
        desc: "Opens on SUPER+E, and becomes the default for opening folders everywhere."

        Repeater {
            model: appsPage.listFor("FileManager")
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.name
                desc: modelData.cmd
                selected: app.xdgDefaults.files === modelData.id
                onChosen: app.setDefaultApp("files", modelData)
            }
        }
        Text {
            visible: appsPage.listFor("FileManager").length === 0
            text: "None installed that declare themselves as one."
            color: app.cFaint
            font.family: "Inter"
            font.pixelSize: app.fs(11)
        }
    }

    Card {
        app: settingsRoot.app
        title: "Web browser"
        desc: "The default for opening links from any app."

        Repeater {
            model: appsPage.listFor("WebBrowser")
            delegate: ChoiceRow {
                required property var modelData
                app: settingsRoot.app
                title: modelData.name
                desc: modelData.cmd
                selected: app.xdgDefaults.browser === modelData.id
                onChosen: app.setDefaultApp("browser", modelData)
            }
        }
        Text {
            visible: appsPage.listFor("WebBrowser").length === 0
            text: "None installed that declare themselves as one."
            color: app.cFaint
            font.family: "Inter"
            font.pixelSize: app.fs(11)
        }
    }
}
