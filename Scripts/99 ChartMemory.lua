-- Not part of upstream Infinitesimal
-- (https://github.com/Team-Infinitesimal/Infinitesimal): added in the
-- RazZziel/Infinitesimal fork. ScreenSelectMusicFull underlay/ChartDisplay.lua
-- calls it.
--
-- Remembers the chart each player played last and, when the song wheel lands on
-- a song, preselects that song's chart closest to it:
--   1. same StepsType (single, half-double, double...), closest level;
--   2. if the song has none of that type, the closest level of any type.
--   Between charts equally close, in this order: the same label as the played
--   one (QUEST, HIDDEN, UCS... or none, as shown on the chart balls), the same
--   description, the lower level. So back on the song just played, its own
--   chart is selected even if another one of the same level comes first in the
--   list (Winter has a plain 7 and a 7 QUEST).
--   Co-op charts (level 99, shown as "??") only stand in for co-op charts, and
--   the other way round.
-- Moving the cursor by hand is kept until the song changes, and only the chart
-- that is played is remembered.
--
-- Kept for the credit, like the remembered group and song: going back to the
-- title menu (ResetLuaMods) forgets it.

LastPlayedChart = {}

-- The labels shown on the chart balls, with the same rule as ChartLabels in
-- ScreenSelectMusicFull underlay/ChartDisplay.lua: the last one of the list
-- found in the description. "" if none.
local Labels = { "NEW", "ANOTHER", "PRO", "TRAIN", "QUEST", "UCS", "HIDDEN", "INFINITY", "JUMP" }

local function ChartLabel(Description)
    local Label = ""
    for _, String in ipairs(Labels) do
        if string.find(ToUpper(Description), String) then Label = String end
    end
    return Label
end

-- Called when the song select screen goes away: on the way to gameplay, the
-- current steps are the chart about to be played. On the way back to the title
-- menu ResetLuaMods clears it anyway.
function RememberPlayedChart(pn, Steps)
    if not Steps then return end
    local Description = Steps:GetDescription() or ""
    LastPlayedChart[pn] = {
        StepsType = Steps:GetStepsType(),
        Meter = Steps:GetMeter(),
        Description = Description,
        Label = ChartLabel(Description),
    }
end

-- Index in Charts of the chart closest to Target (as stored by
-- RememberPlayedChart), or nil if there is no Target or no chart.
function ClosestChartIndex(Charts, Target)
    if not Target or not Charts or #Charts == 0 then return nil end
    local TargetIsCoop = Target.Meter == 99

    -- Smaller is better, compared in order
    local function Rank(Chart)
        local Meter = Chart:GetMeter()
        local Description = Chart:GetDescription() or ""
        return {
            math.abs(Meter - Target.Meter),
            ChartLabel(Description) == Target.Label and 0 or 1,
            Description == Target.Description and 0 or 1,
            Meter,
        }
    end

    local function Better(a, b)
        for k = 1, #a do
            if a[k] ~= b[k] then return a[k] < b[k] end
        end
        return false
    end

    local function Closest(Accept)
        local Best, BestRank
        for i, Chart in ipairs(Charts) do
            if Accept(Chart) then
                local ChartRank = Rank(Chart)
                if not Best or Better(ChartRank, BestRank) then Best, BestRank = i, ChartRank end
            end
        end
        return Best
    end

    local function SameKind(Chart) return (Chart:GetMeter() == 99) == TargetIsCoop end
    return Closest(function(Chart) return SameKind(Chart) and Chart:GetStepsType() == Target.StepsType end)
        or Closest(SameKind)
        or Closest(function() return true end)
end

local ResetLuaModsOriginal = ResetLuaMods

function ResetLuaMods(pn, ...)
    LastPlayedChart[pn] = nil
    return ResetLuaModsOriginal(pn, ...)
end
