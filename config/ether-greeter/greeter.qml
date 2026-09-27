import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// Ether Shell's login screen, for greetd.  One full-screen layer on each
// monitor (the card on the main one).  It has a background of its own, never
// anyone's desktop (it shows before anyone signs in): Ether Nightfall, next to
// this file, unless one has been chosen in Settings > Lock screen, which puts
// it and its colours in /var/lib/ether-greeter.
//
// Preview, inside your normal session, changing nothing about how you log in:
//   ETHER_GREETER_PREVIEW=1 qs -p ~/.config/ether-greeter/greeter.qml
// It's then an ordinary window, with the login screen's background, and the
// login is only simulated (any password works, except "wrong", which shows
// what a failed attempt looks like).
ShellRoot {
    id: root

    readonly property bool preview: Quickshell.env("ETHER_GREETER_PREVIEW") === "1"
    readonly property string home: Quickshell.env("HOME")
    // the background chosen in Settings, and its colours (the preview uses
    // the same place Settings writes to before the login screen is installed)
    readonly property string shared: preview && !installed ? home + "/.cache/ether/greeter" : "/var/lib/ether-greeter"
    property bool installed: false
    Process {
        running: root.preview
        command: ["test", "-w", "/var/lib/ether-greeter"]
        onExited: code => root.installed = code === 0
    }
    // the shipped background, next to this file
    readonly property string here: Qt.resolvedUrl(".").toString().replace("file://", "")
    // what the login screen remembers itself (the last username and session)
    readonly property string stateFile: preview ? "/tmp/ether-greeter-preview.json" : "/var/cache/ether-greeter/state.json"

    // ---- its look: the chosen background and colours, or the shipped ones ----
    property var pal: ({})
    property string wallpaper: ""
    property string mainScreen: ""
    FileView {
        path: root.shared + "/colors.json"
        onLoaded: {
            try { root.pal = JSON.parse(text()); root.wallpaper = root.shared + "/background" }
            catch (e) { shipped.reload() }
        }
        onLoadFailed: shipped.reload()
    }
    FileView {
        id: shipped
        path: root.here + "colors.json"
        onLoaded: {
            if (root.wallpaper !== "") return
            try { root.pal = JSON.parse(text()) } catch (e) { root.pal = ({}) }
            root.wallpaper = root.here + "background.jpg"
        }
    }
    FileView {
        path: root.shared + "/settings.json"
        onLoaded: { try { root.mainScreen = JSON.parse(text()).mainScreen || "" } catch (e) {} }
    }

    // ---- what it remembers: the session you last chose (not your username,
    // which you type each time) ----
    property int lastSession: 0
    FileView {
        id: stateView
        path: root.stateFile
        onLoaded: {
            try {
                const s = JSON.parse(text())
                root.lastSession = s.session || 0
            } catch (e) {}
        }
    }
    function remember(session) {
        stateWrite.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"',
                              "sh", root.stateFile, JSON.stringify({ session: session })]
        stateWrite.running = true
    }
    Process { id: stateWrite }

    // ---- the sessions ----
    // Hyprland under UWSM (the systemd session) when uwsm is installed, and
    // Hyprland on its own
    property bool hasUwsm: false
    Process {
        running: true
        command: ["sh", "-c", "command -v uwsm >/dev/null && echo yes"]
        stdout: StdioCollector { onStreamFinished: root.hasUwsm = text.trim() === "yes" }
    }
    readonly property var sessions: {
        const own = { name: "Hyprland", detail: "on its own",
                      command: ["sh", "-c", "command -v start-hyprland >/dev/null && exec start-hyprland || exec Hyprland"] }
        return hasUwsm ? [ { name: "Hyprland", detail: "with UWSM", command: ["uwsm", "start", "hyprland.desktop"] }, own ]
                       : [ own ]
    }

    // ---- caps lock, from the keyboard's own light ----
    property bool capsLock: false
    Process {
        id: capsRead
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -nr | head -1"]
        stdout: StdioCollector { onStreamFinished: root.capsLock = parseInt(text.trim()) > 0 }
    }
    Timer { interval: 400; running: true; repeat: true; onTriggered: capsRead.running = true }

    // ---- restart and power off ----
    Process { id: powerProc }
    function power(action) {
        if (root.preview) { console.log("preview: would " + action); return }
        powerProc.command = ["systemctl", action]
        powerProc.running = true
    }

    // ---- signing in ----
    // greetd asks, through PAM, for whatever the login needs: usually just
    // the password, which is answered straight away; anything more (a code,
    // an expired password) is put to you on the card.
    property var views: []                  // the card(s) to report back to
    property string pending: ""             // the password, until greetd asks for it
    property int chosenSession: 0
    function each(f) { for (const v of views) if (v) f(v) }
    function login(user, password, session) {
        chosenSession = session
        if (root.preview) {
            fakeLogin.user = user; fakeLogin.password = password
            fakeLogin.restart()
            return
        }
        if (!Greetd.available) { each(v => v.fail("The login service isn't running")); return }
        pending = password
        Greetd.createSession(user)
    }
    function respond(text) {
        if (root.preview) { each(v => v.info("Preview: that's all it would ask")); fakeDone.restart(); return }
        Greetd.respond(text)
    }
    Connections {
        target: root.preview ? null : Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                // the first secret question is the password already typed
                if (root.pending !== "" && !echoResponse) {
                    const p = root.pending
                    root.pending = ""
                    Greetd.respond(p)
                } else {
                    root.each(v => v.askMore(message, echoResponse))
                }
            } else if (message) {
                root.each(v => v.info(message))
            }
        }
        function onAuthFailure(message) {
            root.pending = ""
            Greetd.cancelSession()
            root.each(v => v.fail(""))
        }
        function onReadyToLaunch() {
            root.remember(root.chosenSession)
            // a marker for the start-up script: this login screen closing now
            // means someone signed in (not that it failed, which would bring
            // up the text login instead); then the session
            launchMark.running = true
        }
        function onError(error) {
            root.pending = ""
            Greetd.cancelSession()
            root.each(v => v.fail("Couldn't sign in: " + error))
        }
    }
    Process {
        id: launchMark
        command: ["sh", "-c", 'touch "${XDG_RUNTIME_DIR:-/tmp}/ether-greeter-launched"']
        onExited: {
            const s = root.sessions[root.chosenSession] || root.sessions[0]
            Greetd.launch(s.command, [], true)
        }
    }

    // preview: a pretend login that behaves like the real one
    Timer {
        id: fakeLogin
        property string user
        property string password
        interval: 700
        onTriggered: {
            if (password === "wrong") root.each(v => v.fail(""))
            else { root.remember(root.chosenSession); root.each(v => v.info("Preview: this is where Hyprland would start")); fakeDone.restart() }
        }
    }
    Timer { id: fakeDone; interval: 2500; onTriggered: root.each(v => { v.busy = false; v.info("") }) }

    // ---- the screens ----
    // the login screen: every monitor, the card on the main one
    Variants {
        model: root.preview ? [] : Quickshell.screens
        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool isMain: root.mainScreen !== "" ? modelData.name === root.mainScreen
                                                                 : modelData === Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: isMain ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "ether-greeter"
            color: "black"
            GreeterView {
                id: gv
                anchors.fill: parent
                main: win.isMain
                pal: root.pal
                wallpaper: root.wallpaper
                sessions: root.sessions
                sessionIndex: Math.min(root.lastSession, root.sessions.length - 1)
                capsLock: root.capsLock
                onLogin: (u, p, s) => root.login(u, p, s)
                onRespond: t => root.respond(t)
                onPower: a => root.power(a)
                Component.onCompleted: if (win.isMain) root.views = root.views.concat([gv])
            }
        }
    }
    // the preview: one ordinary window
    FloatingWindow {
        visible: root.preview
        implicitWidth: 1280
        implicitHeight: 720
        title: "Ether Shell login screen (preview)"
        color: "black"
        GreeterView {
            id: pv
            anchors.fill: parent
            main: true
            pal: root.pal
            wallpaper: root.wallpaper
            sessions: root.sessions
            sessionIndex: Math.min(root.lastSession, root.sessions.length - 1)
            capsLock: root.capsLock
            onLogin: (u, p, s) => root.login(u, p, s)
            onRespond: t => root.respond(t)
            onPower: a => root.power(a)
            Component.onCompleted: if (root.preview) root.views = root.views.concat([pv])
        }
    }
}
