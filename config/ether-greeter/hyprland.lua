-- /etc/ether-greeter/hyprland.lua  (Ether Shell)
-- Hyprland for the login screen only.  It runs as greetd's own user, shows
-- Ether Shell's login screen (greeter.qml) on every monitor, and exits once
-- someone has signed in, so their own session can start.

hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        -- greetd doesn't hand start-hyprland what it expects; nothing is wrong
        disable_watchdog_warning = true,
    },
    animations = { enabled = false },
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    decoration = { rounding = 0 },
})

-- the login screen; when it closes (someone signed in), Hyprland does too
hl.on("hyprland.start", function()
    hl.exec_cmd([[sh -c 'quickshell -p /etc/ether-greeter/greeter.qml >"${XDG_RUNTIME_DIR:-/tmp}/ether-greeter.log" 2>&1; hyprctl dispatch "hl.dsp.exit()"']])
end)
