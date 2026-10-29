pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The machine's readings: CPU, memory, network speed and the GPU (NVIDIA),
// with two minutes of history for the system panel's graphs, the busiest
// processes (only while the system panel is open), uptime, and the About
// page's details.  Use it anywhere as System.cpuPct, System.cpuHist...
// (import qs.services).
//
// Where the numbers come from: the native plugin (NativeStats.qml, which
// writes them here) when it's built; otherwise the two fallback readers
// below, which read /proc and run one nvidia-smi.  The shell tells it
// whether the system panel is open (watchProcesses).  Nothing here goes
// over the network.
Singleton {
    id: sys

    // the system panel is open: read the busiest processes every 2 s
    property bool watchProcesses: false

    property int cpuPct: 0
    property int gpuPct: 0
    property int gpuTemp: 0
    property int gpuMemPct: 0
    property int gpuWatts: 0
    property bool gpuOk: false
    property string gpuVendor: ""           // "nvidia" or "amd": whose card the GPU readings are from

    property string netDown: "0"
    property string netUp: "0"
    property var lastNet: null

    // "0.4 KB/s", "85 KB/s", "1.2 MB/s": always a unit per second
    function fmtRate(bps) {
        const k = bps / 1024
        if (k < 10) return k.toFixed(1) + " KB/s"
        if (k < 1000) return Math.round(k) + " KB/s"
        return (k / 1024).toFixed(1) + " MB/s"
    }

    property int memPct: 0
    property var lastCpu: null

    // ---- stats history, for the system panel's graphs ----------------
    // The last 60 readings of each (two minutes at one every 2 s), as
    // plain numbers.  Sampled on the clock rather than on change, so a
    // flat line is still a line and the graphs keep an even pace.
    property var cpuHist: []
    property var memHist: []
    property var gpuHist: []
    property var tempHist: []
    function recordStats() {
        const push = (a, v) => { const b = a.slice(-59); b.push(v); return b }
        cpuHist = push(cpuHist, cpuPct)
        memHist = push(memHist, memPct)
        if (gpuOk) {
            gpuHist = push(gpuHist, gpuPct)
            tempHist = push(tempHist, gpuTemp)
        }
    }

    // the busiest processes, read only while the system panel is open.
    // What each one is using right now: the CPU time it took between two
    // readings, from /proc/PID/stat.  (Not ps's %CPU, which is an average
    // over a program's whole life: that put ps itself, a moment old, at
    // 300%, and something busy for the last minute low on the list.)
    // A process needs two readings to count, so the reader itself (sh and
    // cat, new each time) never shows up.
    property var topProcs: []
    property var lastTicks: ({})            // pid: CPU ticks at the last reading
    property real lastTicksAt: 0
    onWatchProcessesChanged: if (!watchProcesses) { lastTicks = ({}); lastTicksAt = 0 }
    Process {
        id: procsProc
        // MemTotal, then a line per process
        command: ["sh", "-c", "head -n1 /proc/meminfo; cat /proc/[0-9]*/stat 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now()
                const secs = sys.lastTicksAt > 0 ? (now - sys.lastTicksAt) / 1000 : 0
                const lines = text.split("\n")
                const memKb = parseInt((lines[0].match(/\d+/) || ["0"])[0]) || 0
                const ticks = {}, out = []
                for (let i = 1; i < lines.length; i++) {
                    // "PID (name) state ...": the name can hold spaces and brackets
                    const l = lines[i], open = l.indexOf("("), close = l.lastIndexOf(")")
                    if (open < 0 || close < open) continue
                    const pid = l.substring(0, open).trim()
                    const f = l.substring(close + 2).split(" ")
                    const t = (parseInt(f[11]) || 0) + (parseInt(f[12]) || 0)   // utime + stime
                    ticks[pid] = t
                    const before = sys.lastTicks[pid]
                    if (secs <= 0 || before === undefined || t < before) continue
                    out.push({
                        name: l.substring(open + 1, close),
                        // 100 ticks a second, so ticks per second is % of one core
                        cpu: (t - before) / secs,
                        // resident pages (4 KiB) against all memory
                        mem: memKb > 0 ? (parseInt(f[21]) || 0) * 4 / memKb * 100 : 0
                    })
                }
                const first = secs <= 0
                sys.lastTicks = ticks
                sys.lastTicksAt = now
                if (first) { procsSoon.restart(); return }
                out.sort((a, b) => b.cpu - a.cpu || b.mem - a.mem)
                sys.topProcs = out.slice(0, 5)
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: sys.watchProcesses
        onTriggered: procsProc.running = true
    }
    // the second reading, soon after the first, so the list fills quickly
    Timer { id: procsSoon; interval: 600; onTriggered: if (sys.watchProcesses) procsProc.running = true }

    // ---- system stats -----------------------------------------------------
    // Two long-running readers instead of launching four commands (nine
    // programs) every 2 seconds.  statsProc loops by itself, reading
    // /proc/stat, /proc/meminfo and /proc/net/dev with the shell's own
    // built-ins, so the only thing it starts is `sleep`.  gpuStream is one
    // nvidia-smi in its looping mode, which keeps the driver awake between
    // readings instead of waking it from scratch each time.  If either
    // stops, it's started again a few seconds later.
    Process {
        id: statsProc
        command: ["sh", "-c",
            'while :; do ' +
            '  read -r _ u n s i w q sq st _ < /proc/stat; ' +
            '  t=0; a=0; ' +
            '  while read -r k v _; do case $k in MemTotal:) t=$v;; MemAvailable:) a=$v; break;; esac; done < /proc/meminfo; ' +
            '  rx=0; tx=0; ' +
            '  { read -r _; read -r _; while read -r line; do ' +
            '      name=${line%%:*}; set -- $name; name=$1; [ "$name" = lo ] && continue; ' +
            '      set -- ${line#*:}; rx=$((rx + $1)); tx=$((tx + $9)); ' +
            '    done; } < /proc/net/dev; ' +
            '  echo "S $u $n $s $i $w $q $sq $st $t $a $rx $tx"; ' +
            '  sleep 2; ' +
            'done']
        stdout: SplitParser {
            onRead: line => {
                const f = line.trim().split(/\s+/)
                if (f[0] !== "S" || f.length < 13) return
                const v = f.slice(1).map(Number)
                // cpu: busy share of the time since the last reading
                const total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7]
                const idle = v[3] + v[4]
                if (sys.lastCpu) {
                    const dt = total - sys.lastCpu.total, di = idle - sys.lastCpu.idle
                    if (dt > 0) sys.cpuPct = Math.round(100 * (dt - di) / dt)
                }
                sys.lastCpu = { total: total, idle: idle }
                // memory in use
                if (v[8] > 0) sys.memPct = Math.round((v[8] - v[9]) * 100 / v[8])
                // network: bytes per second since the last reading
                const now = Date.now()
                if (sys.lastNet) {
                    const secs = (now - sys.lastNet.t) / 1000
                    if (secs > 0) {
                        sys.netDown = sys.fmtRate(Math.max(0, (v[10] - sys.lastNet.rx) / secs))
                        sys.netUp   = sys.fmtRate(Math.max(0, (v[11] - sys.lastNet.tx) / secs))
                    }
                }
                sys.lastNet = { rx: v[10], tx: v[11], t: now }
                sys.recordStats()
            }
        }
        onExited: statsRestart.restart()
    }
    Timer { id: statsRestart; interval: 3000; onTriggered: statsProc.running = true }

    Process {
        id: gpuStream
        // An NVIDIA card: nvidia-smi.  Otherwise an AMD one (the amdgpu
        // driver; the one with the most video memory), read from /sys with
        // the shell's own built-ins every 2 s, in nvidia-smi's layout: busy %,
        // temperature, memory used and total, watts.  A card that's asleep
        // (a laptop's, unused) is left asleep.
        command: ["sh", "-c",
            "if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then echo vendor=nvidia; " +
            "exec nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw " +
            "--format=csv,noheader,nounits -lms 2000 2>/dev/null; fi; " +
            'd=; bv=-1; ' +
            'for c in /sys/class/drm/card*; do ' +
            '  case ${c##*/} in *-*) continue;; esac; ' +
            '  case $(readlink "$c/device/driver") in */amdgpu) ;; *) continue;; esac; ' +
            '  [ -r "$c/device/gpu_busy_percent" ] || continue; ' +
            '  v=0; read -r v 2>/dev/null < "$c/device/mem_info_vram_total"; ' +
            '  [ "${v:-0}" -gt "$bv" ] && { d=$c/device; bv=${v:-0}; }; ' +
            'done; ' +
            '[ -n "$d" ] || exit 0; ' +
            'h=; for x in "$d"/hwmon/hwmon*; do [ -d "$x" ] && { h=$x; break; }; done; ' +
            'echo vendor=amd; ' +
            'while :; do ' +
            '  s=; read -r s 2>/dev/null < "$d/power/runtime_status"; ' +
            '  if [ "$s" = suspended ]; then echo "0, , , , 0"; else ' +
            '    b=; t=; w=; u=; vt=; ' +
            '    read -r b 2>/dev/null < "$d/gpu_busy_percent"; ' +
            '    if [ -n "$h" ]; then ' +
            '      read -r t 2>/dev/null < "$h/temp1_input"; ' +
            '      read -r w 2>/dev/null < "$h/power1_average" || read -r w 2>/dev/null < "$h/power1_input"; ' +
            '    fi; ' +
            '    read -r u 2>/dev/null < "$d/mem_info_vram_used"; read -r vt 2>/dev/null < "$d/mem_info_vram_total"; ' +
            '    echo "$b, ${t:+$((t / 1000))}, $u, $vt, ${w:+$((w / 1000000))}"; ' +
            '  fi; ' +
            '  sleep 2; ' +
            'done']
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("vendor=")) { sys.gpuVendor = line.slice(7).trim(); return }
                const p = line.split(",").map(x => parseFloat(x.trim()))
                if (p.length < 5 || isNaN(p[0])) return
                sys.gpuPct = Math.round(p[0])
                if (!isNaN(p[1])) sys.gpuTemp = Math.round(p[1])
                if (!isNaN(p[2]) && p[3] > 0) sys.gpuMemPct = Math.round(100 * p[2] / p[3])
                if (!isNaN(p[4])) sys.gpuWatts = Math.round(p[4])
                sys.gpuOk = true
            }
        }
        // no card it can read, or the driver went away: try again in a while
        onExited: { sys.gpuOk = false; gpuRestart.restart() }
    }
    Timer { id: gpuRestart; interval: 15000; onTriggered: gpuStream.running = true }

    function startFallbackReaders() {
        statsProc.running = true
        gpuStream.running = true
    }

    // ---- about -------------------------------------------------------
    // one snapshot of the machine, taken when Settings > About opens
    property var aboutInfo: ({})
    Process {
        id: aboutProc
        command: ["sh", "-c",
            'echo "host=$(cat /etc/hostname 2>/dev/null)"; '
            + '. /etc/os-release 2>/dev/null; echo "os=$PRETTY_NAME"; '
            + 'echo "kernel=$(uname -r)"; '
            + 'echo "cpu=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed "s/^ *//")"; '
            + 'echo "cores=$(nproc)"; '
            + 'g=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1); '
            // an AMD card: its own name if it gives one, else the PCI name (when
            // lspci is there), else just AMD; the one with the most video memory
            + 'if [ -z "$g" ]; then bv=-1; for c in /sys/class/drm/card*; do '
            + '  case ${c##*/} in *-*) continue;; esac; '
            + '  case $(readlink "$c/device/driver") in */amdgpu) ;; *) continue;; esac; '
            + '  v=0; read -r v 2>/dev/null < "$c/device/mem_info_vram_total"; [ "${v:-0}" -gt "$bv" ] || continue; bv=${v:-0}; '
            + '  n=; read -r n 2>/dev/null < "$c/device/product_name"; '
            + '  [ -z "$n" ] && command -v lspci >/dev/null && n=$(lspci -vmm -s "$(basename "$(readlink -f "$c/device")")" 2>/dev/null | sed -n "s/^Device:[[:space:]]*//p" | head -1); '
            + '  g="${n:-AMD graphics}, amdgpu"; '
            + 'done; fi; echo "gpu=$g"; '
            + 'echo "ram=$(( ($(awk \'/MemTotal/ {print $2}\' /proc/meminfo) + 524288) / 1048576 )) GB"; '
            + 'echo "uptime=$(uptime -p | sed "s/^up //")"; '
            + 'echo "hyprland=$(hyprctl version -j 2>/dev/null | grep -m1 \"tag\" | cut -d\\\" -f4)"; '
            + 'echo "quickshell=$(qs --version 2>/dev/null | head -1)"; '
            + 'echo "shell=$(basename "$SHELL")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                sys.aboutInfo = o
            }
        }
    }
    function refreshAbout() { aboutProc.running = true }

    // ---- uptime, for the power menu and the system panel ----
    property string uptimeText: ""
    function refreshUptime() { upProc.running = true }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: upProc.running = true
    }
    Process {
        id: upProc
        command: ["uptime", "-p"]
        stdout: StdioCollector { onStreamFinished: sys.uptimeText = text.trim() }
    }
}
