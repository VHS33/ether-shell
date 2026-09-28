pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.common

// Notifications: Ether Shell is the notification daemon (the server), and
// this keeps the list (the newest 100, saved to ~/.local/state/ether/
// notifications.json and read back at start-up), the pop-ups, groups by
// app, how many arrived unseen, and the actions (dismiss, clear, a button,
// a typed reply).  Use it anywhere as Notifications.notifList,
// .dismissNotif(id)... (import qs.services).
//
// The shell tells it whether to stay quiet (quiet: do not disturb, or a
// game running), whether the island shows notifications (islandNotifs), and
// whether quick settings or the sidebar is open (panelsOpen: nothing's
// unseen then); it tells the shell when one arrives for the island
// (arrivedForIsland).  Nothing here goes over the network.
Singleton {
    id: ns

    property bool quiet: false
    property bool islandNotifs: true
    property bool panelsOpen: false
    signal arrivedForIsland(var n)

    property var notifList: []
    property var popups: []

    function dismissPopup(id) {
        ns.popups = ns.popups.filter(n => n.id !== id)
    }

    // run one of a notification's buttons ("Reply", "Open", the click
    // action "default", ...) through the live object, then clear it
    function invokeNotifAction(id, key) {
        const obj = ns.notifRefs[id]
        if (obj) {
            try {
                for (const a of (obj.actions || []))
                    if (String(a.identifier) === key) { a.invoke(); break }
            } catch (e) {}
        }
        dismissNotif(id)
    }

    // send a typed reply back to the app that asked for one
    function sendNotifReply(id, text) {
        const obj = ns.notifRefs[id]
        if (obj && text.trim() !== "") {
            try { obj.sendInlineReply(text) } catch (e) {
                console.log("inline reply failed:", e)
            }
        }
        dismissNotif(id)
    }

    property int notifSeq: 0

    // Live Notification objects, keyed by our id.  They must NOT go inside
    // notifList/popups: those arrays are list models, and when the server
    // destroys an expired notification, a model entry still pointing at it
    // makes Qt segfault the next time it builds a delegate from that entry.
    // Model entries hold only plain values; the object is looked up here.
    property var notifRefs: ({})
    readonly property int notifCount: notifList.length

    // ---- grouped by app, and history ------------------------------------
    // Groups are worked out from notifList: { app, icon, items } with the
    // newest group first and each group's newest item first.
    readonly property var notifGroups: {
        const idx = {}, out = []
        for (const n of notifList) {
            const k = n.app || "notification"
            if (idx[k] === undefined) { idx[k] = out.length; out.push({ app: k, items: [] }) }
            out[idx[k]].items.push(n)
        }
        return out
    }
    function dismissGroup(appName) {
        for (const n of notifList.filter(x => (x.app || "notification") === appName)) {
            const obj = notifRefs[n.id]
            if (obj) { try { obj.dismiss() } catch (e) {} }
        }
        notifList = notifList.filter(x => (x.app || "notification") !== appName)
        popups = popups.filter(x => (x.app || "notification") !== appName)
    }
    // when it arrived: the time today, the day before that
    function notifWhen(n) {
        if (!n.ts) return n.when || ""
        const d = new Date(n.ts), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.formatDateTime(d, Config.cfg.clock24h === true ? "HH:mm" : "h:mm AP")
        return Qt.formatDateTime(d, "ddd d")
    }
    // arrived since quick settings or the sidebar was last opened
    property int notifUnseen: 0

    // Saved to ~/.local/state/ether/notifications.json (the newest 100),
    // and read back at startup.  Saved ones come back without their
    // buttons: the app that sent them has moved on.
    property bool notifLoaded: false
    Process {
        running: true
        // (the project was called Aether; its folder is moved across once)
        command: ["sh", "-c", "s=\"$HOME/.local/state\"; " +
            "[ -d \"$s/aether\" ] && [ ! -e \"$s/ether\" ] && mv \"$s/aether\" \"$s/ether\"; " +
            "cat \"$s/ether/notifications.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const saved = JSON.parse(text)
                    if (Array.isArray(saved)) {
                        const old = saved.map(n => Object.assign({}, n, { saved: true, actions: [], replyable: false }))
                        let top = ns.notifSeq
                        for (const n of old) top = Math.max(top, n.id || 0)
                        ns.notifSeq = top
                        ns.notifList = ns.notifList.concat(old).slice(0, 100)
                    }
                } catch (e) {}
                ns.notifLoaded = true
            }
        }
    }
    onNotifListChanged: if (notifLoaded) notifSave.restart()
    Timer {
        id: notifSave
        interval: 800
        onTriggered: {
            notifWrite.command = ["sh", "-c",
                'd="$HOME/.local/state/ether"; mkdir -p "$d"; ' +
                'printf "%s" "$1" > "$d/notifications.json.tmp" && mv "$d/notifications.json.tmp" "$d/notifications.json"',
                "sh", JSON.stringify(ns.notifList.slice(0, 100))]
            notifWrite.running = true
        }
    }
    Process { id: notifWrite }

    function dismissNotif(id) {
        const obj = ns.notifRefs[id]
        if (obj) {
            try { obj.dismiss() } catch (e) {}
        }
        ns.notifList = ns.notifList.filter(n => n.id !== id)
        ns.popups = ns.popups.filter(n => n.id !== id)
    }

    function clearNotifs() {
        for (const k in ns.notifRefs) {
            try { ns.notifRefs[k].dismiss() } catch (e) {}
        }
        ns.notifRefs = ({})
        ns.notifList = []
        ns.popups = []
    }

    NotificationServer {
        id: notifServer

        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: true

        onNotification: notif => {
            notif.tracked = true

            const crit = (notif.urgency === NotificationUrgency.Critical) ? 2 : 1
            // actions are copied out as plain values; the live objects stay
            // behind in notifRefs and are looked up by id when clicked
            const acts = []
            for (const a of (notif.actions || []))
                acts.push({ key: String(a.identifier), text: String(a.text || "") })
            const n = {
                id: ++ns.notifSeq,
                app: notif.appName || "notification",
                icon: notif.appIcon || "",
                desktop: notif.desktopEntry || "",
                summary: notif.summary || "",
                body: notif.body || "",
                urgency: crit,
                image: notif.image || "",
                actions: acts,
                // apps that accept a typed reply (KDE Connect, some chat
                // clients); Discord doesn't offer one
                replyable: notif.hasInlineReply === true,
                replyHint: notif.inlineReplyPlaceholder || "",
                ts: Date.now(),
                when: Qt.formatDateTime(new Date(), Config.cfg.clock24h === true ? "HH:mm" : "h:mm AP")
            }

            const id = n.id
            const refs = ns.notifRefs
            refs[id] = notif
            ns.notifRefs = refs

            // when the server drops it, forget the object immediately so
            // nothing can reach a destroyed pointer through notifRefs
            notif.closed.connect(() => {
                const r = ns.notifRefs
                delete r[id]
                ns.notifRefs = r
            })

            ns.notifList = [n].concat(ns.notifList).slice(0, 100)
            if (!ns.panelsOpen) ns.notifUnseen++
            if (!ns.quiet) {
                // the island shows it; ones with buttons or a reply box still
                // get their pop-up too, since the island has no room for those
                const needsPopup = !ns.islandNotifs || n.replyable
                    || (n.actions || []).some(a => a.key !== "default")
                if (needsPopup) ns.popups = ns.popups.concat([n]).slice(-4)
                if (ns.islandNotifs) ns.arrivedForIsland(n)
            }
        }
    }
}
