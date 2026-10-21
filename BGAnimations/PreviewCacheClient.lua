-- Wheel-side client for the session-persistent chart preview.
--
-- The fields and their render targets live on the ScreenChartPreviewCache overlay
-- screen (BGAnimations/ScreenChartPreviewCache overlay.lua); this actor only displays
-- the render target by name and drives the host through InfinitesimalPreviewCache.
-- Mounted by ScreenSelectMusic underlay/SongPreview.lua instead of NotefieldPreview.lua
-- when the host is present; NotefieldPreview.lua remains the fallback.
--
-- Same root name and BuildChart command as the fallback, so SongPreview's poll does not
-- need to know which one it mounted.
--
-- Note: Def.Sprite{...} builds a definition, not a live actor, so the sprites are
-- looked up by name (GetChild) whenever they are touched. They are direct children of
-- this frame because ActorFrame::GetChild only searches direct children.

local PM = { PLAYER_1, PLAYER_2 }
local PlayerPos = GAMESTATE:GetNumPlayersEnabled() == 1 and "OnePlayerTwoSides" or "TwoPlayersTwoSides"

local Loaded = {} -- pn -> texture name currently loaded into the sprite
local LastTick = nil
local StalePolls = 0

local function Cache()
	return _G.InfinitesimalPreviewCache
end

local function SpriteName(pn)
	return "CacheSprite" .. ToEnumShortString(pn)
end

-- Point each player's sprite at the host's render target once it exists.
local function Bind(root)
	local c = Cache()
	if not c or not c.Host then return false end

	for _, pn in ipairs(PM) do
		local sprite = root:GetChild(SpriteName(pn))
		if sprite then
			local name = c.TextureName and c.TextureName(pn)
			if name then
				local width = (c.TextureWidth and c.TextureWidth(pn)) or 640
				if Loaded[pn] ~= name then
					sprite:Load(name):zoomto(width, 480)
					Loaded[pn] = name
				end
				sprite:visible(true)
			else
				sprite:visible(false)
			end
		end
	end
	return true
end

-- The host bumps Cache.Tick once a second. If it stops, the host was torn down (theme
-- reload) and the next screen entry must use the fallback instead of dead actors.
local function Watch()
	local c = Cache()
	if not c or not c.Host then return end
	local tick = c.Tick or 0
	if LastTick ~= nil and tick == LastTick then
		StalePolls = StalePolls + 1
		if StalePolls > 60 then -- ~3 s at the 50 ms poll
			c.Host = false
		end
	else
		StalePolls = 0
	end
	LastTick = tick
end

local t = Def.ActorFrame {
	Name = "PreviewNotefield",

	-- Called by SongPreview's poll every 50 ms while this screen is open.
	HeartbeatCommand=function(self)
		local c = Cache()
		if not c or not c.Host then return end
		c.Heartbeat = (c.Heartbeat or 0) + 1
		Watch()
		-- Front-load the field creation to the wheel load rather than the first
		-- difficulty entry. Cheap once warm.
		if c.Ensure then c.Ensure() end
		Bind(self)
	end,

	-- Called by SongPreview when the chart signature changes (poll, i.e. a tween).
	BuildChartCommand=function(self)
		local c = Cache()
		if not c or not c.Host then return end
		c.Heartbeat = (c.Heartbeat or 0) + 1
		Watch()
		c.Build()
		Bind(self)
	end,

	-- Visibility only, so this is safe from a message handler.
	SetShownCommand=function(self, params)
		local c = Cache()
		if not c or not c.Host then return end
		c.SetShown(params and params.Shown == true)
	end,

	-- Transient hide (a StepsType change is about to redraw the field). Keeps the
	-- "show when built" intent so the rebuilt field is revealed again.
	HideNowCommand=function(self)
		local c = Cache()
		if not c or not c.Host then return end
		c.Hide()
	end,

	-- The fallback owns per-song pre-creation; the host does its own prewarm.
	EnsureTypesCommand=function(self) end,
}

for _, pn in ipairs(PM) do
	local pnShort = ToEnumShortString(pn)

	t[#t+1] = Def.Sprite {
		Name = SpriteName(pn),
		InitCommand=function(self)
			self:xy((THEME:GetMetric("ScreenGameplay", "Player" .. pnShort .. PlayerPos .. "X") - SCREEN_CENTER_X) / 1.5, 0)
			self:visible(false)
		end,
	}
end

return t
