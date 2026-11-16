-- Sterling 3: quest state, compare, live sync, and the path engine that follows a recorded session.
local ADDON, S = ...
Sterling = S
S.PREFIX = "SterlingQuest"
S.VERSION = 6          -- sync protocol; both sides must match or nothing is exchanged

local function msg(text) DEFAULT_CHAT_FRAME:AddMessage("|cff8ab8ffSterling Quest Tracker:|r " .. tostring(text)) end
S.msg = msg
-- Chat detail per area (Options > Chat detail): 0 quiet (failures only), 1 simple, 2 advanced, 3 full.
-- Areas: sync, tooltip. Old debug_<area> toggles count as full.
S.CHAT_LEVELS = { [0] = "Quiet", [1] = "Simple", [2] = "Advanced", [3] = "Full" }
function S.ChatLevel(area)
  local o = SterlingQuestDB and SterlingQuestDB.opts
  if not o then return 0 end
  local v = o["chat_" .. area]
  if v == nil then return o["debug_" .. area] and 3 or 0 end
  return v
end
-- say(area, level, text): printed when the area's chat detail is at least `level`. Level 0 always prints.
local function say(area, level, text)
  if S.ChatLevel(area) < (level or 0) then return false end
  if level and level >= 3 then DEFAULT_CHAT_FRAME:AddMessage("|cff8a93a8[STQ " .. area .. " " .. date("%H:%M:%S") .. "]|r " .. tostring(text))
  else msg(text) end
  return true
end
S.Say = say
local function dbg(area, text) say(area, 3, text) end
S.Debug = dbg
-- One readable line for a sync message: chunk parts as "SNAP 3/20 (#id)", others by their first words.
local function describe(text)
  local kind, id, i, n, chunk = text:match("^(%u+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
  if kind then return kind .. " part " .. i .. "/" .. n .. " (#" .. id .. ", " .. #chunk .. " bytes)", tonumber(i), tonumber(n) end
  return (text:gsub("\t", " "):sub(1, 60))
end
S.DescribeSync = describe

-- Run fn safely. One bad frame of drawing must never take the whole addon down.
local errCount, lastErr = 0, 0
function S.Safe(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return true end
  errCount = errCount + 1
  if GetTime() - lastErr > 30 then
    lastErr = GetTime()
    msg("|cffff6060Hit a snag in " .. what .. ":|r " .. tostring(err):sub(1, 160))
    if errCount > 5 then msg("If this keeps happening, /reload and report the message above on Sterling's GitHub page.") end
  end
  return false
end
function S.Opt(key, default) local v = SterlingQuestDB and SterlingQuestDB.opts and SterlingQuestDB.opts[key]; if v == nil then return default end return v end
function S.InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Quest log state
---------------------------------------------------------------------------
local function tryCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end

function S.ReadLog()
  local log = {}
  local n = (GetNumQuestLogEntries and GetNumQuestLogEntries())
         or (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
  for i = 1, n do
    local title, isHeader, isComplete, questID
    if GetQuestLogTitle then
      title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
    elseif C_QuestLog and C_QuestLog.GetInfo then
      local info = C_QuestLog.GetInfo(i)
      if info then title, isHeader, questID = info.title, info.isHeader, info.questID end
    end
    if not isHeader and questID and questID > 0 then
      local done = (isComplete == 1 or isComplete == true)
      if not done and C_QuestLog and C_QuestLog.IsComplete then
        local ok, v = pcall(C_QuestLog.IsComplete, questID); if ok and v then done = true end
      end
      log[questID] = { title = title or ("Quest " .. questID), complete = done, index = i }
    end
  end
  return log
end

function S.ReadCompleted()
  local set = {}
  local list = tryCall(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
  if type(list) == "table" then for _, id in ipairs(list) do set[id] = true end return set end
  local t = tryCall(GetQuestsCompleted)
  if type(t) == "table" then for id in pairs(t) do set[id] = true end end
  return set
end

function S.IsFlaggedDone(qid)
  if not qid then return false end
  if S.completed[qid] then return true end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid); if ok and v then return true end
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, qid); if ok and v then return true end
  end
  return false
end

S.log, S.completed, S.names = {}, {}, {}
function S.Refresh()
  S.log = S.ReadLog()
  S.completed = S.ReadCompleted()
  for qid, q in pairs(S.log) do S.names[qid] = q.title; S.LearnName(qid, q.title) end
end

local function questieName(qid)
  if type(QuestieLoader) ~= "table" or not QuestieLoader.ImportModule then return nil end
  local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
  if not ok or not db or not db.QueryQuestSingle then return nil end
  local ok2, name = pcall(db.QueryQuestSingle, qid, "name")
  if ok2 and type(name) == "string" and name ~= "" then return name end
end
-- Remember a quest name for good (SavedVariables), from any log or session we see.
function S.LearnName(qid, name)
  if not qid or not name or name == "" or name:find("^Quest #") then return end
  SterlingQuestDB.names = SterlingQuestDB.names or {}
  if SterlingQuestDB.names[qid] ~= name then SterlingQuestDB.names[qid] = name end
end
function S.QuestName(qid)
  if S.names[qid] then return S.names[qid] end
  for _, sn in pairs(S.snaps or {}) do if sn.log[qid] and sn.log[qid].title and sn.log[qid].title ~= "" then return sn.log[qid].title end end
  if SterlingQuestDB and SterlingQuestDB.names and SterlingQuestDB.names[qid] then return SterlingQuestDB.names[qid] end
  local qn = questieName(qid); if qn then S.LearnName(qid, qn); return qn end
  if C_QuestLog and C_QuestLog.GetQuestInfo then
    local ok, t = pcall(C_QuestLog.GetQuestInfo, qid); if ok and t and t ~= "" then return t end
  end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid); if ok and t and t ~= "" then return t end
  end
  return "Quest #" .. qid
end

---------------------------------------------------------------------------
-- Profile: how you appear on the map (display name, race face, color). Shared with partners.
---------------------------------------------------------------------------
S.COLORS = {
  { key = "gold",   name = "Gold",   rgb = { 1, .8, .1 } },
  { key = "red",    name = "Red",    rgb = { .95, .25, .25 } },
  { key = "blue",   name = "Blue",   rgb = { .35, .55, 1 } },
  { key = "green",  name = "Green",  rgb = { .35, .85, .45 } },
  { key = "purple", name = "Purple", rgb = { .72, .5, 1 } },
  { key = "orange", name = "Orange", rgb = { 1, .55, .15 } },
  { key = "pink",   name = "Pink",   rgb = { 1, .5, .8 } },
  { key = "teal",   name = "Teal",   rgb = { .25, .85, .85 } },
  { key = "white",  name = "White",  rgb = { 1, 1, 1 } },
}
S.RACES = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", "SkyborneElf" }
S.RACE_NAME = { Human = "Human", Dwarf = "Dwarf", NightElf = "Night Elf", Gnome = "Gnome", Orc = "Orc", Scourge = "Undead", Tauren = "Tauren", Troll = "Troll", SkyborneElf = "Skyborne" }
local ATLAS = { Human = "raceicon-human-male", Dwarf = "raceicon-dwarf-male", NightElf = "raceicon-nightelf-male", Gnome = "raceicon-gnome-male",
                Orc = "raceicon-orc-male", Scourge = "raceicon-undead-male", Tauren = "raceicon-tauren-male", Troll = "raceicon-troll-male",
                SkyborneElf = "raceicon-bloodelf-male" }   -- Skyborne Elves share the Blood Elf look
-- whatever the client calls them (SkyborneElf, Skyborne, Skyelf...), treat it as one race
local function normRace(tok)
  if not tok then return nil end
  if tok:lower():find("sky") then return "SkyborneElf" end
  return tok
end
S.NormRace = normRace
-- the player's own race token is always accepted, even one this list doesn't know yet
local function knownRace(tok) for _, r in ipairs(S.RACES) do if r == tok then return true end end return false end
local SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"
local COORDS = { Human = { 0, .25, 0, .25 }, Dwarf = { .25, .5, 0, .25 }, Gnome = { .5, .75, 0, .25 }, NightElf = { .75, 1, 0, .25 },
                 Tauren = { 0, .25, .25, .5 }, Scourge = { .25, .5, .25, .5 }, Troll = { .5, .75, .25, .5 }, Orc = { .75, 1, .25, .5 } }

function S.ColorRGB(key)
  for _, c in ipairs(S.COLORS) do if c.key == key then return c.rgb[1], c.rgb[2], c.rgb[3] end end
  return 1, .8, .1
end

-- Put a race face on a texture. Tries the client's atlas, then the classic sprite sheet, then a plain tile.
function S.SetFace(t, race)
  race = race or "Troll"
  race = normRace(race)
  local atlas = ATLAS[race] or ("raceicon-" .. race:lower() .. "-male")
  local tries = { atlas, "raceicon128-" .. race:lower() .. "-male", "raceicon-" .. race:lower() .. "-female" }
  if race == "SkyborneElf" then
    -- the client's own Skyborne portrait first, the Blood Elf one as a stand-in
    tries = { "raceicon-skyborne-male", "raceicon128-skyborne-male", "raceicon-skyborne-female", "raceicon-skyborneelf-male",
              "raceicon-bloodelf-male", "raceicon128-bloodelf-male", "raceicon-bloodelf-female" }
  end
  if t.SetAtlas then
    for _, name in ipairs(tries) do
      local ok = pcall(t.SetAtlas, t, name)
      if ok and (not t.GetAtlas or t:GetAtlas()) then t:SetTexCoord(0, 1, 0, 1) return "atlas" end
    end
  end
  if COORDS[race] then
    local ok = t:SetTexture(SHEET)
    if ok ~= false then local c = COORDS[race]; t:SetTexCoord(c[1], c[2], c[3], c[4]) return "sheet" end
  end
  -- unknown race or no art: a plain tile (tinted by the caller) with nothing else
  t:SetTexture(nil); t:SetColorTexture(.6, .6, .65, 1); return "plain"
end
S.FaceSource = function(race) local t = UIParent:CreateTexture(); local how = S.SetFace(t, race); t:Hide(); return how end

function S.Profile()
  SterlingQuestDB.profile = SterlingQuestDB.profile or {}
  local p = SterlingQuestDB.profile
  if not p.name or p.name == "" then p.name = S.MyName() end
  if p.race then p.race = normRace(p.race) end
  if not p.race then
    local _, token = UnitRace("player"); token = normRace(token)
    p.race = token or "Troll"
    if token and not knownRace(token) then table.insert(S.RACES, token); S.RACE_NAME[token] = (UnitRace("player")) end
  end
  if not p.color then p.color = "gold" end
  return p
end
-- Someone else's look (from sync or a session), falling back to sensible defaults.
function S.LookFor(name, sess)
  local prof = S.profiles and S.profiles[name]
  local nick = S.Nickname and S.Nickname(name)
  if nick then
    local base = prof or (sess and { race = sess.race, color = sess.color }) or {}
    return { name = nick, race = base.race or "Troll", color = base.color or "gold" }
  end
  if prof then return prof end
  if sess and sess.race then return { name = sess.display or sess.char, race = sess.race, color = sess.color or "gold" } end
  if name == UnitName("player") or S.IsMe(name) then return S.Profile() end
  return { name = name, race = "Troll", color = "gold" }
end

function S.PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok or not pos then return nil end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return nil end
  return map, x * 100, y * 100
end

function S.MapName(map)
  if C_Map and C_Map.GetMapInfo and map then
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if ok and info and info.name then return info.name end
  end
  return "Unknown zone"
end

---------------------------------------------------------------------------
-- Snapshot (quest log only) for Compare
---------------------------------------------------------------------------
local function clean(s) return (tostring(s or ""):gsub("[|;,~%^:]", " ")) end
S.Clean = clean

-- Current log as qid -> encoded entry, plus the set of completed quest ids.
function S.SnapshotPieces()
  S.Refresh()
  local entries = {}
  for qid, q in pairs(S.log) do
    local objs = {}
    if S.ObjectiveList then for _, o in ipairs(S.ObjectiveList(qid, q.index)) do objs[#objs + 1] = clean(o.text):gsub("%s+", " ") end end
    entries[qid] = qid .. "." .. (q.complete and "c" or "a") .. "." .. clean(q.title) .. "." .. table.concat(objs, "~")
  end
  return entries, S.completed
end

-- The order this character finished its quests, from Questie's journey (every accept and turn-in,
-- timestamped, kept since Questie was installed). qid -> position; nil without Questie.
local rankCache, rankN
function S.CompletedRank()
  local q = rawget(_G, "Questie")
  local j = type(q) == "table" and q.db and q.db.char and q.db.char.journey
  if type(j) ~= "table" then return nil end
  if rankCache and rankN == #j then return rankCache end
  local r = {}
  for i, e in ipairs(j) do
    if type(e) == "table" and e.Event == "Quest" and e.SubType == "Complete" and tonumber(e.Quest) then r[tonumber(e.Quest)] = i end
  end
  rankCache, rankN = r, #j
  return r
end
-- Finished quests in the order they were done: anything Questie never saw first (by id), then by date.
local function orderDone(list)
  local r = S.CompletedRank()
  if not r then table.sort(list) return end
  table.sort(list, function(a, b)
    local ra, rb = r[a], r[b]
    if ra and rb then return ra < rb end
    if ra then return false end
    if rb then return true end
    return a < b
  end)
end

function S.MakeSnapshot(seq)
  local entries, completed = S.SnapshotPieces()
  local parts = {}
  for _, e in pairs(entries) do parts[#parts + 1] = e end
  table.sort(parts)
  local done = {}
  for qid in pairs(completed) do done[#done + 1] = qid end
  orderDone(done)
  return table.concat({ "STR3", clean(S.MyName()), clean(GetRealmName()), UnitLevel("player") or 0,
                        table.concat(parts, ";"), table.concat(done, ","), time(), "=", seq or 0 }, "^")
end

-- Snapshot table back to a string (used to persist a partner snapshot after applying deltas).
function S.SnapshotToString(snap)
  local parts = {}
  for qid, q in pairs(snap.log) do parts[#parts + 1] = qid .. "." .. (q.complete and "c" or "a") .. "." .. clean(q.title) .. "." .. table.concat(q.objs or {}, "~") end
  table.sort(parts)
  local done = {}
  for qid in pairs(snap.completed) do done[#done + 1] = qid end
  local rk = snap.rank or {}
  table.sort(done, function(a, b) local ra, rb = rk[a] or 0, rk[b] or 0; if ra ~= rb then return ra < rb end; return a < b end)
  return table.concat({ "STR3", clean(snap.name), clean(snap.realm), snap.level or 0, table.concat(parts, ";"), table.concat(done, ","), snap.at or time(), "=", snap.seq or 0, snap.label or "", snap.ordered and "o" or "" }, "^")
end

function S.ParseSnapshot(str)
  if type(str) ~= "string" then return nil, "empty" end
  str = str:gsub("^%s+", ""):gsub("%s+$", ""):gsub("||", "|"):gsub("[\r\n]", "")
  local sep = str:sub(1, 5) == "STR3^" and "^" or "|"
  local f = {}
  for piece in (str .. sep):gmatch("(.-)%" .. sep) do f[#f + 1] = piece end
  if not (f[1] == "STR1" or f[1] == "STR2" or f[1] == "STR3") then return nil, "not a Sterling Quest Tracker string" end
  local snap = { name = f[2], realm = f[3], level = tonumber(f[4]) or 0, log = {}, completed = {}, at = tonumber(f[7]) or 0, seq = tonumber(f[9]) or 0, label = f[10] }
  for item in (f[5] or ""):gmatch("[^;]+") do
    local qid, st, title, objs = item:match("^(%d+)%.(%a)%.([^%.]*)%.?(.*)$")
    if qid then
      local o = {}
      for t in (objs or ""):gmatch("[^~]+") do o[#o + 1] = t end
      snap.log[tonumber(qid)] = { title = title, complete = (st == "c"), objs = o }
    end
  end
  -- finished quests arrive in the order they were done when field 11 says so ("o", 6.20+)
  snap.rank, snap.rankMax, snap.ordered = {}, 0, f[11] == "o"
  for qid in (f[6] or ""):gmatch("%d+") do
    qid = tonumber(qid)
    if not snap.completed[qid] then snap.completed[qid] = true; snap.rankMax = snap.rankMax + 1; snap.rank[qid] = snap.rankMax end
  end
  return snap
end

-- Import anything: a session string or a quest-log snapshot.
function S.ImportString(str)
  str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if str:sub(1, 4) == "SES1" then
    local sess, err = S.DecodeSession(str)
    if not sess then msg("Couldn't read that session: " .. tostring(err)) return end
    sess.imported = true
    S.AddSession(sess)
    msg(("Imported %s's session \"%s\" (%s, %d events)."):format(sess.char, sess.name, S.Duration(sess), #sess.events))
    S.FollowSession(sess, true)
    return
  end
  local snap, err = S.ParseSnapshot(str)
  if not snap then msg("Couldn't read that: " .. err) return end
  snap.source = "import"
  S.AddPartner(snap.name, false)
  S.StoreSnap(snap.name, snap, str)
  S.SelectPartner(snap.name)
  msg("Imported " .. snap.name .. "'s quest log (level " .. snap.level .. ").")
  S.UI_Update()
end

---------------------------------------------------------------------------
-- Compare
---------------------------------------------------------------------------
function S.Diff()
  local p = S.partner
  if not p then return nil end
  S.Refresh()
  local d = { theyHave = {}, youHave = {}, theyFinished = {}, youFinished = {} }
  for qid, q in pairs(p.log) do
    if not S.log[qid] then d.theyHave[#d.theyHave + 1] = { qid = qid, title = q.title, complete = q.complete } end
  end
  for qid, q in pairs(S.log) do
    if not p.log[qid] then d.youHave[#d.youHave + 1] = { qid = qid, title = q.title, complete = q.complete } end
  end
  for qid in pairs(p.completed) do
    if not S.IsFlaggedDone(qid) then d.theyFinished[#d.theyFinished + 1] = { qid = qid, title = S.QuestName(qid), inLog = S.log[qid] ~= nil } end
  end
  for qid in pairs(S.completed) do
    if not p.completed[qid] then d.youFinished[#d.youFinished + 1] = { qid = qid, title = S.QuestName(qid), inLog = p.log[qid] ~= nil } end
  end
  d.shared = {}
  for qid, q in pairs(S.log) do
    local pq = p.log[qid]
    if pq then
      local mine = {}
      for _, o in ipairs(S.ObjectiveList(qid, q.index)) do mine[#mine + 1] = clean(o.text):gsub("%s+", " ") end
      local diff = {}
      for i = 1, math.max(#mine, #(pq.objs or {})) do
        local a, b = mine[i], pq.objs and pq.objs[i]
        if a ~= b and (a or b) then diff[#diff + 1] = { you = a, they = b } end
      end
      if #diff > 0 or q.complete ~= pq.complete then d.shared[#d.shared + 1] = { qid = qid, title = q.title, youDone = q.complete, theyDone = pq.complete, diff = diff } end
    end
  end
  for _, list in pairs(d) do table.sort(list, function(a, b) return a.title < b.title end) end
  return d
end

---------------------------------------------------------------------------
-- Live sync (quest snapshot + sessions on request)
---------------------------------------------------------------------------
local CHUNK = 240
local inbox, queue, draining = {}, {}, false
local heard, pinged = {}, {}          -- per partner name
S.snaps = {}                           -- name -> snapshot table (live / saved / import)
S.profiles = {}                        -- name -> { name=, race=, color= } learned from partners
-- Names compared without realm, case, spaces (including the no-break space the game uses in names
-- like "Kaelith Emberfall" in some messages) or hyphens, so one character always matches itself.
local function squash(n)
  n = tostring(n or ""):gsub("\194\160", ""):gsub("[%s%-_%.']", "")
  return n:lower()
end
S.SquashName = squash
local function stripRealm(n)
  n = tostring(n or "")
  for _, fn in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local f = _G[fn]
    if type(f) == "function" then
      local ok, r = pcall(f)
      if ok and type(r) == "string" and r ~= "" then
        local suf = "-" .. r:gsub("%s", "")
        if #n > #suf and n:sub(-#suf):lower() == suf:lower() then return n:sub(1, -#suf - 1) end
      end
    end
  end
  return (n:gsub("%-[^%-]+$", function(rest) return rest:find(" ") and rest or "" end))
end
-- Is this me? Works on raw senders ("Kaelith Emberfall-Realm"), short names and look-alikes.
-- Every spelling of my own name the game will give us. On this client UnitName("player") can return
-- only the first word of a name with a space ("Kaelith" for "Kaelith Emberfall"), while other players' messages
-- carry the full name, so we also ask the other name APIs and remember the full name once we see it.
do
  local seed = (time and time() or 0) + math.floor(((GetTime and GetTime()) or 0) * 1000) + math.floor(((type(debugprofilestop) == "function" and debugprofilestop()) or 0) * 1000)
  S.SESSION_TOKEN = tostring(math.random(100000, 999999)) .. tostring(seed % 1000000)
end
function S.MyNames()
  local set = {}
  local function add(n) if type(n) == "string" and n ~= "" and n ~= UNKNOWNOBJECT then set[squash(stripRealm(n))] = true end end
  local function try(fn, ...) if type(fn) == "function" then local ok, a = pcall(fn, ...); if ok then add(a) end end end
  try(UnitName, "player")
  try(UnitFullName, "player")
  try(GetUnitName, "player", true)
  if type(GetPlayerInfoByGUID) == "function" and type(UnitGUID) == "function" then
    local okG, guid = pcall(UnitGUID, "player")
    if okG and guid then local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, guid); if ok then add(n) end end
  end
  if SterlingQuestDB and SterlingQuestDB.myFullName then add(SterlingQuestDB.myFullName) end
  set[""] = nil
  return set
end
function S.IsMe(name)
  if not name or name == "" then return false end
  local set = S.MyNames()
  return set[squash(stripRealm(name))] or set[squash(name)] or false
end
-- Our own message came back with our session token: whatever name it carries is us.
function S.LearnMyName(n)
  if not n or n == "" or not SterlingQuestDB then return end
  if SterlingQuestDB.myFullName ~= n then SterlingQuestDB.myFullName = n; S.Debug("sync", "learned your full name: " .. n) end
end
-- My character's full name: the one learned from our own echoed messages, else the longest the game gives.
function S.MyName()
  if SterlingQuestDB and SterlingQuestDB.myFullName then return SterlingQuestDB.myFullName end
  local best = (pcall(UnitName, "player") and UnitName("player")) or "?"
  local function try(fn, ...) if type(fn) == "function" then local ok, a = pcall(fn, ...); if ok and type(a) == "string" and #a > #best then best = a end end end
  try(UnitFullName, "player"); try(GetUnitName, "player", false)
  if type(GetPlayerInfoByGUID) == "function" and type(UnitGUID) == "function" then
    local okG, guid = pcall(UnitGUID, "player")
    if okG and guid then local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, guid); if ok and type(n) == "string" and #n > #best then best = n end end
  end
  return (best:gsub("%-.*$", ""))
end
-- A partner whose character name starts with my name and whose profile is exactly mine is me.
function S.LooksLikeMe(name)
  if S.IsMe(name) then return true end
  local okM, me = pcall(UnitName, "player")
  if not okM or not me or me == "" then return false end
  local first = tostring(name or ""):match("^(%S+)")
  if not first or squash(first) ~= squash(me) or squash(name) == squash(me) then return false end
  local mine, theirs = S.Profile and S.Profile(), S.profiles and S.profiles[name]
  return mine and theirs and theirs.name == mine.name and theirs.race == mine.race and theirs.color == mine.color or false
end
local function sameName(a, b)
  if not a or not b then return false end
  if squash(a) == squash(b) then return true end
  a, b = a:lower():gsub("%-.*$", ""), b:lower():gsub("%-.*$", "")
  return squash(a) == squash(b)
end
S.sync = { sent = 0, recv = 0, bytesOut = 0, bytesIn = 0, snapsIn = 0, snapsOut = 0, sessIn = 0, sessOut = 0, per = {} }
-- Per-partner counters (persisted). bump("Brannoc", "sent", 1); for a group key every enabled partner in the group is credited.
local function perStat(name)
  SterlingQuestDB.syncStats = SterlingQuestDB.syncStats or {}
  SterlingQuestDB.syncStats[name] = SterlingQuestDB.syncStats[name] or { sent = 0, recv = 0, bytesOut = 0, bytesIn = 0, snapsOut = 0, deltasOut = 0, snapsIn = 0, deltasIn = 0, acks = 0, replays = 0, resyncs = 0, sessIn = 0, sessOut = 0 }
  return SterlingQuestDB.syncStats[name]
end
S.PerStat = perStat
local function namesForKey(key)
  if key:sub(1, 2) == "W:" then return { key:sub(3) } end
  local out = {}
  for _, p in ipairs(SterlingQuestDB.partners or {}) do
    if p.on and IsInGroup and IsInGroup() then
      local unit = IsInRaid() and "raid" or "party"
      for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do if sameName(UnitName(unit .. i), p.name) then out[#out + 1] = p.name end end
    end
  end
  return out
end
-- Same counters since login or /reload (not saved): S.SessionStat(name)
function S.SessionStat(name)
  S.sync.per[name] = S.sync.per[name] or { sent = 0, recv = 0, bytesOut = 0, bytesIn = 0, snapsOut = 0, deltasOut = 0, snapsIn = 0, deltasIn = 0, acks = 0, replays = 0, resyncs = 0, sessIn = 0, sessOut = 0 }
  return S.sync.per[name]
end
local function bump(keyOrName, field, n, stamp)
  local names = keyOrName:find("^W:") and namesForKey(keyOrName) or (keyOrName == "GROUP" and namesForKey("GROUP") or { keyOrName })
  for _, nm in ipairs(names) do
    local st = perStat(nm); st[field] = (st[field] or 0) + (n or 1); if stamp then st[stamp] = time() end
    local ss = S.SessionStat(nm); ss[field] = (ss[field] or 0) + (n or 1); if stamp then ss[stamp] = time() end
  end
end
-- The most recent sync event, for the Sync page: { text=, at= }
function S.SyncEvent(text) S.sync.lastEvent = { text = text, at = time() }; if S.UI_Update then S.UI_Update() end end


---------------------------------------------------------------------------
-- Partners: any number, each with its own on/off switch and its own snapshot.
---------------------------------------------------------------------------
local function shortName(n) return n and (n:match("^([^%-]+)") or n) or nil end

function S.Partners() SterlingQuestDB.partners = SterlingQuestDB.partners or {}; return SterlingQuestDB.partners end
function S.FindPartner(name)
  for i, p in ipairs(S.Partners()) do if sameName(p.name, name) then return p, i end end
end
function S.AddPartner(name, on)
  name = shortName(name); if not name or name == "" then return end
  if sameName(name, UnitName("player")) or S.IsMe(name) then return end
  local p = S.FindPartner(name)
  if p then if on ~= nil then p.on = on end return p end
  p = { name = name, on = (on ~= false) }
  table.insert(S.Partners(), p)
  return p
end
function S.RemovePartner(name)
  local p, i = S.FindPartner(name)
  if p then table.remove(S.Partners(), i); S.snaps[p.name] = nil; if SterlingQuestDB.snaps then SterlingQuestDB.snaps[p.name] = nil end end
  if SterlingQuestDB.compareWith and sameName(SterlingQuestDB.compareWith, name) then SterlingQuestDB.compareWith = nil end
  S.SelectPartner(nil)
end
function S.StoreSnap(name, snap, str)
  name = shortName(name)
  if sameName(name, UnitName("player")) then return end
  S.snaps[name] = snap
  if snap.label and snap.label ~= "" and snap.seq then
    SterlingQuestDB.recvLabels = SterlingQuestDB.recvLabels or {}
    SterlingQuestDB.recvLabels[name] = SterlingQuestDB.recvLabels[name] or {}
    SterlingQuestDB.recvLabels[name][snap.label] = snap.seq
  end
  for qid, q in pairs(snap.log) do S.LearnName(qid, q.title) end
  SterlingQuestDB.snaps = SterlingQuestDB.snaps or {}
  SterlingQuestDB.snaps[name] = str
end
-- Pick which partner the Compare tab looks at. nil = best available (selected, else first live, else any).
function S.SelectPartner(name)
  if name then SterlingQuestDB.compareWith = shortName(name) end
  local want = SterlingQuestDB.compareWith
  if want and S.snaps[want] then S.partner = S.snaps[want] return S.partner end
  local best
  for _, p in ipairs(S.Partners()) do
    local sn = S.snaps[p.name]
    if sn and (not best or (sn.source == "live" and best.source ~= "live")) then best = sn end
  end
  if not best then for _, sn in pairs(S.snaps) do best = best or sn end end
  S.partner = best
  return best
end

local function inGroup(name)
  if not (IsInGroup and IsInGroup()) then return false end
  local unit = IsInRaid() and "raid" or "party"
  for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
    if sameName(UnitName(unit .. i), name) then return true, UnitIsConnected(unit .. i) and true or false end
  end
  return false
end
-- Group sync (Options > Sync, off by default): talk to the whole party or raid at once and accept
-- anyone there who runs Sterling. Off: only your Sync list, each one whispered, group or not.
local function groupSync() return S.Opt("groupSync", false) end   -- off by default: partners are added by hand
local function useGroup(name) return groupSync() and inGroup(name) end

-- Returns online(bool), how("addon"/"group"/"friend"/"guild"/nil) for one partner name.
function S.PartnerStatus(name)
  name = name or (S.Partners()[1] and S.Partners()[1].name)
  if not name or name == "" then return false, nil end
  if heard[name] and GetTime() - heard[name] < 120 then return true, "addon" end
  local inG, conn = inGroup(name)
  if inG then return conn, "group" end
  if type(C_FriendList) == "table" and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, (C_FriendList.GetNumFriends() or 0) do
      local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
      if ok and info and sameName(info.name, name) then return info.connected and true or false, "friend" end
    end
  end
  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, (GetNumGuildMembers() or 0) do
      local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
      if sameName(gname, name) then return online and true or false, "guild" end
    end
  end
  return false, nil
end
-- What to call a partner: your nickname for them, else the name they chose, else their character's first name.
function S.Nickname(name) return SterlingQuestDB.nicknames and SterlingQuestDB.nicknames[shortName(name) or ""] end
function S.SetNickname(name, nick)
  name = shortName(name); if not name then return end
  SterlingQuestDB.nicknames = SterlingQuestDB.nicknames or {}
  nick = nick and nick:gsub("[|^:;,~]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  SterlingQuestDB.nicknames[name] = (nick ~= "" and nick:sub(1, 16)) or nil
  if S.ViewerRedraw then S.ViewerRedraw() end
end
-- Eye on the Sync page: show this partner in tooltips and the quest log (default on).
function S.PartnerShown(p) return p and p.show ~= false end
-- Class token for a partner (group, friends list or guild roster), for a colour before they've sent a profile.
function S.PartnerClass(name)
  if IsInGroup and IsInGroup() then
    local unit = IsInRaid() and "raid" or "party"
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
      if sameName(UnitName(unit .. i), name) then local _, cls = UnitClass(unit .. i); return cls end
    end
  end
  if type(C_FriendList) == "table" and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, (C_FriendList.GetNumFriends() or 0) do
      local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
      if ok and info and sameName(info.name, name) and info.className then
        for tok, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do if loc == info.className then return tok end end
        for tok, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do if loc == info.className then return tok end end
      end
    end
  end
  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, (GetNumGuildMembers() or 0) do
      local gname, _, _, _, _, _, _, _, _, _, cls = GetGuildRosterInfo(i)
      if sameName(gname, name) then return cls end
    end
  end
end
-- When we last got quest data from them (their snapshot's time), or nil.
function S.LastSynced(name) local sn = S.snaps[shortName(name) or ""]; return sn and sn.at or nil end
function S.PartnerLabel(name)
  local n = shortName(name) or "?"
  local nick = S.Nickname(n)
  if nick then return nick end
  local prof = S.profiles and S.profiles[n]
  if prof and prof.name and prof.name ~= "" and prof.name ~= n then return prof.name end
  return n:match("^(%S+)") or n
end
S.ADDON_VER = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
-- -1 if a is older than b, 1 if newer, 0 if the same or unknown. Compares 5.42 < 5.83 < 6.0 part by part.
function S.CompareVer(a, b)
  if not a or not b then return 0 end
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  if #pa == 0 or #pb == 0 then return 0 end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x < y then return -1 elseif x > y then return 1 end
  end
  return 0
end

function S.PartnerOnline(name) local on = S.PartnerStatus(name); return on end
function S.LastHeard(name)
  if name then return heard[name] and (GetTime() - heard[name]) or nil end
  local best
  for _, t in pairs(heard) do if not best or t > best then best = t end end
  return best and (GetTime() - best) or nil
end
-- Everyone a message should go to right now: the group as one target, plus each enabled partner
-- who is online but not in the group (whispered). Each target has a key for delta bookkeeping.
function S.Targets()
  local list = {}
  if groupSync() then
    if IsInRaid() then list[#list + 1] = { chan = "RAID", key = "GROUP" }
    elseif IsInGroup() then list[#list + 1] = { chan = "PARTY", key = "GROUP" } end
  end
  for _, p in ipairs(S.Partners()) do
    local kv = S.sync and S.sync.vers and S.sync.vers[p.name]
    local okVer = (kv == nil) or (kv == S.VERSION)
    if p.on and okVer and not useGroup(p.name) and S.PartnerOnline(p.name) then list[#list + 1] = { chan = "WHISPER", target = p.name, key = "W:" .. p.name } end
  end
  return list
end

local function channel() local t = S.Targets()[1]; if t then return t.chan, t.target end end

local function rawSend(item)
  local f = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if not f then return false end
  local ok, res
  if item.target then ok, res = pcall(f, S.PREFIX, item.text, item.chan, item.target) else ok, res = pcall(f, S.PREFIX, item.text, item.chan) end
  -- Newer clients return a result code (0 = sent); older ones return true/false. Anything else means
  -- the message was throttled or refused: report it so the queue can retry instead of losing it.
  if ok and (res == false or (type(res) == "number" and res ~= 0)) then
    S.sync.throttled = (S.sync.throttled or 0) + 1
    dbg("sync", "|cffff9b92refused by the game|r (code " .. tostring(res) .. "), will retry: to " .. (item.target or item.chan) .. " " .. describe(item.text))
    return false
  end
  if not ok then dbg("sync", "|cffff9b92send error|r: " .. tostring(res)) end
  do
    local d, i, n = describe(item.text)
    if not i or i == 1 or i == n then dbg("sync", "out to " .. (item.target or item.chan) .. ": " .. d .. ((i and n > 2 and i == 1) and "  ..." or "") .. "  |cff8a93a8(" .. #queue .. " queued)|r") end
    -- live progress for the Sync tab (only for logs big enough to take a moment)
    if i and n and n > 2 then S.sync.prog = { who = item.target and (item.target:match("^([^%-]+)") or item.target) or "group", dir = "out", got = i, n = n, t = GetTime() } end
  end
  S.sync.trace = S.sync.trace or {}
  table.insert(S.sync.trace, 1, date("%H:%M:%S") .. " out " .. (item.target or item.chan) .. ": " .. item.text:sub(1, 48):gsub("\t", " "))
  if #S.sync.trace > 30 then S.sync.trace[31] = nil end
  S.sync.sent = S.sync.sent + 1; S.sync.bytesOut = S.sync.bytesOut + #item.text; S.sync.lastOut = time(); S.sync.lastChan = item.target or item.chan
  local k = item.target and ("W:" .. item.target) or "GROUP"
  bump(k, "sent", 1, "lastOut"); bump(k, "bytesOut", #item.text)
  return true
end
-- Two messages per second, steady. A refused message goes back to the front and we wait a bit longer.
local function drain()
  if #queue == 0 then draining = false return end
  draining = true
  local wait = 0.5
  local t = table.remove(queue, 1)
  if t and rawSend(t) == false then
    t.tries = (t.tries or 0) + 1
    if t.tries <= 6 then table.insert(queue, 1, t) end
    wait = 1.5
  end
  C_Timer.After(wait, drain)
end
-- send to one target, or to every current target when tgt is nil
local function send(text, tgt)
  local targets = tgt and { tgt } or S.Targets()
  if #targets == 0 then return false end
  for _, t in ipairs(targets) do queue[#queue + 1] = { text = text, chan = t.chan, target = t.target } end
  if not draining then drain() end
  return true
end

local outbox, chunkN = {}, 0
local function sendChunked(kind, str, tgt)
  local n = math.ceil(#str / CHUNK)
  chunkN = (chunkN + 1) % 10
  local id = tostring(time() % 100000) .. chunkN       -- unique even for two sends in the same second
  outbox[kind .. id] = { str = str, n = n, at = time() }
  for k, o in pairs(outbox) do if time() - o.at > 300 then outbox[k] = nil end end
  for i = 1, n do send(table.concat({ kind, id, i, n, str:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"), tgt) end
end
-- They told us which parts never arrived: send just those again.
local function resendParts(kind, id, list, tgt)
  local o = outbox[kind .. id]
  if not o then return false end
  for i in list:gmatch("%d+") do
    i = tonumber(i)
    if i >= 1 and i <= o.n then send(table.concat({ kind, id, i, o.n, o.str:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"), tgt) end
  end
  return true
end

-- Sync: the first send to a peer is the full snapshot (log + every completed quest). After that only
-- changes go out: log entries added/changed/removed, newly completed quests, level. The receiver
-- checks the sequence number and asks for a full copy if it missed anything.
-- Send state and journal live in SavedVariables so a /reload doesn't force a full copy:
--   SterlingQuestDB.syncState[key] = { seq, entries = {qid=entry}, done = {qid=true}, level }
--   SterlingQuestDB.journal[key]   = { {seq, base, at, kind, body, acked}, ... }  (newest last, 100 kept)
local JOURNAL_MAX = 100
local function syncState() SterlingQuestDB.syncState = SterlingQuestDB.syncState or {}; return SterlingQuestDB.syncState end
local function journal(key) SterlingQuestDB.journal = SterlingQuestDB.journal or {}; SterlingQuestDB.journal[key] = SterlingQuestDB.journal[key] or {}; return SterlingQuestDB.journal[key] end
local function nextSeq() SterlingQuestDB.syncSeq = (SterlingQuestDB.syncSeq or 0) + 1; return SterlingQuestDB.syncSeq end
-- Human label for a sync: MM.DD.YY-HH.MM.n (24h clock, n counts syncs within the same minute)
local function nextLabel()
  local minute = date("%m.%d.%y-%H.%M")
  if SterlingQuestDB.labelMinute == minute then SterlingQuestDB.labelN = (SterlingQuestDB.labelN or 1) + 1 else SterlingQuestDB.labelMinute, SterlingQuestDB.labelN = minute, 1 end
  return minute .. "." .. SterlingQuestDB.labelN
end
S.NextSyncLabel = nextLabel
local function logEntry(key, e)
  local j = journal(key)
  j[#j + 1] = e
  while #j > JOURNAL_MAX do table.remove(j, 1) end
end

local function sendTo(tgt, force, full, entries, completed, level)
  local st = syncState()[tgt.key]
  if full or not st then
    local seq = nextSeq()
    local label = nextLabel()
    local body = S.MakeSnapshot(seq) .. "^" .. label .. "^o"   -- "o": finished quests are in the order they were done
    sendChunked("SNAP", body, tgt)
    local e2, doneCopy = {}, {}
    for q, e in pairs(entries) do e2[q] = e end
    for q in pairs(completed) do doneCopy[q] = true end
    syncState()[tgt.key] = { seq = seq, entries = e2, done = doneCopy, level = level }
    logEntry(tgt.key, { seq = seq, label = label, at = time(), kind = "full", n = #body })
    S.sync.snapsOut = S.sync.snapsOut + 1; S.sync.lastSnapOut = time(); S.sync.lastMode = "full"
    bump(tgt.key, "snapsOut", 1, "lastSnapOut"); for _, nm in ipairs(namesForKey(tgt.key)) do perStat(nm).lastMode = "full"; perStat(nm).lastLabel = label end
    return true
  end
  local changed, removed, newDone = {}, {}, {}
  for qid, e in pairs(entries) do if st.entries[qid] ~= e then changed[#changed + 1] = e end end
  for qid in pairs(st.entries) do if not entries[qid] then removed[#removed + 1] = qid end end
  for qid in pairs(completed) do if not st.done[qid] then newDone[#newDone + 1] = qid end end
  if #changed == 0 and #removed == 0 and #newDone == 0 and level == st.level then return false end
  table.sort(changed); table.sort(removed); orderDone(newDone)
  local seq = nextSeq()
  local label = nextLabel()
  local body = table.concat({ st.seq, seq, level, table.concat(changed, ";"), table.concat(removed, ","), table.concat(newDone, ","), label }, "^")
  sendChunked("DELT", body, tgt)
  logEntry(tgt.key, { seq = seq, label = label, base = st.seq, at = time(), kind = "delta", body = body, n = #body })
  st.seq = seq; st.level = level
  st.entries = {}; for q, e in pairs(entries) do st.entries[q] = e end
  for _, q in ipairs(newDone) do st.done[q] = true end
  S.sync.deltasOut = (S.sync.deltasOut or 0) + 1; S.sync.lastSnapOut = time(); S.sync.lastMode = "delta"
  bump(tgt.key, "deltasOut", 1, "lastSnapOut"); for _, nm in ipairs(namesForKey(tgt.key)) do perStat(nm).lastMode = "delta"; perStat(nm).lastLabel = label end
  return true
end

-- Replay everything after `since` to one target from the journal; full copy if the journal can't reach back.
local function replay(tgt, since)
  local j = journal(tgt.key)
  local st = syncState()[tgt.key]
  local entries, completed = S.SnapshotPieces()
  local level = UnitLevel("player") or 0
  if st and st.seq == since then
    -- they have everything we've sent, but our log may have changed since: send that now
    return sendTo(tgt, true, false, entries, completed, level)
  end
  local chain, base = {}, since
  for _, e in ipairs(j) do
    if e.kind == "delta" and e.base == base then chain[#chain + 1] = e; base = e.seq end
  end
  if #chain > 0 and st and base == st.seq then
    for _, e in ipairs(chain) do sendChunked("DELT", e.body, tgt) end
    S.sync.replays = (S.sync.replays or 0) + 1; bump(tgt.key, "replays")
    sendTo(tgt, true, false, entries, completed, level)
    return true
  end
  return sendTo(tgt, true, true, entries, completed, level)
end
---------------------------------------------------------------------------
-- User-started syncs: one call per button, with "started" and "complete" lines in chat.
-- mode: quick (send mine, ask for theirs), send, receive, full (fresh copies both ways)
---------------------------------------------------------------------------
S.pending = S.pending or {}
local function partsFor(name)
  for k, box in pairs(inbox) do
    if k:sub(1, #name + 1) == name .. ":" then return "got " .. box.got .. " of " .. box.n .. " parts of their log" end
  end
end
local function finish(name, text, failed)
  local p = S.pending[name]
  S.pending[name] = nil
  -- short form for the Sync page's "Last" line
  local who = S.PartnerLabel(name)
  local kind = (p and p.mode == "full") and "Full sync" or ((p and p.auto) and "Auto sync" or "Sync")
  local short
  if text:find("complete") then short = kind .. " with " .. who .. " complete"
  elseif text:find("up to date") then short = who .. " already up to date"
  elseif text:find("didn't finish") then short = kind .. " with " .. who .. " didn't finish"
  elseif text:find("switched off") then short = who .. " has sync off"
  elseif text:find("offline") or text:find("online") then short = who .. " went offline"
  else short = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):sub(1, 40) end
  S.SyncEvent(short)
  -- user-started syncs talk at Simple; auto syncs at Advanced; failures of user-started syncs always
  local level = (p and p.auto) and 2 or ((failed and 0) or 1)
  say("sync", level, text)
end
function S.SyncHeard(name, what, detail)
  local p = S.pending[name]
  if not p then return end
  local who = S.PartnerLabel(name)
  if what == "off" then finish(name, who .. " has sync with you switched off on their side, so nothing came back.", true) return end
  if what == "confirmed" then p.confirmed = true
  else p.got = detail or "already up to date"; if what == "current" then p.got = "already up to date" end end
  if p.mode == "full" then
    if p.got and p.confirmed then finish(name, "|cff7ee2a2Full sync complete|r with " .. who .. ": got theirs (" .. p.got .. "), they confirmed yours.") end
  elseif p.mode == "send" then
    if p.confirmed then finish(name, "|cff7ee2a2Sync complete|r with " .. who .. ": they have your changes.") end
  elseif p.got then
    finish(name, "|cff7ee2a2Sync complete|r with " .. who .. ": " .. p.got .. ".")
  end
end
local function direct(name)
  if useGroup(name) then return { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } end
  return { chan = "WHISPER", target = name, key = "W:" .. name }
end
local function askForMissing()
  local now = GetTime()
  for key, box in pairs(inbox) do
    if box.last and now - box.last > 3 then
      if box.asks >= 5 then inbox[key] = nil; dbg("sync", "|cffff9b92gave up|r on " .. box.kind .. " #" .. box.id .. " from " .. box.from .. " (" .. box.got .. "/" .. box.n .. " parts)")
      else
        local miss = {}
        for i = 1, box.n do if not box.parts[i] then miss[#miss + 1] = i; if #miss >= 30 then break end end end
        if #miss > 0 then
          box.asks = box.asks + 1; box.last = now
          local tgt = useGroup(box.from) and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = box.from, key = "W:" .. box.from }
          send("NEED\t" .. box.kind .. "\t" .. box.id .. "\t" .. table.concat(miss, ","), tgt)
          dbg("sync", "|cfff3c56bmissing parts|r of " .. box.kind .. " #" .. box.id .. " from " .. box.from .. ": have " .. box.got .. "/" .. box.n .. ", asking for " .. #miss .. " (try " .. box.asks .. " of 5)")
        end
      end
    end
  end
end
S.AskForMissing = askForMissing
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() pcall(askForMissing) end) end

-- Refresh button: fresh online info from the game, and a ping to every partner so their answer
-- updates the online dot, last received and version. Old copies just won't answer the ping.
function S.RefreshPartners()
  if type(C_FriendList) == "table" and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
  if type(C_GuildInfo) == "table" and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif type(GuildRoster) == "function" then pcall(GuildRoster) end
  local n = 0
  for _, p in ipairs(S.Partners()) do
    if p.on then send("PING", useGroup(p.name) and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = p.name, key = "W:" .. p.name }); n = n + 1 end
  end
  dbg("sync", "refresh: pinged " .. n .. " partner" .. (n == 1 and "" or "s"))
  S.lastRefresh = time()
  if S.UI_Update then S.UI_Update() end
  C_Timer.After(2.5, function() if S.UI_Update then S.UI_Update() end end)
end

local function sysPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end
function S.SyncSystemMessage(text)
  if type(text) ~= "string" then return end
  text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  for _, key in ipairs({ "ERR_FRIEND_OFFLINE_S", "ERR_CHAT_PLAYER_NOT_FOUND_S" }) do
    local pat = sysPattern(_G[key]); local who = pat and text:match(pat)
    if who then
      who = who:gsub("^%[", ""):gsub("%]$", ""):gsub("^'", ""):gsub("'$", "")
      if S.FindPartner(who) then dbg("sync", "|cffff9b92game says|r: " .. text) end
    end
  end
  if not next(S.pending) then return end
  for _, key in ipairs({ "ERR_FRIEND_OFFLINE_S", "ERR_CHAT_PLAYER_NOT_FOUND_S" }) do
    local pat = sysPattern(_G[key])
    local who = pat and text:match(pat)
    if who then
      who = who:gsub("^%[", ""):gsub("%]$", ""):gsub("^'", ""):gsub("'$", "")
      for name in pairs(S.pending) do
        if sameName(name, who) then
          dbg("sync", "system says " .. who .. (key == "ERR_FRIEND_OFFLINE_S" and " went offline" or " isn't online"))
          finish(name, "|cffff9b92Sync with " .. S.PartnerLabel(name) .. " stopped|r: " .. (key == "ERR_FRIEND_OFFLINE_S" and "they went offline." or "the game says they aren't online.") .. " Try again when they're back.", true)
        end
      end
    end
  end
end

-- Everything about sync in one print (Options > Debugging > Print sync state).
function S.PrintSyncState()
  local P = function(t) DEFAULT_CHAT_FRAME:AddMessage("|cff8a93a8[STQ state]|r " .. t) end
  P("me: v" .. tostring(S.ADDON_VER) .. ", protocol " .. S.VERSION .. ", live sync " .. (SterlingQuestDB.sync and "on" or "off") .. ", queue " .. #queue .. (draining and " (sending)" or "") .. ", refused so far " .. tostring(S.sync.throttled or 0) .. ", resend requests answered " .. tostring(S.sync.partsResent or 0))
  for _, p in ipairs(S.Partners()) do
    local on, how = S.PartnerStatus(p.name)
    local st = syncState()["W:" .. p.name]
    local sn = S.snaps[p.name]
    local lh = heard[p.name] and math.floor(GetTime() - heard[p.name]) or nil
    P(p.name .. (p.on and "" or " (unchecked)") .. ": " .. (on and ("online via " .. tostring(how)) or "offline") .. ", heard " .. (lh and (lh .. "s ago") or "never this session") ..
      ", v" .. tostring((S.addonVers and S.addonVers[p.name]) or p.ver or "?") .. ", protocol " .. tostring(S.sync.vers and S.sync.vers[p.name] or "?"))
    P("   ours to them: #" .. tostring(st and st.seq or "none") .. "   theirs here: #" .. tostring(sn and sn.seq or "none") .. (sn and sn.at and (" from " .. date("%m/%d %H:%M", sn.at)) or "") .. (S.pending[p.name] and ("   waiting: " .. S.pending[p.name].mode .. " sync") or ""))
  end
  local n = 0
  for key, box in pairs(inbox) do n = n + 1; P("incoming " .. key .. ": " .. box.got .. "/" .. box.n .. " parts, asked " .. (box.asks or 0) .. "x, last part " .. (box.last and (math.floor(GetTime() - box.last) .. "s ago") or "?")) end
  if n == 0 then P("no unfinished incoming copies") end
  local o = 0; for _ in pairs(outbox) do o = o + 1 end
  P(o .. " sent copies kept for resends")
end

-- auto = started by Sterling itself (login, partner came online, joined a group): quieter in chat.
function S.SyncWith(who, mode, auto)
  local names = {}
  if who then names[1] = who
  else for _, p in ipairs(S.Partners()) do if p.on and S.PartnerOnline(p.name) then names[#names + 1] = p.name end end end
  if #names == 0 then if not auto then msg("Sync: nobody online to sync with.") end return end
  local entries, completed = S.SnapshotPieces()
  local level = UnitLevel("player") or 0
  local lvl = auto and 2 or 1
  for _, name in ipairs(names) do
    local who2 = S.PartnerLabel(name)
    local tgt = direct(name)
    if not S.PartnerOnline(name) and not auto then msg("Sync with " .. who2 .. ": they look offline. Trying anyway.") end
    local token = {}
    S.pending[name] = { mode = mode, at = GetTime(), token = token, auto = auto }
    local pre = auto and "Auto sync" or "Sync"
    if mode == "full" then
      S.ResetSync(tgt.key)
      if S.snaps[name] then S.snaps[name].seq = 0 end
      send("REQ\t" .. S.VERSION, tgt)
      sendTo(tgt, true, true, entries, completed, level)
      say("sync", lvl, "|cfff3c56bFull sync started|r with " .. who2 .. ": asked for their log, sending yours.")
      S.SyncEvent("Full sync with " .. who2 .. " started")
    elseif mode == "send" then
      if not sendTo(tgt, true, false, entries, completed, level) then finish(name, pre .. " with " .. who2 .. ": nothing new to send, they're up to date.") end
      if S.pending[name] then say("sync", lvl, pre .. " started with " .. who2 .. ": sent your changes."); S.SyncEvent(pre .. " with " .. who2 .. " started") end
    else
      if mode == "quick" then sendTo(tgt, true, false, entries, completed, level) end
      S.RequestPartner(name)
      say("sync", lvl, pre .. " started with " .. who2 .. ": " .. (mode == "quick" and "sent your changes, " or "") .. "asked for theirs.")
      S.SyncEvent(pre .. " with " .. who2 .. " started")
    end
    C_Timer.After(mode == "full" and 60 or 30, function()
      local p = S.pending[name]
      if not (p and p.token == token) then return end
      local missing = {}
      if p.mode == "full" then
        if not p.got then missing[#missing + 1] = "their log never arrived" .. (partsFor(name) and (" (" .. partsFor(name) .. ")") or "") end
        if not p.confirmed then missing[#missing + 1] = "they didn't confirm yours" end
      elseif p.mode == "send" then missing[1] = "they didn't confirm your changes"
      else missing[1] = "no reply" .. (partsFor(name) and (" (" .. partsFor(name) .. ")") or "") end
      local theirVer = (S.addonVers and S.addonVers[name]) or (S.FindPartner(name) and S.FindPartner(name).ver)
      local vnum = tonumber(theirVer)
      local why
      if vnum and vnum >= 5.37 then
        why = "They're on v" .. theirVer .. ", so it isn't the version. They may have zoned, logged out, or not gotten your messages. Hit Refresh, then try again."
      elseif theirVer then
        why = "They're on v" .. theirVer .. ". Both of you need 5.37 or newer for this to finish reliably."
      else
        why = "Their version is unknown. They may be offline, or need 5.37 or newer."
      end
      finish(name, "|cffff9b92" .. (p.auto and "Auto sync" or "Sync") .. " with " .. who2 .. " didn't finish|r after " .. (p.mode == "full" and 60 or 30) .. " seconds: " .. table.concat(missing, ", ") .. ". " .. why, true)
    end)
  end
end

---------------------------------------------------------------------------
-- Auto sync: a quick sync (send my changes, ask for theirs) when I log in, when a partner comes
-- online, and when a partner joins my group. Every 5 minutes, a check that nothing was missed.
---------------------------------------------------------------------------
local autoDone = {}   -- name -> GetTime() of the last auto sync, so one trigger doesn't fire twice
function S.AutoSync(name, why)
  if not S.Opt("autoSync", true) or not SterlingQuestDB.sync then return end
  local p = S.FindPartner(name)
  if not (p and p.on) then return end
  if S.pending[p.name] then return end
  if autoDone[p.name] and GetTime() - autoDone[p.name] < 20 then return end
  autoDone[p.name] = GetTime()
  dbg("sync", "auto sync with " .. p.name .. ": " .. tostring(why))
  S.SyncWith(p.name, "quick", true)
end
function S.AutoSyncAll(why)
  for _, p in ipairs(S.Partners()) do if p.on and S.PartnerOnline(p.name) then S.AutoSync(p.name, why) end end
end
-- The periodic check: ask each online partner for anything after the copy we hold, and send ours.
local function autoCheck()
  if not S.Opt("autoSync", true) or not SterlingQuestDB.sync then return end
  local n = 0
  for _, p in ipairs(S.Partners()) do
    if p.on and S.PartnerOnline(p.name) and not S.pending[p.name] then S.RequestPartner(p.name); n = n + 1 end
  end
  if n > 0 then S.ScheduleBroadcast(); dbg("sync", "auto check: asked " .. n .. " partner" .. (n == 1 and "" or "s") .. " for anything new") end
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(300, function() pcall(autoCheck) end) end

---------------------------------------------------------------------------
-- Quest sharing between grouped partners: ASK asks them to share a quest with you.
---------------------------------------------------------------------------
-- Share one of your quests with the group (the game decides if it can be shared).
function S.ShareQuest(qid)
  local ok = false
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if idx then
      if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, qid) end
      if QuestLogPushQuest then ok = pcall(QuestLogPushQuest, idx) end
    end
  elseif GetQuestLogIndexByID and QuestLogPushQuest then
    local idx = GetQuestLogIndexByID(qid)
    if idx and idx > 0 then ok = pcall(QuestLogPushQuest, idx) end
  end
  if ok then msg("Sharing " .. S.QuestName(qid) .. " with the group.") else msg("Couldn't share " .. S.QuestName(qid) .. ".") end
  return ok
end
-- Can this quest in my log be shared at all? (nil = the game can't say)
function S.CanShare(qid)
  if C_QuestLog and C_QuestLog.IsPushableQuest then local ok, v = pcall(C_QuestLog.IsPushableQuest, qid); if ok then return v and true or false end end
  return nil
end
function S.AskShare(name, qid)
  send("ASK\t" .. qid .. "\t" .. clean(S.QuestName(qid)), direct(name))
  msg("Asked " .. S.PartnerLabel(name) .. " to share " .. S.QuestName(qid) .. ".")
end

function S.Confirmed(key)
  local best, at, label
  for _, e in ipairs(journal(key)) do if e.acked then best, at, label = e.seq, e.ackAt, e.label end end
  return best, at, label
end
function S.Journal(key) return journal(key) end
function S.ResetSync(key) if key then syncState()[key] = nil else SterlingQuestDB.syncState = {} end end

-- Send the quest log to everyone who should have it. Full copy the first time a target is seen
-- (or when asked), changes only after that. `only` limits it to one target key.
function S.Broadcast(force, full, only)
  if not SterlingQuestDB.sync and not force then return end
  local targets = S.Targets()
  if #targets == 0 then return end
  local entries, completed = S.SnapshotPieces()
  local level = UnitLevel("player") or 0
  for _, t in ipairs(targets) do
    if not only or t.key == only then sendTo(t, force, full, entries, completed, level) end
  end
end

function S.SendSession(sess)
  if not sess then msg("No such session.") return end
  if not channel() then msg("Nobody to send to: add a partner in the Sync tab, and be online at the same time.") return end
  sendChunked("SESS", S.EncodeSession(sess)); S.sync.sessOut = S.sync.sessOut + 1; for _, t in ipairs(S.Targets()) do bump(t.key, "sessOut") end; msg("Sent session \"" .. sess.name .. "\".")
end
S.warned = {}
function S.VersionMismatch(name, ver)
  if S.warned[name] == ver then return end
  S.warned[name] = ver
  if ver < S.VERSION then msg("|cffff9b92" .. name .. " is on an older Sterling Quest Tracker (sync " .. ver .. ", yours is " .. S.VERSION .. "). Nothing will sync until they install the zip you have.|r")
  else msg("|cffff9b92" .. name .. " has a newer Sterling Quest Tracker than you (sync " .. ver .. ", yours is " .. S.VERSION .. "). Nothing will sync until you install their zip.|r") end
end
-- Partners known to be on a different version: { {name=, ver=}, ... }
function S.Mismatches()
  local out = {}
  for name, v in pairs((S.sync and S.sync.vers) or {}) do if v ~= S.VERSION then out[#out + 1] = { name = name, ver = v } end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Ask for a copy. If we already hold a numbered copy from that person, ask only for what came after it.
function S.SendProfile(tgt)
  local p = S.Profile()
  send("PROF\t" .. (p.race or "Troll") .. "\t" .. (p.color or "gold") .. "\t" .. (p.name or ""), tgt)
  send("AVER\t" .. tostring(S.ADDON_VER), tgt)   -- addon version, shown on hover in the Sync list (older copies ignore it)
  send("ME\t" .. S.SESSION_TOKEN, tgt)            -- if this comes back to us, its sender name is ours
end

function S.RequestPartner(name)
  local function ask(tgt, who)
    local sn = who and S.snaps[who]
    if sn and sn.seq and sn.seq > 0 then send("SINCE\t" .. S.VERSION .. "\t" .. sn.seq, tgt) else send("REQ\t" .. S.VERSION, tgt) end
  end
  if name then ask({ chan = "WHISPER", target = name, key = "W:" .. name }, name)
  else for _, t in ipairs(S.Targets()) do ask(t, t.target) end end
end

local pending = false
function S.ScheduleBroadcast()
  if not SterlingQuestDB.sync or pending then return end
  pending = true
  C_Timer.After(4, function() pending = false; S.Broadcast() end)
end


---------------------------------------------------------------------------
-- Finding other Sterling users (party, guild, online friends) and invites.
-- Nobody is ever added without both players clicking: an invite carries a one-time code that
-- only the inviter's own copy accepts, within 5 minutes, and only from the person it was sent to.
---------------------------------------------------------------------------
S.found, S.invites = {}, {}
local hiSent, declined, rate, muted, greeted, loginNoted = {}, {}, {}, {}, {}, {}
local loginAt = 0
local SRC_RANK = { party = 1, guild = 2, friend = 3, other = 4 }
local function clean(v, n) return (tostring(v or ""):gsub("[|\t]", "")):sub(1, n or 16) end

function S.IsBlocked(name) name = shortName(name); return name and SterlingQuestDB.blocked and SterlingQuestDB.blocked[name] and true or false end
function S.Block(name)
  name = shortName(name); if not name then return end
  SterlingQuestDB.blocked = SterlingQuestDB.blocked or {}; SterlingQuestDB.blocked[name] = true
  S.found[name] = nil; S.invites[name] = nil
  if S.UI_Update then S.UI_Update() end
end
function S.BlockedCount() local n = 0; for _ in pairs(SterlingQuestDB.blocked or {}) do n = n + 1 end; return n end
function S.ClearBlocked() SterlingQuestDB.blocked = nil; if S.UI_Update then S.UI_Update() end end

-- Per person: partners get plenty of room (a full log is a few dozen parts), anyone else very little.
function S.Flooding(name)
  if muted[name] then return true end
  local now = GetTime()
  local r = rate[name]
  if not r or now - r.t > 10 then r = { t = now, n = 0 }; rate[name] = r end
  r.n = r.n + 1
  local cap = S.FindPartner(name) and 300 or 15
  if r.n > cap then
    muted[name] = true
    msg("Ignoring " .. name .. " for the rest of this session (far too many messages).")
    return true
  end
  return false
end

local function myInfo()
  local _, cls = UnitClass("player")
  return table.concat({ tostring(S.ADDON_VER), cls or "", tostring(UnitLevel("player") or 0) }, "\t")
end
local function friendOnline(name)
  if type(C_FriendList) ~= "table" or not C_FriendList.GetNumFriends then return false end
  for i = 1, (C_FriendList.GetNumFriends() or 0) do
    local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
    if ok and info and sameName(info.name, name) then return info.connected and true or false end
  end
  return false
end
local function inGuild(name)
  if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return false end
  for i = 1, (GetNumGuildMembers() or 0) do if sameName((GetGuildRosterInfo(i)), name) then return true end end
  return false
end
local function srcOf(name, chan)
  if chan == "PARTY" or chan == "RAID" or chan == "INSTANCE_CHAT" or inGroup(name) then return "party" end
  if chan == "GUILD" or inGuild(name) then return "guild" end
  if friendOnline(name) then return "friend" end
  return "other"
end

function S.InviteLink(name) return "|Hgarrmission:sterling:invite:" .. name .. "|h|cffffd100[Add " .. name .. "]|r|h" end
if hooksecurefunc and SetItemRef then
  hooksecurefunc("SetItemRef", function(link)
    local who = type(link) == "string" and link:match("^garrmission:sterling:invite:(.+)$")
    if who and S.Invite then S.Invite(who) end
  end)
end

local function noteFound(name, ver, cls, lvl, src)
  if S.IsBlocked(name) or S.IsMe(name) then return end
  local isNew = S.found[name] == nil
  local f = S.found[name] or {}
  f.ver = clean(ver, 12); f.class = clean(cls, 16); f.level = tonumber(lvl); f.at = time()
  if not f.src or (SRC_RANK[src] or 9) < (SRC_RANK[f.src] or 9) then f.src = src end
  S.found[name] = f
  S.addonVers = S.addonVers or {}; S.addonVers[name] = f.ver
  local p = S.FindPartner(name); if p then p.ver = f.ver end
  heard[name] = GetTime()
  if isNew and f.src == "party" and not p and S.Opt("partyNote", true) then
    msg(name .. " in your party has Sterling. " .. S.InviteLink(name))
  end
  if S.UI_Update then S.UI_Update() end
end

-- Found people not on your list (for the + Add badge and the Add window).
function S.FoundList()
  local out = {}
  for name, f in pairs(S.found) do
    if not S.IsBlocked(name) then out[#out + 1] = { name = name, ver = f.ver, class = f.class, level = f.level, src = f.src, partner = S.FindPartner(name) ~= nil } end
  end
  table.sort(out, function(a, b)
    local ra, rb = SRC_RANK[a.src] or 9, SRC_RANK[b.src] or 9
    if ra ~= rb then return ra < rb end
    return a.name < b.name
  end)
  return out
end
function S.FoundNewCount() local n = 0; for _, f in ipairs(S.FoundList()) do if not f.partner then n = n + 1 end end; return n end

function S.Hello(chan, target)
  if not S.Opt("discoverable", true) then return end
  send("HELLO\t" .. myInfo(), { chan = chan, target = target })
end
local lastLook = 0
function S.DiscoverNow(quiet)
  if GetTime() - lastLook < 30 then if not quiet then msg("Already looked in the last 30 seconds.") end return end
  lastLook = GetTime()
  if not S.Opt("discoverable", true) then if not quiet then msg("Finding others needs \"Let others see I have Sterling\" on (Options > Sync).") end return end
  if IsInGroup and IsInGroup() then S.Hello(IsInRaid() and "RAID" or "PARTY") end
  if IsInGuild and IsInGuild() and S.Opt("findGuild", true) then S.Hello("GUILD") end
  if type(C_FriendList) == "table" and C_FriendList.GetNumFriends then
    local n = 0
    for i = 1, (C_FriendList.GetNumFriends() or 0) do
      local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
      if ok and info and info.connected and info.name and n < 50 then n = n + 1; S.Hello("WHISPER", info.name) end
    end
  end
end

function S.PartnerLoginNote(name)
  if not S.Opt("loginNote", true) or loginAt == 0 or GetTime() - loginAt < 30 then return end
  if loginNoted[name] and GetTime() - loginNoted[name] < 600 then return end
  loginNoted[name] = GetTime()
  local v = (S.addonVers and S.addonVers[name]) or (S.FindPartner(name) or {}).ver
  msg((S.PartnerLabel and S.PartnerLabel(name) or name) .. " is online" .. (v and (" (Sterling v" .. v .. ")") or "") .. ".")
end

function S.Invite(name)
  name = shortName(name); if not name or name == "" or S.IsMe(name) then return end
  if S.IsBlocked(name) then SterlingQuestDB.blocked[name] = nil end   -- inviting someone undoes a block
  local code = tostring(math.random(100000, 999999))
  S.invites[name] = { code = code, at = time() }
  send("INV\t" .. code, { chan = "WHISPER", target = name })
  msg("Invite sent to " .. name .. ". They get a prompt to accept.")
  if S.UI_Update then S.UI_Update() end
end
function S.AcceptInvite(name, code)
  S.AddPartner(name, true)
  send("INVOK\t" .. code, { chan = "WHISPER", target = name })
  msg("Added " .. name .. ". Syncing now.")
  C_Timer.After(1.5, function() S.SyncWith(name, "full") end)
  if S.UI_Update then S.UI_Update() end
end
function S.DeclineInvite(name, code)
  declined[name] = true
  send("INVNO\t" .. code, { chan = "WHISPER", target = name })
end

-- Handles HELLO / HI / INV / INVOK / INVNO. Returns true when the message was one of these.
function S.OnDiscovery(short, text, chan)
  local kind, rest = text:match("^(%u+)\t?(.*)$")
  if kind == "HELLO" or kind == "HI" then
    local ver, cls, lvl = rest:match("^([%d%.]+)\t(%u*)\t(%d+)$")
    if not ver then return true end
    noteFound(short, ver, cls, lvl, srcOf(short, chan))
    if S.FindPartner(short) and kind == "HELLO" and chan ~= "PARTY" and chan ~= "RAID" then S.PartnerLoginNote(short) end
    if kind == "HELLO" and S.Opt("discoverable", true) and (not hiSent[short] or time() - hiSent[short] > 300) then
      hiSent[short] = time()
      C_Timer.After(math.random() * 3, function() send("HI\t" .. myInfo(), { chan = "WHISPER", target = short }) end)
    end
    return true
  end
  if kind == "INV" then
    local code = rest:match("^(%d+)$"); if not code then return true end
    if S.FindPartner(short) then send("INVOK\t" .. code, { chan = "WHISPER", target = short }) return true end
    if declined[short] then return true end
    if S.UI_InvitePrompt then S.UI_InvitePrompt(short, code) end
    return true
  end
  if kind == "INVOK" or kind == "INVNO" then
    local code = rest:match("^(%d+)$")
    local inv = S.invites[short]
    if not (code and inv and inv.code == code and time() - inv.at <= 300) then dbg("sync", "ignored an invite answer from " .. short .. " (no matching invite)") return true end
    S.invites[short] = nil
    if kind == "INVOK" then
      S.AddPartner(short, true)
      msg(short .. " accepted. Syncing now.")
      C_Timer.After(1.5, function() S.SyncWith(short, "full") end)
    else
      msg(short .. " said not now.")
    end
    if S.UI_Update then S.UI_Update() end
    return true
  end
  return false
end

-- Say hello: once at login (guild and online friends), and to the group whenever someone new joins.
local helloPending = false
function S.GroupHello()
  if not (IsInGroup and IsInGroup()) or not S.Opt("discoverable", true) then return end
  local unit = IsInRaid() and "raid" or "party"
  local newOne = false
  for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
    local n = UnitName(unit .. i)
    if n and not greeted[n] and not S.IsMe(n) then greeted[n] = true; newOne = true end
  end
  if newOne and not helloPending then
    helloPending = true
    C_Timer.After(2, function() helloPending = false; if IsInGroup() then S.Hello(IsInRaid() and "RAID" or "PARTY") end end)
  end
end
function S.LoginHello()
  if loginAt ~= 0 then return end
  loginAt = GetTime()
  C_Timer.After(12, function() lastLook = 0; S.DiscoverNow(true) end)
  -- partners already online when we log in aren't "logging in": don't announce them
  C_Timer.After(28, function() for _, p in ipairs(S.Partners()) do if S.PartnerOnline(p.name) then loginNoted[p.name] = GetTime() end end end)
  if C_Timer.NewTicker then C_Timer.NewTicker(900, function() if IsInGuild and IsInGuild() and S.Opt("findGuild", true) then S.Hello("GUILD") end end) end
end

local function onAddonMessage(prefix, text, chan, sender)
  if prefix ~= S.PREFIX then return end
  local short = sender and sender:match("^([^%-]+)") or sender
  if short ~= UnitName("player") then
    local d, i, n = describe(text)
    if not i or i == 1 or i == n then dbg("sync", "in from " .. tostring(short) .. " (" .. tostring(chan) .. "): " .. d) end
  end
  local meTok = text:match("^ME\t(%d+)$")
  if meTok then
    if meTok == S.SESSION_TOKEN then
      S.LearnMyName(short)
      if S.FindPartner(short) then S.RemovePartner(short); msg("Took yourself off the Sync list (" .. short .. ").") end
      if S.UI_Update then S.UI_Update() end
    end
    return
  end
  if short == UnitName("player") or S.IsMe(sender) or S.IsMe(short) then
    -- our own message coming back to us (the group echoes addon messages to the sender)
    if S.FindPartner(short) then S.RemovePartner(short); dbg("sync", "removed yourself from the Sync list (" .. tostring(sender) .. ")"); if S.UI_Update then S.UI_Update() end end
    return
  end
  -- blocked people are never heard; anyone flooding us is ignored for the rest of the session
  if S.IsBlocked(short) or S.Flooding(short) then return end
  -- finding Sterling users and invites: handled for anyone, they never touch quest data
  if S.OnDiscovery(short, text, chan) then return end
  -- Only people on your Sync list, plus (with group sync on) people in your group right now.
  -- A whisper from anyone else is never taken, whatever the setting.
  if not S.FindPartner(short) and not (groupSync() and inGroup(short)) then
    -- not on your Sync list: nothing is taken from them, but say once that they're trying
    S.knocked = S.knocked or {}
    if not S.knocked[short] and (text:find("^REQ") or text:find("^SINCE") or text:find("^SNAP") or text:find("^DELT")) then
      S.knocked[short] = true
      msg(short .. " is trying to sync with you. To accept, add them in the Sync tab (+ Add).")
    end
    dbg("sync", "ignored " .. describe(text) .. " from " .. short .. ": not on your Sync list (group sync is off)")
    return
  end
  heard[short] = GetTime()
  S.sync.trace = S.sync.trace or {}
  table.insert(S.sync.trace, 1, date("%H:%M:%S") .. " in  " .. short .. ": " .. text:sub(1, 48):gsub("\t", " "))
  if #S.sync.trace > 30 then S.sync.trace[31] = nil end
  S.sync.recv = S.sync.recv + 1; S.sync.bytesIn = S.sync.bytesIn + #text; S.sync.lastIn = time(); S.sync.lastFrom = short
  bump(short, "recv", 1, "lastIn"); bump(short, "bytesIn", #text)
  S.sync.vers = S.sync.vers or {}
  local function tgtFor()
    local inG = useGroup(short)
    return inG and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = short, key = "W:" .. short }
  end
  local nk, nid, nlist = text:match("^NEED\t(%u+)\t(%d+)\t([%d,]+)$")
  if nk then
    S.sync.partsResent = (S.sync.partsResent or 0) + 1
    dbg("sync", short .. " is missing parts of " .. nk .. " #" .. nid .. ": " .. nlist .. (outbox[nk .. nid] and ", resending them" or ", that copy is gone, sending a fresh one"))
    if not resendParts(nk, nid, nlist, tgtFor()) and nk == "SNAP" then
      -- that copy is gone: send a fresh one
      local entries, completed = S.SnapshotPieces()
      sendTo(tgtFor(), true, true, entries, completed, UnitLevel("player") or 0)
    end
    return
  end
  local askQ, askT = text:match("^ASK\t(%d+)\t(.*)$")
  if askQ then
    askQ = tonumber(askQ)
    askT = askT and askT:gsub("|", ""):sub(1, 80)
    if askT and askT ~= "" then S.LearnName(askQ, askT) end
    if S.Opt("groupHints", true) and S.UI_ShareAsk then S.UI_ShareAsk(short, askQ) end
    return
  end
  if text == "PING" then
    -- a partner hit Refresh: answer with who we are (cheap, no quest data)
    send("VER\t" .. S.VERSION, tgtFor()); send("AVER\t" .. tostring(S.ADDON_VER), tgtFor())
    return
  end
  if text == "CUR" then if S.SyncHeard then S.SyncHeard(short, "current") end return end
  if text == "OFF" then if S.SyncHeard then S.SyncHeard(short, "off") end return end
  local aver = text:match("^AVER\t([%d%.]+)$")
  if aver then
    aver = aver:sub(1, 12)
    S.addonVers = S.addonVers or {}; S.addonVers[short] = aver
    local p = S.FindPartner(short); if p then p.ver = aver end
    S.UI_Update()
    return
  end
  local prace, pcolor, pname = text:match("^PROF\t(%w+)\t(%w+)\t(.*)$")
  if prace then
    pname = (pname or ""):gsub("[|\t]", ""):sub(1, 24)   -- no links or textures smuggled into our windows
    S.profiles[short] = { name = (pname ~= "" and pname or short), race = normRace(prace), color = pcolor:sub(1, 12) }
    if S.LooksLikeMe(short) then
      S.LearnMyName(short); S.profiles[short] = nil
      if S.FindPartner(short) then S.RemovePartner(short); msg("Took yourself off the Sync list (" .. short .. ").") end
      if S.UI_Update then S.UI_Update() end
      return
    end
    SterlingQuestDB.profiles = SterlingQuestDB.profiles or {}; SterlingQuestDB.profiles[short] = S.profiles[short]
    if S.ViewerRedraw then S.ViewerRedraw() end
    return
  end
  local ackSeq = text:match("^ACK\t(%d+)$")
  if ackSeq then
    ackSeq = tonumber(ackSeq)
    dbg("sync", short .. " confirmed our #" .. ackSeq)
    local key = useGroup(short) and "GROUP" or ("W:" .. short)
    for _, e in ipairs(journal(key)) do
      if e.seq == ackSeq then
        e.acked = true; e.ackAt = time(); e.by = short
        if S.SyncHeard then S.SyncHeard(short, "confirmed") end
      end
    end
    S.sync.acks = (S.sync.acks or 0) + 1; bump(short, "acks", 1, "lastAck")
    S.UI_Update()
    return
  end
  local sinceVer, sinceSeq = text:match("^SINCE\t(%d+)\t(%d+)$")
  local ver = text:match("^REQ\t?(%d*)$") or text:match("^VER\t(%d+)$") or sinceVer
  if ver then
    ver = tonumber(ver) or 0
    S.sync.theirVer = ver; S.sync.vers[short] = ver
    S.AddPartner(short)
    if ver ~= S.VERSION then
      S.VersionMismatch(short, ver)
      -- tell them ours so their side can show the same warning, then stop
      if text:sub(1, 3) == "REQ" then
        local inG = useGroup(short)
        send("VER\t" .. S.VERSION, inG and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = short, key = "W:" .. short })
      end
      S.UI_Update()
      return
    end
    if not sinceSeq and text:sub(1, 3) ~= "REQ" then S.UI_Update() return end
    -- They asked us directly, so they always get an answer: our log, "nothing new", or "sync is off here".
    send("VER\t" .. S.VERSION, tgtFor()); S.SendProfile(tgtFor())
    local mine = S.FindPartner(short)
    if mine and mine.on == false then send("OFF", tgtFor()); dbg("sync", short .. " asked for our log, but sync with them is switched off here: told them so"); return end
    local before = #queue
    if sinceSeq then
      if not replay(tgtFor(), tonumber(sinceSeq)) then send("CUR", tgtFor()); dbg("sync", short .. " asked for changes since #" .. sinceSeq .. ": nothing new, told them they're up to date")
      else dbg("sync", short .. " asked for changes since #" .. sinceSeq .. ": sending " .. (#queue - before) .. " messages") end
    else
      local entries, completed = S.SnapshotPieces()
      sendTo(tgtFor(), true, true, entries, completed, UnitLevel("player") or 0)
      dbg("sync", short .. " asked for a full copy: sending " .. (#queue - before) .. " messages (queue now " .. #queue .. ")")
    end
    return
  end
  -- data from a sender whose version doesn't match ours is ignored; unknown versions get asked
  local kv = S.sync.vers[short]
  if kv == nil then dbg("sync", "ignored from " .. short .. ": don't know their version yet, asking"); S.RequestPartner(short); return end
  if kv ~= S.VERSION then dbg("sync", "|cffff9b92ignored|r from " .. short .. ": their sync protocol " .. tostring(kv) .. ", ours " .. S.VERSION); return end
  local kind, id, i, n, chunk = text:match("^(%u+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
  if not kind then return end
  i, n = tonumber(i), tonumber(n)
  -- sanity caps: a real log is a few dozen parts; anything far bigger or out of range is dropped
  if not i or not n or n < 1 or n > 400 or i < 1 or i > n then dbg("sync", "|cffff9b92dropped|r a malformed part from " .. short); return end
  local open = 0
  for k, b in pairs(inbox) do if b.from == short then open = open + 1 end end
  if open > 6 and not inbox[short .. ":" .. kind .. ":" .. id] then dbg("sync", "|cffff9b92dropped|r: too many unfinished copies from " .. short); return end
  if n > 2 then S.sync.prog = { who = short, dir = "in", got = (inbox[short .. ":" .. kind .. ":" .. id] and inbox[short .. ":" .. kind .. ":" .. id].got or 0) + 1, n = n, t = GetTime() } end
  local key = short .. ":" .. kind .. ":" .. id
  inbox[key] = inbox[key] or { n = n, parts = {}, got = 0, from = short, kind = kind, id = id, asks = 0 }
  local box = inbox[key]
  box.last = GetTime()
  if not box.parts[i] then
    box.parts[i] = chunk; box.got = box.got + 1
    if box.got % 5 == 0 and box.got < n then dbg("sync", kind .. " #" .. id .. " from " .. short .. ": " .. box.got .. "/" .. n .. " parts so far") end
  else dbg("sync", "duplicate part " .. i .. "/" .. n .. " of " .. kind .. " #" .. id .. " from " .. short) end
  if box.got < n then return end
  dbg("sync", "|cff7ee2a2complete|r: all " .. n .. " parts of " .. kind .. " #" .. id .. " from " .. short .. (box.asks > 0 and (" (after " .. box.asks .. " ask" .. (box.asks == 1 and "" or "s") .. " for missing parts)") or ""))
  inbox[key] = nil
  local whole = table.concat(box.parts)
  if kind == "SNAP" then
    local snap = S.ParseSnapshot(whole)
    if snap and S.IsMe(snap.name) then
      -- a copy of our own log under another spelling of our name: never a partner
      if S.FindPartner(short) then S.RemovePartner(short) end
      dbg("sync", "ignored a copy of your own log from " .. tostring(sender))
      snap = nil
    end
    if snap then
      snap.source = "live"; snap.at = time(); snap.name = short
      local prev = S.snaps[short]
      local first = (prev == nil) or prev.source ~= "live"
      S.AddPartner(short)
      S.StoreSnap(short, snap, whole)
      S.SelectPartner(nil)
      S.sync.snapsIn = S.sync.snapsIn + 1; S.sync.lastSnapIn = time(); bump(short, "snapsIn", 1, "lastSnapIn")
      if snap.seq and snap.seq > 0 then send("ACK\t" .. snap.seq, tgtFor()); dbg("sync", "confirming " .. short .. "'s full copy #" .. snap.seq) end
      if first then say("sync", 1, "Live sync with " .. S.PartnerLabel(short) .. " is on.") end
      if S.OnPartnerData then S.OnPartnerData(short) end
      if S.SyncHeard then
        local nl, nd = 0, 0
        for _ in pairs(snap.log) do nl = nl + 1 end
        for _ in pairs(snap.completed) do nd = nd + 1 end
        S.SyncHeard(short, "full", nl .. " quests in log, " .. nd .. " done")
      end
      S.UI_Update()
    end
  elseif kind == "DELT" then
    local f = {}
    for piece in (whole .. "^"):gmatch("(.-)%^") do f[#f + 1] = piece end
    local base, seq, level = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
    local p = S.snaps[short]
    if p and p.seq and seq and seq <= p.seq then return end     -- already applied (replay overlap)
    if not (p and (p.source == "live" or p.source == "saved") and p.seq == base) then
      -- out of step: ask that sender for the whole thing
      dbg("sync", "|cfff3c56bout of step|r: " .. short .. "'s change #" .. tostring(seq) .. " builds on #" .. tostring(base) .. ", we have #" .. tostring(p and p.seq) .. ". Asking for a resend.")
      S.sync.resyncs = (S.sync.resyncs or 0) + 1; bump(short, "resyncs")
      S.RequestPartner(short)
      return
    end
    for item in (f[4] or ""):gmatch("[^;]+") do
      local qid, st, title, objs = item:match("^(%d+)%.(%a)%.([^%.]*)%.?(.*)$")
      if qid then
        local o = {}
        for t in (objs or ""):gmatch("[^~]+") do o[#o + 1] = t end
        p.log[tonumber(qid)] = { title = title, complete = (st == "c"), objs = o }
      end
    end
    for qid in (f[5] or ""):gmatch("%d+") do p.log[tonumber(qid)] = nil end
    p.rank = p.rank or {}
    for qid in (f[6] or ""):gmatch("%d+") do
      qid = tonumber(qid)
      if not p.completed[qid] then p.completed[qid] = true; p.rankMax = (p.rankMax or 0) + 1; p.rank[qid] = p.rankMax end
    end
    p.level = level or p.level; p.seq = seq; p.at = time(); p.label = f[7] ~= "" and f[7] or p.label
    S.StoreSnap(short, p, S.SnapshotToString(p))
    S.SelectPartner(nil)
    send("ACK\t" .. seq, tgtFor()); dbg("sync", "applied and confirming " .. short .. "'s change #" .. tostring(seq))
    if S.OnPartnerData then S.OnPartnerData(short) end
    S.sync.deltasIn = (S.sync.deltasIn or 0) + 1; S.sync.lastSnapIn = time(); bump(short, "deltasIn", 1, "lastSnapIn")
    if S.SyncHeard then
      local nc = 0
      for _ in (f[4] or ""):gmatch("[^;]+") do nc = nc + 1 end
      for _ in (f[5] or ""):gmatch("%d+") do nc = nc + 1 end
      for _ in (f[6] or ""):gmatch("%d+") do nc = nc + 1 end
      S.SyncHeard(short, "delta", nc .. (nc == 1 and " change" or " changes"))
    end
    S.UI_Update()
  elseif kind == "SESS" then
    local sess = S.DecodeSession(whole)
    if sess then
      sess.imported = true
      S.sync.sessIn = S.sync.sessIn + 1; S.sync.lastSessIn = time(); bump(short, "sessIn")
      S.AddSession(sess)
      msg(("%s sent you the session \"%s\" (%s). Open Sessions to follow it."):format(short, sess.name, S.Duration(sess)))
      S.UI_Update()
    end
  end
end

if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
    if not (SterlingQuestDB and text and text:find("currently playing", 1, true)) then return end
    for _, p in ipairs(SterlingQuestDB.partners or {}) do if text:find(p.name, 1, true) then return true end end
  end)
end

---------------------------------------------------------------------------
-- Path engine: steps come from a followed session
---------------------------------------------------------------------------
S.legs, S.steps = {}, {}
local lastIndex

local function indexSteps()
  S.steps = {}
  for _, leg in ipairs(S.legs) do
    for _, st in ipairs(leg.steps) do st.leg = leg; S.steps[#S.steps + 1] = st; st.index = #S.steps end
  end
end

function S.SetLegs(legs)
  S.legs = legs or {}
  indexSteps()
  wipe(SterlingQuestDB.manual)
  lastIndex = nil
  S.Recalc(false)
end

function S.ObjectiveList(qid, logIndex)
  local objs
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, o = pcall(C_QuestLog.GetQuestObjectives, qid); if ok and type(o) == "table" then objs = o end
  end
  if not objs and logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    objs = {}
    for i = 1, (GetNumQuestLeaderBoards(logIndex) or 0) do
      local t, _, fin = GetQuestLogLeaderBoard(i, logIndex); objs[i] = { text = t, finished = fin }
    end
  end
  return objs or {}
end

local function inLog(qid) return S.log[qid] ~= nil end
local function logComplete(qid) local q = S.log[qid]; return q and q.complete end

local function objectiveDone(qid, text)
  if not (qid and text) then return nil end
  local q = S.log[qid]
  if not q then return nil end
  local objs
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, o = pcall(C_QuestLog.GetQuestObjectives, qid); if ok then objs = o end
  end
  if not objs and GetNumQuestLeaderBoards and q.index then
    objs = {}
    for i = 1, (GetNumQuestLeaderBoards(q.index) or 0) do
      local t, _, fin = GetQuestLogLeaderBoard(i, q.index); objs[i] = { text = t, finished = fin }
    end
  end
  if type(objs) ~= "table" then return nil end
  local want = text:lower():gsub("%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s+", "")
  for _, o in ipairs(objs) do
    local have = (o.text or ""):lower():gsub("%s*%d+%s*/%s*%d+%s*$", ""):gsub(":%s*$", "")
    if have ~= "" and (have:find(want, 1, true) or want:find(have, 1, true)) then return o.finished and true or false end
  end
end

local function nearby(st)
  if not (st.map and st.x) then return false end
  local map, x, y = S.PlayerPos()
  if map ~= st.map then return false end
  local dx, dy = x - st.x, y - st.y
  return (dx * dx + dy * dy) < 1.0
end

function S.StepSatisfied(st, i)
  local k = st.kind
  if k == "turnin" then return S.IsFlaggedDone(st.qid)
  elseif k == "pickup" then return inLog(st.qid) or S.IsFlaggedDone(st.qid)
  elseif k == "deliver" then return S.IsFlaggedDone(st.qid)
  elseif k == "do" then return logComplete(st.qid) or S.IsFlaggedDone(st.qid)
  elseif k == "objective" then
    local v = objectiveDone(st.qid, st.text)
    if v ~= nil then return v end
    return logComplete(st.qid) or S.IsFlaggedDone(st.qid)
  elseif k == "ding" then return (UnitLevel("player") or 0) >= st.level
  elseif k == "skip" then return not inLog(st.qid)
  elseif k == "flight" or k == "ride" or k == "hearth" then
    -- done once you're at the destination (never just for standing at the flight master or dock)
    local dest = { map = st.dmap or st.map, x = st.dx or st.x, y = st.dy or st.y }
    if st.subzone and ((GetSubZoneText() or "") == st.subzone) then return true end
    if nearby(dest) then return true end
    if k ~= "flight" then local here = S.PlayerPos(); if here and here == dest.map then return true end end
    for j = i + 1, math.min(i + 3, #S.steps) do
      local nx = S.steps[j]
      if nx.qid and S.StepSatisfied(nx, j) then return true end
    end
    return false
  elseif k == "note" or k == "travel" or k == "dungeon" then
    if k == "dungeon" and IsInInstance and IsInInstance() then
      local name = GetInstanceInfo and GetInstanceInfo()
      if name and st.text and name == st.text then return true end
    end
    if st.subzone and ((GetSubZoneText() or "") == st.subzone or (GetZoneText() or "") == st.subzone) then return true end
    if nearby(st) then return true end
    for j = i + 1, math.min(i + 3, #S.steps) do
      local nx = S.steps[j]
      if nx.qid and S.StepSatisfied(nx, j) then return true end
    end
    return false
  end
  return false
end

function S.CurrentIndex()
  for i, st in ipairs(S.steps) do
    if not SterlingQuestDB.manual[i] and not S.StepSatisfied(st, i) then return i end
  end
  return #S.steps + 1
end

-- Waypoints
local wpUID
function S.ClearWaypoint()
  if wpUID and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, wpUID) end
  wpUID = nil
end
function S.SetWaypoint(st)
  S.ClearWaypoint()
  if not (st and st.x and st.y and st.map) then return end
  local title = S.StepLabel(st)
  -- pick up and turn in: the giver first, then (once it's in your log) the turn-in NPC
  if st.kind == "deliver" and st.tmap and inLog(st.qid) then st = { map = st.tmap, x = st.tx, y = st.ty } end
  -- once you're in the air (or for a hearth), point at where you're going instead of where you left from
  if st.dmap and st.dx and ((UnitOnTaxi and UnitOnTaxi("player")) or st.kind == "hearth") then
    st = { map = st.dmap, x = st.dx, y = st.dy }
  end
  if TomTom and TomTom.AddWaypoint then
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, st.map, st.x / 100, st.y / 100,
      { title = title, persistent = false, minimap = true, world = true, crazy = true, from = "Sterling Quest Tracker" })
    if ok and uid then wpUID = uid; return end
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
    local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, st.map, st.x / 100, st.y / 100)
    if ok and pt then
      pcall(C_Map.SetUserWaypoint, pt)
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
  end
end

S.KIND_LABEL = { turnin = "Turn in", pickup = "Pick up", deliver = "Pick up and turn in", ["do"] = "Do", objective = "Objective", skip = "Skip",
                 travel = "Travel", flight = "Flight", ride = "Ride", hearth = "Hearth", dungeon = "Dungeon", ding = "Level", note = "Note" }
function S.StepLabel(st)
  if not st then return "all caught up" end
  local k = st.kind
  if k == "ding" then return "Reach level " .. st.level end
  if k == "objective" then return st.text and (st.text .. " (" .. (st.quest or "") .. ")") or ("Objective for " .. (st.quest or "a quest")) end
  if k == "dungeon" then return "Ran " .. (st.text or "a dungeon") end
  if k == "note" then return "Note: " .. (st.text or "") end
  if k == "flight" then return st.from and ("Fly from " .. st.from .. " to " .. (st.text or "")) or ("Fly to " .. (st.text or "")) end
  if k == "ride" then return "Boat or zeppelin" .. (st.from and (" from " .. st.from) or "") .. " to " .. (st.text or "") end
  if k == "hearth" then return ((st.from == "Hearthstone" or not st.from) and "Hearth to " or (st.from .. " to ")) .. (st.text or "") end
  if k == "travel" then return "Travel: " .. (st.text or st.subzone or "") end
  return (S.KIND_LABEL[k] or k) .. " " .. (st.quest or "") .. (st.npc and (" (" .. st.npc .. ")") or "")
end

local lastPhase = false
function S.Recalc(announce)
  if not S.Safe("quest log", S.Refresh) then return end
  if S.RecordTick then S.Safe("recording", S.RecordTick, "questlog") end
  local i = S.CurrentIndex()
  -- a pick-up-and-turn-in step moves its arrow from the giver to the turn-in NPC once you have the quest
  local cur = S.steps[i]
  local phase = cur and cur.kind == "deliver" and inLog(cur.qid) and true or false
  if i == lastIndex and phase ~= lastPhase and SterlingQuestDB.path then S.Safe("waypoint", S.SetWaypoint, cur) end
  lastPhase = phase
  if i ~= lastIndex then
    local st = S.steps[i]
    if SterlingQuestDB.path then S.Safe("waypoint", S.SetWaypoint, st) end
    if announce and lastIndex and SterlingQuestDB.path then
      if S.Opt("sound", true) and PlaySound then pcall(PlaySound, 3175) end
      if S.Opt("chat", true) then if st then msg("Next: " .. S.StepLabel(st)) else msg("You're caught up. Path complete.") end end
    end
    lastIndex = i
  end
  S.Safe("window", S.UI_Update)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
  "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_CONTROL_GAINED",
  "PLAYER_CONTROL_LOST", "PLAYER_DEAD", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_LOGOUT" }) do
  f:RegisterEvent(ev)
end

local throttle
f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  if ev == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    -- 5.30: saved data renamed SterlingDB -> SterlingQuestDB. Carry the old table over once.
    if SterlingQuestDB == nil and type(SterlingDB) == "table" then SterlingQuestDB = SterlingDB end
    SterlingDB = nil
    SterlingQuestDB = SterlingQuestDB or {}
    SterlingQuestDB.manual = SterlingQuestDB.manual or {}
    SterlingQuestDB.sessions = SterlingQuestDB.sessions or {}
    SterlingQuestDB.opts = SterlingQuestDB.opts or {}
    if SterlingQuestDB.sync == nil then SterlingQuestDB.sync = true end
    if SterlingQuestDB.path == nil then SterlingQuestDB.path = true end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(S.PREFIX)
    elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(S.PREFIX) end
    -- migrate the old single-partner fields
    SterlingQuestDB.partners = SterlingQuestDB.partners or {}
    if SterlingQuestDB.partnerName and SterlingQuestDB.partnerName ~= "" then S.AddPartner(SterlingQuestDB.partnerName, true) end
    SterlingQuestDB.snaps = SterlingQuestDB.snaps or {}
    if SterlingQuestDB.partnerSnap then
      local snap = S.ParseSnapshot(SterlingQuestDB.partnerSnap)
      if snap and snap.name then SterlingQuestDB.snaps[snap.name] = SterlingQuestDB.snaps[snap.name] or SterlingQuestDB.partnerSnap end
    end
    SterlingQuestDB.partnerName, SterlingQuestDB.partnerExplicit, SterlingQuestDB.partnerSnap = nil, nil, nil
    for n, pr in pairs(SterlingQuestDB.profiles or {}) do S.profiles[n] = pr end
    for name in pairs(SterlingQuestDB.snaps) do
      local parsed = S.ParseSnapshot(SterlingQuestDB.snaps[name])
      if sameName(name, UnitName("player")) or S.IsMe(name) or (parsed and S.IsMe(parsed.name)) or not S.FindPartner(name) then
        SterlingQuestDB.snaps[name] = nil
        if parsed and S.IsMe(parsed.name) then local _, i = S.FindPartner(name); if i then table.remove(SterlingQuestDB.partners, i) end end
      end
    end
    for i = #SterlingQuestDB.partners, 1, -1 do
      if sameName(SterlingQuestDB.partners[i].name, UnitName("player")) or S.IsMe(SterlingQuestDB.partners[i].name) then table.remove(SterlingQuestDB.partners, i) end
    end
    for name, str in pairs(SterlingQuestDB.snaps) do
      local snap = S.ParseSnapshot(str)
      if snap then snap.source = "saved"; snap.name = name; S.snaps[name] = snap end
    end
    S.SelectPartner(nil)
    if S.ThemeInit then S.ThemeInit() end
    S.Safe("recording", S.RecordInit)
    S.Safe("window", S.UI_Init)
    if S.MapInit then S.Safe("map", S.MapInit) end
    return
  end
  if ev == "CHAT_MSG_ADDON" then onAddonMessage(a1, a2, a3, a4) return end
  if ev == "CHAT_MSG_SYSTEM" then if S.SyncSystemMessage then S.SyncSystemMessage(a1) end return end
  if ev == "PLAYER_LOGOUT" then S.RecordFlush() return end
  if S.RecordEvent then S.Safe("recording", S.RecordEvent, ev, a1, a2) end
  if (ev == "PLAYER_CONTROL_LOST" or ev == "PLAYER_CONTROL_GAINED") and SterlingQuestDB.path then
    C_Timer.After(1.5, function() local st = S.steps[S.CurrentIndex()]; if st and st.dmap then S.Safe("waypoint", S.SetWaypoint, st) end end)
  end
  if ev == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(3, function()
      if SterlingQuestDB.following then S.FollowSession(S.FindSession(SterlingQuestDB.following), false) end
      -- your name is certain by now (it can be missing while the addon first loads): drop yourself if listed
      for i = #S.Partners(), 1, -1 do
        local p = S.Partners()[i]
        if S.LooksLikeMe(p.name) then
          S.LearnMyName(p.name)
          S.snaps[p.name] = nil; if SterlingQuestDB.snaps then SterlingQuestDB.snaps[p.name] = nil end; table.remove(S.Partners(), i)
          msg("Took yourself off the Sync list (" .. p.name .. ").")
        end
      end
      S.Recalc(false); S.RequestPartner(); S.ScheduleBroadcast()
      if S.CatchupRestore then S.Safe("catch-up", S.CatchupRestore) end
    end)
    C_Timer.After(6, function() S.AutoSyncAll("logged in") end)
    S.LoginHello()
    return
  end
  if ev == "GROUP_ROSTER_UPDATE" then
    S.ScheduleBroadcast()
    S.GroupHello()
    -- a partner joined (or we joined them): sync, and offer quest sharing
    -- the first roster event after login just records who is already here (a /reload mid-group isn't a join)
    local first = S.inGroupWith == nil
    S.inGroupWith = S.inGroupWith or {}
    local now = {}
    for _, p in ipairs(S.Partners()) do
      if p.on and inGroup(p.name) then
        now[p.name] = true
        if not first and not S.inGroupWith[p.name] then
          S.AutoSync(p.name, "joined the group")
          if S.OnPartnerJoined then S.Safe("group hints", S.OnPartnerJoined, p.name) end
        end
      end
    end
    S.inGroupWith = now
    if S.UI_ShareRefresh then S.UI_ShareRefresh() end
    return
  end
  if ev == "FRIENDLIST_UPDATE" or ev == "GUILD_ROSTER_UPDATE" then
    for _, p in ipairs(S.Partners()) do
      if p.on then
        local on = S.PartnerOnline(p.name)
        if on and not pinged[p.name] then pinged[p.name] = true; S.RequestPartner(p.name); S.ScheduleBroadcast(); S.AutoSync(p.name, "came online"); S.PartnerLoginNote(p.name)
        elseif not on then pinged[p.name] = nil; S.ResetSync("W:" .. p.name) end
      end
    end
    return
  end
  if ev == "PLAYER_CONTROL_GAINED" or ev == "PLAYER_CONTROL_LOST" or ev == "PLAYER_DEAD" or ev == "PLAYER_LEAVING_WORLD" then return end
  if throttle then return end
  throttle = true
  C_Timer.After(0.5, function() throttle = nil; S.Recalc(true); S.ScheduleBroadcast() end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_STERLINGQUEST1 = "/sterling"
SLASH_STERLINGQUEST2 = "/st"
SLASH_STERLINGQUEST3 = "/stq"
SlashCmdList.STERLINGQUEST = function(input)
  local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "show" then S.UI_Toggle(true)
  elseif cmd == "hide" then S.UI_Toggle(false)
  elseif cmd == "rec" or cmd == "record" or cmd == "start" then S.RecordStart(rest ~= "" and rest or nil)
  elseif cmd == "stop" then S.RecordStop()
  elseif cmd == "sessions" then S.UI_Toggle(true); S.UI_Tab("sessions")
  elseif cmd == "export" then S.UI_ShowExport(rest)
  elseif cmd == "import" then S.UI_ShowImport()
  elseif cmd == "diff" or cmd == "compare" then S.UI_Compare()
  elseif cmd == "map" or cmd == "play" then S.MapToggle()
  elseif cmd == "mapinfo" then if S.ViewerDebug then S.ViewerDebug() end
  elseif cmd == "raceinfo" then
    local name, token = UnitRace("player")
    msg("Your race: " .. tostring(name) .. " (token " .. tostring(token) .. "), face source: " .. S.FaceSource(token))
    for _, r in ipairs(S.RACES) do msg("  " .. r .. ": " .. S.FaceSource(r)) end
  elseif cmd == "add" then if S.UI_AddPartner then S.UI_AddPartner() end
  elseif cmd == "invite" then if rest ~= "" then S.Invite(rest) else msg("Use /st invite Name") end
  elseif cmd == "partner" or cmd == "partners" then
    local sub, who = rest:match("^(%a+)%s+(.+)$")
    if rest == "clear" or rest == "none" then SterlingQuestDB.partners = {}; S.SelectPartner(nil); msg("All partners removed.")
    elseif sub == "remove" or sub == "del" then S.RemovePartner(who); msg("Removed " .. who .. "."); S.UI_Update()
    elseif sub == "off" then S.AddPartner(who, false); msg(who .. ": sync off.")
    elseif sub == "on" then S.AddPartner(who, true); msg(who .. ": sync on.")
    elseif sub == "compare" then S.SelectPartner(who); msg("Compare tab now shows " .. who .. "."); S.UI_Update()
    elseif rest ~= "" then
      S.AddPartner(rest, true)
      msg("Added partner " .. rest .. ". Sterling Quest Tracker syncs quietly whenever you're both online (add them as a friend so it can tell).")
      if S.PartnerOnline(rest) then S.RequestPartner(rest) end
      S.UI_Update()
    else
      local list = {}
      for _, p in ipairs(S.Partners()) do list[#list + 1] = p.name .. (p.on and "" or " (off)") .. (S.PartnerOnline(p.name) and " online" or " offline") end
      msg("Partners: " .. (#list > 0 and table.concat(list, ", ") or "none") .. ".  /st partner Name | remove Name | on/off Name | compare Name | clear")
    end
  elseif cmd == "since" then
    local who, n = rest:match("^(%S+)%s+(%S+)$")
    if who then
      local seq = tonumber(n) or (SterlingQuestDB.recvLabels and SterlingQuestDB.recvLabels[who] and SterlingQuestDB.recvLabels[who][n])
      if not seq then msg("I don't have a sync from " .. who .. " labelled " .. n .. ". Their labels I know: " .. (function() local l = {} for k in pairs((SterlingQuestDB.recvLabels or {})[who] or {}) do l[#l + 1] = k end table.sort(l) return #l > 0 and table.concat(l, ", ") or "none" end)()) return end
      send("SINCE\t" .. S.VERSION .. "\t" .. seq, { chan = "WHISPER", target = who, key = "W:" .. who }); msg("Asked " .. who .. " for everything after " .. n .. ".")
    elseif rest ~= "" then S.RequestPartner(rest); msg("Asked " .. rest .. " for whatever I'm missing.")
    else msg("Use /st since Name [number]") end
  elseif cmd == "restore" then S.Restore()
  elseif cmd == "trace" then
    msg("Last sync messages (newest first):")
    for i = 1, math.min(15, #(S.sync.trace or {})) do msg("  " .. S.sync.trace[i]) end
    local vs = {}
    for n, v in pairs(S.sync.vers or {}) do vs[#vs + 1] = n .. "=" .. v end
    msg("Known versions: " .. (#vs > 0 and table.concat(vs, ", ") or "none") .. "  (mine " .. S.VERSION .. ")")
  elseif cmd == "journal" then
    local key = rest ~= "" and ("W:" .. rest) or "GROUP"
    local j = S.Journal(key)
    msg("Sync journal for " .. (rest ~= "" and rest or "group") .. ": " .. #j .. " entries")
    for i = math.max(1, #j - 9), #j do local e = j[i]; msg(string.format("  %s  %s  %s%s", e.label or ("#" .. e.seq), e.kind, e.acked and "confirmed" or "unconfirmed", e.by and (" by " .. e.by) or "")) end
  elseif cmd == "sync" then SterlingQuestDB.sync = not SterlingQuestDB.sync; msg("Live sync " .. (SterlingQuestDB.sync and "on" or "off")); if SterlingQuestDB.sync then S.Broadcast(true) end
  elseif cmd == "path" then
    if rest == "clear" then S.StopFollowing(); msg("Not following anything now.")
    else SterlingQuestDB.path = not SterlingQuestDB.path; msg("Guided arrow " .. (SterlingQuestDB.path and "on" or "off")); S.Recalc(false); if not SterlingQuestDB.path then S.ClearWaypoint() end end
  elseif cmd == "done" then SterlingQuestDB.manual[S.CurrentIndex()] = true; S.Recalc(false)
  elseif cmd == "undo" then
    if S.lastJump and #S.lastJump > 0 then
      for _, k in ipairs(S.lastJump) do SterlingQuestDB.manual[k] = nil end
      S.lastJump = nil; msg("Jump undone.")
    else
      local last; for i in pairs(SterlingQuestDB.manual) do if not last or i > last then last = i end end
      if last then SterlingQuestDB.manual[last] = nil end
    end
    S.Recalc(false)
  elseif cmd == "reset" then wipe(SterlingQuestDB.manual); S.Recalc(false); msg("Manual check-offs cleared.")
  elseif cmd == "send" then
    if rest ~= "" then S.SendSession(S.FindSession(rest)) else S.Broadcast(true, true); msg("Full quest snapshot sent.") end
  elseif cmd == "note" then
    if rest == "" then msg("Usage: /st note grab the flight path here") elseif S.RecordNote(rest) then msg("Noted.") else msg("Not recording, nothing to attach the note to.") end
  elseif cmd == "merge" then
    local a, b = rest:match("^(.-)%s*%+%s*(.-)$")
    local sa, sb = S.FindSession(a), S.FindSession(b)
    if sa and sb then local m = S.MergeSessions(sa, sb); msg("Merged into \"" .. m.name .. "\"."); S.UI_Update() else msg("Usage: /st merge Name A + Name B  (or numbers from the Sessions list)") end
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if v and v >= 0.5 and v <= 2 then SterlingQuestDB.opts.scale = v; S.UI_ApplyOptions(); msg("Scale " .. v) else msg("Usage: /st scale 0.5 to 2") end
  elseif cmd == "lock" then SterlingQuestDB.opts.lock = not SterlingQuestDB.opts.lock; S.UI_ApplyOptions(); msg("Window " .. (SterlingQuestDB.opts.lock and "locked" or "unlocked"))
  elseif cmd == "options" or cmd == "opt" then S.UI_Options()
  elseif cmd == "tabs" then S.PrintTabs()
  elseif cmd == "trail" then
    SterlingQuestDB.hideMinimapTrail = not SterlingQuestDB.hideMinimapTrail; msg("Minimap trail " .. (SterlingQuestDB.hideMinimapTrail and "off" or "on"))
  elseif cmd == "minimap" then
    SterlingQuestDB.hideMinimap = not SterlingQuestDB.hideMinimap
    if SterlingQuestMinimapButton then if SterlingQuestDB.hideMinimap then SterlingQuestMinimapButton:Hide() else SterlingQuestMinimapButton:Show() end end
  else
    msg("Commands: /st | rec [name] | stop | sessions | export | import | compare | map | partner Name | sync | path | path clear | done | undo | reset | send [session] | note text | merge A + B | scale | lock | options | trail | minimap")
  end
end
