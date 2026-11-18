-- Sterling 3: quest state, compare, live sync, and the path engine that follows a recorded session.
local ADDON, S = ...

Sterling = S
S.PREFIX = "SterlingQuest"
S.VERSION = 6          -- sync protocol; both sides must match or nothing is exchanged

local function msg(text) DEFAULT_CHAT_FRAME:AddMessage("|cff8ab8ffSterling Quest Sync:|r " .. tostring(text)) end

S.msg = msg

-- Chat detail per area (Options > Chat detail): 0 quiet (failures only), 1 simple, 2 advanced, 3 full.
-- Areas: sync, tooltip. Old debug_<area> toggles count as full.
S.CHAT_LEVELS = { [0] = "Quiet", [1] = "Simple", [2] = "Advanced", [3] = "Full" }

-- How much chat an area (sync, record...) is set to show: 0 quiet to 3 everything
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
-- Pairing codes for the Companion app are never shown anywhere, debugging included.
local function hideCode(text) if text:find("^PCODE\t") or text:find("^PCOK\t") then return text:match("^%u+") .. " (code hidden)" end return text end

S.HideCode = hideCode

-- One line describing a message for the Sync traffic list (pairing codes hidden)
local function describe(text)
    text = hideCode(text)

    local kind, id, i, n, chunk = text:match("^(%u+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")

    if kind then return kind .. " part " .. i .. "/" .. n .. " (#" .. id .. ", " .. #chunk .. " bytes)", tonumber(i), tonumber(n) end

    return (text:gsub("\t", " "):sub(1, 60))
end

S.DescribeSync = describe

-- Run fn safely. One bad frame of drawing must never take the whole addon down.
local errCount, lastErr = 0, 0

-- Runs fn and reports an error in chat instead of breaking whatever called it
function S.Safe(what, fn, ...)
    local ok, err = pcall(fn, ...)

    if ok then return true end

    errCount = errCount + 1

    if GetTime() - lastErr > 30 then
        lastErr = GetTime()

        msg("|cffff6060Hit a snag in " .. what .. ":|r " .. tostring(err):sub(1, 160))

        if errCount > 5 then msg("If this keeps happening, /reload. If it still happens, report the message above on Sterling's GitHub page.") end
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

-- Your quest log: every quest with its title, objectives and whether it's complete
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

            if info then title, isHeader, questID, isComplete = info.title, info.isHeader, info.questID, info.isComplete end
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

-- Every quest the game says you've turned in
function S.ReadCompleted()
    local set = {}
    local list = tryCall(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)

    if type(list) == "table" then for _, id in ipairs(list) do set[id] = true end return set end

    local t = tryCall(GetQuestsCompleted)

    if type(t) == "table" then for id in pairs(t) do set[id] = true end end

    return set
end

-- Has this quest been turned in (by the game's list, or flagged completed)?
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

-- Reads the quest log and the finished list again
function S.Refresh()
    S.log = S.ReadLog()
    S.completed = S.ReadCompleted()

    for qid, quest in pairs(S.log) do S.names[qid] = quest.title; S.LearnName(qid, quest.title) end
end

-- A quest's name from Questie, for quests the game has no name for here
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

-- The best name we have for a quest: saved, partner logs, the game, then Questie
function S.QuestName(qid)
    if S.names[qid] then return S.names[qid] end

    for _, snap in pairs(S.snaps or {}) do if snap.log[qid] and snap.log[qid].title and snap.log[qid].title ~= "" then return snap.log[qid].title end end

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
S.COLORS =
{
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

-- The r, g, b of one of the profile colours
function S.ColorRGB(key)
    for _, c in ipairs(S.COLORS) do if c.key == key then return c.rgb[1], c.rgb[2], c.rgb[3] end end

    return 1, .8, .1
end

-- Put a race face on a texture. Tries the client's atlas, then the classic sprite sheet, then a plain tile.
-- female = true picks the female portrait (falling back to the male one if the client has none).
function S.SetFace(texture, race, female)
    race = race or "Troll"
    race = normRace(race)

    local a, b = female and "female" or "male", female and "male" or "female"
    local base = (ATLAS[race] or ("raceicon-" .. race:lower() .. "-male")):gsub("%-male$", "")
    local tries = { base .. "-" .. a, "raceicon128-" .. race:lower() .. "-" .. a, base .. "-" .. b }

    if race == "SkyborneElf" then
        -- the client's own Skyborne portrait first, the Blood Elf one as a stand-in
        tries = { "raceicon-skyborne-" .. a, "raceicon128-skyborne-" .. a, "raceicon-skyborneelf-" .. a,
                  "raceicon-bloodelf-" .. a, "raceicon128-bloodelf-" .. a, "raceicon-skyborne-" .. b, "raceicon-bloodelf-" .. b }
    end

    if texture.SetAtlas then
        for _, name in ipairs(tries) do
            local ok = pcall(texture.SetAtlas, texture, name)

            if ok and (not texture.GetAtlas or texture:GetAtlas()) then texture:SetTexCoord(0, 1, 0, 1) return "atlas" end
        end
    end

    if COORDS[race] then
        local ok = texture:SetTexture(SHEET)

        -- the classic sheet has the male faces in its top half and the female faces in the bottom half
        local dv = female and .5 or 0

        if ok ~= false then local c = COORDS[race]; texture:SetTexCoord(c[1], c[2], c[3] + dv, c[4] + dv) return "sheet" end
    end

    -- unknown race or no art: a plain tile (tinted by the caller) with nothing else
    texture:SetTexture(nil); texture:SetColorTexture(.6, .6, .65, 1); return "plain"
end

S.FaceSource = function(race) local texture = UIParent:CreateTexture(); local how = S.SetFace(texture, race); texture:Hide(); return how end

-- Your profile (display name, colour, race face), created on first use
function S.Profile()
    SterlingQuestDB.profile = SterlingQuestDB.profile or {}

    local profile = SterlingQuestDB.profile

    if not profile.name or profile.name == "" then profile.name = S.MyName() end
    if profile.race then profile.race = normRace(profile.race) end
    if not profile.race then
        local _, token = UnitRace("player"); token = normRace(token)

        profile.race = token or "Troll"

        if token and not knownRace(token) then table.insert(S.RACES, token); S.RACE_NAME[token] = (UnitRace("player")) end
    end

    if not profile.color then profile.color = "gold" end

    return profile
end

-- Someone else's look (from sync or a session), falling back to sensible defaults.
function S.LookFor(name, sess)
    local prof = S.profiles and S.profiles[name]
    local nick = S.Nickname and S.Nickname(name)

    if nick then
        local base = prof or (sess and { race = sess.race, color = sess.color }) or {}

        return { name = nick, race = base.race or "Troll", color = base.color or "gold", female = base.female }
    end

    if prof then return prof end
    if sess and sess.race then return { name = sess.display or sess.char, race = sess.race, color = sess.color or "gold", female = sess.female } end
    if name == UnitName("player") or S.IsMe(name) then return S.Profile() end

    return { name = name, race = "Troll", color = "gold" }
end

-- Where you are: map id and x, y on it
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

-- A map's name, or "Map <id>" when the game doesn't know it
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

    for qid, quest in pairs(S.log) do
        local objs = {}

        if S.ObjectiveList then for _, o in ipairs(S.ObjectiveList(qid, quest.index)) do objs[#objs + 1] = clean(o.text):gsub("%s+", " ") end end

        entries[qid] = qid .. "." .. (quest.complete and "c" or "a") .. "." .. clean(quest.title) .. "." .. table.concat(objs, "~")
    end

    return entries, S.completed
end

-- The order this character finished its quests, from Questie's journey (every accept and turn-in,
-- timestamped, kept since Questie was installed), merged with what our other PCs knew (the Sterling
-- Quest Sync app's self copy: Questie's journey is saved per PC). qid -> position; nil with neither.
local rankCache, rankKey

-- When each quest was finished, from Questie's journey and your other PCs
function S.DoneTimes()
    local q = rawget(_G, "Questie")
    local j = type(q) == "table" and q.db and q.db.char and q.db.char.journey
    local other = type(SterlingQuestDB.otherDone) == "table" and SterlingQuestDB.otherDone or nil

    if type(j) ~= "table" and not other then return nil end

    local t = {}

    for i, e in ipairs(type(j) == "table" and j or {}) do
        local qid = type(e) == "table" and e.Event == "Quest" and e.SubType == "Complete" and tonumber(e.Quest)

        if qid and not t[qid] then t[qid] = tonumber(e.Timestamp) or i end
    end

    for qid, ts in pairs(other or {}) do
        qid, ts = tonumber(qid), tonumber(ts)

        if qid and ts and (not t[qid] or ts < t[qid]) then t[qid] = ts end
    end

    return t
end

function S.ResetRank() rankCache = nil end

-- Each finished quest's place in the order you did them (cached until something changes)
function S.CompletedRank()
    local q = rawget(_G, "Questie")
    local j = type(q) == "table" and q.db and q.db.char and q.db.char.journey
    local key = (type(j) == "table" and #j or -1) .. ":" .. tostring(SterlingQuestDB.otherDone ~= nil)

    if rankCache and rankKey == key then return rankCache end

    local t = S.DoneTimes()

    if not t then return nil end

    local list = {}

    for qid in pairs(t) do list[#list + 1] = qid end

    table.sort(list, function(a, b) if t[a] ~= t[b] then return t[a] < t[b] end return a < b end)

    local r = {}

    for i, qid in ipairs(list) do r[qid] = i end

    rankCache, rankKey = r, key

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

-- Your quest log and finished quests packed into one string to send
function S.MakeSnapshot(seq)
    local entries, completed = S.SnapshotPieces()
    local parts = {}

    for _, entry in pairs(entries) do parts[#parts + 1] = entry end

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

    for qid, quest in pairs(snap.log) do parts[#parts + 1] = qid .. "." .. (quest.complete and "c" or "a") .. "." .. clean(quest.title) .. "." .. table.concat(quest.objs or {}, "~") end

    table.sort(parts)

    local done = {}

    for qid in pairs(snap.completed) do done[#done + 1] = qid end

    local rk = snap.rank or {}

    table.sort(done, function(a, b) local ra, rb = rk[a] or 0, rk[b] or 0; if ra ~= rb then return ra < rb end; return a < b end)

    return table.concat({ "STR3", clean(snap.name), clean(snap.realm), snap.level or 0, table.concat(parts, ";"), table.concat(done, ","), snap.at or time(), "=", snap.seq or 0, snap.label or "", snap.ordered and "o" or "" }, "^")
end

-- Reads a quest-log string back into a table, or returns why it couldn't
function S.ParseSnapshot(str)
    if type(str) ~= "string" then return nil, "empty" end

    str = str:gsub("^%s+", ""):gsub("%s+$", ""):gsub("||", "|"):gsub("[\r\n]", "")

    local sep = str:sub(1, 5) == "STR3^" and "^" or "|"
    local f = {}

    for piece in (str .. sep):gmatch("(.-)%" .. sep) do f[#f + 1] = piece end

    if not (f[1] == "STR1" or f[1] == "STR2" or f[1] == "STR3") then return nil, "not a Sterling Quest Sync string" end

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

    if str:sub(1, 5) == "STO1:" then
        -- an offline sync string: it has its own window (parts, signature, who it's from)
        if S.UI_Offline then S.UI_Offline(nil, str) else msg("That's an offline sync string. Open a partner's right-click menu > Offline sync.") end

        return
    end

    local snap, err = S.ParseSnapshot(str)

    if not snap then msg("Couldn't read that: " .. err) return end

    snap.source = "import"

    if not S.AddPartner(snap.name, false) then return end

    S.StoreSnap(snap.name, snap, str)
    S.SelectPartner(snap.name)
    msg("Imported " .. snap.name .. "'s quest log (level " .. snap.level .. ").")
    S.UI_Update()
end

---------------------------------------------------------------------------
-- Compare
---------------------------------------------------------------------------
function S.Diff()
    local snap = S.partner

    if not snap then return nil end

    S.Refresh()

    local d = { theyHave = {}, youHave = {}, theyFinished = {}, youFinished = {} }

    for qid, quest in pairs(snap.log) do
        if not S.log[qid] then d.theyHave[#d.theyHave + 1] = { qid = qid, title = quest.title, complete = quest.complete } end
    end

    for qid, quest in pairs(S.log) do
        if not snap.log[qid] then d.youHave[#d.youHave + 1] = { qid = qid, title = quest.title, complete = quest.complete } end
    end

    for qid in pairs(snap.completed) do
        if not S.IsFlaggedDone(qid) then d.theyFinished[#d.theyFinished + 1] = { qid = qid, title = S.QuestName(qid), inLog = S.log[qid] ~= nil } end
    end

    for qid in pairs(S.completed) do
        if not snap.completed[qid] then d.youFinished[#d.youFinished + 1] = { qid = qid, title = S.QuestName(qid), inLog = snap.log[qid] ~= nil } end
    end

    d.shared = {}

    for qid, quest in pairs(S.log) do
        local theirQuest = snap.log[qid]

        if theirQuest then
            local mine = {}

            for _, o in ipairs(S.ObjectiveList(qid, quest.index)) do mine[#mine + 1] = clean(o.text):gsub("%s+", " ") end

            local diff = {}

            for i = 1, math.max(#mine, #(theirQuest.objs or {})) do
                local a, b = mine[i], theirQuest.objs and theirQuest.objs[i]

                if a ~= b and (a or b) then diff[#diff + 1] = { you = a, they = b } end
            end

            if #diff > 0 or quest.complete ~= theirQuest.complete then d.shared[#d.shared + 1] = { qid = qid, title = quest.title, youDone = quest.complete, theyDone = theirQuest.complete, diff = diff } end
        end
    end

    for _, list in pairs(d) do table.sort(list, function(a, b) return a.title < b.title end) end

    return d
end

---------------------------------------------------------------------------
-- Live sync (quest snapshot + sessions on request)
---------------------------------------------------------------------------
-- One addon message carries at most 255 bytes. A part is "KIND<tab>id<tab>i<tab>n<tab>" (up to 20 bytes) plus
-- this much of the text, so every message stays inside the limit and ChatThrottleLib accepts it.
local CHUNK = 232
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

-- A character name without its realm
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

-- Every way your own name can appear (full name, first word, profile name), squashed for matching
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

-- Is this name you?
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

-- Do two character names match, ignoring spaces, case and realm?
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

-- Which partners a sync state key covers (a whisper key is one person, GROUP is everyone in the group)
local function namesForKey(key)
    if key:sub(1, 2) == "W:" then return { key:sub(3) } end

    local out = {}

    for _, partner in ipairs(SterlingQuestDB.partners or {}) do
        if partner.on and IsInGroup and IsInGroup() then
            local unit = IsInRaid() and "raid" or "party"

            for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do if sameName(UnitName(unit .. i), partner.name) then out[#out + 1] = partner.name end end
        end
    end

    return out
end

-- Same counters since login or /reload (not saved): S.SessionStat(name)
function S.SessionStat(name)
    S.sync.per[name] = S.sync.per[name] or { sent = 0, recv = 0, bytesOut = 0, bytesIn = 0, snapsOut = 0, deltasOut = 0, snapsIn = 0, deltasIn = 0, acks = 0, replays = 0, resyncs = 0, sessIn = 0, sessOut = 0 }

    return S.sync.per[name]
end

-- Adds to a per-partner counter in the This session stats
local function bump(keyOrName, field, n, stamp)
    local names = keyOrName:find("^W:") and namesForKey(keyOrName) or (keyOrName == "GROUP" and namesForKey("GROUP") or { keyOrName })

    for _, name in ipairs(names) do
        local st = perStat(name); st[field] = (st[field] or 0) + (n or 1); if stamp then st[stamp] = time() end
        local ss = S.SessionStat(name); ss[field] = (ss[field] or 0) + (n or 1); if stamp then ss[stamp] = time() end
    end
end

-- The most recent sync event, for the Sync page: { text=, at= }
function S.SyncEvent(text) S.sync.lastEvent = { text = text, at = time() }; if S.UI_Update then S.UI_Update() end end

---------------------------------------------------------------------------
-- Partners: any number, each with its own on/off switch and its own snapshot.
---------------------------------------------------------------------------
local function shortName(n) return n and (n:match("^([^%-]+)") or n) or nil end

function S.Partners() SterlingQuestDB.partners = SterlingQuestDB.partners or {}; return SterlingQuestDB.partners end

-- A partner by name, and their place in the list
function S.FindPartner(name)
    for i, partner in ipairs(S.Partners()) do if sameName(partner.name, name) then return partner, i end end
end

-- Ten partners at most: every partner is a full quest history kept in your saved data and a share
-- of the game's addon message budget, and ten is plenty for a levelling group.
S.MAX_PARTNERS = 10

function S.PartnersFull() return #S.Partners() >= S.MAX_PARTNERS end

local fullSaid = 0

-- A random half of the secret that signs offline sync strings (the other half is the partner's).
local function newKey()
    local t = {}

    for i = 1, 4 do t[i] = ("%04x"):format(math.random(0, 65535)) end

    return table.concat(t)
end

-- Adds someone to the Sync list (up to the partner limit), or switches them back on
function S.AddPartner(name, enabled)
    name = shortName(name); if not name or name == "" then return end

    if sameName(name, UnitName("player")) or S.IsMe(name) then return end

    local partner = S.FindPartner(name)

    if partner then if enabled ~= nil then partner.on = enabled end; partner.k1 = partner.k1 or newKey(); return partner end
    if S.PartnersFull() then
        if GetTime() - fullSaid > 5 then fullSaid = GetTime(); msg("|cffff9b92Your Sync list is full|r (" .. S.MAX_PARTNERS .. " partners). Remove someone on the Sync tab before adding " .. name .. ".") end

        return nil
    end

    partner = { name = name, on = (enabled ~= false), k1 = newKey(), change = S.ServerTime() }

    table.insert(S.Partners(), partner)

    return partner
end

-- Takes someone off the Sync list and forgets their quest log
function S.RemovePartner(name)
    local partner, i = S.FindPartner(name)

    if partner and partner.guid and partner.guid ~= S.MyGUID() then
        -- remembered (with the game server's time) so the Companion app can end that pairing too
        SterlingQuestDB.removedG = SterlingQuestDB.removedG or {}
        SterlingQuestDB.removedG[partner.guid] = S.ServerTime()
    end

    if partner and S.IsFav and S.IsFav(partner) then S.SetFav(partner, false) end   -- a removed partner is no longer a favourite
    if partner then
        table.remove(S.Partners(), i); S.snaps[partner.name] = nil

        if SterlingQuestDB.snaps then SterlingQuestDB.snaps[partner.name] = nil end
        if SterlingQuestDB.offline then SterlingQuestDB.offline[partner.name] = nil end
    end

    if SterlingQuestDB.compareWith and sameName(SterlingQuestDB.compareWith, name) then SterlingQuestDB.compareWith = nil end

    S.SelectPartner(nil)
end

-- Keeps a partner's quest log after a sync, and tells the windows to update
function S.StoreSnap(name, snap, str)
    name = shortName(name)

    if sameName(name, UnitName("player")) then return end

    S.snaps[name] = snap

    if snap.label and snap.label ~= "" and snap.seq then
        SterlingQuestDB.recvLabels = SterlingQuestDB.recvLabels or {}
        SterlingQuestDB.recvLabels[name] = SterlingQuestDB.recvLabels[name] or {}
        SterlingQuestDB.recvLabels[name][snap.label] = snap.seq
    end

    for qid, quest in pairs(snap.log) do S.LearnName(qid, quest.title) end

    SterlingQuestDB.snaps = SterlingQuestDB.snaps or {}
    SterlingQuestDB.snaps[name] = str
end

-- Pick which partner the Compare tab looks at. nil = best available (selected, else first live, else any).
function S.SelectPartner(name)
    if name then SterlingQuestDB.compareWith = shortName(name) end

    local want = SterlingQuestDB.compareWith

    if want and S.snaps[want] then S.partner = S.snaps[want] return S.partner end

    local best

    for _, partner in ipairs(S.Partners()) do
        local snap = S.snaps[partner.name]

        if snap and (not best or (snap.source == "live" and best.source ~= "live")) then best = snap end
    end

    if not best then for _, snap in pairs(S.snaps) do best = best or snap end end

    S.partner = best

    return best
end

-- Is this person in your party or raid?
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

-- Sets or clears your nickname for a partner
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
            if sameName(UnitName(unit .. i), name) then local _, classToken = UnitClass(unit .. i); return classToken end
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
            local gname, _, _, _, _, _, _, _, _, _, classToken = GetGuildRosterInfo(i)

            if sameName(gname, name) then return classToken end
        end
    end
end

-- When we last got quest data from them (their snapshot's time), or nil.
function S.LastSynced(name) local snap = S.snaps[shortName(name) or ""]; return snap and snap.at or nil end

-- How a partner is shown: your nickname, else their profile name, else their first name
function S.PartnerLabel(name)
    local n = shortName(name) or "?"
    local nick = S.Nickname(n)

    if nick then return nick end

    local prof = S.profiles and S.profiles[n]

    if prof and prof.name and prof.name ~= "" and prof.name ~= n then return prof.name end

    return n:match("^(%S+)") or n
end

S.ADDON_VER = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"

-- Build number: one number that only ever goes up, used for every "older / newer" check so the
-- visible version can be anything. It is worked out from the version text, so nothing extra travels.
-- Released versions have three parts; internal builds add a fourth (0.3.17.01, 0.3.17.02 ...), which
-- sorts after the release it started from and before the next one: 0.3.17 < 0.3.17.03 < 0.3.18.
--   0.3.17 -> 317000, 0.3.17.03 -> 317003, 0.2.30 -> 230000 (minor * 100000 + patch * 1000 + internal,
--   so up to 999 internal builds fit between two releases)
--   5.84 -> 184000, 6.0 -> 200000, 6.29 -> 229000 (the old two-part numbers that came before)
--   1.0.0 and up -> 10000000 and up
-- Copies before 0.3.17.01 ignore the fourth part (and count 1000 times smaller), but they only ever
-- compare versions with their own numbers, so the two scales never meet.
-- The toc carries the same number as X-Build so the two can be checked against each other.
function S.BuildOf(ver)
    if not ver then return nil end

    local p = {}

    for n in tostring(ver):gmatch("%d+") do p[#p + 1] = tonumber(n) end

    if #p == 0 then return nil end

    local a, b, c, internal = p[1], p[2] or 0, p[3] or 0, p[4] or 0

    if a == 0 then return (b * 100 + c) * 1000 + internal end
    if a >= 5 and #p <= 2 then return ((a - 4) * 100 + b) * 1000 end

    return (a * 10000 + b * 100 + c) * 1000 + internal
end

do
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, b = pcall(function() return meta and meta(ADDON, "X-Build") end)

    S.BUILD = (ok and tonumber(b)) or S.BuildOf(S.ADDON_VER) or 0
end

-- -1 if a is older than b, 1 if newer, 0 if the same or unknown.
function S.CompareVer(a, b)
    local x, y = S.BuildOf(a), S.BuildOf(b)

    if not x or not y then return 0 end
    if x < y then return -1 elseif x > y then return 1 end

    return 0
end

-- Where a partner stands against this copy:
--   "nosync"  their sync protocol differs: nothing is exchanged until someone updates (red)
--   "older"   their Sterling is older but still syncs (amber)
--   "newer"   theirs is newer: yours is the outdated one (amber)
--   "same" / nil when it matches or isn't known yet
-- Second value: who should update ("they" or "you").
function S.VersionState(name)
    local proto = S.sync and S.sync.vers and S.sync.vers[name]
    local partner = S.FindPartner(name)
    local ver = (S.addonVers and S.addonVers[name]) or (partner and partner.ver)

    if proto and proto ~= S.VERSION then return "nosync", proto < S.VERSION and "they" or "you", ver end
    if not ver then return nil, nil, nil end

    local cmp = S.CompareVer(ver, S.ADDON_VER)

    if cmp < 0 then return "older", "they", ver elseif cmp > 0 then return "newer", "you", ver end

    return "same", nil, ver
end

function S.PartnerOnline(name) local online = S.PartnerStatus(name); return online end
function S.MarkHeard(name) heard[name] = GetTime() end

-- Seconds since we last heard from someone (or from anyone, without a name)
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

    for _, partner in ipairs(S.Partners()) do
        local theirProto = S.sync and S.sync.vers and S.sync.vers[partner.name]
        local okVer = (theirProto == nil) or (theirProto == S.VERSION)

        if partner.on and okVer and not useGroup(partner.name) and S.PartnerOnline(partner.name) then list[#list + 1] = { chan = "WHISPER", target = partner.name, key = "W:" .. partner.name } end
    end

    return list
end

local function channel() local t = S.Targets()[1]; if t then return t.chan, t.target end end

-- Messages waiting to go out (ours plus anything handed to ChatThrottleLib and not yet sent).
local waiting, handed = 0, 0   -- handed: every message ever queued this session (for "sending N messages" lines)

local function queued() return #queue + waiting end

S.QueuedMessages = queued

-- Bookkeeping once a message has really left: chat detail, progress for the Sync tab, counters.
local function afterSend(item)
    do
        local d, i, n = describe(item.text)

        if not i or i == 1 or i == n then dbg("sync", "out to " .. (item.target or item.chan) .. ": " .. d .. ((i and n > 2 and i == 1) and "  ..." or "") .. "  |cff8a93a8(" .. queued() .. " queued)|r") end

        -- live progress for the Sync tab (only for logs big enough to take a moment)
        if i and n and n > 2 then S.sync.prog = { who = item.target and (item.target:match("^([^%-]+)") or item.target) or "group", dir = "out", got = i, n = n, t = GetTime() } end
    end

    S.sync.trace = S.sync.trace or {}

    table.insert(S.sync.trace, 1, date("%H:%M:%S") .. " out " .. (item.target or item.chan) .. ": " .. hideCode(item.text):sub(1, 48):gsub("\t", " "))

    if #S.sync.trace > 30 then S.sync.trace[31] = nil end

    S.sync.sent = S.sync.sent + 1; S.sync.bytesOut = S.sync.bytesOut + #item.text; S.sync.lastOut = time(); S.sync.lastChan = item.target or item.chan

    local k = item.target and ("W:" .. item.target) or "GROUP"

    bump(k, "sent", 1, "lastOut"); bump(k, "bytesOut", #item.text)

    return true
end

-- Fallback sender, used only if ChatThrottleLib is somehow missing: straight to the game.
local function rawSend(item)
    if S.testMode then return true end

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

    return afterSend(item)
end

-- ChatThrottleLib (bundled in Libs) is the game-wide standard for pacing addon messages: every addon
-- that uses it shares one budget, so Sterling can't get anyone disconnected for chatting too fast and
-- never starves other addons. It retries throttled messages itself; we only retry real failures.
local function ctl() local c = rawget(_G, "ChatThrottleLib"); return type(c) == "table" and type(c.SendAddonMessage) == "function" and c or nil end

local viaCTL

-- ChatThrottleLib reports a message went out or was refused; refused ones are put back in the queue
local function sentCallback(item, ok, res)
    waiting = math.max(0, waiting - 1)

    -- (a much older ChatThrottleLib calls back with no result at all: that means it went out)
    if ok or (ok == nil and res == nil) then afterSend(item) return end

    S.sync.throttled = (S.sync.throttled or 0) + 1
    item.tries = (item.tries or 0) + 1

    dbg("sync", "|cffff9b92refused by the game|r (code " .. tostring(res) .. ")" .. (item.tries <= 6 and ", will retry" or ", giving up") .. ": to " .. (item.target or item.chan) .. " " .. describe(item.text))

    if item.tries <= 6 then C_Timer.After(1.5, function() viaCTL(item) end) end
end

-- Sends one message through ChatThrottleLib, falling back to our own slow queue without it
viaCTL = function(item)
    if S.testMode then return true end

    local throttle = ctl()

    if not throttle then return false end

    waiting = waiting + 1

    -- parts of a log are bulk; everything else (confirmations, version, invites, pings) is a short control
    -- message that shouldn't wait behind a long log going to someone else
    local prio = item.text:find("^%u+\t%d+\t%d+\t%d+\t") and "NORMAL" or "ALERT"
    local ok, err = pcall(throttle.SendAddonMessage, throttle, prio, S.PREFIX, item.text, item.chan, item.target, nil, sentCallback, item)

    if not ok then waiting = math.max(0, waiting - 1); dbg("sync", "|cffff9b92send error|r: " .. tostring(err)); return false end

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
    if S.testMode then return false end   -- screenshot mode: nothing goes out

    local targets = tgt and { tgt } or S.Targets()

    if #targets == 0 then return false end

    for _, t in ipairs(targets) do
        local item = { text = text, chan = t.chan, target = t.target }

        handed = handed + 1

        if not viaCTL(item) then queue[#queue + 1] = item end
    end

    if #queue > 0 and not draining then drain() end

    return true
end

local outbox, chunkN = {}, 0

-- Sends a long string in numbered parts that the other side puts back together
local function sendChunked(kind, str, target)
    local n = math.ceil(#str / CHUNK)

    chunkN = (chunkN + 1) % 10

    local id = tostring(time() % 100000) .. chunkN       -- unique even for two sends in the same second

    outbox[kind .. id] = { str = str, n = n, at = time() }

    for k, o in pairs(outbox) do if time() - o.at > 300 then outbox[k] = nil end end
    for i = 1, n do send(table.concat({ kind, id, i, n, str:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"), target) end
end

-- They told us which parts never arrived: send just those again.
local function resendParts(kind, id, list, target)
    local o = outbox[kind .. id]

    if not o then return false end

    for i in list:gmatch("%d+") do
        i = tonumber(i)

        if i >= 1 and i <= o.n then send(table.concat({ kind, id, i, o.n, o.str:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"), target) end
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

-- Copy numbers. Partly the game server's clock, so they keep rising when one character plays on two
-- PCs: a counter saved per PC alone made the other PC's small updates look "old" to partners, who
-- dropped them. The server clock is the same on every PC; the counter keeps two copies in one second apart.
-- The game server's clock (the same on every PC), and this character's id. Names are display only.
function S.ServerTime() return (GetServerTime and GetServerTime()) or time() end

S.GUID_PAT = "^Player%-%d%d?%d?%d?%d?%-%x%x%x%x%x%x%x%x$"

function S.ValidGUID(g) return type(g) == "string" and g:match(S.GUID_PAT) ~= nil and g:upper():sub(8) == g:sub(8) end
function S.MyGUID() local g = UnitGUID and UnitGUID("player"); return S.ValidGUID(g) and g or nil end

-- A partner by their character id
function S.PartnerByGUID(g)
    if not g then return nil end

    for _, partner in ipairs(S.Partners()) do if partner.guid == g then return partner end end
end

-- The next copy number: always higher than the last, even across two PCs
local function nextSeq()
    local now = (GetServerTime and GetServerTime()) or 0
    local n = math.max((SterlingQuestDB.syncSeq or 0) + 1, now)

    SterlingQuestDB.syncSeq = n

    return n
end

-- Human label for a sync: MM.DD.YY-HH.MM.n (24h clock, n counts syncs within the same minute)
local function nextLabel()
    local minute = date("%m.%d.%y-%H.%M")

    if SterlingQuestDB.labelMinute == minute then SterlingQuestDB.labelN = (SterlingQuestDB.labelN or 1) + 1 else SterlingQuestDB.labelMinute, SterlingQuestDB.labelN = minute, 1 end

    return minute .. "." .. SterlingQuestDB.labelN
end

S.NextSyncLabel = nextLabel

-- Remembers what was sent, so a later confirmation can be matched to it
local function logEntry(key, e)
    local j = journal(key)

    j[#j + 1] = e

    while #j > JOURNAL_MAX do table.remove(j, 1) end
end

-- Sends your quest log to one partner or the group: the whole log, or only what changed since they last confirmed
local function sendTo(target, force, full, entries, completed, level)
    local state = syncState()[target.key]

    if full or not state then
        local seq = nextSeq()
        local label = nextLabel()
        local body = S.MakeSnapshot(seq) .. "^" .. label .. "^o"   -- "o": finished quests are in the order they were done

        sendChunked("SNAP", body, target)

        local e2, doneCopy = {}, {}

        for q, entry in pairs(entries) do e2[q] = entry end
        for qid in pairs(completed) do doneCopy[qid] = true end

        syncState()[target.key] = { seq = seq, entries = e2, done = doneCopy, level = level, fullAt = time() }

        logEntry(target.key, { seq = seq, label = label, at = time(), kind = "full", n = #body })

        S.sync.snapsOut = S.sync.snapsOut + 1; S.sync.lastSnapOut = time(); S.sync.lastMode = "full"
        bump(target.key, "snapsOut", 1, "lastSnapOut"); for _, nm in ipairs(namesForKey(target.key)) do perStat(nm).lastMode = "full"; perStat(nm).lastLabel = label end

        return true
    end

    local changed, removed, newDone = {}, {}, {}

    for qid, entry in pairs(entries) do if state.entries[qid] ~= entry then changed[#changed + 1] = entry end end
    for qid in pairs(state.entries) do if not entries[qid] then removed[#removed + 1] = qid end end
    for qid in pairs(completed) do if not state.done[qid] then newDone[#newDone + 1] = qid end end

    if #changed == 0 and #removed == 0 and #newDone == 0 and level == state.level then return false end

    table.sort(changed); table.sort(removed); orderDone(newDone)

    local seq = nextSeq()
    local label = nextLabel()
    local body = table.concat({ state.seq, seq, level, table.concat(changed, ";"), table.concat(removed, ","), table.concat(newDone, ","), label }, "^")

    sendChunked("DELT", body, target)
    logEntry(target.key, { seq = seq, label = label, base = state.seq, at = time(), kind = "delta", body = body, n = #body })

    state.seq = seq; state.level = level
    state.entries = {}; for q, entry in pairs(entries) do state.entries[q] = entry end

    for _, q in ipairs(newDone) do state.done[q] = true end

    S.sync.deltasOut = (S.sync.deltasOut or 0) + 1; S.sync.lastSnapOut = time(); S.sync.lastMode = "delta"
    bump(target.key, "deltasOut", 1, "lastSnapOut"); for _, nm in ipairs(namesForKey(target.key)) do perStat(nm).lastMode = "delta"; perStat(nm).lastLabel = label end

    return true
end

-- Replay everything after `since` to one target from the journal; full copy if the journal can't reach back.
local function replay(target, since)
    local j = journal(target.key)
    local state = syncState()[target.key]
    local entries, completed = S.SnapshotPieces()
    local level = UnitLevel("player") or 0

    if state and state.seq == since then
        -- they have everything we've sent, but our log may have changed since: send that now
        return sendTo(target, true, false, entries, completed, level)
    end

    local chain, base = {}, since

    for _, e in ipairs(j) do
        if e.kind == "delta" and e.base == base then chain[#chain + 1] = e; base = e.seq end
    end

    if #chain > 0 and state and base == state.seq then
        for _, delta in ipairs(chain) do sendChunked("DELT", delta.body, target) end

        S.sync.replays = (S.sync.replays or 0) + 1; bump(target.key, "replays")

        sendTo(target, true, false, entries, completed, level)

        return true
    end

    return sendTo(target, true, true, entries, completed, level)
end

---------------------------------------------------------------------------
-- User-started syncs: one call per button, with "started" and "complete" lines in chat.
-- mode: quick (send mine, ask for theirs), send, receive, full (fresh copies both ways)
---------------------------------------------------------------------------
S.pending = S.pending or {}

-- "got 3 of 8 parts" for a sync that's still coming in
local function partsFor(name)
    for k, box in pairs(inbox) do
        if k:sub(1, #name + 1) == name .. ":" then return "got " .. box.got .. " of " .. box.n .. " parts of their log" end
    end
end

-- Ends a sync that was waiting, with a chat line saying how it went
local function finish(name, text, failed)
    local pending = S.pending[name]

    S.pending[name] = nil

    -- short form for the Sync page's "Last" line
    local who = S.PartnerLabel(name)
    local kind = (pending and pending.mode == "full") and "Full sync" or ((pending and pending.auto) and "Auto sync" or "Sync")
    local short

    if text:find("complete") then short = kind .. " with " .. who .. " complete"
    elseif text:find("up to date") then short = who .. " already up to date"
    elseif text:find("didn't finish") then short = kind .. " with " .. who .. " didn't finish"
    elseif text:find("switched off") then short = who .. " has sync off"
    elseif text:find("offline") or text:find("online") then short = who .. " went offline"
    else short = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):sub(1, 40) end
    S.SyncEvent(short)

    -- user-started syncs talk at Simple; auto syncs at Advanced; failures of user-started syncs always
    local level = (pending and pending.auto) and 2 or ((failed and 0) or 1)

    say("sync", level, text)
end

-- Updates a waiting sync when something comes back from that partner
function S.SyncHeard(name, what, detail)
    local pending = S.pending[name]

    if not pending then return end

    local who = S.PartnerLabel(name)

    if what == "off" then finish(name, who .. " has sync with you switched off on their side, so nothing came back.", true) return end
    if what == "notp" then finish(name, who .. " hasn't added you yet. Ask them to type your name in the Sync tab's + Add box, then sync again.", true) return end
    if what == "confirmed" then pending.confirmed = true
    else pending.got = detail or "already up to date"; if what == "current" then pending.got = "already up to date" end end
    if pending.mode == "full" then
        if pending.got and pending.confirmed then finish(name, "|cff7ee2a2Full sync complete|r with " .. who .. ": got theirs (" .. pending.got .. "), they confirmed yours.") end
    elseif pending.mode == "send" then
        if pending.confirmed then finish(name, "|cff7ee2a2Sync complete|r with " .. who .. ": they have your changes.") end
    elseif pending.got then
        finish(name, "|cff7ee2a2Sync complete|r with " .. who .. ": " .. pending.got .. ".")
    end
end

-- Where to send something for one person: the group channel when grouped, else a whisper
local function direct(name)
    if useGroup(name) then return { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } end

    return { chan = "WHISPER", target = name, key = "W:" .. name }
end

-- Asks for any message parts that seem to have gone missing
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

    for _, partner in ipairs(S.Partners()) do
        if partner.on then send("PING", useGroup(partner.name) and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = partner.name, key = "W:" .. partner.name }); n = n + 1 end
    end

    dbg("sync", "refresh: pinged " .. n .. " partner" .. (n == 1 and "" or "s"))

    S.lastRefresh = time()

    if S.UI_Update then S.UI_Update() end

    C_Timer.After(2.5, function() if S.UI_Update then S.UI_Update() end end)
end

-- Turns one of the game's system message formats into a pattern that picks out the name
local function sysPattern(fmt)
    if type(fmt) ~= "string" then return nil end

    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")

    return "^" .. p .. "$"
end

-- Watches system messages for "player not online" so a waiting sync stops early
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

    P("me: v" .. tostring(S.ADDON_VER) .. ", protocol " .. S.VERSION .. ", live sync " .. (SterlingQuestDB.sync and "on" or "off") .. ", queue " .. queued() .. ((draining or waiting > 0) and " (sending)" or "") .. ", refused so far " .. tostring(S.sync.throttled or 0) .. ", resend requests answered " .. tostring(S.sync.partsResent or 0))

    for _, partner in ipairs(S.Partners()) do
        local online, how = S.PartnerStatus(partner.name)
        local state = syncState()["W:" .. partner.name]
        local snap = S.snaps[partner.name]
        local lh = heard[partner.name] and math.floor(GetTime() - heard[partner.name]) or nil

        P(partner.name .. (partner.on and "" or " (unchecked)") .. ": " .. (online and ("online via " .. tostring(how)) or "offline") .. ", heard " .. (lh and (lh .. "s ago") or "never this session") ..
            ", v" .. tostring((S.addonVers and S.addonVers[partner.name]) or partner.ver or "?") .. ", protocol " .. tostring(S.sync.vers and S.sync.vers[partner.name] or "?"))
        P("   ours to them: #" .. tostring(state and state.seq or "none") .. "   theirs here: #" .. tostring(snap and snap.seq or "none") .. (snap and snap.at and (" from " .. date("%m/%d %H:%M", snap.at)) or "") .. (S.pending[partner.name] and ("   waiting: " .. S.pending[partner.name].mode .. " sync") or ""))
    end

    local n = 0

    for key, box in pairs(inbox) do n = n + 1; P("incoming " .. key .. ": " .. box.got .. "/" .. box.n .. " parts, asked " .. (box.asks or 0) .. "x, last part " .. (box.last and (math.floor(GetTime() - box.last) .. "s ago") or "?")) end

    if n == 0 then P("no unfinished incoming copies") end

    local o = 0; for _ in pairs(outbox) do o = o + 1 end

    P(o .. " sent copies kept for resends")
end

-- auto = started by Sterling itself (login, partner came online, joined a group): quieter in chat.
function S.SyncWith(who, mode, auto)
    if S.testMode then return end   -- screenshot mode: no syncs start, so nothing shows "Syncing..."

    local names = {}

    if who then names[1] = who
    else for _, partner in ipairs(S.Partners()) do if partner.on and S.PartnerOnline(partner.name) then names[#names + 1] = partner.name end end end
    if #names == 0 then if not auto then msg("Sync: nobody online to sync with.") end return end

    local entries, completed = S.SnapshotPieces()
    local level = UnitLevel("player") or 0
    local lvl = auto and 2 or 1

    for _, name in ipairs(names) do
        local who2 = S.PartnerLabel(name)
        local target = direct(name)

        if not S.PartnerOnline(name) and not auto then msg("Sync with " .. who2 .. ": they look offline. Trying anyway.") end

        local token = {}

        S.pending[name] = { mode = mode, at = GetTime(), token = token, auto = auto }

        local pre = auto and "Auto sync" or "Sync"

        if mode == "full" then
            S.ResetSync(target.key)

            if S.snaps[name] then S.snaps[name].seq = 0 end

            send("REQ\t" .. S.VERSION, target)
            sendTo(target, true, true, entries, completed, level)
            say("sync", lvl, "|cfff3c56bFull sync started|r with " .. who2 .. ": asked for their log, sending yours.")
            S.SyncEvent("Full sync with " .. who2 .. " started")
        elseif mode == "send" then
            if not sendTo(target, true, false, entries, completed, level) then finish(name, pre .. " with " .. who2 .. ": nothing new to send, they're up to date.") end
            if S.pending[name] then say("sync", lvl, pre .. " started with " .. who2 .. ": sent your changes."); S.SyncEvent(pre .. " with " .. who2 .. " started") end
        else
            if mode == "quick" then sendTo(target, true, false, entries, completed, level) end

            S.RequestPartner(name)
            say("sync", lvl, pre .. " started with " .. who2 .. ": " .. (mode == "quick" and "sent your changes, " or "") .. "asked for theirs.")
            S.SyncEvent(pre .. " with " .. who2 .. " started")
        end

        C_Timer.After(mode == "full" and 60 or 30, function()
            local pending = S.pending[name]

            if not (pending and pending.token == token) then return end

            local missing = {}

            if pending.mode == "full" then
                if not pending.got then missing[#missing + 1] = "their log never arrived" .. (partsFor(name) and (" (" .. partsFor(name) .. ")") or "") end
                if not pending.confirmed then missing[#missing + 1] = "they didn't confirm yours" end
            elseif pending.mode == "send" then missing[1] = "they didn't confirm your changes"
            else missing[1] = "no reply" .. (partsFor(name) and (" (" .. partsFor(name) .. ")") or "") end
            local theirVer = (S.addonVers and S.addonVers[name]) or (S.FindPartner(name) and S.FindPartner(name).ver)
            local vnum = S.BuildOf(theirVer)
            local why

            if vnum and vnum >= 137000 then   -- 5.37
                why = "They're on v" .. theirVer .. ", so it isn't the version. They may have zoned, logged out, or not gotten your messages. Hit Refresh, then try again."
            elseif theirVer then
                why = "They're on v" .. theirVer .. ". Both of you need 5.37 or newer for this to finish reliably."
            else
                why = "Their version is unknown. They may be offline, or need 5.37 or newer."
            end

            finish(name, "|cffff9b92" .. (pending.auto and "Auto sync" or "Sync") .. " with " .. who2 .. " didn't finish|r after " .. (pending.mode == "full" and 60 or 30) .. " seconds: " .. table.concat(missing, ", ") .. ". " .. why, true)
        end)
    end
end

---------------------------------------------------------------------------
-- Auto sync: a quick sync (send my changes, ask for theirs) when I log in, when a partner comes
-- online, and when a partner joins my group. Every 5 minutes, a check that nothing was missed.
---------------------------------------------------------------------------
S.offSince = {}       -- name -> GetTime() when they first looked offline (cleared when seen online)

local autoDone = {}   -- name -> GetTime() of the last auto sync, so one trigger doesn't fire twice

-- Starts a quiet sync with a partner when the Auto sync option allows it
function S.AutoSync(name, why)
    if S.testMode then return end   -- screenshot mode: no syncs start, so nothing shows "Syncing..."
    if not S.Opt("autoSync", true) or not SterlingQuestDB.sync then return end

    local partner = S.FindPartner(name)

    if not (partner and partner.on) then return end
    if S.pending[partner.name] then return end
    if autoDone[partner.name] and GetTime() - autoDone[partner.name] < 20 then return end

    autoDone[partner.name] = GetTime()

    dbg("sync", "auto sync with " .. partner.name .. ": " .. tostring(why))
    S.SyncWith(partner.name, "quick", true)
end

-- Auto sync with every partner who's online
function S.AutoSyncAll(why)
    for _, partner in ipairs(S.Partners()) do if partner.on and S.PartnerOnline(partner.name) then S.AutoSync(partner.name, why) end end
end

-- The periodic check: ask each online partner for anything after the copy we hold, and send ours.
local function autoCheck()
    if S.testMode then return end   -- screenshot mode: no syncs start, so nothing shows "Syncing..."
    if not S.Opt("autoSync", true) or not SterlingQuestDB.sync then return end

    local n = 0

    for _, partner in ipairs(S.Partners()) do
        if partner.on and S.PartnerOnline(partner.name) and not S.pending[partner.name] then S.RequestPartner(partner.name); n = n + 1 end
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

-- Asks a partner to share a quest with you
function S.AskShare(name, qid)
    send("ASK\t" .. qid .. "\t" .. clean(S.QuestName(qid)), direct(name))
    msg("Asked " .. S.PartnerLabel(name) .. " to share " .. S.QuestName(qid) .. ".")
end

-- The last copy of yours that a partner confirmed: number, time and label
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

    for _, target in ipairs(targets) do
        if not only or target.key == only then sendTo(target, force, full, entries, completed, level) end
    end
end

-- Sends a recorded session to your partners
function S.SendSession(sess)
    if not sess then msg("No such session.") return end
    if not channel() then msg("Nobody to send to: add a partner in the Sync tab, and be online at the same time.") return end

    sendChunked("SESS", S.EncodeSession(sess)); S.sync.sessOut = S.sync.sessOut + 1; for _, t in ipairs(S.Targets()) do bump(t.key, "sessOut") end; msg("Sent session \"" .. sess.name .. "\".")
end

S.warned = {}

-- Warns once in chat when a partner's Sterling can't sync with yours
function S.VersionMismatch(name, ver)
    if S.warned[name] == ver then return end

    S.warned[name] = ver

    if ver < S.VERSION then msg("|cffff9b92Can't sync with " .. name .. ": update needed.|r Their Sterling Quest Sync is too old to talk to yours. They need to update (WowUp, or the zip you have).")
    else msg("|cffff9b92Can't sync with " .. name .. ": update needed.|r Their Sterling Quest Sync is newer than yours. Update yours (WowUp, or their zip).") end
end

-- Partners known to be on a different version: { {name=, ver=}, ... }
function S.Mismatches()
    local out = {}

    for name, v in pairs((S.sync and S.sync.vers) or {}) do if v ~= S.VERSION then out[#out + 1] = { name = name, ver = v } end end

    table.sort(out, function(a, b) return a.name < b.name end)

    return out
end

-- Ask for a copy. If we already hold a numbered copy from that person, ask only for what came after it.
function S.SendProfile(target)
    local profile = S.Profile()

    send("PROF\t" .. (profile.race or "Troll") .. "\t" .. (profile.color or "gold") .. "\t" .. (profile.name or ""), target)
    send("FACE\t" .. (profile.female and "f" or "m"), target)   -- female or male portrait, right after PROF (older copies ignore it)
    send("AVER\t" .. tostring(S.ADDON_VER), target)   -- addon version, shown on hover in the Sync list (older copies ignore it)
    send("ME\t" .. S.SESSION_TOKEN, target)            -- if this comes back to us, its sender name is ours

    local g = S.MyGUID()

    if g then send("GID\t" .. g, target) end          -- character id for the Companion app (older copies ignore it)

    -- our Companion app version (older copies ignore it): the version, empty = no app,
    -- nothing at all when the companion is there but its inbox doesn't say yet
    -- level, class token and race, for the Companion app's partner list (older copies ignore it)
    do
        local _, classToken = UnitClass("player")

        send("CHAR\t" .. tostring(UnitLevel("player") or 0) .. "\t" .. tostring(classToken or "") .. "\t" .. tostring((UnitRace("player")) or ""):gsub("[\t|]", ""), target)
    end

    local av = S.MyAppVersion()

    if av or not S.AppPresent() then send("APPV\t" .. (av or ""), target) end
end

-- Asks a partner for their quest log: only the changes if we have an earlier copy, else all of it
function S.RequestPartner(name)
    if S.testMode then return end

    -- Sends the request to one channel
    local function ask(target, who)
        local snap = who and S.snaps[who]

        if snap and snap.seq and snap.seq > 0 then send("SINCE\t" .. S.VERSION .. "\t" .. snap.seq, target) else send("REQ\t" .. S.VERSION, target) end
    end

    if name then ask({ chan = "WHISPER", target = name, key = "W:" .. name }, name); S.SendKey(name)
    else for _, t in ipairs(S.Targets()) do ask(t, t.target); if t.target then S.SendKey(t.target) end end end
end

local pending = false

-- Sends your changes to partners shortly, so several quick changes go out as one
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
-- Store a partner's full copy (from a live sync or an offline string). Returns the snapshot and
-- whether it is the first live copy from them; nil when it turned out to be our own log.
function S.ApplyFull(short, whole, sender, source)
    local snap = S.ParseSnapshot(whole)

    if not snap then return nil end
    if S.IsMe(snap.name) then
        -- a copy of our own log under another spelling of our name: never a partner
        if S.FindPartner(short) then S.RemovePartner(short) end

        dbg("sync", "ignored a copy of your own log from " .. tostring(sender or short))

        return nil
    end

    snap.source = source or "live"; snap.at = time(); snap.name = short

    local prev = S.snaps[short]
    local first = (prev == nil) or prev.source ~= "live"

    if not S.AddPartner(short) then return nil end

    S.StoreSnap(short, snap, whole)
    S.SelectPartner(nil)

    return snap, first
end

-- Apply a partner's changes on top of the copy we hold. Returns:
--   "old"                       already applied
--   "step", base, have          it builds on a copy we don't hold
--   "ok", changes, seq          applied
function S.ApplyDelta(short, whole)
    local f = {}

    for piece in (whole .. "^"):gmatch("(.-)%^") do f[#f + 1] = piece end

    local base, seq, level = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
    local snap = S.snaps[short]

    if snap and snap.seq and seq and seq <= snap.seq then return "old" end
    if not (seq and snap and (snap.source == "live" or snap.source == "saved" or snap.source == "offline") and snap.seq == base) then return "step", base, snap and snap.seq end

    for item in (f[4] or ""):gmatch("[^;]+") do
        local qid, st, title, objs = item:match("^(%d+)%.(%a)%.([^%.]*)%.?(.*)$")

        if qid then
            local o = {}

            for t in (objs or ""):gmatch("[^~]+") do o[#o + 1] = t end

            snap.log[tonumber(qid)] = { title = title, complete = (st == "c"), objs = o }
        end
    end

    for qid in (f[5] or ""):gmatch("%d+") do snap.log[tonumber(qid)] = nil end

    snap.rank = snap.rank or {}

    for qid in (f[6] or ""):gmatch("%d+") do
        qid = tonumber(qid)

        if not snap.completed[qid] then snap.completed[qid] = true; snap.rankMax = (snap.rankMax or 0) + 1; snap.rank[qid] = snap.rankMax end
    end

    snap.level = level or snap.level; snap.seq = seq; snap.at = time(); snap.label = f[7] ~= "" and f[7] or snap.label

    S.StoreSnap(short, snap, S.SnapshotToString(snap))
    S.SelectPartner(nil)

    local nc = 0

    for _ in (f[4] or ""):gmatch("[^;]+") do nc = nc + 1 end
    for _ in (f[5] or ""):gmatch("%d+") do nc = nc + 1 end
    for _ in (f[6] or ""):gmatch("%d+") do nc = nc + 1 end

    return "ok", nc, seq
end

---------------------------------------------------------------------------
-- Offline sync: the same data as a live sync, as a string you can paste anywhere (Discord, a text).
--   STO1:<part>/<parts>:<id>:<data>      data = EncodeForPrint(Deflate(signature \n checksum \n header \n body))
--   header = O1^protocol^from^to^F|D^ack^key half^addon version
--   body   = a full copy (same as SNAP) or changes since the last copy they confirmed (same as DELT)
-- Signing: each side of a partnership makes a random key half. The halves are swapped by whisper at
-- the next live sync (KEY), or carried once inside a full offline string (trust on first use, with a
-- warning on the receiving side). Both halves together sign every string after that. Strings holding
-- only changes must be signed; a full copy may arrive unsigned, and then the player is asked first.
---------------------------------------------------------------------------
local function LD()
    local ls = rawget(_G, "LibStub")

    if type(ls) ~= "table" then return nil end

    local ok, lib = pcall(ls.GetLibrary, ls, "LibDeflate", true)

    return ok and type(lib) == "table" and lib or nil
end

S.LibDeflate = LD

local function hex32(h) return ("%04x%04x"):format(math.floor(h / 65536), h % 65536) end

-- Keyed checksum (two running hashes over key + text + key). Not bank-grade, but nobody without the
-- key can make a string that passes, which is all it has to do.
local function sign(key, text)
    local h1, h2 = 5381, 40503
    local src = key .. "\n" .. text .. "\n" .. key

    for i = 1, #src do
        local c = src:byte(i)

        h1 = (h1 * 33 + c) % 4294967296
        h2 = (h2 * 65599 + c * 131 + 7) % 4294967296
    end

    return hex32(h1) .. hex32(h2)
end

S.Sign = sign

-- The key both partners share for signing offline strings (their two halves, sorted)
local function sharedKey(partner)
    if not (partner and partner.k1 and partner.k2) then return nil end

    return partner.k1 < partner.k2 and (partner.k1 .. partner.k2) or (partner.k2 .. partner.k1)
end

-- "signed": both halves known. "half": ours only (needs one live sync, or a full string each way).
function S.KeyState(name)
    local partner = S.FindPartner(name)

    if not partner then return "none" end

    return sharedKey(partner) and "signed" or "half"
end

local keySent = {}

-- Sends your half of the shared key to a partner (once a session, unless forced)
function S.SendKey(name, force)
    local partner = S.FindPartner(name)

    if not partner then return end
    if keySent[partner.name] and not force then return end

    partner.k1 = partner.k1 or newKey()
    keySent[partner.name] = true

    send("KEY\t" .. partner.k1, { chan = "WHISPER", target = partner.name, key = "W:" .. partner.name })   -- whisper only, never a group channel
end

-- What the partner is known to hold from us (set when they confirm a live sync or their string says so),
-- and what the last offline string gave them if they imported it.
local function offState(name)
    SterlingQuestDB.offline = SterlingQuestDB.offline or {}
    SterlingQuestDB.offline[name] = SterlingQuestDB.offline[name] or {}

    return SterlingQuestDB.offline[name]
end

-- A copy of what was sent, kept to work out the next set of changes
local function copyState(seq, entries, done, level)
    local e2, d2 = {}, {}

    for q, entry in pairs(entries) do e2[q] = entry end
    for qid in pairs(done) do d2[qid] = true end

    return { seq = seq, entries = e2, done = d2, level = level, at = time() }
end

-- A live ACK for the newest thing we sent: that is now their confirmed copy.
function S.NoteConfirmed(name, seq)
    local state = syncState()["W:" .. name]

    if state and state.seq == seq and S.FindPartner(name) then
        local o = offState(name)

        o.base = copyState(state.seq, state.entries, state.done, state.level); o.pend = nil
    end
end

S.OFFLINE_PART = 1880   -- Discord cuts messages at 2000 characters

-- Make the string for one partner. Returns a list of parts and an info table, or nil and a reason.
function S.OfflineExport(name, forceFull)
    local partner = S.FindPartner(name)

    if not partner then return nil, "They're not on your Sync list." end

    local lib = LD()

    if not lib then return nil, "LibDeflate didn't load (it ships inside Sterling's Libs folder). Reinstall Sterling Quest Sync." end

    partner.k1 = partner.k1 or newKey()

    local o = offState(partner.name)
    local key = sharedKey(partner)
    local entries, completed = S.SnapshotPieces()
    local level = UnitLevel("player") or 0

    -- changes only when they hold a confirmed copy AND the string can be signed
    local base = (not forceFull and key) and o.base or nil
    local seq, label = nextSeq(), nextLabel()
    local kind, body, changes = "F", nil, 0

    if base then
        local changed, removed, newDone = {}, {}, {}

        for qid, entry in pairs(entries) do if base.entries[qid] ~= entry then changed[#changed + 1] = entry end end
        for qid in pairs(base.entries) do if not entries[qid] then removed[#removed + 1] = qid end end
        for qid in pairs(completed) do if not base.done[qid] then newDone[#newDone + 1] = qid end end

        table.sort(changed); table.sort(removed); orderDone(newDone)

        changes = #changed + #removed + #newDone
        kind = "D"
        body = table.concat({ base.seq, seq, level, table.concat(changed, ";"), table.concat(removed, ","), table.concat(newDone, ","), label }, "^")
    else
        body = S.MakeSnapshot(seq) .. "^" .. label .. "^o"
    end

    o.pend = copyState(seq, entries, completed, level)

    -- if they import it, live sync carries on from this copy; if they don't, the next live sync sorts it out
    syncState()["W:" .. partner.name] = copyState(seq, entries, completed, level)

    logEntry("W:" .. partner.name, { seq = seq, label = label, base = base and base.seq or nil, at = time(), kind = base and "delta" or "full", body = base and body or nil, n = #body, offline = true })

    local ack = (S.snaps[partner.name] and S.snaps[partner.name].seq) or 0
    local carry = (kind == "F" and not partner.kok) and partner.k1 or ""
    local header = table.concat({ "O1", S.VERSION, clean(S.MyName()), clean(partner.name), kind, ack, carry, tostring(S.ADDON_VER) }, "^")
    local sig = key and sign(key, header .. "\n" .. body) or ""

    -- the checksum catches a string that lost or gained characters on the way, signed or not
    local raw = sig .. "\n" .. sign("STQ", header .. "\n" .. body) .. "\n" .. header .. "\n" .. body
    local packed = lib:EncodeForPrint(lib:CompressDeflate(raw, { level = 9 }))

    if type(packed) ~= "string" or packed == "" then return nil, "Couldn't pack the string." end

    local id = ("%04x"):format(math.random(0, 65535))
    local n = math.max(1, math.ceil(#packed / S.OFFLINE_PART))
    local parts = {}

    for i = 1, n do parts[i] = ("STO1:%d/%d:%s:%s"):format(i, n, id, packed:sub((i - 1) * S.OFFLINE_PART + 1, i * S.OFFLINE_PART)) end

    S.sync.offOut = (S.sync.offOut or 0) + 1

    return parts, { kind = kind, signed = key ~= nil, seq = seq, base = base and base.seq or nil, baseAt = base and base.at or nil, label = label, changes = changes, raw = #raw, chars = #packed, to = partner.name }
end

-- Pull the parts out of whatever was pasted (any order, several at once, junk around them).
-- Returns the packed text when one string is complete, else nil plus how many parts are here and needed.
function S.OfflineCollect(text)
    text = tostring(text or "")

    local heads = {}
    local at = 1

    while true do
        local a, b, i, n, id = text:find("STO1:(%d+)/(%d+):(%x+):", at)

        if not a then break end

        heads[#heads + 1] = { a = a, b = b, i = tonumber(i), n = tonumber(n), id = id }
        at = b + 1
    end

    if #heads == 0 then return nil, 0, 0 end

    local sets = {}

    for k, head in ipairs(heads) do
        local stop = heads[k + 1] and (heads[k + 1].a - 1) or #text

        -- the data is one unbroken run of letters, digits and brackets; anything after the first gap is not part of it
        local chunk = text:sub(head.b + 1, stop):match("^[%w%(%)]+") or ""

        if head.n >= 1 and head.n <= 60 and head.i >= 1 and head.i <= head.n then
            local set = sets[head.id] or { n = head.n, parts = {}, got = 0, id = head.id }

            sets[head.id] = set

            if set.n == head.n and not set.parts[head.i] then set.parts[head.i] = chunk; set.got = set.got + 1 end
        end
    end

    local best

    for _, set in pairs(sets) do
        if set.got == set.n then return table.concat(set.parts), set.n, set.n end
        if not best or set.got > best.got then best = set end
    end

    return nil, best and best.got or 0, best and best.n or 0
end

-- Unpack a complete string into its fields. Returns a table, or nil and what is wrong with it.
function S.OfflineRead(packed)
    local lib = LD()

    if not lib then return nil, "LibDeflate didn't load. Reinstall Sterling Quest Sync." end

    local okD, bin = pcall(lib.DecodeForPrint, lib, packed)

    if not okD or not bin then return nil, "That string is damaged (it didn't decode). Copy it again, all of it." end

    local okZ, raw = pcall(lib.DecompressDeflate, lib, bin)

    if not okZ or type(raw) ~= "string" then return nil, "That string is damaged (it didn't unpack). Copy it again, all of it." end

    local sig, sum, header, body = raw:match("^(%x*)\n(%x+)\n([^\n]*)\n(.*)$")

    if not header then return nil, "That isn't a Sterling offline sync string." end
    if sum ~= sign("STQ", header .. "\n" .. body) then return nil, "That string is damaged (part of it is missing or changed). Copy it again, all of it." end

    local f = {}

    for piece in (header .. "^"):gmatch("(.-)%^") do f[#f + 1] = piece end

    if f[1] ~= "O1" then return nil, "That offline string is in a format this version doesn't know. Update Sterling Quest Sync." end

    local d = { sig = sig, header = header, body = body, proto = tonumber(f[2]) or 0, from = f[3] or "", to = f[4] or "", kind = f[5], ack = tonumber(f[6]) or 0,
                carry = (f[7] or ""):match("^%x+$") and f[7]:sub(1, 32) or "", ver = (f[8] or ""):match("^[%d%.]+$") and f[8]:sub(1, 12) or nil }
    if d.kind ~= "F" and d.kind ~= "D" then return nil, "That offline string is damaged (unknown kind)." end

    d.from = d.from:gsub("[|\t]", ""):sub(1, 30)

    if d.kind == "D" then d.base, d.seq = tonumber(body:match("^(%d+)%^")), tonumber(body:match("^%d+%^(%d+)%^")) end

    return d
end

-- Decide what to do with a string before touching anything:
--   "ok"                  signed by this partner: import straight away
--   "confirm", warning    a full copy that isn't signed: ask the player first
--   nil, reason           refuse
function S.OfflineCheck(d)
    if d.proto ~= S.VERSION then
        return nil, "|cffff9b92Can't sync: update needed.|r This string was made by " .. (d.proto < S.VERSION and "an older" or "a newer") .. " Sterling Quest Sync" .. (d.ver and (" (v" .. d.ver .. ")") or "") .. ". " .. (d.proto < S.VERSION and (d.from .. " needs to update.") or "Update yours.")
    end

    if S.IsMe(d.from) then return nil, "That's your own string. Send it to " .. d.to .. ", and paste the one they send you here." end
    if not S.IsMe(d.to) then return nil, "That string was made for " .. d.to .. ", not for this character." end

    local partner = S.FindPartner(d.from)

    if not partner then
        if d.kind == "D" then return nil, d.from .. " isn't on your Sync list. Add them first, then ask for a full copy (their Offline sync window > Full copy)." end
        if S.PartnersFull() then return nil, "Your Sync list is full (" .. S.MAX_PARTNERS .. " partners). Remove someone before importing from " .. d.from .. "." end

        return "confirm", d.from .. " isn't on your Sync list yet. Importing adds them as a partner.\n\nThis string isn't signed, so Sterling can't prove who made it. Only import it if " .. d.from .. " gave it to you directly."
    end

    local key = sharedKey(partner)

    if key and d.sig ~= "" and d.sig == sign(key, d.header .. "\n" .. d.body) then return "ok" end
    if d.kind == "D" then
        if not key then return nil, "Offline sync needs one live sync with " .. S.PartnerLabel(partner.name) .. " first (or a full copy each way). Ask them for a full copy: their Offline sync window > Full copy." end

        return nil, "The signature on this string doesn't match your shared key with " .. S.PartnerLabel(partner.name) .. ". It may be damaged, or one of you reinstalled. Ask them for a full copy."
    end

    if key and d.sig ~= "" then
        return "confirm", "The signature on this string doesn't match your shared key with " .. S.PartnerLabel(partner.name) .. " (one of you may have reinstalled).\n\nOnly import it if they gave it to you directly."
    end

    return "confirm", "This full copy isn't signed" .. (key and "" or " (you and " .. S.PartnerLabel(partner.name) .. " haven't swapped keys yet)") .. ", so Sterling can't prove who made it.\n\nOnly import it if they gave it to you directly. After this, their strings are signed."
end

-- Do the import (after OfflineCheck said "ok", or the player confirmed). Returns true and a line for
-- the window, or nil and what went wrong.
function S.OfflineApply(d, verdict)
    local partner = S.FindPartner(d.from)

    if not partner then partner = S.AddPartner(d.from, true) end
    if not partner then return nil, "Couldn't add " .. d.from .. " to your Sync list." end

    local who = S.PartnerLabel(partner.name)
    local line

    if d.kind == "F" then
        local snap = S.ApplyFull(partner.name, d.body, nil, "offline")

        if not snap then return nil, "Couldn't read the quest log in that string." end

        local nl, nd = 0, 0

        for _ in pairs(snap.log) do nl = nl + 1 end
        for _ in pairs(snap.completed) do nd = nd + 1 end

        line = "Imported " .. who .. "'s full copy: " .. nl .. " quests in log, " .. nd .. " done."
    else
        local res, a1, a2 = S.ApplyDelta(partner.name, d.body)

        if res == "old" then return nil, "You already have this update from " .. who .. ". Nothing to do." end
        if res == "step" then
            return nil, "This string continues from " .. who .. "'s update #" .. tostring(a1) .. ", but you hold " .. (a2 and ("#" .. a2) or "nothing from them") .. ". Ask them for a full copy (their Offline sync window > Full copy)."
        end

        line = "Imported " .. a1 .. (a1 == 1 and " change" or " changes") .. " from " .. who .. "."
    end

    -- keys: a string that passed the signature proves they hold our half; an unsigned one may carry theirs
    if verdict == "ok" then partner.kok = true
    elseif d.carry ~= "" then partner.k2 = d.carry end
    if d.ver then partner.ver = d.ver; S.addonVers = S.addonVers or {}; S.addonVers[partner.name] = d.ver end

    -- their string says which of our updates they hold
    local o = offState(partner.name)

    if o.pend and d.ack == o.pend.seq then
        o.base, o.pend = o.pend, nil

        for _, e in ipairs(journal("W:" .. partner.name)) do if e.seq == d.ack then e.acked = true; e.ackAt = time(); e.by = partner.name end end
    end

    S.sync.offIn = (S.sync.offIn or 0) + 1

    S.SyncEvent("Offline sync from " .. who .. " imported")

    if S.OnPartnerData then S.Safe("partner data", S.OnPartnerData, partner.name) end
    if S.UI_Update then S.UI_Update() end

    return true, line
end

---------------------------------------------------------------------------
-- Sterling Quest Sync (the optional desktop app). It carries full copies between friends who aren't
-- online together. The companion add-on SterlingQuestSync owns two tables; Sterling does the work:
--   SterlingQuestSyncOut    (its SavedVariables) we write at logout and /reload: one full copy per
--                           partner, a copy for our own other PCs, removals, what we applied
--   SterlingQuestSync_Inbox (its Inbox.lua, written by the app) we read at login and /reload
-- Packets are the same text as a full offline string (EncodeForPrint alphabet only), signed with the
-- pair key the app hands us, or our game key with that partner. Without the companion, all of this
-- quietly does nothing. A missing or broken inbox is treated as empty, and nothing here may error.
---------------------------------------------------------------------------
S.app = S.app or { got = {}, problems = {} }
S.APP_LINK = "https://github.com/SterlingAddons/SterlingQuestSync-App"
S.APP_MAX = 65536

-- Is the Companion app installed (its add-on loaded, or its data there)?
function S.AppPresent()
    if type(rawget(_G, "SterlingQuestSyncOut")) == "table" then return true end

    local isl = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")

    return isl and isl("SterlingQuestSync") and true or false
end

-- App versions look like 0.1.9: two or three groups of up to 4 digits. Anything else is ignored.
local function appVerOK(v)
    if type(v) ~= "string" then return nil end
    if v:match("^%d%d?%d?%d?%.%d%d?%d?%d?$") or v:match("^%d%d?%d?%d?%.%d%d?%d?%d?%.%d%d?%d?%d?$") then return v end
end

S.AppVerOK = appVerOK

-- Our own app version: only when the companion add-on is loaded (only the app installs it) and its inbox says.
function S.MyAppVersion()
    if not S.AppPresent() then return nil end

    local ib = rawget(_G, "SterlingQuestSync_Inbox")
    local a = type(ib) == "table" and type(ib.app) == "table" and ib.app or nil

    return a and appVerOK(a.version) or nil
end

local function appDB(k) SterlingQuestDB[k] = type(SterlingQuestDB[k]) == "table" and SterlingQuestDB[k] or {}; return SterlingQuestDB[k] end

-- app pairing codes: exactly this shape, or they're never touched
local CODEC = "[A-HJKMNP-TV-Z2-9]"

S.CODE_PAT = "^" .. CODEC:rep(4) .. "%-" .. CODEC:rep(4) .. "%-" .. CODEC:rep(4) .. "$"

local function codeOK(c) return type(c) == "string" and c:match(S.CODE_PAT) ~= nil end

S.AppCodeOK = codeOK

-- The key the Companion app made for one pairing, when that pairing is active
local function pairKey(guid)
    local pr = guid and appDB("appPairs")[guid]

    if not (pr and pr.status == "active" and pr.my and pr.their) then return nil end

    return pr.my < pr.their and (pr.my .. pr.their) or (pr.their .. pr.my)
end

S.AppPairKey = pairKey

-- A full copy for one partner, packed exactly like a one-part offline string. Returns the packet or nil.
function S.AppPacket(p, body, key)
    local lib = LD(); if not lib then return nil end
    local ack = (S.snaps[p.name] and S.snaps[p.name].seq) or 0
    local header = table.concat({ "O1", S.VERSION, clean(S.MyName()), clean(p.name), "F", ack, "", tostring(S.ADDON_VER) }, "^")
    local sig = key and sign(key, header .. "\n" .. body) or ""
    local raw = sig .. "\n" .. sign("STQ", header .. "\n" .. body) .. "\n" .. header .. "\n" .. body
    local packed = lib:EncodeForPrint(lib:CompressDeflate(raw, { level = 9 }))

    if type(packed) ~= "string" or #packed == 0 or #packed > S.APP_MAX or packed:find("[^%w%(%)]") then return nil end

    return packed
end

-- The copy for our own other PCs: the order quests were finished in (timestamps), and nicknames.
-- Each PC only knows the quests finished on it (Questie's journey is saved per PC), so both lists merge.
function S.AppSelfPacket()
    local lib = LD(); if not lib or not S.Serialize then return nil end
    local done = S.DoneTimes() or {}
    local nick = {}

    for k, v in pairs(SterlingQuestDB.nicknames or {}) do if type(k) == "string" and type(v) == "string" then nick[k] = v end end

    local ser = S.Serialize({ v = 1, done = done, nick = nick })
    local raw = sign("STQ", "S1\n" .. ser) .. "\nS1\n" .. ser
    local packed = lib:EncodeForPrint(lib:CompressDeflate(raw, { level = 9 }))

    if type(packed) ~= "string" or #packed == 0 or #packed > S.APP_MAX or packed:find("[^%w%(%)]") then return nil end

    return packed
end

-- A name cleaned to what the Companion app accepts (letters, spaces, - and '), or nil
local function nameOK(n)
    n = tostring(n or ""):gsub("[%c%d%p]", function(c) return (c == "-" or c == "'") and c or "" end)
    n = n:gsub("^%s+", ""):gsub("%s+$", "")

    if n == "" or #n > 24 then return nil end

    return n
end

-- Favourite partners: up to 5 partner character ids, in order, shared with the Companion app.
-- The newest change wins as a whole list (SterlingQuestDB.favsChange = server time of our last change).
S.MAX_FAVS = 5

-- The favourites list cleaned: valid ids, not you, no repeats, at most 5
local function cleanFavs(list)
    local out, seen, me = {}, {}, S.MyGUID()

    for _, g in ipairs(type(list) == "table" and list or {}) do
        if #out >= S.MAX_FAVS then break end
        if S.ValidGUID(g) and g ~= me and not seen[g] then out[#out + 1] = g; seen[g] = true end
    end

    return out
end

function S.Favs() SterlingQuestDB.favs = cleanFavs(SterlingQuestDB.favs); return SterlingQuestDB.favs end

-- A partner's place in the favourites list, or nil
function S.FavIndex(partner)
    if not (partner and partner.guid) then return nil end

    for i, g in ipairs(S.Favs()) do if g == partner.guid then return i end end
end

function S.IsFav(p) return S.FavIndex(p) ~= nil end

-- Star or unstar a partner. Returns true, or false plus "full" / "noid".
function S.SetFav(partner, on)
    if not partner then return false end
    if not S.ValidGUID(partner.guid) then return false, "noid" end

    local i = S.FavIndex(partner)
    local list = SterlingQuestDB.favs   -- the cleaned list S.FavIndex just stored

    if on and i then return true end
    if not on and not i then return true end
    if on then
        if #list >= S.MAX_FAVS then msg("You can favourite up to " .. S.MAX_FAVS .. " partners."); return false, "full" end

        list[#list + 1] = partner.guid
    else
        table.remove(list, i)
    end

    SterlingQuestDB.favsChange = S.ServerTime()

    if S.UI_Update then S.UI_Update() end

    return true
end

function S.ToggleFav(p) return S.SetFav(p, not S.IsFav(p)) end

-- Partners in display order: favourites first (in favourite order), then the rest as listed.
function S.PartnersSorted()
    local out, used = {}, {}

    for _, g in ipairs(S.Favs()) do
        local partner = S.PartnerByGUID(g)

        if partner and not used[partner] then out[#out + 1] = partner; used[partner] = true end
    end

    for _, partner in ipairs(S.Partners()) do if not used[partner] then out[#out + 1] = partner end end

    return out
end

S.CleanFavs = cleanFavs

-- Write our part of the outbox. Called at logout (which also fires on /reload).
function S.AppOutbox()
    if S.testMode then return end

    local out = rawget(_G, "SterlingQuestSyncOut")

    if type(out) ~= "table" or out.format ~= 1 then return end

    local me = S.MyGUID(); if not me then return end

    if type(out.characters) ~= "table" then out.characters = {} end

    local full = GetUnitName and GetUnitName("player", true)

    if type(full) == "string" then full = full:gsub("%-.*$", "") end   -- no realm suffix

    local name = nameOK(full) or nameOK(S.MyName())

    if not name then return end

    local realm = tostring(GetRealmName and GetRealmName() or ""):gsub("[%c|]", ""):sub(1, 64)
    local entry = { name = name, realm = realm, saved = S.ServerTime(), proto = S.VERSION, partners = {}, applied = {} }

    -- our own nickname: the display name set in Your profile, only when it isn't just our character name
    do
        local profile = nameOK(SterlingQuestDB.profile and SterlingQuestDB.profile.name)
        local sq = function(x) return (tostring(x or ""):lower():gsub("[%s%p]", "")) end

        if profile and sq(profile) ~= sq(name) and sq(profile) ~= sq(name:match("^(%S+)")) then entry.nick = profile end
    end

    -- level, class, race and Sterling version, for the app's "You" row
    do
        local lv = tonumber(UnitLevel("player")); if lv and lv >= 1 and lv <= 100 then entry.level = math.floor(lv) end
        local _, classToken = UnitClass("player"); if type(classToken) == "string" and classToken:match("^%u+$") and #classToken <= 16 then entry.class = classToken end
        local rc = nameOK((UnitRace("player"))); if rc then entry.race = rc end
        local v = tostring(S.ADDON_VER or ""); if appVerOK(v) or v:match("^%d+%.%d+%.%d+%.%d+$") then entry.sterling = v end   -- internal builds have a 4th part
    end

    local selfp = S.AppSelfPacket(); if selfp then entry.self = selfp end

    -- favourites: always written; the time only when they were ever changed in game or taken from the app
    entry.favs = {}

    for i, g in ipairs(S.Favs()) do entry.favs[i] = g end

    local fc = tonumber(SterlingQuestDB.favsChange)

    if fc and fc > 0 then entry.favs_change = math.floor(fc) end

    local body

    for _, partner in ipairs(S.Partners()) do
        if S.ValidGUID(partner.guid) and partner.guid ~= me then
            if not body then body = S.MakeSnapshot(nextSeq()) .. "^" .. nextLabel() .. "^o" end

            local pk = S.AppPacket(partner, body, pairKey(partner.guid) or sharedKey(partner))

            if pk then
                entry.partners[partner.guid] = { packet = pk, change = math.max(0, math.floor(tonumber(partner.change) or 0)) }

                -- shown only in the app's own window: their full character name, plus the nickname you gave them (if any)
                local nm = nameOK(partner.name)

                if nm then entry.partners[partner.guid].name = nm end

                local nk = nameOK(S.Nickname(partner.name))

                if nk then entry.partners[partner.guid].nick = nk end
                if partner.app == false or appVerOK(partner.app) then entry.partners[partner.guid].app = partner.app end   -- left out: not seen since 0.2.40

                -- level, class, race as last heard from them, and the last live sync (server time); each left out when unknown
                local e = entry.partners[partner.guid]
                local level = (S.snaps[partner.name] and tonumber(S.snaps[partner.name].level)) or tonumber(partner.lvl)   -- their quest log copy is the freshest

                if level and level >= 1 and level <= 100 then e.level = math.floor(level) end
                if type(partner.class) == "string" and partner.class:match("^%u+$") and #partner.class <= 16 then e.class = partner.class end
                if type(partner.race) == "string" and partner.race:match("^[%a][%a '%-]*$") and #partner.race <= 24 then e.race = partner.race end   -- exactly as they sent it, or left out

                local snap = tonumber(partner.seen); if snap and snap > 1e9 then e.seen = math.floor(snap) end
            end
        end
    end

    local cutoff = S.ServerTime() - 90 * 86400

    for g, t in pairs(appDB("removedG")) do
        if type(t) ~= "number" or t < cutoff then SterlingQuestDB.removedG[g] = nil
        elseif S.ValidGUID(g) and not S.PartnerByGUID(g) then entry.partners[g] = { removed = true, change = math.floor(t) } end
    end

    for g, n in pairs(appDB("appApplied")) do
        if S.ValidGUID(g) and type(n) == "number" and n >= 0 then entry.applied[g] = math.floor(n) end
    end

    -- pairing codes partners handed us, newest per sender, for our app to redeem (a day at most)
    local codes = {}

    for g, c in pairs(appDB("appCodes")) do
        if type(c) ~= "table" or not codeOK(c.code) or type(c.time) ~= "number" or c.time < S.ServerTime() - 86400 then SterlingQuestDB.appCodes[g] = nil
        elseif S.ValidGUID(g) and g ~= me then codes[g] = { code = c.code, time = math.floor(c.time) } end
    end

    if next(codes) then entry.codes = codes end

    out.characters[me] = entry
end

-- Is version a newer than b? (digits and dots only)
local function verAbove(a, b)
    -- dotted version a newer than b (digits and dots only)
    a, b = tostring(a or ""), tostring(b or "")

    if not a:match("^[%d%.]+$") or not b:match("^[%d%.]+$") then return false end

    local pa, pb = {}, {}

    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0

        if x ~= y then return x > y end
    end

    return false
end

S.VerAbove = verAbove

-- Merges your other PC's finished quests and nicknames from the Companion app
local function applySelf(data)
    local lib = LD(); if not lib or not S.Deserialize then return false end
    local okD, bin = pcall(lib.DecodeForPrint, lib, data); if not okD or not bin then return false end
    local okZ, raw = pcall(lib.DecompressDeflate, lib, bin); if not okZ or type(raw) ~= "string" then return false end
    local sum, tag, ser = raw:match("^(%x+)\n(S1)\n(.*)$")

    if not sum or sum ~= sign("STQ", "S1\n" .. ser) then return false end

    local okS, selfData = pcall(S.Deserialize, ser)

    if not okS or type(selfData) ~= "table" then return false end

    local other = appDB("otherDone")
    local n = 0

    for qid, finishedAt in pairs(type(selfData.done) == "table" and selfData.done or {}) do
        qid, finishedAt = tonumber(qid), tonumber(finishedAt)

        if qid and finishedAt and qid > 0 and finishedAt > 0 and (not other[qid] or finishedAt < other[qid]) then other[qid] = finishedAt; n = n + 1 end
    end

    SterlingQuestDB.nicknames = SterlingQuestDB.nicknames or {}

    for k, v in pairs(type(selfData.nick) == "table" and selfData.nick or {}) do
        if type(k) == "string" and type(v) == "string" and not SterlingQuestDB.nicknames[k] then SterlingQuestDB.nicknames[k] = v:gsub("[|\t]", ""):sub(1, 16) end
    end

    if n > 0 and S.ResetRank then S.ResetRank() end

    return true
end

-- One partner packet from the inbox. Returns a word for the status line.
local function applyPartner(from, data, pr)
    local d = S.OfflineRead(data)

    if not d or d.kind ~= "F" then return "bad" end
    if d.proto ~= S.VERSION then return "proto" end
    if not S.IsMe(d.to) or S.IsMe(d.from) then return "notme" end

    local partner = S.PartnerByGUID(from) or S.FindPartner(d.from)
    local pk = pairKey(from)
    local gk = partner and sharedKey(partner)
    local signedBy = (d.sig ~= "" and pk and d.sig == sign(pk, d.header .. "\n" .. d.body) and "pair")
                                or (d.sig ~= "" and gk and d.sig == sign(gk, d.header .. "\n" .. d.body) and "game") or nil
    if not signedBy then return (d.sig == "" and not pk) and "unsigned" or "resync" end
    if not partner then
        -- paired in the app but not on the list here: add them, unless we removed them after that pairing
        local rem = appDB("removedG")[from]

        if not (pr and pr.status == "active") or (rem and pr.change and rem >= pr.change) then return "removed" end

        partner = S.AddPartner(d.from, true)

        if not partner then return "full" end

        partner.change = pr.change
    end

    if not partner.guid then partner.guid = from end
    if partner.guid ~= from then return "resync" end

    local snap = S.ApplyFull(partner.name, d.body, nil, "offline")

    if not snap then return "bad" end
    if d.ver then partner.ver = d.ver; S.addonVers = S.addonVers or {}; S.addonVers[partner.name] = d.ver end

    return "ok", partner
end

-- Read the inbox. Called once a session, a few seconds after login (and again after a /reload).
function S.AppInbox()
    local st = S.app

    st.present = S.AppPresent()

    if st.present and type(rawget(_G, "SterlingQuestAccountDB")) == "table" then SterlingQuestAccountDB.appSeen = true end

    local ib = rawget(_G, "SterlingQuestSync_Inbox")

    if type(ib) ~= "table" or ib.format ~= 1 then return end

    st.written = tonumber(ib.written) or 0

    local app = type(ib.app) == "table" and ib.app or {}

    st.version = type(app.version) == "string" and app.version:match("^[%d%.]+$") and app.version or nil
    st.latest = type(app.latest) == "string" and app.latest:match("^[%d%.]+$") and app.latest or nil
    st.sterlingLatest = type(app.sterling_latest) == "string" and app.sterling_latest:match("^[%d%.]+$") and app.sterling_latest or nil
    st.appUpdate = st.version and st.latest and verAbove(st.latest, st.version) or false
    st.sterlingUpdate = st.sterlingLatest and S.CompareVer and S.CompareVer(S.ADDON_VER, st.sterlingLatest) < 0 or false

    local me = S.MyGUID()
    local mine = me and type(ib.chars) == "table" and ib.chars[me]

    if type(mine) ~= "table" then return end

    -- pairs first: keys and states
    local pairsT = appDB("appPairs")
    local seen = {}

    for _, pair in ipairs(type(mine.pairs) == "table" and mine.pairs or {}) do
        if type(pair) == "table" and S.ValidGUID(pair.partner) and pair.partner ~= me then
            local okKey = function(k) return type(k) == "string" and k:match("^[%w%-_]+$") and #k >= 8 and #k <= 128 end
            local e = { status = (pair.status == "active") and "active" or "ended", change = tonumber(pair.change) or 0 }

            if e.status == "active" and okKey(pair.my_key) and okKey(pair.partner_key) then e.my, e.their = pair.my_key, pair.partner_key
            elseif e.status == "active" then e.status = "ended" end
            pairsT[pair.partner] = e; seen[pair.partner] = true
        end
    end

    -- favourites changed in the app more recently than in game: take its whole list
    local afc = tonumber(mine.favs_change)

    if afc and type(mine.favs) == "table" and afc > (tonumber(SterlingQuestDB.favsChange) or 0) then
        SterlingQuestDB.favs = cleanFavs(mine.favs); SterlingQuestDB.favsChange = math.floor(afc)
    end

    -- pairing codes to hand to partners; codes we were given are done once that pairing is active
    st.offers = {}

    local now = S.ServerTime()

    for _, offer in ipairs(type(mine.offers) == "table" and mine.offers or {}) do
        if type(offer) == "table" and S.ValidGUID(offer.partner) and offer.partner ~= me and codeOK(offer.code) and tonumber(offer.expires) and tonumber(offer.expires) > now then
            st.offers[offer.partner] = { code = offer.code, expires = tonumber(offer.expires) }
        end
    end

    for g, e in pairs(pairsT) do if e.status == "active" and SterlingQuestDB.appCodes then SterlingQuestDB.appCodes[g] = nil end end

    st.problems = {}

    for g, e in pairs(pairsT) do
        if e.status ~= "active" then st.problems[g] = "resync" end
    end

    -- packets, newest per sender; only those numbered above what we already applied
    local applied = appDB("appApplied")
    local list = {}

    for _, packet in ipairs(type(mine.packets) == "table" and mine.packets or {}) do
        if type(packet) == "table" and S.ValidGUID(packet.from) and tonumber(packet.seq) and type(packet.data) == "string" and #packet.data <= S.APP_MAX and not packet.data:find("[^%w%(%)]") then
            list[#list + 1] = packet
        end
    end

    table.sort(list, function(a, b) return tonumber(a.seq) < tonumber(b.seq) end)

    st.got = {}

    for _, pk in ipairs(list) do
        local seq = math.floor(tonumber(pk.seq))

        if seq > (applied[pk.from] or -1) then
            if pk.kind == "self" and pk.from == me then
                local ok, good = pcall(applySelf, pk.data)

                if ok and good then applied[pk.from] = seq; st.selfAt = tonumber(pk.time) end
            elseif pk.kind == "partner" and pk.from ~= me then
                local pr = pairsT[pk.from]

                if not (pr and pr.status == "ended") then
                    local ok, res, p = pcall(applyPartner, pk.from, pk.data, pr)

                    if ok and res == "ok" then
                        applied[pk.from] = seq; st.problems[pk.from] = nil
                        st.got[#st.got + 1] = p.name
                    elseif ok and (res == "resync") then st.problems[pk.from] = "resync"
                    elseif ok and (res == "removed" or res == "notme" or res == "bad") then applied[pk.from] = seq   -- never retried
                    end
                end
            end
        end
    end

    st.read = time()

    if #st.got > 0 then
        S.SyncEvent("Companion app: got " .. table.concat(st.got, ", "))
        say("sync", 1, "Sterling Quest Sync Companion: got the latest from " .. table.concat(st.got, ", ") .. ".")

        if S.OnPartnerData then for _, n in ipairs(st.got) do S.Safe("partner data", S.OnPartnerData, n) end end
    end

    if not st.told then
        st.told = true

        if st.appUpdate then msg("Sterling Quest Sync Companion update available (v" .. st.latest .. "). Open the Companion app to update.") end
        if st.sterlingUpdate then msg("Sterling update available (v" .. st.sterlingLatest .. ").") end
    end

    pcall(S.AppSendCodes)

    if S.UI_Update then S.UI_Update() end
end

-- Auto-pairing (handoff section 9). The app puts a one-time pairing code for each Sterling partner it
-- isn't paired with yet into the inbox (offers). We hand it to that partner, signed with our game key,
-- while they're online; their Sterling saves it in its outbox (codes) and their app redeems it.
-- Sterling never makes, changes or shows a code.
local function codeSig(key, code, fromG, toG) return sign(key, "PCODE\n" .. code .. "\n" .. fromG .. "\n" .. toG) end

-- Send offered codes to partners who are online now. Each code goes once; resent only when it wasn't
-- acknowledged (every 2 minutes, 5 tries a session) or the app made a new one.
function S.AppSendCodes()
    local offers = S.app and S.app.offers

    if type(offers) ~= "table" then return end

    local me = S.MyGUID(); if not me then return end
    local sent = appDB("codeSent")
    local now = S.ServerTime()

    for g in pairs(sent) do if not offers[g] then sent[g] = nil end end   -- pairing made (or offer withdrawn)
    for g, off in pairs(offers) do
        local partner = S.PartnerByGUID(g)
        local key = partner and sharedKey(partner)

        if partner and partner.on and key and off.expires > now and partner.app ~= false then   -- not to someone who told us they have no app
            local st = sent[g]
            local fresh = not st or st.code ~= off.code
            local retry = st and st.code == off.code and not st.acked and (st.tries or 0) < 5 and time() - (st.at or 0) >= 120

            if (fresh or retry) and S.PartnerStatus(partner.name) then
                send("PCODE\t" .. off.code .. "\t" .. codeSig(key, off.code, me, g), { chan = "WHISPER", target = partner.name, key = "W:" .. partner.name })

                sent[g] = { code = off.code, at = time(), acked = false, tries = (fresh and 1) or ((st.tries or 0) + 1) }
            end
        end
    end
end

-- A code from a partner: only from someone on the list whose character id we know, signed with our key.
function S.AppTakeCode(short, code, sig)
    local partner = S.FindPartner(short)
    local me = S.MyGUID()

    if not (partner and me and S.ValidGUID(partner.guid) and codeOK(code) and type(sig) == "string") then return false end

    local key = sharedKey(partner)

    if not key or sig ~= codeSig(key, code, partner.guid, me) then return false end

    appDB("appCodes")[partner.guid] = { code = code, time = S.ServerTime() }

    send("PCOK\t" .. code, { chan = "WHISPER", target = partner.name, key = "W:" .. partner.name })

    return true
end

-- A partner confirmed they got a pairing code: stop sending it
function S.AppCodeAcked(short, code)
    local partner = S.FindPartner(short)
    local sent = partner and partner.guid and appDB("codeSent")[partner.guid]

    if sent and sent.code == code then sent.acked = true end
end

if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() if S.appRead then pcall(S.AppSendCodes) end end) end

-- "missing key, resync" for this partner, if the app says so
function S.AppProblem(name)
    local partner = S.FindPartner(name)

    if not (partner and partner.guid) then return nil end

    return S.app.problems and S.app.problems[partner.guid]
end

-- The app is installed but its SterlingQuestSync helper add-on isn't running in this session.
-- WoW only finds new add-ons when the game starts, so after the app installs it a /reload isn't enough.
-- Signs the app is there: the game knows the add-on (unticked or not loadable), it ran here before on
-- this account, or there are pairings made in the app.
S.APP_ADDON_MISSING = "The Companion add-on (Sterling Quest Sync Companion) isn't loaded. Exit WoW completely and start it again, then make sure it's ticked in AddOns at character select."

-- Is the Companion app there but its add-on not loaded (unticked, or installed while the game ran)?
function S.AppAddonMissing()
    if S.AppPresent() then return false end

    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")

    if info then
        local ok, name, _, _, _, reason = pcall(info, "SterlingQuestSync")

        if ok and name and reason ~= "MISSING" then return true end
    end

    local acc = rawget(_G, "SterlingQuestAccountDB")

    if type(acc) == "table" and acc.appSeen then return true end

    local ap = SterlingQuestDB and SterlingQuestDB.appPairs

    if type(ap) == "table" and next(ap) ~= nil then return true end

    return false
end

-- One status per partner, worded like the Companion app (0.1.24). Returns key, text, r, g, b.
--   syncing   "Syncing..."                           only while a live in-game sync with them is running
--   current   "Up to date" (green)                   we have their latest progress and it's loaded
--   paired    "Paired. Waiting for their next save"  paired in the app, no progress from them yet
--   pairsoon  "Pairs when you're both next online"   both have the app; Sterling pairs them next time both are in game
--   noapp     "No Companion app" (grey)              they told us they don't have it (live sync still works)
--   unknown   "Not online with you yet"              we don't know about their app yet
-- plus "Sync disabled", "Missing key, resync" and "Not synced yet" (no app on either side we know of).
-- The app's "New copy, /reload to see it" can't happen in game: the app's new progress is only read at login
-- and /reload, and everything there is loaded right then. Only the app can show it.
function S.PartnerSyncState(name)
    local partner = S.FindPartner(name)

    if not partner then return nil end
    if not partner.on then return "off", "Sync disabled", .55, .53, .48 end
    if S.AppProblem(partner.name) then return "key", S.Mark("warn") .. "Missing key, resync", .95, .77, .42 end

    local progress = S.sync and S.sync.prog
    local live = (S.pending and S.pending[partner.name]) or (progress and progress.who == partner.name and progress.t and GetTime() - progress.t < 6 and progress.got < progress.n)

    if live then return "syncing", "Syncing...", .95, .77, .42 end

    local have = S.LastSynced(partner.name)
    local paired = partner.guid and S.AppPairKey and S.AppPairKey(partner.guid)

    if paired then
        if have then return "current", S.Mark("good") .. "Up to date", .49, .89, .64 end

        return "paired", "Paired. Waiting for their next save", .84, .86, .91
    end

    -- app statuses only mean something when you have the app yourself
    if not S.AppPresent() then
        if have then return "current", S.Mark("good") .. "Up to date", .49, .89, .64 end

        return "never", "Not synced yet", .55, .53, .48
    end

    if type(partner.app) == "string" then return "pairsoon", "Pairs when you're both next online", .95, .77, .42 end
    if partner.app == false then return "noapp", "No Companion app", .62, .65, .72 end
    if have then return "current", S.Mark("good") .. "Up to date", .49, .89, .64 end

    return "unknown", "Not online with you yet", .84, .86, .91
end

S.NOAPP_TIP = "You still sync live in game when you're both online. Offline syncing starts once they install the Sterling Quest Sync Companion app."

S.found = {}

-- Invites we sent, kept in saved data for a day: an accept that comes late (the other side was in a
-- fight, away, or reloaded) still works. Codes are random and only count from the person invited.
S.INVITE_TTL = 24 * 3600

-- Invites sent and not yet answered, dropping any older than a day
function S.Invites()
    if not SterlingQuestDB then return {} end

    local t = SterlingQuestDB.invites or {}; SterlingQuestDB.invites = t

    for n, v in pairs(t) do if type(v) ~= "table" or not v.at or time() - v.at > S.INVITE_TTL then t[n] = nil end end

    return t
end

function S.PendingInvite(name) local v = S.Invites()[name]; return v ~= nil end

local hiSent, declined, rate, muted, greeted, loginNoted = {}, {}, {}, {}, {}, {}
local loginAt = 0
local SRC_RANK = { party = 1, guild = 2, friend = 3, other = 4 }

local function clean(v, n) return (tostring(v or ""):gsub("[|\t]", "")):sub(1, n or 16) end

function S.IsBlocked(name) name = shortName(name); return name and SterlingQuestDB.blocked and SterlingQuestDB.blocked[name] and true or false end

-- Hides a player from discovery and invites
function S.Block(name)
    name = shortName(name); if not name then return end
    SterlingQuestDB.blocked = SterlingQuestDB.blocked or {}; SterlingQuestDB.blocked[name] = true
    S.found[name] = nil; S.Invites()[name] = nil

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

    local cap = (S.FindPartner(name) or S.PendingInvite(name)) and 300 or 15

    if r.n > cap then
        muted[name] = true

        msg("Ignoring " .. name .. " for the rest of this session (far too many messages).")

        return true
    end

    return false
end

-- Your version, class and level, as sent in HELLO and HI
local function myInfo()
    local _, classToken = UnitClass("player")

    return table.concat({ tostring(S.ADDON_VER), classToken or "", tostring(UnitLevel("player") or 0) }, "\t")
end

-- Is this person on your friends list and online?
local function friendOnline(name)
    if type(C_FriendList) ~= "table" or not C_FriendList.GetNumFriends then return false end

    for i = 1, (C_FriendList.GetNumFriends() or 0) do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)

        if ok and info and sameName(info.name, name) then return info.connected and true or false end
    end

    return false
end

-- Is this person in your guild?
local function inGuild(name)
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return false end

    for i = 1, (GetNumGuildMembers() or 0) do if sameName((GetGuildRosterInfo(i)), name) then return true end end

    return false
end

-- Where we know someone from: party, guild, friends or other
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

-- Remembers another Sterling user we found, for the Add window
local function noteFound(name, ver, classToken, lvl, src)
    if S.IsBlocked(name) or S.IsMe(name) then return end

    local isNew = S.found[name] == nil
    local f = S.found[name] or {}

    f.ver = clean(ver, 12); f.class = clean(classToken, 16); f.level = tonumber(lvl); f.at = time()

    if not f.src or (SRC_RANK[src] or 9) < (SRC_RANK[f.src] or 9) then f.src = src end

    S.found[name] = f
    S.addonVers = S.addonVers or {}; S.addonVers[name] = f.ver

    local partner = S.FindPartner(name)

    if partner then
        partner.ver = f.ver

        if f.class and f.class:match("^%u+$") then partner.class = f.class end
        if f.level and f.level >= 1 and f.level <= 100 then partner.lvl = f.level end
    end

    heard[name] = GetTime()

    if isNew and f.src == "party" and not partner and S.Opt("partyNote", true) then
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

-- Tells a channel or person that you have Sterling
function S.Hello(chan, target)
    if not S.Opt("discoverable", true) then return end

    send("HELLO\t" .. myInfo(), { chan = chan, target = target })
end

local lastLook = 0

-- Looks for other Sterling users in your guild, group and friends list
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

-- The "X is online" chat line for partners, at most once per 10 minutes each
function S.PartnerLoginNote(name)
    if not S.Opt("loginNote", true) or loginAt == 0 or GetTime() - loginAt < 30 then return end
    if S.ChatLevel("sync") < 1 then return end   -- Quiet chat detail: failures only
    if loginNoted[name] and GetTime() - loginNoted[name] < 600 then return end

    loginNoted[name] = GetTime()

    local v = (S.addonVers and S.addonVers[name]) or (S.FindPartner(name) or {}).ver

    msg((S.PartnerLabel and S.PartnerLabel(name) or name) .. " is online" .. (v and (" (Sterling v" .. v .. ")") or "") .. ".")
end

-- Invites someone to sync: they get a prompt to accept
function S.Invite(name)
    name = shortName(name); if not name or name == "" or S.IsMe(name) then return end

    if S.IsBlocked(name) then SterlingQuestDB.blocked[name] = nil end   -- inviting someone undoes a block

    local code = tostring(math.random(100000, 999999))

    S.Invites()[name] = { code = code, at = time() }

    send("INV\t" .. code, { chan = "WHISPER", target = name })
    msg("Invite sent to " .. name .. ". They get a prompt to accept.")

    if S.UI_Update then S.UI_Update() end
end

-- Accepting an invite: adds them and tells them yes
function S.AcceptInvite(name, code)
    if not S.AddPartner(name, true) then S.DeclineInvite(name, code) return end

    send("INVOK\t" .. code, { chan = "WHISPER", target = name })
    msg("Added " .. name .. ". Syncing now.")
    C_Timer.After(1.5, function() S.SyncWith(name, "full") end)

    if S.UI_Update then S.UI_Update() end
end

-- Saying no to an invite (and staying quiet about them for the session)
function S.DeclineInvite(name, code)
    declined[name] = true

    send("INVNO\t" .. code, { chan = "WHISPER", target = name })
end

-- Handles HELLO / HI / INV / INVOK / INVNO. Returns true when the message was one of these.
function S.OnDiscovery(short, text, chan)
    local kind, rest = text:match("^(%u+)\t?(.*)$")

    if kind == "HELLO" or kind == "HI" then
        local ver, classToken, lvl = rest:match("^([%d%.]+)\t(%u*)\t(%d+)$")

        if not ver then return true end

        noteFound(short, ver, classToken, lvl, srcOf(short, chan))

        if S.FindPartner(short) and kind == "HELLO" and chan ~= "PARTY" and chan ~= "RAID" then
            -- a guild hello goes out every 15 minutes; only the first one after a real absence is news
            local lh = S.LastHeard(short)

            if not lh or lh > 1200 then S.PartnerLoginNote(short) end
        end

        if S.FindPartner(short) then S.MarkHeard(short) end
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
        local inv = S.Invites()[short]

        if not (code and inv and inv.code == code) then dbg("sync", "ignored an invite answer from " .. short .. " (no matching invite)") return true end

        S.Invites()[short] = nil

        if kind == "INVOK" then
            if S.AddPartner(short, true) then
                msg(short .. " accepted. Syncing now.")
                C_Timer.After(1.5, function() S.SyncWith(short, "full") end)
            end
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

-- Says hello to anyone new who joined your group
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

-- The hellos sent once after login: guild, online friends
function S.LoginHello()
    if loginAt ~= 0 then return end

    loginAt = GetTime()

    C_Timer.After(12, function() lastLook = 0; S.DiscoverNow(true) end)

    -- partners already online when we log in aren't "logging in": don't announce them
    C_Timer.After(28, function() for _, partner in ipairs(S.Partners()) do if S.PartnerOnline(partner.name) then loginNoted[partner.name] = GetTime() end end end)

    if C_Timer.NewTicker then C_Timer.NewTicker(900, function() if IsInGuild and IsInGuild() and S.Opt("findGuild", true) then S.Hello("GUILD") end end) end
end

-- A partner's character id (GID message) is only stored once the game itself says that id belongs to
-- the character who sent it (GetPlayerInfoByGUID). Not known yet = kept aside and tried again on
-- their next message; a different name = dropped. So nobody can claim someone else's id.
S.pendingGID = {}

-- Does this character id belong to this name? (nil when the game doesn't know the id yet)
function S.GIDMatches(short, gid)
    if type(GetPlayerInfoByGUID) ~= "function" then return nil end

    local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, gid)

    if not ok or type(name) ~= "string" or name == "" then return nil end   -- not known yet

    return sameName(name, short)
end

-- Keeps a partner's character id once the game confirms it's really theirs
function S.TakeGID(short, gid)
    local partner = S.FindPartner(short)

    if not (partner and S.ValidGUID(gid) and gid ~= S.MyGUID()) then S.pendingGID[short] = nil; return false end

    local m = S.GIDMatches(short, gid)

    if m == nil then S.pendingGID[short] = gid; return false end

    S.pendingGID[short] = nil

    if not m then dbg("sync", "ignored a character id from " .. short .. ": the game says it belongs to someone else"); return false end
    if partner.guid ~= gid then
        -- the same id on another entry (a renamed character) moves here
        for _, otherPartner in ipairs(S.Partners()) do if otherPartner ~= partner and otherPartner.guid == gid then otherPartner.guid = nil end end

        partner.guid = gid
    end

    if SterlingQuestDB.removedG then SterlingQuestDB.removedG[gid] = nil end

    return true
end

-- Every Sterling message from another player comes in here
local function onAddonMessage(prefix, text, chan, sender)
    if prefix ~= S.PREFIX then return end
    if S.testMode then return end   -- screenshot mode: nothing is taken in either

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

    -- blocked people are never heard
    if S.IsBlocked(short) then return end

    local listed = S.FindPartner(short) or (groupSync() and inGroup(short))
    local kind0 = text:match("^(%u+)")
    local discovery = kind0 == "HELLO" or kind0 == "HI" or kind0 == "INV" or kind0 == "INVOK" or kind0 == "INVNO"

    -- the flood guard counts what we actually handle: everything from people on the list, and the
    -- discovery messages from anyone else (the rest from strangers is dropped below without work)
    if (listed or discovery) and S.Flooding(short) then return end

    -- finding Sterling users and invites: handled for anyone, they never touch quest data
    if S.OnDiscovery(short, text, chan) then return end

    -- The other side says we're not on their list: stop waiting and say what to do.
    if text == "NOTP" then
        if S.FindPartner(short) and S.SyncHeard then S.SyncHeard(short, "notp") end

        return
    end

    -- Only people on your Sync list, plus (with group sync on) people in your group right now.
    -- A whisper from anyone else is never taken, whatever the setting.
    if not listed then
        -- not on your Sync list: nothing is taken from them, but say once that they're trying,
        -- and tell their copy (at most once a minute) so it stops sending and explains
        S.knocked = S.knocked or {}

        local asks = text:find("^REQ") or text:find("^SINCE") or text:find("^SNAP") or text:find("^DELT")

        if asks and not S.knocked[short] then
            S.knocked[short] = true

            msg(short .. " is trying to sync with you. To accept, add them in the Sync tab (+ Add).")
        end

        S.notpAt = S.notpAt or {}

        if asks and (not S.notpAt[short] or GetTime() - S.notpAt[short] > 60) then
            S.notpAt[short] = GetTime()

            send("NOTP", { chan = "WHISPER", target = short })
        end

        dbg("sync", "ignored " .. describe(text) .. " from " .. short .. ": not on your Sync list (group sync is off)")

        return
    end

    -- a character id they told us earlier that the game couldn't confirm yet: try again now
    if S.pendingGID and S.pendingGID[short] and S.TakeGID then S.TakeGID(short, S.pendingGID[short]) end

    heard[short] = GetTime()
    S.sync.trace = S.sync.trace or {}

    table.insert(S.sync.trace, 1, date("%H:%M:%S") .. " in  " .. short .. ": " .. hideCode(text):sub(1, 48):gsub("\t", " "))

    if #S.sync.trace > 30 then S.sync.trace[31] = nil end

    S.sync.recv = S.sync.recv + 1; S.sync.bytesIn = S.sync.bytesIn + #text; S.sync.lastIn = time(); S.sync.lastFrom = short

    bump(short, "recv", 1, "lastIn"); bump(short, "bytesIn", #text)

    S.sync.vers = S.sync.vers or {}

    -- Where to answer the sender: the group when grouped, else a whisper
    local function tgtFor()
        local inG = useGroup(short)

        return inG and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = short, key = "W:" .. short }
    end

    do
        local pc, psig = text:match("^PCODE\t(%S+)\t(%x+)$")

        if pc then S.AppTakeCode(short, pc, psig) return end

        local ack = text:match("^PCOK\t(%S+)$")

        if ack then S.AppCodeAcked(short, ack) return end
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

        local partner = S.FindPartner(short); if partner then partner.ver = aver end

        S.UI_Update()

        return
    end

    local khalf = text:match("^KEY\t(%x+)$")

    if khalf then
        -- their half of the offline sync key; only ever taken from a whisper by someone on the Sync list
        if chan == "WHISPER" then
            local partner = S.FindPartner(short)

            if partner then
                partner.k2 = khalf:sub(1, 32); partner.kok = true

                S.SendKey(short)   -- once per session, so two copies can't ping-pong

                if S.UI_Update then S.UI_Update() end
            end
        end

        return
    end

    local clvl, ccls, crace = text:match("^CHAR\t(%d+)\t(%u*)\t([^\t|]*)$")

    if clvl then
        local partner = S.FindPartner(short)

        if partner then
            clvl = tonumber(clvl)

            if clvl and clvl >= 1 and clvl <= 100 then partner.lvl = clvl end
            if ccls ~= "" and #ccls <= 16 then partner.class = ccls end
            if crace ~= "" and #crace <= 24 then partner.race = crace end
        end

        return
    end

    local appv = text:match("^APPV\t(.*)$")

    if appv then
        -- what a partner told us about their Companion app; kept until they tell us otherwise
        local partner = S.FindPartner(short)

        if partner then
            if appv == "" then partner.app = false elseif appVerOK(appv) then partner.app = appv end
        end

        return
    end

    local gid = text:match("^GID\t(%S+)$")

    if gid then S.TakeGID(short, gid); return end

    local face = text:match("^FACE\t([mf])$")

    if face then
        local pr = S.profiles[short]

        if pr then
            pr.female = (face == "f") or nil
            SterlingQuestDB.profiles = SterlingQuestDB.profiles or {}; SterlingQuestDB.profiles[short] = pr

            if S.ViewerRedraw then S.ViewerRedraw() end
            if S.UI_Update then S.UI_Update() end
        end

        return
    end

    local prace, pcolor, pname = text:match("^PROF\t(%w+)\t(%w+)\t(.*)$")

    if prace then
        pname = (pname or ""):gsub("[|\t]", ""):sub(1, 24)   -- no links or textures smuggled into our windows

        local was = S.profiles[short]

        S.profiles[short] = { name = (pname ~= "" and pname or short), race = normRace(prace), color = pcolor:sub(1, 12), female = was and was.female or nil }

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

        do local stA = syncState()[key]; if stA and stA.seq == ackSeq then stA.acked = true end end

        for _, e in ipairs(journal(key)) do
            if e.seq == ackSeq then
                e.acked = true; e.ackAt = time(); e.by = short

                if key ~= "GROUP" then S.NoteConfirmed(short, ackSeq) end
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
            if text:sub(1, 3) == "REQ" or sinceVer then
                local inG = useGroup(short)

                send("VER\t" .. S.VERSION, inG and { chan = IsInRaid() and "RAID" or "PARTY", key = "GROUP" } or { chan = "WHISPER", target = short, key = "W:" .. short })
            end

            S.UI_Update()

            return
        end

        if not sinceSeq and text:sub(1, 3) ~= "REQ" then S.UI_Update() return end

        -- They asked us directly, so they always get an answer: our log, "nothing new", or "sync is off here".
        send("VER\t" .. S.VERSION, tgtFor())

        S.profAt = S.profAt or {}

        if not S.profAt[short] or GetTime() - S.profAt[short] > 1800 then S.profAt[short] = GetTime(); S.SendProfile(tgtFor()) end

        S.SendKey(short)

        local mine = S.FindPartner(short)

        if mine and mine.on == false then send("OFF", tgtFor()); dbg("sync", short .. " asked for our log, but sync with them is switched off here: told them so"); return end

        local before = handed

        if sinceSeq then
            if not replay(tgtFor(), tonumber(sinceSeq)) then send("CUR", tgtFor()); dbg("sync", short .. " asked for changes since #" .. sinceSeq .. ": nothing new, told them they're up to date")
            else dbg("sync", short .. " asked for changes since #" .. sinceSeq .. ": sending " .. (handed - before) .. " messages") end
        else
            local had = syncState()[tgtFor().key]

            if had and had.fullAt and not had.acked and time() - had.fullAt < 20 then
                -- our full copy went out seconds ago and is still on its way (their request crossed with it): one is enough.
                -- Once they've confirmed it, a new request is a deliberate one and gets a fresh copy.
                dbg("sync", short .. " asked for a full copy, but one left " .. (time() - had.fullAt) .. "s ago: not sending it twice")

                return
            end

            local entries, completed = S.SnapshotPieces()

            sendTo(tgtFor(), true, true, entries, completed, UnitLevel("player") or 0)
            dbg("sync", short .. " asked for a full copy: sending " .. (handed - before) .. " messages (queue now " .. queued() .. ")")
        end

        return
    end

    -- data from a sender whose version doesn't match ours is ignored; unknown versions get asked
    local theirProto = S.sync.vers[short]

    if theirProto == nil then dbg("sync", "ignored from " .. short .. ": don't know their version yet, asking"); S.RequestPartner(short); return end
    if theirProto ~= S.VERSION then dbg("sync", "|cffff9b92ignored|r from " .. short .. ": their sync protocol " .. tostring(theirProto) .. ", ours " .. S.VERSION); return end

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
        local snap, first = S.ApplyFull(short, whole, sender)

        if snap then
            S.sync.snapsIn = S.sync.snapsIn + 1; S.sync.lastSnapIn = time(); bump(short, "snapsIn", 1, "lastSnapIn")

            do local partner = S.FindPartner(short); if partner then partner.seen = S.ServerTime() end end   -- last live sync, for the app

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
        local res, a1, a2 = S.ApplyDelta(short, whole)

        if res == "old" then return end                                   -- already applied (replay overlap)
        if res == "step" then
            -- out of step: ask that sender for the whole thing
            dbg("sync", "|cfff3c56bout of step|r: " .. short .. "'s change builds on #" .. tostring(a1) .. ", we have #" .. tostring(a2) .. ". Asking for a resend.")

            S.sync.resyncs = (S.sync.resyncs or 0) + 1; bump(short, "resyncs")

            S.RequestPartner(short)

            return
        end

        send("ACK\t" .. a2, tgtFor()); dbg("sync", "applied and confirming " .. short .. "'s change #" .. tostring(a2))

        do local partner = S.FindPartner(short); if partner then partner.seen = S.ServerTime() end end   -- last live sync, for the app

        if S.OnPartnerData then S.OnPartnerData(short) end

        S.sync.deltasIn = (S.sync.deltasIn or 0) + 1; S.sync.lastSnapIn = time(); bump(short, "deltasIn", 1, "lastSnapIn")

        if S.SyncHeard then S.SyncHeard(short, "delta", a1 .. (a1 == 1 and " change" or " changes")) end

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

        for _, partner in ipairs(SterlingQuestDB.partners or {}) do if text:find(partner.name, 1, true) then return true end end
    end)
end

---------------------------------------------------------------------------
-- Path engine: steps come from a followed session
---------------------------------------------------------------------------
S.legs, S.steps = {}, {}

local lastIndex

-- Numbers every step of every leg, so steps can be found by index
local function indexSteps()
    S.steps = {}

    for _, leg in ipairs(S.legs) do
        for _, step in ipairs(leg.steps) do step.leg = leg; S.steps[#S.steps + 1] = step; step.index = #S.steps end
    end
end

-- Replaces the path with new legs and moves to the first open step
function S.SetLegs(legs)
    S.legs = legs or {}

    indexSteps()
    wipe(SterlingQuestDB.manual)

    lastIndex = nil

    S.Recalc(false)
end

-- A quest's objectives with their text and whether each is finished
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
local function logComplete(qid) local quest = S.log[qid]; return quest and quest.complete end

-- Is this objective finished in your quest log?
local function objectiveDone(qid, text)
    if not (qid and text) then return nil end

    local quest = S.log[qid]

    if not quest then return nil end

    local objs

    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, o = pcall(C_QuestLog.GetQuestObjectives, qid); if ok then objs = o end
    end

    if not objs and GetNumQuestLeaderBoards and quest.index then
        objs = {}

        for i = 1, (GetNumQuestLeaderBoards(quest.index) or 0) do
            local t, _, fin = GetQuestLogLeaderBoard(i, quest.index); objs[i] = { text = t, finished = fin }
        end
    end

    if type(objs) ~= "table" then return nil end

    local want = text:lower():gsub("%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s+", "")

    for _, objective in ipairs(objs) do
        local have = (objective.text or ""):lower():gsub("%s*%d+%s*/%s*%d+%s*$", ""):gsub(":%s*$", "")

        if have ~= "" and (have:find(want, 1, true) or want:find(have, 1, true)) then return objective.finished and true or false end
    end
end

-- Are you standing close to this step's spot?
local function nearby(step)
    if not (step.map and step.x) then return false end

    local map, x, y = S.PlayerPos()

    if map ~= step.map then return false end

    local dx, dy = x - step.x, y - step.y

    return (dx * dx + dy * dy) < 1.0
end

-- Is this step already done (quest turned in, picked up, objective finished, place reached)?
function S.StepSatisfied(step, i)
    local k = step.kind

    if k == "turnin" then return S.IsFlaggedDone(step.qid)
    elseif k == "pickup" then return inLog(step.qid) or S.IsFlaggedDone(step.qid)
    elseif k == "deliver" then return S.IsFlaggedDone(step.qid)
    elseif k == "do" then return logComplete(step.qid) or S.IsFlaggedDone(step.qid)
    elseif k == "objective" then
        local v = objectiveDone(step.qid, step.text)

        if v ~= nil then return v end

        return logComplete(step.qid) or S.IsFlaggedDone(step.qid)
    elseif k == "ding" then return (UnitLevel("player") or 0) >= step.level
    elseif k == "skip" then return not inLog(step.qid)
    elseif k == "flight" or k == "ride" or k == "hearth" then
        -- done once you're at the destination (never just for standing at the flight master or dock)
        local dest = { map = step.dmap or step.map, x = step.dx or step.x, y = step.dy or step.y }

        if step.subzone and ((GetSubZoneText() or "") == step.subzone) then return true end
        if nearby(dest) then return true end
        if k ~= "flight" then local here = S.PlayerPos(); if here and here == dest.map then return true end end

        for j = i + 1, math.min(i + 3, #S.steps) do
            local nextStep = S.steps[j]

            if nextStep.qid and S.StepSatisfied(nextStep, j) then return true end
        end

        return false
    elseif k == "note" or k == "travel" or k == "dungeon" then
        if k == "dungeon" and IsInInstance and IsInInstance() then
            local name = GetInstanceInfo and GetInstanceInfo()

            if name and step.text and name == step.text then return true end
        end

        if step.subzone and ((GetSubZoneText() or "") == step.subzone or (GetZoneText() or "") == step.subzone) then return true end
        if nearby(step) then return true end

        for j = i + 1, math.min(i + 3, #S.steps) do
            local nextStep = S.steps[j]

            if nextStep.qid and S.StepSatisfied(nextStep, j) then return true end
        end

        return false
    end

    return false
end

-- The first step that isn't done yet
function S.CurrentIndex()
    for i, step in ipairs(S.steps) do
        if not SterlingQuestDB.manual[i] and not S.StepSatisfied(step, i) then return i end
    end

    return #S.steps + 1
end

-- Waypoints
local wpUID

-- Removes our TomTom arrow
function S.ClearWaypoint()
    if S.testMode then return end
    if wpUID and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, wpUID) end

    wpUID = nil
end

-- Points the TomTom arrow at a step
function S.SetWaypoint(step)
    if S.testMode then return end   -- screenshot mode: TomTom keeps your real arrow

    S.ClearWaypoint()

    if not (step and step.x and step.y and step.map) then return end

    local title = S.StepLabel(step)

    -- pick up and turn in: the giver first, then (once it's in your log) the turn-in NPC
    if step.kind == "deliver" and step.tmap and inLog(step.qid) then step = { map = step.tmap, x = step.tx, y = step.ty } end

    -- once you're in the air (or for a hearth), point at where you're going instead of where you left from
    if step.dmap and step.dx and ((UnitOnTaxi and UnitOnTaxi("player")) or step.kind == "hearth") then
        step = { map = step.dmap, x = step.dx, y = step.dy }
    end

    if TomTom and TomTom.AddWaypoint then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, step.map, step.x / 100, step.y / 100,
            { title = title, persistent = false, minimap = true, world = true, crazy = true, from = "Sterling Quest Sync" })
        if ok and uid then wpUID = uid; return end
    end

    if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, step.map, step.x / 100, step.y / 100)

        if ok and pt then
            pcall(C_Map.SetUserWaypoint, pt)

            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        end
    end
end

S.KIND_LABEL = { turnin = "Turn in", pickup = "Pick up", deliver = "Pick up and turn in", ["do"] = "Do", objective = "Objective", skip = "Skip",
                 travel = "Travel", flight = "Flight", ride = "Ride", hearth = "Hearth", dungeon = "Dungeon", ding = "Level", note = "Note" }
-- The step's text for chat and the Path card
function S.StepLabel(step)
    if not step then return "all caught up" end

    local k = step.kind

    if k == "ding" then return "Reach level " .. step.level end
    if k == "objective" then return step.text and (step.text .. " (" .. (step.quest or "") .. ")") or ("Objective for " .. (step.quest or "a quest")) end
    if k == "dungeon" then return "Ran " .. (step.text or "a dungeon") end
    if k == "note" then return "Note: " .. (step.text or "") end
    if k == "flight" then return step.from and ("Fly from " .. step.from .. " to " .. (step.text or "")) or ("Fly to " .. (step.text or "")) end
    if k == "ride" then return "Boat or zeppelin" .. (step.from and (" from " .. step.from) or "") .. " to " .. (step.text or "") end
    if k == "hearth" then return ((step.from == "Hearthstone" or not step.from) and "Hearth to " or (step.from .. " to ")) .. (step.text or "") end
    if k == "travel" then return "Travel: " .. (step.text or step.subzone or "") end

    return (S.KIND_LABEL[k] or k) .. " " .. (step.quest or "") .. (step.npc and (" (" .. step.npc .. ")") or "")
end

local lastPhase = false

-- Reads the quest log again and moves the path on when steps got done
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
        local step = S.steps[i]

        if SterlingQuestDB.path then S.Safe("waypoint", S.SetWaypoint, step) end
        if announce and lastIndex and SterlingQuestDB.path then
            if S.Opt("sound", true) and PlaySound then pcall(PlaySound, 3175) end
            if S.Opt("chat", true) then if step then msg("Next: " .. S.StepLabel(step)) else msg("You're caught up. Path complete.") end end
        end

        lastIndex = i
    end

    S.Safe("window", S.UI_Update)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Addons Sterling works with. Everything still runs without them; this says what each one adds.
---------------------------------------------------------------------------
S.WORKS_WITH =
{
    { key = "Questie", name = "Questie", adds = "Catch-up tab, quest names for finished quests, status on quest givers and map pins, the order quests were done in",
        without = "Sync, Compare, recording and following a path all still work.",
        chat = "Questie isn't installed. Sterling still syncs and records, but the Catch-up tab and status on quest givers need Questie." },
    { key = "TomTom", name = "TomTom", adds = "the arrow that points at your next step",
        without = "Sterling uses the game's own map pin instead (the diamond on the map and minimap).",
        chat = "TomTom isn't installed, so the next step is marked with the game's own map pin instead of an arrow." },
}

-- Is another add-on Sterling works with (Questie, TomTom...) installed?
function S.HasAddon(key)
    if key == "Questie" then return type(rawget(_G, "QuestieLoader")) == "table" end
    if key == "TomTom" then return type(rawget(_G, "TomTom")) == "table" end

    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

    if type(fn) == "function" then local ok, v = pcall(fn, key); return ok and v and true or false end

    return false
end

-- One chat line per missing addon, once per account (again only if it was there and then went away).
function S.WorksWithNote()
    local told = SterlingQuestAccountDB and SterlingQuestAccountDB.told

    if type(told) ~= "table" then return end

    for _, w in ipairs(S.WORKS_WITH) do
        if S.HasAddon(w.key) then told[w.key] = nil
        elseif not told[w.key] then told[w.key] = true; msg(w.chat .. " |cff8a93a8(Options > General > Works with)|r") end
    end
end

-- Back to how a fresh install behaves. Partners, quest data and sessions are never touched.
function S.ResetSettings()
    SterlingQuestDB.opts = {}
    SterlingQuestDB.pos = nil
    SterlingQuestDB.sync, SterlingQuestDB.path = true, true
    SterlingQuestDB.hideMinimap, SterlingQuestDB.hideMinimapTrail, SterlingQuestDB.minimapAngle = nil, nil, nil

    if S.ThemeInit then S.ThemeInit() end
    if S.UI_ApplyLook then S.UI_ApplyLook() end
    if SterlingQuestMinimapButton then SterlingQuestMinimapButton:Show() end
    if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end

    msg("Settings are back to their defaults. Your partners, quest data and sessions are untouched.")
end

local frame = CreateFrame("Frame")

for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_CONTROL_GAINED",
    "PLAYER_CONTROL_LOST", "PLAYER_DEAD", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_LOGOUT" }) do
    frame:RegisterEvent(ev)
end

local throttle

frame:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
    if ev == "ADDON_LOADED" then
        if a1 ~= ADDON then return end

        -- 5.30: saved data renamed SterlingDB -> SterlingQuestDB. Carry the old table over once.
        if SterlingQuestDB == nil and type(SterlingDB) == "table" then SterlingQuestDB = SterlingDB end

        SterlingDB = nil
        SterlingQuestDB = SterlingQuestDB or {}
        SterlingQuestDB.manual = SterlingQuestDB.manual or {}
        SterlingQuestDB.sessions = SterlingQuestDB.sessions or {}
        SterlingQuestDB.opts = SterlingQuestDB.opts or {}

        -- account-wide: things you only need to see once whichever character you're on (welcome, tour, hints)
        if type(SterlingQuestAccountDB) ~= "table" then SterlingQuestAccountDB = {} end

        SterlingQuestAccountDB.hints = SterlingQuestAccountDB.hints or {}
        SterlingQuestAccountDB.told = SterlingQuestAccountDB.told or {}

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

        for n, profile in pairs(SterlingQuestDB.profiles or {}) do S.profiles[n] = profile end
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

        -- every partner gets their half of the offline sync key; nobody is dropped for not having one yet
        for _, partner in ipairs(SterlingQuestDB.partners) do partner.k1 = partner.k1 or newKey() end

        S.SelectPartner(nil)

        if S.ThemeInit then S.ThemeInit() end

        S.Safe("recording", S.RecordInit)
        S.Safe("window", S.UI_Init)

        if S.MapInit then S.Safe("map", S.MapInit) end

        return
    end

    if ev == "CHAT_MSG_ADDON" then onAddonMessage(a1, a2, a3, a4) return end
    if ev == "CHAT_MSG_SYSTEM" then if S.SyncSystemMessage then S.SyncSystemMessage(a1) end return end
    if ev == "PLAYER_LOGOUT" then if S.testMode then S.TestModeOff(true) end; S.Safe("saving your progress for the Companion app", S.AppOutbox); S.RecordFlush(); if S.PackFlush then S.Safe("packing", S.PackFlush) end return end
    if S.RecordEvent then S.Safe("recording", S.RecordEvent, ev, a1, a2) end
    if (ev == "PLAYER_CONTROL_LOST" or ev == "PLAYER_CONTROL_GAINED") and SterlingQuestDB.path then
        C_Timer.After(1.5, function() local step = S.steps[S.CurrentIndex()]; if step and step.dmap then S.Safe("waypoint", S.SetWaypoint, step) end end)
    end

    if ev == "PLAYER_ENTERING_WORLD" then
        if not S.appRead then S.appRead = true; C_Timer.After(2, function() S.Safe("reading new progress from the Companion app", S.AppInbox) end) end

        C_Timer.After(3, function()
            if SterlingQuestDB.following then S.FollowSession(S.FindSession(SterlingQuestDB.following), false) end

            -- your name is certain by now (it can be missing while the addon first loads): drop yourself if listed
            for i = #S.Partners(), 1, -1 do
                local partner = S.Partners()[i]

                if S.LooksLikeMe(partner.name) then
                    S.LearnMyName(partner.name)

                    S.snaps[partner.name] = nil; if SterlingQuestDB.snaps then SterlingQuestDB.snaps[partner.name] = nil end; table.remove(S.Partners(), i)

                    msg("Took yourself off the Sync list (" .. partner.name .. ").")
                end
            end

            S.Recalc(false); S.RequestPartner(); S.ScheduleBroadcast()

            if S.CatchupRestore then S.Safe("catch-up", S.CatchupRestore) end
        end)

        C_Timer.After(6, function() S.AutoSyncAll("logged in") end)

        if not S.loggedIn then
            S.loggedIn = true

            C_Timer.After(8, function() S.Safe("works with", S.WorksWithNote) end)
            C_Timer.After(5, function() if S.GuideLogin then S.Safe("welcome", S.GuideLogin) end end)
        end

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

        for _, partner in ipairs(S.Partners()) do
            if partner.on and inGroup(partner.name) then
                now[partner.name] = true

                if not first and not S.inGroupWith[partner.name] then
                    S.AutoSync(partner.name, "joined the group")

                    if S.OnPartnerJoined then S.Safe("group hints", S.OnPartnerJoined, partner.name) end
                end
            end
        end

        S.inGroupWith = now

        if S.UI_ShareRefresh then S.UI_ShareRefresh() end

        return
    end

    if ev == "FRIENDLIST_UPDATE" or ev == "GUILD_ROSTER_UPDATE" then
        for _, partner in ipairs(S.Partners()) do
            if partner.on then
                -- The friends list and guild roster come back empty for a moment now and then. Treating every
                -- blip as "went offline, came back" used to throw away what we knew they hold and send the whole
                -- log again. Now: what they hold is kept (their own request sorts out anything they missed), and
                -- they only count as having come online after three minutes of looking offline.
                -- Only a list that actually shows them offline counts (not finding them at all is "can't tell"),
                -- and never while we've heard from them in the last 10 minutes.
                local online, src = S.PartnerStatus(partner.name)
                local lh = S.LastHeard(partner.name)

                if not online and (src == nil or (lh and lh < 600)) then
                    -- can't tell, or they were talking to us a moment ago: leave things as they are
                elseif online then
                    S.offSince[partner.name] = nil

                    if not pinged[partner.name] then pinged[partner.name] = true; S.RequestPartner(partner.name); S.ScheduleBroadcast(); S.AutoSync(partner.name, "came online"); S.PartnerLoginNote(partner.name) end
                else
                    S.offSince[partner.name] = S.offSince[partner.name] or GetTime()

                    if GetTime() - S.offSince[partner.name] > 180 then pinged[partner.name] = nil end
                end
            end
        end

        return
    end

    -- the Catch-up tab follows you into a new zone (not while a flight path carries you through them)
    if ev == "ZONE_CHANGED_NEW_AREA" and S.UI_ZoneChanged and not (UnitOnTaxi and UnitOnTaxi("player")) then
        C_Timer.After(1, function() S.Safe("catch-up zone", S.UI_ZoneChanged) end)
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

---------------------------------------------------------------------------
-- Screenshot mode (/st testmode, hidden): made-up partners, quests and a "You" row for README
-- screenshots. Display only. The real saved data is swapped out for a throwaway copy, nothing is sent,
-- incoming messages are ignored, the app outbox isn't written. /st testmode again, /reload or logout
-- puts the real data back before the game saves.
---------------------------------------------------------------------------
local function deepCopy(t, seen)
    if type(t) ~= "table" then return t end

    seen = seen or {}

    if seen[t] then return seen[t] end

    local c = {}; seen[t] = c

    for k, v in pairs(t) do c[deepCopy(k, seen)] = deepCopy(v, seen) end

    return c
end

local FAKE_ME = { name = "Kaelith", char = "Kaelith Emberfall", level = 43, race = "Troll", color = "teal" }
local FAKE =
{
    { name = "Brannoc Ashvale", nick = "Bran", level = 44, class = "WARRIOR", race = "Orc", color = "red", ver = "now", online = true, ago = 60, fav = 1,
        log = { { 196, "c", "Raptor Mastery", "Lashtail Raptor: 10/10" }, { 189, "i", "Bloodscalp Ears", "Bloodscalp Ear: 9/15" } },
        done = { 185, 186, 187, 190, 191, 192, 194, 195, 568, 569, 572, 581, 582, 583, 584, 585, 586, 587, 596 } },
    { name = "Mirelle Duskwhisper", level = 42, class = "MAGE", race = "Scourge", color = "purple", ver = "0.2.45", online = true, ago = 240,
        log = { { 191, "i", "Panther Mastery", "Panther: 4/10" } }, done = { 185, 186, 190, 194, 583, 568, 569 } },
    { name = "Tovak Stoneroot", nick = "Tovak", level = 40, class = "SHAMAN", race = "Tauren", color = "green", ver = "now", online = false, ago = 3 * 3600, fav = 2,
        log = { { 185, "i", "Tiger Mastery", "Young Stranglethorn Tiger: 6/10" } }, done = { 190, 191 } },
    { name = "Zil'ana Frostcall", level = 45, class = "PRIEST", race = "Troll", color = "blue", ver = "0.2.40", online = nil, ago = 26 * 3600,
        log = {}, done = { 185, 186, 187, 188, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 572, 581, 582, 583, 584, 585, 586, 587, 596, 629 } },
}

-- Stranglethorn quests (Horde side and shared). Ones the client's Questie doesn't know are skipped.
local STV = { 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 572, 581, 582, 583, 584, 585, 586, 587, 596, 629 }
local FAKE_MYDONE = { 185, 190, 194, 583 }   -- "your" finished quests while it's on, so Catch-up has plenty to show

-- Test mode sessions are drawn on the classic Stranglethorn Vale map, the one real recordings use there
local STV_MAP = 1434

-- Places in Stranglethorn (x, y on that map), taken from real recordings and Questie
local GROMGOL = { 32.5, 29.3 }
local NIMBOYA = { 32.3, 27.9 }
local KINWEELAY = { 32.0, 28.2 }
local KRAZEK = { 27.0, 77.2 }

-- The flight between Grom'gol and Booty Bay, the way the taxi actually flies it
local FLIGHT_TO_BB = { { 31.5, 28.4 }, { 30.7, 30.2 }, { 32.7, 33.3 }, { 34.5, 34.0 }, { 38.8, 40.5 }, { 36.7, 49.6 }, { 33.4, 50.5 }, { 32.3, 52.2 }, { 30.7, 68.0 }, { 28.9, 69.5 }, { 27.6, 74.4 }, { 27.4, 76.9 } }

-- Test mode: one made-up session built like a real recording. The route is a list of stops ({ x, y }, plus
-- ev = events that happen there, fly = flown to, jump = arrived by hearth); the trail walks from stop to stop
-- in short straight stretches with a little sway, the way a thinned real trail looks
local function sess(now, id, name, char, startAgo, mins, lvl0, lvl1, route, imported)
    local start = now - startAgo
    local session = { id = id, name = name, start = start, stop = start + mins * 60, char = char, realm = "", lvl0 = lvl0, lvl1 = lvl1, events = {}, trail = {}, zones = { ["Stranglethorn Vale"] = true }, race = "Troll", color = "teal", display = char:match("^(%S+)"), imported = imported }

    -- time is shared out by distance walked; a flight counts as a short walk, a hearth as none
    local cost, total = {}, 0

    for i = 2, #route do
        local a, b = route[i - 1], route[i]
        local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)

        cost[i] = b.jump and 1 or (b.fly and d * .25 or d)
        total = total + cost[i]
    end

    local perUnit = mins * 60 / math.max(1, total)
    local t = start
    local seed = 0

    local function point(x, y, brk)
        session.trail[#session.trail + 1] = { t = math.floor(t), map = STV_MAP, x = math.floor(x * 10 + .5) / 10, y = math.floor(y * 10 + .5) / 10, brk = brk }
    end

    for i, stop in ipairs(route) do
        if i == 1 then
            point(stop[1], stop[2])
        else
            local a = route[i - 1]
            local dt = cost[i] * perUnit

            if stop.jump then
                t = t + dt

                point(stop[1], stop[2], true)
            else
                -- a point every 2.5 or so, nudged sideways a little so the line doesn't look ruled
                local d = math.sqrt((stop[1] - a[1]) ^ 2 + (stop[2] - a[2]) ^ 2)
                local steps = math.max(1, math.floor(d / 2.5))
                local nx, ny = -(stop[2] - a[2]) / math.max(d, .01), (stop[1] - a[1]) / math.max(d, .01)

                for k = 1, steps do
                    local f = k / steps

                    seed = seed + 1

                    local sway = (k < steps and not stop.fly) and math.sin(seed * 2.3) * .45 or 0

                    t = t + dt / steps

                    point(a[1] + (stop[1] - a[1]) * f + nx * sway, a[2] + (stop[2] - a[2]) * f + ny * sway)
                end
            end
        end

        for j, event in ipairs(stop.ev or {}) do
            local copy = { t = math.floor(t) + (j - 1) * 25, map = STV_MAP, x = stop[1], y = stop[2] }

            for k, v in pairs(event) do copy[k] = v end

            session.events[#session.events + 1] = copy
        end
    end

    session.stop = math.floor(t) + 120   -- a little after the last event

    return session
end

-- A route's stops for a flight from Grom'gol to Booty Bay, ending with what happens on landing
local function flightToBootyBay(landing)
    local stops = {}

    for i, p in ipairs(FLIGHT_TO_BB) do stops[i] = { p[1], p[2], fly = true } end

    stops[#stops].ev = landing

    return stops
end

-- Joins route pieces into one list
local function route(...)
    local out = {}

    for _, piece in ipairs({ ... }) do
        if piece[1] and type(piece[1]) == "table" then
            for _, stop in ipairs(piece) do out[#out + 1] = stop end
        else
            out[#out + 1] = piece
        end
    end

    return out
end

-- Two recorded sessions and one from a partner, built like real ones (events plus a trail), all in Stranglethorn
local function fakeSessions(now)
    local function at(place, ev) return { place[1], place[2], ev = ev } end

    -- Ruins of north Stranglethorn where the tigers and panthers are, and the raptor hills south of Grom'gol
    local tigers = { { 31.2, 24.4 }, { 31.5, 19.4 }, { 32.6, 18.9 }, { 33.4, 17.6 }, { 32.7, 16.4 }, { 33.9, 15.8 }, { 34.8, 16.9 }, { 34.1, 18.2 }, { 35.2, 18.8 }, { 34.4, 19.9 } }
    local panthers = { { 31.2, 24.4 }, { 31.5, 19.4 }, { 30.6, 16.1 }, { 29.4, 14.6 }, { 30.3, 13.2 }, { 29.2, 12.1 }, { 30.4, 11.0 }, { 31.3, 12.4 }, { 30.1, 13.9 }, { 28.9, 13.4 } }
    local raptors = { { 33.6, 31.8 }, { 34.6, 34.4 }, { 33.5, 36.1 }, { 34.7, 37.3 }, { 33.8, 38.7 }, { 35.4, 39.2 }, { 35.9, 37.6 }, { 34.9, 36.0 } }

    local function walk(list, last) local out = {} for i, p in ipairs(list) do out[i] = { p[1], p[2] } end out[#out].ev = last return out end
    local function back(list) local out = {} for i = #list - 1, 1, -1 do out[#out + 1] = { list[i][1], list[i][2] } end return out end

    local mine = route(
        at(NIMBOYA, { { k = "A", q = 186, quest = "Tiger Mastery", npc = "Nimboya" }, { k = "A", q = 191, quest = "Panther Mastery", npc = "Nimboya" }, { k = "A", q = 195, quest = "Raptor Mastery", npc = "Nimboya" } }),
        walk(tigers, { { k = "O", q = 186, quest = "Tiger Mastery", text = "Stranglethorn Tiger: 10/10" } }),
        back(tigers),
        at({ 31.6, 25.6 }, { { k = "L", lvl = 42 } }),
        at(NIMBOYA, { { k = "T", q = 186, quest = "Tiger Mastery", npc = "Nimboya" } }),
        at(KINWEELAY, { { k = "A", q = 584, quest = "Bloodscalp Clan Heads", npc = "Kin'weelay" } }),
        walk(panthers, { { k = "O", q = 191, quest = "Panther Mastery", text = "Panther: 10/10" } }),
        back(panthers),
        at(NIMBOYA, { { k = "T", q = 191, quest = "Panther Mastery", npc = "Nimboya" } }),
        at(GROMGOL),
        flightToBootyBay({ { k = "F", text = "Booty Bay", from = "Grom'gol", fmap = STV_MAP, fx = GROMGOL[1], fy = GROMGOL[2] } }),
        at(KRAZEK, { { k = "L", lvl = 43 } }))

    local errands = route(
        at({ 27.4, 76.9 }),
        at(KRAZEK, { { k = "A", q = 587, quest = "Up to Snuff", npc = "Krazek" } }),
        at({ 26.7, 76.8 }), at({ 28.0, 76.5 }), at({ 27.1, 77.6 }),
        at(KRAZEK, { { k = "T", q = 587, quest = "Up to Snuff", npc = "Krazek" } }),
        { GROMGOL[1], GROMGOL[2] - .4, jump = true, ev = { { k = "H", text = "Grom'gol" } } },
        at(KINWEELAY, { { k = "A", q = 596, quest = "Bloody Bone Necklaces", npc = "Kin'weelay" } }))

    local elder = { { 31.2, 24.4 }, { 31.5, 19.4 }, { 34.2, 18.3 }, { 35.8, 14.8 }, { 37.1, 13.6 }, { 36.3, 15.4 }, { 37.5, 16.2 }, { 38.4, 14.9 }, { 37.2, 14.6 } }

    local brans = route(
        at(NIMBOYA, { { k = "A", q = 187, quest = "Tiger Mastery", npc = "Nimboya" }, { k = "A", q = 192, quest = "Panther Mastery", npc = "Nimboya" }, { k = "A", q = 196, quest = "Raptor Mastery", npc = "Nimboya" } }),
        walk(elder, { { k = "O", q = 187, quest = "Tiger Mastery", text = "Elder Stranglethorn Tiger: 10/10" } }),
        back(elder),
        at(NIMBOYA, { { k = "T", q = 187, quest = "Tiger Mastery", npc = "Nimboya" }, { k = "A", q = 581, quest = "Hunt for Yenniku", npc = "Nimboya" } }),
        walk(raptors),
        back(raptors),
        at(NIMBOYA, { { k = "T", q = 192, quest = "Panther Mastery", npc = "Nimboya" }, { k = "T", q = 196, quest = "Raptor Mastery", npc = "Nimboya" } }))

    return
    {
        sess(now, "test-1", "Grom'gol loop", FAKE_ME.char, 2 * 3600, 95, 41, 43, mine),
        sess(now, "test-2", "Booty Bay errands", FAKE_ME.char, 26 * 3600, 48, 40, 41, errands),
        sess(now, "test-3", "Bran's route", "Brannoc Ashvale", 5 * 3600, 70, 42, 44, brans, true),
    }
end

local real = nil

-- Test mode: a made-up partner's quest log in the same shape as a real one
local function fakeSnap(f, now)
    local entries = {}

    for _, quest in ipairs(f.log) do entries[#entries + 1] = quest[1] .. "." .. quest[2] .. "." .. quest[3] .. "." .. (quest[4] or "") end

    local str = table.concat({ "STR3", f.name, "", f.level, table.concat(entries, ";"), table.concat(f.done, ","), now - f.ago, "=", 1, "", "o" }, "^")
    local snap = S.ParseSnapshot(str)

    snap.source = "live"; snap.at = now - f.ago; snap.name = f.name

    return snap
end

-- Test mode on: swaps every saved table for a copy filled with made-up data
function S.TestModeOn()
    if S.testMode then return end
    if S.IsRecording and S.IsRecording() then msg("Stop the recording first (test mode would lose it).") return end

    local now = time()

    real = { db = SterlingQuestDB, snaps = S.snaps, profiles = S.profiles, addonVers = S.addonVers, sync = S.sync,
             PartnerStatus = S.PartnerStatus, MyName = S.MyName, app = S.app, IsFlaggedDone = S.IsFlaggedDone, ReadCompleted = S.ReadCompleted, ReadLog = S.ReadLog, pending = S.pending, QuestPartnerStatus = S.QuestPartnerStatus,
             legs = S.legs, catchupLabel = S.catchupLabel, catchupWho = S.catchupWho, manual = deepCopy(SterlingQuestDB.manual or {}) }
    local db = deepCopy(SterlingQuestDB)

    db.partners, db.snaps, db.profiles, db.nicknames, db.favs, db.favsChange = {}, {}, {}, {}, {}, nil
    db.sessions, db.trash, db.path, db.manual, db.following, db.catchup, db.recording = {}, {}, nil, {}, nil, nil, nil
    db.appPairs, db.appCodes, db.offline, db.removedG, db.otherDone = {}, {}, {}, {}, {}
    db.profile = { name = FAKE_ME.name, race = FAKE_ME.race, color = FAKE_ME.color }
    db.myFullName = FAKE_ME.char
    SterlingQuestDB = db

    local snaps, profiles, vers = {}, {}, {}
    local favs = {}

    -- Catch-up: Bran has done every Stranglethorn quest Questie knows, plus a few in other zones
    local picks = S.TestQuestPicks and S.TestQuestPicks({ [33] = true, [400] = false, [405] = false, [45] = false, [15] = false,
                                                          [3] = false, [8] = false, [267] = false, [406] = false }, 6, 44) or {}
    for i, f0 in ipairs(FAKE) do
        local fake = f0

        if i == 1 then
            fake = {}

            for k, v in pairs(f0) do fake[k] = v end

            local done, seen = {}, {}

            for _, doneQid in ipairs(f0.done) do done[#done + 1] = doneQid; seen[doneQid] = true end
            for _, list in pairs(picks) do for _, q in ipairs(list) do if not seen[q] then done[#done + 1] = q; seen[q] = true end end end

            fake.done = done
        end

        local guid = ("Player-6800-%08X"):format(0x5E570000 + i)

        db.partners[#db.partners + 1] = { name = fake.name, on = true, show = true, guid = guid, lvl = fake.level, class = fake.class, race = fake.race,
                                          ver = fake.ver == "now" and tostring(S.ADDON_VER) or fake.ver }
        if fake.nick then db.nicknames[fake.name] = fake.nick end
        if fake.fav then favs[fake.fav] = guid end

        snaps[fake.name] = fakeSnap(fake, now)
        profiles[fake.name] = { name = fake.name:match("^(%S+)"), race = fake.race, color = fake.color }
        vers[fake.name] = fake.ver == "now" and tostring(S.ADDON_VER) or fake.ver
    end

    for i = 1, #FAKE do if favs[i] then db.favs[#db.favs + 1] = favs[i] end end

    S.snaps, S.profiles, S.addonVers = snaps, profiles, vers
    S.sync = deepCopy(S.sync or {})
    S.sync.snapsIn, S.sync.snapsOut, S.sync.deltasIn = 3, 2, 7
    S.sync.lastEvent = { text = "Auto sync with Bran: 3 changes", at = now - 120 }   -- a clean "Last" line, not your real one
    S.sync.prog = nil

    -- Made-up objective lines for a partner: your own objective names when the quest is in your log, with
    -- counts worked out from the quest id and the partner, so the hover is steady and varied
    local function fakeObjectives(qid, seed)
        local quest = S.log and S.log[qid]
        local own = quest and S.ObjectiveList and S.ObjectiveList(qid, quest.index) or {}
        local objs = {}

        for i, objective in ipairs(own) do
            local text = tostring(objective.text or "")
            local _, total = text:match("(%d+)%s*/%s*(%d+)")
            local name = text:gsub("%s*%(Complete%)", ""):gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":?%s*%d+%s*/%s*%d+%s*$", "")

            total = tonumber(total) or 1

            if name ~= "" then objs[#objs + 1] = ((seed * 3 + i * 7) % (total + 1)) .. "/" .. total .. " " .. name end
        end

        if #objs == 0 then
            local total = ({ 8, 10, 12, 15 })[seed % 4 + 1]

            objs[1] = ((seed * 3) % total) .. "/" .. total .. " Creatures slain"
        end

        return objs
    end

    -- Quest log and map/mob tooltips: a made-up mix for every quest, the same each time you hover it
    S.QuestPartnerStatus = function(qid)
        local list = {}
        local n = tonumber(qid) or 0

        for i, f in ipairs(FAKE) do
            local h = (n * 7919 + i * 104729 + math.floor(n / 7) * 31) % 100
            local st, extra = "none", nil

            local objs

            if h < 35 then st = "done" elseif h < 50 then st = "ready"
            elseif h < 78 then
                st = "log"
                objs = fakeObjectives(n, h)

                if S.Opt("statusProgress", true) and S.QuestProgress then extra = S.QuestProgress({ objs = objs }) end
            end

            list[#list + 1] = { name = S.PartnerLabel and S.PartnerLabel(f.name) or f.name, state = st, extra = extra, objs = objs }
        end

        return list
    end

    S.pending = {}
    S.app = { got = {}, problems = {} }

    local byName = {}

    for _, f in ipairs(FAKE) do byName[f.name] = f end

    -- Test mode: made-up partners are online or not as the cast says
    S.PartnerStatus = function(name)
        local f = byName[name]

        if not f then return false, nil end
        if f.online == nil then return false, nil end

        return f.online, "friend"
    end

    S.MyName = function() return FAKE_ME.char end

    local mydone = {}

    for _, q in ipairs(FAKE_MYDONE) do mydone[q] = true end

    S.IsFlaggedDone = function(qid) return qid ~= nil and mydone[qid] == true end
    S.ReadCompleted = function() local t = {}; for qid in pairs(mydone) do t[qid] = true end; return t end

    -- titles from your real log stay known (only in the copy), so tooltips on those quests still get status lines
    db.names = db.names or {}

    local okLog, realLog = pcall(real.ReadLog)

    for qid, quest in pairs(okLog and type(realLog) == "table" and realLog or {}) do if quest.title then db.names[qid] = db.names[qid] or quest.title end end

    -- your quest log while it's on: one ready to turn in, one still going
    S.ReadLog = function() return { [186] = { title = "Tiger Mastery", complete = true, index = 1 }, [189] = { title = "Bloodscalp Ears", complete = false, index = 2 } } end
    S.testMode = { level = FAKE_ME.level }

    S.Refresh()

    -- sessions, a followed one on the Path tab and the map, and Catch-up on Bran
    for _, ss in ipairs(fakeSessions(now)) do table.insert(db.sessions, ss) end

    S.catchupWho = "Brannoc Ashvale"

    if S.FollowSession then S.Safe("test mode path", S.FollowSession, db.sessions[3], false) end

    msg("|cfff3c56bTest mode on: nothing is saved or sent.|r /st testmode again or /reload to leave it.")

    if S.UI_TestTag then S.UI_TestTag() end
    if S.UI_Update then S.UI_Update() end
end

-- quiet = at logout (no chat line, no redraw)
function S.TestModeOff(quiet)
    if not S.testMode or not real then S.testMode = nil return end

    SterlingQuestDB = real.db
    S.snaps, S.profiles, S.addonVers, S.sync, S.app = real.snaps, real.profiles, real.addonVers, real.sync, real.app
    S.PartnerStatus, S.MyName = real.PartnerStatus, real.MyName
    S.pending = real.pending or {}
    S.QuestPartnerStatus = real.QuestPartnerStatus
    S.IsFlaggedDone, S.ReadCompleted, S.ReadLog = real.IsFlaggedDone, real.ReadCompleted, real.ReadLog

    local r = real

    S.testMode, real = nil, nil

    -- your real path, check-offs and map session back as they were
    S.Refresh()

    S.catchupLabel, S.catchupWho = r.catchupLabel, r.catchupWho

    S.Safe("test mode off", S.SetLegs, r.legs or {})

    SterlingQuestDB.manual = SterlingQuestDB.manual or {}

    for k, v in pairs(r.manual) do SterlingQuestDB.manual[k] = v end

    if S.MapSetSession then S.Safe("test mode off", S.MapSetSession, S.FindSession and S.FindSession(SterlingQuestDB.following) or nil) end

    S.Recalc(false)

    if quiet then return end

    msg("Test mode off: your real data is back.")

    if S.UI_TestTag then S.UI_TestTag() end
    if S.UI_Update then S.UI_Update() end
end

function S.TestModeToggle() if S.testMode then S.TestModeOff() else S.TestModeOn() end end
function S.MyLevel() return (S.testMode and S.testMode.level) or UnitLevel("player") end

-- The /st, /stq and /sterling commands
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
            if S.AddPartner(rest, true) then
                msg("Added partner " .. rest .. ". Sterling Quest Sync syncs quietly whenever you're both online (add them as a friend so it can tell).")

                if S.PartnerOnline(rest) then S.RequestPartner(rest) end
            end

            S.UI_Update()
        else
            local list = {}

            for _, partner in ipairs(S.Partners()) do list[#list + 1] = partner.name .. (partner.on and "" or " (off)") .. (S.PartnerOnline(partner.name) and " online" or " offline") end

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
        local session, sb = S.FindSession(a), S.FindSession(b)

        if session and sb then local m = S.MergeSessions(session, sb); msg("Merged into \"" .. m.name .. "\"."); S.UI_Update() else msg("Usage: /st merge Name A + Name B  (or numbers from the Sessions list)") end
    elseif cmd == "scale" then
        local v = tonumber(rest)

        if v and v >= 0.5 and v <= 2 then SterlingQuestDB.opts.scale = v; S.UI_ApplyOptions(); msg("Scale " .. v) else msg("Usage: /st scale 0.5 to 2") end
    elseif cmd == "lock" then SterlingQuestDB.opts.lock = not SterlingQuestDB.opts.lock; S.UI_ApplyOptions(); msg("Window " .. (SterlingQuestDB.opts.lock and "locked" or "unlocked"))
    elseif cmd == "options" or cmd == "opt" then S.UI_Options()
    elseif cmd == "help" or cmd == "?" then if S.UI_Help then S.UI_Help() end
    elseif cmd == "tour" then if S.TourStart then S.TourStart() end
    elseif cmd == "welcome" then if S.UI_Welcome then S.UI_Welcome() end
    elseif cmd == "offline" then if rest ~= "" and S.FindPartner(rest) then S.UI_Offline(rest) elseif S.UI_Offline then S.UI_Offline(nil) end
    elseif cmd == "testmode" then S.TestModeToggle()
    elseif cmd == "trail" then
        SterlingQuestDB.hideMinimapTrail = not SterlingQuestDB.hideMinimapTrail; msg("Minimap trail " .. (SterlingQuestDB.hideMinimapTrail and "off" or "on"))
    elseif cmd == "minimap" then
        SterlingQuestDB.hideMinimap = not SterlingQuestDB.hideMinimap

        if SterlingQuestMinimapButton then if SterlingQuestDB.hideMinimap then SterlingQuestMinimapButton:Hide() else SterlingQuestMinimapButton:Show() end end
    else
        msg("Commands: /st | help | tour | rec [name] | stop | sessions | export | import | compare | map | add | partner Name | invite Name | offline Name | sync | path | path clear | done | undo | reset | send [session] | note text | merge A + B | scale | lock | options | trail | minimap")
    end
end
