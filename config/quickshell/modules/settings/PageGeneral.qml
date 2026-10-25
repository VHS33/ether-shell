import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
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
    visible: settingsWin.page === 0
    readonly property int pageNo: 0
    spacing: 4
    // the fonts are looked for each time the page is opened (a font just
    // installed shows up), and when Settings opens on this page
    onVisibleChanged: if (visible) Fonts.refresh()
    Component.onCompleted: if (visible) Fonts.refresh()

    SectionLabel { app: settingsRoot.app; text: "Launcher" }

    Card {
        app: settingsRoot.app
        title: "File search"
        desc: !app.nativeOk ? "Needs the native plugin, which isn't built: re-run the installer."
              : app.cfg.fileSearch === false
              ? "Off: the launcher only finds apps, and nothing is indexed."
              : "The launcher finds your files as you type (start with / for files only). "
                + (app.fileCount ? app.fileCount.toLocaleString(Qt.locale(), "f", 0) + " files and folders in your home, kept up to date as they change. "
                                 : "Indexing your home\u2026 ")
                + "Hidden folders, caches and dependency folders are left out."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.fileSearch === false ? 0 : 1
                onPicked: i => app.setting("fileSearch", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Clipboard" }

    Card {
        app: settingsRoot.app
        title: "Keep copies when apps close"
        desc: !app.clipNativeOn
              ? "Needs the native clipboard, which isn't running: re-run the installer."
              : app.cfg.clipPersist === false
              ? "Off: when you close the app you copied from, what you copied goes with it (how Wayland works on its own)."
              : "When you close the app you copied from, your copy stays on the clipboard. Copies a password manager marks secret are never kept."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.cfg.clipPersist === false ? 0 : 1
                onPicked: i => app.setting("clipPersist", i === 1)
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Text" }

    Card {
        app: settingsRoot.app
        title: "Text size"
        desc: "Scales every label in the bar, dock, sidebar and panels. Takes effect straight away."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0.8
                to: 1.4
                tick: 1
                step: 0.05
                value: app.cfg.fontScale ?? 1
                label: Math.round(value * 100) + "%"
                onMoved: v => app.setting("fontScale",
                                          Math.round(v * 20) / 20)
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.fontScale === undefined ? 0 : -1
                onPicked: app.resetSetting("fontScale")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Font"
        desc: "For the whole shell, and for apps (GTK, Qt and KDE). Open apps may need a restart to switch."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.uiFont ? -1 : 0
                onPicked: app.resetSetting("uiFont")
            }
        ]
        FontPicker {
            app: settingsRoot.app
            picks: Fonts.picksText
            all: Fonts.all
            current: Fonts.text
            sample: "Aa"
            onPicked: f => Fonts.setText(f)
        }
    }

    Card {
        app: settingsRoot.app
        title: "Terminal font"
        desc: "Monospace, for the terminal (kitty) and code in apps. Open terminals switch straight away."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.monoFont ? -1 : 0
                onPicked: app.resetSetting("monoFont")
            }
        ]
        FontPicker {
            app: settingsRoot.app
            picks: Fonts.picksMono
            all: Fonts.monoAll
            current: Fonts.mono
            sample: "0O {}"
            onPicked: f => Fonts.setMono(f)
        }
    }

}
