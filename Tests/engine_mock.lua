-- Stand-in for the OutFox engine, used by the tests in this folder that run the
-- song select screen. OutFox does not read this folder.
--
-- It loads the REAL theme scripts (Scripts/) and the REAL screen files
-- (BGAnimations/ScreenSelectMusicFull */MusicWheel.lua, ChartDisplay.lua,
-- GroupSelect.lua) with mocks of the engine globals they use, and drives them
-- like the engine does: commands, broadcast messages, queued commands, input
-- callbacks and the branches evaluated between screens.
--
-- What the mocks model, and where it comes from:
--   * SongUtil.GetPlayableSteps returns nothing while no player is enabled. Seen
--     in the real log: "Most Played: ... (playable right now: 0)" is traced at
--     startup, before anyone joins. With players it follows StepMania 5's
--     GameManager::GetCompatibleStyles: one player gets pump single, half-double
--     and double; two players get single, half-double, couple and routine.
--   * GAMESTATE:SetCurrentSong broadcasts CurrentSongChanged on every call, as
--     StepMania 5's BroadcastOnChangePtr::Set does.
--   * queuecommand runs on the next Tick() (the next frame), playcommand and
--     broadcasts run immediately.
--   * Config.Load.lua / Config.Save.lua work on an in-memory copy of the .ini
--     files, with the same return values as _fallback's modules (strings, or
--     true/false for "true"/"false", or false when the key is missing).
--   * CheckIfUserOrMachineProfile is a copy of _fallback/Scripts/03 ModuleSys.lua.

local M = {}

M.ThemeDir = (arg and arg[0] and arg[0]:match("^(.*)/Tests/[^/]*$")) or "."

-- ------------------------------------------------------------------ helpers
M.Traces, M.Warnings = {}, {}
function Trace(s) M.Traces[#M.Traces + 1] = tostring(s) end
function Warn(s) M.Warnings[#M.Warnings + 1] = tostring(s) end
function ToUpper(s) return string.upper(s) end
function ToLower(s) return string.lower(s) end
function ToEnumShortString(e) local s = tostring(e) return s:match("^[^_]+_(.+)$") or s end
function ivalues(t) local i = 0 return function() i = i + 1 return t[i] end end
function color() return { 1, 1, 1, 1 } end
Color = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end })
function IsArcade() return false end
function IsHome() return true end
function GameOverOrContinue() return "ScreenGameOver" end
Branch = {}

PLAYER_1, PLAYER_2 = "PlayerNumber_P1", "PlayerNumber_P2"
SCREEN_WIDTH, SCREEN_HEIGHT = 1280, 720
SCREEN_LEFT, SCREEN_TOP, SCREEN_RIGHT, SCREEN_BOTTOM = 0, 0, 1280, 720
SCREEN_CENTER_X, SCREEN_CENTER_Y = 640, 360

local Env = {}
function getenv(k) return Env[k] end
function setenv(k, v) Env[k] = v end

-- ------------------------------------------------------------ config files
M.Files = {}
local function ConfigLoad(Key, File)
    local Values = M.Files[File]
    if not Values or Values[Key] == nil then return false end
    local Val = Values[Key]
    if Val == "true" then return true end
    if Val == "false" then return false end
    return Val
end
local function ConfigSave(Key, Value, File)
    M.Files[File] = M.Files[File] or {}
    M.Files[File][Key] = tostring(Value)
end
function LoadModule(Name)
    if Name == "Config.Load.lua" then return ConfigLoad end
    if Name == "Config.Save.lua" then return ConfigSave end
    return function() end
end
function CheckIfUserOrMachineProfile(pn)
    if PROFILEMAN:GetProfileDir(pn) == "" then
        return "Save/MachineProfile/OutFoxPrefsForPlayerp" .. pn + 1
    else
        return PROFILEMAN:GetProfileDir(pn)
    end
end
function M.PlayerPrefs(pn) return "Save/MachineProfile/OutFoxPrefsForPlayerp" .. pn:sub(-1) .. "/OutFoxPrefs.ini" end

-- ------------------------------------------------------------ songs, steps
function M.NewSteps(StepsType, Meter, Description)
    local Steps = {}
    function Steps:GetStepsType() return StepsType end
    function Steps:GetMeter() return Meter end
    function Steps:GetDescription() return Description or "" end
    function Steps:GetChartLength() return 120 end
    return Steps
end

-- Songs are userdata in the engine, and the theme relies on it: deepcopy() in
-- UpdateGroupSorting copies tables but keeps userdata, so GroupsList holds the
-- same Song objects as SONGMAN. A table here would be copied and every
-- "Song == OtherSong" check would fail. Pure Lua 5.4 cannot create userdata, so
-- this borrows one from io.tmpfile() and swaps its metatable for the methods.
local function NewUserdata(Methods)
    local u = io.tmpfile()
    debug.setmetatable(u, { __index = Methods, __name = "Song" })
    return u
end

-- Charts: list of { "StepsType_Pump_Single", Meter, Description }
-- Opts: LastSecond (default 120), ChartLength (default 120)
function M.NewSong(Title, Group, Folder, Charts, Opts)
    Opts = Opts or {}
    local Steps = {}
    for i, c in ipairs(Charts) do
        Steps[i] = M.NewSteps(c[1], c[2], c[3])
        local Length = Opts.ChartLength or 120
        Steps[i].GetChartLength = function() return Length end
    end
    local Dir = "/AdditionalSongs/" .. Group .. "/" .. (Folder or Title) .. "/"
    local Song = {}
    function Song:GetTranslitFullTitle() return Title end
    function Song:GetDisplayMainTitle() return Title end
    function Song:GetDisplayArtist() return "Artist" end
    function Song:GetSongDir() return Dir end
    function Song:GetGroupName() return Group end
    function Song:GetLastSecond() return Opts.LastSecond or 120 end
    function Song:GetAllSteps() return Steps end
    function Song:GetStepsByStepsType(st)
        local r = {}
        for _, s in ipairs(Steps) do if s:GetStepsType() == st then r[#r + 1] = s end end
        return r
    end
    function Song:GetMusicPath() return Dir .. "music.ogg" end
    function Song:GetSampleStart() return 0 end
    function Song:GetSampleLength() return 10 end
    function Song:GetTimingData() return {} end
    return NewUserdata(Song)
end

-- -------------------------------------------------------------- game state
local State
local function Enabled(pn)
    for _, p in ipairs(State.Players) do if p == pn then return true end end
    return false
end

GAMESTATE = {
    GetCurrentGame = function() return { GetName = function() return "pump" end } end,
    GetEnabledPlayers = function() local r = {} for i, p in ipairs(State.Players) do r[i] = p end return r end,
    GetHumanPlayers = function() local r = {} for i, p in ipairs(State.Players) do r[i] = p end return r end,
    GetNumPlayersEnabled = function() return #State.Players end,
    GetNumSidesJoined = function() return #State.Players end,
    IsPlayerEnabled = function(_, pn) return Enabled(pn) end,
    IsSideJoined = function(_, pn) return Enabled(pn) end,
    IsHumanPlayer = function(_, pn) return Enabled(pn) end,
    GetMasterPlayerNumber = function() return State.Players[1] or PLAYER_1 end,
    JoinPlayer = function(_, pn) if not Enabled(pn) then State.Players[#State.Players + 1] = pn table.sort(State.Players) end end,
    UnjoinPlayer = function(_, pn)
        for i = #State.Players, 1, -1 do if State.Players[i] == pn then table.remove(State.Players, i) end end
    end,
    GetCoins = function() return 0 end,
    GetCoinsNeededToJoin = function() return 0 end,
    GetCoinMode = function() return "CoinMode_Home" end,
    IsEventMode = function() return true end,
    IsCourseMode = function() return false end,
    IsAnyHumanPlayerUsingMemoryCard = function() return false end,
    GetNumStagesLeft = function() return 3 end,
    SetCurrentSong = function(_, Song)
        State.Song = Song
        MESSAGEMAN:Broadcast("CurrentSongChanged")
    end,
    GetCurrentSong = function() return State.Song end,
    SetCurrentSteps = function(_, pn, Steps) State.Steps[pn] = Steps end,
    GetCurrentSteps = function(_, pn) return State.Steps[pn] end,
    SetCurrentPlayMode = function() end,
    SetCurrentStyle = function(_, Style) State.Style = Style end,
}

SongUtil = {
    GetPlayableSteps = function(Song)
        local Types
        if #State.Players == 1 then
            Types = { StepsType_Pump_Single = true, StepsType_Pump_Halfdouble = true, StepsType_Pump_Double = true }
        elseif #State.Players == 2 then
            Types = { StepsType_Pump_Single = true, StepsType_Pump_Halfdouble = true,
                      StepsType_Pump_Couple = true, StepsType_Pump_Routine = true }
        else
            Types = {}
        end
        local r = {}
        for _, s in ipairs(Song:GetAllSteps()) do if Types[s:GetStepsType()] then r[#r + 1] = s end end
        return r
    end,
}

SONGMAN = {
    GetAllSongs = function() return State.Songs end,
    GetNumSongs = function() return #State.Songs end,
    GetNumAdditionalSongs = function() return 0 end,
    GetSongGroupNames = function()
        local Seen, r = {}, {}
        for _, s in ipairs(State.Songs) do
            local g = s:GetGroupName()
            if not Seen[g] then Seen[g] = true r[#r + 1] = g end
        end
        return r
    end,
    GetSongsInGroup = function(_, g)
        local r = {}
        for _, s in ipairs(State.Songs) do if s:GetGroupName() == g then r[#r + 1] = s end end
        return r
    end,
    GetSongGroupBannerPath = function() return "" end,
}

PROFILEMAN = {
    GetMachineProfile = function()
        return { GetSongNumTimesPlayed = function(_, Song) return State.Plays[Song] or 0 end }
    end,
    GetProfileDir = function() return "" end,
    GetNumLocalProfiles = function() return 0 end,
}

THEME = {
    GetPathG = function(_, a, b) return "G/" .. a .. b end,
    GetPathS = function(_, a, b) return "S/" .. a .. b end,
    HasMetric = function() return false end,
    GetMetric = function() return 0 end,
    GetCurrentThemeDirectory = function() return "/Themes/Infinitesimal/" end,
}
PREFSMAN = { GetPreference = function() return false end }
SOUND = { StopMusic = function() end, PlayMusicPart = function() end, DimMusic = function() end }

-- ------------------------------------------------------ actors and screens
Def = setmetatable({}, { __index = function(_, Class) return function(t) t.Class = Class return t end end })
local ActorDefMeta = { __concat = function(a, b) for k, v in pairs(b) do a[k] = v end return a end }
function LoadActor(Path) return setmetatable({ Path = Path }, ActorDefMeta) end

local Queue = {}
-- An actor as seen by its commands: every method returns the actor itself,
-- playcommand/queuecommand run the commands of its definition.
function M.NewActor(Definition)
    local Actor = {}
    setmetatable(Actor, { __index = function(_, k)
        if type(k) == "number" then return Actor end
        if k == "playcommand" then
            return function(s, Name, Params)
                local f = Definition[Name .. "Command"]
                if f then f(s, Params) end
                return s
            end
        end
        if k == "queuecommand" then
            return function(s, Name)
                Queue[#Queue + 1] = function()
                    local f = Definition[Name .. "Command"]
                    if f then f(s) end
                end
                return s
            end
        end
        return function(s) return s end
    end })
    return Actor
end

-- Runs the commands queued so far, like the engine does on the next frames.
function M.Tick()
    local Guard = 0
    while #Queue > 0 do
        Guard = Guard + 1
        if Guard > 1000 then error("queued commands never settle") end
        table.remove(Queue, 1)()
    end
end

M.Layers = {}
MESSAGEMAN = {
    Broadcast = function(_, Message, Params)
        for _, Layer in ipairs(M.Layers) do
            local f = Layer.Def[Message .. "MessageCommand"]
            if f then f(Layer.Actor, Params) end
        end
    end,
}
function M.Broadcast(Message, Params) MESSAGEMAN:Broadcast(Message, Params) M.Tick() end

local function NewScreen(Name)
    local Screen = { Name = Name, Callbacks = {} }
    function Screen:AddInputCallback(f) self.Callbacks[#self.Callbacks + 1] = f end
    function Screen:PostScreenMessage() end
    function Screen:Cancel() self.Cancelled = true end
    function Screen:StartTransitioningScreen(Message) self.Transition = Message end
    function Screen:SetNextScreenName(n) self.NextScreen = n end
    function Screen:GetName() return self.Name end
    return Screen
end
SCREENMAN = { GetTopScreen = function() return M.Screen end, SystemMessage = function() end }

-- Loads ScreenSelectMusicFull: the actor files that read or change the song
-- list and the selected chart, in the order the engine loads them (underlay,
-- then overlay), then runs their InitCommand and OnCommand.
function M.LoadSelectMusic()
    M.Screen = NewScreen("ScreenSelectMusicFull")
    M.Layers, Queue = {}, {}
    local Files = {
        { "BGAnimations/ScreenSelectMusicFull underlay/MusicWheel.lua" },
        { "BGAnimations/ScreenSelectMusicFull underlay/ChartDisplay.lua", 12 },
        { "BGAnimations/ScreenSelectMusicFull overlay/GroupSelect.lua" },
    }
    for _, f in ipairs(Files) do
        local Chunk = assert(loadfile(M.ThemeDir .. "/" .. f[1]))
        local Definition = Chunk(f[2])
        M.Layers[#M.Layers + 1] = { Name = f[1], Def = Definition, Actor = M.NewActor(Definition) }
    end
    for _, Layer in ipairs(M.Layers) do
        if Layer.Def.InitCommand then Layer.Def.InitCommand(Layer.Actor) end
    end
    for _, Layer in ipairs(M.Layers) do
        if Layer.Def.OnCommand then Layer.Def.OnCommand(Layer.Actor) end
    end
    M.Tick()
end

-- The screen goes away (to gameplay, or back): every layer runs OffCommand.
function M.LeaveScreen()
    for _, Layer in ipairs(M.Layers) do
        if Layer.Def.OffCommand then Layer.Def.OffCommand(Layer.Actor) end
    end
    M.Tick()
end

function M.Press(pn, Button)
    local Event = { PlayerNumber = pn, GameButton = Button, button = Button, type = "InputEventType_FirstPress" }
    for _, f in ipairs(M.Screen.Callbacks) do f(Event) end
    M.Tick()
end

-- ------------------------------------------------------------------- boot
-- Resets the engine state and loads the theme scripts in the order the engine
-- does (alphabetical). Only the scripts the song select screen depends on.
function M.Boot(Fixture)
    State = { Players = {}, Songs = Fixture.Songs, Plays = Fixture.Plays or {}, Steps = {} }
    M.Traces, M.Warnings, M.Files, M.Layers, Queue, Env = {}, {}, {}, {}, {}, {}
    M.Files["Save/OutFoxPrefs.ini"] = {
        ShowUCSCharts = "true", ShowQuestCharts = "true", ShowHiddenCharts = "true",
        BasicMode = "false", CenterChartList = "true", WrapChartScroll = "false",
    }
    local Scripts = { "01 Sorting.lua", "03 CustomBranches.lua", "04 Main.lua" }
    local p = io.popen('ls "' .. M.ThemeDir .. '/Scripts"')
    for Name in p:lines() do if Name:match("^99 .*%.lua$") then Scripts[#Scripts + 1] = Name end end
    p:close()
    table.sort(Scripts)
    M.Scripts = Scripts
    for _, Name in ipairs(Scripts) do dofile(M.ThemeDir .. "/Scripts/" .. Name) end
end

-- What happens from the moment the game starts until song select, as seen in
-- the logs: ScreenSystemLayer builds the master list before anyone joins, then
-- ScreenTitleMenu (see TitleMenu).
function M.StartGame(...)
    AssembleGroupSorting() -- ScreenSystemLayer overlay, InitCommand
    return M.TitleMenu(...)
end

-- ScreenTitleMenu evaluates its ChoiceGameStart metric (CustomBranch.StartGame())
-- when it loads, with nobody joined; its underlay resets the remembered
-- positions; then the players press Start. Players default to { PLAYER_1 }.
function M.TitleMenu(Players)
    for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do GAMESTATE:UnjoinPlayer(pn) end
    local Next = CustomBranch.StartGame() -- ScreenTitleMenu metric, at load time
    ResetLuaMods(PLAYER_1)                -- ScreenTitleMenu underlay, OnCommand
    ResetLuaMods(PLAYER_2)
    for _, pn in ipairs(Players or { PLAYER_1 }) do GAMESTATE:JoinPlayer(pn) end
    return Next
end

-- After gameplay: ScreenEvaluation, then ScreenProfileSave, whose NextScreen
-- metric is CustomBranch.AfterProfileSave().
function M.FinishStage() return CustomBranch.AfterProfileSave() end

-- ------------------------------------------------------- user interaction
local function Wrap(i, n) return (i - 1) % n + 1 end

-- Opens the group wheel and moves to MainName/SubName like a player would,
-- reading the names on screen (GroupsList). GroupSelect.lua opens the wheel
-- on LastGroupMainIndex/LastGroupSubIndex.
function M.SelectGroup(pn, MainName, SubName)
    M.Broadcast("Code", { Name = "GroupSelectPad1", PlayerNumber = pn })
    local Main, Sub = LastGroupMainIndex, LastGroupSubIndex
    if GroupsList[Main].Name ~= MainName then
        M.Press(pn, "UpLeft") -- focus the main wheel
        for _ = 1, #GroupsList do
            if GroupsList[Main].Name == MainName then break end
            M.Press(pn, "Right")
            Main, Sub = Wrap(Main + 1, #GroupsList), 1
        end
        assert(GroupsList[Main].Name == MainName, "no main group " .. MainName)
        M.Press(pn, "Start") -- focus the sub wheel
    end
    for _ = 1, #GroupsList[Main].SubGroups do
        if GroupsList[Main].SubGroups[Sub].Name == SubName then break end
        M.Press(pn, "Right")
        Sub = Wrap(Sub + 1, #GroupsList[Main].SubGroups)
    end
    if GroupsList[Main].SubGroups[Sub].Name ~= SubName then return false end
    M.Press(pn, "Start")
    return true
end

-- Moves the song wheel until Song is the current song. Returns false if the
-- current list does not have it.
function M.ScrollToSong(pn, Song)
    for _ = 1, 500 do
        if GAMESTATE:GetCurrentSong() == Song then return true end
        M.Press(pn, "Right")
    end
    return false
end

-- Start on the song, then move the chart cursor ChartMoves steps (negative =
-- left), then Start twice (choose, confirm) and leave the screen.
function M.PlayCurrentSong(pn, ChartMoves)
    M.Press(pn, "Start")
    ChartMoves = ChartMoves or 0
    for _ = 1, math.abs(ChartMoves) do M.Press(pn, ChartMoves > 0 and "Right" or "Left") end
    local Steps = GAMESTATE:GetCurrentSteps(pn)
    M.Press(pn, "Start")
    M.Press(pn, "Start")
    assert(M.Screen.Transition == "SM_GoToNextScreen", "the screen did not go to gameplay")
    M.LeaveScreen()
    return Steps
end

-- Start on the song, move the chart cursor to the chart with this meter and
-- description, play it and leave the screen. Returns the steps played, or nil
-- (staying on the chart list) if the song has no such chart.
function M.PlayChart(pn, Meter, Description)
    local function Wanted()
        local Steps = GAMESTATE:GetCurrentSteps(pn)
        return Steps and Steps:GetMeter() == Meter and Steps:GetDescription() == Description
    end
    M.Press(pn, "Start")
    local Charts = #SongUtil.GetPlayableSteps(GAMESTATE:GetCurrentSong())
    for _ = 1, Charts do M.Press(pn, "Left") end -- to the first chart (no wrapping)
    for _ = 1, Charts do
        if Wanted() then break end
        M.Press(pn, "Right")
    end
    if not Wanted() then return nil end
    local Steps = GAMESTATE:GetCurrentSteps(pn)
    M.Press(pn, "Start")
    M.Press(pn, "Start")
    assert(M.Screen.Transition == "SM_GoToNextScreen", "the screen did not go to gameplay")
    M.LeaveScreen()
    return Steps
end

-- ------------------------------------------------------------ assertions
M.Failures, M.Checks = 0, 0
function M.Check(Cond, Msg)
    M.Checks = M.Checks + 1
    if Cond then print("  ok   " .. Msg) else M.Failures = M.Failures + 1 print("  FAIL " .. Msg) end
end
function M.Finish()
    print(string.format("\n%d checks, %d failed", M.Checks, M.Failures))
    os.exit(M.Failures == 0 and 0 or 1)
end

function M.ChartName(Steps)
    if not Steps then return "none" end
    local Type = ToEnumShortString(Steps:GetStepsType()):gsub("^Pump_", "")
    return Type .. " " .. Steps:GetMeter()
end

return M
