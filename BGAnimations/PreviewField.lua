-- One chart-preview NoteField for one player.
--
-- Added into that player's ActorFrameTexture by NotefieldPreview.lua, which sets the
-- global InfinitesimalPreviewFieldPN first and then calls the "Build" command below.
-- The field is created once per (player, StepsType, noteskin) and then reused for
-- chart changes: creating a field costs 120-570 ms, updating a live one a few tens of
-- milliseconds.
--
-- A chart change always does both halves, because each half alone leaves the preview
-- blank in this engine build:
--   * ChangeReload(Steps) rebuilds the columns/receptors/noteskin and loads the chart.
--   * SetNoteDataFromLua(<chart data>) is what makes the note rows refresh on screen.
-- ChangeReload alone updates only the receptors; SetNoteDataFromLua alone keeps the old
-- chart's rows. Both together render the new chart.
--
-- Note data source: Steps:GetNoteData() first, falling back to Song:GetNoteData() by
-- chart key. Song:GetNoteData() is lazily populated and returns an empty table for a
-- chart the song has not decoded yet, so it cannot be the only source.
--
-- Speed mods are applied after the reload with ModsFromString: applying them before it
-- lets the reload reset them, which produces inconsistent note spacing.

local pn = InfinitesimalPreviewFieldPN
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
    local key = Steps:GetChartKey()
    for i = 1, #all do
        if all[i]:GetChartKey() == key then
            return Song:GetNoteData(i)
        end
    end
    return nil
end

-- Chart note data, keyed by the chart we are about to show.
local function NoteDataFor(Steps)
    local ok, data = pcall(function() return Steps:GetNoteData() end)
    if ok and type(data) == "table" and #data > 0 then return data end
    local songData = NoteDataFromSong(Steps)
    if songData and #songData > 0 then return songData end
    return nil
end

return Def.NoteField {
    Name = "PreviewField",
    Player = pnNoteField,
    NoteSkin = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions('ModsLevel_Preferred'):NoteSkin(),
    DrawDistanceAfterTargetsPixels = THEME:GetMetric("Player","DrawDistanceAfterTargetsPixels"),
    DrawDistanceBeforeTargetsPixels = THEME:GetMetric("Player","DrawDistanceBeforeTargetsPixels"),
    YReverseOffsetPixels = ReceptorOffset,
    FieldID=1,

    InitCommand=function(self)
        self:xy(AFTWidth / 2, 240):addy(NotefieldY)
    end,

    BuildCommand=function(self)
        local Steps = GAMESTATE:GetCurrentSteps(pn)
        if not Steps then return end

        LoadModule("Player.SetSpeed.lua")(pn)
        local ModString = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptionsString("ModsLevel_Preferred")
        self:ChangeReload(Steps)
        self:ModsFromString(ModString)
        self:GetPlayerOptions("ModsLevel_Current"):StealthPastReceptors(true, true)

        local NoteData = NoteDataFor(Steps)
        if NoteData then self:SetNoteDataFromLua(NoteData) end

        -- Never AutoPlay(true) on a menu field: it leaks ~180 MB/min. The arrows keep
        -- scrolling without it because the field's position comes from the music clock.
        self:AutoPlay(false)
    end,
}
