import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common.widgets
import qs.services

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
                    font.family: Theme.uiFont
                    font.pixelSize: app.fs(12)
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.v
                    color: app.cFg
                    font.family: Theme.uiFont
                    font.pixelSize: app.fs(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Software" }

    // the version that came with the shell's files (as ether -d shows it)
    FileView {
        id: versionFile
        path: Quickshell.shellPath("VERSION")
        blockLoading: false
    }
    Card {
        app: settingsRoot.app
        title: "Desktop"
        desc: (versionFile.text().trim() ? "Ether Shell " + versionFile.text().trim() + ", " : "")
              + "Hyprland " + (app.aboutInfo.hyprland || "?")
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

    Card {
        app: settingsRoot.app
        title: "Welcome setup"
        desc: "The first-run setup again: your wallpaper and colours, which screen gets the bar, and the weather."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Run it again"]
                onPicked: { app.settingsShown = false; app.openWelcome() }
            }
        ]
    }

    // ---- updates: Ether Shell and the system's packages, only when asked ----
    SectionLabel { app: settingsRoot.app; text: "Updates" }

    Card {
        app: settingsRoot.app
        title: "Check for updates"
        desc: Updates.checking ? "Checking\u2026"
            : Updates.checked ? "Last checked at " + Qt.formatDateTime(Updates.checkedAt, app.cfg.clock24h === true ? "HH:mm" : "h:mm AP") + "."
            : "Ether Shell and your system's packages. Nothing is checked until you press this."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: [Updates.checking ? "Checking\u2026" : "Check now"]
                onPicked: Updates.check()
            }
        ]
    }

    Card {
        app: settingsRoot.app
        visible: Updates.checked
        searchable: false
        title: "Ether Shell"
        desc: Updates.shellState === "new" ? (Updates.shellHave || "Yours") + " installed. " + Updates.shellLatest + " is out."
            : Updates.shellState === "current" ? Updates.shellHave + ", the newest."
            : Updates.shellState === "ahead" ? Updates.shellHave + ", newer than GitHub's " + Updates.shellLatest + "."
            : Updates.shellState === "none" ? "GitHub's copy doesn't say which version it is."
            : "Couldn't reach GitHub. Online?"
        trailing: [
            Seg {
                app: settingsRoot.app
                visible: Updates.shellState === "new"
                options: ["Update"]
                onPicked: Updates.updateShell()
            }
        ]
    }

    Card {
        id: pkgCard
        app: settingsRoot.app
        visible: Updates.checked
        searchable: false
        title: "System packages"
        readonly property var all: Updates.repoList.map(p => Object.assign({ aur: false }, p))
                                   .concat(Updates.aurList.map(p => Object.assign({ aur: true }, p)))
        desc: (Updates.repoState === "missing" ? "Checking needs pacman-contrib: sudo pacman -S pacman-contrib. "
             : Updates.repoState === "error" ? "Couldn't check (offline?). "
             : "")
            + (Updates.pkgCount === 0 ? (Updates.repoState === "ok" ? "Everything is up to date." : "")
               : Updates.pkgCount + (Updates.pkgCount === 1 ? " update" : " updates")
                 + (Updates.aurList.length ? ", " + Updates.aurList.length + " from the AUR." : "."))
            + (Updates.aurHelper === "" ? " AUR packages aren't checked (no paru or yay)."
               : Updates.aurState === "error" ? " Couldn't check the AUR." : "")
        trailing: [
            Seg {
                app: settingsRoot.app
                visible: Updates.pkgCount > 0
                options: ["Update all"]
                onPicked: Updates.updatePackages()
            }
        ]

        // what would change, name and versions
        Repeater {
            model: pkgCard.all.slice(0, 40)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: app.cFg
                    font.family: Theme.font
                    font.pixelSize: app.fs(11)
                    elide: Text.ElideRight
                }
                Text {
                    text: modelData.from + "  ->  " + modelData.to
                    color: app.cDim
                    font.family: Theme.font
                    font.pixelSize: app.fs(11)
                }
                Text {
                    Layout.preferredWidth: 30
                    text: modelData.aur ? "AUR" : ""
                    color: app.cBlue
                    font.family: Theme.font
                    font.weight: Font.Bold
                    font.pixelSize: app.fs(10)
                }
            }
        }
        Text {
            visible: pkgCard.all.length > 40
            text: "and " + (pkgCard.all.length - 40) + " more"
            color: app.cDim
            font.family: Theme.uiFont
            font.pixelSize: app.fs(11)
        }
    }
}
