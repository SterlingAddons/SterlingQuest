-- Sterling Quest Tracker: catch-up plans and quest sharing hints, built on Questie's database.
--   S.CatchupZones(partner)        zones where they finished (or hold) quests you haven't done
--   S.CatchupPlan(partner, zone)   those quests grouped: ready / in your log / locked behind a quest / level / not for you
--   S.CatchupStart(partner, zone)  turns the plan into a Path (pick-ups, then turn-ins)
--   S.ShareCandidates(partner)     what they could share with you, and you with them, when grouped
local ADDON, S = ...
local msg = S.msg

---------------------------------------------------------------------------
-- Questie access (everything through pcall; Questie may be missing or not ready yet)
---------------------------------------------------------------------------
local function mod(name)
  if type(QuestieLoader) ~= "table" or not QuestieLoader.ImportModule then return nil end
  local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
  if ok and type(m) == "table" then return m end
end
local function qdb() local db = mod("QuestieDB"); if db and db.QueryQuestSingle then return db end end
function S.HasQuestie() return qdb() ~= nil end
local function Q(qid, key)
  local db = qdb(); if not db then return nil end
  local ok, v = pcall(db.QueryQuestSingle, qid, key)
  if ok then return v end
end
local function NPC(id, key)
  local db = qdb(); if not (db and db.QueryNPCSingle) then return nil end
  local ok, v = pcall(db.QueryNPCSingle, id, key); if ok then return v end
end
local function OBJ(id, key)
  local db = qdb(); if not (db and db.QueryObjectSingle) then return nil end
  local ok, v = pcall(db.QueryObjectSingle, id, key); if ok then return v end
end
local function doable(qid)
  local db = qdb(); if not (db and db.IsDoable) then return nil end
  local ok, v = pcall(db.IsDoable, qid); if ok then return v and true or false end
end
local function whyNot(qid)
  local db = qdb(); if not (db and db.IsDoableVerbose) then return nil end
  local ok, text, _, state = pcall(db.IsDoableVerbose, qid, false, true, true)
  if ok then return text, state end
end
local function uiMapFor(areaId)
  local z = mod("ZoneDB")
  if not (z and z.GetUiMapIdByAreaId and areaId) then return nil end
  local ok, v = pcall(z.GetUiMapIdByAreaId, z, areaId); if ok then return v end
end
local function parentZone(areaId)
  local z = mod("ZoneDB")
  if not (z and z.GetParentZoneId and areaId) then return areaId end
  local ok, v = pcall(z.GetParentZoneId, z, areaId); if ok and v then return v end
  return areaId
end
local function mapName(uiMap)
  if uiMap and C_Map and C_Map.GetMapInfo then local ok, info = pcall(C_Map.GetMapInfo, uiMap); if ok and info and info.name then return info.name end end
  return nil
end

-- A name for an area with no world map of its own (dungeons, class or event quest groups):
-- Questie's zone names first (it also says which are dungeons), then the game's area table,
-- then Questie's quest categories (negative ids, like Hunter or Seasonal).
local function areaName(areaId)
  local l = mod("l10n")
  if l and type(l.zoneLookup) == "table" then
    for cont, list in pairs(l.zoneLookup) do
      local n = type(list) == "table" and list[areaId]
      if type(n) == "string" and n ~= "" then return n .. (cont == 9 and " (dungeon)" or "") end
    end
  end
  if C_Map and C_Map.GetAreaInfo and areaId and areaId > 0 then
    local ok, n = pcall(C_Map.GetAreaInfo, areaId); if ok and type(n) == "string" and n ~= "" then return n end
  end
  if l and type(l.questCategoryLookup) == "table" then
    local n = l.questCategoryLookup[areaId]; if type(n) == "string" and n ~= "" then return n .. " quests" end
  end
  return nil
end
S.CatchupAreaName = areaName

local function name(qid) return S.QuestName(qid) end

-- Where a quest starts / ends: npc or object name plus one spawn (areaId, x, y)
local function spot(by)
  if type(by) ~= "table" then return nil end
  local npcs, objs = by[1], by[2]
  local id = type(npcs) == "table" and npcs[1]
  local nm, spawns = nil, nil
  if id then nm, spawns = NPC(id, "name"), NPC(id, "spawns") end
  if not nm then
    id = type(objs) == "table" and objs[1]
    if id then nm, spawns = OBJ(id, "name"), OBJ(id, "spawns") end
  end
  if not nm then return nil end
  local area, x, y
  if type(spawns) == "table" then
    for a, list in pairs(spawns) do
      if type(list) == "table" and list[1] and list[1][1] and list[1][1] > 0 then area, x, y = a, list[1][1], list[1][2]; break end
    end
  end
  return { name = nm, area = area, x = x, y = y, map = uiMapFor(area) }
end

function S.PrereqSpot(qid) return spot(Q(qid, "startedBy")) end
function S.QuestieNPC(id, key) return NPC(id, key) end

-- Zone key for a quest: the parent area id from zoneOrSort, else the quest giver's zone. nil = unknown.
local function zoneOf(qid)
  local z = Q(qid, "zoneOrSort")
  if type(z) == "number" and z > 0 then return parentZone(z) end
  local s = spot(Q(qid, "startedBy"))
  if s and s.area then return parentZone(s.area) end
  return nil
end

---------------------------------------------------------------------------
-- Catch-up: quests a partner has done (or holds) that you haven't
---------------------------------------------------------------------------
local cache = {}
local function myStamp()
  local n = 0
  for _ in pairs(S.completed or {}) do n = n + 1 end
  for _ in pairs(S.log or {}) do n = n + 1 end
  return n
end

-- Zones: { { key=areaId, name=, map=uiMapId, quests={qid,...}, count= }, ... } sorted by name
function S.CatchupZones(partner)
  local sn = partner and S.snaps[partner]
  if not sn then return {} end
  if not S.HasQuestie() then return nil end
  S.Refresh()
  local stamp = (sn.seq or 0) .. ":" .. myStamp() .. ":" .. (UnitLevel("player") or 0)
  local c = cache[partner]
  if c and c.stamp == stamp then return c.zones end
  local byZone = {}
  local function consider(qid)
    if S.IsFlaggedDone(qid) then return end
    local z = zoneOf(qid)
    if not z then return end
    byZone[z] = byZone[z] or {}
    byZone[z][#byZone[z] + 1] = qid
  end
  for qid in pairs(sn.completed or {}) do consider(qid) end
  for qid in pairs(sn.log or {}) do if not (sn.completed and sn.completed[qid]) then consider(qid) end end
  local zones = {}
  for area, list in pairs(byZone) do
    local map = uiMapFor(area)
    table.sort(list)
    zones[#zones + 1] = { key = area, map = map, name = mapName(map) or areaName(area) or ("Zone " .. area), quests = list, count = #list }
  end
  table.sort(zones, function(a, b) return a.name < b.name end)
  cache[partner] = { stamp = stamp, zones = zones, plans = {} }
  return zones
end

-- The plan for one zone. Returns { groups = { {key, title, items={...}} }, total=, theirs=, mine= }
-- item: { qid, name, state, why, after (quest name), level, giver (spot), turnin (spot), inLog }
local STATE_ORDER = { ready = 1, inlog = 2, locked = 3, level = 4, other = 5 }
-- Questie's brief reasons ("Unavailable: Exclusive quest completed") in plain words
local PLAIN = { ["exclusive quest completed"] = "another quest replaced it", ["exclusive quest in quest log"] = "you took a different quest instead",
  ["class requirement"] = "wrong class", ["race requirement"] = "wrong race", ["profession missing"] = "needs a profession", ["profession skill"] = "needs more profession skill",
  ["profession rank"] = "needs a higher profession rank", ["event inactive"] = "holiday quest, not active now", ["automatically blacklisted"] = "Questie hides this one",
  ["disabling quest is active"] = "blocked by a quest in your log", ["disabling quest already turned in"] = "blocked by a quest you finished", ["incomplete pre-quest"] = "needs an earlier quest",
  ["incomplete pre-quest group"] = "needs earlier quests", ["reputation requirement"] = "needs reputation" }
function S.PlainReason(text)
  if type(text) ~= "string" then return "not available to you" end
  local r = text:gsub("^[^:]*:%s*", "")
  return PLAIN[r:lower()] or r
end
function S.CatchupPlan(partner, zoneKey)
  local zones = S.CatchupZones(partner)
  if not zones then return nil end
  local c = cache[partner]
  if c and c.plans[zoneKey] then return c.plans[zoneKey] end
  local zone
  for _, z in ipairs(zones) do if z.key == zoneKey then zone = z end end
  if not zone then return nil end
  local sn = S.snaps[partner]
  local myLevel = UnitLevel("player") or 0
  local zoneKeyName = zone.name
  local items = {}
  for _, qid in ipairs(zone.quests) do
    local it = { qid = qid, name = name(qid), level = Q(qid, "requiredLevel") or 0, qlevel = Q(qid, "questLevel") or 0 }
    it.giver = spot(Q(qid, "startedBy")); it.turnin = spot(Q(qid, "finishedBy"))
    it.theirs = sn.completed[qid] and "done" or (sn.log[qid] and "log") or nil
    if S.log[qid] then it.state = "inlog"; it.why = S.log[qid].complete and "ready to turn in" or "in your log"
    elseif it.level > myLevel then it.state = "level"; it.why = "needs lvl " .. it.level
    else
      local ok = doable(qid)
      if ok then it.state = "ready"
      else
        local text, st = whyNot(qid)
        local pre = Q(qid, "preQuestSingle"); local grp = Q(qid, "preQuestGroup")
        local missing
        for _, set in ipairs({ type(pre) == "table" and pre or {}, type(grp) == "table" and grp or {} }) do
          for _, pq in ipairs(set) do if pq > 0 and not S.IsFlaggedDone(pq) and not missing then missing = pq end end
        end
        if missing then
          it.state = "locked"; it.after = name(missing); it.afterId = missing
          local mz = zoneOf(missing); local mzMap = mz and uiMapFor(mz); it.afterZone = (mzMap and mapName(mzMap)) or (mz and areaName(mz)) or nil
          it.afterInLog = S.log[missing] ~= nil
          it.why = "Prerequisite: " .. it.after .. (it.afterInLog and " (in your log)" or (it.afterZone and it.afterZone ~= zoneKeyName and (" (" .. it.afterZone .. ")") or ""))
        else it.state = "other"; it.why = S.PlainReason(text) end
      end
    end
    items[#items + 1] = it
  end
  table.sort(items, function(a, b)
    if STATE_ORDER[a.state] ~= STATE_ORDER[b.state] then return STATE_ORDER[a.state] < STATE_ORDER[b.state] end
    if a.level ~= b.level then return a.level < b.level end
    if a.qlevel ~= b.qlevel then return a.qlevel < b.qlevel end
    return a.name < b.name
  end)
  -- locked quests: after their prerequisite when it is in the same list
  local pos = {}
  for i, it in ipairs(items) do pos[it.qid] = i end
  local ordered, placed = {}, {}
  local function place(it, depth)
    if placed[it.qid] or depth > 8 then return end
    if it.afterId and pos[it.afterId] then place(items[pos[it.afterId]], depth + 1) end
    placed[it.qid] = true; ordered[#ordered + 1] = it
  end
  for _, it in ipairs(items) do place(it, 0) end
  -- chains: a locked quest whose prerequisite is in this list hangs off that quest instead of
  -- taking its own row; the prerequisite gets it.chain = { next, next, ... } in order
  local byId = {}
  for _, it in ipairs(ordered) do byId[it.qid] = it end
  for _, it in ipairs(ordered) do
    if it.state == "locked" and it.afterId and byId[it.afterId] then
      -- walk up to the first quest that stands on its own
      local root, hops = byId[it.afterId], 0
      while root.state == "locked" and root.afterId and byId[root.afterId] and hops < 8 do root = byId[root.afterId]; hops = hops + 1 end
      if root ~= it then root.chain = root.chain or {}; root.chain[#root.chain + 1] = it; it.inChain = true end
    end
  end
  local groups = {}
  local titles = { ready = "Ready now", inlog = "In your log", locked = "Needs another quest first", level = "Level too high", other = "Not available to you" }
  for _, key in ipairs({ "ready", "inlog", "locked", "level", "other" }) do
    local g = { key = key, title = titles[key], items = {} }
    for _, it in ipairs(ordered) do if it.state == key and not it.inChain then g.items[#g.items + 1] = it end end
    if #g.items > 0 then groups[#groups + 1] = g end
  end
  local theirs = 0
  for qid in pairs(sn.completed or {}) do if zoneOf(qid) == zoneKey then theirs = theirs + 1 end end
  local mine = 0
  for qid in pairs(S.completed or {}) do if zoneOf(qid) == zoneKey then mine = mine + 1 end end
  local plan = { zone = zone, groups = groups, ordered = ordered, total = #items, theirs = theirs, mine = mine }
  if c then c.plans[zoneKey] = plan end
  return plan
end

-- Where to do a quest's objectives: the middle of the spawns of its first mob, object or item source,
-- in this zone when there are spawns here. nil = Questie doesn't know (the step still shows, no arrow).
local function centroid(spawns, wantMap)
  if type(spawns) ~= "table" then return nil end
  local best
  for area, list in pairs(spawns) do
    if type(list) == "table" and #list > 0 then
      local map = uiMapFor(area)
      if not best or (map == wantMap and best.map ~= wantMap) then best = { area = area, list = list, map = map } end
    end
  end
  if not best then return nil end
  local sx, sy, n = 0, 0, 0
  for i, pt in ipairs(best.list) do
    if i > 40 then break end
    if type(pt) == "table" and pt[1] and pt[1] > 0 then sx, sy, n = sx + pt[1], sy + pt[2], n + 1 end
  end
  if n == 0 then return nil end
  return { map = best.map, x = sx / n, y = sy / n }
end
-- Questie's own normalised objective list for a quest (monsters, objects, items, kill credit, explore
-- events), plus the raw fields it builds from. Missing pieces just come back empty.
local function objectiveData(qid)
  local db = qdb()
  if db and db.GetQuest then
    local ok, q = pcall(db.GetQuest, qid)
    if ok and type(q) == "table" then
      local list = {}
      for _, o in ipairs(type(q.ObjectiveData) == "table" and q.ObjectiveData or {}) do if type(o) == "table" then list[#list + 1] = o end end
      if type(q.SpecialObjectives) == "table" then for _, o in pairs(q.SpecialObjectives) do if type(o) == "table" then list[#list + 1] = o end end end
      if #list > 0 then return list end
    end
  end
  -- older Questie: read the raw fields
  local list = {}
  local o = Q(qid, "objectives")
  if type(o) == "table" then
    for _, c in ipairs(type(o[1]) == "table" and o[1] or {}) do list[#list + 1] = { Type = "monster", Id = c[1], Text = c[2] } end
    for _, c in ipairs(type(o[2]) == "table" and o[2] or {}) do list[#list + 1] = { Type = "object", Id = c[1], Text = c[2] } end
    for _, c in ipairs(type(o[3]) == "table" and o[3] or {}) do list[#list + 1] = { Type = "item", Id = c[1], Text = c[2] } end
    for _, c in ipairs(type(o[5]) == "table" and o[5] or {}) do list[#list + 1] = { Type = "killcredit", IdList = c[1], Text = c[3] } end
    if type(o[6]) == "table" and next(o[6]) then list[#list + 1] = { Type = "spell" } end
    if type(o[4]) == "table" and o[4][1] then list[#list + 1] = { Type = "reputation" } end
  end
  local te = Q(qid, "triggerEnd")
  if type(te) == "table" then list[#list + 1] = { Type = "event", Text = te[1], Coordinates = te[2] } end
  local src = Q(qid, "requiredSourceItems")
  if type(src) == "table" then for _, id in ipairs(src) do list[#list + 1] = { Type = "item", Id = id } end end
  return list
end
-- Something to do between pick-up and turn-in? Questie's data first; for quests it has no objectives
-- for (common in Forever's own zones), a quest handed in to the same NPC that gave it almost always has.
local function hasObjectives(qid, it)
  if #objectiveData(qid) > 0 then return true end
  if it and it.giver and it.turnin and it.giver.name == it.turnin.name then return true end
  return false
end
local function itemSpawns(id)
  local db = qdb()
  if not (db and db.QueryItemSingle) then return {} end
  local out = {}
  local ok, drops = pcall(db.QueryItemSingle, id, "npcDrops")
  if ok and type(drops) == "table" then for i = 1, math.min(3, #drops) do out[#out + 1] = NPC(drops[i], "spawns") end end
  local ok2, odrops = pcall(db.QueryItemSingle, id, "objectDrops")
  if ok2 and type(odrops) == "table" then for i = 1, math.min(3, #odrops) do out[#out + 1] = OBJ(odrops[i], "spawns") end end
  return out
end
-- Where to do it, and what the first objective says.
local function objSpot(qid, wantMap)
  local text
  for _, o in ipairs(objectiveData(qid)) do
    text = text or o.Text
    local cands = {}
    if o.Type == "monster" and o.Id then cands[1] = NPC(o.Id, "spawns")
    elseif o.Type == "object" and o.Id then cands[1] = OBJ(o.Id, "spawns")
    elseif o.Type == "item" and o.Id then cands = itemSpawns(o.Id)
    elseif o.Type == "killcredit" and type(o.IdList) == "table" then for i = 1, math.min(3, #o.IdList) do cands[#cands + 1] = NPC(o.IdList[i], "spawns") end
    elseif o.Type == "event" then cands[1] = o.Coordinates end
    for _, sp in ipairs(cands) do
      local c = centroid(sp, wantMap)
      if c then c.text = o.Text or text; return c end
    end
  end
  return text and { text = text } or nil
end

-- Catch-up order: "theirs" (the order your partner finished them, 6.20+ partners) or "route" (shortest walk).
function S.CatchupOrder() return S.Opt("catchupOrder", "route") end

-- Turn the plan into stops: pick up, do (when it has objectives), turn in.
local function buildStops(plan, wantMap)
  local stops, byQ = {}, {}
  for _, it in ipairs(plan.ordered) do
    if it.state == "ready" or it.state == "inlog" or it.state == "locked" then
      local q = { it = it }
      local inLog = S.log[it.qid]
      local needDo = hasObjectives(it.qid, it) and not (inLog and inLog.complete)
      if not inLog then q.pick = { kind = "pickup", it = it, sp = it.giver, q = q } end
      if needDo then q.doit = { kind = "do", it = it, sp = objSpot(it.qid, wantMap), q = q } end
      q.turn = { kind = "turnin", it = it, sp = it.turnin, q = q }
      byQ[it.qid] = q
      stops[#stops + 1] = q
    end
  end
  return stops, byQ
end

local function emitOne(leg, s)
  local it = s.it
  local st = { kind = s.kind, qid = it.qid, quest = it.name, npc = s.sp and s.sp.name or nil }
  if s.sp and s.sp.map and s.sp.x then st.map, st.x, st.y = s.sp.map, s.sp.x, s.sp.y end
  if s.kind == "deliver" then
    st.npc = (s.sp and s.sp.name or "?") .. " >> " .. (s.after and s.after.name or "?")
    if s.after and s.after.map and s.after.x then st.tmap, st.tx, st.ty = s.after.map, s.after.x, s.after.y end
  elseif s.kind == "do" then st.npc = s.sp and s.sp.text or nil
  end
  leg.steps[#leg.steps + 1] = st
end
-- Stops in order -> path steps. A pick-up followed straight away by that quest's turn-in (nothing to do
-- in between, like a delivery) becomes one PICK TURN step that walks you from giver to turn-in NPC.
local function emitAll(leg, seq)
  local i = 1
  while i <= #seq do
    local s, nx = seq[i], seq[i + 1]
    if s.kind == "pickup" and nx and nx.kind == "turnin" and nx.q == s.q and s.sp and nx.sp then
      emitOne(leg, { kind = "deliver", it = s.it, sp = s.sp, after = nx.sp }); i = i + 2
    else
      emitOne(leg, s); i = i + 1
    end
  end
end

local function dist(a, b)
  if not (a and b and a.map and b.map and a.x and b.x) then return 500 end
  if a.map ~= b.map then return 1000 end
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Shortest walk: always the nearest stop you're allowed to do next (pick up before doing before turning in,
-- and a locked quest only after the quest it needs is turned in).
local function routeOrder(leg, stops, byQ, here)
  local list, done = {}, {}
  for _, q in ipairs(stops) do for _, k in ipairs({ "pick", "doit", "turn" }) do if q[k] then list[#list + 1] = q[k] end end end
  local seq = {}
  local function ready(s)
    local q, it = s.q, s.it
    if s.kind == "pickup" then
      local pre = it.afterId and byQ[it.afterId]
      if pre and pre.turn and not done[pre.turn] then return false end
      return true
    end
    if s.kind == "do" then return not q.pick or done[q.pick] end
    if s.kind == "turnin" then return (not q.pick or done[q.pick]) and (not q.doit or done[q.doit]) end
    return true
  end
  local cur = here
  local order = { pickup = 1, ["do"] = 2, turnin = 3 }
  while true do
    local best, bd
    for _, s in ipairs(list) do
      if not done[s] and ready(s) then
        local d = dist(cur, s.sp)
        if not best or d < bd - 0.01 or (math.abs(d - bd) <= 0.01 and order[s.kind] < order[best.kind]) then best, bd = s, d end
      end
    end
    if not best then break end
    done[best] = true; seq[#seq + 1] = best
    if best.sp and best.sp.x then cur = best.sp end
  end
  emitAll(leg, seq)
end

-- Their order: quests in the order your partner finished them. Pick-ups from the same quest giver are
-- grabbed together; a quest that needs another one waits for it.
local function theirOrder(leg, stops, byQ, rank)
  local seq = {}
  for _, q in ipairs(stops) do seq[#seq + 1] = q end
  table.sort(seq, function(a, b)
    local ra, rb = rank[a.it.qid], rank[b.it.qid]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return a.it.qid < b.it.qid
  end)
  local emitted, out = {}, {}
  local function put(s) if s and not emitted[s] then emitted[s] = true; out[#out + 1] = s end end
  local function doQuest(q, depth)
    if depth > 8 or emitted[q] then return end
    emitted[q] = true
    local pre = q.it.afterId and byQ[q.it.afterId]
    if pre then doQuest(pre, depth + 1) end
    if q.pick and not emitted[q.pick] then
      put(q.pick)
      -- grab everything else this quest giver has for you while you're there
      for _, o in ipairs(seq) do
        if o.pick and not emitted[o.pick] and o.it.state == "ready" and o.pick.sp and q.pick.sp and o.pick.sp.name == q.pick.sp.name then put(o.pick) end
      end
    end
    put(q.doit); put(q.turn)
  end
  for _, q in ipairs(seq) do doQuest(q, 0) end
  emitAll(leg, out)
end

-- Build a Path from the plan, in the chosen order.
function S.CatchupStart(partner, zoneKey, quiet)
  local plan = S.CatchupPlan(partner, zoneKey)
  if not plan then return false end
  local leg = { n = 1, title = plan.zone.name, sub = "Catching up to " .. S.PartnerLabel(partner), time = "", steps = {} }
  local stops, byQ = buildStops(plan, plan.zone.map)
  local sn = S.snaps[partner]
  local mode = S.CatchupOrder()
  if mode == "theirs" and not (sn and sn.ordered and sn.rank) then
    mode = "route"
    if not quiet then msg(S.PartnerLabel(partner) .. "'s Sterling doesn't send the order yet (needs 6.20). Using the shortest route instead.") end
  end
  if mode == "theirs" then theirOrder(leg, stops, byQ, sn.rank)
  else
    local m, x, y
    if S.PlayerPos then m, x, y = S.PlayerPos() end
    routeOrder(leg, stops, byQ, m and { map = m, x = x, y = y } or nil)
  end
  if #leg.steps == 0 then if not quiet then msg("Nothing to catch up on in " .. plan.zone.name .. ".") end return false end
  SterlingQuestDB.following = nil
  SterlingQuestDB.catchup = { who = partner, zone = zoneKey, name = plan.zone.name }
  S.catchupLabel = "Catching up to " .. S.PartnerLabel(partner) .. " in " .. plan.zone.name
  S.SetLegs({ leg })
  if S.MapSetSession then S.MapSetSession(nil) end
  if not quiet then msg(("Catch-up path: %d steps in %s, %s."):format(#leg.steps, plan.zone.name, mode == "theirs" and "in " .. S.PartnerLabel(partner) .. "'s order" or "shortest route")) end
  return true
end

-- After a /reload, rebuild the catch-up path once Questie is ready.
function S.CatchupRestore()
  local c = SterlingQuestDB.catchup
  if not c or SterlingQuestDB.following then return end
  if not S.HasQuestie() then return end
  if not S.CatchupStart(c.who, c.zone, true) then SterlingQuestDB.catchup = nil; S.catchupLabel = nil end
end

function S.CatchupClear()
  SterlingQuestDB.catchup = nil; S.catchupLabel = nil
end

-- Open the world map on a zone (Questie draws the pins there).
function S.ShowZoneOnMap(uiMap)
  if not uiMap then return end
  if OpenWorldMap then pcall(OpenWorldMap, uiMap)
  elseif WorldMapFrame then pcall(function() if not WorldMapFrame:IsShown() then ToggleWorldMap() end; WorldMapFrame:SetMapID(uiMap) end) end
end

---------------------------------------------------------------------------
-- Group hints: what a grouped partner could share with you, and you with them
---------------------------------------------------------------------------
-- Does a quest's requirements look met for a partner, going by their snapshot?
local function theirDoable(qid, sn)
  local lvl = Q(qid, "requiredLevel")
  if lvl and sn.level and sn.level > 0 and sn.level < lvl then return false, "needs lvl " .. lvl end
  local pre = Q(qid, "preQuestSingle")
  if type(pre) == "table" and #pre > 0 then
    local any = false
    for _, pq in ipairs(pre) do if sn.completed[pq] then any = true end end
    if not any then return false, "after " .. name(pre[1]) end
  end
  local grp = Q(qid, "preQuestGroup")
  if type(grp) == "table" then
    for _, pq in ipairs(grp) do if pq > 0 and not sn.completed[pq] then return false, "after " .. name(pq) end end
  end
  local ex = Q(qid, "exclusiveTo")
  if type(ex) == "table" then for _, eq in ipairs(ex) do if sn.completed[eq] or sn.log[eq] then return false, "they did " .. name(eq) .. " instead" end end end
  return true
end

function S.ShareCandidates(partner)
  local sn = S.snaps[partner]
  local out = { theirs = {}, mine = {} }
  if not sn then return out end
  S.Refresh()
  local questie = S.HasQuestie()
  for qid, q in pairs(sn.log or {}) do
    if not S.log[qid] and not S.IsFlaggedDone(qid) then
      local ok, why = true, nil
      if questie then
        local d = doable(qid)
        if d == false then
          local text, st = whyNot(qid)
          ok = false; why = S.PlainReason(text)
          local lvl = Q(qid, "requiredLevel"); if lvl and (UnitLevel("player") or 0) < lvl then why = "needs lvl " .. lvl end
        end
      end
      out.theirs[#out.theirs + 1] = { qid = qid, name = (q.title and q.title ~= "" and q.title) or name(qid), ok = ok, why = why }
    end
  end
  for qid, q in pairs(S.log or {}) do
    if not sn.log[qid] and not (sn.completed and sn.completed[qid]) then
      local can = S.CanShare(qid)
      if can ~= false then
        local ok, why = true, nil
        if questie then ok, why = theirDoable(qid, sn) end
        out.mine[#out.mine + 1] = { qid = qid, name = q.title or name(qid), ok = ok, why = why }
      end
    end
  end
  local function srt(a, b) if a.ok ~= b.ok then return a.ok end return a.name < b.name end
  table.sort(out.theirs, srt); table.sort(out.mine, srt)
  return out
end
