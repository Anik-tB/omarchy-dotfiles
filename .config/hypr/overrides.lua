-- Anik command overrides.
-- Omarchy puts /usr/share/omarchy/bin first on PATH (default/hypr/envs.lua), so
-- a stock omarchy-* command can only be replaced from a folder placed ahead of
-- it. Only deliberate replacements live in ~/.local/share/anik-overrides/bin
-- (currently: omarchy-screensaver -> Anik screensaver animation). Delete a file
-- there to get Omarchy's version back.
local dir = os.getenv("HOME") .. "/.local/share/anik-overrides/bin"
local kept = {}
for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  if entry ~= dir then table.insert(kept, entry) end
end
table.insert(kept, 1, dir)
hl.env("PATH", table.concat(kept, ":"))
