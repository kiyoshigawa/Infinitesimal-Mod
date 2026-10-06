-- Theme-owned Full-mode select screen overlay: reuse the existing overlay actors
-- (GroupSelect, OptionsList, HudPanels, CornerArrows, player-join handling),
-- then add our own "chart locked" corner indicators.
local t = LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay"))

t[#t+1] = LoadActor("LockIndicator")

return t
