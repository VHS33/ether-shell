#!/usr/bin/env bash
# ============================================================
#   Æther installer
#
#   ./install.sh              install everything
#   ./install.sh --dry-run    show what would happen, change nothing
#   ./install.sh --no-packages  skip package installation
#   ./install.sh --yes        don't ask before installing packages
#
#   Needs an Arch-based system (Arch, EndeavourOS, CachyOS, ...) and
#   Hyprland 0.55 or newer, which uses a Lua config.
#   Anything it replaces is moved to ~/.config/aether-backup-<time>/.
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; PKGS=1; YES=0
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY=1 ;;
        --no-packages) PKGS=0 ;;
        --yes|-y)      YES=1 ;;
        -h|--help)     sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $a (try --help)"; exit 1 ;;
    esac
done

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
# ÆTHER in block letters, the Æ drawn by hand (font generators don't have
# it), shaded from teal to violet down the lines when the terminal has
# colour.
banner() {
    local lines=(
        " ███████████╗ ████████╗██╗  ██╗███████╗██████╗ "
        "██╔══██╔════╝ ╚══██╔══╝██║  ██║██╔════╝██╔══██╗"
        "██████████╗      ██║   ███████║█████╗  ██████╔╝"
        "██╔══██╔══╝      ██║   ██╔══██║██╔══╝  ██╔══██╗"
        "██║  ███████╗    ██║   ██║  ██║███████╗██║  ██║"
        "╚═╝  ╚══════╝    ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    )
    # teal -> violet, one shade per line
    local colours=("94;226;213" "110;200;226" "128;176;235" "148;152;240" "170;130;240" "190;112;235")
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
    # the shell
    quickshell qt6-declarative qt6-wayland qt6-svg
    # theming
    matugen-bin awww adw-gtk-theme papirus-icon-theme glib2 plasma-integration
    # fonts
    noto-fonts ttf-jetbrains-mono-nerd
    # apps the shell opens
    kitty rofi dolphin btop pavucontrol nm-connection-editor
    # sound and media
    pipewire wireplumber pipewire-pulse libpulse playerctl cava
    # screenshots and clipboard
    grim slurp wl-clipboard cliphist
    # brightness
    ddcutil brightnessctl
    # system
    networkmanager libnotify xdg-utils curl python coreutils util-linux procps-ng dbus
)

if [ "$PKGS" = 1 ]; then
    step "Working out which packages are needed"
    missing=()
    for p in "${PACKAGES[@]}"; do
        pacman -Q "$p" >/dev/null 2>&1 && continue
        # matugen-bin provides matugen; accept either
        [ "$p" = matugen-bin ] && pacman -Q matugen >/dev/null 2>&1 && continue
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
            read -r -p "    Install these now? [Y/n] " ans
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
            warn "Hyprland $hv found. Æther's config is Lua, which needs 0.55 or newer."
        else
            info "Hyprland $hv"
        fi
    fi
fi

# ---- back up and copy -------------------------------------------------
BACKUP="$HOME/.config/aether-backup-$(date +%Y%m%d-%H%M%S)"
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
while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/config/}"
    # written by the Settings panel: only a starting point, never
    # overwritten on a re-install so nobody's choices get reset
    case "$rel" in
        hypr/hyprlock-settings.conf|hypr/hypridle.conf|kitty/shell-settings.conf)
            [ -e "$HOME/.config/$rel" ] && continue ;;
    esac
    place "$f" "$HOME/.config/$rel"
done < <(find "$HERE/config" -type f -print0)

while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/local/}"
    place "$f" "$HOME/.local/$rel"
done < <(find "$HERE/local" -type f -print0)
run chmod +x "$HOME/.local/bin/setwall" "$HOME/.local/bin/restore-wall" "$HOME/.local/bin/shot"

if [ "$backed" -gt 0 ]; then
    info "Replaced $backed existing file(s); the old versions are in $BACKUP"
else
    info "Nothing needed backing up."
fi

step "Wallpapers and folders"
run mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/screenshots"
for w in "$HERE"/wallpapers/*; do
    [ -e "$HOME/Pictures/wallpapers/$(basename "$w")" ] || run cp "$w" "$HOME/Pictures/wallpapers/"
done
info "Three Æther wallpapers are in ~/Pictures/wallpapers. Add your own there too."

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
first="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f -iname 'aether-*' 2>/dev/null | sort | head -1 || true)"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -n "$first" ]; then
    info "Generating colours from $(basename "$first")"
    run "$HOME/.local/bin/setwall" "$first" < /dev/null || warn "setwall failed; run it after logging in."
    run hyprctl reload >/dev/null || true
else
    info "Not inside Hyprland right now, so this waits until you log in."
    info "After logging in, run:  setwall ~/Pictures/wallpapers/aether-nightfall.jpg"
fi

# ---- done ------------------------------------------------------------
cat << DONE

${G}${B}Æther is installed.${N}

  Next:
  1. Log in to Hyprland (or restart it) if you aren't in it already.
  2. Open Settings: click the clock, then the gear.
     - Weather: search for your city.
     - Displays: pick your main monitor and set modes.
  3. Press SUPER + / to see every keybind.

  To undo, copy the files back from:
    ${BACKUP}
DONE
