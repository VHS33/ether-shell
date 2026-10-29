#!/usr/bin/env bash
# ============================================================
#   Installs Ether Shell for real and checks what it did.
#   GitHub runs it on a clean Arch machine on every push
#   (.github/workflows/checks.yml); it runs on your own machine too,
#   in a throwaway home, but it does install packages there.
#
#   tests/install-test.sh fresh     a first install: every file in place,
#                                   scripts runnable, the version recorded,
#                                   ether -d answering
#   tests/install-test.sh again     installing the same again changes nothing
#   tests/install-test.sh upgrade   the release before this one, then an
#                                   update to this one: your settings kept,
#                                   anything replaced backed up; and ether -u
#                                   never going back to an older version
#   tests/install-test.sh start     the shell starts on a test desktop (sway,
#                                   headless) with no load errors; its
#                                   warnings are listed, and a screenshot kept
#
#   Logs and the screenshot go in $ETHER_TEST_OUT (/tmp/ether-test).
#   Run as a normal user with sudo, as a real install is.
# ============================================================
# (messages show paths as you would type them, "~" and all)
# shellcheck disable=SC2088
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${ETHER_TEST_OUT:-/tmp/ether-test}"
mkdir -p "$out"
fails=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
note() { printf '  note  %s\n' "$*"; }
version="$(head -1 "$repo/config/quickshell/VERSION" 2>/dev/null)"

# the files the installer puts in place: config/ to ~/.config, local/ to
# ~/.local; the ones that are yours after the first install aren't compared
shipped() {
    (cd "$repo" && find config local -type f | sort) | while IFS= read -r f; do
        case "$f" in
            config/hypr/hypridle.conf|config/kitty/shell-settings.conf|config/uwsm/env|config/uwsm/env-hyprland) continue ;;
        esac
        case "$f" in config/*) echo "$f ${f#config/}" ;; local/*) echo "$f ${f#local/}" ;; esac
    done
}
dest() { case "$1" in config/*) echo "$HOME/.config/${1#config/}" ;; *) echo "$HOME/.local/${1#local/}" ;; esac; }

# every shipped file in place and the same; every script runnable
check_files() {
    local missing=0 differ=0 f
    while read -r f _; do
        d=$(dest "$f")
        if [ ! -e "$d" ]; then missing=$((missing + 1)); [ $missing -le 5 ] && echo "        missing: $d"
        elif ! cmp -s "$repo/$f" "$d"; then differ=$((differ + 1)); [ $differ -le 5 ] && echo "        different: $d"; fi
    done < <(shipped)
    n=$(shipped | wc -l)
    if [ $missing = 0 ] && [ $differ = 0 ]; then ok "all $n files in place"
    else bad "$missing of $n files missing, $differ different"; fi
    local notx=""
    for f in "$repo"/local/bin/*; do
        [ "$(head -c2 "$f")" = "#!" ] || continue
        [ -x "$HOME/.local/bin/$(basename "$f")" ] || notx="$notx $(basename "$f")"
    done
    [ -z "$notx" ] && ok "every script in ~/.local/bin can be run" || bad "not runnable:$notx"
}

check_version() {
    local rec
    rec=$(sed -n 's/^version=//p' "$HOME/.local/state/ether-shell/installed" 2>/dev/null)
    [ "$rec" = "$version" ] && ok "recorded as version $version" || bad "recorded version is '${rec}', not $version"
    [ "$(head -1 "$HOME/.config/quickshell/VERSION" 2>/dev/null)" = "$version" ] \
        && ok "~/.config/quickshell/VERSION says $version" || bad "~/.config/quickshell/VERSION isn't $version"
}

backups() { find "$HOME/.config" -maxdepth 1 -name 'ether-backup-*' 2>/dev/null | wc -l; }

case "${1:-}" in
fresh)
    echo "A first install"
    if bash "$repo/install.sh" --yes --gpu=none > "$out/fresh.log" 2>&1; then ok "install.sh finished"
    else bad "install.sh stopped (exit $?):"; tail -20 "$out/fresh.log"; fi
    # (the installer's own errors stop it, which the line above catches; an
    # error from pacman or a package's setup is noted with what it was about:
    # in a container a hook that needs a running system can fail, harmlessly)
    if grep -q "error:" "$out/fresh.log"; then
        note "pacman or a package's setup reported: $(grep -B2 'error:' "$out/fresh.log" | grep -v '^--$' | sed 's/^ *//' | head -6 | tr '\n' ' ')"
    fi
    w=$(grep -c "warning:" "$out/fresh.log")
    [ "$w" = 0 ] || note "$w warning(s) from the installer: $(grep 'warning:' "$out/fresh.log" | sed 's/^ *//' | head -3 | tr '\n' ' ')"
    check_files
    check_version
    # (-T: anything that provides it counts, an AUR -bin version too)
    for p in quickshell hyprland matugen awww; do pacman -T "$p" >/dev/null 2>&1 || bad "package $p isn't installed"; done
    [ -f "$HOME/.local/lib/ether-shell/qml/Ether/Native/qmldir" ] && ok "the native plugin was built" || bad "the native plugin wasn't built"
    if timeout 90 "$HOME/.local/bin/ether" -d > "$out/doctor.log" 2>&1 || [ $? != 124 ]; then
        grep -q "^Version" "$out/doctor.log" && ok "ether -d answers ($(sed -n '/^Version/{n;p}' "$out/doctor.log" | sed 's/^ *//'))" \
            || bad "ether -d didn't show the version"
    else bad "ether -d took over 90 seconds"; fi
    ;;
again)
    echo "Installing the same again"
    before=$(backups)
    if bash "$repo/install.sh" --yes --gpu=none > "$out/again.log" 2>&1; then ok "install.sh finished"
    else bad "install.sh stopped (exit $?):"; tail -20 "$out/again.log"; fi
    grep -q "Nothing needed backing up" "$out/again.log" && ok "nothing replaced" \
        || bad "it replaced files the first install put there: $(grep 'Replaced' "$out/again.log")"
    [ "$(backups)" = "$before" ] && ok "no backup folder made" || bad "a backup folder was made"
    check_files
    ;;
upgrade)
    echo "Updating from the release before this one"
    # the newest release commit ("v0.5.7: ...") with another version than this
    # one (a fix pushed after a release has the same version, so its release
    # isn't "before"); one from before versions counts as another
    prev=$(git -C "$repo" log --format='%H %s' | awk '$2 ~ /^v[0-9]+\.[0-9]/ {print $1}' \
           | while read -r c; do
                 v=$(git -C "$repo" show "$c:config/quickshell/VERSION" 2>/dev/null | head -1)
                 [ "$v" != "$version" ] && { echo "$c"; break; }
             done)
    if [ -z "$prev" ]; then note "no earlier release in the history (needs the full history: fetch-depth 0)"; exit 0; fi
    echo "  from $(git -C "$repo" log -1 --format='%s' "$prev" | cut -c1-70)"
    old=$(mktemp -d); git -C "$repo" archive "$prev" | tar x -C "$old"
    # a home of its own, so the first install's files don't count
    export HOME; HOME=$(mktemp -d)
    if bash "$old/install.sh" --yes > "$out/upgrade-old.log" 2>&1; then ok "the earlier release installed"
    else bad "the earlier release didn't install (exit $?)"; tail -10 "$out/upgrade-old.log"; fi
    # things that are yours: changed before the update
    printf '{"clock24h": true, "barNet": false}\n' > "$HOME/.config/quickshell/settings.json"
    echo "-- mine" >> "$HOME/.config/hypr/user.lua"
    echo "# mine" >> "$HOME/.config/hypr/hypridle.conf"
    mine=$(cat "$HOME/.config/quickshell/settings.json" "$HOME/.config/hypr/user.lua" | md5sum)
    if bash "$repo/install.sh" --update --yes > "$out/upgrade.log" 2>&1; then ok "the update finished"
    else bad "the update stopped (exit $?):"; tail -20 "$out/upgrade.log"; fi
    [ "$(cat "$HOME/.config/quickshell/settings.json" "$HOME/.config/hypr/user.lua" | md5sum)" = "$mine" ] \
        && ok "your settings and user.lua kept" || bad "your settings or user.lua changed"
    grep -q "^# mine" "$HOME/.config/hypr/hypridle.conf" && ok "your hypridle.conf kept" || bad "your hypridle.conf was replaced"
    grep -q 'lock_cmd.*hyprlock' "$HOME/.config/hypr/hypridle.conf" && bad "hypridle still locks with hyprlock" || ok "idle locking uses the shell's lock screen"
    check_files
    check_version
    changed=$(git -C "$repo" diff --name-only "$prev" HEAD -- config local | while read -r f; do [ -e "$repo/$f" ] && echo "$f"; done | wc -l)
    if [ "$changed" -gt 0 ]; then
        [ "$(backups)" -ge 1 ] && ok "the files it replaced were backed up" || bad "no backup of the replaced files"
    fi
    # ether -u: never backwards.  Copies of this version and the earlier
    # one stand in for GitHub.
    gh=$(mktemp -d)
    git clone -q --bare "$repo" "$gh/now.git" 2>/dev/null
    git -C "$gh/now.git" update-ref refs/heads/main "$(git -C "$repo" rev-parse HEAD)"
    git clone -q --bare "$repo" "$gh/old.git" 2>/dev/null; git -C "$gh/old.git" update-ref refs/heads/main "$prev"
    r=$(ETHER_REPO="$gh/now.git" ETHER_DIR="$HOME/.cache/ether-copy" "$HOME/.local/bin/ether" -u --yes 2>&1)
    echo "$r" | grep -q "Up to date" && ok "ether -u: up to date with this version" || bad "ether -u against this version: $(echo "$r" | tail -1)"
    r=$(ETHER_REPO="$gh/old.git" ETHER_DIR="$HOME/.cache/ether-copy2" "$HOME/.local/bin/ether" -u --yes 2>&1)
    if echo "$r" | grep -qE "Nothing to do|nothing was changed"; then ok "ether -u: won't go back to the earlier release"
    else bad "ether -u against the earlier release: $(echo "$r" | tail -1)"; fi
    # and one with a lower number than this (the earlier release may be from
    # before versions, which stops sooner): the never-backwards check itself
    w=$(mktemp -d); git clone -q "$gh/now.git" "$w/lower" 2>/dev/null
    echo 0.0.1 > "$w/lower/config/quickshell/VERSION"
    git -C "$w/lower" -c user.name=test -c user.email=test@test commit -qam "v0.0.1: lower" \
        && git -C "$w/lower" push -q "$gh/now.git" HEAD:refs/heads/lower 2>/dev/null
    git clone -q --bare "$gh/now.git" "$gh/lower.git" 2>/dev/null
    git -C "$gh/lower.git" update-ref refs/heads/main refs/heads/lower
    r=$(ETHER_REPO="$gh/lower.git" ETHER_DIR="$HOME/.cache/ether-copy3" "$HOME/.local/bin/ether" -u --yes 2>&1)
    echo "$r" | grep -q "Nothing to do" && ok "ether -u: won't install a lower version (0.0.1)" \
        || bad "ether -u against version 0.0.1: $(echo "$r" | tail -1)"
    rm -rf "$w"
    [ "$(head -1 "$HOME/.config/quickshell/VERSION")" = "$version" ] && ok "still $version afterwards" || bad "the version changed to $(head -1 "$HOME/.config/quickshell/VERSION")"
    rm -rf "$old" "$gh"
    ;;
start)
    echo "The shell starts"
    rt=$(mktemp -d); chmod 700 "$rt"; export XDG_RUNTIME_DIR="$rt"
    printf 'output HEADLESS-1 resolution 1920x1080\n' > "$rt/sway.conf"
    # a plain copy of sway: Arch's carries a capability (to raise its own
    # priority) that a container won't run a program with; the copy has none
    sw="${ETHER_SWAY:-}"
    if [ -z "$sw" ]; then cp "$(command -v sway)" "$rt/sway" && sw="$rt/sway"; fi
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
        "$sw" -c "$rt/sway.conf" > "$out/sway.log" 2>&1 &
    sway_pid=$!
    for _ in $(seq 50); do [ -S "$rt/wayland-1" ] && break; sleep 0.2; done
    if [ ! -S "$rt/wayland-1" ]; then bad "the test desktop (sway) didn't start"; tail -5 "$out/sway.log"; exit 1; fi
    # as ether-shell starts it: the native plugin on the import path, and a
    # session bus of its own (notifications, media, the tray need one)
    QML_IMPORT_PATH="$HOME/.local/lib/ether-shell/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"; export QML_IMPORT_PATH
    bus=""; command -v dbus-run-session >/dev/null && bus=dbus-run-session
    WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland \
        $bus ${ETHER_QS:-qs} -p "$HOME/.config/quickshell/shell.qml" > "$out/shell.log" 2>&1 &
    qs_pid=$!
    # (Quickshell's own lines only: "  ERROR: ...", not a driver's VK_ERROR_...)
    plain() { sed 's/\x1b\[[0-9;]*m//g' "$out/shell.log" 2>/dev/null; }
    # The shell's own errors fail it: not loading ("Failed to load
    # configuration", and what caused it), a QML error.  Errors from
    # Quickshell's services ("ERROR quickshell.service.pipewire...") are the
    # test machine lacking a system service (no sound server, no
    # NetworkManager in a container): noted, as a real desktop has them.
    own() { plain | grep -E "^ *ERROR" | grep -vE "^ *ERROR quickshell\."; }
    for _ in $(seq 120); do plain | grep -q "Configuration Loaded" && break; [ -n "$(own)" ] && break; sleep 0.5; done
    sleep 8                                           # let it settle, and anything late show
    if plain | grep -q "Configuration Loaded" && [ -z "$(own)" ]; then ok "it loaded, with no errors of its own"
    else bad "it didn't load:"; plain | grep -E -A3 "^ *ERROR" | grep -vE "^ *ERROR quickshell\." | head -10; fi
    svc=$(plain | grep -E "^ *ERROR quickshell\." | sed 's/^ *ERROR //' | sort -u)
    [ -z "$svc" ] || note "missing on the test machine (fine on a desktop): $(printf '%s\n' "$svc" | cut -d: -f1 | tr '\n' ' ')"
    kill -0 "$qs_pid" 2>/dev/null && ok "still running after 8 seconds" || bad "it stopped (crashed?)"
    WAYLAND_DISPLAY=wayland-1 grim "$out/screen.png" 2>/dev/null && ok "screenshot kept (screen.png)" || note "no screenshot (grim)"
    # its warnings, for a look (the test desktop has no Hyprland, so some are expected)
    plain | grep -E "^ *WARN" | sed 's/^ *//' | sort | uniq -c | sort -rn > "$out/warnings.txt"
    note "$(wc -l < "$out/warnings.txt") different warning(s), listed in warnings.txt"
    kill "$qs_pid" "$sway_pid" 2>/dev/null; wait 2>/dev/null
    ;;
*)
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

echo
[ "$fails" = 0 ] && echo "All right." || echo "$fails problem(s)."
[ "$fails" = 0 ]
