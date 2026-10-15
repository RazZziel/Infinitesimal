-- Tests for the song list of ScreenSelectMusicFull: which groups and songs it
-- shows, and that the group and song chosen before a stage are selected again
-- when the player comes back to the screen.
--
-- Runs the REAL theme scripts and screen files with the engine stand-in in
-- Tests/engine_mock.lua. OutFox does not read this folder.
--
-- Usage (Lua 5.4, from the theme root): lua Tests/test_groupsorting.lua
-- Exit code 0 = all checks passed.

package.path = (arg[0]:match("^(.*)/[^/]*$") or ".") .. "/?.lua;" .. package.path
local E = require("engine_mock")
local Check = E.Check

local Single, HalfDouble, Double = "StepsType_Pump_Single", "StepsType_Pump_Halfdouble", "StepsType_Pump_Double"
local DanceSingle = "StepsType_Dance_Single"

-- Same shape as the real Special category in the logs: All Tunes, Shortcut,
-- Remix, Full Song, Co-op, Most Played. Two dance-only groups in a row
-- ("DDR ...") between two pump groups, as in the real song folders.
local S = {}
local function Fixture()
    local PIU1, PIU2 = "01 - 1ST~3RD", "PIU Extra"
    S.FinalAudition = E.NewSong("Final Audition", PIU1, nil, { { Single, 5 }, { Single, 9 }, { Double, 10 } })
    S.Beethoven = E.NewSong("Beethoven Virus", PIU1, nil,
        { { Single, 9 }, { Single, 14 }, { Double, 16 }, { Double, 99, "DP" } })
    S.ParkMeeKyung = E.NewSong("Park Mee Kyung Remix", PIU1, "(1) 323 - [Remix] Park Mee Kyung Remix", { { Single, 7 } })
    S.UhmJungHwa = E.NewSong("Uhm Jung Hwa Remix", PIU1, "(2) 220 - [Remix] Uhm Jung Hwa Remix", { { Single, 8 } })
    S.LoveDanger = E.NewSong("Love is a Danger Zone", PIU1, nil, { { Single, 6 } }, { LastSecond = 60 })
    S.Csikos = E.NewSong("Csikos Post", PIU1, "Csikos Post [FULL SONG]", { { Single, 12 }, { HalfDouble, 13 } })
    S.DemonGunShot = E.NewSong("Demon Gun Shot", "DDR Anime 2nd Mix", nil, { { DanceSingle, 5 } }, { LastSecond = 60 })
    S.Azumanga = E.NewSong("Azumanga Daioh", "DDR Pack08 Anime", nil, { { DanceSingle, 3 }, { DanceSingle, 7 } })
    S.Kanon = E.NewSong("Kanon", "DDR Pack08 Anime", nil, { { DanceSingle, 4 } })
    S.Winter = E.NewSong("WINTER", PIU2, nil, { { Single, 4 }, { Single, 11 }, { Double, 12 } })
    S.DrM = E.NewSong("Dr. M", PIU2, nil, { { Single, 7 }, { Double, 15 } })
    return {
        Songs = { S.FinalAudition, S.Beethoven, S.ParkMeeKyung, S.UhmJungHwa, S.LoveDanger, S.Csikos,
                  S.DemonGunShot, S.Azumanga, S.Kanon, S.Winter, S.DrM },
        Plays = { [S.Winter] = 85, [S.Beethoven] = 59, [S.DrM] = 44, [S.Azumanga] = 3 },
    }
end

local function Title(Song) return Song and Song:GetTranslitFullTitle() or "none" end

-- Groups and songs in GroupsList that the current players cannot play.
local function Unplayable()
    local r = {}
    for _, Main in ipairs(GroupsList) do
        for _, Sub in ipairs(Main.SubGroups) do
            for _, Song in ipairs(Sub.Songs) do
                if #SongUtil.GetPlayableSteps(Song) == 0 then
                    r[#r + 1] = Main.Name .. "/" .. Sub.Name .. ": " .. Title(Song)
                end
            end
        end
    end
    return r
end

local function SubNames(MainName)
    for _, Main in ipairs(GroupsList) do
        if Main.Name == MainName then
            local r = {}
            for i, Sub in ipairs(Main.SubGroups) do r[i] = Sub.Name end
            return table.concat(r, ", ")
        end
    end
    return "(no " .. MainName .. ")"
end

local function CurrentGroup()
    local Main = GroupsList[LastGroupMainIndex]
    local Sub = Main and Main.SubGroups[LastGroupSubIndex]
    return Sub and (Main.Name .. "/" .. Sub.Name) or "none"
end

local SpecialAll = "All Tunes, Shortcut, Remix, Full Song, Co-op, Most Played"

-- ----------------------------------------------------------------------------
print("case 1: UpdateGroupSorting with one player drops every group and song without playable charts")
E.Boot(Fixture())
AssembleGroupSorting()
GAMESTATE:JoinPlayer(PLAYER_1)
UpdateGroupSorting()
local Bad = Unplayable()
Check(#Bad == 0, "no unplayable songs in GroupsList (got: " .. table.concat(Bad, " | ") .. ")")
Check(SubNames("Group") == "01 - 1ST~3RD, PIU Extra",
    "Group = 01 - 1ST~3RD, PIU Extra (got: " .. SubNames("Group") .. ")")
Check(SubNames("Special") == SpecialAll, "Special = " .. SpecialAll .. " (got: " .. SubNames("Special") .. ")")

-- ----------------------------------------------------------------------------
print("case 2: first visit to song select shows the list for the player who joined")
E.Boot(Fixture())
Check(E.StartGame({ PLAYER_1 }) == "ScreenSelectMusicFull", "title menu leads to ScreenSelectMusicFull")
E.LoadSelectMusic()
Bad = Unplayable()
Check(#Bad == 0, "no unplayable songs in GroupsList (got: " .. table.concat(Bad, " | ") .. ")")
Check(SubNames("Special") == SpecialAll, "Special = " .. SpecialAll .. " (got: " .. SubNames("Special") .. ")")
Check(#SongUtil.GetPlayableSteps(GAMESTATE:GetCurrentSong()) > 0,
    "the song on the wheel is playable (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
local Assembled = 0
for _, t in ipairs(E.Traces) do if t == "Creating group sorts..." then Assembled = Assembled + 1 end end
Check(Assembled == 1, "the master list is built once, at startup, not again by song select (built " .. Assembled .. " times)")

-- ----------------------------------------------------------------------------
print("case 3: group and song chosen on the first visit are selected again after the first stage")
-- continues from case 2
Check(E.SelectGroup(PLAYER_1, "Special", "Most Played"), "Special/Most Played can be chosen")
Check(E.ScrollToSong(PLAYER_1, S.Beethoven), "Beethoven Virus is in Most Played")
E.PlayCurrentSong(PLAYER_1)
Check(E.FinishStage() == "ScreenSelectMusicFull", "after the stage: back to ScreenSelectMusicFull")
E.LoadSelectMusic()
Check(CurrentGroup() == "Special/Most Played", "group = Special/Most Played (got: " .. CurrentGroup() .. ")")
Check(GAMESTATE:GetCurrentSong() == S.Beethoven,
    "song = Beethoven Virus (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")
Bad = Unplayable()
Check(#Bad == 0, "no unplayable songs in GroupsList (got: " .. table.concat(Bad, " | ") .. ")")

-- ----------------------------------------------------------------------------
print("case 4: ... and after the second stage")
-- continues from case 3
Check(E.SelectGroup(PLAYER_1, "Special", "Most Played"), "Special/Most Played can be chosen")
Check(E.ScrollToSong(PLAYER_1, S.DrM), "Dr. M is in Most Played")
E.PlayCurrentSong(PLAYER_1)
E.FinishStage()
E.LoadSelectMusic()
Check(CurrentGroup() == "Special/Most Played", "group = Special/Most Played (got: " .. CurrentGroup() .. ")")
Check(GAMESTATE:GetCurrentSong() == S.DrM, "song = Dr. M (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")

-- ----------------------------------------------------------------------------
print("case 5: a group chosen in the Group category is selected again after the first stage")
E.Boot(Fixture())
E.StartGame({ PLAYER_1 })
E.LoadSelectMusic()
Check(E.SelectGroup(PLAYER_1, "Group", "PIU Extra"), "Group/PIU Extra can be chosen")
Check(E.ScrollToSong(PLAYER_1, S.DrM), "Dr. M is in PIU Extra")
E.PlayCurrentSong(PLAYER_1)
E.FinishStage()
E.LoadSelectMusic()
Check(CurrentGroup() == "Group/PIU Extra", "group = Group/PIU Extra (got: " .. CurrentGroup() .. ")")
Check(GAMESTATE:GetCurrentSong() == S.DrM, "song = Dr. M (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")

-- ----------------------------------------------------------------------------
print("case 6: a song chosen without opening the group wheel is selected again after the stage")
E.Boot(Fixture())
E.StartGame({ PLAYER_1 })
E.LoadSelectMusic()
Check(CurrentGroup() == "Special/All Tunes", "the wheel starts on Special/All Tunes (got: " .. CurrentGroup() .. ")")
Check(E.ScrollToSong(PLAYER_1, S.Csikos), "Csikos Post is in All Tunes")
E.PlayCurrentSong(PLAYER_1)
E.FinishStage()
E.LoadSelectMusic()
Check(CurrentGroup() == "Special/All Tunes", "group = Special/All Tunes (got: " .. CurrentGroup() .. ")")
Check(GAMESTATE:GetCurrentSong() == S.Csikos, "song = Csikos Post (got: " .. Title(GAMESTATE:GetCurrentSong()) .. ")")

E.Finish()
