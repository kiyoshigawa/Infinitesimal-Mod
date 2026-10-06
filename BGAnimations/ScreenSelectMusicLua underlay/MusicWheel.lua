-- ScreenSelectMusicLua underlay: theme-owned song wheel.
--
-- Two levels:
--   * FOLDER level: browse song groups;     Select opens a group;      Back exits
--   * SONG   level: browse songs in a group; Select chooses a song;     Back returns
--
-- The chrome (preview/video, song info, difficulty list, scores) follows the
-- highlighted entry; a highlighted folder previews its first playable song.
--
-- Synthetic buckets (All Songs / K-Pop / ...) will be added to GroupList later.
--
-- Adapted from BGAnimations/ScreenSelectMusicBasic underlay/MusicWheel.lua

local WheelSize = 13
local WheelCenter = math.ceil( WheelSize * 0.5 )
local WheelItem = { Width = 212, Height = 120 }
local WheelSpacing = 250
local WheelRotation = 0.1

-- ---------------------------------------------------------------- data ------
local GroupList = {}      -- ordered folder names
local SongsByGroup = {}   -- folder name -> { playable Song, ... }

local function BuildData()
	GroupList = {}
	SongsByGroup = {}
	for Group in ivalues(SONGMAN:GetSongGroupNames()) do
		local playable = {}
		for Song in ivalues(SONGMAN:GetSongsInGroup(Group)) do
			if #SongUtil.GetPlayableSteps(Song) > 0 then
				playable[#playable+1] = Song
			end
		end
		if #playable > 0 then
			GroupList[#GroupList+1] = Group
			SongsByGroup[Group] = playable
		end
	end
end

BuildData()

-- --------------------------------------------------------------- state ------
local Entries = {}          -- active list: strings (folders) or Song tables
local Targets = {}
local CurrentIndex = 1
local CurrentGroup = nil    -- nil = folder level
local SongIsChosen = false
local Confirmed = {}        -- PlayerNumber -> true once that side has confirmed
local Transitioning = false -- one-shot guard for the gameplay transition

local function BuildFolderEntries()
	Entries = {}
	for i = 1, #GroupList do Entries[i] = GroupList[i] end
end

local function BuildSongEntries(group)
	Entries = {}
	local songs = SongsByGroup[group] or {}
	for i = 1, #songs do Entries[i] = songs[i] end
end

local function UpdateItemTargets(val)
	if #Entries == 0 then return end
	for i = 1, WheelSize do
		Targets[i] = val + i - WheelCenter
		while Targets[i] > #Entries do Targets[i] = Targets[i] - #Entries end
		while Targets[i] < 1 do Targets[i] = Targets[i] + #Entries end
	end
end

-- Load either a folder banner or a song banner onto an item's Banner sprite.
local function UpdateItem(self, entry)
	local banner = self:GetChild("Banner")
	local name = self:GetChild("GroupName")
	if type(entry) == "string" then
		local path = SONGMAN:GetSongGroupBannerPath(entry)
		if path == "" then banner:Load(nil) else banner:Load(path) end
		banner:scaletoclipped(WheelItem.Width, WheelItem.Height)
		name:settext(entry)
	elseif entry then
		banner:LoadFromSongBanner(entry):scaletoclipped(WheelItem.Width, WheelItem.Height)
		name:settext("")
	else
		banner:Load(nil)
		name:settext("")
	end
end

-- Point the chrome (preview / difficulty / scores) at the highlighted entry.
local function SetSelection(index)
	CurrentIndex = index
	local entry = Entries[CurrentIndex]
	if type(entry) == "string" then
		local songs = SongsByGroup[entry]
		if songs and songs[1] then GAMESTATE:SetCurrentSong(songs[1]) end
	elseif entry then
		GAMESTATE:SetCurrentSong(entry)
		-- Remember where we are at song level so we can return here after gameplay.
		if CurrentGroup then
			LuaWheelLastGroup = CurrentGroup
			LuaWheelLastIndex = CurrentIndex
		end
	end
	MESSAGEMAN:Broadcast("CurrentSongChanged")
	Trace("LuaWheel selection: " .. tostring(type(entry) == "string" and entry or (entry and entry:GetDisplayFullTitle()) or "nil"))
end

local function Move(delta)
	if #Entries == 0 then return end
	CurrentIndex = CurrentIndex + delta
	if CurrentIndex < 1 then CurrentIndex = #Entries end
	if CurrentIndex > #Entries then CurrentIndex = 1 end
	SetSelection(CurrentIndex)
	UpdateItemTargets(CurrentIndex)
	MESSAGEMAN:Broadcast("Scroll", { Direction = delta })
end

local function EnterGroup(group)
	CurrentGroup = group
	BuildSongEntries(group)
	CurrentIndex = 1
	SetSelection(CurrentIndex)
	UpdateItemTargets(CurrentIndex)
	MESSAGEMAN:Broadcast("Rebuild")
end

local function LeaveGroup()
	local previous = CurrentGroup
	CurrentGroup = nil
	BuildFolderEntries()
	CurrentIndex = 1
	for i = 1, #GroupList do
		if GroupList[i] == previous then CurrentIndex = i break end
	end
	SetSelection(CurrentIndex)
	UpdateItemTargets(CurrentIndex)
	MESSAGEMAN:Broadcast("Rebuild")
end

-- ------------------------------------------------------- confirm/start ------
-- Difficulty stage: each joined player confirms their own chart; gameplay starts
-- once every joined player has confirmed. Cancel stays available at all times.
local function AllJoinedConfirmed()
	local any = false
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) then
			any = true
			if not Confirmed[pn] then return false end
		end
	end
	return any
end

local function CancelSong()
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if Confirmed[pn] then
			MESSAGEMAN:Broadcast("StepsUnchosen", { Player = pn })
		end
	end
	MESSAGEMAN:Broadcast("SongUnchosen")
end

local function StartGameplay()
	if Transitioning then return end
	Transitioning = true
	-- Required, or the transition crashes (see BasicChartDisplay.lua).
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	GAMESTATE:SetCurrentStyle(GAMESTATE:GetNumSidesJoined() > 1 and "versus" or "single")
	SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
end

-- --------------------------------------------------------------- input ------
local function InputHandler(event)
	local pn = event.PlayerNumber
	if not pn then return end
	if event.type == "InputEventType_Release" then return end
	local button = event.button

	-- If an unjoined player attempts to join and has enough credits, join them
	if (button == "Center" or (not IsGame("pump") and button == "Start")) and
		not GAMESTATE:IsSideJoined(pn) and GAMESTATE:GetCoins() >= GAMESTATE:GetCoinsNeededToJoin() then
		GAMESTATE:JoinPlayer(pn)
		GAMESTATE:InsertCoin(-(GAMESTATE:GetCoinsNeededToJoin()))
		MESSAGEMAN:Broadcast("PlayerJoined", { Player = pn })
	end

	-- To avoid control from a player that has not joined, filter the inputs out
	if pn == PLAYER_1 and not GAMESTATE:IsPlayerEnabled(PLAYER_1) then return end
	if pn == PLAYER_2 and not GAMESTATE:IsPlayerEnabled(PLAYER_2) then return end

	local back   = button == "Back" or button == "UpLeft" or button == "UpRight"
	local left   = button == "Left" or button == "MenuLeft" or button == "DownLeft"
	local right  = button == "Right" or button == "MenuRight" or button == "DownRight"
	local select = button == "Start" or button == "MenuStart" or button == "Center"

	if SongIsChosen then
		-- Difficulty is owned by ChartDisplay. Each joined player confirms their own
		-- chart; gameplay starts once every joined player has confirmed. Cancel must
		-- stay available even after a player has confirmed -- Basic mode locks the
		-- confirmed side out via PlayerCanMove, which we deliberately do not do.
		if event.type == "InputEventType_Repeat" then return end

		if back or button == "MenuUp" or button == "MenuDown" then
			if Confirmed[pn] then
				-- Unlock just this player and stay in difficulty select; a second
				-- Back (now unlocked) leaves to the song list.
				Confirmed[pn] = false
				MESSAGEMAN:Broadcast("StepsUnchosen", { Player = pn })
			else
				CancelSong()
			end
		elseif select then
			if not Confirmed[pn] then
				Confirmed[pn] = true
				MESSAGEMAN:Broadcast("StepsChosen", { Player = pn })
			end
			if AllJoinedConfirmed() then StartGameplay() end
		end
		return
	end

	if CurrentGroup == nil then
		-- folder level
		if left then Move(-1)
		elseif right then Move(1)
		elseif select then
			local entry = Entries[CurrentIndex]
			if type(entry) == "string" then EnterGroup(entry) end
		elseif back then
			SCREENMAN:GetTopScreen():Cancel()
		end
	else
		-- song level
		if left then Move(-1)
		elseif right then Move(1)
		elseif select then
			MESSAGEMAN:Broadcast("MusicWheelStart")
		elseif back then
			LeaveGroup()
		end
	end

	MESSAGEMAN:Broadcast("UpdateMusic")
end

-- --------------------------------------------------------------- actor ------
-- Re-entering the screen (e.g. after finishing a song) should land on the group
-- and song we left off on, not reset to the folder list. Position is kept in
-- globals because this file is re-run for each screen instance.
if type(LuaWheelLastGroup) == "string" and SongsByGroup[LuaWheelLastGroup] then
	CurrentGroup = LuaWheelLastGroup
	BuildSongEntries(CurrentGroup)
	CurrentIndex = tonumber(LuaWheelLastIndex) or 1
	if CurrentIndex < 1 or CurrentIndex > #Entries then CurrentIndex = 1 end
else
	BuildFolderEntries()
	CurrentIndex = 1
end
UpdateItemTargets(CurrentIndex)

local t = Def.ActorFrame {
	InitCommand=function(self)
		self:y(SCREEN_HEIGHT / 2 + 155):fov(90):SetDrawByZPosition(true)
		:vanishpoint(SCREEN_CENTER_X, SCREEN_BOTTOM - 150)
	end,

	OnCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		self:easeoutexpo(1):y(SCREEN_HEIGHT / 2 - 150)
		-- Defer the first selection until the screen/chrome are fully built.
		self:sleep(0.1):queuecommand("InitialSelection")
	end,

	InitialSelectionCommand=function(self)
		SetSelection(CurrentIndex)
		MESSAGEMAN:Broadcast("Rebuild")
	end,

	-- Race condition workaround (matches Basic wheel)
	MusicWheelStartMessageCommand=function(self) self:sleep(0.01):queuecommand("Confirm") end,
	ConfirmCommand=function(self) MESSAGEMAN:Broadcast("SongChosen") end,

	SongChosenMessageCommand=function(self)
		SongIsChosen = true
		Confirmed[PLAYER_1] = false
		Confirmed[PLAYER_2] = false
	end,
	SongUnchosenMessageCommand=function(self)
		SongIsChosen = false
		Confirmed[PLAYER_1] = false
		Confirmed[PLAYER_2] = false
	end,

	-- Play song preview
	Def.Actor {
		CurrentSongChangedMessageCommand=function(self)
			SOUND:StopMusic()
			self:stoptweening():sleep(THEME:GetMetric("ScreenSelectMusic", "SampleMusicDelay")):queuecommand("PlayMusic")
		end,

		PlayMusicCommand=function(self)
			local Song = GAMESTATE:GetCurrentSong()
			if Song then
				SOUND:PlayMusicPart(Song:GetMusicPath(), Song:GetSampleStart(), Song:GetSampleLength(), 0, 1, false, false, false, Song:GetTimingData())
			end
		end
	},

	Def.Sound {
		File=THEME:GetPathS("MusicWheel", "change"),
		IsAction=true,
		ScrollMessageCommand=function(self) self:play() end
	},

	Def.Sound {
		File=THEME:GetPathS("Common", "Start"),
		IsAction=true,
		MusicWheelStartMessageCommand=function(self) self:play() end
	},

	-- Lock feedback: distinct sound when a player locks / unlocks their chart.
	Def.Sound {
		File=THEME:GetPathS("Common", "Start"),
		IsAction=true,
		StepsChosenMessageCommand=function(self) self:play() end
	},

	Def.Sound {
		File=THEME:GetPathS("Common", "Cancel"),
		IsAction=true,
		StepsUnchosenMessageCommand=function(self) self:play() end
	},
}

-- The Wheel: originally made by Luizsan
for i = 1, WheelSize do
	local slot = i

	t[#t+1] = Def.ActorFrame{
		OnCommand=function(self)
			UpdateItem(self, Entries[Targets[slot]])
			self:playcommand("Scroll", { Direction = 0 })
		end,

		-- Rebuild (level change): reset the scroll offset and reload every slot.
		RebuildMessageCommand=function(self)
			i = slot
			self:stoptweening()
			UpdateItem(self, Entries[Targets[slot]])
			self:playcommand("Scroll", { Direction = 0 })
		end,

		ScrollMessageCommand=function(self,param)
			-- Save this so that we can resume the last selection after gameplay
			LastSongIndex = CurrentIndex

			self:stoptweening()

			-- Calculate position
			local xpos = SCREEN_CENTER_X + (i - WheelCenter) * WheelSpacing

			-- Calculate displacement based on input
			local displace = -param.Direction * WheelSpacing

			-- Only tween if a direction was specified
			local tween = param and param.Direction and math.abs(param.Direction) > 0

			-- Adjust and wrap actor index
			i = i - param.Direction
			while i > WheelSize do i = i - WheelSize end
			while i < 1 do i = i + WheelSize end

			-- If it's an edge item, load a new entry. Edge items should never tween
			if i == 1 or i == WheelSize then
				UpdateItem(self, Entries[Targets[i]])
			elseif tween then
				self:easeoutexpo(0.4)
			end

			-- Animate!
			self:xy(xpos + displace, SCREEN_CENTER_Y)
			self:rotationy((SCREEN_CENTER_X - xpos - displace) * -WheelRotation)
			self:z(-math.abs(SCREEN_CENTER_X - xpos - displace) * 0.25)
			self:GetChild(""):GetChild("Index"):playcommand("Refresh")
		end,

		Def.Banner {
			Name="Banner",
		},

		Def.Sprite {
			Texture=THEME:GetPathG("", "MusicWheel/SongFrame"),
		},

		Def.BitmapText {
			Name="GroupName",
			Font="Montserrat semibold 40px",
			InitCommand=function(self)
				self:zoom(0.6):maxwidth(WheelItem.Width * 0.9 / self:GetZoom())
				:shadowlength(2)
			end,
		},

		Def.ActorFrame {
			Def.Quad {
				InitCommand=function(self)
					self:zoomto(60, 18):addy(-50)
					:diffuse(0,0,0,0.6)
					:fadeleft(0.3):faderight(0.3)
				end
			},

			Def.BitmapText {
				Name="Index",
				Font="Montserrat semibold 40px",
				InitCommand=function(self)
					self:addy(-50):zoom(0.4):skewx(-0.1):diffusetopedge(0.95,0.95,0.95,0.8):shadowlength(1.5)
				end,
				RefreshCommand=function(self,param) self:settext(Targets[slot]) end
			}
		}
	}
end

return t
