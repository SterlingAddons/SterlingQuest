local S = ...

local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then local ok, e = pcall(h, f, ev, ...); if not ok then print("ERR " .. ev .. ": " .. e) end end end end

fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)

UnitLevel = function() return 38 end

local Q =
{
    [1] = { name = "Riverglade Cleanup", zoneOrSort = 500, requiredLevel = 35, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [2] = { name = "Fishy Business", zoneOrSort = 500, requiredLevel = 36, startedBy = { { 11 } }, finishedBy = { { 11 } } },
    [3] = { name = "Shrine Keeper", zoneOrSort = 500, requiredLevel = 36, preQuestSingle = { 1 }, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [4] = { name = "The Glade Tyrant", zoneOrSort = 500, requiredLevel = 41, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [5] = { name = "Elsewhere", zoneOrSort = 600, requiredLevel = 30, startedBy = { { 12 } }, finishedBy = { { 12 } } },
    [6] = { name = "Already Mine", zoneOrSort = 500, requiredLevel = 30, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [7] = { name = "Class Only", zoneOrSort = 500, requiredLevel = 30, startedBy = { { 10 } }, finishedBy = { { 10 } } },
}

local N = { [10] = { name = "Warden Tal", spawns = { [500] = { { 40.5, 60.2 } } } }, [11] = { name = "Old Marn", spawns = { [500] = { { 55, 61 } } } }, [12] = { name = "Far Guy", spawns = { [600] = { { 10, 10 } } } } }
local DB =
{
    QueryQuestSingle = function(id, k) return Q[id] and Q[id][k] end,
    QueryNPCSingle = function(id, k) return N[id] and N[id][k] end,
    QueryObjectSingle = function() return nil end,
    IsDoable = function(id) if id == 3 then return false end if id == 7 then return false end return true end,
    IsDoableVerbose = function(id) if id == 3 then return "Unavailable: Incomplete pre-quest", true, 7 end if id == 7 then return "Unavailable: Class requirement", true, 8 end return "Available", true, 0 end,
}

local ZDB = { GetUiMapIdByAreaId = function(_, a) return a == 500 and 1500 or (a == 600 and 1600) end, GetParentZoneId = function(_, a) return a end }

QuestieLoader = { ImportModule = function(_, n) if n == "QuestieDB" then return DB elseif n == "ZoneDB" then return ZDB end return {} end }
C_Map.GetMapInfo = function(id) return { name = id == 1500 and "Riverglades" or "Riverpaw Hollow" } end
C_Map.GetBestMapForUnit = function() return 1500 end
S.ReadCompleted = function() return { [6] = true } end
S.ReadLog = function() return {} end
SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true } }
S.snaps["Brannoc Ashvale"] = { log = { [2] = { title = "Fishy Business", complete = false, objs = {} } }, completed = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true }, seq = 3, at = time(), level = 39, source = "live", name = "Brannoc Ashvale" }

local zones = S.CatchupZones("Brannoc Ashvale")

for _, z in ipairs(zones) do print("zone:", z.name, z.count, z.map) end

local plan = S.CatchupPlan("Brannoc Ashvale", 500)

print("plan total:", plan.total, "theirs:", plan.theirs, "mine:", plan.mine)

for _, g in ipairs(plan.groups) do local names = {}; for _, it in ipairs(g.items) do names[#names + 1] = it.name .. (it.why and (" [" .. it.why .. "]") or "") end; print("  " .. g.title .. ": " .. table.concat(names, ", ")) end

print("start:", S.CatchupStart("Brannoc Ashvale", 500))

for i, st in ipairs(S.steps) do print("  step", i, st.kind, st.quest, st.npc, st.map, st.x, st.y) end

print("label:", S.catchupLabel, "saved:", SterlingQuestDB.catchup and SterlingQuestDB.catchup.name)
S.UI_Toggle(true); print("catchup tab:", pcall(function() S.UI_Tab("catchup"); S.UI_Update() end))
S.StopFollowing(); print("after stop:", S.catchupLabel, SterlingQuestDB.catchup)

-- share candidates with questie
S.ReadLog = function() return { [6] = { title = "Already Mine", complete = false }, [9] = { title = "My Own", complete = false } } end
Q[9] = { name = "My Own", requiredLevel = 45 }

local c = S.ShareCandidates("Brannoc Ashvale")

for _, it in ipairs(c.theirs) do print("they can share:", it.name, it.ok, it.why) end
for _, it in ipairs(c.mine) do print("I can share:", it.name, it.ok, it.why) end

local plan2 = S.CatchupPlan("Brannoc Ashvale", 500)

for _, g in ipairs(plan2.groups) do for _, it in ipairs(g.items) do if it.chain then local n = {}; for _, c in ipairs(it.chain) do n[#n+1] = c.name end; print("chain under", it.name, ":", table.concat(n, " > ")) end end end

S.UI_Toggle(true); S.catchupWho = "Brannoc Ashvale"; print("catchup page w/ chain:", pcall(function() S.UI_Tab("catchup"); S.UI_Update() end))

-- zone search keeps the pick
local pg

for _, f in ipairs(FRAMES) do if rawget(f, "zoneRows") then pg = f end end

pg.zone = 500; pg.search:SetText("paw"); pg.scrollToSel = true; S.UI_Update(); print("search 'paw' picks:", pg.zone)
pg.search:SetText(""); pg.scrollToSel = true; S.UI_Update(); print("after clearing search still:", pg.zone)

print("clear button:", pcall(function() for _, f in ipairs(FRAMES) do if f._text == "Clear" and f._scripts.OnClick then f._scripts.OnClick(f) end end end))
