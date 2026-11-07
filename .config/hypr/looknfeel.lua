-- Omarchy / Hyprland
-- HP EliteBook 830 G5 | Intel UHD 620 | 16 GB RAM
-- Goal: smooth, responsive, battery-conscious

hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 4,
        border_size = 2,
        resize_on_border = true,
        -- The theme's full-strength gradient: violet → butterfly blue → orchid,
        -- matching the bar, popups and notification borders.
        col = {
            active_border = { colors = { "rgba(a08ae6ee)", "rgba(7d95f5ee)", "rgba(c29af0ee)" }, angle = 45 },
        },
        -- layout = "scrolling",
    },

    decoration = {
        --rounding = 12,

        dim_inactive = true,
        dim_strength = 0.06,
        active_opacity = 1.0,
        inactive_opacity = 1.0,

        shadow = { enabled = false },
        -- Blur is on only for the bar (see the layer rule at the end); every
        -- window opts out below, so windows cost nothing extra. xray blurs just
        -- the static wallpaper behind the bar, which is cached rather than
        -- recomputed every frame.
        blur = {
            enabled = true,
            size = 7,
            passes = 2,
            xray = true,
            vibrancy = 0.25,
            noise = 0.015,
        },
    },

    misc = {
        disable_hyprland_logo = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        focus_on_activate = false,
    },

    render = {
        direct_scanout = 2,
    },

    cursor = {
        inactive_timeout = 3,
        hide_on_key_press = true,
    },

    input = {
        follow_mouse = 1,
        repeat_rate = 40,
        repeat_delay = 250,

        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.5,
            disable_while_typing = true,
        },
    },
})

-- Quick start, smooth finish
hl.curve("easeOutQuint", {
    type = "bezier",
    points = { { 0.22, 1.00 }, { 0.36, 1.00 } },
})

-- Smooth fades
hl.curve("smoothFade", {
    type = "bezier",
    points = { { 0.25, 0.10 }, { 0.25, 1.00 } },
})

-- Linear curve for quick closing
hl.curve("linear", {
    type = "bezier",
    points = { { 0.00, 0.00 }, { 1.00, 1.00 } },
})

-- Window animations
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3,
    bezier = "easeOutQuint",
    style = "popin 90%",
})

hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.5,
    bezier = "linear",
    style = "popin 90%",
})

hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "easeOutQuint",
})

-- Fades and focus changes
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 2,
    bezier = "smoothFade",
})

hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 1.5,
    bezier = "smoothFade",
})

hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 1.2,
    bezier = "linear",
})

hl.animation({
    leaf = "fadeDim",
    enabled = true,
    speed = 2,
    bezier = "smoothFade",
})

-- Launcher and popup layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.5,
    bezier = "easeOutQuint",
    style = "fade",
})

hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.2,
    bezier = "linear",
    style = "fade",
})

hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 1.5,
    bezier = "smoothFade",
})

hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.2,
    bezier = "linear",
})

-- Active border transition
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 2,
    bezier = "smoothFade",
})

hl.animation({
    leaf = "borderangle",
    enabled = false,
})

-- Workspace transitions
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 2.5,
    bezier = "easeOutQuint",
    style = "slidefade 10%",
})

hl.animation({
    leaf = "specialWorkspace",
    enabled = true,
    speed = 2.5,
    bezier = "easeOutQuint",
    style = "slidefadevert 12%",
})

-- Frosted-glass bar islands: blur behind the Omarchy bar only, never behind
-- windows. ignore_alpha skips the bar's clear strip so only the islands blur.
o.window(".*", { no_blur = true })
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "omarchy-notifications" }, blur = true, ignore_alpha = 0.3 })

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.
