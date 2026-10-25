pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common

// The laptop's power mode (Power saver, Balanced, Performance), through
// power-profiles-daemon.  Shown only on a laptop that has it: `shown`.
// Use it anywhere as Power.shown, .name, .icon, .cycle() (import qs.services).
//
// Power saver comes on by itself when the battery reaches 20% while it's
// running down, and the mode from before comes back once it's plugged in
// (Settings > Idle, "Power saver when low"; on unless turned off).
// Choosing a mode yourself while it's low wins until it's plugged in again.
// Nothing here goes over the network.
Singleton {
    id: powerSvc

    // power-profiles-daemon is there (its command comes with it); without it
    // the modes can't change, so nothing is shown
    property bool available: false
    Process {
        running: true
        command: ["sh", "-c", "command -v powerprofilesctl"]
        onExited: code => powerSvc.available = code === 0
    }
    readonly property bool shown: available && Battery.present

    readonly property int profile: PowerProfiles.profile
    readonly property bool saver: profile === PowerProfile.PowerSaver
    readonly property bool performance: profile === PowerProfile.Performance
    readonly property string name: saver ? "Power saver" : performance ? "Performance" : "Balanced"
    readonly property string icon: saver ? "eco" : performance ? "rocket_launch" : "balance"

    // Power saver, Balanced, Performance (where the machine has it), round again
    function cycle() {
        set(saver ? PowerProfile.Balanced
            : !performance && PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance
            : PowerProfile.PowerSaver)
    }
    function set(p) {
        PowerProfiles.profile = p
        autoSet = false
        // picked while it's already low: that choice holds until plugged in
        // (picked earlier, Power saver still comes on at 20%)
        if (Battery.present && !Battery.pluggedIn && Battery.percent <= 20) userChose = true
    }

    // ---- Power saver when low ----------------------------------------
    readonly property bool autoOn: Config.cfg.autoPowerSaver !== false
    property bool autoSet: false        // we turned it on
    property bool userChose: false      // a mode was picked by hand while low
    property int before: PowerProfile.Balanced
    Connections {
        target: Battery
        function onPercentChanged() { powerSvc.check() }
        function onPluggedInChanged() { powerSvc.check() }
    }
    onShownChanged: check()
    function check() {
        // (the battery's level reads -1 for a moment as it goes away)
        if (!shown || !Battery.present || Battery.percent < 0) return
        if (Battery.pluggedIn) {
            if (autoSet) PowerProfiles.profile = before
            autoSet = false
            userChose = false
            return
        }
        if (autoOn && !autoSet && !userChose && !saver && Battery.percent <= 20) {
            before = profile
            PowerProfiles.profile = PowerProfile.PowerSaver
            autoSet = true
            Quickshell.execDetached(["notify-send", "-a", "Ether Shell", "-i", "battery-low",
                "Power saver on", "The battery is at " + Battery.percent
                + "%. Your usual mode comes back when you plug in."])
        }
    }
}
