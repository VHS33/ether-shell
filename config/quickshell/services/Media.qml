pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.common

// Music and video: the player everything controls, every player (for the
// media card's switcher), whether it's playing, the playback position, the
// song's lyrics, and the visualiser's bars.  Use it anywhere as
// Media.player, Media.lyrics, Media.fmtTime(s)... (import qs.services).
//
// The shell tells it which media views are open (drawerOpen, sidebarOpen)
// and whether the native plugin is there (nativeOk): lyrics are fetched,
// and the visualiser's fallback (cava) runs, only while the drawer is open.
//
// Over the network: the song's artist, title, album and length, to
// lrclib.net (a free lyrics database, no account), once per song, only
// while the media drawer is open, and only if lyrics are on in Settings.
Singleton {
    id: mediaSvc

    property bool drawerOpen: false
    property bool sidebarOpen: false
    property bool nativeOk: false

    // The player everything controls: the one picked in the media card
    // if it's still around, else whichever is playing, else the first.
    property string pickedPlayer: ""
    readonly property var player: {
        const list = Mpris.players.values
        if (!list || list.length === 0) return null
        if (pickedPlayer !== "")
            for (const p of list) if (p.dbusName === pickedPlayer) return p
        for (const p of list) {
            if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return list[0]
    }
    // every player, as plain values for the card's switcher
    readonly property var playerList: (Mpris.players.values || []).map(p => ({
        key: p.dbusName, name: p.identity || p.dbusName,
        playing: p.playbackState === MprisPlaybackState.Playing
    }))


    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing

    Timer {
        // the track position: every half second while a media view is
        // open, every second otherwise, for the pill's progress line
        // four times a second while lyrics are following along
        interval: mediaSvc.drawerOpen && mediaSvc.lyricsState === "synced" && mediaSvc.lyricsOn ? 250
                : (mediaSvc.drawerOpen || mediaSvc.sidebarOpen) ? 500 : 1000
        // paused, the position doesn't move: only while playing (or while a
        // media view is open, to follow a seek)
        running: mediaSvc.player !== null
                 && (mediaSvc.player.playbackState === MprisPlaybackState.Playing || mediaSvc.drawerOpen || mediaSvc.sidebarOpen)
        repeat: true; triggeredOnStart: true
        onTriggered: mediaSvc.player?.positionChanged()
    }

    function fmtTime(sec) {
        if (!sec || sec < 0 || !isFinite(sec)) return "0:00"
        const s = Math.floor(sec % 60)
        const m = Math.floor(sec / 60) % 60
        const h = Math.floor(sec / 3600)
        const pad = n => (n < 10 ? "0" + n : "" + n)
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
    }


    // ---- synced lyrics (LRCLIB) -------------------------------------------
    // Fetched from lrclib.net, a free lyrics database with no key, only
    // while the media drawer is open and only once per song.  The artist
    // and title go to curl as arguments, never pasted into a command.
    // lyrics: [{ t: seconds, text }], plain values.
    readonly property bool lyricsOn: Config.cfg.lyricsShown !== false
    property var lyrics: []
    property string lyricsPlain: ""
    property string lyricsState: ""        // loading, synced, plain, none
    property string lyricsKey: ""
    property var lyricsCache: ({})
    readonly property string trackKey: player
        ? (player.trackArtist || "") + "\u0001" + (player.trackTitle || "") : ""
    // the line being sung: the last one that has started
    readonly property int lyricIndex: {
        if (lyricsState !== "synced" || !player) return -1
        const pos = player.position + 0.25
        let lo = 0, hi = lyrics.length - 1, ans = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lyrics[mid].t <= pos) { ans = mid; lo = mid + 1 } else hi = mid - 1
        }
        return ans
    }
    function parseLrc(lrc) {
        const out = []
        for (const line of (lrc || "").split("\n")) {
            const stamps = line.match(/\[(\d+):(\d+(?:\.\d+)?)\]/g)
            if (!stamps) continue
            const text = line.replace(/\[[^\]]*\]/g, "").trim()
            for (const st of stamps) {
                const m = st.match(/\[(\d+):(\d+(?:\.\d+)?)\]/)
                out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: text })
            }
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }
    function showLyrics(entry) {
        lyrics = entry.synced
        lyricsPlain = entry.plain
        lyricsState = entry.synced.length ? "synced" : entry.plain ? "plain" : "none"
    }
    function fetchLyrics() {
        if (!player || trackKey === "" || !lyricsOn) return
        if (trackKey === lyricsKey && lyricsState !== "") return
        lyricsKey = trackKey
        const hit = lyricsCache[trackKey]
        if (hit) { showLyrics(hit); return }
        lyrics = []
        lyricsPlain = ""
        lyricsState = "loading"
        lyricsProc.key = trackKey
        lyricsProc.command = ["sh", "-c",
            'UA="Ether Shell (github.com/VHS33/ether-shell)"; ' +
            'r=$(curl -s --max-time 8 -A "$UA" -G "https://lrclib.net/api/get" ' +
            '--data-urlencode "artist_name=$1" --data-urlencode "track_name=$2" ' +
            '--data-urlencode "album_name=$3" --data-urlencode "duration=$4"); ' +
            'case "$r" in *yncedLyrics*|*lainLyrics*) printf "%s" "$r"; exit 0;; esac; ' +
            'curl -s --max-time 8 -A "$UA" -G "https://lrclib.net/api/search" ' +
            '--data-urlencode "track_name=$2" --data-urlencode "artist_name=$1"',
            "sh", player.trackArtist || "", player.trackTitle || "", player.trackAlbum || "",
            String(Math.round(player.length || 0))]
        lyricsProc.running = true
    }
    Process {
        id: lyricsProc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let entry = { synced: [], plain: "" }
                try {
                    let j = JSON.parse(text)
                    // the search gives a list: prefer one with timings
                    if (Array.isArray(j)) j = j.find(x => x && x.syncedLyrics) || j.find(x => x && x.plainLyrics) || {}
                    entry = { synced: mediaSvc.parseLrc(j.syncedLyrics || ""), plain: (j.plainLyrics || "").trim() }
                } catch (e) {}
                const c = Object.assign({}, mediaSvc.lyricsCache)
                c[lyricsProc.key] = entry
                const keys = Object.keys(c)
                if (keys.length > 40) delete c[keys[0]]
                mediaSvc.lyricsCache = c
                if (lyricsProc.key === mediaSvc.lyricsKey) mediaSvc.showLyrics(entry)
            }
        }
    }
    // a new song, or the media drawer opening: fetch (once) after a beat
    onTrackKeyChanged: lyricsLater.restart()
    function fetchLyricsSoon() { lyricsLater.restart() }
    Timer {
        id: lyricsLater
        interval: 400
        onTriggered: if (mediaSvc.drawerOpen) mediaSvc.fetchLyrics()
    }


    // cava spectrum, 28 bars of 0-100; only runs while the media card is
    // open so nothing is burning CPU in the background
    property var cavaBars: new Array(28).fill(0)
    Process {
        id: cavaProc
        // the native reader does this when the plugin is installed
        running: mediaSvc.drawerOpen && !mediaSvc.nativeOk
        command: ["cava", "-p", Quickshell.env("HOME")
                  + "/.config/cava/quickshell.conf"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const out = []
                for (let i = 0; i < 28; i++) {
                    const v = parseInt(parts[i])
                    out.push(isNaN(v) ? 0 : v)
                }
                mediaSvc.cavaBars = out
            }
        }
        onRunningChanged: {
            if (!running) mediaSvc.cavaBars = new Array(28).fill(0)
        }
    }
}
