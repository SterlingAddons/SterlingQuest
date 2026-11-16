-- a small fake Questie: one zone with a handful of quests in every Catch-up state
do
  local Q = {
    [1] = { name = "Riverglade Cleanup", zoneOrSort = 500, requiredLevel = 35, questLevel = 36, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [2] = { name = "Fishy Business", zoneOrSort = 500, requiredLevel = 36, questLevel = 37, startedBy = { { 11 } }, finishedBy = { { 11 } } },
    [3] = { name = "Shrine Keeper of the Western Glade", zoneOrSort = 500, requiredLevel = 36, questLevel = 38, preQuestSingle = { 1 }, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [4] = { name = "The Glade Tyrant", zoneOrSort = 500, requiredLevel = 41, questLevel = 42, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [5] = { name = "Elsewhere", zoneOrSort = 600, requiredLevel = 30, startedBy = { { 12 } }, finishedBy = { { 12 } } },
    [6] = { name = "Already Mine", zoneOrSort = 500, requiredLevel = 30, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [7] = { name = "Class Only", zoneOrSort = 500, requiredLevel = 30, startedBy = { { 10 } }, finishedBy = { { 10 } } },
    [8] = { name = "A Very Long Quest Name That Goes On And On", zoneOrSort = 500, requiredLevel = 33, startedBy = { { 11 } }, finishedBy = { { 10 } } },
    [9] = { name = "Marsh Lights", zoneOrSort = 500, requiredLevel = 34, startedBy = { { 11 } }, finishedBy = { { 11 } } },
  }
  local N = { [10] = { name = "Warden Tal", spawns = { [500] = { { 40.5, 60.2 } } } }, [11] = { name = "Old Marn the Fisher", spawns = { [500] = { { 55, 61 } } } }, [12] = { name = "Far Guy", spawns = { [600] = { { 10, 10 } } } } }
  QUESTIE_Q, QUESTIE_N = Q, N   -- tests can add quests
  local DB = {
    QueryQuestSingle = function(id, k) return Q[id] and Q[id][k] end,
    QueryNPCSingle = function(id, k) return N[id] and N[id][k] end,
    QueryObjectSingle = function() return nil end,
    QueryItemSingle = function() return nil end,
    GetQuest = function(id) return Q[id] and { ObjectiveData = {} } or nil end,
    IsDoable = function(id) if id == 3 or id == 7 then return false end return true end,
    IsDoableVerbose = function(id) if id == 3 then return "Unavailable: Incomplete pre-quest", true, 7 end if id == 7 then return "Unavailable: Class requirement", true, 8 end return "Available", true, 0 end,
  }
  local ZDB = { GetUiMapIdByAreaId = function(_, a) return a == 500 and 1500 or (a == 600 and 1600) or (a == 33 and 1434) end, GetParentZoneId = function(_, a) return a end }
  QuestieLoader = { ImportModule = function(_, n) if n == "QuestieDB" then return DB elseif n == "ZoneDB" then return ZDB end return {} end }
  Questie = { db = { char = { journey = {} } } }
  C_Map.GetMapInfo = function(id) return { name = id == 1500 and "Riverglades" or (id == 1600 and "Riverpaw Hollow" or (id == 1434 and "Stranglethorn Vale" or "Zone")) } end
  C_Map.GetBestMapForUnit = function() return 1500 end
end
