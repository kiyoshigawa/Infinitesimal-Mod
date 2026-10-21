-- Theme-owned Full-mode select screen underlay.
-- Reuse Infinitesimal's existing select-music chrome, then attach our own MusicWheel.
--
-- The chrome is loaded by absolute theme path (THEME:GetPathB) rather than a
-- relative LoadActor: a nested relative load from a BGAnimations layer hits a
-- stack-depth bug in ResolveRelativePath. The chrome calls setenv("IsBasicMode", false)
-- and sorts the engine wheel only if one exists.

local t = LoadActor(THEME:GetPathB("ScreenSelectMusic", "underlay"))

-- The chrome above clears InfinitesimalPreviewScreen (the stock select screen shares
-- it and must not mount the chart preview). Re-set it after that load so the preview
-- mounts on this screen only.
InfinitesimalPreviewScreen = true

t[#t+1] = LoadActor("MusicWheel") .. { Name = "MusicWheel" }

return t
