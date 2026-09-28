pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth: whether this PC has an adapter, whether its system service
// (bluetoothd) is running (and starting it), and then on or off, the
// devices, scanning, connecting.  Use it anywhere as BluetoothService.btOn,
// .btList, .btConnect(...), .adapter, .start()... (import qs.services).
//
// The devices come from Quickshell's own Bluetooth (NetworkService's
// NetNative: live) or, when that can't see the adapter, bluetoothctl.
//
// Without an adapter the service can't run (its unit needs one), so the
// quick settings tile says so instead of offering to start it.  Starting it
// asks for your password (a system service: polkit's prompt).
//
// It reads /sys/class/bluetooth and asks systemctl and bluetoothd; nothing
// goes over the network.
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

    // ---- the devices ----
    // Quickshell's own Bluetooth gives up for good if bluetoothd wasn't
    // running when the shell started, so when there's an adapter it isn't
    // seeing (the service started later, from the tile), bluetoothctl does
    readonly property bool btNativeOn: NetworkService.netNativeOk && NetworkService.nativeItem.btOk
                                       && (NetworkService.nativeItem.btHas || !bs.adapter)
    onStarted: bs.refreshBt()
    Binding { target: bs; property: "btHas";      when: bs.btNativeOn; value: NetworkService.nativeItem ? NetworkService.nativeItem.btHas : false; restoreMode: Binding.RestoreNone }
    Binding { target: bs; property: "btOn";       when: bs.btNativeOn; value: NetworkService.nativeItem ? NetworkService.nativeItem.btOn : false; restoreMode: Binding.RestoreNone }
    Binding { target: bs; property: "btList";     when: bs.btNativeOn; value: NetworkService.nativeItem ? NetworkService.nativeItem.btList : []; restoreMode: Binding.RestoreNone }
    Binding { target: bs; property: "btScanning"; when: bs.btNativeOn; value: NetworkService.nativeItem ? NetworkService.nativeItem.btScanning : false; restoreMode: Binding.RestoreNone }
    Binding { target: bs; property: "btBusy";     when: bs.btNativeOn; value: NetworkService.nativeItem ? NetworkService.nativeItem.btBusy : ""; restoreMode: Binding.RestoreNone }

    // ---- Bluetooth (through bluetoothctl: the fallback) ----------------------
    property bool btHas: false
    property bool btOn: false
    property var btList: []              // { mac, name, paired, connected }
    property bool btScanning: false
    property string btBusy: ""
    function refreshBt() {
        if (btNativeOn) return                    // live: nothing to refresh
        btRead.command = ["sh", "-c",
            "bluetoothctl list 2>/dev/null | grep -q Controller && echo HAS; " +
            "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo ON; " +
            "bluetoothctl devices Paired 2>/dev/null | sed 's/^Device /PAIRED /'; " +
            "bluetoothctl devices Connected 2>/dev/null | sed 's/^Device /CONN /'; " +
            "bluetoothctl devices 2>/dev/null | sed 's/^Device /SEEN /'"]
        btRead.running = true
    }
    Process {
        id: btRead
        stdout: StdioCollector {
            onStreamFinished: {
                let has = false, on = false
                const dev = {}, order = []
                for (const line of text.split("\n")) {
                    if (line === "HAS") { has = true; continue }
                    if (line === "ON") { on = true; continue }
                    const m = line.match(/^(PAIRED|CONN|SEEN) ([0-9A-F:]{17}) ?(.*)$/)
                    if (!m) continue
                    if (!dev[m[2]]) { dev[m[2]] = { mac: m[2], name: m[3] || m[2], paired: false, connected: false }; order.push(m[2]) }
                    if (m[1] === "PAIRED") dev[m[2]].paired = true
                    if (m[1] === "CONN") dev[m[2]].connected = true
                }
                // connected first, then paired, then everything else nearby;
                // unnamed devices (just an address) are left out
                const out = order.map(k => dev[k]).filter(d => d.paired || !/^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name))
                out.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
                bs.btHas = has
                bs.btOn = on
                bs.btList = out
            }
        }
    }
    Process {
        id: btAct
        onExited: { bs.btBusy = ""; bs.refreshBt() }
    }
    Process {
        id: btScanProc
        command: ["bluetoothctl", "--timeout", "12", "scan", "on"]
        onExited: { bs.btScanning = false; bs.refreshBt() }
    }
    Timer {
        // while scanning, show devices as they're found
        interval: 2000; repeat: true
        running: bs.btScanning
        onTriggered: bs.refreshBt()
    }
    function btToggle() {
        if (btNativeOn) { NetworkService.nativeItem.btToggle(); return }
        btAct.command = ["bluetoothctl", "power", btOn ? "off" : "on"]
        btAct.running = true
    }
    function btScan() {
        if (btNativeOn) { NetworkService.nativeItem.btScan(); return }
        if (btScanning) return
        btScanning = true
        btScanProc.running = true
    }
    function btConnect(mac, paired) {
        if (btNativeOn) { NetworkService.nativeItem.btConnect(mac, paired); return }
        if (!/^[0-9A-F:]{17}$/i.test(mac)) return
        btBusy = mac
        btAct.command = paired ? ["bluetoothctl", "connect", mac]
            : ["sh", "-c", "bluetoothctl pair \"$1\" && bluetoothctl trust \"$1\" && bluetoothctl connect \"$1\"", "sh", mac]
        btAct.running = true
    }
    function btDisconnect(mac) {
        if (btNativeOn) { NetworkService.nativeItem.btDisconnect(mac); return }
        if (!/^[0-9A-F:]{17}$/i.test(mac)) return
        btBusy = mac
        btAct.command = ["bluetoothctl", "disconnect", mac]
        btAct.running = true
    }
}
