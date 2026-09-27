import QtQuick
import Ether.Native

// ============================================================
//   NATIVE READERS  (the Ether.Native C++ plugin)
//   Loaded by shell.qml.  When the plugin is installed, this takes over:
//   CPU, memory and network straight from /proc, the GPU through NVIDIA's
//   own library (no nvidia-smi running alongside), and the visualiser's
//   bars from cava's binary output.  When it isn't, this file fails to
//   load and the shell starts its own readers instead.
// ============================================================
Item {
    id: nat
    property var app: null
    property string home: ""               // set by the shell

    SystemStats {
        running: nat.app !== null
        // slower while a game runs: the bar is hidden behind it anyway
        interval: nat.app && nat.app.gameRunning ? 10000 : 2000
        onUpdated: {
            const a = nat.app
            a.cpuPct = cpuPct
            a.memPct = memPct
            a.netDown = a.fmtRate(netDownBps)
            a.netUp = a.fmtRate(netUpBps)
            a.gpuOk = gpuOk
            if (gpuOk) {
                a.gpuPct = gpuPct
                a.gpuTemp = gpuTemp
                a.gpuMemPct = gpuMemPct
                a.gpuWatts = gpuWatts
            }
            a.recordStats()
        }
    }

    // colours from the current song's album art
    ArtColors {
        id: art
        source: nat.app && nat.app.player ? (nat.app.player.trackArtUrl || "") : ""
        dark: nat.app ? nat.app.darkTheme : true
        onColorsChanged: {
            const a = nat.app
            if (!a) return
            a.artValid = valid
            if (valid) {
                a.artAccent = accent
                a.artOnAccent = onAccent
                a.artContainer = container
                a.artOnContainer = onContainer
            }
        }
    }

    // the wallpaper: how light it looks (automatic light or dark), which
    // colour style suits it (automatic style), and its calm places (widgets)
    ArtColors {
        id: wallArt
        source: nat.app ? (nat.app.currentWall || "") : ""
        onAnalyzed: if (nat.app && lightness >= 0)
            nat.app.wallMeasured(lightness, suggestedScheme, colourfulness,
                                 smartSeed.valid ? smartSeed.toString() : "",
                                 smartSecond.valid ? smartSecond.toString() : "", smartWhy, source,
                                 smartThird.valid ? smartThird.toString() : "")
    }
    // any wallpaper, measured for its swatches (its own light or dark and style)
    ArtColors {
        id: probeArt
        onAnalyzed: if (nat.app && source !== "")
            nat.app.paletteProbed(source, lightness, suggestedScheme, smartSeed.valid ? smartSeed.toString() : "",
                                  smartSecond.valid ? smartSecond.toString() : "", smartWhy,
                                  smartThird.valid ? smartThird.toString() : "")
    }
    function probe(path) {
        probeArt.source = ""             // the same file again still gets measured
        probeArt.source = path
    }
    // the clipboard history, straight from the compositor
    ClipboardHistory {
        id: clipHist
        persist: nat.app ? nat.app.cfg.clipPersist !== false : true
    }
    readonly property bool clipAvailable: clipHist.available
    readonly property var clipItems: clipHist.items
    readonly property string clipDir: clipHist.directory
    function clipCopy(id) { clipHist.copy(id) }
    function clipRemove(id) { clipHist.remove(id) }
    function clipClear() { clipHist.clear() }

    // monitor brightness over DDC/CI, without running ddcutil each time
    Ddc {
        id: ddc
        onRead: (bus, percent) => { if (nat.app) nat.app.ddcGotBrightness(bus, percent) }
        onFailed: bus => { if (nat.app) nat.app.ddcFailed(bus) }
    }
    function ddcGet(bus) { ddc.get(bus) }
    function ddcSet(bus, percent) { ddc.set(bus, percent) }

    // file search for the launcher: built at start-up, kept live
    FileIndex {
        id: fileIdx
        enabled: nat.app ? nat.app.cfg.fileSearch !== false : false
        query: nat.app ? nat.app.fileQuery : ""
        limit: nat.app ? nat.app.fileLimit : 8
    }
    readonly property var fileResults: fileIdx.results
    readonly property string fileResultsFor: fileIdx.resultsFor
    readonly property int fileCount: fileIdx.count
    function calmSpots(sizes, w, h, top, bottom, margin) {
        return wallArt.calmSpots(sizes, w, h, top, bottom, margin)
    }

    // The visualiser, only while the media drawer is open: straight from
    // PipeWire (what the speakers play), in this process.  cava only if
    // PipeWire can't be reached (or the plugin was built without it).
    AudioBars {
        id: bars
        running: nat.app !== null && nat.app.cardShown && available
        bars: 28
        onValuesChanged: if (nat.app && available) nat.app.cavaBars = values
    }
    CavaReader {
        running: nat.app !== null && nat.app.cardShown && !bars.available
        config: nat.home + "/.config/cava/quickshell-bin.conf"
        bars: 28
        onValuesChanged: if (nat.app && !bars.available) nat.app.cavaBars = values
    }
}
