-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- HP EliteBook 830 G5: 13.3" 1920x1080 panel (290x170 mm, ~166 PPI).
-- Native 1x: 1920x1080 logical, pixel-exact everywhere.
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Built-in display at its native 120 Hz mode.
hl.monitor({ output = "eDP-1", mode = "1920x1080@120.02", position = "0x0", scale = omarchy_monitor_scale })

-- Anything plugged in (HDMI/DisplayPort): native mode, placed to the right, normal size.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
