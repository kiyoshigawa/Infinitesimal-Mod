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
	local fa, fb = a:GetDisplayFullTitle() or "", b:GetDisplayFullTitle() or ""
	local la, lb = fa:lower(), fb:lower()
	if la ~= lb then return la < lb end
	return fa < fb
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

	for Song in ivalues(SONGMAN:GetAllSongs() or {}) do
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
-- remembers the last song per bucket; `DiffMemory` holds the last started song's
-- difficulty per side (keyed by profile identity, or by side for a guest); `View`
-- remembers where the wheel was left, by identity (bucket kind/name + song dir,
-- the same vocabulary ResumeState.ini uses) rather than by list index.
local SESSION_SCHEMA = 3

local function Session()
	local s = LuaWheelSession
	if type(s) ~= "table" or s.Schema ~= SESSION_SCHEMA then
		s = { Schema = SESSION_SCHEMA, BucketMemory = {}, View = { Index = 1 }, DiffMemory = {}, Seeded = false }
		LuaWheelSession = s
	end
	if type(s.BucketMemory) ~= "table" then s.BucketMemory = {} end
	if type(s.View) ~= "table" then s.View = { Index = 1 } end
	if type(s.DiffMemory) ~= "table" then s.DiffMemory = {} end
	if s.Seeded == nil then s.Seeded = false end
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

-- Profile directory for a persistent profile, else nil (guest / no profile).
local function ProfileDirFor(pn)
	if not pn or not PROFILEMAN:IsPersistentProfile(pn) then return nil end
	local slot = tonumber(string.sub(pn, -1)) - 1 -- PlayerNumber_P1 -> ProfileSlot 0
	local dir = PROFILEMAN:GetProfileDir(slot)
	if not dir or dir == "" then return nil end
	return dir
end

-- Difficulty memory is keyed by profile identity, not P1/P2, so a profile keeps its
-- chart choice whichever side it plays on. Guests (no profile) stay per-side.
local function SideKey(pn)
	local dir = ProfileDirFor(pn)
	if dir then return "profile:" .. dir end
	return "guest:" .. tostring(pn)
end

-- Lock in each joined side's difficulty memory when a song starts. Memory is keyed
-- by profile identity (SideKey), so a profile keeps its value on either side; guests
-- stay per-side. The record also names the chart, so re-opening the same song
-- restores exactly that chart.
local function CaptureCharts(song)
	if not song then return end
	local memory = Session().DiffMemory
	local songDir = song:GetSongDir()
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) then
			local steps = GAMESTATE:GetCurrentSteps(pn)
			if steps then
				memory[SideKey(pn)] = {
					StepsType = steps:GetStepsType(),
					Meter = steps:GetMeter(),
					SongDir = songDir,
					ChartKey = steps:GetChartKey(),
				}
			end
		end
	end
end

-- The difficulty memory to snap to for a side. A guest has no persistent record of
-- its own, so until it starts a song it mirrors a profiled side's live record; with
-- no profile in play it has none, and the wheel starts at the first chart.
local function DifficultyRecordFor(pn)
	local memory = Session().DiffMemory
	local rec = memory[SideKey(pn)]
	if rec then return rec end
	if ProfileDirFor(pn) then return nil end
	for _, other in ipairs({ PLAYER_1, PLAYER_2 }) do
		if other ~= pn and GAMESTATE:IsPlayerEnabled(other)
			and PROFILEMAN:IsPersistentProfile(other) then
			local otherRec = memory[SideKey(other)]
			if otherRec then return otherRec end
		end
	end
	return nil
end

-- Ask ChartDisplay to snap to each side's remembered difficulty for `song`
-- (one-shot handoff). A side with no memory yet gets { Default = true }, meaning
-- "start at the first chart".
local function RequestChartRestore(song)
	if not song then return end
	local pending = { SongDir = song:GetSongDir() }
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		local rec = DifficultyRecordFor(pn)
		if rec and tonumber(rec.Meter) then
			pending[pn] = { StepsType = rec.StepsType, Meter = rec.Meter, ChartKey = rec.ChartKey }
		else
			pending[pn] = { Default = true }
		end
	end
	GAMESTATE:Env()["LuaWheelChartRestore"] = pending
end

-- ------------------------------------------------- durable resume state -----
-- Per-profile record in Save/LocalProfiles/<id>/ResumeState.ini. The file format,
-- the schema migrations and the write path live in WheelResume
-- (Scripts/01 WheelResume.lua); this file only decides what goes into a record.

local function IndexOfSongIn(list, dir)
	for i = 1, #list do
		if list[i]:GetSongDir() == dir then return i end
	end
	return nil
end

-- Seed player: the master player if it has a profile, else any other enabled
-- profile ("profile beats guest"); nil when everyone is a guest.
local function SeedPlayer()
	local master = GAMESTATE:GetMasterPlayerNumber()
	if master and PROFILEMAN:IsPersistentProfile(master) then return master end
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) and PROFILEMAN:IsPersistentProfile(pn) then return pn end
	end
	return nil
end

local function SaveResumeForProfiles()
	local song = GAMESTATE:GetCurrentSong()
	if not song or not CurrentGroup or not GroupInfo[CurrentGroup] then return end
	local info = GroupInfo[CurrentGroup]
	local memory = Session().DiffMemory
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) then
			local dir = ProfileDirFor(pn)
			local rec = dir and memory[SideKey(pn)]
			if rec then
				WheelResume.Save(dir, {
					Schema = WheelResume.CurrentSchema,
					BucketKind = info.Kind,
					BucketName = info.Name,
					SongDir = song:GetSongDir(),
					StepsType = rec.StepsType,
					Meter = rec.Meter,
					ChartKey = rec.ChartKey,
				})
			end
		end
	end
end

-- On the first entry of a run, load every profiled side's difficulty memory and
-- restore the seed profile's last bucket/song. Guests stay unset here; they mirror a
-- profiled side's live record until they start a song (see DifficultyRecordFor).
local function SeedFromProfile(session)
	session.BucketMemory = {}
	session.DiffMemory = {}
	session.View = { Index = 1 } -- default: folder level, first bucket

	local seedPn = SeedPlayer()
	local seedRec
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) then
			local rec = WheelResume.Load(ProfileDirFor(pn))
			if rec then
				session.DiffMemory[SideKey(pn)] = rec
				if pn == seedPn then seedRec = rec end
			end
		end
	end
	if not seedRec then return end

	local bucket = BucketKey(seedRec.BucketKind, seedRec.BucketName)
	local songs = SongsByGroup[bucket]
	if songs and #songs > 0 then
		-- Same record shape the live wheel writes: identity, not an index, so a
		-- cold load and a warm re-entry restore through one code path.
		session.View = {
			BucketKind = seedRec.BucketKind,
			BucketName = seedRec.BucketName,
			SongDir = seedRec.SongDir,
			Index = IndexOfSongIn(songs, seedRec.SongDir),
		}
	end
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

-- Index of a bucket key in GroupList (nil if that bucket no longer exists).
local function IndexOfFolderKey(kind, name)
	if type(kind) ~= "string" or type(name) ~= "string" then return nil end
	local key = BucketKey(kind, name)
	for i = 1, #GroupList do
		if GroupList[i] == key then return i end
	end
	return nil
end

-- Restore the wheel position from a session View record. Position is stored by
-- identity (bucket kind/name + song directory, the same vocabulary as
-- ResumeState.ini), not by list index, so a rebuilt or drifted list cannot land
-- on the wrong song. The stored Index is only a fallback for entries that are
-- gone (song deleted, bucket renamed).
local function ResolveView(view)
	if type(view) ~= "table" then view = {} end
	local bucket = nil
	if type(view.BucketKind) == "string" and type(view.BucketName) == "string" then
		bucket = BucketKey(view.BucketKind, view.BucketName)
	end
	if bucket and SongsByGroup[bucket] then
		CurrentGroup = bucket
		BuildSongEntries(bucket)
		CurrentIndex = IndexOfSongDir(view.SongDir) or tonumber(view.Index) or 1
	else
		CurrentGroup = nil
		BuildFolderEntries()
		CurrentIndex = IndexOfFolderKey(view.FolderKind, view.FolderName)
			or tonumber(view.Index) or 1
	end
	if CurrentIndex < 1 or CurrentIndex > #Entries then CurrentIndex = 1 end
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
		-- Restore this side's previously chosen charts for this song, if any.
		RequestChartRestore(entry)
	end
	local view = { Index = CurrentIndex }
	if CurrentGroup then
		local info = GroupInfo[CurrentGroup]
		view.BucketKind = info and info.Kind
		view.BucketName = info and info.Name
		if entry and type(entry) ~= "string" then view.SongDir = entry:GetSongDir() end
	elseif type(entry) == "string" then
		local info = GroupInfo[entry]
		view.FolderKind = info and info.Kind
		view.FolderName = info and info.Name
	end
	session.View = view
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

-- Primary joined player (master, else any enabled side).
local function PrimaryPlayer()
	local master = GAMESTATE:GetMasterPlayerNumber()
	if master and GAMESTATE:IsPlayerEnabled(master) then return master end
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) then return pn end
	end
	return nil
end

-- Style matching the selected chart's steps type (and player count). Forcing the
-- wrong style makes SetCurrentStyle clear the chosen chart, which then crashes
-- ScreenGameplay::Init (assert m_pCurSteps[p] != nullptr).
local function StyleForSelection()
	local pn = PrimaryPlayer()
	local steps = pn and GAMESTATE:GetCurrentSteps(pn)
	if not steps or not GAMEMAN then return nil end
	local game = GAMESTATE:GetCurrentGame()
	if not game then return nil end
	local wantType = steps:GetStepsType()
	local wantVersus = GAMESTATE:GetNumSidesJoined() > 1
	local fallback
	for _, style in ipairs(GAMEMAN:GetStylesForGame(game:GetName())) do
		if style:GetStepsType() == wantType then
			local isVersus = ToEnumShortString(style:GetStyleType()) == "TwoPlayersTwoSides"
			if isVersus == wantVersus then return style:GetName() end
			fallback = fallback or style:GetName()
		end
	end
	return fallback
end

local function StartGameplay()
	if Transitioning then return end
	Transitioning = true
	-- Set the style to match the chosen chart, else SetCurrentStyle clears it and
	-- ScreenGameplay::Init asserts (hard crash).
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	GAMESTATE:SetCurrentStyle(StyleForSelection() or (GAMESTATE:GetNumSidesJoined() > 1 and "versus" or "single"))
	-- Backstop: never transition with a missing chart; let the player reselect.
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		if GAMESTATE:IsPlayerEnabled(pn) and not GAMESTATE:GetCurrentSteps(pn) then
			MESSAGEMAN:Broadcast("LockedDifficultyDenied")
			Transitioning = false
			return
		end
	end
	-- Save each side's chosen chart, and persist each joined profile's resume record.
	CaptureCharts(GAMESTATE:GetCurrentSong())
	SaveResumeForProfiles()
	SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
end

-- --------------------------------------------------------------- input ------
local function InputHandler(event)
	local pn = event.PlayerNumber
	if not pn then return end
	if event.type == "InputEventType_Release" then return end
	local button = event.button

	-- If an unjoined player presses a join button and can afford it, join them and
	-- stop here so the same press doesn't also trigger the stage action below.
	if JoinUtils.TryJoin(pn, button) then return end

	-- To avoid control from a player that has not joined, filter the inputs out
	if pn == PLAYER_1 and not GAMESTATE:IsPlayerEnabled(PLAYER_1) then return end
	if pn == PLAYER_2 and not GAMESTATE:IsPlayerEnabled(PLAYER_2) then return end

	local Intent     = InputIntent.Intent
	local intent     = InputIntent.Horizontal(button)
	local firstPress = InputIntent.IsFirstPress(event)

	-- Engine command window. The window's own player never reaches this handler
	-- while it is open (the engine consumes their input first), so this branch
	-- is really about the OTHER side: do not let them scroll or start a song
	-- underneath an open window. Joining above is still allowed, and a player
	-- may still open their own window.
	if WheelOptions.AnyOpen() then
		if firstPress and InputIntent.IsOpenOptions(button) then
			WheelOptions.Open(pn)
		end
		return
	end

	-- Select opens this player's window at any wheel stage, including the
	-- difficulty list: Select is not one of the chart-confirm buttons (those are
	-- Center/Start), so there is nothing to conflict with.
	if firstPress and InputIntent.IsOpenOptions(button) then
		if WheelOptions.Open(pn) then return end
	end

	if SongIsChosen then
		-- Difficulty is owned by ChartDisplay. Each joined player confirms their own
		-- chart; gameplay starts once every joined player has confirmed. Cancel must
		-- stay available even after a player has confirmed -- Basic mode locks the
		-- confirmed side out via PlayerCanMove, which we deliberately do not do.
		if intent == Intent.Back then
			-- One shot: holding back must not unlock and then cancel in one hold.
			if not firstPress then return end
			if Confirmed[pn] then
				-- Unlock just this player and stay in difficulty select; a second
				-- Back (now unlocked) leaves to the song list.
				Confirmed[pn] = false
				MESSAGEMAN:Broadcast("StepsUnchosen", { Player = pn })
			else
				CancelSong()
			end
		elseif intent == Intent.Forward then
			-- One shot: holding it must not confirm and then start gameplay.
			if not firstPress then return end
			if not Confirmed[pn] then
				Confirmed[pn] = true
				MESSAGEMAN:Broadcast("StepsChosen", { Player = pn })
			end
			if AllJoinedConfirmed() then StartGameplay() end
		elseif (intent == Intent.Left or intent == Intent.Right) and Confirmed[pn] then
			-- Locked: the chart cannot change. Give audible feedback so the
			-- silence is not mistaken for a broken control. Initial press only, so
			-- a held direction cannot machine-gun the denial sound.
			if firstPress then
				MESSAGEMAN:Broadcast("LockedDifficultyDenied")
			end
		end
		return
	end

	if CurrentGroup == nil then
		-- folder level
		if intent == Intent.Left then Move(-1)
		elseif intent == Intent.Right then Move(1)
		elseif intent == Intent.Forward then
			-- One shot: holding it must not open a bucket and then select a song.
			if firstPress then
				local entry = Entries[CurrentIndex]
				if type(entry) == "string" then EnterGroup(entry) end
			end
		elseif intent == Intent.Back then
			if firstPress then SCREENMAN:GetTopScreen():Cancel() end
		end
	else
		-- song level
		if intent == Intent.Left then Move(-1)
		elseif intent == Intent.Right then Move(1)
		elseif intent == Intent.Forward then
			if firstPress then MESSAGEMAN:Broadcast("MusicWheelStart") end
		elseif intent == Intent.Back then
			if firstPress then LeaveGroup() end
		end
	end

	MESSAGEMAN:Broadcast("UpdateMusic")
end

-- --------------------------------------------------------------- actor ------
-- Re-entering the screen (e.g. after finishing a song, or after a mid-session join)
-- should resume where we left off.  Position lives in the Lua session table (see
-- Session()) as identities, not indices, and resets on the next launch.
local session = Session()
if not session.Seeded then
	SeedFromProfile(session)
	session.Seeded = true
end
ResolveView(session.View)
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
	ConfirmCommand=function(self)
		-- Re-arm the snap as the difficulty stage opens: a side that joined since this
		-- song was highlighted (a mid-session guest) then still gets its memory honoured.
		RequestChartRestore(GAMESTATE:GetCurrentSong())
		MESSAGEMAN:Broadcast("SongChosen")
	end,

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
