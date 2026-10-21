-- Per-profile resume record + difficulty memory for the theme-owned music wheel.
--
-- File: Save/LocalProfiles/<id>/ResumeState.ini
--
-- Schema 2 (current) keys:
--   WheelSchema      schema version (integer)
--   WheelBucketKind  "custom" / "genre" / "folder" (bucket the wheel was in)
--   WheelBucketName  display name of that bucket
--   WheelSongDir     Song:GetSongDir() of the last song started
--   WheelStepsType   Steps:GetStepsType() of its chart, e.g. StepsType_Pump_Double
--   WheelMeter       Steps:GetMeter() of its chart (integer level)
--   WheelChartKey    Steps:GetChartKey() of its chart (exact chart identity)
--
-- The record has two independent uses: where the wheel was left (bucket + song) and
-- the difficulty memory (type + meter + chart). A schema-1 record had no type/meter,
-- so migration recovers them from the song library.
--
-- Owned here so the format, the migrations and the snap rule have a single home.
-- MusicWheel only records/saves; ChartDisplay only asks for an index.

WheelResume = WheelResume or {}

local CURRENT_SCHEMA = 2
local FILE_NAME = "ResumeState.ini"

WheelResume.CurrentSchema = CURRENT_SCHEMA

-- Steps type ladder for the snap. Type distance outranks level distance, so a
-- remembered Single prefers a Halfdouble chart (1 step) over a Double (2 steps).
-- A type missing from this table is treated as one step from everything: it can
-- still be a fallback, but never beats an exact type match.
local TYPE_RANK = {
    StepsType_Pump_Single     = 0,
    StepsType_Pump_Halfdouble = 1,
    StepsType_Pump_Double     = 2,
}

local UNKNOWN_TYPE_DISTANCE = 1

local function TypeDistance(a, b)
    if a == b then return 0 end
    local ra, rb = TYPE_RANK[a], TYPE_RANK[b]
    if ra and rb then return math.abs(ra - rb) end
    return UNKNOWN_TYPE_DISTANCE
end

-- Index in `charts` (a Steps array, already filtered and sorted by the caller) that
-- best matches `record`:
--   1. the exact chart, when the record names one that is present;
--   2. else the smallest (steps-type distance, |meter - record.Meter|, meter, index).
-- Returns nil when the record carries no usable meter or there are no charts; the
-- caller then keeps its own default.
function WheelResume.NearestIndex(charts, record)
    if type(charts) ~= "table" or #charts == 0 then return nil end
    if type(record) ~= "table" then return nil end

    -- Same song, same chart: nothing to guess.
    if type(record.ChartKey) == "string" and record.ChartKey ~= "" then
        for i = 1, #charts do
            if charts[i]:GetChartKey() == record.ChartKey then return i end
        end
    end

    local wantMeter = tonumber(record.Meter)
    if not wantMeter then return nil end
    local wantType = record.StepsType

    local bestIndex, bestTypeDist, bestDelta, bestMeter
    for i = 1, #charts do
        local chart = charts[i]
        local meter = tonumber(chart:GetMeter()) or 0
        local typeDist = TypeDistance(wantType, chart:GetStepsType())
        local delta = math.abs(meter - wantMeter)

        if not bestIndex
            or typeDist < bestTypeDist
            or (typeDist == bestTypeDist and delta < bestDelta)
            or (typeDist == bestTypeDist and delta == bestDelta and meter < bestMeter) then
            bestIndex, bestTypeDist, bestDelta, bestMeter = i, typeDist, delta, meter
        end
    end
    return bestIndex
end

-- ------------------------------------------------------------ migration -----
-- Bring any older raw record up to CURRENT_SCHEMA. Each entry upgrades N -> N+1 and
-- returns the raw table; adding a migration is one function plus a schema bump.
-- Pure (no file I/O) so the chain can be exercised standalone.

local function NormalizeDir(dir)
    if type(dir) ~= "string" then return "" end
    local s = dir:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^/+", ""):gsub("/+$", "")
    return s:lower()
end

-- Resolve a stored song directory against the loaded library. Compares
-- Song:GetSongDir() (normalized) rather than relying on SONGMAN:FindSong's accepted
-- input format.
local function FindSongByDir(dir)
    local want = NormalizeDir(dir)
    if want == "" then return nil end
    for song in ivalues(SONGMAN:GetAllSongs() or {}) do
        if NormalizeDir(song:GetSongDir()) == want then return song end
    end
    return nil
end

local function FindChartByKey(song, key)
    if not song or type(key) ~= "string" or key == "" then return nil end
    for steps in ivalues(song:GetAllSteps() or {}) do
        if steps:GetChartKey() == key then return steps end
    end
    return nil
end

local function FindChartByDifficulty(song, difficulty)
    if not song or type(difficulty) ~= "string" or difficulty == "" then return nil end
    for steps in ivalues(song:GetAllSteps() or {}) do
        if ToEnumShortString(steps:GetDifficulty()) == difficulty then return steps end
    end
    return nil
end

-- Migration 1 -> 2: schema 1 stored the chart fingerprint and the difficulty name
-- but no level, so recover the real (steps type, meter) from the library. When the
-- song or chart is gone both stay empty (the snap then starts at the first chart)
-- and the bucket/song resume fields are kept.
local function Migrate1To2(raw)
    local rec = {
        Schema = 2,
        BucketKind = raw.BucketKind,
        BucketName = raw.BucketName,
        SongDir = raw.SongDir,
    }
    local song = FindSongByDir(raw.SongDir)
    local steps = FindChartByKey(song, raw.ChartKey) or FindChartByDifficulty(song, raw.Difficulty)
    if steps then
        rec.StepsType = steps:GetStepsType()
        rec.Meter = steps:GetMeter()
        rec.ChartKey = steps:GetChartKey()
    end
    return rec
end

local MIGRATIONS = {
    [1] = Migrate1To2,
}

-- Returns a current-schema record, or nil when the raw table is unusable: missing or
-- unknown schema, a record written by a newer theme, or an incomplete bucket/song.
function WheelResume.Migrate(raw)
    if type(raw) ~= "table" then return nil end
    local version = tonumber(raw.Schema)
    if not version or version < 1 or version > CURRENT_SCHEMA then return nil end

    while version < CURRENT_SCHEMA do
        local step = MIGRATIONS[version]
        if not step then return nil end
        raw = step(raw)
        version = version + 1
        raw.Schema = version
    end

    if type(raw.BucketKind) ~= "string" or raw.BucketKind == ""
        or type(raw.BucketName) ~= "string" or raw.BucketName == ""
        or type(raw.SongDir) ~= "string" or raw.SongDir == "" then
        return nil
    end

    return {
        Schema = CURRENT_SCHEMA,
        BucketKind = raw.BucketKind,
        BucketName = raw.BucketName,
        SongDir = raw.SongDir,
        StepsType = type(raw.StepsType) == "string" and raw.StepsType or nil,
        Meter = tonumber(raw.Meter),
        ChartKey = type(raw.ChartKey) == "string" and raw.ChartKey or nil,
    }
end

-- ------------------------------------------------------------------ I/O -----
-- The whole file is rewritten in one pass, so keys dropped by a migration actually
-- disappear (Config.Save only ever appends/overwrites single keys).

local RAW_KEYS = {
    "WheelSchema",
    "WheelBucketKind",
    "WheelBucketName",
    "WheelSongDir",
    "WheelChartKey",
    "WheelDifficulty",
    "WheelStepsType",
    "WheelMeter",
}

local function RecordPath(dir)
    if type(dir) ~= "string" or dir == "" then return nil end
    return dir .. "/" .. FILE_NAME
end

local function ReadRaw(path)
    local get = LoadModule("Config.Load.lua")
    local raw = {}
    for _, key in ipairs(RAW_KEYS) do raw[key] = get(key, path) end

    local function str(value)
        return (type(value) == "string" and value ~= "") and value or nil
    end

    return {
        Schema = tonumber(raw.WheelSchema) or 0,
        BucketKind = str(raw.WheelBucketKind),
        BucketName = str(raw.WheelBucketName),
        SongDir = str(raw.WheelSongDir),
        ChartKey = str(raw.WheelChartKey),
        Difficulty = str(raw.WheelDifficulty),
        StepsType = str(raw.WheelStepsType),
        Meter = tonumber(raw.WheelMeter),
    }
end

-- Values are written into a flat "key=value" file, so they must stay single-line.
local function Clean(value)
    if value == nil then return "" end
    return (tostring(value):gsub("[\r\n]", " "))
end

local function WriteRecord(path, rec)
    local meter = tonumber(rec.Meter)
    local lines = {
        "WheelSchema=" .. tostring(CURRENT_SCHEMA),
        "WheelBucketKind=" .. Clean(rec.BucketKind),
        "WheelBucketName=" .. Clean(rec.BucketName),
        "WheelSongDir=" .. Clean(rec.SongDir),
        "WheelStepsType=" .. Clean(rec.StepsType),
        "WheelMeter=" .. (meter and tostring(math.floor(meter)) or ""),
        "WheelChartKey=" .. Clean(rec.ChartKey),
    }

    local file = RageFileUtil.CreateRageFile()
    if file:Open(path, 2) then
        file:Write(table.concat(lines, "\n") .. "\n")
    end
    file:Close()
    file:destroy()
end

-- Load a profile's record, upgrading and rewriting it once when it is older than
-- CURRENT_SCHEMA. Returns nil when there is no usable record.
function WheelResume.Load(dir)
    local path = RecordPath(dir)
    if not path or not FILEMAN:DoesFileExist(path) then return nil end

    local raw = ReadRaw(path)
    local rec = WheelResume.Migrate(raw)
    if not rec then return nil end

    if tonumber(raw.Schema) ~= CURRENT_SCHEMA then WriteRecord(path, rec) end
    return rec
end

function WheelResume.Save(dir, rec)
    local path = RecordPath(dir)
    if not path or type(rec) ~= "table" then return end
    WriteRecord(path, rec)
end
