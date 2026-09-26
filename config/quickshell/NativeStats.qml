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

    // how light the wallpaper looks, for automatic light or dark
    ArtColors {
        source: nat.app ? (nat.app.currentWall || "") : ""
        onAnalyzed: if (nat.app && lightness >= 0) nat.app.wallMeasured(lightness)
    }

    // only while the media drawer is open, as before
    CavaReader {
        running: nat.app !== null && nat.app.cardShown
        config: nat.home + "/.config/cava/quickshell-bin.conf"
        bars: 28
        onValuesChanged: if (nat.app) nat.app.cavaBars = values
    }
}
