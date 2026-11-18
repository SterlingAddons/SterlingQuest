-- Sterling: session recording. Start/stop, events with positions, a thinned trail,
-- session storage, encode/decode for sharing, and turning a session into a path to follow.
local _, S = ...
local msg = S.msg

-- Event kinds: A accept, T turn in, X abandon, O objective done, L level, Z arrived somewhere,
-- F flight (text = destination, from = takeoff place, fmap/fx/fy = flight master), D dungeon (text = instance name, dur = seconds),
-- K died, B boat or zeppelin (text = arrival, from/fmap/fx/fy = the dock), H hearth or teleport (text = arrival, from = spell).
local rec        -- active recording, or nil
local objState, seeded = {}, false
local lastPlace, inInst, instName, instStart

local function safe(s, n) return (tostring(s or ""):gsub("[%^:;,|~]", " "):gsub("%s+", " "):sub(1, n or 40)) end

function S.Duration(sess)
    local d = (sess.stop or time()) - (sess.start or time())
    local h, m = math.floor(d / 3600), math.floor((d % 3600) / 60)

    if h > 0 then return ("%dh %02dm"):format(h, m) end

    return ("%dm"):format(m)
end

function S.Clock(t) return (date("%I:%M %p", t):gsub("^0", "")) end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
function S.IsRecording() return rec ~= nil end
function S.Recording() return rec end

local function addEvent(k, fields)
    if not rec then return end

    local e = { t = time(), k = k }

    for key, v in pairs(fields or {}) do e[key] = v end

    if k ~= "L" and not e.map then
        local map, x, y = S.PlayerPos()

        if map then e.map, e.x, e.y = map, math.floor(x * 10 + .5) / 10, math.floor(y * 10 + .5) / 10 end
    end

    rec.events[#rec.events + 1] = e

    if S.UI_Update then S.UI_Update() end

    return e
end

local function addPoint(force)
    if not rec then return end
    if inInst then return end

    -- while dead or a ghost the trail pauses; the next point starts a new line (no streak from
    -- the graveyard back to the corpse, or wherever a res puts you)
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then rec._broke = true; return end

    local map, x, y = S.PlayerPos()

    if not map then return end

    local tr = rec.trail
    local last = tr[#tr]

    if last and last.map == map and not force then
        local dx, dy = x - last.x, y - last.y

        if dx * dx + dy * dy < 0.09 then return end -- hasn't moved ~0.3% of the map
    end

    tr[#tr + 1] = { t = time(), map = map, x = math.floor(x * 10 + .5) / 10, y = math.floor(y * 10 + .5) / 10, brk = rec._broke or nil }
    rec._broke = nil
end

function S.RecordStart(name, auto)
    if rec then if not auto then msg("Already recording.") end return end

    -- an unfinished recording still in the save (say a reload didn't pick it back up): continue it, never overwrite it
    local orphan = SterlingQuestDB.recording

    if orphan and orphan.events and orphan.start then
        rec = orphan
        objState, seeded = {}, false

        msg("Picked your unfinished recording back up (" .. S.Duration(rec) .. " so far). Stop it first if you want a fresh one.")

        if S.UI_Update then S.UI_Update() end

        return
    end

    S.Refresh()

    local look = S.Profile()

    rec = { name = name, start = time(), char = S.MyName(), realm = GetRealmName(), lvl0 = UnitLevel("player"),
            events = {}, trail = {}, zones = {}, race = look.race, color = look.color, female = look.female, display = look.name }
    objState, seeded = {}, false

    pcall(S.RecordTick, "questlog")

    lastPlace = nil

    local map = S.PlayerPos()

    if map then rec.zones[S.MapName(map)] = true end

    addPoint(true)
    S.RecordEvent("ZONE_CHANGED_NEW_AREA")

    SterlingQuestDB.recording = rec
    rec.lastSeen = time()

    if auto then msg("|cffff8080Auto record:|r recording started. Stop it from the Path tab or with /st stop.")
    else msg("Recording. /st stop when you're done.") end
    if S.UI_Update then S.UI_Update() end
end

function S.RecordStop(discard)
    if not rec then msg("Not recording.") return end

    addPoint(true)

    rec.stop = time()
    rec.lvl1 = UnitLevel("player")

    local sess = rec

    rec = nil
    SterlingQuestDB.recording = nil

    if discard then S.Trash(sess); msg("Recording discarded. /st restore brings it back.") if S.UI_Update then S.UI_Update() end return end

    S.Safe("clean", S.CleanSession, sess)

    -- saved straight away, so nothing can lose it; the box afterwards is only for naming it
    S.SaveSession(sess)

    if S.InCombat() then S.pendingSave = sess return end
    if S.UI_SaveDialog then S.UI_SaveDialog(sess) end
end

-- Deleted and discarded sessions go here first (last 5), so a misclick is never final.
function S.Trash(sess)
    SterlingQuestDB.trash = SterlingQuestDB.trash or {}

    table.insert(SterlingQuestDB.trash, 1, sess)

    while #SterlingQuestDB.trash > 5 do table.remove(SterlingQuestDB.trash) end
end

function S.EmptyTrash()
    local n = SterlingQuestDB.trash and #SterlingQuestDB.trash or 0

    SterlingQuestDB.trash = {}

    msg(n > 0 and ("Trash emptied (" .. n .. " session" .. (n == 1 and "" or "s") .. " gone for good).") or "Trash was already empty.")

    if S.UI_Update then S.UI_Update() end
end

function S.Restore()
    local t = SterlingQuestDB.trash and table.remove(SterlingQuestDB.trash, 1)

    if not t then msg("Nothing to restore.") return end

    S.AddSession(t); msg("Restored \"" .. (t.name or "session") .. "\".")

    if S.UI_Update then S.UI_Update() end
end

-- Tidy a finished session: resolve leftover "Quest #id" names, collapse double deaths,
-- and rewrite pick-up-then-abandon into a single "skipped" note at the pick-up spot.
function S.CleanSession(sess)
    if not sess or (S.IsPacked and S.IsPacked(sess)) or not sess.events then return sess end

    local ev = sess.events

    -- names
    local known = {}

    for _, e in ipairs(ev) do if e.q and e.quest and not e.quest:find("^Quest #") then known[e.q] = e.quest; if S.LearnName then S.LearnName(e.q, e.quest) end end end
    for _, e in ipairs(ev) do
        if e.q and (not e.quest or e.quest:find("^Quest #")) then
            local t = known[e.q] or S.QuestName(e.q)

            if t and not t:find("^Quest #") then e.quest = t; known[e.q] = t end
        end

        -- notes written with an unresolved name get the real one once we know it
        if e.k == "N" and e.q and e.text then
            local verb = e.text:match("^(%a+) Quest #%d+$")

            if verb then
                local t = known[e.q] or S.QuestName(e.q)

                if t and not t:find("^Quest #") then e.text = verb .. " " .. t end
            end
        end
    end

    -- abandons: walk forward; an X closes the most recent open A of that quest
    local openA = {}      -- qid -> index of its A event
    local drop = {}       -- indices to remove
    local lastA = {}      -- qid -> index of the last A in the session

    for i, e in ipairs(ev) do if e.k == "A" and e.q then lastA[e.q] = i end end
    for i, e in ipairs(ev) do
        if e.k == "A" and e.q then openA[e.q] = i
        elseif e.k == "T" and e.q then openA[e.q] = nil
        elseif e.k == "X" and e.q then
            local a = openA[e.q]

            drop[i] = true

            if lastA[e.q] and lastA[e.q] > i then
                -- picked up again later: the abandon was a hiccup, erase it and the first pick-up
                if a then drop[a] = true; for j = a + 1, i - 1 do if ev[j].k == "O" and ev[j].q == e.q then drop[j] = true end end end

                openA[e.q] = nil
            elseif a then
                for j = a + 1, i - 1 do if ev[j].k == "O" and ev[j].q == e.q then drop[j] = true end end

                local A = ev[a]
                local name = known[e.q] or A.quest or e.quest or ("Quest #" .. e.q)

                ev[a] = { t = A.t, k = "N", q = e.q, map = A.map, x = A.x, y = A.y, text = "Skipped " .. name }
                openA[e.q] = nil
            else
                -- abandoned something picked up before the recording started: keep a short note
                ev[i] = { t = e.t, k = "N", q = e.q, map = e.map, x = e.x, y = e.y, text = "Abandoned " .. (known[e.q] or e.quest or ("Quest #" .. e.q)) }
                drop[i] = nil

                for j = 1, i - 1 do if ev[j].k == "O" and ev[j].q == e.q then drop[j] = true end end
            end
        end
    end

    -- double deaths
    for i = 2, #ev do if ev[i].k == "K" and ev[i - 1].k == "K" and ev[i].t - ev[i - 1].t < 15 then drop[i] = true end end

    local out = {}

    for i, e in ipairs(ev) do if not drop[i] then out[#out + 1] = e end end

    sess.events = out

    return sess
end

function S.RecordNote(text)
    if not rec then return false end

    addEvent("N", { text = safe(text, 200) })

    return true
end

-- Trail thinning while recording, every ~10 minutes, so long sessions never pile up.
local lastThin = 0

local function maybeThin()
    if not rec or #rec.trail < 400 then return end
    if time() - lastThin < 600 then return end

    lastThin = time()

    local keep = 40 -- leave the newest points raw so the simplifier has the full shape of the current stretch
    local head, tail = {}, {}

    for i = 1, #rec.trail - keep do head[i] = rec.trail[i] end
    for i = #rec.trail - keep + 1, #rec.trail do tail[#tail + 1] = rec.trail[i] end

    local thinned = S.ThinTrail(head)

    for _, p in ipairs(tail) do thinned[#thinned + 1] = p end

    rec.trail = thinned
end

function S.SaveSession(sess, name)
    sess.name = name or sess.name or (date("%a %I:%M %p", sess.start):gsub(" 0", " "))
    sess.trail = S.ThinTrail(sess.trail)

    S.AddSession(sess)
    msg(("Saved \"%s\": %s, %d events, %d trail points."):format(sess.name, S.Duration(sess), #sess.events, #sess.trail))

    if S.UI_Update then S.UI_Update() end
end

-- Last moment we know the recording was live: newest trail point, event, or heartbeat.
local function lastActivity(r)
    local t = r.start or 0
    local tr = r.trail and r.trail[#r.trail]; if tr and tr.t and tr.t > t then t = tr.t end
    local ev = r.events and r.events[#r.events]; if ev and ev.t and ev.t > t then t = ev.t end

    if r.lastSeen and r.lastSeen > t then t = r.lastSeen end

    return t
end

local function agoText(sec)
    sec = math.max(0, sec or 0)

    if sec < 90 then return "just now" end
    if sec < 3600 then return math.floor(sec / 60 + .5) .. " min ago" end
    if sec < 86400 then local h = math.floor(sec / 3600); local m = math.floor((sec % 3600) / 60); return h .. "h " .. m .. "m ago" end

    return math.floor(sec / 86400 + .5) .. " days ago"
end

S.ResumeChoices = { 1800, 3600, 3 * 3600, 12 * 3600, 0 }      -- 0 = always continue

function S.ResumeLabel(v) v = v or 3 * 3600; if v == 0 then return "always" end if v < 3600 then return (v / 60) .. " minutes" end return (v / 3600) .. (v == 3600 and " hour" or " hours") end

-- Keep the recording alive across a /reload, a relog or a game restart, and start one automatically if asked.
function S.RecordInit()
    -- Tidy sessions saved by older versions (safe to run again on clean ones).
    for _, sess in ipairs(SterlingQuestDB.sessions or {}) do S.Safe("clean", S.CleanSession, sess) end

    S.Safe("packing", S.PackInit)

    if SterlingQuestDB.recording then
        local r = SterlingQuestDB.recording
        local idle = time() - lastActivity(r)
        local within = S.Opt("resumeWithin", 3 * 3600)

        if S.Opt("autoResume", true) and (within == 0 or idle <= within) then
            rec = r
            objState, seeded = {}, false

            msg("|cffff8080Recording resumed|r" .. (r.name and (": \"" .. r.name .. "\"") or "") .. " (" .. S.Duration(rec) .. " since it started, last activity " .. agoText(idle) .. ").")
        else
            -- too long ago (or resuming is off): close it out as its own session, ending where it actually stopped
            r.stop = lastActivity(r)
            r.lvl1 = r.lvl1 or UnitLevel("player")
            SterlingQuestDB.recording = nil

            S.Safe("clean", S.CleanSession, r)
            S.SaveSession(r)
            msg("|cffff8080Recording:|r your last recording stopped " .. agoText(idle) .. (S.Opt("autoResume", true) and (", longer than " .. S.ResumeLabel(within) .. ",") or "") .. " so it was saved as its own session.")
        end
    end

    if not rec and S.Opt("autoRecord", false) then
        -- give the world a moment to load so the first point and zone are right
        C_Timer.After(4, function() if not rec then S.RecordStart(nil, true) end end)
    end

    local f = CreateFrame("Frame")
    local acc = 0

    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt

        if acc < 2 then return end

        acc = 0

        if S.pendingSave and not S.InCombat() then local s = S.pendingSave; S.pendingSave = nil; if S.UI_SaveDialog then S.UI_SaveDialog(s) end end
        if not rec then return end

        rec.lastSeen = time()

        addPoint(false)
        maybeThin()
        S.Safe("travel", S.TravelTick)
    end)

    -- hearthstone / teleports / portals: remember the cast so the jump that follows is labelled right
    local sf = CreateFrame("Frame")

    if sf.RegisterUnitEvent then sf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") else sf:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") end

    sf:SetScript("OnEvent", function(_, _, unit, _, spellID)
        if unit ~= "player" or not rec then return end

        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))

        if not name then return end
        if spellID == 8690 or spellID == 556 or name:find("Hearthstone") or name:find("Astral Recall") or name:find("^Teleport") or name:find("^Portal") then
            rec._tele = { name = name:find("Hearthstone") and "Hearthstone" or name, t = time() }
        end
    end)
end

---------------------------------------------------------------------------
-- Travel: flights, boats and zeppelins, hearths and teleports.
-- Works off where you were last standing ("ground"), where you last stood still ("still", i.e. waiting
-- at a dock), and the continent from the game's world coordinates. State lives in rec so a /reload
-- mid-flight or mid-boat is fine.
---------------------------------------------------------------------------
local function worldPos(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end

    local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))

    if not ok or not cont then return nil end

    return cont, v and v.x, v and v.y
end

local function r1(v) return math.floor(v * 10 + .5) / 10 end
local function placeNow() local sub = GetSubZoneText and GetSubZoneText() or ""; return sub ~= "" and sub or (GetZoneText and GetZoneText() or "") end

local function hasResSickness()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(15007) then return true end
    if UnitDebuff then for i = 1, 40 do local n = UnitDebuff("player", i); if not n then break end; if n == "Resurrection Sickness" then return true end end end

    return false
end

function S.TravelTick()
    if not rec or inInst then return end

    -- a death followed by res sickness means they took the spirit healer
    local lastK

    for i = #rec.events, math.max(1, #rec.events - 5), -1 do if rec.events[i].k == "K" then lastK = rec.events[i] break end end

    if lastK and not lastK.text and time() - lastK.t < 900 and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and hasResSickness() then
        lastK.text = "res sickness"
    end

    -- dead or a ghost: releasing, corpse runs, spirit healers, a player's res, soulstones and ankhs all
    -- move you around. None of that is travel, so forget where we were and start fresh once alive.
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then rec._ground, rec._still, rec._deadAt = nil, nil, time(); return end
    if rec._deadAt and time() - rec._deadAt < 8 then rec._ground = nil; return end

    local map, x, y = S.PlayerPos()

    if not map then return end                                  -- out at sea or on a loading screen: wait

    local place = placeNow()
    local cont, wx, wy = worldPos(map, x, y)
    local g = rec._ground
    local taxi = UnitOnTaxi and UnitOnTaxi("player")

    if taxi then
        if not rec._taxi then
            local from = g and (time() - g.t) < 30 and g or { map = map, x = r1(x), y = r1(y), place = place }

            rec._taxi = { from = from.place, map = from.map, x = from.x, y = from.y }
        end

        return
    end

    if rec._taxi then                                           -- landed
        local tx = rec._taxi; rec._taxi = nil

        addEvent("F", { text = safe(place), from = safe(tx.from), fmap = tx.map, fx = tx.x, fy = tx.y })

        lastPlace = place
    elseif g and cont and g.cont and (time() - g.t) < 600 and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        local jump

        if cont ~= g.cont then jump = "far"
        elseif g.wx and wx then
            local d = math.sqrt((wx - g.wx) ^ 2 + (wy - g.wy) ^ 2)

            if d > 250 and d > (time() - g.t) * 40 then jump = "near" end   -- faster than any mount: a teleport
        end

        local recentDeath = false

        for i = #rec.events, math.max(1, #rec.events - 3), -1 do local e = rec.events[i]; if e.k == "K" and time() - e.t < 120 then recentDeath = true end end

        if jump and not recentDeath then
            local tele = rec._tele and (time() - rec._tele.t) < 120 and rec._tele

            if tele then
                addEvent("H", { text = safe(place), from = safe(tele.name) })
            elseif jump == "far" then
                local st = rec._still
                local dock = (st and st.cont == g.cont and (time() - st.t) < 900) and st or g

                addEvent("B", { text = safe(place), from = safe(dock.place), fmap = dock.map, fx = dock.x, fy = dock.y })
            else
                addEvent("H", { text = safe(place), from = "Teleport" })
            end

            rec._tele = nil
            lastPlace = place
        end
    end

    -- remember where we stand, and where we last stood still (a dock, a flight master)
    local here = { map = map, x = r1(x), y = r1(y), place = place, t = time(), cont = cont, wx = wx, wy = wy }

    if g and g.map == map and math.abs(g.x - here.x) < 0.2 and math.abs(g.y - here.y) < 0.2 then rec._still = here end

    rec._ground = here
end

function S.RecordFlush() if rec then addPoint(true); SterlingQuestDB.recording = rec end end

-- Objective tracking, called from Recalc on every quest log update.
local function objectivesFor(qid, logIndex) return S.ObjectiveList(qid, logIndex) end

function S.RecordTick(why)
    if not rec then return end

    local seen = {}

    for qid, q in pairs(S.log) do
        seen[qid] = true

        local objs = objectivesFor(qid, q.index)
        local prev = objState[qid]
        local now = {}

        for idx, o in ipairs(objs) do
            now[idx] = o.finished and true or false

            if seeded and prev and o.finished and not prev[idx] then
                addEvent("O", { q = qid, quest = safe(q.title), text = safe(((o.text or ""):gsub(":%s*$", "")), 80) })
            end
        end

        objState[qid] = now
    end

    for qid in pairs(objState) do if not seen[qid] then objState[qid] = nil end end

    seeded = true
end

function S.RecordEvent(ev, a1, a2)
    if not rec then return end
    if ev == "QUEST_ACCEPTED" then
        local qid = a2 or a1

        if type(qid) ~= "number" then return end

        local title = S.names[qid] or S.QuestName(qid)

        if not title or title:find("^Quest #") then
            S.Refresh()

            title = S.names[qid] or S.QuestName(qid)
        end

        local e = addEvent("A", { q = qid, quest = safe(title or ("Quest " .. qid)), npc = safe(UnitName("npc")) })

        -- Shared quests arrive before the log updates; fix the name up a moment later.
        if e and e.quest:find("^Quest #") then
            for _, d in ipairs({ 1, 3, 8 }) do
                C_Timer.After(d, function() if e.quest:find("^Quest #") then S.Refresh(); local t = S.QuestName(qid); if t and not t:find("^Quest #") then e.quest = safe(t) end end end)
            end
        end
    elseif ev == "QUEST_TURNED_IN" then
        local e = addEvent("T", { q = a1, quest = safe(S.names[a1] or S.QuestName(a1)), npc = safe(UnitName("npc")) })

        if e and e.quest:find("^Quest #") then
            C_Timer.After(2, function() local t = S.QuestName(a1); if t and not t:find("^Quest #") then e.quest = safe(t) end end)
        end
    elseif ev == "QUEST_REMOVED" then
        local qid = a1

        C_Timer.After(1, function() if rec and qid and not S.IsFlaggedDone(qid) then addEvent("X", { q = qid, quest = safe(S.QuestName(qid)) }) end end)
    elseif ev == "PLAYER_LEVEL_UP" then
        addEvent("L", { lvl = a1 })
    elseif ev == "PLAYER_DEAD" then
        local last = rec.events[#rec.events]

        if not (last and last.k == "K" and time() - last.t < 15) then addEvent("K", {}) end
    elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" then
        local isInst = IsInInstance and IsInInstance()

        if isInst and not inInst then
            inInst = true; instName = GetInstanceInfo and GetInstanceInfo() or GetZoneText(); instStart = time()
        elseif not isInst and inInst then
            inInst = false

            addEvent("D", { text = safe(instName), dur = time() - (instStart or time()) })
            addPoint(true)
        end

        if not isInst then
            local map = S.PlayerPos()

            if map then rec.zones[S.MapName(map)] = true end
        end
    end

    if ev == "ZONE_CHANGED" or ev == "ZONE_CHANGED_NEW_AREA" or ev == "ZONE_CHANGED_INDOORS" then
        if inInst or (UnitOnTaxi and UnitOnTaxi("player")) then return end

        local sub, zone = GetSubZoneText and GetSubZoneText() or "", GetZoneText and GetZoneText() or ""
        local place = (sub ~= "" and sub) or zone

        if place ~= "" and place ~= lastPlace then
            lastPlace = place

            addEvent("Z", { text = safe(place) })
        end
    end
end

---------------------------------------------------------------------------
-- Trail thinning: drop points that sit on a straight line (Douglas-Peucker, per map run)
---------------------------------------------------------------------------
local function dp(points, eps, out)
    if #points < 3 then for _, p in ipairs(points) do out[#out + 1] = p end return end

    local a, b = points[1], points[#points]
    local maxd, idx = 0, 0
    local dx, dy = b.x - a.x, b.y - a.y
    local len2 = dx * dx + dy * dy

    for i = 2, #points - 1 do
        local p = points[i]
        local d

        if len2 == 0 then d = math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
        else
            local t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2

            t = math.max(0, math.min(1, t))
            d = math.sqrt((p.x - (a.x + t * dx)) ^ 2 + (p.y - (a.y + t * dy)) ^ 2)
        end

        if d > maxd then maxd, idx = d, i end
    end

    if maxd > eps then
        local left, right = {}, {}

        for i = 1, idx do left[#left + 1] = points[i] end
        for i = idx, #points do right[#right + 1] = points[i] end

        dp(left, eps, out); table.remove(out)
        dp(right, eps, out)
    else
        out[#out + 1] = a; out[#out + 1] = b
    end
end

function S.ThinTrail(trail)
    local out, run = {}, {}

    local function flush() if #run > 0 then dp(run, 0.35, out); run = {} end end

    for _, p in ipairs(trail) do
        if #run > 0 and (run[#run].map ~= p.map or p.brk) then flush() end

        run[#run + 1] = p
    end

    flush()

    return out
end

---------------------------------------------------------------------------
-- Sessions store
---------------------------------------------------------------------------
function S.AddSession(sess)
    sess.id = sess.id or (sess.char .. "-" .. sess.start)

    S.Safe("clean", S.CleanSession, sess)

    for i, s in ipairs(SterlingQuestDB.sessions) do
        if s.id == sess.id then SterlingQuestDB.sessions[i] = sess return end
    end

    table.insert(SterlingQuestDB.sessions, 1, sess)
end

function S.FindSession(key)
    if not key then return nil end

    for _, s in ipairs(SterlingQuestDB.sessions) do if s.id == key then return s end end

    key = tostring(key):lower()

    for _, s in ipairs(SterlingQuestDB.sessions) do if (s.name or ""):lower() == key then return s end end

    local n = tonumber(key)

    if n then return SterlingQuestDB.sessions[n] end
end

function S.DeleteSession(sess)
    for i, s in ipairs(SterlingQuestDB.sessions) do
        if s == sess or s.id == sess.id then
            table.remove(SterlingQuestDB.sessions, i)

            if not S.Opt("noTrash", false) then S.Trash(s) end
            if SterlingQuestDB.following == sess.id then S.StopFollowing() end

            return
        end
    end
end

function S.MergeSessions(a, b)
    if a.start > b.start then a, b = b, a end

    local m = { name = a.name .. " + " .. b.name, char = a.char, realm = a.realm, start = a.start, stop = math.max(a.stop or 0, b.stop or 0),
                lvl0 = a.lvl0, lvl1 = b.lvl1 or a.lvl1, imported = a.imported or b.imported, events = {}, trail = {}, zones = {} }
    for _, e in ipairs(a.events) do m.events[#m.events + 1] = e end
    for _, e in ipairs(b.events) do m.events[#m.events + 1] = e end

    table.sort(m.events, function(x, y) return x.t < y.t end)

    for _, p in ipairs(a.trail) do m.trail[#m.trail + 1] = p end
    for _, p in ipairs(b.trail) do m.trail[#m.trail + 1] = p end

    table.sort(m.trail, function(x, y) return x.t < y.t end)

    for z in pairs(a.zones or {}) do m.zones[z] = true end
    for z in pairs(b.zones or {}) do m.zones[z] = true end

    m.id = m.char .. "-" .. m.start .. "m"

    S.AddSession(m)

    return m
end

-- Compare two sessions by quest IDs: what "theirs" did that "mine" didn't (extra), what mine did that
-- theirs didn't (missed), and what both did (same). Dungeon runs and levels are compared too.
function S.DiffSessions(theirs, mine)
    local function scan(sess)
        local q, dung, order = {}, {}, {}

        for _, e in ipairs(sess.events) do
            if e.q then
                local r = q[e.q]

                if not r then r = { qid = e.q, name = nil }; q[e.q] = r; order[#order + 1] = e.q end
                if e.quest and not e.quest:find("^Quest #") then r.name = e.quest end
                if e.k == "A" then r.picked = r.picked or e; r.status = "picked"
                elseif e.k == "T" then r.done = e; r.status = "done"
                elseif e.k == "N" and e.text and (e.text:find("^Skipped") or e.text:find("^Abandoned")) then r.status = r.status ~= "done" and "skipped" or r.status; r.skip = e
                    if not r.name then r.name = e.text:match("^%a+ (.+)$") end
                end
            elseif e.k == "D" and e.text then
                dung[e.text] = dung[e.text] or { name = e.text, runs = {} }

                table.insert(dung[e.text].runs, e)
            end
        end

        return q, dung, order
    end

    local tq, td, torder = scan(theirs)
    local mq, md, morder = scan(mine)

    local function nameOf(qid) local a, b = tq[qid], mq[qid]; return (a and a.name) or (b and b.name) or ("Quest #" .. qid) end

    local extra, missed, same = {}, {}, {}

    for _, qid in ipairs(torder) do
        local t, m = tq[qid], mq[qid]
        local ms = m and m.status

        if t.status == "done" then
            if ms == "done" then same[#same + 1] = { kind = "turnin", label = nameOf(qid), t = t.done.t, t2 = m.done.t, map = t.done.map, x = t.done.x, y = t.done.y, npc = t.done.npc }
            else extra[#extra + 1] = { kind = "turnin", label = nameOf(qid), sub = ms == "picked" and "you still have it in your log" or ms == "skipped" and "you skipped this one" or nil, t = t.done.t, map = t.done.map, x = t.done.x, y = t.done.y, npc = t.done.npc } end
        elseif t.status == "picked" then
            if ms == "done" then missed[#missed + 1] = { kind = "pickup", label = nameOf(qid), sub = "picked up, not turned in yet", t = t.picked.t, map = t.picked.map, x = t.picked.x, y = t.picked.y }
            elseif not ms then extra[#extra + 1] = { kind = "pickup", label = nameOf(qid), sub = "picked up, still in the log", t = t.picked.t, map = t.picked.map, x = t.picked.x, y = t.picked.y } end
        elseif t.status == "skipped" then
            if ms == "done" then missed[#missed + 1] = { kind = "skip", label = nameOf(qid), sub = "picked up then abandoned", t = t.skip.t, map = t.skip.map, x = t.skip.x, y = t.skip.y } end
        end
    end

    for _, qid in ipairs(morder) do
        local m, t = mq[qid], tq[qid]

        if m.status == "done" and not t then
            missed[#missed + 1] = { kind = "turnin", label = nameOf(qid), sub = "not in their session", t = m.done.t, t2 = m.done.t, map = m.done.map, x = m.done.x, y = m.done.y, mineOnly = true }
        end
    end

    -- dungeons
    for name, d in pairs(td) do
        local mine_ = md[name]

        if mine_ then same[#same + 1] = { kind = "dungeon", label = name, sub = #d.runs .. " run" .. (#d.runs > 1 and "s" or "") .. " vs your " .. #mine_.runs, t = d.runs[1].t, t2 = mine_.runs[1].t, map = d.runs[1].map, x = d.runs[1].x, y = d.runs[1].y }
        else extra[#extra + 1] = { kind = "dungeon", label = name, sub = #d.runs .. " run" .. (#d.runs > 1 and "s" or ""), t = d.runs[1].t, map = d.runs[1].map, x = d.runs[1].x, y = d.runs[1].y } end
    end

    for name, d in pairs(md) do
        if not td[name] then missed[#missed + 1] = { kind = "dungeon", label = name, sub = "you ran it " .. #d.runs .. "x, they didn't", t = d.runs[1].t, t2 = d.runs[1].t, mineOnly = true } end
    end

    local function byT(a, b) return (a.t or 0) < (b.t or 0) end

    table.sort(extra, byT); table.sort(missed, byT); table.sort(same, byT)

    local stats = string.format("%s: %s, lvl %s->%s   |   you: %s, lvl %s->%s",
        theirs.char or "them", S.Duration(theirs), theirs.lvl0 or "?", theirs.lvl1 or "?", S.Duration(mine), mine.lvl0 or "?", mine.lvl1 or "?")
    return { extra = extra, missed = missed, same = same, stats = stats }
end

---------------------------------------------------------------------------
-- Packing old sessions. A recorded session is mostly its trail and event list. After 30 days those
-- two tables are squeezed into one compressed string (LibDeflate) so the saved file stays small and
-- logging in stays quick. Nothing is thrown away: the session unpacks by itself the moment anything
-- reads it (Follow, Map, Export, Send, Merge, Compare), and its name, times, zones and counts stay
-- readable without unpacking. Only your own Sessions list is touched; partner quest data never is.
---------------------------------------------------------------------------
S.PACK_AFTER = 30 * 86400

local function numStr(v)
    if v % 1 == 0 and v > -1e15 and v < 1e15 then return ("%.0f"):format(v) end

    local t = tostring(v)

    if tonumber(t) == v then return t end

    return ("%.17g"):format(v)
end

-- table -> text, exactly (every key, value and type that can be in a session)
local function ser(v, out)
    local t = type(v)

    if t == "table" then
        out[#out + 1] = "{"

        local n = #v

        for i = 1, n do ser(v[i], out) end

        out[#out + 1] = "|"

        for k, x in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) and x ~= nil then ser(k, out); ser(x, out) end
        end

        out[#out + 1] = "}"
    elseif t == "number" then out[#out + 1] = "n" .. numStr(v) .. ";"
    elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    else out[#out + 1] = "Z" end
end

local function de(str, i)
    local c = str:sub(i, i)

    if c == "n" then
        local j = str:find(";", i, true)

        return tonumber(str:sub(i + 1, j - 1)), j + 1
    elseif c == "s" then
        local j = str:find(":", i, true)
        local len = tonumber(str:sub(i + 1, j - 1))

        return str:sub(j + 1, j + len), j + len + 1
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1
    elseif c == "Z" then return nil, i + 1
    elseif c == "{" then
        local t, n = {}, 0

        i = i + 1

        while str:sub(i, i) ~= "|" do
            local v; v, i = de(str, i); n = n + 1; t[n] = v
        end

        i = i + 1

        while str:sub(i, i) ~= "}" do
            local k, v; k, i = de(str, i); v, i = de(str, i)

            if k ~= nil then t[k] = v end
        end

        return t, i + 1
    end

    error("bad packed data at " .. i)
end

function S.Serialize(v) local out = {}; ser(v, out); return table.concat(out) end
function S.Deserialize(str) local v = de(str, 1); return v end

function S.SessionCounts(sess)
    if S.IsPacked(sess) and type(rawget(sess, "sum")) == "table" then return sess.sum end

    local c = { turnin = 0, pickup = 0, skip = 0, dungeon = 0, flight = 0, death = 0, ding = 0, ev = 0, tr = 0 }

    for _, e in ipairs(sess.events or {}) do
        if e.k == "T" then c.turnin = c.turnin + 1 elseif e.k == "A" then c.pickup = c.pickup + 1
        elseif e.k == "D" then c.dungeon = c.dungeon + 1 elseif e.k == "F" then c.flight = c.flight + 1
        elseif e.k == "K" then c.death = c.death + 1 elseif e.k == "L" then c.ding = c.ding + 1
        elseif e.k == "N" and e.text and (e.text:find("^Skipped") or e.text:find("^Abandoned")) then c.skip = c.skip + 1 end
    end

    c.ev, c.tr = #(sess.events or {}), #(sess.trail or {})

    return c
end

-- packed: the two big tables are gone and "pk" holds them
function S.IsPacked(sess) return type(sess) == "table" and rawget(sess, "pk") ~= nil and rawget(sess, "events") == nil end

local opened = setmetatable({}, { __mode = "k" })   -- unpacked this play session: sess -> what it looked like
local lazy = { __index = function(t, k)
    if (k == "events" or k == "trail") and rawget(t, "pk") then S.UnpackSession(t); return rawget(t, k) end
end }

local function shape(sess) return #(rawget(sess, "events") or {}) .. ":" .. #(rawget(sess, "trail") or {}) end
function S.UnpackSession(sess)
    local z = rawget(sess, "pk")

    if not z or rawget(sess, "events") then return true end

    local lib = S.LibDeflate and S.LibDeflate()
    local data

    if lib then
        local ok, raw = pcall(function() return lib:DecompressDeflate(lib:DecodeForPrint(z)) end)

        if ok and type(raw) == "string" then local ok2, t = pcall(S.Deserialize, raw); if ok2 and type(t) == "table" then data = t end end
    end

    if not data then
        -- can't read it right now: show the session empty for this play session and leave the packed copy alone
        rawset(sess, "events", {}); rawset(sess, "trail", {}); opened[sess] = "unread"

        msg("|cffff9b92Couldn't unpack the session \"" .. tostring(sess.name) .. "\".|r Its packed copy is untouched; try again after a /reload.")

        return false
    end

    rawset(sess, "events", data.events or {}); rawset(sess, "trail", data.trail or {})

    opened[sess] = shape(sess)

    return true
end

-- Returns true when the session is packed after the call.
function S.PackSession(sess)
    if type(sess) ~= "table" then return false end
    if S.IsPacked(sess) then return true end

    local ev, tr = rawget(sess, "events"), rawget(sess, "trail")

    if type(ev) ~= "table" or type(tr) ~= "table" then return false end

    local lib = S.LibDeflate and S.LibDeflate()

    if not lib then return false end

    local okS, raw = pcall(S.Serialize, { events = ev, trail = tr })

    if not okS then return false end

    local okZ, z = pcall(function() return lib:EncodeForPrint(lib:CompressDeflate(raw, { level = 3 })) end)

    if not okZ or type(z) ~= "string" or z == "" then return false end

    -- prove it reads back exactly before letting go of the tables
    local okB, back = pcall(function() return lib:DecompressDeflate(lib:DecodeForPrint(z)) end)

    if not okB or back ~= raw then return false end

    local okT, t = pcall(S.Deserialize, back)

    if not okT or type(t) ~= "table" or #(t.events or {}) ~= #ev or #(t.trail or {}) ~= #tr then return false end

    local sum = S.SessionCounts(sess)

    sum.raw, sum.z = #raw, #z

    rawset(sess, "sum", sum); rawset(sess, "pk", z); rawset(sess, "pkv", 1)
    rawset(sess, "events", nil); rawset(sess, "trail", nil)

    opened[sess] = nil

    setmetatable(sess, lazy)

    return true
end

-- How many sessions are packed and how much room that saved.
function S.PackStats()
    local n, before, after, waiting = 0, 0, 0, 0

    for _, sess in ipairs(SterlingQuestDB.sessions or {}) do
        if rawget(sess, "pk") then n = n + 1; local sm = rawget(sess, "sum"); if type(sm) == "table" then before = before + (sm.raw or 0); after = after + (sm.z or 0) end
        elseif S.PackDue(sess) then waiting = waiting + 1 end
    end

    return n, before, after, waiting
end

function S.PackDue(sess)
    if type(sess) ~= "table" or rawget(sess, "pk") or rawget(sess, "pkSkip") or type(rawget(sess, "events")) ~= "table" then return false end
    if SterlingQuestDB.following == sess.id or sess == rec then return false end

    local last = sess.stop or sess.start

    return type(last) == "number" and (time() - last) > S.PACK_AFTER
end

-- One session at a time, a few seconds apart, never in combat: packing a long session takes a moment.
local packing = false

local function packStep()
    packing = false

    if not S.Opt("packOld", true) then return end
    if S.InCombat() then packing = true; C_Timer.After(10, packStep) return end

    for _, sess in ipairs(SterlingQuestDB.sessions or {}) do
        if S.PackDue(sess) then
            S.Safe("packing", S.PackSession, sess)

            if not rawget(sess, "pk") then rawset(sess, "pkSkip", true) end   -- didn't take: don't retry it every few seconds

            packing = true; C_Timer.After(5, packStep)

            return
        end
    end
end

function S.PackSoon(delay)
    if packing then return end

    packing = true; C_Timer.After(delay or 30, packStep)
end

function S.PackInit()
    for _, list in ipairs({ SterlingQuestDB.sessions or {}, SterlingQuestDB.trash or {} }) do
        for _, sess in ipairs(list) do
            if type(sess) == "table" then
                sess.pkSkip = nil

                if rawget(sess, "pk") then
                    if rawget(sess, "events") then rawset(sess, "pk", nil); rawset(sess, "sum", nil)   -- both present: the tables are the truth
                    else setmetatable(sess, lazy) end
                end
            end
        end
    end

    S.PackSoon(30)
end

-- Before the game saves: anything unpacked this play session goes back to its packed form.
function S.PackFlush()
    for _, list in ipairs({ SterlingQuestDB.sessions or {}, SterlingQuestDB.trash or {} }) do
        for _, sess in ipairs(list) do
            if type(sess) == "table" and rawget(sess, "pk") and rawget(sess, "events") then
                local was = opened[sess]

                if was == "unread" or was == shape(sess) then
                    rawset(sess, "events", nil); rawset(sess, "trail", nil)        -- unchanged: the packed copy is still right
                else
                    rawset(sess, "pk", nil); rawset(sess, "sum", nil)              -- changed: pack it again from the tables
                    S.Safe("packing", S.PackSession, sess)
                end
            end
        end
    end
end

-- Unpack everything (Options > Recording, when packing is switched off).
function S.UnpackAll()
    local n = 0

    for _, sess in ipairs(SterlingQuestDB.sessions or {}) do
        if S.IsPacked(sess) and S.UnpackSession(sess) and opened[sess] ~= "unread" then rawset(sess, "pk", nil); rawset(sess, "sum", nil); opened[sess] = nil; n = n + 1 end
    end

    return n
end

function S.SessionSummary(sess)
    local zones = {}

    for z in pairs(sess.zones or {}) do zones[#zones + 1] = z end

    table.sort(zones)

    local cnt = S.SessionCounts(sess)
    local turnins, pickups = cnt.turnin, cnt.pickup
    local lv = sess.lvl0 and sess.lvl1 and sess.lvl1 > sess.lvl0 and (" " .. sess.lvl0 .. "->" .. sess.lvl1) or ""

    return S.Duration(sess) .. " | " .. (#zones > 0 and table.concat(zones, ", ") or "?") .. " | " .. turnins .. " turn-ins" .. lv
end

---------------------------------------------------------------------------
-- Encode / decode. No "|" anywhere (WoW edit boxes mangle it).
-- SES1^name^char^realm^start^stop^lvl0^lvl1^zones^events^trail
---------------------------------------------------------------------------
local function enc(v) return v == nil and "" or tostring(v) end

function S.EncodeSession(sess)
    local ev = {}

    for _, e in ipairs(sess.events) do
        ev[#ev + 1] = table.concat({ e.t - sess.start, e.k, enc(e.q), enc(e.map), enc(e.x), enc(e.y), safe(e.quest), safe(e.npc), safe(e.text, 200), enc(e.lvl or e.dur), safe(e.from),
                                     enc(e.fmap), enc(e.fx), enc(e.fy) }, ":")
    end

    local tr, lastMap, lastT = {}, nil, sess.start

    for _, p in ipairs(sess.trail) do
        if p.map ~= lastMap then tr[#tr + 1] = "m" .. p.map; lastMap = p.map end
        if p.brk then tr[#tr + 1] = "b" end

        tr[#tr + 1] = (p.t - lastT) .. "," .. p.x .. "," .. p.y
        lastT = p.t
    end

    local zones = {}

    for z in pairs(sess.zones or {}) do zones[#zones + 1] = safe(z) end

    return table.concat({ "SES1", safe(sess.name), safe(sess.char), safe(sess.realm), sess.start, sess.stop or time(),
                          enc(sess.lvl0), enc(sess.lvl1), table.concat(zones, ","), table.concat(ev, ";"), table.concat(tr, ";"),
                          sess.race or "", sess.color or "", safe(sess.display or ""), safe(sess.note or "", 200) }, "^")
end

function S.DecodeSession(str)
    str = str:gsub("[\r\n]", "")

    local f = {}

    for piece in (str .. "^"):gmatch("(.-)%^") do f[#f + 1] = piece end

    if f[1] ~= "SES1" then return nil, "not a session string" end

    local sess = { name = f[2], char = f[3], realm = f[4], start = tonumber(f[5]), stop = tonumber(f[6]),
                   lvl0 = tonumber(f[7]), lvl1 = tonumber(f[8]), zones = {}, events = {}, trail = {} }
    if not sess.start then return nil, "bad start time" end
    if f[12] and f[12] ~= "" then sess.race = f[12] end
    if f[13] and f[13] ~= "" then sess.color = f[13] end
    if f[14] and f[14] ~= "" then sess.display = f[14] end
    if f[15] and f[15] ~= "" then sess.note = f[15] end

    for z in (f[9] or ""):gmatch("[^,]+") do sess.zones[z] = true end
    for item in (f[10] or ""):gmatch("[^;]+") do
        local p = {}

        for v in (item .. ":"):gmatch("(.-):") do p[#p + 1] = v end

        local dt, k = tonumber(p[1]), p[2]

        if dt and k then
            local e = { t = sess.start + dt, k = k, q = tonumber(p[3]), map = tonumber(p[4]), x = tonumber(p[5]), y = tonumber(p[6]) }

            if p[7] ~= "" then e.quest = p[7] end
            if p[8] ~= "" then e.npc = p[8] end
            if p[9] ~= "" then e.text = p[9] end
            if k == "L" then e.lvl = tonumber(p[10]) elseif k == "D" then e.dur = tonumber(p[10]) end
            if p[11] and p[11] ~= "" then e.from = p[11] end
            if p[12] and p[12] ~= "" then e.fmap, e.fx, e.fy = tonumber(p[12]), tonumber(p[13]), tonumber(p[14]) end

            sess.events[#sess.events + 1] = e
        end
    end

    local map, t = nil, sess.start

    for item in (f[11] or ""):gmatch("[^;]+") do
        if item:sub(1, 1) == "m" then map = tonumber(item:sub(2))
        elseif item == "b" then sess._nextBrk = true
        else
            local dt, x, y = item:match("^(%-?%d+),(%-?[%d%.]+),(%-?[%d%.]+)$")

            if dt and map then t = t + tonumber(dt); sess.trail[#sess.trail + 1] = { t = t, map = map, x = tonumber(x), y = tonumber(y), brk = sess._nextBrk }; sess._nextBrk = nil end
        end
    end

    sess.id = sess.char .. "-" .. sess.start

    return sess
end

---------------------------------------------------------------------------
-- Session -> path legs (the step list the follower sees)
---------------------------------------------------------------------------
function S.SessionToLegs(sess)
    S.Refresh()

    local myLevel = UnitLevel("player") or 0
    local abandoned = {}

    for _, e in ipairs(sess.events) do if e.k == "X" then abandoned[e.q] = true end end

    local legs, leg = {}, nil

    local function newLeg(title, t)
        if leg and #leg.steps == 0 then legs[#legs] = nil end

        leg = { n = #legs + 1, title = title, sub = sess.char .. "'s session, " .. S.Clock(t), time = S.Clock(t), steps = {} }
        legs[#legs + 1] = leg
    end

    newLeg(sess.zones and next(sess.zones) and S.MapName(sess.events[1] and sess.events[1].map) or "Start", sess.start)

    local lastMap

    for _, e in ipairs(sess.events) do
        local st

        if e.k == "A" and not abandoned[e.q] then st = { kind = "pickup", qid = e.q, quest = e.quest, npc = e.npc }
        elseif e.k == "T" then st = { kind = "turnin", qid = e.q, quest = e.quest, npc = e.npc }
        elseif e.k == "O" and not abandoned[e.q] then st = { kind = "objective", qid = e.q, quest = e.quest, text = (e.text and e.text:find("%S")) and e.text or nil }
        elseif e.k == "L" then if e.lvl and e.lvl > myLevel then st = { kind = "ding", level = e.lvl, quest = "Level " .. e.lvl } end
        elseif e.k == "Z" then
            newLeg(e.text, e.t)

            st = { kind = "travel", text = e.text, subzone = e.text }
        elseif e.k == "F" then st = { kind = "flight", text = e.text, subzone = e.text, from = e.from, fmap = e.fmap, fx = e.fx, fy = e.fy }; newLeg(e.text, e.t)
        elseif e.k == "B" then st = { kind = "ride", text = e.text, subzone = e.text, from = e.from, fmap = e.fmap, fx = e.fx, fy = e.fy }; newLeg(e.text, e.t)
        elseif e.k == "H" then st = { kind = "hearth", text = e.text, subzone = e.text, from = e.from }; newLeg(e.text, e.t)
        elseif e.k == "D" then st = { kind = "dungeon", text = e.text, dur = e.dur }
        elseif e.k == "N" then st = { kind = "note", text = e.text }
        end

        if st then
            st.t = e.t

            if e.map and e.x then st.map, st.x, st.y = e.map, e.x, e.y end

            -- travel steps keep the arrival as the destination and point the arrow at where to catch it
            if st.kind == "flight" or st.kind == "ride" or st.kind == "hearth" then
                st.dmap, st.dx, st.dy = st.map, st.x, st.y

                if st.fmap and st.fx then st.map, st.x, st.y = st.fmap, st.fx, st.fy end
            end

            if st.kind ~= "travel" and e.map and e.map ~= lastMap and lastMap then
                -- zone changed without a named arrival: still start a new leg
                newLeg(S.MapName(e.map), e.t)
            end

            if e.map then lastMap = e.map end

            -- Skip quest steps you've already done.
            local skip = false

            if st.qid then
                if st.kind == "turnin" and S.IsFlaggedDone(st.qid) then skip = true end
                if st.kind == "pickup" and (S.log[st.qid] or S.IsFlaggedDone(st.qid)) then skip = true end
                if st.kind == "objective" and S.IsFlaggedDone(st.qid) then skip = true end
            end

            if not skip then leg.steps[#leg.steps + 1] = st end
        end
    end

    if leg and #leg.steps == 0 then legs[#legs] = nil end

    -- Legs that only say "arrived somewhere" are noise. Flights, boats, zeppelins and hearths are real
    -- instructions (that's how they got there), so they always stay.
    for _, l in ipairs(legs) do
        local real = false

        for _, s in ipairs(l.steps) do if s.kind ~= "travel" then real = true break end end

        if not real then l.steps = {} end
    end

    local cleaned = {}

    for _, l in ipairs(legs) do if #l.steps > 0 then l.n = #cleaned + 1; cleaned[#cleaned + 1] = l end end

    return cleaned
end

function S.FollowSession(sess, announce)
    if not sess then return end

    SterlingQuestDB.following = sess.id

    if S.CatchupClear then S.CatchupClear() end

    local legs = S.SessionToLegs(sess)

    S.SetLegs(legs)

    if S.MapSetSession then S.MapSetSession(sess) end
    if announce then msg(("Following \"%s\": %d steps left."):format(sess.name, #S.steps)) end
end

function S.StopFollowing()
    SterlingQuestDB.following = nil

    if S.CatchupClear then S.CatchupClear() end

    S.SetLegs({})
    S.ClearWaypoint()

    if S.MapSetSession then S.MapSetSession(nil) end
end

-- Distance from the player to the nearest point of the followed trail, in map % units (nil if other map).
function S.TrailDistance()
    local sess = S.FindSession(SterlingQuestDB.following)

    if not sess then return nil end

    local map, x, y = S.PlayerPos()

    if not map then return nil end

    local best

    for _, p in ipairs(sess.trail) do
        if p.map == map then
            local d = (p.x - x) ^ 2 + (p.y - y) ^ 2

            if not best or d < best then best = d end
        end
    end

    return best and math.sqrt(best) or nil
end
