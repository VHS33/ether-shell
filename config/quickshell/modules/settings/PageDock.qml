import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 6
    readonly property int pageNo: 6
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Visibility" }

    Card {
        app: settingsRoot.app
        title: "Show dock"
        desc: "When it's off, the space it reserves is given back and windows use the full height of the screen."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.dockEnabled ? 1 : 0
                onPicked: i => app.setting("dockEnabled", i === 1)
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Icon size"
        desc: "How big the app icons are. The dock grows or shrinks around them."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 20
                to: 44
                step: 2
                value: app.dockIcon
                label: Math.round(value) + " px"
                onMoved: v => app.setting("dockIcon", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.dockIcon === undefined ? 0 : -1
                onPicked: app.resetSetting("dockIcon")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Hide the dock"
        desc: app.dockHide === "windows"
              ? "Only while a window overlaps it: it stays up over an empty desktop, and steps aside for windows (and full screen). Touch the screen's edge to bring it back."
              : app.dockHide === "always"
              ? "Slides away until your pointer touches the screen's edge, where the dock sits. Windows get the space meanwhile."
              : "Always showing, with its own space that windows keep clear of."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Never", "Always", "When windows overlap"]
                current: ["never", "always", "windows"].indexOf(app.dockHide)
                onPicked: i => app.setting("dockHide", ["never", "always", "windows"][i])
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Position"
        desc: app.dockEdge === "bottom" ? "Along the bottom of the screen."
              : "Down the " + app.dockEdge + " side of the screen, with its menus and previews opening beside it."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Bottom", "Left", "Right"]
                current: ["bottom", "left", "right"].indexOf(app.dockEdge)
                onPicked: i => app.setting("dockEdge", ["bottom", "left", "right"][i])
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Show on"
        desc: app.dockAllScreens ? "Every screen, each with its own dock." : "Just your main screen (Settings, Displays)."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Main screen", "Every screen"]
                current: app.dockAllScreens ? 1 : 0
                onPicked: i => app.setting("dockAllScreens", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Pinned apps" }

    Card {
        app: settingsRoot.app
        title: app.dockPinned.length ? app.dockPinned.length + (app.dockPinned.length === 1 ? " app pinned" : " apps pinned") : "Nothing pinned yet"
        desc: "Right-click any app in the dock to pin it. Pinned apps stay in the dock when closed, and clicking one launches it."

        Repeater {
            model: app.dockPinned
            delegate: RowLayout {
                id: pinRow
                required property var modelData
                readonly property var entry: DesktopEntries.byId(modelData)
                Layout.fillWidth: true
                spacing: 10
                IconImage {
                    implicitSize: 24
                    source: pinRow.entry ? Quickshell.iconPath(pinRow.entry.icon, true) : ""
                }
                Text {
                    Layout.fillWidth: true
                    text: pinRow.entry ? pinRow.entry.name : pinRow.modelData + " (not installed)"
                    color: app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                    elide: Text.ElideRight
                }
                Seg {
                    app: settingsRoot.app
                    options: ["Unpin"]
                    onPicked: app.setting("dockPinned", app.dockPinned.filter(x => x !== pinRow.modelData))
                }
            }
        }
    }
}
