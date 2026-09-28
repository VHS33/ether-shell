pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Apps: finding an app's icon from its window class (with overrides for
// apps whose class doesn't match their .desktop file), how often each is
// launched (the launcher puts favourites first), launching a command, the
// environment apps start with, and file search (the launcher asks, the
// native plugin answers).  Use it anywhere as Apps.iconFor(cls),
// .run(cmd)... (import qs.services).
//
// The shell passes in the native plugin (nativeItem).  Nothing here goes
// over the network.
Singleton {
    id: appsSvc

    property var nativeItem: null

    readonly property var appEnv: ({ "__EGL_VENDOR_LIBRARY_FILENAMES": null })

    // manual overrides for apps whose window class doesn't match their
    // .desktop file id
    readonly property var iconOverrides: ({
        "spotify":            "spotify",
        "discord":            "discord",
        "vesktop":            "vesktop",
        "code":               "code",
        "code-oss":           "code-oss",
        "steam":              "steam",
        "steam_app":          "steam",
        "thunar":             "thunar",
        "org.kde.dolphin":    "org.kde.dolphin",
        "kitty":              "kitty",
        "firefox":            "firefox",
        "librewolf":          "librewolf",
        "chromium":           "chromium",
        "obsidian":           "obsidian",
        "lutris":             "lutris",
        "heroic":             "heroic",
        "pavucontrol":        "pavucontrol",
        "systemsettings":     "systemsettings"
    })

    function iconFor(cls) {
        const raw = (cls || "").trim()
        if (!raw) return Quickshell.iconPath("application-x-executable")
        const low = raw.toLowerCase()

        // 1. explicit override
        const ov = appsSvc.iconOverrides[low]
        if (ov) {
            const e0 = DesktopEntries.byId(ov)
            if (e0) return Quickshell.iconPath(e0.icon, true)
            const p0 = Quickshell.iconPath(ov, true)
            if (p0) return p0
        }

        // 2. straight desktop-entry lookups
        const tries = [raw, low, low.replace(/_/g, "-"), low.split(".").pop()]
        for (const t of tries) {
            const e = DesktopEntries.byId(t)
            if (e) return Quickshell.iconPath(e.icon, true)
        }

        // 3. scan every entry for a matching StartupWMClass or id tail
        const all = DesktopEntries.applications?.values ?? []
        for (const e of all) {
            const sc = (e.startupClass || "").toLowerCase()
            if (sc && sc === low) return Quickshell.iconPath(e.icon, true)
        }
        for (const e of all) {
            const id = (e.id || "").toLowerCase()
            if (id === low || id.endsWith("." + low))
                return Quickshell.iconPath(e.icon, true)
        }

        // 4. icon theme by name, then generic
        const p = Quickshell.iconPath(low, true)
        if (p) return p
        return Quickshell.iconPath("application-x-executable")
    }

    // kept so anything already calling `qs ipc call audio ...` still
    // works: it opens Settings on the Output page

    readonly property var launchCounts: Config.cfg.launchCounts ?? ({})
    function noteLaunch(id) {
        const c = Object.assign({}, launchCounts)
        c[id] = (c[id] || 0) + 1
        Config.setting("launchCounts", c)
    }

    function run(cmd) {
        launchProc.command = ["sh", "-c", cmd]
        launchProc.running = true
    }
    Process { id: launchProc; environment: appsSvc.appEnv }

    property string fileQuery: ""
    property int fileLimit: 8
    readonly property var fileResults: appsSvc.nativeItem ? appsSvc.nativeItem.fileResults : []
    readonly property string fileResultsFor: appsSvc.nativeItem ? appsSvc.nativeItem.fileResultsFor : ""
    readonly property int fileCount: appsSvc.nativeItem ? appsSvc.nativeItem.fileCount : 0
}
