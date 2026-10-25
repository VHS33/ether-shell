pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// The laptop's battery, from UPower (a laptop battery only: desktops, and a
// mouse's or headphones' batteries, don't count).  Use it anywhere as
// Battery.present, .percent, .charging, .low... (import qs.services).
//
// A warning at 10% and again at 5% while it's running down, once each
// until it's charged again.  Nothing here goes over the network.
Singleton {
    id: batterySvc

    readonly property var dev: UPower.displayDevice
    // a laptop battery, really there (UPower's combined device reports one
    // even without, so check what it is)
    readonly property bool present: !!dev && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property int percent: present ? Math.round(dev.percentage * 100) : -1
    readonly property bool charging: present && (dev.state === UPowerDeviceState.Charging
                                                 || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: present && dev.state === UPowerDeviceState.FullyCharged
    readonly property bool pluggedIn: present && !UPower.onBattery
    readonly property bool low: present && !pluggedIn && percent <= 15

    // the icon: Material Symbols' battery levels (0 to 6 bars; the bar lays
    // them on their side), or a bolt while charging (shown upright)
    readonly property string icon: {
        if (!present) return "battery_unknown"
        if (charging) return "bolt"
        if (full || percent >= 95) return "battery_full"
        if (percent <= 5) return "battery_0_bar"
        return "battery_" + Math.max(0, Math.min(6, Math.round(percent / 100 * 6))) + "_bar"
    }

    // "2 h 10 min left", "Full in 40 min", "Plugged in", "Fully charged"
    function dur(s) {
        const m = Math.round(s / 60)
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), r = m % 60
        return h + " h" + (r ? " " + r + " min" : "")
    }
    readonly property string detail: {
        if (!present) return ""
        if (full) return "Fully charged"
        if (charging) return dev.timeToFull > 0 ? "Full in " + dur(dev.timeToFull) : "Charging"
        if (pluggedIn) return "Plugged in"
        return dev.timeToEmpty > 0 ? dur(dev.timeToEmpty) + " left" : "On battery"
    }

    // ---- low battery warnings ----------------------------------------
    property int warned: 100           // the lowest level already warned about
    onPercentChanged: check()
    onPluggedInChanged: check()
    function check() {
        if (!present) return
        if (pluggedIn) { warned = 100; return }
        const at = percent <= 5 ? 5 : percent <= 10 ? 10 : 100
        if (at < warned) {
            warned = at
            Quickshell.execDetached(["notify-send", "-a", "Ether Shell", "-u", "critical", "-i", "battery-caution",
                at === 5 ? "Battery almost empty" : "Battery low",
                percent + "% left" + (dev.timeToEmpty > 0 ? ", about " + dur(dev.timeToEmpty) : "")
                + ". Plug in soon."])
        }
    }
}
