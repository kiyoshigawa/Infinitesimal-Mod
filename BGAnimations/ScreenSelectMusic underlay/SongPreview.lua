local FrameW = 640
local FrameH = 360

local PreviewDelay = THEME:GetMetric("ScreenSelectMusic", "SampleMusicDelay")

-- Video/background display
local t = Def.ActorFrame {
    OnCommand=function(self)
        self:zoom(0.8)
    end,

    Def.Sprite {
        Texture=((_G["Secret"] == true) and THEME:GetPathG("", "MusicWheel/SecretPreviewFrame") or THEME:GetPathG("", "MusicWheel/PreviewFrame"))
    },

    Def.ActorFrame {
        Name="Noise",

        Def.Sprite {
            Texture=THEME:GetPathG("", "Noise"),
            InitCommand=function(self)
                self:zoomto(FrameW, FrameH)
                :texcoordvelocity(24,16)
            end
        },

        Def.BitmapText {
            Name="NextPrevText",
            Font="VCR OSD Mono 40px",
            Text="",
            InitCommand=function(self)
                self:zoom(2):y(-40)
                :shadowlength(4)
                --:shadowcolor(0,0,0)
            end,
            NextSongMessageCommand=function(self)
                self:stoptweening()
                :settext("NEXT")
                :zoom(2.1)
                :easeoutquad(0.2)
                :zoom(2)
            end,
            PreviousSongMessageCommand=function(self)
                self:stoptweening()
                :settext("PREV")
                :zoom(2.1)
                :easeoutquad(0.2)
                :zoom(2)
            end,
        },

        Def.BitmapText {
            Name="Arrows",
            Font="VCR OSD Mono 40px",
            Text=" ",
            InitCommand=function(self)
                arr_width = self:GetWidth()
                self:zoom(2):y(40)
                :shadowlength(4)
                --:shadowcolor(0,0,0)
            end,
            NextSongMessageCommand=function(self)
                self:stoptweening():queuecommand("LoopForward")
            end,
            PreviousSongMessageCommand=function(self)
                self:stoptweening():queuecommand("LoopBackward")
             end,
            LoopForwardCommand=function(self)
                self:settext(">")
                :x(arr_width * -1.5):sleep(0.1)
                :x(0):sleep(0.1)
                :x(arr_width * 1.5):sleep(0.1)
                :queuecommand("LoopForward")
            end,
            LoopBackwardCommand=function(self)
                self:settext("<")
                :x(arr_width * 1.5):sleep(0.1)
                :x(0):sleep(0.1)
                :x(arr_width * -1.5):sleep(0.1)
                :queuecommand("LoopBackward")
            end,
        }
    },

    Def.Sprite {
        InitCommand=function(self) self:Load(nil):queuecommand("Refresh") end,
        CurrentSongChangedMessageCommand=function(self) self:Load(nil):queuecommand("Refresh") end,

        RefreshCommand=function(self)
            self:stoptweening():diffusealpha(0):sleep(PreviewDelay)
            Song = GAMESTATE:GetCurrentSong()
            if Song then
                if GAMESTATE:GetCurrentSong():GetPreviewVidPath() == nil or LoadModule("Config.Load.lua")("ImagePreviewOnly", "Save/OutFoxPrefs.ini") then
                    self:queuecommand("LoadBG")
                else
                    self:queuecommand("LoadAnimated")
                end
            end
        end,

        LoadBGCommand=function(self)
            local Path = Song:GetBackgroundPath()
            if Path and FILEMAN:DoesFileExist(Path) then
                self:LoadFromCached("Background", Path):zoomto(FrameW, FrameH)
                :linear(PreviewDelay):diffusealpha(1)
            else
                self:LoadFromCached("Banner", Song:GetBannerPath()):zoomto(FrameW, FrameH)
                :linear(PreviewDelay):diffusealpha(1)
            end
        end,

        LoadAnimatedCommand=function(self)
            local Path = Song:GetPreviewVidPath()
            if Path and FILEMAN:DoesFileExist(Path) then
                self:Load(Path):zoomto(FrameW, FrameH)
                :linear(PreviewDelay):diffusealpha(1)
            else
                self:queuecommand("LoadBG")
            end
        end
    }
}

-- Chart preview (difficulty stage).
-- Only the theme-owned select screen (ScreenSelectMusicLua) mounts it: the stock
-- ScreenSelectMusic shares this underlay, so the screen marker InfinitesimalPreviewScreen
-- is set by the underlays and read here at run time (never at load time, which would
-- depend on file load order). The pref gates the whole block.
if LoadModule("Config.Load.lua")("ChartPreview", "Save/OutFoxPrefs.ini") then
    -- What the live preview was last built for: the song directory, each joined
    -- side's chart key and each side's preferred noteskin (a noteskin change has to
    -- rebuild the field). Any difference means rebuild.
    local function ChartSignature()
        local Song = GAMESTATE:GetCurrentSong()
        if not Song then return "" end
        local sig = Song:GetSongDir()
        for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
            if GAMESTATE:IsPlayerEnabled(pn) then
                local Steps = GAMESTATE:GetCurrentSteps(pn)
                local pnNoteField = PlayerNumber:Reverse()[pn]
                local skin = GAMESTATE:GetPlayerState(pnNoteField):GetPlayerOptions("ModsLevel_Preferred"):NoteSkin()
                sig = sig .. "|" .. (Steps and Steps:GetChartKey() or "-") .. "@" .. tostring(skin)
            end
        end
        return sig
    end

    local Enabled = false      -- this screen owns a preview; set in OnCommand
    local Shown = false        -- difficulty stage is open
    local BuiltSignature = nil -- signature the live field was last built for

    t[#t+1] = Def.ActorFrame {
        Name = "ChartPreview",

        InitCommand=function(self)
            self:y(0):zoom(0.75):visible(false)
        end,

        SongChosenMessageCommand=function(self)
            if not Enabled then return end
            Shown = true
            -- Force a build on the next poll; the reveal happens after it, so no
            -- empty frame is shown. Never build from inside a handler.
            BuiltSignature = nil
        end,
        SongUnchosenMessageCommand=function(self)
            Shown = false
            self:visible(false)
        end,

        -- ChartDisplay is about to change this side's StepsType, which switches the
        -- engine style. The live field still has the old column count and drawing it
        -- then aborts, so hide now (hiding does not touch message subscriptions) and
        -- let the poll rebuild and reveal it.
        PreviewStepsTypeChangingMessageCommand=function(self)
            self:visible(false)
            -- Force the poll to rebuild and reveal, even if the signature happens to
            -- match (the field must be re-made for the new column count).
            BuiltSignature = nil
        end,

        -- Mount the preview shell here, while the screen's own commands still run:
        -- actors added after a screen is running get InitCommand but never OnCommand
        -- in this engine build, so the shell must exist up front and do its work on
        -- explicit commands.
        OnCommand=function(self)
            Enabled = (InfinitesimalPreviewScreen == true)
            if not Enabled then return end
            self:AddChildFromPath(THEME:GetPathB("", "NotefieldPreview"))
            self:sleep(0.05):queuecommand("PollPreview")
        end,

        PollPreviewCommand=function(self)
            -- Builds happen here, outside any message broadcast: mutating actors in a
            -- handler changes MessageManager's subscriber list mid-broadcast and
            -- segfaults the engine.
            if Shown then
                local preview = self:GetChild("PreviewNotefield")
                if preview then
                    local sig = ChartSignature()
                    if sig ~= BuiltSignature then
                        preview:playcommand("BuildChart")
                        -- Recorded after the build: if a side has no steps yet the
                        -- signature differs again next tick, so it self-heals instead
                        -- of being marked done.
                        BuiltSignature = sig
                        self:visible(true)
                    end
                end
            end
            self:sleep(0.05):queuecommand("PollPreview")
        end,
    }
end

-- Portion dedicated to song stats
t[#t+1] = Def.ActorFrame {
    InitCommand=function(self) self:playcommand("Refresh") end,
    CurrentSongChangedMessageCommand=function(self) self:playcommand("Refresh") end,

    RefreshCommand=function(self)
        if GAMESTATE:GetCurrentSong() then
            local Song = GAMESTATE:GetCurrentSong()

            local TitleText = Song:GetDisplayFullTitle()
            if TitleText == "" then TitleText = "Unknown" end

            local AuthorText = Song:GetDisplayArtist()
            if AuthorText == "" then AuthorText = "Unknown" end

            local BPMRaw = Song:GetDisplayBpms()
            local BPMLow = math.ceil(BPMRaw[1])
            local BPMHigh = math.ceil(BPMRaw[2])
            local BPMDisplay = (BPMLow == BPMHigh and BPMHigh or BPMLow .. "-" .. BPMHigh)

            if Song:IsDisplayBpmRandom() or BPMDisplay == 0 then BPMDisplay = "???" end

            self:GetChild("Title"):settext(TitleText)
            self:GetChild("Artist"):settext(AuthorText)
            self:GetChild("BPM"):settext(BPMDisplay .. " BPM")

            if GAMESTATE:IsEventMode() then
                self:GetChild("Length"):visible(true):settext(SecondsToMMSS(Song:MusicLengthSeconds()))
                self:GetChild("HeartsIcon"):visible(false)
                self:GetChild("Hearts"):visible(false)
            else
                self:GetChild("Length"):visible(false)
                self:GetChild("HeartsIcon"):visible(true)
                self:GetChild("Hearts"):visible(true):settext("x " .. Song:GetStageCost() * GAMESTATE:GetNumPlayersEnabled())
            end
        else
            self:GetChild("Title"):settext("")
            self:GetChild("Artist"):settext("")
            self:GetChild("Length"):settext("")
            self:GetChild("BPM"):settext("")
        end
    end,

    Def.Quad {
        InitCommand=function(self)
            self:zoomto(FrameW, 32):y(-FrameH / 2):valign(0)
            :diffuse(Color.Black):diffusealpha(0.5)
        end
    },

    Def.BitmapText {
        Font="Montserrat semibold 40px",
        Name="Title",
        InitCommand=function(self)
            self:zoom(0.7):halign(0):valign(0)
            :maxwidth(FrameW * 0.8 / self:GetZoom())
            :x(-FrameW / 2 + 6)
            :y(-FrameH / 2 + 6)
        end
    },

    Def.BitmapText {
        Font="Montserrat semibold 40px",
        Name="Length",
        InitCommand=function(self)
            self:zoom(0.7):halign(1):valign(0)
            :maxwidth(FrameW * 0.2 / self:GetZoom())
            :x(FrameW / 2 - 6)
            :y(-FrameH / 2 + 6)
        end
    },

    Def.Sprite {
        Texture=THEME:GetPathG("", "UI/Heart"),
        Name="HeartsIcon",
        InitCommand=function(self)
            self:zoom(0.35):halign(1):valign(0)
            :x(FrameW / 2 - 54)
            :y(-FrameH / 2 + 5)
        end,
    },

    Def.BitmapText {
        Font="Montserrat semibold 40px",
        Name="Hearts",
        InitCommand=function(self)
            self:zoom(0.7):halign(0):valign(0)
            :x(FrameW / 2 - 48)
            :y(-FrameH / 2 + 6)

            local Hearts = GAMESTATE:GetNumStagesLeft(PLAYER_1) + GAMESTATE:GetNumStagesLeft(PLAYER_2)
            self:settext("x " .. (GAMESTATE:IsEventMode() and "∞" or Hearts))
        end
    },

    Def.Quad {
        InitCommand=function(self)
            self:zoomto(FrameW, 32):y(FrameH / 2):valign(1)
            :diffuse(Color.Black):diffusealpha(0.5)
        end
    },

    Def.BitmapText {
        Font="Montserrat semibold 40px",
        Name="Artist",
        InitCommand=function(self)
            self:zoom(0.7):halign(0):valign(1)
            :maxwidth(FrameW * 0.7 / self:GetZoom())
            :x(-FrameW / 2 + 6)
            :y(FrameH / 2 - 6)
        end
    },

    Def.BitmapText {
        Font="Montserrat semibold 40px",
        Name="BPM",
        InitCommand=function(self)
            self:zoom(0.7):halign(1):valign(1)
            :maxwidth(FrameW * 0.3 / self:GetZoom())
            :x(FrameW / 2 - 6)
            :y(FrameH / 2 - 6)
        end
    }
}

return t
