-- Not part of upstream Infinitesimal
-- (https://github.com/Team-Infinitesimal/Infinitesimal): added in the
-- RazZziel/Infinitesimal fork. It lives in its own file and only wraps
-- AssembleGroupSorting, so merging upstream changes does not conflict with it.
--
-- Adds a "Most Played" entry at the end of the "Special" category of the group
-- selector (UpLeft/UpRight on the song wheel). It lists the songs played the
-- most on this machine (machine profile play counts), most played first, like
-- the Popularity sort of the default theme, capped by the same metric that
-- sort uses (MusicWheel::MostPlayedSongsToShow, 30 in _fallback).
--
-- The list is built together with the rest of the groups, once per game start
-- (AssembleGroupSorting runs from ScreenSystemLayer), so it does not reorder
-- itself between stages: the theme remembers the selected song by its position
-- in the list, and re-ranking after every stage would move the wheel cursor to
-- a different song.

local MostPlayedName = "Most Played"
local DefaultLimit = 30

local function GetLimit()
    if THEME:HasMetric("MusicWheel", "MostPlayedSongsToShow") then
        local Limit = tonumber(THEME:GetMetric("MusicWheel", "MostPlayedSongsToShow"))
        if Limit and Limit > 0 then return Limit end
    end
    return DefaultLimit
end

local function HasChartsForGame(Song, GameName)
    for Chart in ivalues(Song:GetAllSteps()) do
        if string.find(Chart:GetStepsType():lower(), GameName, 1, true) then return true end
    end
    return false
end

local function GetMostPlayedSongs()
    local Profile = PROFILEMAN:GetMachineProfile()
    if not Profile then
        Trace("Most Played: no machine profile")
        return {}
    end

    local Played = {}
    for Song in ivalues(SONGMAN:GetAllSongs()) do
        local Plays = Profile:GetSongNumTimesPlayed(Song)
        if Plays > 0 then
            Played[#Played + 1] = {
                Song = Song,
                Plays = Plays,
                Title = ToLower(Song:GetTranslitFullTitle()),
                Dir = Song:GetSongDir(),
            }
        end
    end

    table.sort(Played, function(a, b)
        if a.Plays ~= b.Plays then return a.Plays > b.Plays end
        if a.Title ~= b.Title then return a.Title < b.Title end
        return a.Dir < b.Dir
    end)

    -- Songs without charts for the current game (e.g. dance-only songs while
    -- playing pump) must not take places in the ranking: filter before the cap.
    -- SongUtil.GetPlayableSteps cannot do it here: this runs at startup, before
    -- any player has joined, and with nobody joined it returns no steps at all.
    -- Match the StepsType against the game name instead, like the theme's own
    -- level groups do. Song select still applies PlayableSongs on top of this.
    local GameName = GAMESTATE:GetCurrentGame():GetName():lower()
    local Limit = GetLimit()
    local Songs, ForGame, PlayableNow = {}, 0, 0
    for _, Entry in ipairs(Played) do
        if HasChartsForGame(Entry.Song, GameName) then
            ForGame = ForGame + 1
            if #Songs < Limit then
                Songs[#Songs + 1] = Entry.Song
                Trace(string.format("Most Played #%d: %d plays - %s", #Songs, Entry.Plays, Entry.Dir))
            end
        end
        if #SongUtil.GetPlayableSteps(Entry.Song) > 0 then PlayableNow = PlayableNow + 1 end
    end
    Trace(string.format("Most Played: %d songs with plays, %d with %s charts, showing %d (playable right now: %d)",
        #Played, ForGame, GameName, #Songs, PlayableNow))
    return Songs
end

local function AddMostPlayedGroup()
    local Special
    for _, MainGroup in ipairs(MasterGroupsList) do
        if MainGroup.Name == "Special" then Special = MainGroup break end
    end
    if not Special then return end

    -- The original function can return early without resetting the list, so
    -- drop any previous copy of the group before adding it again.
    for i = #Special.SubGroups, 1, -1 do
        if Special.SubGroups[i].Name == MostPlayedName then table.remove(Special.SubGroups, i) end
    end

    local Songs = GetMostPlayedSongs()
    if #Songs == 0 then return end

    Special.SubGroups[#Special.SubGroups + 1] = {
        Name = MostPlayedName,
        Banner = THEME:GetPathG("", "Common fallback banner"),
        Songs = Songs,
    }
    Trace("Group added: Special/" .. MostPlayedName .. " - " .. #Songs .. " songs")
end

local AssembleGroupSortingOriginal = AssembleGroupSorting

function AssembleGroupSorting(...)
    local Result = AssembleGroupSortingOriginal(...)
    -- This add-on must never break the song list: log errors and carry on.
    local Ok, Err = pcall(AddMostPlayedGroup)
    if not Ok then Warn("99 MostPlayed.lua: " .. tostring(Err)) end
    return Result
end
