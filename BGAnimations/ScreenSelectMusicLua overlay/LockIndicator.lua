-- "Chart locked" indicator, one per player, at the bottom corners.
--
-- StepF2-style cue: when a player confirms their difficulty, that side's bottom
-- corner arrow stays lit (and a sound plays), so it is obvious who is locked in
-- versus still choosing. Driven by StepsChosen/StepsUnchosen, which MusicWheel
-- broadcasts with { Player = pn }.
--
-- Placement mirrors CornerArrows' GlowShiftDL/DR so the lit glow lands on the
-- same spot as the arrow the player is looking at.

local function LockArrow(pn, texture, x)
	return Def.Sprite {
		Texture=THEME:GetPathG("", texture),
		InitCommand=function(self)
			self:xy(x, SCREEN_BOTTOM - 72):zoom(0.5):blend('add'):diffusealpha(0)
		end,

		StepsChosenMessageCommand=function(self, params)
			if params.Player == pn then
				-- Quick flash, then settle to a steady lit state.
				self:stoptweening():diffusealpha(1):linear(0.4):diffusealpha(0.55)
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
