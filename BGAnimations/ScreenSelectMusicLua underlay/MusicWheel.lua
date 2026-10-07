-- ScreenSelectMusicLua underlay: theme-owned song wheel.
--
-- Two levels:
--   * FOLDER level: browse song groups;     Select opens a group;      Back exits
--   * SONG   level: browse songs in a group; Select chooses a song;     Back returns
--
-- The chrome (preview/video, song info, difficulty list, scores) follows the
-- highlighted entry; a highlighted folder previews its first playable song.
--
-- Top-level entries are "buckets": custom (All Songs, ...) -> genre (A-Z) ->
-- mix folders (A-Z).  See the data section below.
--
-- Adapted from BGAnimations/ScreenSelectMusicBasic underlay/MusicWheel.lua

local WheelSize = 13
local WheelCenter = math.ceil( WheelSize * 0.5 )
local WheelItem = { Width = 212, Height = 120 }
local WheelSpacing = 250
local WheelRotation = 0.1

-- ---------------------------------------------------------------- data ------
-- Top-level entries are "buckets", computed here from SONGMAN:
--   * custom buckets  (registry below; e.g. All Songs)
--   * genre buckets   (derived from Song:GetGenre(); empty skipped)
--   * mix folders     (physical Songs/ groups)
-- Fixed order: custom -> genre (A-Z) -> mix folders (A-Z).
local GroupList = {}      -- ordered bucket keys
local SongsByGroup = {}   -- bucket key -> { playable Song, ... }
local GroupInfo = {}      -- bucket key -> { Kind, Name, Songs }

local function BucketKey(kind, name)
	return kind .. ":" .. name
end

-- Trim surrounding whitespace (genre tags can carry CR/LF/space from the simfile).
local function Trim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Case-insensitive title sort used within every bucket (case tie-break for stability).
local function TitleLess(a, b)
	local ta, tb = a:GetDisplayFullTitle():lower(), b:GetDisplayFullTitle():lower()
	if ta ~= tb then return ta < tb end
	return a:GetDisplayFullTitle() < b:GetDisplayFullTitle()
end

-- Case-insensitive name sort (case tie-break, so K-POP vs K-Pop is deterministic).
local function NameLess(a, b)
	local la, lb = a:lower(), b:lower()
	if la ~= lb then return la < lb end
	return a < b
end

-- Custom bucket registry. Adding a bucket is a one-liner:
--   { Name = "Short Songs", Predicate = function(song) return song:MusicLengthSeconds() < 90 end },
local CustomBuckets = {
	{ Name = "All Songs", Predicate = function(song) return true end },
}

local function BuildData()
	GroupList = {}
	SongsByGroup = {}
	GroupInfo = {}

	-- Single pass: collect playable songs once, grouped by folder and by genre.
	local folderNames = {}
	local folderSongs = {}
	local genreSongs = {}
	local allPlayable = {}

	for Song in ivalues(SONGMAN:GetAllSongs()) do
		if #SongUtil.GetPlayableSteps(Song) > 0 then
			allPlayable[#allPlayable+1] = Song

			local folder = Song:GetGroupName()
			if not folderSongs[folder] then
				folderSongs[folder] = {}
				folderNames[#folderNames+1] = folder
			end
			folderSongs[folder][#folderSongs[folder]+1] = Song

			local genre = Trim(Song:GetGenre())
			if genre ~= "" then
				if not genreSongs[genre] then genreSongs[genre] = {} end
				genreSongs[genre][#genreSongs[genre]+1] = Song
			end
		end
	end

	local function AddBucket(kind, name, songs)
		if #songs == 0 then return end
		table.sort(songs, TitleLess)
		local key = BucketKey(kind, name)
		GroupList[#GroupList+1] = key
		SongsByGroup[key] = songs
		GroupInfo[key] = { Kind = kind, Name = name, Songs = songs }
	end

	-- 1. Custom buckets (registry order), evaluated over all playable songs.
	for _, def in ipairs(CustomBuckets) do
		local songs = {}
		for _, song in ipairs(allPlayable) do
			if def.Predicate(song) then songs[#songs+1] = song end
		end
		AddBucket("custom", def.Name, songs)
	end

	-- 2. Genre buckets, alphabetical, empty skipped.
	local genreNames = {}
	for name in pairs(genreSongs) do genreNames[#genreNames+1] = name end
	table.sort(genreNames, NameLess)
	for _, name in ipairs(genreNames) do
		AddBucket("genre", name, genreSongs[name])
	end

	-- 3. Mix folders, alphabetical.
	table.sort(folderNames, NameLess)
	for _, name in ipairs(folderNames) do
		AddBucket("folder", name, folderSongs[name])
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

-- ---------------------------------------------------------- session --------
-- Session state lives in a Lua global: it survives screen entries *and* title-menu
-- visits within a run, and is fresh on each launch.  (GAMESTATE:Env() was tried
-- first but the engine clears it when returning to the title.)  `BucketMemory`
-- remembers the last song per bucket; `View` remembers where the wheel was left so
-- re-entry resumes there.
local SESSION_SCHEMA = 1

local function Session()
	local s = LuaWheelSession
	if type(s) ~= "table" or s.Schema ~= SESSION_SCHEMA then
		s = { Schema = SESSION_SCHEMA, BucketMemory = {}, View = { Bucket = nil, Index = 1 } }
		LuaWheelSession = s
	end
	if type(s.BucketMemory) ~= "table" then s.BucketMemory = {} end
	if type(s.View) ~= "table" then s.View = { Bucket = nil, Index = 1 } end
	return s
end

-- Index of a song in the active Entries by its stable directory id (nil if absent).
local function IndexOfSongDir(dir)
	for i = 1, #Entries do
		local e = Entries[i]
		if type(e) ~= "string" and e:GetSongDir() == dir then return i end
	end
	return nil
end

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

-- Load either a bucket banner (mix folders only) or a song banner.
local function UpdateItem(self, entry)
	local banner = self:GetChild("Banner")
	local name = self:GetChild("GroupName")
	if type(entry) == "string" then
		local info = GroupInfo[entry]
		if info and info.Kind == "folder" then
			local path = SONGMAN:GetSongGroupBannerPath(info.Name)
			if path == "" then banner:Load(nil) else banner:Load(path) end
			banner:visible(true)
		else
			-- Synthetic buckets are text-only: clear AND hide the banner so no
			-- previously-loaded song art can linger on the tile.
			banner:Load(nil)
			banner:visible(false)
		end
		banner:scaletoclipped(WheelItem.Width, WheelItem.Height)
		name:settext(info and info.Name or "")
	elseif entry then
		banner:LoadFromSongBanner(entry):scaletoclipped(WheelItem.Width, WheelItem.Height)
		banner:visible(true)
		name:settext("")
	else
		banner:Load(nil)
		banner:visible(false)
		name:settext("")
	end
end

-- Point the chrome (preview / difficulty / scores) at the highlighted entry.
local function SetSelection(index)
	CurrentIndex = index
	local entry = Entries[CurrentIndex]
	local session = Session()
	if type(entry) == "string" then
		local songs = SongsByGroup[entry]
		if songs then
			-- Preview the bucket's remembered song, else its first.
			local preview = songs[1]
			local remembered = session.BucketMemory[entry]
			if remembered then
				for _, s in ipairs(songs) do
					if s:GetSongDir() == remembered then preview = s break end
				end
			end
			if preview then GAMESTATE:SetCurrentSong(preview) end
		end
	elseif entry then
		GAMESTATE:SetCurrentSong(entry)
		-- Remember this song for the bucket we're in, so re-entering it resumes here.
		if CurrentGroup then
			session.BucketMemory[CurrentGroup] = entry:GetSongDir()
		end
	end
	session.View = { Bucket = CurrentGroup, Index = CurrentIndex }
	MESSAGEMAN:Broadcast("CurrentSongChanged")
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
	-- Resume this bucket's last-visited song if we have one, else start at the top.
	CurrentIndex = IndexOfSongDir(Session().BucketMemory[group]) or 1
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
		elseif (left or right) and Confirmed[pn] then
			-- Locked: the chart cannot change. Give audible feedback so the
			-- silence is not mistaken for a broken control.
			MESSAGEMAN:Broadcast("LockedDifficultyDenied")
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
-- Re-entering the screen (e.g. after finishing a song) should resume where we left
-- off.  Position lives in the GAMESTATE:Env() session table, so it survives screen
-- entries within a run and resets on the next launch.
local view = Session().View
if type(view.Bucket) == "string" and SongsByGroup[view.Bucket] then
	CurrentGroup = view.Bucket
	BuildSongEntries(CurrentGroup)
else
	CurrentGroup = nil
	BuildFolderEntries()
end
CurrentIndex = tonumber(view.Index) or 1
if CurrentIndex < 1 or CurrentIndex > #Entries then CurrentIndex = 1 end
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
		-- Slide the wheel out of the way so the expanded chart/stats pane is visible
		-- (the stock wheel does this via MusicWheelSongChosenMessageCommand).
		self:stoptweening():easeoutexpo(0.5):y(SCREEN_HEIGHT / 2 + 150)
	end,
	SongUnchosenMessageCommand=function(self)
		SongIsChosen = false
		Confirmed[PLAYER_1] = false
		Confirmed[PLAYER_2] = false
		self:stoptweening():easeoutexpo(0.5):y(SCREEN_HEIGHT / 2 - 150)
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
		-- Backing out of a locked chart: distinct from the lock (Start) and the
		-- denied-L/R (Cancel) sounds.
		File=THEME:GetPathS("_switch", "down"),
		IsAction=true,
		StepsUnchosenMessageCommand=function(self) self:play() end
	},

	Def.Sound {
		File=THEME:GetPathS("Common", "Cancel"),
		IsAction=true,
		LockedDifficultyDeniedMessageCommand=function(self) self:play() end
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
				RefreshCommand=function(self,param) self:settext(Targets[i]) end
			}
		}
	}
end

return t
