-- When a window is sent somewhere you can't see it (Super+Shift+Alt+<n>,
-- Super+Alt+S to the scratchpad, ...), Hyprland keeps the keyboard on it, so
-- whatever you type next lands in an invisible window. After any move, if the
-- focused window is no longer on a visible workspace, focus the workspace in
-- front of you instead: one of its windows, or nothing if it is empty.
--
-- Dispatching happens from a timer, never inside a bind callback.

_G.__hidden_focus_gen = (_G.__hidden_focus_gen or 0) + 1
local GEN = _G.__hidden_focus_gen
local seq = 0

-- Focusing the workspace you are already on does not drop the focus (Hyprland
-- 0.56), so hop to another normal workspace and straight back in one go; the
-- compositor never draws the in-between state.
-- Workspace objects are live (their fields follow the current state), so copy
-- the names into plain strings before dispatching anything.
local function hop_target(here_name, ws_name)
  if ws_name ~= "" and not ws_name:find("^special") then return ws_name end
  for _, w in ipairs(hl.get_workspaces()) do
    local n = tostring(w.name or "")
    if n ~= "" and n ~= here_name and not n:find("^special") then return n end
  end
  return nil
end

local function check()
  local win = hl.get_active_window()
  local ws = win and win.workspace
  if not ws or ws.visible ~= false then return end
  local here = hl.get_active_workspace()
  local here_name = here and here.name and tostring(here.name) or ""
  local ws_name = tostring(ws.name or "")
  if here_name == "" or here_name == ws_name then return end
  local hop = hop_target(here_name, ws_name)
  if not hop then return end
  hl.dispatch(hl.dsp.focus({ workspace = hop }))
  hl.dispatch(hl.dsp.focus({ workspace = here_name }))
end

hl.on("window.move_to_workspace", function()
  if _G.__hidden_focus_gen ~= GEN then return end
  seq = seq + 1
  local my = seq
  hl.timer(function()
    if _G.__hidden_focus_gen ~= GEN or my ~= seq then return end
    check()
  end, { timeout = 60, type = "oneshot" })
end)
