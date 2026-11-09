-- One chart-preview NoteField for one player and one StepsType.
--
-- Added into that player's ActorFrameTexture by NotefieldPreview.lua, which sets the
-- globals InfinitesimalPreviewFieldPN (player) and InfinitesimalPreviewFieldKey
-- (StepsType) first and then calls "Build" below. NotefieldPreview keeps one field per
-- (player, StepsType) so that crossing between chart types only swaps visibility
-- instead of creating a field: creation costs 120-570 ms, while a build on an
-- existing field costs a few tens of milliseconds.
--
-- Two things happen on every build, because each half alone leaves the preview blank
-- in this engine build:
--   * ChangeReload(Steps) rebuilds the columns/receptors/noteskin and loads the chart.
--   * SetNoteDataFromLua(<chart data>) is what makes the note rows refresh on screen.
-- ChangeReload alone updates only the receptors; SetNoteDataFromLua alone keeps the
-- old chart's rows. Both together render the new chart.
--
-- Note data source: Steps:GetNoteData() first, falling back to Song:GetNoteData() by
-- chart key. Song:GetNoteData() is lazily populated and returns an empty table for a
-- chart the song has not decoded yet, so it cannot be the only source.
--
-- Speed mods are applied after the reload with ModsFromString: applying them before it
-- lets the reload reset them, which produces inconsistent note spacing.

local pn = InfinitesimalPreviewFieldPN
local key = InfinitesimalPreviewFieldKey or "field"
local pnNoteField = PlayerNumber:Reverse()[pn]

local ReceptorPosNormal = THEME:GetMetric("Player","ReceptorArrowsYStandard")
local ReceptorPosReverse = THEME:GetMetric("Player","ReceptorArrowsYReverse")
local ReceptorOffset = ReceptorPosReverse - ReceptorPosNormal
local NotefieldY = (ReceptorPosNormal + ReceptorPosReverse) / 2
local AFTWidth = GAMESTATE:GetNumPlayersEnabled() == 1 and 640 or 320

local function NoteDataFromSong(Steps)
    local Song = GAMESTATE:GetCurrentSong()
    if not Song then return nil end
    local all = Song:GetAllSteps()
    local chartKey = Steps:GetChartKey()
    for i = 1, #all do
        if all[i]:GetChartKey() == chartKey then
            return Song:GetNoteData(i)
        end
    end
    return nil
end

-- Chart note data for the chart we are about to show.
local function NoteDataFor(Steps)
    local ok, data = pcall(function() return Steps:GetNoteData() end)
    if ok and type(data) == "table" and #data > 0 then return data end
    local songData = NoteDataFromSong(Steps)
    if songData and #songData > 0 then return songData end
    return nil
end

-- The Steps this field is currently showing, and the last X multiplier pushed into
-- it. Both are per field (this file runs once per created field).
local ChartSteps = nil
local LastAppliedX = nil

-- Chart scroll ratio at a beat, from the chart's own TimingData (#SCROLLS). Returns
-- 1 for anything we will not model: missing timing, no segments, non-finite or
-- non-positive ratios (negative-scroll gimmicks).
local function ScrollRatioAt(TD, beat)
    if not TD or type(beat) ~= "number" then return 1 end
    local ok, segs = pcall(function() return TD:GetScrolls(true) end)
    if not ok or type(segs) ~= "table" or #segs == 0 then return 1 end

    local ratio = 1
    for i = 1, #segs do
        local b, r = segs[i][1], segs[i][2]
        if type(b) ~= "number" or b > beat then break end
        if type(r) == "number" then ratio = r end
    end

    if type(ratio) ~= "number" or ratio ~= ratio or ratio <= 0 then return 1 end
    return ratio
end

return Def.NoteField {
    Name = "PreviewField_" .. key,
    Player = pnNoteField,
    NoteSkin = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions('ModsLevel_Preferred'):NoteSkin(),
    DrawDistanceAfterTargetsPixels = THEME:GetMetric("Player","DrawDistanceAfterTargetsPixels"),
    DrawDistanceBeforeTargetsPixels = THEME:GetMetric("Player","DrawDistanceBeforeTargetsPixels"),
    YReverseOffsetPixels = ReceptorOffset,
    -- 0 is what other themes use for menu note fields that coexist with a live
    -- gameplay field for the same player (e.g. alphav-dance's player-options field).
    -- Any other value makes the engine treat this as a different field, which crashed
    -- gameplay input in NoteField::DidTapNote (out_of_range).
    FieldID=0,

    InitCommand=function(self)
        self:xy(AFTWidth / 2, 240):addy(NotefieldY):visible(false)
    end,

    -- params.Steps   -- chart to load (defaults to the selected chart)
    -- params.WithData -- set the note data too (false when pre-creating a hidden field)
    BuildCommand=function(self, params)
        local Steps = (params and params.Steps) or GAMESTATE:GetCurrentSteps(pn)
        if not Steps then return end

        -- Last line of defence in front of the only engine call that aborts: a
        -- chart type this player count may not load never reaches ChangeReload.
        -- The rule and the engine reason are in Scripts/01 ChartEligibility.lua.
        ChartEligibility.Probe(Steps, pn)
        if not ChartEligibility.IsAllowed(Steps) then return end

        local withData = not (params and params.WithData == false)

        LoadModule("Player.SetSpeed.lua")(pn)
        local ModString = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptionsString("ModsLevel_Preferred")
        self:ChangeReload(Steps)
        self:ModsFromString(ModString)
        self:GetPlayerOptions("ModsLevel_Current"):StealthPastReceptors(true, true)

        -- The engine's scroll map is not rebuilt for a menu field, so X-mod spacing
        -- loses the chart's #SCROLLS here. Normalize with SpeedTick; reset the
        -- bookkeeping so a rebuild is traced and re-applied.
        ChartSteps = Steps
        LastAppliedX = nil
        self:playcommand("SpeedTick")

        if withData then
            local NoteData = NoteDataFor(Steps)
            if NoteData then self:SetNoteDataFromLua(NoteData) end
        end

        -- Never AutoPlay(true) on a menu field: it leaks ~180 MB/min. The arrows keep
        -- scrolling without it because the field's position comes from the music clock.
        self:AutoPlay(false)
    end,

    -- Called after each build and every poll (via the cache host / fallback heartbeat).
    -- Multiplies the player's X mod by the chart's scroll ratio at the playhead so the
    -- preview's note spacing matches gameplay on charts that rescale #BPMS/#SCROLLS.
    -- No note data or field is rebuilt here: at most a scalar mod is set, and only when
    -- it changes. C-mods ignore scroll segments already; M/A-mods are left alone.
    SpeedTickCommand=function(self)
        if not ChartSteps then return end
        local ps = GAMESTATE:GetPlayerState(pnNoteField)
        if not ps then return end

        local po = ps:GetPlayerOptions("ModsLevel_Preferred")
        if not po then return end

        local timeSpacing = po:TimeSpacing()
        local maxBPM = po:MaxScrollBPM()
        local avgBPM = 0
        local okAvg, avg = pcall(function() return po:AvarageScrollBPM() end)
        if okAvg and type(avg) == "number" then avgBPM = avg end
        if (type(timeSpacing) == "number" and timeSpacing > 0)
            or (type(maxBPM) == "number" and maxBPM > 0)
            or avgBPM > 0 then
            return
        end

        local base = po:XMod()
        if type(base) ~= "number" or base ~= base then
            base = po:ScrollSpeed()
        end
        if type(base) ~= "number" or base ~= base then return end

        local pos = ps:GetSongPosition()
        local beat = pos and pos:GetSongBeatVisible() or 0
        local ratio = ScrollRatioAt(ChartSteps:GetTimingData(), beat)
        local target = base * ratio
        if type(target) ~= "number" or target ~= target then return end

        local cur = self:GetPlayerOptions("ModsLevel_Current")
        if cur and (LastAppliedX == nil or math.abs(LastAppliedX - target) > 0.0001) then
            cur:XMod(target, 10000)
            LastAppliedX = target
        end
    end,
}
