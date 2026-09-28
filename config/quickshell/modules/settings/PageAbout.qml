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
    visible: settingsWin.page === 18
    readonly property int pageNo: 18
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "This machine" }

    Card {
        app: settingsRoot.app
        title: app.aboutInfo.host || "\u2026"
        desc: app.aboutInfo.os || ""

        Repeater {
            model: [
                { k: "CPU",        v: (app.aboutInfo.cpu || "") + (app.aboutInfo.cores ? ", " + app.aboutInfo.cores + " threads" : "") },
                { k: "GPU",        v: app.aboutInfo.gpu || "" },
                { k: "Memory",     v: app.aboutInfo.ram || "" },
                { k: "Kernel",     v: app.aboutInfo.kernel || "" },
                { k: "Uptime",     v: app.aboutInfo.uptime || "" },
                { k: "Displays",   v: app.monInfo.map(m => m.name + " " + m.w + "\u00d7" + m.h + " at " + Math.round(m.hz) + " Hz").join(", ") }
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                visible: modelData.v !== ""
                spacing: 12
                Text {
                    Layout.preferredWidth: 90
                    text: modelData.k
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.v
                    color: app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Software" }

    Card {
        app: settingsRoot.app
        title: "Desktop"
        desc: "Hyprland " + (app.aboutInfo.hyprland || "?")
              + ", " + (app.aboutInfo.quickshell || "Quickshell")
              + (app.aboutInfo.shell ? ", " + app.aboutInfo.shell + " shell" : "")
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Copy details", "Open config"]
                onPicked: i => {
                    const a = app.aboutInfo
                    if (i === 0) {
                        const lines = [a.host, a.os, "CPU: " + a.cpu, "GPU: " + a.gpu,
                                       "RAM: " + a.ram, "Kernel: " + a.kernel,
                                       "Hyprland " + a.hyprland, a.quickshell]
                        app.run("printf '%s\\n' " + lines.map(x =>
                            "'" + String(x ?? "").replace(/'/g, "") + "'").join(" ") + " | wl-copy")
                    }
                    else
                        app.run("xdg-open \"$HOME/.config/quickshell\"")
                }
            }
        ]
    }
}
