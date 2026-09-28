pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether this PC has a Bluetooth adapter, and whether Bluetooth's system
// service (bluetoothd) is running, and starting it.  Use it anywhere as
// BluetoothService.adapter, .active, .start() (import qs.services).
//
// Without an adapter the service can't run (its unit needs one), so the
// quick settings tile says so instead of offering to start it.  Starting it
// asks for your password (a system service: polkit's prompt).
//
// It reads /sys/class/bluetooth and asks systemctl; nothing goes over the
// network.
Singleton {
    id: bs

    property bool adapter: false        // an adapter in /sys/class/bluetooth
    property bool active: false         // bluetooth.service running
    property bool starting: false
    property string error: ""
    signal started()                    // it's running now: read Bluetooth again

    function check() { if (!checkProc.running) checkProc.running = true }
    function start() {
        if (starting || active || !adapter) return
        starting = true
        error = ""
        startProc.running = true
    }

    Process {
        id: checkProc
        running: true
        command: ["sh", "-c",
            "ls /sys/class/bluetooth 2>/dev/null | grep -q . && echo ADAPTER; " +
            "systemctl is-active --quiet bluetooth && echo ACTIVE; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const wasActive = bs.active
                bs.adapter = text.indexOf("ADAPTER") >= 0
                bs.active = text.indexOf("ACTIVE") >= 0
                if (bs.active && !wasActive) bs.started()
            }
        }
    }
    Process {
        id: startProc
        command: ["systemctl", "start", "bluetooth"]
        onExited: code => {
            bs.starting = false
            if (code !== 0) { bs.error = "Couldn't start Bluetooth"; bs.check(); return }
            bs.tries = 6
            bs.check()
        }
    }
    // once started, it can take a moment to answer: a few more looks, a
    // second apart, then no more (nothing is checked in the background)
    property int tries: 0
    Timer {
        interval: 1000; repeat: true
        running: bs.tries > 0 && !bs.active
        onTriggered: { bs.tries--; bs.check() }
    }
}
