-- Chart preview shell: one persistent ActorFrameTexture per enabled player, plus one
-- NoteField per (player, StepsType), created once and then reused.
--
-- The AFT (and the Sprite that shows it) are created once when the screen loads and
-- are never destroyed, so the texture is never re-registered and a stale texture
-- cannot be displayed.
--
-- One field per StepsType is what keeps chart-type crossings cheap: creating a field
-- costs 120-570 ms (cold noteskin), while switching between pre-created fields is a
-- visibility swap plus a reload on the selected one (a few tens of milliseconds).
-- Fields are pre-created hidden by EnsureTypes as soon as the highlighted song's
-- chart types are known, i.e. at the wheel, before the difficulty stage is opened;
-- crossing between chart types then never creates anything.
--
-- A field whose columns no longer match the engine style aborts in
-- ReceptorArrowRow::DrawPrimitives, which is why a field is never reused across
-- StepsTypes and why BuildChart hides the preview before ChartDisplay switches style.
--
-- BuildChart is invoked from SongPreview's poll (a tween), never from a message
-- handler: mutating actors inside a broadcast segfaults the engine.
--
-- Note field layout borrowed from Mr. ThatKid and Sudospective

local PlayerPos = GAMESTATE:GetNumPlayersEnabled() == 1 and "OnePlayerTwoSides" or "TwoPlayersTwoSides"
local AFTWidth = GAMESTATE:GetNumPlayersEnabled() == 1 and 640 or 320

local AFTs = {}
local Fields = {}    -- pn -> StepsType string -> NoteField actor
local FieldSkin = {} -- pn -> StepsType string -> preferred noteskin it was built with

local function FieldName(stype)
	return "PreviewField_" .. stype
end

local function PrefSkin(pn)
	local pnNoteField = PlayerNumber:Reverse()[pn]
	return GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions("ModsLevel_Preferred"):NoteSkin()
end

local function NeedsField(pn, stype, skin)
	local field = Fields[pn] and Fields[pn][stype]
	return not field or not FieldSkin[pn] or FieldSkin[pn][stype] ~= skin
end

-- Create (and build) the field for one (player, StepsType). Left hidden; BuildChart
-- reveals whichever field matches the selected chart.
local function CreateField(pn, AFT, stype, Steps, skin, withData)
	local name = FieldName(stype)
	AFT:RemoveChild(name)
	InfinitesimalPreviewFieldPN = pn
	InfinitesimalPreviewFieldKey = stype
	AFT:AddChildFromPath(THEME:GetPathB("", "PreviewField"))
	local field = AFT:GetChild(name)

	Fields[pn] = Fields[pn] or {}
	FieldSkin[pn] = FieldSkin[pn] or {}
	Fields[pn][stype] = field
	FieldSkin[pn][stype] = skin

	if field then
		field:playcommand("Build", { Steps = Steps, WithData = withData })
		field:visible(false)
	end
	return field
end

local t = Def.ActorFrame {
	Name = "PreviewNotefield",

	-- Pre-create hidden fields for the chart types present in the highlighted song.
	-- params.Types is { [StepsType string] = Steps } used only to build the columns
	-- and noteskin; the selected chart is loaded later by BuildChart.
	EnsureTypesCommand=function(self, params)
		local types = params and params.Types
		if not types then return end
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local AFT = AFTs[pn]
			if AFT then
				local skin = PrefSkin(pn)
				for stype, Steps in pairs(types) do
					if ChartEligibility.IsAllowed(Steps) and NeedsField(pn, stype, skin) then
						CreateField(pn, AFT, stype, Steps, skin, false)
					end
				end
			end
		end
	end,

	BuildChartCommand=function(self)
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local AFT = AFTs[pn]
			local Steps = GAMESTATE:GetCurrentSteps(pn)
			if AFT then
				if Steps and ChartEligibility.IsAllowed(Steps) then
					local stype = ChartEligibility.TypeKey(Steps)
					local skin = PrefSkin(pn)

					if NeedsField(pn, stype, skin) then
						CreateField(pn, AFT, stype, Steps, skin, true)
					else
						Fields[pn][stype]:playcommand("Build", { Steps = Steps, WithData = true })
					end

					-- Show only the field that matches the selected chart's StepsType.
					for otherType, field in pairs(Fields[pn]) do
						if field then field:visible(otherType == stype) end
					end
				else
					-- Rejected or missing: hide everything this side owns.
					for _, field in pairs(Fields[pn] or {}) do
						if field then field:visible(false) end
					end
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
