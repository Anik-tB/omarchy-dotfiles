-- Type-to-search: when nothing is focused (empty workspace / bare desktop),
-- typing a letter or digit opens the Omarchy menu with what you typed in its
-- search box. The binds only exist while no window is focused and no
-- interactive layer (menu, launcher, panels, pickers...) is open, so normal
-- typing is untouched.
--
-- Flow: the first key starts ~/.local/bin/type-to-search, which opens the menu.
-- Until the helper has handed the text over, the binds stay on and every key
-- (letters, digits, Space, Backspace, Enter) goes into `buffer`, so fast typing
-- loses nothing. The helper copies the buffer into the menu with setFilter and
-- calls finish(); finish() turns the binds off only when no new key arrived in
-- the meantime, so from then on keys go straight to the menu, in order.
--
-- Crash-safety (Hyprland 0.56.2 segfaulted in CLuaKeybind::push):
--   * No HL.Keybind / HL.Timer handles are kept. Binds are added with hl.bind
--     and removed with hl.unbind(key) by name, so nothing can go stale.
--   * Bind callbacks never bind or unbind; that only happens from timers,
--     events and the helper's hyprctl eval calls.
--   * Every config load bumps a global generation; callbacks from an older
--     load see a mismatch and do nothing.

local CHARS = {}
for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):gmatch(".") do CHARS[c] = c:lower() end
local KEYS = { "SPACE", "BACKSPACE", "RETURN" }
for c in pairs(CHARS) do table.insert(KEYS, c) end

local PASSIVE = { "background", "bar", "notif", "osd", "wallpaper", "cava" }
local function is_passive(ns)
  ns = ns or ""
  for _, p in ipairs(PASSIVE) do
    if ns:find(p, 1, true) then return true end
  end
  return false
end

_G.__tts_gen = (_G.__tts_gen or 0) + 1
local GEN = _G.__tts_gen
local function stale() return _G.__tts_gen ~= GEN end

local HELPER = os.getenv("HOME") .. "/.local/bin/type-to-search"
local PENDING_TIMEOUT = 3000 -- ms; give up if the menu never shows up

local enabled = false
local pending = false -- helper started, text not handed over yet
local pending_id = 0
local buffer = ""
local enter = false
local seq = 0
-- Right after a window closes (e.g. Super+W on the last terminal) the key that
-- closed it can still reach these binds once the desktop is empty. Ignore keys
-- for a moment after any close (or move away) so that W never starts a search.
local CLOSE_COOLDOWN = 500 -- ms
local cooldown_id = 0
local cooling = false

-- Clear anything a previous load may have left behind.
for _, k in ipairs(KEYS) do pcall(hl.unbind, k) end

-- Layers that always take the keyboard, matched by name as a backup in case a
-- Hyprland update renames/removes the `interactivity` field.
local KEYBOARD_LAYERS = { ["omarchy-menu"] = true }

local function interactive_layer_open()
  for _, l in ipairs(hl.get_layers()) do
    if l.mapped ~= false and not is_passive(l.namespace) then
      if KEYBOARD_LAYERS[l.namespace or ""] or (tonumber(l.interactivity) or 0) > 0 then return true end
    end
  end
  return false
end

local function desired()
  if pending then return true end
  return hl.get_active_window() == nil and not interactive_layer_open()
end

local on_key

local function set_enabled(on)
  if stale() or enabled == on then return end
  enabled = on
  for _, k in ipairs(KEYS) do
    if on then
      hl.bind(k, function() on_key(k) end, { description = "Type to search" })
    else
      pcall(hl.unbind, k)
    end
  end
end

on_key = function(k)
  if stale() then return end
  if cooling and not pending then return end
  local ch = CHARS[k]
  if ch then
    buffer = buffer .. ch
    if not pending then
      pending, enter = true, false
      pending_id = pending_id + 1
      local my = pending_id
      hl.exec_cmd(HELPER)
      hl.timer(function()
        if stale() or not pending or my ~= pending_id then return end
        pending, buffer, enter = false, "", false
        set_enabled(desired())
      end, { timeout = PENDING_TIMEOUT, type = "oneshot" })
    end
  elseif pending then
    if k == "SPACE" then buffer = buffer .. " "
    elseif k == "BACKSPACE" then buffer = buffer:sub(1, -2)
    elseif k == "RETURN" then enter = true end
  end
  -- Space/Backspace/Enter with no search running are swallowed
  -- (nothing is focused, so nothing would have received them anyway).
end

-- Debounced: only the most recently scheduled check acts.
local function schedule(delay)
  seq = seq + 1
  local my = seq
  hl.timer(function()
    if stale() or my ~= seq then return end
    set_enabled(desired())
  end, { timeout = math.max(delay or 60, 1), type = "oneshot" })
end

for _, ev in ipairs({ "window.active", "window.open", "window.close", "window.destroy",
                      "window.move_to_workspace", "workspace.active",
                      "layer.opened", "layer.closed" }) do
  hl.on(ev, function() if not stale() then schedule() end end)
end

for _, ev in ipairs({ "window.close", "window.destroy", "window.move_to_workspace" }) do
  hl.on(ev, function()
    if stale() then return end
    cooling = true
    cooldown_id = cooldown_id + 1
    local my = cooldown_id
    hl.timer(function()
      if stale() or my ~= cooldown_id then return end
      cooling = false
    end, { timeout = CLOSE_COOLDOWN, type = "oneshot" })
  end)
end

-- An interactive layer took the keyboard: get out of its way at once
-- (unless it is the menu we are filling right now).
hl.on("layer.opened", function(layer)
  if stale() or pending or is_passive(layer.namespace) then return end
  set_enabled(false)
end)

schedule()

-- Called by the helper through `hyprctl eval`. Results come back through
-- error() because that is the only way hyprctl eval prints a value.
type_to_search = {
  buffer = function() return stale() and "" or buffer end,
  -- The helper has put `text` into the menu (nil = the menu failed to open).
  -- Hand over only if nothing new was typed since it read the buffer;
  -- otherwise it must run another round.
  finish = function(text)
    if stale() or not pending then return "done" end
    if text ~= nil and text ~= buffer then return "more" end
    local was_enter = enter and text ~= nil
    pending, buffer, enter = false, "", false
    set_enabled(desired())
    return was_enter and "done-enter" or "done"
  end,
  update = function() schedule() end,
  state = function()
    return "gen=" .. GEN .. " enabled=" .. tostring(enabled) .. " pending=" .. tostring(pending)
      .. " buffer=[" .. buffer .. "] layer=" .. tostring(interactive_layer_open())
      .. " win=" .. tostring(hl.get_active_window())
  end,
}
