pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Clipboard history: from the native plugin (live) or cliphist (the
// fallback: wl-paste watching, read when the sidebar or panel opens),
// copying an item back, deleting one, wiping all, and image thumbnails for
// the clipboard panel.  Use it anywhere as Clipboard.clipItems,
// .clipCopy(id)... (import qs.services).
//
// The shell passes in the native plugin (nativeItem) and whether the
// clipboard panel is open (panelOpen, for thumbnails), and closes the
// panels when an item is copied (copied).  Nothing here goes over the
// network.
Singleton {
    id: clipSvc

    property var nativeItem: null
    property bool panelOpen: false
    signal copied()

    property var clipItems: []
    readonly property bool clipNativeOn: clipSvc.nativeItem !== null && clipSvc.nativeItem.clipAvailable
    Binding { target: clipSvc; property: "clipItems"; when: clipSvc.clipNativeOn
              value: clipSvc.nativeItem ? clipSvc.nativeItem.clipItems : []; restoreMode: Binding.RestoreNone }
    function readClipboard() {
        if (clipNativeOn) return              // live already
        clipProc.running = true
    }
    // the fallback's watchers, once it's clear the native history isn't there
    property bool clipDecided: false
    Timer { interval: 3000; running: true; onTriggered: clipSvc.clipDecided = true }
    Process { running: clipSvc.clipDecided && !clipSvc.clipNativeOn; command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"] }
    Process { running: clipSvc.clipDecided && !clipSvc.clipNativeOn; command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"] }

    Process {
        id: clipProc
        command: ["sh", "-c", "cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    if (!line.length) continue
                    const tab = line.indexOf("\t")
                    if (tab === -1) continue
                    out.push({
                        id: line.slice(0, tab),
                        preview: line.slice(tab + 1)
                    })
                }
                clipSvc.clipItems = out
                if (clipSvc.panelOpen) clipSvc.makeClipThumbs()
            }
        }
    }

    Process { id: clipAct }

    function clipCopy(id) {
        if (clipNativeOn) { clipSvc.nativeItem.clipCopy(id); clipSvc.copied(); return }
        clipAct.command = ["sh", "-c",
            "cliphist decode " + id + " | wl-copy"]
        clipAct.running = true
        clipSvc.copied()                     // the shell closes the panels
    }

    function clipDelete(id) {
        if (clipNativeOn) { clipSvc.nativeItem.clipRemove(id); return }
        clipAct.command = ["sh", "-c",
            "cliphist list | grep -m1 '^" + id + "\t' | cliphist delete"]
        clipAct.running = true
        clipRefresh.restart()
    }

    function clipWipe() {
        if (clipNativeOn) { clipSvc.nativeItem.clipClear(); return }
        clipAct.command = ["sh", "-c", "cliphist wipe"]
        clipAct.running = true
        clipRefresh.restart()
    }

    Timer {
        id: clipRefresh
        interval: 120
        onTriggered: clipSvc.readClipboard()
    }

    function clipImageInfo(preview) {
        const m = (preview || "").match(/^\[\[ binary data (.+?) (png|jpe?g|bmp|webp|gif)(?: (\d+x\d+))? \]\]$/i)
        return m ? { ext: m[2].toLowerCase(), size: m[3] || "", bytes: m[1] } : null
    }
    readonly property string clipThumbDir: clipNativeOn ? clipSvc.nativeItem.clipDir
                                                         : Quickshell.env("HOME") + "/.cache/ether/clip"
    property int clipThumbVer: 0
    function makeClipThumbs() {
        if (clipNativeOn) { clipThumbVer++; return }    // they're files already
        const args = []
        for (const c of clipItems.slice(0, 60)) {
            const info = clipImageInfo(c.preview)
            if (info && /^[0-9]+$/.test(c.id)) args.push(c.id + ":" + info.ext)
        }
        if (!args.length) return
        clipThumbProc.command = ["sh", "-c",
            'd="$HOME/.cache/ether/clip"; mkdir -p "$d"; ' +
            'for x in "$@"; do id=${x%%:*}; ext=${x#*:}; ' +
            '[ -s "$d/$id.$ext" ] || cliphist decode "$id" > "$d/$id.$ext" 2>/dev/null; done',
            "sh"].concat(args)
        clipThumbProc.running = true
    }
    Process {
        id: clipThumbProc
        onExited: clipSvc.clipThumbVer++
    }
}
