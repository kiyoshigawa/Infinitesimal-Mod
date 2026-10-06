-- "Chart locked" indicator, one per player, at the bottom corners.
--
-- When a player confirms their difficulty, that side's bottom corner arrow is
-- tinted and lit so it is obvious who is locked in versus still choosing.
-- Driven by StepsChosen/StepsUnchosen, which MusicWheel broadcasts with
-- { Player = pn }.
--
-- NOTE: the GlowShift* artwork is the *same* SHIFT arrow as CornerArrows draws,
-- just with a faint halo. Drawing it untinted is invisible, so we recolour it to
-- make the locked state read at a glance.

local LockColor = { 1, 0.82, 0.25 } -- warm gold

local function LockArrow(pn, texture, x)
	return Def.Sprite {
		Texture=THEME:GetPathG("", texture),
		InitCommand=function(self)
			self:xy(x, SCREEN_BOTTOM - 72):zoom(0.5):diffuse(LockColor[1], LockColor[2], LockColor[3], 1):diffusealpha(0)
		end,

		StepsChosenMessageCommand=function(self, params)
			if params.Player == pn then
				-- Quick flash, then settle to a steady lit state.
				self:stoptweening():diffusealpha(1):linear(0.4):diffusealpha(0.9)
			end
		end,

		StepsUnchosenMessageCommand=function(self, params)
			if params.Player == pn then
				self:stoptweening():linear(0.15):diffusealpha(0)
			end
		end,

		-- Safety resets: entering/leaving the difficulty stage starts clean.
		SongChosenMessageCommand=function(self) self:stoptweening():diffusealpha(0) end,
		SongUnchosenMessageCommand=function(self) self:stoptweening():diffusealpha(0) end,
	}
end

return Def.ActorFrame {
	LockArrow(PLAYER_1, "CornerArrows/GlowShiftDL", 72),
	LockArrow(PLAYER_2, "CornerArrows/GlowShiftDR", SCREEN_RIGHT - 72),
}
