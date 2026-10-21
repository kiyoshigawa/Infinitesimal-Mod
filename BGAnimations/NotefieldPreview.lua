-- Chart preview shell: one persistent ActorFrameTexture per enabled player, and one
-- NoteField per player that is reused across chart changes.
--
-- The AFT (and the Sprite that shows it) are created once when the screen loads and
-- are never destroyed, so the texture is never re-registered and a stale texture
-- cannot be displayed.
--
-- The chart itself lives in a separate NoteField actor (BGAnimations/PreviewField.lua).
-- A chart change reloads the existing field, which costs a few tens of milliseconds;
-- the field is only recreated when the StepsType or the preferred noteskin changes,
-- because the column count and the noteskin textures have to change with them, and
-- drawing a field whose columns no longer match the engine style aborts in
-- ReceptorArrowRow::DrawPrimitives.
--
-- BuildChart is invoked from SongPreview's poll (a tween), never from a message
-- handler: mutating actors inside a broadcast segfaults the engine.
--
-- Note field layout borrowed from Mr. ThatKid and Sudospective

local PlayerPos = GAMESTATE:GetNumPlayersEnabled() == 1 and "OnePlayerTwoSides" or "TwoPlayersTwoSides"
local AFTWidth = GAMESTATE:GetNumPlayersEnabled() == 1 and 640 or 320

local AFTs = {}
local Fields = {}
local FieldType = {}
local FieldSkin = {}

local function CreateField(pn, AFT)
	AFT:RemoveChild("PreviewField")
	-- PreviewField.lua reads its player from this global at chunk load.
	InfinitesimalPreviewFieldPN = pn
	AFT:AddChildFromPath(THEME:GetPathB("", "PreviewField"))
	local field = AFT:GetChild("PreviewField")
	Fields[pn] = field
	if field then field:playcommand("Build") end
	return field
end

local t = Def.ActorFrame {
	Name = "PreviewNotefield",

	BuildChartCommand=function(self)
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local AFT = AFTs[pn]
			local Steps = GAMESTATE:GetCurrentSteps(pn)
			if AFT and Steps then
				local pnNoteField = PlayerNumber:Reverse()[pn]
				local stype = ToEnumShortString(Steps:GetStepsType())
				local skin = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions("ModsLevel_Preferred"):NoteSkin()

				if not Fields[pn] or FieldType[pn] ~= stype or FieldSkin[pn] ~= skin then
					CreateField(pn, AFT)
					FieldType[pn] = stype
					FieldSkin[pn] = skin
				else
					Fields[pn]:playcommand("Build")
				end
			end
		end
	end,
}

for i, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	t[#t+1] = Def.ActorFrame {
		Name="Player" .. ToEnumShortString(pn),
		FOV=45,
		InitCommand=function(self)
			self:x((THEME:GetMetric('ScreenGameplay', 'Player' .. ToEnumShortString(pn) .. PlayerPos .. 'X') - SCREEN_CENTER_X) / 1.5)
		end,

		Def.ActorFrameTexture {
			InitCommand=function(self)
				AFTs[pn] = self
				self:SetTextureName("AFT" .. ToEnumShortString(pn))
				self:SetWidth(AFTWidth):SetHeight(480)
				self:EnableAlphaBuffer(true):Create()
			end,
		},

		Def.Sprite {
			Texture="AFT" .. ToEnumShortString(pn),
			InitCommand=function(self)
				self:zoomto(AFTWidth, 480)
			end
		}
	}
end

return t
