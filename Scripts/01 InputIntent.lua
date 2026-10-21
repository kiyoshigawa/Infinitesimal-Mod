-- Theme-side menu vocabulary for the pump game.
--
-- Screens ask for an *intent* ("this press means back"), never for an engine
-- button name, so engine GameButton strings live in exactly one place.
--
-- Only buttons pump can actually emit are listed: the pad panels
-- (Center/UpLeft/UpRight/DownLeft/DownRight), the dedicated menu buttons
-- (MenuUp/MenuDown/MenuLeft/MenuRight) and the system buttons
-- (Start/Select/Back). Plain Left/Right/Up/Down are only bindable under other
-- games, and MenuStart/MenuSelect/MenuBack do not exist in OutFox, so they are
-- deliberately absent: an unknown button maps to nil, not to an alias.
--
-- A non-pump game would need a second table keyed off
-- GAMESTATE:GetCurrentGame():GetName(); do not sprinkle untestable aliases into
-- the pump maps below.

InputIntent = InputIntent or {}

-- Intent names. Compare against these, not against string literals.
InputIntent.Intent = {
    Forward = "Forward", -- wheel/difficulty: open bucket, choose song, confirm chart
    Back    = "Back",    -- one level out / cancel / unlock
    Left    = "Left",
    Right   = "Right",
    Select  = "Select",  -- list menus: join / confirm
    Prev    = "Prev",    -- list menus: previous item
    Next    = "Next",    -- list menus: next item
}

local Intent = InputIntent.Intent

-- Horizontal menus: the music wheel (folder and song levels) and the
-- difficulty list. Up is forward, Down is back.
local HORIZONTAL = {
    Center    = Intent.Forward,
    Start     = Intent.Forward,
    MenuUp    = Intent.Forward,

    UpLeft    = Intent.Back,
    UpRight   = Intent.Back,
    Back      = Intent.Back,
    MenuDown  = Intent.Back,

    DownLeft  = Intent.Left,
    MenuLeft  = Intent.Left,

    DownRight = Intent.Right,
    MenuRight = Intent.Right,
}

-- List menus (profile select): up/down navigate like left/right; only
-- Center/Start confirm and only Back/UpLeft/UpRight leave.
local VERTICAL = {
    Center    = Intent.Select,
    Start     = Intent.Select,

    MenuUp    = Intent.Prev,
    MenuLeft  = Intent.Prev,
    DownLeft  = Intent.Prev,

    MenuDown  = Intent.Next,
    MenuRight = Intent.Next,
    DownRight = Intent.Next,

    Back      = Intent.Back,
    UpLeft    = Intent.Back,
    UpRight   = Intent.Back,
}

-- Joining is narrower than selecting: only the pad center or Start.
local JOIN = {
    Center = true,
    Start  = true,
}

function InputIntent.Horizontal(button)
    if not button then return nil end
    return HORIZONTAL[button]
end

function InputIntent.Vertical(button)
    if not button then return nil end
    return VERTICAL[button]
end

function InputIntent.IsJoin(button)
    return button ~= nil and JOIN[button] == true
end

-- Engine input event types (Docs/Luadoc/Lua.xml, Enum InputEventType).
-- "First press" is defined as neither repeat nor release so it does not depend
-- on the exact FirstPress spelling.
function InputIntent.IsRelease(event)
    return event.type == "InputEventType_Release"
end

function InputIntent.IsRepeat(event)
    return event.type == "InputEventType_Repeat"
end

function InputIntent.IsFirstPress(event)
    return event.type ~= "InputEventType_Repeat"
        and event.type ~= "InputEventType_Release"
end
