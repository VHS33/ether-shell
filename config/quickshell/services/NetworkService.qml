pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The network: Wi-Fi (on or off, the networks around, joining and leaving,
// passwords) and the connection in use (Wi-Fi or wired, and its name).  Use
// it anywhere as NetworkService.wifiOn, .wifiList, .wifiConnect(...)...
// (import qs.services).
//
// Two ways, the same properties either way: NetNative.qml, with Quickshell's
// own NetworkManager module (live, nothing polled), and nmcli when that
// can't load.  NetNative also carries Bluetooth's live side, which
// BluetoothService uses (nativeItem).
//
// It talks to NetworkManager on this PC; joining a network sends its
// password to NetworkManager, nowhere else.
Singleton {
    id: ns

    // ---- Wi-Fi and Bluetooth, native (Quickshell 0.3+) -------------------
    // NetNative.qml uses Quickshell's own NetworkManager and BlueZ modules:
    // live, nothing polled, no programs run.  Loaded on its own, so on an
    // older Quickshell (no such modules) it just fails to load and the
    // nmcli and bluetoothctl code below carries on.  Either way the same
    // properties and actions, so the UI doesn't need to know which.
    Loader { id: netNative; source: "NetNative.qml" }
    // the live side, whether or not it runs Wi-Fi (Bluetooth uses it too)
    readonly property bool netNativeOk: netNative.status === Loader.Ready
    readonly property var nativeItem: netNativeOk ? netNative.item : null
    readonly property bool netNativeOn: netNative.status === Loader.Ready && netNative.item.netOk
    Binding { target: ns; property: "wifiHas";   when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiHas : false; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "wifiOn";    when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiOn : false; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "wifiList";  when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiList : []; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "wifiBusy";  when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiBusy : ""; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "wifiAskPw"; when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiAskPw : ""; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "wifiError"; when: ns.netNativeOn; value: netNative.item ? netNative.item.wifiError : ""; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "netKind";   when: ns.netNativeOn; value: netNative.item ? netNative.item.netNow.kind : ""; restoreMode: Binding.RestoreNone }
    Binding { target: ns; property: "netName";   when: ns.netNativeOn; value: netNative.item ? netNative.item.netNow.name : ""; restoreMode: Binding.RestoreNone }
    function refreshNet() { if (!netNativeOn) netStatProc.running = true }
    // the password prompt, closed without joining
    function wifiCancelPw() {
        if (netNativeOn) netNative.item.wifiAskPw = ""
        wifiAskPw = ""
    }

    // ---- Wi-Fi (NetworkManager, through nmcli: the fallback) --------------
    // Lists are plain values.  Connecting runs nmcli with its arguments
    // as a list, never through a shell, so a network name or password
    // can't be mistaken for a command.
    property bool wifiHas: false
    property bool wifiOn: false
    property var wifiList: []            // { ssid, signal, secure, active }
    property string wifiBusy: ""         // the network being joined
    property string wifiAskPw: ""        // the network that needs a password
    property string wifiError: ""
    function refreshWifi(rescan) {
        if (netNativeOn) { netNative.item.refreshWifi(rescan); return }
        wifiScan.command = ["sh", "-c",
            "nmcli -t -f TYPE device | grep -qx wifi && echo HAS; " +
            "echo \"RADIO $(nmcli radio wifi)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan " +
            (rescan ? "yes" : "auto") + " 2>/dev/null | sed 's/^/NET /'"]
        wifiScan.running = true
    }
    Process {
        id: wifiScan
        stdout: StdioCollector {
            onStreamFinished: {
                let has = false, on = false
                const seen = {}, out = []
                for (const line of text.split("\n")) {
                    if (line === "HAS") has = true
                    else if (line.startsWith("RADIO ")) on = line.slice(6).trim() === "enabled"
                    else if (line.startsWith("NET ")) {
                        const f = ns.nmFields(line.slice(4))
                        if (f.length < 4 || !f[1]) continue
                        const n = { active: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0,
                                    secure: f[3] !== "" && f[3] !== "--" }
                        if (seen[n.ssid] !== undefined) {
                            const o = out[seen[n.ssid]]
                            if (n.active || n.signal > o.signal) out[seen[n.ssid]] = n
                            continue
                        }
                        seen[n.ssid] = out.length
                        out.push(n)
                    }
                }
                out.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
                ns.wifiHas = has
                ns.wifiOn = on
                ns.wifiList = out
            }
        }
    }
    Process {
        id: wifiAct
        stdout: StdioCollector { id: wifiActOut }
        stderr: StdioCollector { id: wifiActErr }
        onExited: code => {
            const msg = (wifiActErr.text + " " + wifiActOut.text).toLowerCase()
            if (code !== 0 && ns.wifiBusy !== "") {
                if (/secret|password|802-11-wireless-security/.test(msg)) ns.wifiAskPw = ns.wifiBusy
                else ns.wifiError = "Couldn't join " + ns.wifiBusy
            } else {
                ns.wifiAskPw = ""
                ns.wifiError = ""
            }
            ns.wifiBusy = ""
            ns.refreshWifi(false)
            netStatProc.running = true
        }
    }
    // nmcli -t separates fields with ":" and escapes any inside a field
    // (a network called "Cafe: 2" comes out as "Cafe\: 2")
    function nmFields(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur)
        return out
    }
    function wifiToggle() {
        if (netNativeOn) { netNative.item.wifiToggle(); return }
        wifiAct.command = ["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]
        wifiAct.running = true
    }
    function wifiConnect(ssid, pw) {
        if (netNativeOn) { netNative.item.wifiConnect(ssid, pw); return }
        wifiBusy = ssid
        wifiError = ""
        wifiAct.command = pw ? ["nmcli", "device", "wifi", "connect", ssid, "password", pw]
                             : ["nmcli", "device", "wifi", "connect", ssid]
        wifiAct.running = true
    }
    function wifiDisconnect(ssid) {
        if (netNativeOn) { netNative.item.wifiDisconnect(ssid); return }
        wifiAct.command = ["nmcli", "connection", "down", "id", ssid]
        wifiAct.running = true
    }

    // ---- network, for the sidebar's network tile ----------------------
    // The first connected device from NetworkManager: its kind and the
    // connection's name.  Refreshed whenever the sidebar opens.
    property string netKind: ""        // "wifi", "ethernet" or ""
    property string netName: ""
    Process {
        id: netStatProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let kind = "", name = ""
                for (const line of text.split("\n")) {
                    const f = line.split(":")
                    if (f.length < 3 || f[1] !== "connected") continue
                    if (f[0] === "wifi" || f[0] === "ethernet") {
                        kind = f[0]
                        name = f.slice(2).join(":")
                        break
                    }
                }
                ns.netKind = kind
                ns.netName = name
            }
        }
    }
}
