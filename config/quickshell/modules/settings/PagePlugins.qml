import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.plugins
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 23
    readonly property int pageNo: 23
    spacing: 4

    Card {
        app: settingsRoot.app
        title: "Your plugins"
        desc: "Each plugin is a folder in ~/.config/ether-shell/plugins. They're off until you switch them on here. After adding or changing one, press Check plugins. Plugins are code, so only add ones from people you trust."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Open folder", "Check plugins"]
                current: -1
                onPicked: i => i === 0 ? app.openPluginsFolder() : app.reloadPlugins()
            }
        ]
    }

    Text {
        visible: app.plugins.length === 0
        Layout.fillWidth: true
        Layout.margins: 12
        wrapMode: Text.WordWrap
        text: "No plugins yet. Put a plugin's folder in ~/.config/ether-shell/plugins, then press Check plugins."
        color: app.cDim
        font.family: "Inter"
        font.pixelSize: app.fs(13)
    }

    Repeater {
        model: app.plugins
        delegate: Card {
            id: pcard
            required property var modelData
            readonly property string failed: app.pluginErrors[modelData.id] || ""
            app: settingsRoot.app
            title: modelData.name + (modelData.version ? "  " + modelData.version : "")
            desc: !modelData.ok
                  ? "Can't be used: " + modelData.errors.join("; ") + "."
                  : failed !== ""
                  ? "Set aside, it didn't load: " + failed
                  : (modelData.description || "No description.")
                    + (modelData.author ? "  By " + modelData.author + "." : "")
                    + (modelData.bar ? "  Adds a bar item on the " + modelData.bar.side + "." : "")
                    + (modelData.launcher ? "  Adds launcher results" + (modelData.launcher.prefix ? " (type " + modelData.launcher.prefix + " first)" : "") + "." : "")
            trailing: [
                Seg {
                    app: settingsRoot.app
                    visible: pcard.modelData.ok
                    options: ["Off", "On"]
                    current: app.pluginEnabled(pcard.modelData.id) ? 1 : 0
                    onPicked: i => app.setPluginEnabled(pcard.modelData.id, i === 1)
                }
            ]
            // its own settings, while it's on
            Loader {
                Layout.fillWidth: true
                active: pcard.modelData.ok && pcard.modelData.settings !== null
                        && app.pluginEnabled(pcard.modelData.id) && pcard.failed === ""
                visible: active
                sourceComponent: PluginHost {
                    app: settingsRoot.app
                    pluginId: pcard.modelData.id
                    dir: pcard.modelData.dir
                    file: pcard.modelData.settings.file
                    part: "settings"
                    fill: true
                }
            }
        }
    }
}
