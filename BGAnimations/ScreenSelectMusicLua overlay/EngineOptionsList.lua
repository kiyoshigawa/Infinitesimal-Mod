-- Engine "command window" for the Lua song wheel.
--
-- One engine OptionsList actor per joined player, created with the screen. The
-- engine owns the rows, the cursor, the input and the settings; this file only
-- builds the actors, parks them at the command-window position and keeps
-- WheelOptions' open/closed state in sync with the engine's broadcasts.
--
-- Positioning mirrors [ScreenSelectMusic] OptionsListP1OnCommand /
-- OptionsListP2OnCommand (x,200 / SCREEN_RIGHT-200, y at two slightly different
-- screen-centre offsets, draworder 100). Those metrics are applied by the C++
-- ScreenSelectMusic via ActorUtil::LoadAllCommands; a Lua-created actor gets no
-- metrics commands, so the values are set here and must stay in step.
--
-- The visible frame, its masks, the slide-in/out and the sounds all come from
-- BGAnimations/ScreenSelectMusic overlay/OptionsList.lua, which is shared with
-- the stock screen and finds these actors through WheelOptions.

local function PlayerAttr(pn)
    -- Read by OptionsList::LoadFromNode: only this exact string means P2.
    return (pn == PLAYER_2) and "PlayerNumber_P2" or "PlayerNumber_P1"
end

local function WindowX(pn)
    return (pn == PLAYER_2) and (SCREEN_RIGHT - 200) or 200
end

local function WindowY(pn)
    return (pn == PLAYER_2) and (SCREEN_CENTER_Y - 160) or (SCREEN_CENTER_Y - 180)
end

local function OptionsWindow(pn)
    return Def.OptionsList {
        Name = WheelOptions.NameFor(pn),
        Player = PlayerAttr(pn),

        InitCommand = function(self)
            self:x(WindowX(pn)):y(WindowY(pn)):draworder(100)
            WheelOptions.Attach(pn, self)
        end,

        OnCommand = function(self)
            -- Import the stored pref values now; WheelOptions.Open does the
            -- same again on every open so external changes are picked up.
            self:Reset()
        end,

        -- Played by the engine: Open() ends with "TweenOn", Close() with
        -- "TweenOff". The OptionsList Lua object exposes Actor methods (not
        -- ActorFrame's playcommandonleaves), so fade the window as a whole.
        TweenOnCommand = function(self)
            self:stoptweening():diffusealpha(0):linear(0.1):diffusealpha(1)
        end,
        TweenOffCommand = function(self)
            self:stoptweening():linear(0.1):diffusealpha(0)
        end,

        -- Back closes the window. The engine's OptionsList input never handles
        -- GAME_BUTTON_BACK, and while the window is open it consumes every
        -- press before the screen sees it, so the [OptionsList] code set is the
        -- only hook available. See CodeCloseOpList in metrics.ini.
        --
        -- Never close synchronously here: OptionsList::Input calls
        -- GetCurrentHandler() right after the code handler, which asserts the
        -- menu stack is non-empty. Defer to the next update instead.
        CodeMessageCommand = function(self, params)
            if params.Name == "CloseOpList" then
                self:queuecommand("CloseFromBack")
            end
        end,
        CloseFromBackCommand = function(self)
            WheelOptions.Close(pn)
        end,

        -- The engine also closes the window itself (Select / Exit row), so the
        -- shared state follows the broadcasts rather than only our own calls.
        OptionsListOpenedMessageCommand = function(self, params)
            if params and params.Player == pn then WheelOptions.IsOpen[pn] = true end
        end,
        OptionsListClosedMessageCommand = function(self, params)
            if params and params.Player == pn then WheelOptions.IsOpen[pn] = false end
        end,
    }
end

local t = Def.ActorFrame {}

for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
    t[#t+1] = OptionsWindow(pn)
end

return t
