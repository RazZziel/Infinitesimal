-- Tests for the chart preselected on ScreenSelectMusicFull: each player gets
-- the chart closest to the one they played last.
--
-- Runs the REAL theme scripts and screen files with the engine stand-in in
-- Tests/engine_mock.lua. OutFox does not read this folder.
--
-- Usage (Lua 5.4, from the theme root): lua Tests/test_chartmemory.lua
-- Exit code 0 = all checks passed.

package.path = (arg[0]:match("^(.*)/[^/]*$") or ".") .. "/?.lua;" .. package.path
local E = require("engine_mock")
local Check = E.Check

local Single, Double = "StepsType_Pump_Single", "StepsType_Pump_Double"

-- ChartDisplay.lua sorts the charts by type (single, half-double, double) and
-- level, and starts on the first one.
local S = {}
local function Fixture()
    local G = "PIU"
    S.FinalAudition = E.NewSong("Final Audition", G, nil, { { Single, 5 }, { Single, 9 }, { Double, 10 } })
    S.Beethoven = E.NewSong("Beethoven Virus", G, nil,
        { { Single, 9 }, { Single, 14 }, { Double, 16 }, { Double, 99, "DP" } })
    S.Winter = E.NewSong("WINTER", G, nil, { { Single, 4 }, { Single, 11 }, { Double, 12 } })
    S.DrM = E.NewSong("Dr. M", G, nil, { { Single, 7 }, { Double, 15 } })
    S.SinglesOnly = E.NewSong("Singles Only", G, nil, { { Single, 10 }, { Single, 18 } })
    S.Tie = E.NewSong("Tie", G, nil, { { Single, 3 }, { Double, 15 }, { Double, 17 } })
    S.CoopOnly = E.NewSong("Coop Only", G, nil, { { Single, 16 }, { Double, 99, "DP" } })
    S.TwoLevels = E.NewSong("Two Levels", G, nil, { { Single, 5 }, { Single, 13 } })
    return { Songs = { S.FinalAudition, S.Beethoven, S.Winter, S.DrM, S.SinglesOnly, S.Tie, S.CoopOnly, S.TwoLevels } }
end

local function Chart(pn) return E.ChartName(GAMESTATE:GetCurrentSteps(pn or PLAYER_1)) end
local function Title(Song) return Song and Song:GetTranslitFullTitle() or "none" end

local function ExpectOn(Song, Expected, pn)
    Check(E.ScrollToSong(pn or PLAYER_1, Song), Title(Song) .. " is on the wheel")
    Check(Chart(pn) == Expected, Title(Song) .. " -> " .. Expected .. " (got: " .. Chart(pn) .. ")")
end

-- ----------------------------------------------------------------------------
print("case 1: nothing played yet in this credit: the list starts on the first chart, as before")
E.Boot(Fixture())
E.StartGame({ PLAYER_1 })
E.LoadSelectMusic()
Check(GAMESTATE:GetCurrentSong() == S.FinalAudition, "first song: Final Audition (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
Check(Chart() == "Single 5", "Final Audition -> Single 5 (got: " .. Chart() .. ")")

-- ----------------------------------------------------------------------------
print("case 2: after playing Double 16 every song preselects its closest chart")
-- continues from case 1
Check(E.ScrollToSong(PLAYER_1, S.Beethoven), "Beethoven Virus is on the wheel")
local Played = E.PlayCurrentSong(PLAYER_1, 2)
Check(E.ChartName(Played) == "Double 16", "played Beethoven Virus Double 16 (got: " .. E.ChartName(Played) .. ")")
E.FinishStage()
E.LoadSelectMusic()
Check(GAMESTATE:GetCurrentSong() == S.Beethoven, "back on Beethoven Virus (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
Check(Chart() == "Double 16", "Beethoven Virus -> Double 16, the chart just played (got: " .. Chart() .. ")")
ExpectOn(S.Winter, "Double 12")
ExpectOn(S.DrM, "Double 15")
ExpectOn(S.FinalAudition, "Double 10")

print("case 3: no chart of the same type: the closest level of any type")
ExpectOn(S.SinglesOnly, "Single 18")

print("case 4: two charts equally close: the lower one")
ExpectOn(S.Tie, "Double 15")

print("case 5: co-op charts (level 99) do not stand in for normal charts")
ExpectOn(S.CoopOnly, "Single 16")

-- ----------------------------------------------------------------------------
print("case 6: moving the cursor by hand is kept until the song changes; only played charts are remembered")
ExpectOn(S.Winter, "Double 12")
E.Press(PLAYER_1, "Start") -- choose the song, the chart list opens
Check(Chart() == "Double 12", "song chosen: still Double 12 (got: " .. Chart() .. ")")
E.Press(PLAYER_1, "Left")
Check(Chart() == "Single 11", "Left -> Single 11 (got: " .. Chart() .. ")")
E.Press(PLAYER_1, "UpLeft") -- back to the song wheel without playing
Check(Chart() == "Single 11", "back to the wheel: still Single 11 (got: " .. Chart() .. ")")
ExpectOn(S.DrM, "Double 15") -- still closest to the played Double 16, not to Single 11

-- ----------------------------------------------------------------------------
print("case 7: after playing a co-op chart, co-op charts are preselected")
Check(E.ScrollToSong(PLAYER_1, S.CoopOnly), "Coop Only is on the wheel")
Played = E.PlayCurrentSong(PLAYER_1, 1)
Check(E.ChartName(Played) == "Double 99", "played Coop Only Double 99 (got: " .. E.ChartName(Played) .. ")")
E.FinishStage()
E.LoadSelectMusic()
ExpectOn(S.Beethoven, "Double 99")
ExpectOn(S.Winter, "Double 12") -- no co-op chart: the closest level of the rest

-- ----------------------------------------------------------------------------
print("case 8: going back to the title menu forgets it, like the remembered group and song")
E.TitleMenu({ PLAYER_1 })
E.LoadSelectMusic()
Check(GAMESTATE:GetCurrentSong() == S.FinalAudition, "first song: Final Audition (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
Check(Chart() == "Single 5", "Final Audition -> Single 5 (got: " .. Chart() .. ")")

-- ----------------------------------------------------------------------------
print("case 9: two players: each one gets the chart closest to their own")
E.Boot(Fixture())
E.StartGame({ PLAYER_1, PLAYER_2 })
E.LoadSelectMusic()
Check(E.ScrollToSong(PLAYER_1, S.Beethoven), "Beethoven Virus is on the wheel")
E.Press(PLAYER_1, "Start")
E.Press(PLAYER_1, "Right") -- P1: Single 14, P2 stays on Single 9
Check(Chart(PLAYER_1) == "Single 14" and Chart(PLAYER_2) == "Single 9",
    "P1 Single 14, P2 Single 9 (got: " .. Chart(PLAYER_1) .. ", " .. Chart(PLAYER_2) .. ")")
E.Press(PLAYER_1, "Start")
E.Press(PLAYER_1, "Start")
Check(E.Screen.Transition == "SM_GoToNextScreen", "goes to gameplay")
E.LeaveScreen()
E.FinishStage()
E.LoadSelectMusic()
Check(E.ScrollToSong(PLAYER_1, S.TwoLevels), "Two Levels is on the wheel")
Check(Chart(PLAYER_1) == "Single 13", "P1 (played Single 14) -> Single 13 (got: " .. Chart(PLAYER_1) .. ")")
Check(Chart(PLAYER_2) == "Single 5", "P2 (played Single 9) -> Single 5, the lower of 5 and 13 (got: " .. Chart(PLAYER_2) .. ")")

-- ----------------------------------------------------------------------------
-- Charts of the same type and level told apart by their description, as in
-- "03 - REBIRTH~PREX 3/(2) 711 - Winter": Single 7 "S7" and Single 7 "SQUEST"
-- (shown as 7 QUEST, left of the plain 7).
local Q = {}
local function LabelsFixture()
    local G = "PIU"
    Q.Winter = E.NewSong("Winter", G, nil,
        { { Single, 4, "S4" }, { Single, 7, "S7" }, { Single, 7, "SQUEST" }, { Single, 12, "S12" } })
    Q.Labels = E.NewSong("Labels", G, nil, { { Single, 7, "QUEST" }, { Single, 7, "7" }, { Single, 10, "" } })
    Q.EquallyClose = E.NewSong("Equally Close", G, nil, { { Single, 6, "S6 QUEST" }, { Single, 8, "S8" } })
    Q.NearestFirst = E.NewSong("Nearest First", G, nil, { { Single, 7, "SQUEST" }, { Single, 8, "S8" } })
    Q.TwoUCS = E.NewSong("Two UCS", G, nil, { { Single, 17, "HUCAR UCS" }, { Single, 17, "UCS" } })
    return { Songs = { Q.Winter, Q.Labels, Q.EquallyClose, Q.NearestFirst, Q.TwoUCS } }
end

local function Desc(pn)
    local Steps = GAMESTATE:GetCurrentSteps(pn or PLAYER_1)
    return Steps and (E.ChartName(Steps) .. " " .. Steps:GetDescription()) or "none"
end

-- The order ChartDisplay.lua shows the charts in: SongUtil.GetPlayableSteps
-- sorted with its SortCharts (type and level only).
local function ListedBefore(Song, DescA, DescB)
    local List = SongUtil.GetPlayableSteps(Song)
    table.sort(List, SortCharts)
    local a, b
    for i, Steps in ipairs(List) do
        if Steps:GetDescription() == DescA then a = i end
        if Steps:GetDescription() == DescB then b = i end
    end
    return a ~= nil and b ~= nil and a < b
end

local function ExpectDesc(Song, Expected)
    Check(E.ScrollToSong(PLAYER_1, Song), Title(Song) .. " is on the wheel")
    Check(Desc() == Expected, Title(Song) .. " -> " .. Expected .. " (got: " .. Desc() .. ")")
end

print("case 10: two charts of the same type and level: back on the song, the one played")
E.Boot(LabelsFixture())
E.StartGame({ PLAYER_1 })
E.LoadSelectMusic()
Check(ListedBefore(Q.Winter, "SQUEST", "S7"), "precondition: Winter lists 7 QUEST before the plain 7")
Check(E.ScrollToSong(PLAYER_1, Q.Winter), "Winter is on the wheel")
Played = E.PlayChart(PLAYER_1, 7, "S7")
Check(Played ~= nil, "played Winter Single 7 S7")
E.FinishStage()
E.LoadSelectMusic()
Check(GAMESTATE:GetCurrentSong() == Q.Winter, "back on Winter (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
Check(Desc() == "Single 7 S7", "Winter -> Single 7 S7 (got: " .. Desc() .. ")")

print("case 11: another song with both kinds at that level: the one with the same label (none)")
Check(ListedBefore(Q.Labels, "QUEST", "7"), "precondition: Labels lists 7 QUEST before the plain 7")
ExpectDesc(Q.Labels, "Single 7 7")

print("case 12: two levels equally close: the one with the same label before the lower one")
ExpectDesc(Q.EquallyClose, "Single 8 S8")

print("case 13: the closest level comes first, whatever its label")
ExpectDesc(Q.NearestFirst, "Single 7 SQUEST")

print("case 14: same type, level and label: the same description")
Check(ListedBefore(Q.TwoUCS, "HUCAR UCS", "UCS"), "precondition: Two UCS lists HUCAR UCS before UCS")
Check(E.ScrollToSong(PLAYER_1, Q.TwoUCS), "Two UCS is on the wheel")
Check(E.PlayChart(PLAYER_1, 17, "UCS") ~= nil, "played Two UCS Single 17 UCS")
E.FinishStage()
E.LoadSelectMusic()
Check(Desc() == "Single 17 UCS", "Two UCS -> Single 17 UCS (got: " .. Desc() .. ")")

print("case 15: after playing a QUEST chart, QUEST charts win the ties")
Check(E.ScrollToSong(PLAYER_1, Q.Winter), "Winter is on the wheel")
Check(E.PlayChart(PLAYER_1, 7, "SQUEST") ~= nil, "played Winter Single 7 SQUEST")
E.FinishStage()
E.LoadSelectMusic()
Check(Desc() == "Single 7 SQUEST", "Winter -> Single 7 SQUEST (got: " .. Desc() .. ")")
ExpectDesc(Q.Labels, "Single 7 QUEST")

E.Finish()
