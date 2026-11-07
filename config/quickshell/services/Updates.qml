pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Updates: is there a newer Ether Shell, and are there system package
// updates (pacman, and the AUR through paru or yay)?  Use it anywhere as
// Updates.check(), Updates.shellState... (import qs.services).
//
// Only when you ask (Settings > About > Check now, or "Check for updates"
// in the launcher's commands); nothing goes online on its own.
// Over the network, only then: the VERSION file of Ether Shell on GitHub
// (raw.githubusercontent.com), your package mirrors (checkupdates, which
// needs pacman-contrib, works on a copy of the package lists, so nothing on
// the system changes), and the AUR (paru -Qua or yay -Qua).
Singleton {
    id: up

    // (ETHER_REPO: another copy to look at, as `ether -u` takes it)
    readonly property string repo: Quickshell.env("ETHER_REPO") || "https://github.com/VHS33/ether-shell.git"
    readonly property string versionUrl: {
        const m = repo.match(/^https:\/\/github\.com\/([^/]+\/[^/.]+)/)
        return m ? "https://raw.githubusercontent.com/" + m[1] + "/main/config/quickshell/VERSION" : ""
    }

    // ---- what the last check found ----
    property bool checking: false
    property bool checked: false
    property date checkedAt: new Date(0)
    // Ether Shell: "new" (a newer one is out), "current", "ahead" (yours is
    // newer than GitHub's), "none" (GitHub's copy has no version), "offline"
    readonly property string shellHave: versionFile.text().trim()
    property string shellLatest: ""
    property string shellState: ""
    // packages from your mirrors: "ok", "missing" (no checkupdates), "error"
    property string repoState: ""
    property var repoList: []          // [{ name, from, to }]
    // the AUR: the helper used (paru, yay, or none), "ok" or "error"
    property string aurHelper: ""
    property string aurState: ""
    property var aurList: []
    readonly property int pkgCount: repoList.length + aurList.length

    FileView {
        id: versionFile
        path: Quickshell.shellPath("VERSION")
        blockLoading: true
    }

    // is version a newer than b?  (0.6.10 is newer than 0.6.9)
    function newer(a, b) {
        const pa = String(a).split(/[.\-]/), pb = String(b).split(/[.\-]/)
        for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
            const x = parseInt(pa[i] || "0"), y = parseInt(pb[i] || "0")
            if (isNaN(x) || isNaN(y)) return String(pa[i] || "") > String(pb[i] || "")
            if (x !== y) return x > y
        }
        return false
    }

    function check() {
        if (checking) return
        checking = true
        checkProc.lines = []
        checkProc.running = true
    }

    // the updates run in a terminal: they show what they do, and ask
    // (and pacman wants your password)
    function inTerminal(cmd) {
        Apps.run(Session.termCmd + " -e sh -c '" + cmd
                 + "; echo; printf \"Done. Press Enter to close. \"; read _'")
    }
    function updateShell() { inTerminal("\"$HOME/.local/bin/ether\" -u") }
    function updatePackages() {
        inTerminal(aurHelper !== "" ? aurHelper + " -Syu" : "sudo pacman -Syu")
    }

    Process {
        id: checkProc
        property var lines: []
        command: ["sh", "-c",
            // Ether Shell's newest version: one small file from GitHub
            'if [ -n "$1" ]; then ' +
            '  out=$(timeout 10 curl -fsSL "$1" 2>/dev/null); rc=$?; ' +
            '  if [ "$rc" = 0 ]; then echo "@shell ok $(printf "%s" "$out" | head -1)"; ' +
            '  elif [ "$rc" = 22 ]; then echo "@shell none"; else echo "@shell off"; fi; ' +
            'else echo "@shell off"; fi; ' +
            // packages from the mirrors, without touching the system's lists
            'if command -v checkupdates >/dev/null 2>&1; then ' +
            '  echo "@repo"; timeout 120 checkupdates 2>/dev/null; echo "@repo-end $?"; ' +
            'else echo "@repo-missing"; fi; ' +
            // the AUR, through whichever helper there is
            'for h in paru yay; do ' +
            '  if command -v "$h" >/dev/null 2>&1; then ' +
            '    echo "@aur $h"; timeout 120 "$h" -Qua 2>/dev/null; echo "@aur-end $?"; break; ' +
            '  fi; ' +
            'done; echo "@done"',
            "sh", up.versionUrl]
        // read to the end marker (the exit can come before the last lines)
        stdout: SplitParser {
            onRead: l => {
                if (l === "@done") up.parse(checkProc.lines)
                else checkProc.lines.push(l)
            }
        }
        onExited: if (up.checking) up.parse(checkProc.lines)
    }

    function parse(lines) {
        let sect = "", repo = [], aur = [], repoRc = -1, aurRc = -1, helper = "", shell = "off", latest = ""
        const pkg = l => {
            // "name 1.2-1 -> 1.3-1", with a note after it now and then
            const m = l.trim().match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/)
            return m ? { name: m[1], from: m[2], to: m[3] } : null
        }
        for (const l of lines) {
            if (l.startsWith("@shell ")) {
                const p = l.split(" ")
                shell = p[1]; latest = (p[2] || "").trim()
            } else if (l === "@repo") sect = "repo"
            else if (l.startsWith("@repo-end")) { repoRc = parseInt(l.split(" ")[1]); sect = "" }
            else if (l === "@repo-missing") repoRc = -2
            else if (l.startsWith("@aur ")) { helper = l.split(" ")[1]; sect = "aur" }
            else if (l.startsWith("@aur-end")) { aurRc = parseInt(l.split(" ")[1]); sect = "" }
            else if (sect === "repo") { const p = pkg(l); if (p) repo.push(p) }
            else if (sect === "aur") { const p = pkg(l); if (p) aur.push(p) }
        }
        // Ether Shell
        shellLatest = latest
        if (shell === "ok" && latest !== "") {
            shellState = shellHave === "" || newer(latest, shellHave) ? "new"
                       : latest === shellHave ? "current" : "ahead"
        } else shellState = shell === "none" ? "none" : "offline"
        // the mirrors: checkupdates says 0 with updates, 2 with none, 1 on
        // an error (offline, say)
        repoList = repo
        repoState = repoRc === -2 ? "missing" : repoRc === 0 || repoRc === 2 ? "ok" : "error"
        // the AUR: the helper says 0 with updates, 1 with none
        aurHelper = helper
        aurList = aur
        aurState = helper === "" ? "" : aurRc === 0 || aurRc === 1 ? "ok" : "error"
        checkedAt = new Date()
        checked = true
        checking = false
    }
}
