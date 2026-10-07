function WheelTransform (self, OffsetFromCenter, ItemIndex, NumItems) 
    local Spacing = math.abs(math.sin(OffsetFromCenter / math.pi))
    self:x(OffsetFromCenter * (250 - Spacing * 100))
    self:rotationy(clamp(OffsetFromCenter * 36, -85, 85))
    self:z(-math.abs(OffsetFromCenter))
    self:zoom(clamp(1.1 - (math.abs(OffsetFromCenter) / 3), 0.8, 1.1))
end


function WheelTransformGroup (self, OffsetFromCenter, ItemIndex, NumItems) 
    local Spacing = math.abs(math.sin(OffsetFromCenter / math.pi))
    self.container:x(OffsetFromCenter * (250 - Spacing * 100))
    self.container:rotationy(clamp(OffsetFromCenter * 30, -85, 85))
    
    self.container:zoom(clamp(1.1 - (math.abs(OffsetFromCenter) / 3), 0.8, 1.1))
end


-- Theme-side join vocabulary. Engine button names and GAMESTATE calls live here
-- so screens express intent ("this press means join"), not engine API. event.button
-- is the engine GameButton name, hence Center/Start (MenuStart is a menu-button
-- name and is never emitted here).
JoinUtils = JoinUtils or {}

local JOIN_BUTTONS = { Center = true, Start = true }

function JoinUtils.IsJoinButton(button)
    return JOIN_BUTTONS[button] == true
end

-- Can this side join right now? Uses engine state (IsSideJoined), not theme state.
function JoinUtils.CanJoin(pn)
    return not GAMESTATE:IsSideJoined(pn)
        and GAMESTATE:GetCoins() >= GAMESTATE:GetCoinsNeededToJoin()
end

-- Set by TryJoin to the side that just joined, so ScreenSelectProfile can tell a
-- freshly-joined side from one that was already signed in. Read-and-cleared there.
JoinUtils.LastJoinedPlayer = nil

-- Join the side and notify the screen if (and only if) the press was a real join.
function JoinUtils.TryJoin(pn, button)
    if not JoinUtils.IsJoinButton(button) or not JoinUtils.CanJoin(pn) then return false end
    JoinUtils.LastJoinedPlayer = pn
    GAMESTATE:JoinPlayer(pn)
    GAMESTATE:InsertCoin(-(GAMESTATE:GetCoinsNeededToJoin()))
    MESSAGEMAN:Broadcast("PlayerJoined", { Player = pn })
    return true
end