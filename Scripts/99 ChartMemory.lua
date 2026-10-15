-- Not part of upstream Infinitesimal
-- (https://github.com/Team-Infinitesimal/Infinitesimal): added in the
-- RazZziel/Infinitesimal fork. ScreenSelectMusicFull underlay/ChartDisplay.lua
-- calls it.
--
-- Remembers the chart each player played last and, when the song wheel lands on
-- a song, preselects that song's chart closest to it:
--   1. same StepsType (single, half-double, double...), closest level;
--   2. if the song has none of that type, the closest level of any type;
--   ties go to the lower level. Co-op charts (level 99, shown as "??") only
--   stand in for co-op charts, and the other way round.
-- Moving the cursor by hand is kept until the song changes, and only the chart
-- that is played is remembered.
--
-- Kept for the credit, like the remembered group and song: going back to the
-- title menu (ResetLuaMods) forgets it.

LastPlayedChart = {}

-- Called when the song select screen goes away: on the way to gameplay, the
-- current steps are the chart about to be played. On the way back to the title
-- menu ResetLuaMods clears it anyway.
function RememberPlayedChart(pn, Steps)
    if not Steps then return end
    LastPlayedChart[pn] = { StepsType = Steps:GetStepsType(), Meter = Steps:GetMeter() }
end

-- Index in Charts of the chart closest to Target ({ StepsType, Meter }), or nil
-- if there is no Target or no chart.
function ClosestChartIndex(Charts, Target)
    if not Target or not Charts or #Charts == 0 then return nil end
    local TargetIsCoop = Target.Meter == 99

    local function Closest(Accept)
        local Best, BestDiff, BestMeter
        for i, Chart in ipairs(Charts) do
            if Accept(Chart) then
                local Meter = Chart:GetMeter()
                local Diff = math.abs(Meter - Target.Meter)
                if not Best or Diff < BestDiff or (Diff == BestDiff and Meter < BestMeter) then
                    Best, BestDiff, BestMeter = i, Diff, Meter
                end
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
