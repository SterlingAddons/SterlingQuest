local S = ...

local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then local ok, e = pcall(h, f, ev, ...); if not ok then print("ERR " .. ev .. ": " .. e) end end end end

fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)

UnitLevel = function() return 40 end

-- giver A at (10,10), giver B at (90,90), C at (50,50); mobs for kill quest near (85,85)
local Q =
{
    [1] = { name = "Deliver Letter", zoneOrSort = 500, requiredLevel = 1, startedBy = { { 10 } }, finishedBy = { { 12 } } },
    [2] = { name = "Kill Boars", zoneOrSort = 500, requiredLevel = 1, startedBy = { { 11 } }, finishedBy = { { 11 } }, objectives = { { { 50, "Boar slain" } } } },
    [3] = { name = "Far Errand", zoneOrSort = 500, requiredLevel = 1, startedBy = { { 10 } }, finishedBy = { { 10 } }, objectives = { { { 51, "Wolf slain" } } } },
    [4] = { name = "Follow-up", zoneOrSort = 500, requiredLevel = 1, preQuestSingle = { 2 }, startedBy = { { 11 } }, finishedBy = { { 12 } } },
}

local N =
{
    [10] = { name = "Gornek", spawns = { [500] = { { 10, 10 } } } },
    [11] = { name = "Huntress", spawns = { [500] = { { 90, 90 } } } },
    [12] = { name = "Jen'shan", spawns = { [500] = { { 50, 50 } } } },
    [50] = { name = "Boar", spawns = { [500] = { { 84, 84 }, { 86, 86 } } } },
    [51] = { name = "Wolf", spawns = { [500] = { { 15, 12 } } } },
}

local DB =
{
    QueryQuestSingle = function(id, k) return Q[id] and Q[id][k] end,
    QueryNPCSingle = function(id, k) return N[id] and N[id][k] end,
    QueryObjectSingle = function() return nil end,
    IsDoable = function(id) return id ~= 4 end,
    IsDoableVerbose = function(id) if id == 4 then return "Unavailable: Incomplete pre-quest", true, 7 end return "Available", true, 0 end,
}

local ZDB = { GetUiMapIdByAreaId = function(_, a) return a == 500 and 1500 end, GetParentZoneId = function(_, a) return a end }

QuestieLoader = { ImportModule = function(_, n) if n == "QuestieDB" then return DB elseif n == "ZoneDB" then return ZDB end return {} end }
C_Map.GetMapInfo = function(id) return { name = "Durotar" } end
C_Map.GetBestMapForUnit = function() return 1500 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return .12, .12 end } end
S.ReadCompleted = function() return {} end
S.ReadLog = function() return {} end
SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true } }

-- the partner did them: Kill Boars, Follow-up, Far Errand, Deliver Letter
local snapStr = "STR3^Brannoc Ashvale^Forever^40^^2,4,3,1^" .. time() .. "^=^5^L5^o"
local snap = S.ParseSnapshot(snapStr)

print("parsed ordered:", snap.ordered, "ranks 2,4,3,1:", snap.rank[2], snap.rank[4], snap.rank[3], snap.rank[1])
print("round trip keeps order:", S.SnapshotToString(snap):match("%^([%d,]+)%^%d+%^=") )

snap.source = "live"
S.snaps["Brannoc Ashvale"] = snap

local function show(label)
    local out = {}

    for _, st in ipairs(S.steps) do out[#out + 1] = st.kind .. ":" .. st.quest .. (st.npc and ("(" .. st.npc .. ")") or "") end

    print(label .. ": " .. table.concat(out, " | "))
end

SterlingQuestDB.opts.catchupOrder = "route"

print("start route:", S.CatchupStart("Brannoc Ashvale", 500, true)); show("route")

SterlingQuestDB.opts.catchupOrder = "theirs"

print("start theirs:", S.CatchupStart("Brannoc Ashvale", 500, true)); show("theirs")

-- older partner (unordered) falls back to route
snap.ordered = false

print("start theirs, old partner:", S.CatchupStart("Brannoc Ashvale", 500, true)); show("fallback")

-- the pill and path tab draw the new kind
S.UI_Toggle(true)
print("path tab:", pcall(function() S.UI_Tab("path"); S.UI_Update() end))
print("catch-up tab:", pcall(function() S.UI_Tab("catchup"); S.UI_Update() end))

-- sender side: Questie journey order
Questie = { db = { char = { journey = { { Event = "Quest", SubType = "Complete", Quest = 30, Timestamp = 1 }, { Event = "Level", NewLevel = 5 }, { Event = "Quest", SubType = "Complete", Quest = 10, Timestamp = 2 }, { Event = "Quest", SubType = "Complete", Quest = 20, Timestamp = 3 } } } } }
S.ReadCompleted = function() return { [10] = true, [20] = true, [30] = true, [5] = true } end
S.completed = { [10] = true, [20] = true, [30] = true, [5] = true }
S.Refresh = function() end

print("my snapshot done list:", S.MakeSnapshot(1):match("%^([%d,]*)%^%d+%^=") )
