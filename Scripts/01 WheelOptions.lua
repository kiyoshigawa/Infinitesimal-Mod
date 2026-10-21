-- Theme-side registry and state for the engine OptionsList "command window".
--
-- The window itself is the engine's own OptionsList actor: it owns the rows,
-- the cursor, the input handling and the persistence of its lua rows. This
-- module only remembers which actor belongs to which player and whether that
-- window is open, so the wheel and the shared select-screen overlay can ask
-- "is a window open?" without poking at engine state themselves.
--
-- Engine vocabulary (GameButton names, PlayerNumber strings) stays out of here;
-- callers pass PlayerNumber values they already have.

WheelOptions = WheelOptions or {}

WheelOptions.Lists = WheelOptions.Lists or {}   -- PlayerNumber -> OptionsList actor
WheelOptions.IsOpen = WheelOptions.IsOpen or {} -- PlayerNumber -> boolean

local function pname(pn)
    return (pn == PLAYER_2) and "P2" or "P1"
end

-- Called by each window actor when it is created.
function WheelOptions.Attach(pn, actor)
    WheelOptions.Lists[pn] = actor
    WheelOptions.IsOpen[pn] = false
end

function WheelOptions.HasList(pn)
    return WheelOptions.Lists[pn] ~= nil
end

-- Open this player's window. Refuses when there is none (e.g. an unjoined side)
-- or when it is already open: the engine asserts an empty menu stack on Open.
function WheelOptions.Open(pn)
    local list = WheelOptions.Lists[pn]
    if not list or WheelOptions.IsOpen[pn] then return false end

    -- Re-import row values so the window reflects prefs changed elsewhere
    -- (another profile, the operator menu) since the screen was built.
    list:Reset()
    list:Open()
    WheelOptions.IsOpen[pn] = true
    return true
end

function WheelOptions.Close(pn)
    local list = WheelOptions.Lists[pn]
    if not list or not WheelOptions.IsOpen[pn] then return false end
    list:Close()
    WheelOptions.IsOpen[pn] = false
    return true
end

function WheelOptions.AnyOpen()
    for _, open in pairs(WheelOptions.IsOpen) do
        if open then return true end
    end
    return false
end

function WheelOptions.NameFor(pn)
    return "OptionsList" .. pname(pn)
end
