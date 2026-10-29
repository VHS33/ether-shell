import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// The wallpaper, drawn by the shell so it can move: a little larger than the
// screen.  Switching workspaces gives it a bounce the way you went (left
// going 1 → 2, as the windows move; right going 2 → 1; up and down with
// that workspace style), springing back to the middle, so even on an empty
// workspace you see that you moved, and which way.  On the background layer,
// over awww's still copy (which shows again when this is switched off:
// Settings > Windows > Wallpaper moves too).  A new wallpaper crossfades in.
// Game mode, or animations off: it jumps instead of sliding.
// A moving wallpaper (a video or GIF) plays over its still (LiveLayer),
// resting for fullscreen apps and games, while locked, and on battery.
// Nothing here goes over the network.
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    LazyLoader {
        id: perScreen
        required property var modelData
        // (also for a moving wallpaper, which only the shell can play, even
        // with the slide off)
        active: rootV.app.currentWall !== ""
                && (rootV.app.cfg.wsWallSlide !== false || rootV.app.isMovingWall(rootV.app.currentWall))

    PanelWindow {
        id: bd
        readonly property var app: rootV.app
        readonly property var modelData: perScreen.modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Background
        // its own name, so the shell's blur rule doesn't blur under it
        WlrLayershell.namespace: "ether-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { width: 0; height: 0 }          // clicks go to the desktop

        // ---- where it is: this screen's workspaces, and the one showing ----
        readonly property string name: modelData.name
        readonly property var ids: name === app.secondScreen ? app.secondWorkspaces : app.mainWorkspaces
        readonly property int activeId: {
            if (name === app.mainScreen) return app.mainActive
            if (name === app.secondScreen) return app.secondActive
            const m = Hyprland.monitors.values.find(m => m.name === bd.name)
            return m && m.activeWorkspace ? m.activeWorkspace.id : -1
        }
        // where this screen's workspace is in its list; a move along it
        // bounces the way it went (not to or from the scratchpad, say,
        // which isn't in the list)
        property int index: -1
        function place() {
            const i = ids.indexOf(activeId)
            if (i < 0) return
            if (index >= 0 && i !== index) bounce(i > index ? 1 : -1)
            index = i
        }
        onActiveIdChanged: place()
        onIdsChanged: place()
        Component.onCompleted: place()

        readonly property bool vertical: (app.cfg.wsAnim || "slide") === "slidevert"
        // how far it bounces, each way: 1.5% of the screen
        readonly property real reach: Math.round((vertical ? height : width) * 0.015)
        // the push the way it went (quick), then a spring back to the
        // middle, a little past it and settling; none with game mode or
        // animations off
        property real push: 0
        function bounce(dir) {
            if (app.dur(100) === 0 || app.cfg.wsWallSlide === false) return
            out.to = -dir * reach
            bouncer.restart()
        }
        SequentialAnimation {
            id: bouncer
            NumberAnimation { id: out; target: bd; property: "push"; duration: bd.app.dur(110); easing.type: Easing.OutCubic }
            NumberAnimation { target: bd; property: "push"; to: 0; duration: bd.app.dur(320); easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        // ---- the picture ----
        // room for the bounce (and its overshoot) on both sides
        Item {
            id: canvas
            readonly property real room: Math.ceil(bd.reach * 1.3)
            width: bd.width + (bd.vertical ? 0 : 2 * room)
            height: bd.height + (bd.vertical ? 2 * room : 0)
            x: bd.vertical ? 0 : -room + bd.push
            y: bd.vertical ? -room + bd.push : 0

            // Two copies, so a new wallpaper fades in over the old one; the
            // hidden copy is let go once the fade is done.
            property int front: 0
            // (a moving wallpaper's still, which it plays over)
            readonly property string want: bd.app.currentStill
            readonly property size decode: Qt.size(Math.round(width * bd.modelData.devicePixelRatio),
                                                    Math.round(height * bd.modelData.devicePixelRatio))
            function url(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : "" }
            property bool started: false
            function show() {
                if (!started) return                  // the first one is loaded below
                const u = url(want)
                const cur = front === 0 ? imgA : imgB
                if (cur.source.toString() === u) return
                const back = front === 0 ? imgB : imgA
                if (back.source.toString() === u) return
                back.source = u                   // fades in once it's loaded
            }
            onWantChanged: show()
            Component.onCompleted: { imgA.source = url(want); started = true }
            Timer { id: release; interval: 700; onTriggered: (canvas.front === 0 ? imgB : imgA).source = "" }

            Image {
                id: imgA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: canvas.decode
                opacity: canvas.front === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: bd.app.dur(500) } }
                onStatusChanged: if (status === Image.Ready && canvas.front !== 0 && source.toString() !== "") { canvas.front = 0; release.restart() }
            }
            Image {
                id: imgB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize: canvas.decode
                opacity: canvas.front === 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: bd.app.dur(500) } }
                onStatusChanged: if (status === Image.Ready && canvas.front !== 1 && source.toString() !== "") { canvas.front = 1; release.restart() }
            }

            // ---- a moving wallpaper, over its still ----
            readonly property string movie: bd.app.isMovingWall(bd.app.currentWall) && bd.app.cfg.wallMotion !== "never"
                                            ? bd.app.currentWall : ""
            // resting: something fullscreen on this screen, a game, the lock
            // screen, battery power, or (if chosen) any window on it
            readonly property var ws: {
                const m = Hyprland.monitors.values.find(m => m.name === bd.name)
                return m ? m.activeWorkspace : null
            }
            readonly property bool resting: (ws !== null && ws.hasFullscreen)
                || bd.app.gameMode || bd.app.screenLocked
                || (Battery.present && !Battery.pluggedIn)
                || (bd.app.cfg.wallMotion === "empty" && ws !== null && ws.toplevels.values.length > 0)
            Loader {
                id: live
                anchors.fill: parent
                active: canvas.movie !== ""
                source: "LiveLayer.qml"
                onLoaded: { item.source = Qt.binding(() => canvas.movie); item.playing = Qt.binding(() => !canvas.resting); item.fade = bd.app.dur(500) }
                onStatusChanged: if (status === Loader.Error) console.log("moving wallpaper: can't play it here (is qt6-multimedia installed?); showing its still")
            }
        }
    }
    }
}
