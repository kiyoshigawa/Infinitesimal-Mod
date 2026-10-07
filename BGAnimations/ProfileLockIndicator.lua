-- Profile-select "locked" indicator, one per player, at the bottom corners.
--
-- Profile-screen-specific: driven by the custom ProfileLocked / ProfileUnlocked
-- messages this screen broadcasts, so it never touches the music wheel's own
-- lock indicator (StepsChosen / StepsUnchosen). Same corner positions as
-- CornerArrows, so the gold glow lands on the SHIFT arrow the player sees.
--
-- The GlowShift* artwork is the same SHIFT arrow as the base one, just with a
-- halo, so it must be tinted to read as "locked".

local LockColor = { 1, 0.82, 0.25 } -- warm gold

local function LockArrow(pn, texture, x)
	return Def.Sprite {
		Texture=THEME:GetPathG("", texture),
		InitCommand=function(self)
			self:xy(x, SCREEN_BOTTOM - 72):zoom(0.5):blend('add')
			:diffuse(LockColor[1], LockColor[2], LockColor[3], 1):diffusealpha(0)
		end,

		ProfileLockedMessageCommand=function(self, params)
			if params and params.Player == pn then
				-- Quick flash, then settle to a steady lit state.
				self:stoptweening():diffusealpha(1):linear(0.4):diffusealpha(0.9)
			end
		end,

		ProfileUnlockedMessageCommand=function(self, params)
			-- No Player = unglow both sides.
			if not params or not params.Player or params.Player == pn then
				self:stoptweening():linear(0.15):diffusealpha(0)
			end
		end,
	}
end

return Def.ActorFrame {
	LockArrow(PLAYER_1, "CornerArrows/GlowShiftDL", 72),
	LockArrow(PLAYER_2, "CornerArrows/GlowShiftDR", SCREEN_RIGHT - 72),
}
