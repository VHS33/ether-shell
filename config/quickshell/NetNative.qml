import QtQuick
import Quickshell.Networking
import Quickshell.Bluetooth

// Wi-Fi and Bluetooth through Quickshell's own NetworkManager and BlueZ
// modules (Quickshell 0.3 and later): live, with nothing polled and no
// programs run.  It offers exactly what the shell's nmcli and bluetoothctl
// code offers (the same properties and actions), so the quick settings UI is
// unchanged.  shell.qml loads this separately: on an older Quickshell without
// these modules it fails to load, and the nmcli and bluetoothctl code simply
// carries on.
QtObject {
    id: nn

    // ---- which parts work here ----
    readonly property bool netOk: Networking.backend === NetworkBackendType.NetworkManager
    readonly property bool btOk: Bluetooth.defaultAdapter !== null

    // =====================================================================
    //   Wi-Fi and the connection tile
    // =====================================================================
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevices: devices.filter(d => d.type === DeviceType.Wifi)
    readonly property bool wifiHas: wifiDevices.length > 0
    readonly property bool wifiOn: Networking.wifiEnabled

    // { ssid, signal (0-100), secure, active }, connected first, then strongest
    readonly property var wifiList: {
        const seen = {}, out = []
        for (const d of wifiDevices) {
            for (const n of d.networks.values) {
                if (!n.name) continue
                const item = { ssid: n.name, signal: Math.round((n.signalStrength || 0) * 100),
                               secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
                               active: n.connected }
                if (seen[item.ssid] !== undefined) {
                    const o = out[seen[item.ssid]]
                    if (item.active || item.signal > o.signal) out[seen[item.ssid]] = item
                    continue
                }
                seen[item.ssid] = out.length
                out.push(item)
            }
        }
        out.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
        return out
    }

    // the connection tile: the first connected device, Wi-Fi before wired
    readonly property var netNow: {
        for (const d of devices) {
            if (!d.connected) continue
            if (d.type === DeviceType.Wifi) {
                const n = d.networks.values.find(x => x.connected)
                return { kind: "wifi", name: n ? n.name : d.name }
            }
        }
        for (const d of devices)
            if (d.connected && d.type === DeviceType.Wired)
                return { kind: "ethernet", name: d.network && d.network.name ? d.network.name : "Wired" }
        return { kind: "", name: "" }
    }

    property string wifiBusy: ""          // the network being joined
    property string wifiAskPw: ""         // the network that needs a password
    property string wifiError: ""

    function findNetwork(ssid) {
        for (const d of wifiDevices)
            for (const n of d.networks.values)
                if (n.name === ssid) return n
        return null
    }

    // scanning costs power: only while someone's looking at the list
    property Timer scanStop: Timer {
        interval: 15000
        onTriggered: { for (const d of nn.wifiDevices) d.scannerEnabled = false }
    }
    function refreshWifi(rescan) {
        if (!rescan) return
        for (const d of wifiDevices) d.scannerEnabled = true
        scanStop.restart()
    }
    function wifiToggle() { Networking.wifiEnabled = !Networking.wifiEnabled }
    function wifiConnect(ssid, pw) {
        const n = findNetwork(ssid)
        if (!n) { wifiError = "Couldn't find " + ssid; return }
        wifiBusy = ssid
        wifiError = ""
        wifiAskPw = ""
        if (pw) n.connectWithPsk(pw)
        else n.connect()
        busyTimeout.restart()
    }
    function wifiDisconnect(ssid) {
        const n = findNetwork(ssid)
        if (n) n.disconnect()
    }
    // joined: clear the busy state
    onWifiListChanged: {
        if (wifiBusy !== "" && wifiList.some(x => x.ssid === wifiBusy && x.active)) {
            wifiBusy = ""; wifiAskPw = ""; wifiError = ""; busyTimeout.stop()
        }
    }
    // a network that fails says why: no password, or a wrong one, asks for it
    property Instantiator failWatch: Instantiator {
        model: nn.wifiDevices.length ? nn.wifiDevices[0].networks.values : []
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                if (modelData.name !== nn.wifiBusy) return
                nn.busyTimeout.stop()
                if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout
                        || reason === ConnectionFailReason.WifiClientFailed)
                    nn.wifiAskPw = nn.wifiBusy
                else nn.wifiError = "Couldn't join " + nn.wifiBusy
                nn.wifiBusy = ""
            }
        }
    }
    // no answer at all in 45 seconds
    property Timer busyTimeout: Timer {
        interval: 45000
        onTriggered: if (nn.wifiBusy !== "") { nn.wifiError = "Couldn't join " + nn.wifiBusy; nn.wifiBusy = "" }
    }

    // =====================================================================
    //   Bluetooth
    // =====================================================================
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btHas: adapter !== null
    readonly property bool btOn: adapter ? adapter.enabled : false
    readonly property bool btScanning: adapter ? adapter.discovering : false

    // { mac, name, paired, connected, battery (0-100, or -1), icon },
    // connected first, then paired, then nearby; unnamed devices left out
    readonly property var btList: {
        if (!adapter) return []
        const out = []
        for (const d of adapter.devices.values) {
            const name = d.name || d.deviceName || ""
            const unnamed = name === "" || /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(name)
            if (unnamed && !d.paired) continue
            out.push({ mac: d.address, name: unnamed ? d.address : name, paired: d.paired, connected: d.connected,
                       battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1, icon: d.icon || "" })
        }
        out.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
        return out
    }
    property string btBusy: ""

    function findDevice(mac) {
        if (!adapter) return null
        return adapter.devices.values.find(d => d.address === mac) || null
    }
    function refreshBt() { }              // live: nothing to refresh
    function btToggle() { if (adapter) adapter.enabled = !adapter.enabled }
    // discovery stops by itself after 12 seconds
    property Timer scanBtStop: Timer {
        interval: 12000
        onTriggered: if (nn.adapter) nn.adapter.discovering = false
    }
    function btScan() {
        if (!adapter || adapter.discovering) return
        adapter.discovering = true
        scanBtStop.restart()
    }
    // new devices: pair, then trust (so they reconnect by themselves), then connect
    property string pairing: ""
    property Timer pairWatch: Timer {
        interval: 500; repeat: true
        property int ticks: 0
        onTriggered: {
            const d = nn.findDevice(nn.pairing)
            ticks++
            if (d && d.paired) {
                stop(); d.trusted = true; d.connect(); nn.pairing = ""
            } else if (!d || ticks > 60 || (!d.pairing && ticks > 4 && !d.paired)) {
                stop(); nn.pairing = ""; nn.btBusy = ""          // gave up, or it was refused
            }
        }
    }
    function btConnect(mac, paired) {
        const d = findDevice(mac)
        if (!d) return
        btBusy = mac
        btBusyStop.restart()
        if (paired || d.paired) d.connect()
        else { pairing = mac; pairWatch.ticks = 0; pairWatch.start(); d.pair() }
    }
    function btDisconnect(mac) {
        const d = findDevice(mac)
        if (!d) return
        btBusy = mac
        btBusyStop.restart()
        d.disconnect()
    }
    // busy until the device settles (or 30 seconds); checked whenever the
    // list changes, and once the first moment's grace is over
    function checkBtBusy() {
        if (btBusy === "" || pairing !== "" || btBusyStop.fresh) return
        const d = findDevice(btBusy)
        if (!d || d.state === BluetoothDeviceState.Connected || d.state === BluetoothDeviceState.Disconnected) {
            btBusy = ""; btBusyStop.stop()
        }
    }
    onBtListChanged: checkBtBusy()
    property Timer btBusyStop: Timer {
        interval: 30000
        property bool fresh: false
        onRunningChanged: if (running) { fresh = true; nn.freshOff.restart() }
        onTriggered: nn.btBusy = ""
    }
    // a moment's grace before "settled" counts, so the state has time to change
    property Timer freshOff: Timer { interval: 1500; onTriggered: { nn.btBusyStop.fresh = false; nn.checkBtBusy() } }
}
