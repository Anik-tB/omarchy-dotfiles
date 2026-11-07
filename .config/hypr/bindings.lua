-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Unbind SUPER+T (was: toggle floating without repositioning)
hl.unbind("SUPER + T")
o.bind("SUPER + T", "Toggle window floating/tiling (centered)", "~/.config/hypr/scripts/toggle-float-center 80 85")

-- Unbind SUPER+O (was: pop window out at fixed 1300x900)
hl.unbind("SUPER + O")
o.bind("SUPER + O", "Pop window out (float & pin, centered)", "~/.config/hypr/scripts/toggle-float-center --pop 50 60")

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end

-- Minimize works on every workspace, not only floating ones; Super+Alt+M
-- brings back the most recently minimized window.
hl.unbind("SUPER + M")
o.bind("SUPER + M", "Minimize window", "~/.config/hypr/scripts/minimize")
o.bind("SUPER + ALT + M", "Restore minimized window", "~/.config/hypr/scripts/unminimize")

-- Pause/resume screen recording (stop stays on ALT + PRINT)
o.bind("CTRL + ALT + PRINT", "Pause/resume screen recording", "anik-screenrecord-pause toggle")
