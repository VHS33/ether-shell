pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../lib/profiles.mjs" as Profiles

// The monitors: their modes and layout (from hyprctl, whenever Settings >
// Displays opens), applying a new layout with 15 seconds to keep it or go
// back, and monitor profiles (a saved layout for each set of screens, used
// again when that set is connected).  Use it anywhere as Displays.monInfo,
// .applyDisplays(...), .monProfiles... (import qs.services).
//
// The shell passes in which screen is the main one and which the second
// (mainScreen, secondScreen).  Nothing here goes over the network.
Singleton {
    id: displaysSvc

    property string mainScreen: ""
    property string secondScreen: ""

    // ---- displays ----------------------------------------------------
    // monInfo: plain values from `hyprctl monitors all -j`, refreshed
    // whenever the Displays page opens.  Never live objects.
    property var monInfo: []
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    displaysSvc.monInfo = JSON.parse(text).map(m => ({
                        name:  m.name,
                        desc:  ((m.make || "") + " " + (m.model || "")).trim() || m.description || "",
                        w:     m.width,
                        h:     m.height,
                        hz:    m.refreshRate,
                        scale: m.scale,
                        x:     m.x,
                        y:     m.y,
                        transform: (m.transform || 0) % 4,
                        // Hyprland reports whether it's on right now; the
                        // setting (on, off, games only) is what was saved
                        vrr:   (Config.cfg.monitors && Config.cfg.monitors[m.name] && typeof Config.cfg.monitors[m.name].vrr === "number")
                               ? Config.cfg.monitors[m.name].vrr : (m.vrr ? 1 : 0),
                        modes: (m.availableModes || []).map(x => String(x))
                    }))
                } catch (e) {
                    console.log("hyprctl monitors parse failed:", e)
                }
            }
        }
    }
    function refreshMonitors() { monProc.running = true }
    // the Displays page reads modes and brightness each time it opens

    // Apply, then keep or revert.  The countdown lives here rather than
    // in the panel, so it still runs if the screen showing the panel
    // goes dark.
    property var displayBackup: undefined
    property bool displayHadUser: false
    property int revertLeft: 0

    property var arrangeBackup: undefined
    function applyDisplays(monitors, arrange) {
        if (revertLeft === 0) {
            displayHadUser = Config.user.monitors !== undefined
            displayBackup = displayHadUser
                ? JSON.parse(JSON.stringify(Config.user.monitors)) : undefined
            arrangeBackup = Config.user.monitorsArrange
        }
        Config.setting("monitorsArrange", arrange)
        Config.setting("monitors", monitors)
        revertLeft = 15
        revertTimer.restart()
    }
    function keepDisplays() {
        revertTimer.stop()
        revertLeft = 0
        displayBackup = undefined
        refreshMonitors()
    }
    function revertDisplays() {
        revertTimer.stop()
        revertLeft = 0
        if (arrangeBackup === undefined) Config.resetSetting("monitorsArrange")
        else Config.setting("monitorsArrange", arrangeBackup)
        if (displayHadUser) Config.setting("monitors", displayBackup)
        else Config.resetSetting("monitors")
        displayBackup = undefined
        monRefreshLater.restart()
    }
    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            displaysSvc.revertLeft -= 1
            if (displaysSvc.revertLeft <= 0) displaysSvc.revertDisplays()
        }
    }
    // Hyprland needs a moment after the reload before it reports the
    // restored modes
    Timer {
        id: monRefreshLater
        interval: 1200
        onTriggered: displaysSvc.refreshMonitors()
    }

    // ---- monitor profiles (Settings, Displays) ----
    // A saved layout for one set of connected screens (lib/profiles.mjs).
    // When the screens connected change (a monitor plugged in or out, or a
    // change while the PC was off: the last set is saved), the profile for
    // the new set is used, with a notice.  Changing the layout by hand on
    // the same screens is never undone: only a change of screens switches.
    readonly property var monProfiles: Profiles.readProfiles(Config.cfg.monitorProfiles)
    readonly property var screensNowList: Quickshell.screens.map(s => ({ name: s.name, model: s.model, serial: s.serialNumber }))
    readonly property string screensNow: Profiles.screensKey(screensNowList)
    readonly property var profileNow: Profiles.findProfile(monProfiles, screensNow)
    readonly property bool profileNowInUse: profileNow !== null && Profiles.profileInUse(profileNow, Config.cfg.monitors, mainScreen)
    readonly property bool profilesAuto: Config.cfg.monitorProfilesAuto !== false

    // save the layout now (the Displays page's, as applied) for these
    // screens.  -> what happened, in words
    function saveMonProfile(name, monitors) {
        const p = Profiles.makeProfile(name, screensNowList, monitors, mainScreen, secondScreen)
        if (!p) return "Give it a name first."
        const r = Profiles.addProfile(monProfiles, p)
        if (!r) return "There's room for " + Profiles.MAX_PROFILES + " profiles: delete one first."
        Config.setting("monitorProfiles", r.list)
        Config.setting("monitorsLastScreens", screensNow)
        return r.replaced.length ? "Saved, replacing \u201c" + r.replaced.join("\u201d and \u201c") + "\u201d."
                                 : "Saved. It's used whenever these screens are connected."
    }
    function deleteMonProfile(name) { Config.setting("monitorProfiles", Profiles.removeProfile(monProfiles, name)) }
    function useMonProfile(p) {
        if (!p || p.key !== screensNow) return
        Config.setting("monitors", Profiles.profileMonitors(p, Config.cfg.monitors))
        Config.setting("monitorsArrange", "custom")
        if (p.main) Config.setting("mainScreen", p.main)
        if (p.second) Config.setting("secondScreen", p.second)
        monRefreshLater.restart()
    }
    // the screens changed: wait for them to settle (a monitor waking can
    // come and go a few times), then switch if there's a profile for them
    onScreensNowChanged: screensSettle.restart()
    Timer {
        id: screensSettle
        interval: 2500
        running: true                          // once at start, too
        onTriggered: displaysSvc.screensChangedTo(displaysSvc.screensNow)
    }
    function screensChangedTo(key) {
        if (key === "" || key === Config.cfg.monitorsLastScreens) return
        Config.setting("monitorsLastScreens", key)
        const p = profileNow
        if (!profilesAuto || !p || profileNowInUse || revertLeft > 0) return
        useMonProfile(p)
        Quickshell.execDetached(["notify-send", "-a", "Ether Shell", "-i", "video-display",
                                 "Screens changed", "Using your \u201c" + p.name + "\u201d layout."])
    }
}
