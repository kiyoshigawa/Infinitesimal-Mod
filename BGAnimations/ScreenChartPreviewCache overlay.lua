-- Session-persistent chart-preview cache.
--
-- Registered as an overlay screen (see [ScreenChartPreviewCache] and OverlayScreens in
-- metrics.ini). Overlay screens are created once when the theme loads and are updated
-- and drawn every frame after the top screen, so the note fields owned here survive
-- screen changes: returning to the song wheel reuses them instead of re-creating them.
--
-- The wheel side (BGAnimations/PreviewCacheClient.lua) displays the render target by
-- name and drives this host through the table published as InfinitesimalPreviewCache:
--   Show() / Hide()  -- visibility only, safe to call from a message handler
--   Build()          -- (re)build the fields for the currently selected charts; this
--                       creates actors, so it must only run from a tween/poll
--   TextureName(pn), TextureWidth(pn)
-- The wheel increments Heartbeat; if it stops (client gone or screen torn down) the
-- watch loop hides the render targets so nothing is captured during gameplay.
--
-- Cost: the first wheel entry of the run creates the render targets and one field per
-- playable StepsType (~0.6-0.9 s). Later entries only reload the selected chart
-- (measured 15-45 ms). A noteskin change recreates the affected field.

local PM = { PLAYER_1, PLAYER_2 }

local HOST_ROOT
local AFTs = {}      -- pn -> { Actor, Width, Texture }
local Fields = {}    -- pn -> { [StepsType] = field }
local FieldSkin = {} -- pn -> { [StepsType] = preferred noteskin it was built with }
local Reps = nil     -- [StepsType] = representative Steps (session cache)
local WantedCache = nil -- { Sides = n, Types = { [type key] = true } }
local LastHeartbeat = 0

local Cache = {
	Host = true,
	WantShown = false, -- set by SetShown; persists across transient hides
	Heartbeat = 0,
	Tick = 0,
}

local function EnabledPlayers()
	local list = {}
	for _, pn in ipairs(PM) do
		if GAMESTATE:IsPlayerEnabled(pn) then list[#list+1] = pn end
	end
	return list
end

local function PrefSkin(pn)
	local pnNoteField = PlayerNumber:Reverse()[pn]
	return GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions("ModsLevel_Preferred"):NoteSkin()
end

-- Chart types that may be previewed for the current number of joined sides. The
-- rule lives in Scripts/01 ChartEligibility.lua; this file only asks it, so the
-- preview can never pre-build a type the difficulty list does not offer.
local function WantedTypes()
	local sides = ChartEligibility.PlayerSides()
	if WantedCache and WantedCache.Sides == sides then
		return WantedCache.Types
	end

	local set = ChartEligibility.AllowedTypes(sides)
	WantedCache = { Sides = sides, Types = set }
	return set
end

-- One representative chart per wanted StepsType, found by a single library pass that
-- stops as soon as every wanted type has been seen. Cached for the session: the
-- representative only exists to build columns and noteskin, never to be displayed.
local function TypeRepresentatives(wanted)
	Reps = Reps or {}
	local missing, count = {}, 0
	for st in pairs(wanted) do
		if not Reps[st] then
			missing[st] = true
			count = count + 1
		end
	end
	if count == 0 then return end

	local found = 0
	for _, song in ipairs(SONGMAN:GetAllSongs()) do
		for _, steps in ipairs(song:GetAllSteps()) do
			local st = ChartEligibility.TypeKey(steps)
			if st and missing[st] and not Reps[st] then
				Reps[st] = steps
				found = found + 1
			end
		end
		if found >= count then break end
	end
end

local function EnsureAFT(pn, width)
	local cur = AFTs[pn]
	if cur and cur.Width == width then return cur end

	-- A width change (player count changed) needs a new render target; the old one is
	-- hidden rather than destroyed. The width is part of the texture name so creating
	-- the replacement can never collide with the superseded texture.
	if cur then cur.Actor:visible(false) end

	local pnShort = ToEnumShortString(pn)
	local suffix = pnShort .. "_" .. tostring(width)
	InfinitesimalPreviewAFTPN = pn
	InfinitesimalPreviewAFTWidth = width
	HOST_ROOT:AddChildFromPath(THEME:GetPathB("", "PreviewCacheAFT"))

	local actor = HOST_ROOT:GetChild("PreviewCacheAFT_" .. suffix)
	local texture = "InfinitesimalPreview" .. suffix

	-- Hold a reference so the render target survives the wheel screen being destroyed
	-- (see PreviewCacheKeeper.lua). Never removed: releasing it early would delete the
	-- texture out from under an AFT that still exists.
	InfinitesimalPreviewKeeperTexture = texture
	HOST_ROOT:AddChildFromPath(THEME:GetPathB("", "PreviewCacheKeeper"))

	AFTs[pn] = {
		Actor = actor,
		Width = width,
		Texture = texture,
	}
	-- Fields live inside the render target, so they do not carry over.
	Fields[pn] = {}
	FieldSkin[pn] = {}
	return AFTs[pn]
end

local function CreateField(pn, stype, Steps, skin)
	local aft = AFTs[pn]
	if not aft or not aft.Actor then return nil end

	local name = "PreviewField_" .. stype
	aft.Actor:RemoveChild(name)
	InfinitesimalPreviewFieldPN = pn
	InfinitesimalPreviewFieldKey = stype
	aft.Actor:AddChildFromPath(THEME:GetPathB("", "PreviewField"))
	local field = aft.Actor:GetChild(name)

	Fields[pn] = Fields[pn] or {}
	FieldSkin[pn] = FieldSkin[pn] or {}
	Fields[pn][stype] = field
	FieldSkin[pn][stype] = skin

	if field then
		field:playcommand("Build", { Steps = Steps, WithData = false })
		field:visible(false)
	end
	return field
end

-- Create the render targets and one hidden field per playable type. Idempotent.
local function Ensure()
	local players = EnabledPlayers()
	if #players == 0 then return false end

	local width = (#players == 1) and 640 or 320
	for _, pn in ipairs(players) do
		EnsureAFT(pn, width)
	end

	local wanted = WantedTypes()
	TypeRepresentatives(wanted)

	for _, pn in ipairs(players) do
		local skin = PrefSkin(pn)
		Fields[pn] = Fields[pn] or {}
		FieldSkin[pn] = FieldSkin[pn] or {}
		for st in pairs(wanted) do
			local rep = Reps[st]
			if rep and (not Fields[pn][st] or FieldSkin[pn][st] ~= skin) then
				CreateField(pn, st, rep, skin)
			end
		end
	end
	return true
end

function Cache.TextureName(pn)
	local a = AFTs[pn]
	return a and a.Texture or nil
end

function Cache.TextureWidth(pn)
	local a = AFTs[pn]
	return a and a.Width or 640
end

function Cache.Show()
	if not Cache.WantShown then return end
	for _, pn in ipairs(EnabledPlayers()) do
		local a = AFTs[pn]
		if a and a.Actor then
			-- Wake before showing: a hibernating Actor skips Update.
			a.Actor:hibernate(0)
			a.Actor:visible(true)
		end
	end
end

-- Hide only: does not clear the "show when built" intent, so a transient hide (a
-- StepsType change) is undone by the next Build.
--
-- The render target is also hibernated. A cached field must not update while another
-- screen is running: its NoteField's Player then processes the preview chart against
-- gameplay's player state, which crashed in NoteField::DidHoldHead
-- (std::out_of_range) during ScreenGameplay::Update.
function Cache.Hide()
	for _, a in pairs(AFTs) do
		if a.Actor then
			a.Actor:visible(false)
			a.Actor:hibernate(3600)
		end
	end
end

function Cache.SetShown(shown)
	Cache.WantShown = shown and true or false
	if not Cache.WantShown then Cache.Hide() end
end

-- Prewarm entry point for the wheel side: builds the render targets and hidden
-- fields as soon as the wheel knows which players are in, i.e. at wheel load rather
-- than at the first difficulty entry. Cheap once warm.
function Cache.Ensure()
	return Ensure()
end

-- Rebuild the visible field for every enabled player's selected chart. Runs from the
-- wheel's poll (a tween), never from a message handler, because it creates actors.
function Cache.Build()
	if not Ensure() then return end

	local AnyBuilt = false
	for _, pn in ipairs(EnabledPlayers()) do
		local Steps = GAMESTATE:GetCurrentSteps(pn)
		local aft = AFTs[pn]
		if aft and aft.Actor then
			if not Steps or not ChartEligibility.IsAllowed(Steps) then
				-- A rejected chart must never reach the loader: a 10-track couple chart
				-- under the two-player couple style aborts the engine. Hide everything
				-- this side owns and wait for a selectable chart.
				for _, f in pairs(Fields[pn] or {}) do
					if f then f:visible(false) end
				end
			else
				local stype = ChartEligibility.TypeKey(Steps)
				local skin = PrefSkin(pn)
				local field = Fields[pn] and Fields[pn][stype]

				if not field or (FieldSkin[pn] and FieldSkin[pn][stype] ~= skin) then
					field = CreateField(pn, stype, Steps, skin)
				else
					-- Always reload, even when the same chart object is selected again: the
					-- shared PlayerState is reset by the gameplay screen, so a field that is
					-- not reloaded on re-entry draws nothing (black preview).
					field:playcommand("Build", { Steps = Steps, WithData = true })
				end

				for other, f in pairs(Fields[pn]) do
					if f then f:visible(other == stype) end
				end
				if field then field:visible(true) end
				AnyBuilt = true
			end
		end
	end

	if AnyBuilt and Cache.WantShown then Cache.Show() else Cache.Hide() end
end

local t = Def.ActorFrame {
	Name = "PreviewCacheHost",

	InitCommand=function(self)
		HOST_ROOT = self
		_G.InfinitesimalPreviewCache = Cache
		self:sleep(1):queuecommand("Watch")
	end,

	-- Hide the render targets if the wheel stops talking to us (screen torn down, or
	-- the theme reloaded while the wheel was open). Nothing is created here.
	WatchCommand=function(self)
		Cache.Tick = (Cache.Tick or 0) + 1
		local hb = Cache.Heartbeat or 0
		if hb == LastHeartbeat then
			Cache.Hide()
		end
		LastHeartbeat = hb
		self:sleep(1):queuecommand("Watch")
	end,
}

return t
