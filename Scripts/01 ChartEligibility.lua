-- Chart eligibility: the one place that decides which chart types this theme may
-- offer to the current number of player sides, and therefore the only rule that
-- may let a chart reach the engine's chart loader.
--
-- Engine facts this encodes (OutFox 20250907, verified from the binary):
--
--   pump style      chart type        cols/player  player count
--   single          pump_single       5            1
--   versus          pump_single       5            2 (one single chart per side)
--   halfdouble      pump_halfdouble   6            1
--   double          pump_double      10            1
--   couple          pump_couple       5            2
--   couple-edit     pump_couple      10            1
--   routine         pump_routine     10            2 (excluded; separate abort)
--
-- The engine resolves the style from (game, number of HUMAN players, chart type)
-- and then builds one column per track in the chart. A couple chart has 10
-- tracks. The one-player couple style (`couple-edit`) is disabled in this build
-- (its menu/eligible flag is 0), so with one player no couple style is
-- compatible at all and the engine never offers those charts. With two players
-- the chart resolves to `couple` (5 columns per player) and aborts at column 5
-- -- that is the crash this module exists to prevent.
--
-- Rule:
--   one player  -> single, halfdouble, double
--   two players -> single only
--   couple and routine are never offered.
--
-- This module deliberately does NOT read AutoSetStyle, the engine's current
-- style, or style types. It is the translation layer between "how many sides are
-- in" and "which charts are safe"; menu code asks here instead of trusting an
-- engine setting to stay put.

ChartEligibility = ChartEligibility or {}

-- Canonical short type names, matching ToEnumShortString(Steps:GetStepsType())
-- ("StepsType_Pump_Single" -> "Pump_Single").
local ALLOWED = {
	[1] = {
		["Pump_Single"]     = true,
		["Pump_Halfdouble"] = true,
		["Pump_Double"]     = true,
	},
	[2] = {
		["Pump_Single"]     = true,
	},
}

-- Known spellings, so a formatting change in the engine cannot silently disable
-- the rule. Keys lowercase, values canonical.
local CANONICAL = {
	pump_single     = "Pump_Single",
	pump_halfdouble = "Pump_Halfdouble",
	pump_double     = "Pump_Double",
	pump_couple     = "Pump_Couple",
	pump_routine    = "Pump_Routine",
}

local function Call(fn)
	local ok, value = pcall(fn)
	if ok then return value end
	return nil
end

local function Log(msg)
	if Trace then Trace("ChartEligibility: " .. msg) end
end

-- Joined sides, the theme's notion of "how many players". Clamped to the two
-- sides pump has. An explicit count may be passed (probe/tests).
function ChartEligibility.PlayerSides(sides)
	sides = tonumber(sides)
	if not sides then
		sides = Call(function() return GAMESTATE:GetNumSidesJoined() end) or 1
	end
	if sides < 1 then sides = 1 end
	if sides > 2 then sides = 2 end
	return sides
end

-- Canonical type key for a Steps, e.g. "Pump_Couple". Tolerant of prefix case,
-- hyphens, and an already-short name.
function ChartEligibility.TypeKey(steps)
	if not steps then return nil end
	local raw = Call(function() return steps:GetStepsType() end)
	if type(raw) ~= "string" then return nil end
	local short = raw:gsub("^[Ss]teps[Tt]ype_", ""):gsub("-", "_")
	return CANONICAL[short:lower()] or short
end

-- Canonical set of types allowed for the given (or current) side count.
function ChartEligibility.AllowedTypes(sides)
	local out = {}
	for key in pairs(ALLOWED[ChartEligibility.PlayerSides(sides)]) do
		out[key] = true
	end
	return out
end

function ChartEligibility.IsAllowedType(key, sides)
	if type(key) ~= "string" then return false end
	return ALLOWED[ChartEligibility.PlayerSides(sides)][key] == true
end

function ChartEligibility.IsAllowed(steps, sides)
	local key = ChartEligibility.TypeKey(steps)
	if not key then return false end
	return ChartEligibility.IsAllowedType(key, sides)
end

-- Order-preserving filter of a Steps array.
function ChartEligibility.FilterAllowed(list, sides)
	local out = {}
	if type(list) ~= "table" then return out end
	for i = 1, #list do
		if ChartEligibility.IsAllowed(list[i], sides) then out[#out+1] = list[i] end
	end
	return out
end

-- Does this song have at least one chart the current player count may use?
function ChartEligibility.HasAllowedChart(song, sides)
	if not song then return false end
	local all = Call(function() return song:GetAllSteps() end)
	if type(all) ~= "table" then return false end
	for i = 1, #all do
		if ChartEligibility.IsAllowed(all[i], sides) then return true end
	end
	return false
end

function ChartEligibility.Describe(steps)
	if not steps then return "nil" end
	local kind = Call(function() return steps:GetStepsType() end) or "?"
	local meter = Call(function() return steps:GetMeter() end)
	return tostring(kind) .. " Lv" .. tostring(meter or "?")
end

-- One line per preview build attempt: what is being loaded, what the engine
-- reports for player counts, and which style it currently holds for that side.
-- Used to close the remaining question about where a rejected chart came from.
function ChartEligibility.Probe(steps, pn)
	local sides = Call(function() return GAMESTATE:GetNumSidesJoined() end) or 0
	local humans = Call(function() return GAMESTATE:GetNumHumanPlayers() end) or 0
	local enabled = Call(function() return GAMESTATE:GetNumPlayersEnabled() end) or 0
	local style = "?"
	if pn then
		local s = Call(function() return GAMESTATE:GetCurrentStyle(pn) end)
		if s then style = s:GetName() end
	end
	local verdict = ChartEligibility.IsAllowed(steps) and "allow" or "reject"
	Log(string.format("%s %s sides=%d humans=%d enabled=%d style=%s",
		verdict, ChartEligibility.Describe(steps), sides, humans, enabled, tostring(style)))
end
