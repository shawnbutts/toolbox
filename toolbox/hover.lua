-- Toolbox: hover.lua
-- Hover pop-ups: resting the pointer on a "trigger" window pops up a detail window
-- after Toolbox.Hover.SHOW_DELAY seconds. The pop-up stays while the pointer is over
-- either window (so its buttons can be used) and closes Toolbox.Hover.HIDE_DELAY
-- seconds after the pointer has left both.
--
-- Several elements of each window report hover (the window and its sections) because
-- the docs don't say whether moving onto a child counts as leaving the parent.
-- "Hovering" means any reported key is over; the delays absorb flicker between them.
-- Keys starting "t:" come from the trigger window, "p:" from the pop-up.

local Hover = {}
Toolbox.Hover = Hover

Hover.SHOW_DELAY = 0.5   -- passing over the trigger on the way elsewhere does nothing
Hover.HIDE_DELAY = 0.75  -- time to cross from the trigger to the pop-up

local Controller = {}
Controller.__index = Controller

-- opts = {
--   name     = "xp",            -- unique; names the one-shot timers
--   enabled  = function() -> bool,    -- player setting
--   trigger  = function() -> bool,    -- is the trigger window shown
--   popup    = { IsShown, IsPopup, ShowPopup, HidePopup },   -- the detail window's functions
-- }
function Hover.New(opts)
  local self = setmetatable({ opts = opts, hovered = {}, pending = false }, Controller)
  self.showTimer = "toolbox_hover_show_" .. opts.name
  self.hideTimer = "toolbox_hover_hide_" .. opts.name
  return self
end

function Controller:Any(prefix)
  for key in pairs(self.hovered) do
    if not prefix or key:sub(1, #prefix) == prefix then return true end
  end
  return false
end

function Controller:OnShowTimer()
  self.pending = false
  local o = self.opts
  if o.enabled() and o.trigger() and self:Any("t:") then o.popup.ShowPopup() end
end

function Controller:OnHideTimer()
  if not self:Any() then self.opts.popup.HidePopup() end
end

function Controller:Update()
  local o = self.opts
  if self:Any() then
    ShroudRemovePeriodic(self.hideTimer)
    -- Registering the same name again restarts it, so start it only once per hover.
    if o.enabled() and self:Any("t:") and not o.popup.IsShown() and not self.pending then
      self.pending = true
      ShroudRegisterPeriodic(self.showTimer, function() self:OnShowTimer() end, Hover.SHOW_DELAY, false)
    end
  else
    ShroudRemovePeriodic(self.showTimer)
    self.pending = false
    if o.popup.IsPopup() then
      ShroudRegisterPeriodic(self.hideTimer, function() self:OnHideTimer() end, Hover.HIDE_DELAY, false)
    end
  end
end

-- A hover report: key is "t:<element>" or "p:<element>", over is true/false.
function Controller:Report(key, over)
  self.hovered[key] = over and true or nil
  self:Update()
end

-- Forgets keys starting with prefix: a window closed under the pointer reports no
-- "left" event we can rely on.
function Controller:Clear(prefix)
  for key in pairs(self.hovered) do
    if key:sub(1, #prefix) == prefix then self.hovered[key] = nil end
  end
  self:Update()
end

-- Hover was turned off: stop a pending pop-up and close an open one.
function Controller:Cancel()
  ShroudRemovePeriodic(self.showTimer)
  self.pending = false
  self.opts.popup.HidePopup()
end
