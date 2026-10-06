-- Theme-owned Full-mode select screen underlay.
-- Reuse Infinitesimal's existing select-music chrome, then attach our own MusicWheel.
--
-- The chrome is loaded by relative path (resolves from BGAnimations/, same as the
-- theme's existing LoadActor("../HudPanels")). It calls setenv("IsBasicMode", false)
-- and ChangeSort()s the engine wheel only if one exists.

local t = LoadActor("../ScreenSelectMusic underlay/default")

t[#t+1] = LoadActor("MusicWheel") .. { Name = "MusicWheel" }

return t
