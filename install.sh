#!/usr/bin/env bash
# ============================================================
#   Ether Shell installer
#
#   curl -fsSL https://raw.githubusercontent.com/VHS33/ether-shell/main/install.sh | bash
#
#   ./install.sh              install everything
#   ./install.sh --dry-run    show what would happen, change nothing
#   ./install.sh --no-packages  skip package installation
#   ./install.sh --yes        don't ask before installing packages
#
#   Needs an Arch-based system (Arch, EndeavourOS, CachyOS, ...) and
#   Hyprland 0.55 or newer, which uses a Lua config.
#   Anything it replaces is moved to ~/.config/ether-backup-<time>/.
# ============================================================
set -euo pipefail

# Where the repo is.  When piped from curl there's no file, so this falls
# back to the current folder, and the check below fetches the repo.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    HERE="$(cd "$(dirname "$SELF")" && pwd)"
else
    HERE="$(pwd)"
fi
REPO_URL="https://github.com/VHS33/ether-shell.git"
DRY=0; PKGS=1; YES=0
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY=1 ;;
        --no-packages) PKGS=0 ;;
        --yes|-y)      YES=1 ;;
        -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $a (try --help)"; exit 1 ;;
    esac
done

# true when there's a terminal to ask questions on (it may look readable
# yet fail to open, e.g. under automation)
has_tty() { { : < /dev/tty; } 2>/dev/null; }

# ---- run from curl: fetch the repo, then run the installer inside it ----
# Keyboard input comes from the terminal from here on: piped into bash,
# the script itself is what stdin reads.
if [ ! -d "$HERE/config/quickshell" ]; then
    SRC="${ETHER_DIR:-$HOME/.local/share/ether-shell}"
    echo
    echo "Fetching Ether Shell into $SRC"
    if ! command -v git >/dev/null; then
        echo "git isn't installed; installing it first."
        sudo pacman -S --needed --noconfirm git
    fi
    if [ -d "$SRC/.git" ]; then
        git -C "$SRC" pull --ff-only
    else
        mkdir -p "$(dirname "$SRC")"
        git clone --depth 1 "$REPO_URL" "$SRC"
    fi
    if has_tty; then
        exec bash "$SRC/install.sh" "$@" < /dev/tty
    else
        exec bash "$SRC/install.sh" "$@"
    fi
fi

# ---- output ----------------------------------------------------
if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
else B=; D=; G=; Y=; R=; N=; fi
step() { printf '\n%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %swarning:%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
run()  {
    if [ "$DRY" = 1 ]; then printf '    %s[dry run]%s %s\n' "$D" "$N" "$*"
    else "$@"; fi
}

# ---- banner ------------------------------------------------------
# ETHER SHELL in block letters, the two words stacked (on one line it's too
# wide for many terminals), shaded from teal to violet down the lines when
# the terminal has colour.
banner() {
    local lines=(
        "███████╗████████╗██╗  ██╗███████╗██████╗"
        "██╔════╝╚══██╔══╝██║  ██║██╔════╝██╔══██╗"
        "█████╗     ██║   ███████║█████╗  ██████╔╝"
        "██╔══╝     ██║   ██╔══██║██╔══╝  ██╔══██╗"
        "███████╗   ██║   ██║  ██║███████╗██║  ██║"
        "╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
        "███████╗██╗  ██╗███████╗██╗     ██╗"
        "██╔════╝██║  ██║██╔════╝██║     ██║"
        "███████╗███████║█████╗  ██║     ██║"
        "╚════██║██╔══██║██╔══╝  ██║     ██║"
        "███████║██║  ██║███████╗███████╗███████╗"
        "╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝"
    )
    # teal -> violet, one shade per line
    local colours=("94;226;213" "103;216;215" "111;205;217" "120;195;219" "129;185;221" "138;174;223" "146;164;225" "155;153;227" "164;143;229" "173;133;231" "181;122;233" "190;112;235")
    local i
    echo
    for i in "${!lines[@]}"; do
        if [ -t 1 ]; then
            printf '   \e[38;2;%sm%s\e[0m\n' "${colours[$i]}" "${lines[$i]}"
        else
            printf '   %s\n' "${lines[$i]}"
        fi
    done
    printf '\n   %sa Hyprland desktop, built on Quickshell%s\n' "$D" "$N"
}
banner
[ "$DRY" = 1 ] && info "${Y}Dry run: nothing will be changed.${N}"

# ---- checks ----------------------------------------------------
step "Checking the system"
[ "$(id -u)" -eq 0 ] && die "Run this as your normal user, not root. It asks for sudo when it needs it."
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi
case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*) info "Arch-based system: ${PRETTY_NAME:-unknown}" ;;
    *) [ -f /etc/arch-release ] && info "Arch-based system" \
         || die "This installer is for Arch-based systems (Arch, EndeavourOS, CachyOS...)." ;;
esac
command -v pacman >/dev/null || die "pacman not found."

# ---- packages ----------------------------------------------------
# Everything the shell and its scripts call.  Each is installed from the
# official repos when it's there, otherwise from the AUR.
PACKAGES=(
    # desktop
    hyprland hyprlock hypridle hyprsunset xdg-desktop-portal-hyprland polkit-kde-agent
    # file pickers for apps that use portals (Firefox, Flatpaks), as Hyprland recommends
    xdg-desktop-portal-gtk
    # the shell
    quickshell qt6-base qt6-declarative qt6-wayland qt6-svg
    # WebP (and other) images for the wallpaper selector and clipboard thumbnails
    qt6-imageformats
    # theming
    matugen awww adw-gtk-theme papirus-icon-theme breeze-icons glib2 plasma-integration
    # UWSM: the systemd-managed session ("Hyprland (uwsm-managed)" at login)
    uwsm
    # fonts: Inter for words, Material Symbols for icons, JetBrains Mono for
    # the terminal, Noto as a fallback
    noto-fonts ttf-jetbrains-mono-nerd inter-font ttf-material-symbols-variable
    # emoji, for the launcher's emoji search and in notifications
    noto-fonts-emoji
    # apps the shell opens
    kitty rofi dolphin btop pavucontrol nm-connection-editor
    # sound and media
    pipewire wireplumber pipewire-pulse libpulse playerctl cava
    # screenshots and clipboard
    grim slurp wl-clipboard cliphist
    # copying text from the screen (SUPER + SHIFT + T)
    tesseract tesseract-data-eng
    # brightness
    ddcutil brightnessctl
    # system
    networkmanager libnotify xdg-utils curl git python coreutils util-linux procps-ng dbus
    # Bluetooth, for quick settings (harmless without an adapter)
    bluez bluez-utils
    # the sound a finished timer plays
    sound-theme-freedesktop
    # building the native plugin (Ether.Native); wayland for its clipboard
    # (wayland-scanner and the headers), pipewire's library for the visualiser
    cmake base-devel wayland libpipewire
)

if [ "$PKGS" = 1 ]; then
    step "Working out which packages are needed"
    missing=()
    for p in "${PACKAGES[@]}"; do
        # satisfied by anything installed that provides it: an AUR or -git
        # version someone already has counts, instead of being replaced
        # (which pacman would stop on, as the two conflict)
        pacman -T "$p" >/dev/null 2>&1 && continue
        missing+=("$p")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        info "Everything is already installed."
    else
        repo=(); aur=()
        for p in "${missing[@]}"; do
            if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p"); else aur+=("$p"); fi
        done
        [ ${#repo[@]} -gt 0 ] && info "From the official repos: ${repo[*]}"
        [ ${#aur[@]} -gt 0 ]  && info "From the AUR: ${aur[*]}"

        if [ "$YES" = 0 ] && [ "$DRY" = 0 ]; then
            if has_tty; then
                read -r -p "    Install these now? [Y/n] " ans < /dev/tty
            else
                ans=y
            fi
            case "${ans:-y}" in [Yy]*) ;; *) die "Stopped. Re-run with --no-packages to skip this step." ;; esac
        fi

        [ ${#repo[@]} -gt 0 ] && run sudo pacman -S --needed --noconfirm "${repo[@]}"

        if [ ${#aur[@]} -gt 0 ]; then
            helper=""
            for h in paru yay; do command -v "$h" >/dev/null && { helper="$h"; break; }; done
            if [ -z "$helper" ]; then
                info "No AUR helper found; installing yay first."
                run sudo pacman -S --needed --noconfirm git base-devel
                if [ "$DRY" = 0 ]; then
                    tmp="$(mktemp -d)"
                    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
                    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
                    rm -rf "$tmp"
                else
                    info "[dry run] would build yay-bin from the AUR"
                fi
                helper=yay
            fi
            run "$helper" -S --needed --noconfirm "${aur[@]}"
        fi
    fi
else
    step "Skipping packages (--no-packages)"
fi

# ---- Hyprland version ----------------------------------------------
if command -v Hyprland >/dev/null; then
    hv="$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -n "$hv" ]; then
        maj="${hv%%.*}"; rest="${hv#*.}"; min="${rest%%.*}"
        if [ "$maj" -eq 0 ] && [ "$min" -lt 55 ]; then
            warn "Hyprland $hv found. Ether Shell's config is Lua, which needs 0.55 or newer."
        else
            info "Hyprland $hv"
        fi
    fi
fi

# ---- back up and copy -------------------------------------------------
BACKUP="$HOME/.config/ether-backup-$(date +%Y%m%d-%H%M%S)"
backed=0
place() {  # place <source> <destination>
    local src="$1" dst="$2"
    if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
        local rel="${dst#"$HOME"/}"
        run mkdir -p "$BACKUP/$(dirname "$rel")"
        run cp -a "$dst" "$BACKUP/$rel"
        backed=$((backed + 1))
    fi
    run mkdir -p "$(dirname "$dst")"
    run cp "$src" "$dst"
}

step "Installing configs"
# A Quickshell service of its own (from another setup) would start a second
# copy of the shell in every UWSM session, where the graphical session target
# runs: two bars, everything twice.  Ether Shell starts itself, so one like
# that is moved aside (renamed .off, not deleted) and its link removed.
qsu="$HOME/.config/systemd/user"
if [ -f "$qsu/quickshell.service" ]; then
    info "Moving aside a quickshell.service from another setup (it would start the shell twice): $qsu/quickshell.service.off"
    if [ "$DRY" = 0 ]; then
        systemctl --user disable --now quickshell.service >/dev/null 2>&1 || true
        mv "$qsu/quickshell.service" "$qsu/quickshell.service.off"
        find "$qsu" -name quickshell.service -type l -delete 2>/dev/null
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
fi
# your kitty shell (fish, zsh...) set in an existing kitty.conf: kept, in
# user.conf, which the new kitty.conf reads last and updates never touch
kc="$HOME/.config/kitty/kitty.conf"
if [ -f "$kc" ] && [ ! -e "$HOME/.config/kitty/user.conf" ] && grep -qE '^[[:space:]]*shell[[:space:]]' "$kc"; then
    info "Keeping your kitty shell setting (in ~/.config/kitty/user.conf)"
    if [ "$DRY" = 0 ]; then
        mkdir -p "$HOME/.config/kitty"
        { echo "# your own kitty settings: read last, never touched by updates"
          grep -E '^[[:space:]]*shell[[:space:]]' "$kc"; } > "$HOME/.config/kitty/user.conf"
    fi
fi
while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/config/}"
    # written by the Settings panel: only a starting point, never
    # overwritten on a re-install so nobody's choices get reset
    case "$rel" in
        hypr/hyprlock-settings.conf|hypr/hypridle.conf|kitty/shell-settings.conf|uwsm/env|uwsm/env-hyprland)
            [ -e "$HOME/.config/$rel" ] && continue ;;
    esac
    place "$f" "$HOME/.config/$rel"
done < <(find "$HERE/config" -type f -print0)

while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/local/}"
    place "$f" "$HOME/.local/$rel"
done < <(find "$HERE/local" -type f -print0)
run chmod +x "$HOME/.local/bin/setwall" "$HOME/.local/bin/restore-wall" "$HOME/.local/bin/shot" "$HOME/.local/bin/ether-shell" \
    "$HOME/.local/bin/ocr" "$HOME/.local/bin/ether-login" "$HOME/.config/ether-greeter/start"

if [ "$backed" -gt 0 ]; then
    info "Replaced $backed existing file(s); the old versions are in $BACKUP"
else
    info "Nothing needed backing up."
fi

# ---- the native plugin ---------------------------------------------
# Ether.Native: CPU, memory, network and GPU readings, and the visualiser,
# in C++ (native/).  Optional: if it can't be built, the shell uses its own
# readers, so a failure here only costs a little efficiency.
step "Building the native plugin"
qmldir="$HOME/.local/lib/ether-shell/qml"
if command -v cmake >/dev/null 2>&1 && command -v c++ >/dev/null 2>&1; then
    nb="$(mktemp -d)"
    if run cmake -S "$HERE/native" -B "$nb" -DCMAKE_BUILD_TYPE=Release -DETHER_QML_DIR="$qmldir" >/dev/null \
            && run cmake --build "$nb" -j"$(nproc)" >/dev/null \
            && run cmake --install "$nb" >/dev/null; then
        info "Built and installed to $qmldir"
    else
        warn "The native plugin didn't build. Ether Shell works without it, just a little less efficiently."
    fi
    rm -rf "$nb"
else
    warn "cmake or a C++ compiler is missing, so the native plugin wasn't built. Ether Shell works without it."
fi

step "Wallpapers and folders"
run mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/screenshots"
for w in "$HERE"/wallpapers/*; do
    [ -e "$HOME/Pictures/wallpapers/$(basename "$w")" ] || run cp "$w" "$HOME/Pictures/wallpapers/"
done
info "Three Ether Shell wallpapers are in ~/Pictures/wallpapers. Add your own there too."

# ---- one-time system setup ------------------------------------------
step "System setup"

# brightness for external monitors, through DDC/CI
if [ ! -f /etc/modules-load.d/i2c-dev.conf ]; then
    info "Loading i2c-dev at boot, for monitor brightness"
    run sudo sh -c 'echo i2c-dev > /etc/modules-load.d/i2c-dev.conf'
fi
run sudo modprobe i2c-dev || warn "Couldn't load i2c-dev now; it will load on the next boot."

# notifications belong to the shell: stop other daemons claiming them
if pacman -Q mako >/dev/null 2>&1; then
    warn "mako is installed. It can take notifications away from the shell."
    info "Remove it with: sudo pacman -Rns mako"
fi
info "Other notification daemons are blocked from auto-starting (~/.local/share/dbus-1/services)."

# Bluetooth: the service has to be running for quick settings' Bluetooth tile
if systemctl list-unit-files bluetooth.service >/dev/null 2>&1 \
        && ! systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
    info "Turning on the Bluetooth service, for quick settings"
    run sudo systemctl enable --now bluetooth.service || warn "Couldn't start Bluetooth; the tile stays hidden until it runs."
fi

# networking: Ether Shell talks to NetworkManager.  It isn't switched on here, in
# case this system uses something else to get online.
if ! systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
    warn "NetworkManager isn't running, so the Wi-Fi tile and network speeds won't show."
    info "If nothing else manages your network, turn it on with: sudo systemctl enable --now NetworkManager"
fi

# folders matugen writes themes into, so it needn't create them itself
run mkdir -p "$HOME/.cache/ether" "$HOME/.config/btop/themes"

# btop: use the wallpaper's colours (the theme matugen writes)
bt="$HOME/.config/btop/btop.conf"
if [ "$DRY" = 0 ]; then
    mkdir -p "$HOME/.config/btop"
    if [ -f "$bt" ] && grep -q '^color_theme' "$bt"; then
        sed -i 's|^color_theme.*|color_theme = "ether"|' "$bt"
    else
        printf 'color_theme = "ether"\n' >> "$bt"
    fi
    # the Ether Shell feel, for anything not already set: see-through (the
    # terminal's glass shows), rounded corners, smooth graphs, 1 s updates
    for kv in 'theme_background = False' 'rounded_corners = True' \
              'graph_symbol = "braille"' 'update_ms = 1000' 'truecolor = True'; do
        grep -q "^${kv%% *} " "$bt" || printf '%s\n' "$kv" >> "$bt"
    done
fi

# ~/.local/bin on PATH for fish, bash and zsh users
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "\$HOME/.local/bin isn't on your PATH. Hyprland's binds use full paths, so they still work." ;;
esac

# GTK: dark by default; Settings > Theme switches it
if command -v gsettings >/dev/null && [ "$DRY" = 0 ]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme    'adw-gtk3-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme   'Papirus-Dark' 2>/dev/null || true
    info "GTK set to dark with Papirus icons."
fi

# ---- first theme ----------------------------------------------------
step "First theme"
first="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f -iname 'ether-*' 2>/dev/null | sort | head -1 || true)"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -n "$first" ]; then
    info "Generating colours from $(basename "$first")"
    run "$HOME/.local/bin/setwall" "$first" < /dev/null || warn "setwall failed; run it after logging in."
    run hyprctl reload >/dev/null || true
else
    info "Not inside Hyprland right now, so this waits until you log in."
    info "After logging in, run:  setwall ~/Pictures/wallpapers/ether-nightfall.jpg"
fi

# ---- done ------------------------------------------------------------
cat << DONE

${G}${B}Ether Shell is installed.${N}

  Next:
  1. Log in to Hyprland (or restart it) if you aren't in it already.
  2. Open Settings: SUPER + comma (or click the clock, then the gear).
     - Weather: search for your city.
     - Displays: pick your main monitor and set modes.
  3. Press SUPER + / to see every keybind.

  To undo, copy the files back from:
    ${BACKUP}
DONE
