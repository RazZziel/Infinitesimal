-- Test for "Scripts/99 MostPlayed.lua" (the "Most Played" group).
--
-- Loads the REAL "Scripts/01 Sorting.lua" of the theme (plus
-- "Scripts/99 MostPlayed.lua" if it exists) with mocks of the engine
-- globals it uses, then checks the group list that the song select screen
-- would receive. OutFox does not read this folder.
--
-- Usage (Lua 5.4, from the theme root): lua Tests/test_mostplayed.lua [theme_dir]
-- theme_dir defaults to the parent folder of Tests/.
-- Exit code 0 = all checks passed.

local ThemeDir = arg[1] or (arg[0]:match("^(.*)/Tests/[^/]*$") or ".")

-- ----------------------------------------------------------------- mocks
local Traces, Warnings = {}, {}
function Trace(s) Traces[#Traces + 1] = tostring(s) end
function Warn(s) Warnings[#Warnings + 1] = tostring(s) end
function ToUpper(s) return string.upper(s) end
function ToLower(s) return string.lower(s) end
function ToEnumShortString(e) local s = tostring(e) return s:match("^[^_]+_(.+)$") or s end
function ivalues(t) local i = 0 return function() i = i + 1 return t[i] end end
function LoadModule(Name)
    if Name == "Config.Load.lua" then return function() return true end end
    error("unexpected LoadModule: " .. Name)
end
MESSAGEMAN = { Broadcast = function() end }

local Metrics = {}
THEME = {
    GetPathG = function(_, a, b) return "G/" .. a .. b end,
    HasMetric = function(_, g, n) return Metrics[g .. "::" .. n] ~= nil end,
    GetMetric = function(_, g, n)
        local v = Metrics[g .. "::" .. n]
        if v == nil then error("metric " .. g .. "::" .. n .. " missing") end
        return v
    end,
}
GAMESTATE = { GetCurrentGame = function() return { GetName = function() return "pump" end } end }

local function NewSteps(StepsType, Meter)
    return {
        GetStepsType = function() return StepsType end,
        GetMeter = function() return Meter end,
        GetDescription = function() return "" end,
        GetChartLength = function() return 120 end,
    }
end

local function NewSong(Title, Dir, Group, StepsTypes)
    local Steps = {}
    for i, st in ipairs(StepsTypes) do Steps[i] = NewSteps(st, 5) end
    local Song = {}
    function Song:GetTranslitFullTitle() return Title end
    function Song:GetDisplayMainTitle() return Title end
    function Song:GetDisplayArtist() return "Artist" end
    function Song:GetSongDir() return Dir end
    function Song:GetGroupName() return Group end
    function Song:GetLastSecond() return 120 end
    function Song:GetAllSteps() return Steps end
    function Song:GetStepsByStepsType(st)
        local r = {}
        for _, s in ipairs(Steps) do if s:GetStepsType() == st then r[#r + 1] = s end end
        return r
    end
    return Song
end

local Songs, Plays = {}, {}
SONGMAN = {
    GetAllSongs = function() return Songs end,
    GetSongGroupNames = function()
        local Seen, r = {}, {}
        for _, s in ipairs(Songs) do
            local g = s:GetGroupName()
            if not Seen[g] then Seen[g] = true r[#r + 1] = g end
        end
        return r
    end,
    GetSongsInGroup = function(_, g)
        local r = {}
        for _, s in ipairs(Songs) do if s:GetGroupName() == g then r[#r + 1] = s end end
        return r
    end,
    GetSongGroupBannerPath = function() return "" end,
}
local PlayersJoined = true
SongUtil = {
    -- Current game is pump: only pump steps are playable. Like the engine
    -- (GameManager::GetCompatibleStyles with 0 players matches no style),
    -- nothing is playable while no player has joined, which is the case when
    -- AssembleGroupSorting runs at startup from ScreenSystemLayer.
    GetPlayableSteps = function(Song)
        local r = {}
        if not PlayersJoined then return r end
        for _, s in ipairs(Song:GetAllSteps()) do
            if s:GetStepsType():find("^StepsType_Pump_") then r[#r + 1] = s end
        end
        return r
    end,
}
local MachineProfile = { GetSongNumTimesPlayed = function(_, Song) return Plays[Song] or 0 end }
PROFILEMAN = { GetMachineProfile = function() return MachineProfile end }

-- ------------------------------------------------------ load theme code
dofile(ThemeDir .. "/Scripts/01 Sorting.lua")
local AddOnPath = ThemeDir .. "/Scripts/99 MostPlayed.lua"
local f = io.open(AddOnPath, "r")
if f then f:close() dofile(AddOnPath) print("add-on: loaded") else print("add-on: NOT present") end

-- ------------------------------------------------------------ fixtures
local S = {}
local function Setup(WithPlays)
    Songs, Plays, Traces, Warnings = {}, {}, {}, {}
    Metrics = { ["MusicWheel::MostPlayedSongsToShow"] = 30 }
    S.alpha1  = NewSong("Alpha",   "/G1/alpha-a/", "G1", { "StepsType_Pump_Single" })
    S.bravo   = NewSong("Bravo",   "/G1/bravo/",   "G1", { "StepsType_Pump_Double" })
    S.charlie = NewSong("Charlie", "/DDR/charlie/", "DDR", { "StepsType_Dance_Single" })
    S.delta   = NewSong("Delta",   "/G1/delta/",   "G1", { "StepsType_Pump_Single" })
    S.echo    = NewSong("echo",    "/G2/echo/",    "G2", { "StepsType_Pump_Single" })
    S.foxtrot = NewSong("Foxtrot", "/G2/foxtrot/", "G2", { "StepsType_Pump_Halfdouble" })
    S.alpha2  = NewSong("Alpha",   "/G2/alpha-b/", "G2", { "StepsType_Pump_Single" })
    S.golf    = NewSong("Golf",    "/G2/golf/",    "G2", { "StepsType_Pump_Single", "StepsType_Dance_Single" })
    for _, k in ipairs({ "alpha1", "bravo", "charlie", "delta", "echo", "foxtrot", "alpha2", "golf" }) do
        Songs[#Songs + 1] = S[k]
    end
    if WithPlays then
        Plays[S.alpha1] = 5
        Plays[S.bravo] = 10
        Plays[S.charlie] = 50 -- most played, but dance-only: not playable in pump
        Plays[S.delta] = 0
        Plays[S.echo] = 5
        Plays[S.foxtrot] = 7
        Plays[S.alpha2] = 5
        Plays[S.golf] = 1
    end
end

-- ---------------------------------------------------------- mini-framework
local Failures, Checks = 0, 0
local function Check(Cond, Msg)
    Checks = Checks + 1
    if Cond then print("  ok   " .. Msg) else Failures = Failures + 1 print("  FAIL " .. Msg) end
end
local function FindSub(List, Main, Sub)
    for _, g in ipairs(List) do
        if g.Name == Main then
            for i, s in ipairs(g.SubGroups) do if s.Name == Sub then return s, i, g end end
        end
    end
end
local function Count(List, Main, Sub)
    local n = 0
    for _, g in ipairs(List) do
        if g.Name == Main then for _, s in ipairs(g.SubGroups) do if s.Name == Sub then n = n + 1 end end end
    end
    return n
end
local function Dirs(SongList)
    local r = {}
    for i, s in ipairs(SongList or {}) do r[i] = s:GetSongDir() end
    return table.concat(r, " ")
end
local function Run()
    PlayersJoined = false -- startup: ScreenSystemLayer, nobody has joined yet
    AssembleGroupSorting()
    PlayersJoined = true  -- entering song select: a player has joined
    UpdateGroupSorting()
end

-- -------------------------------------------------------------- cases
print("case 1: ranking by plays, ties by title then dir, 0 plays and non-pump songs excluded")
Setup(true)
Run()
local Expected = "/G1/bravo/ /G2/foxtrot/ /G1/alpha-a/ /G2/alpha-b/ /G2/echo/ /G2/golf/"
local MP, MPIndex, Special = FindSub(GroupsList, "Special", "Most Played")
Check(MP ~= nil, "GroupsList has Special/Most Played")
Check(MP and Dirs(MP.Songs) == Expected, "order = " .. Expected .. " (got: " .. Dirs(MP and MP.Songs) .. ")")
Check(Special and MPIndex == #Special.SubGroups, "Most Played is the last Special subgroup")
Check(Special and Special.SubGroups[1].Name == "All Tunes", "All Tunes is still the first Special subgroup")
Check(GroupsList[1].Name == "Special" and GroupsList[2].Name == "Group", "main order kept: Special=1, Group=2 (GroupSelect OrigGroupIndex)")
local function Traced(Line)
    for _, t in ipairs(Traces) do if t == Line then return true end end
    return false
end
Check(Traced("Group added: Special/Most Played - 6 songs"), "Trace 'Group added: Special/Most Played - 6 songs'")
local Summary = "Most Played: 7 songs with plays, 6 with pump charts, showing 6 (playable right now: 0)"
Check(Traced(Summary), "Trace '" .. Summary .. "'")
Check(#Warnings == 0, "no warnings (" .. table.concat(Warnings, " | ") .. ")")

print("case 2: cap = MusicWheel::MostPlayedSongsToShow, counting only playable songs")
Setup(true)
Metrics["MusicWheel::MostPlayedSongsToShow"] = 3
Run()
MP = FindSub(GroupsList, "Special", "Most Played")
Check(MP and Dirs(MP.Songs) == "/G1/bravo/ /G2/foxtrot/ /G1/alpha-a/", "top 3 = bravo foxtrot alpha-a (got: " .. Dirs(MP and MP.Songs) .. ")")

print("case 3: metric missing -> default cap 30, no error")
Setup(true)
Metrics = {}
Run()
MP = FindSub(GroupsList, "Special", "Most Played")
Check(MP and Dirs(MP.Songs) == Expected, "same list as case 1 (got: " .. Dirs(MP and MP.Songs) .. ")")
Check(#Warnings == 0, "no warnings (" .. table.concat(Warnings, " | ") .. ")")

print("case 4: no plays -> no Most Played group, rest untouched")
Setup(false)
Run()
Check(FindSub(MasterGroupsList, "Special", "Most Played") == nil, "no Most Played in MasterGroupsList")
Check(GroupsList[1].Name == "Special" and GroupsList[1].SubGroups[1].Name == "All Tunes", "Special/All Tunes present")
Check(#Warnings == 0, "no warnings (" .. table.concat(Warnings, " | ") .. ")")

print("case 5: no machine profile -> no Most Played group, no error")
Setup(true)
PROFILEMAN.GetMachineProfile = function() return nil end
Run()
Check(FindSub(MasterGroupsList, "Special", "Most Played") == nil, "no Most Played in MasterGroupsList")
Check(#Warnings == 0, "no warnings (" .. table.concat(Warnings, " | ") .. ")")
PROFILEMAN.GetMachineProfile = function() return MachineProfile end

print("case 6: engine call fails -> song list still built, warning logged")
Setup(true)
local SavedGet = MachineProfile.GetSongNumTimesPlayed
MachineProfile.GetSongNumTimesPlayed = function() error("boom") end
local Ok, Err = pcall(Run)
MachineProfile.GetSongNumTimesPlayed = SavedGet
Check(Ok, "AssembleGroupSorting/UpdateGroupSorting did not raise (" .. tostring(Err) .. ")")
Check(FindSub(GroupsList, "Special", "All Tunes") ~= nil, "Special/All Tunes present")
Check(FindSub(MasterGroupsList, "Special", "Most Played") == nil, "no Most Played in MasterGroupsList")
Check(#Warnings == 1 and Warnings[1]:find("MostPlayed", 1, true) ~= nil, "one warning mentioning MostPlayed (" .. table.concat(Warnings, " | ") .. ")")

print("case 7: assembling twice does not duplicate the group")
Setup(true)
PlayersJoined = false
AssembleGroupSorting()
AssembleGroupSorting()
PlayersJoined = true
UpdateGroupSorting()
Check(Count(MasterGroupsList, "Special", "Most Played") == 1, "exactly one Most Played in MasterGroupsList")
Check(Count(GroupsList, "Special", "Most Played") == 1, "exactly one Most Played in GroupsList")

print(string.format("\n%d checks, %d failed", Checks, Failures))
os.exit(Failures == 0 and 0 or 1)
