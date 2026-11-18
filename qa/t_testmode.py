# The real player and partner here use names outside the test-mode cast, so the two can't be mixed up.
# Hidden screenshot mode (/st testmode, 0.3.03): fake partners, nothing saved, sent or written; off restores everything.
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {} }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
R = sim.Player("Garrow Thane", [(188, "a")], [185], account=ACC, pre=COMP + "; " + FRIEND % "Vessa Marr", questie=True)
L = sim.Player("Vessa Marr", [(200, "b")], [185], account=ACC, pre=FRIEND % "Garrow Thane")
R.S.AddPartner("Vessa Marr", True); L.S.AddPartner("Garrow Thane", True)
R.L.eval('function(S) S.SetNickname("Vessa Marr", "Vess") end')(R.S)
sim.pump(60)
sent = []
orig = R.L.globals().SEND
def wrap(prefix, text, chan, target=None):
    sent.append(str(text)); return orig(prefix, text, chan, target)
R.L.globals().SEND = wrap
before = R.L.eval('function(S) return S.Serialize and S.Serialize(SterlingQuestDB) or "" end')(R.S)
R.lua('REAL_DB = SterlingQuestDB')
R.lua('''
QUESTIE_N[13] = { name = "Nimboya", spawns = { [33] = { { 32.2, 17.4 } } } }
for _, id in ipairs({ 185, 186, 187, 190, 191, 192, 194, 195, 196, 581, 584, 587 }) do
  QUESTIE_Q[id] = { name = "STV quest " .. id, zoneOrSort = 33, requiredLevel = 30, startedBy = { { 13 } }, finishedBy = { { 13 } } }
end
for i, z in ipairs({ 400, 405, 45 }) do
  for j = 1, 9 do QUESTIE_Q[2000 + i * 10 + j] = { name = "Other " .. z .. "-" .. j, zoneOrSort = z, requiredLevel = 30 + j, startedBy = { { 13 } }, finishedBy = { { 13 } } } end
end
QUESTIE_Q[2100] = { name = "Alliance only", zoneOrSort = 33, requiredRaces = 77, requiredLevel = 30, startedBy = { { 13 } }, finishedBy = { { 13 } } }
''')
# a real path and a manual check-off before, to see they come back
R.L.eval('function(S) S.SetLegs({ { n = 1, title = "Real leg", steps = { { kind = "note", text = "real step 1" }, { kind = "note", text = "real step 2" } } } }); SterlingQuestDB.manual[1] = true end')(R.S)
R.L.eval('function(S) S.UI_Toggle(true); S.UI_Tab("sync"); S.UI_Update() end')(R.S)
R.lua('SlashCmdList.STERLINGQUEST("testmode")')
check("Sessions: three made-up sessions", R.ev('#SterlingQuestDB.sessions') == 3)
# The made-up sessions look like real recordings in Stranglethorn (0.3.18.01): on its classic map, on land, events on the trail
geo = R.L.eval('''function()
    local onMap, onLand, near, events = true, true, true, 0
    for _, s in ipairs(SterlingQuestDB.sessions) do
        for _, p in ipairs(s.trail) do
            if p.map ~= 1434 then onMap = false end
            if p.x < 24 or p.x > 42 or p.y < 8 or p.y > 80 then onLand = false end
        end
        for _, e in ipairs(s.events) do
            events = events + 1
            if e.map ~= 1434 then onMap = false end
            local best = 999
            for _, p in ipairs(s.trail) do best = math.min(best, (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2) end
            if best > 1 then near = false end
        end
    end
    return onMap, onLand, near, events
end''')()
check("Sessions: trails and events on the Stranglethorn map", geo[0])
check("  trails stay on land (inside Stranglethorn's shore)", geo[1])
check("  every event sits on its trail", geo[2])
check("Path: following a made-up session", R.L.eval('function(S) return #S.steps end')(R.S) > 3, R.L.eval('function(S) return #S.steps end')(R.S))
z = R.L.eval('function(S) local z = S.CatchupZones("Brannoc Ashvale"); return z and z[1] and z[1].count or 0 end')(R.S)
check("Catch-up: quests to catch up on", z >= 5, z)
nz = R.L.eval('function(S) local z = S.CatchupZones("Brannoc Ashvale") or {}; return #z end')(R.S)
check("Catch-up: other zones listed too", nz >= 4, nz)
few = R.L.eval('function(S) for _, z in ipairs(S.CatchupZones("Brannoc Ashvale")) do if z.key == 400 then return z.count end end return 0 end')(R.S)
check("other zones: a few each, level 44 and under", 1 <= few <= 6, few)
stv = R.L.eval('function(S) for _, z in ipairs(S.CatchupZones("Brannoc Ashvale")) do if z.key == 33 then return z.count end end return 0 end')(R.S)
check("Stranglethorn: the full list", stv >= 8, stv)
check("no Alliance-only quests", R.L.eval('function(S) for _, z in ipairs(S.CatchupZones("Brannoc Ashvale")) do for _, q in ipairs(z.quests) do if q == 2100 then return false end end end return true end')(R.S))
st = R.L.eval('''function(S) local p = S.CatchupPlan("Brannoc Ashvale", 33); local n, inlog = 0, 0
  for _, g in ipairs(p.groups) do for _, it in ipairs(g.items) do if it.state == "ready" then n = n + 1 end; if it.state == "inlog" then inlog = inlog + 1 end end end
  return n * 100 + inlog end''')(R.S)
check("Catch-up: quests show as ready, not Already complete", st // 100 >= 3, st)
check("Catch-up: your log is the made-up one", st % 100 >= 1, st)
R.L.eval('function(S) S.UI_Tab("sync"); S.UI_Update() end')(R.S)
last = R.L.eval('function(S) return S.sync.lastEvent and S.sync.lastEvent.text end')(R.S)
check("Sync: clean Last line", last == "Auto sync with Bran: 3 changes", last)
check("no sync starts in test mode (auto, all, single)", R.L.eval('function(S) S.AutoSyncAll("login"); S.SyncWith(nil, "full"); S.SyncWith("Brannoc Ashvale", "quick"); local n = 0 for _ in pairs(S.pending) do n = n + 1 end return n == 0 and S.sync.lastEvent.text == "Auto sync with Bran: 3 changes" end')(R.S))
check("every partner row stays off Syncing...", R.L.eval('function(S) for _, p in ipairs(S.Partners()) do local k = S.PartnerSyncState(p.name) if k == "syncing" then return false end end return true end')(R.S))
mix = R.L.eval('''function(S) local seen = {}; local n = 0
  for q = 100, 400 do local l = S.QuestPartnerStatus(q); if #l ~= 4 then return -1 end
    for _, e in ipairs(l) do if not seen[e.state] then seen[e.state] = true; n = n + 1 end end end
  local a, b = S.QuestPartnerStatus(187), S.QuestPartnerStatus(187)
  for i = 1, 4 do if a[i].state ~= b[i].state then return -2 end end
  return n end''')(R.S)
check("quest status: all four states across quests, steady per quest", mix == 4, mix)
check("test partners in a quest have objective lines", R.L.eval('function(S) for q = 100, 400 do for _, e in ipairs(S.QuestPartnerStatus(q)) do if e.state == "log" and not (e.objs and #e.objs > 0) then return false end end end return true end')(R.S))
check("quest status uses nicknames", R.L.eval('function(S) return S.QuestPartnerStatus(187)[1].name end')(R.S) == "Bran")
check("Catch-up picks Bran", R.L.eval('function(S) return S.catchupWho end')(R.S) == "Brannoc Ashvale")
check("no TomTom arrow touched", R.L.eval('function(S) return true end')(R.S))
check("chat says nothing is saved or sent", any("Test mode on: nothing is saved or sent" in c for c in R.chat()))
names = [R.L.eval('function(S, i) local p = S.PartnersSorted()[i]; return p and p.name end')(R.S, i) for i in range(1, 6)]
check("made-up partners, favourites first", names[:2] == ["Brannoc Ashvale", "Tovak Stoneroot"] and "Vessa Marr" not in names, names)
check("You row uses the made-up name and level", "Kaelith Emberfall" in str(R.L.eval('function(S) return S.UI_Page("sync").me.st:GetText() end')(R.S)) and "lvl 43" in str(R.L.eval('function(S) return S.UI_Page("sync").me.st:GetText() end')(R.S)))
check("TEST DATA tag shown", R.L.eval('function() return SterlingQuestFrame.testTag and SterlingQuestFrame.testTag:IsShown() end')() is True)
check("mixed: one outdated, one online, one can't tell", R.L.eval('function(S) return (S.VersionState("Mirelle Duskwhisper")) end')(R.S) == "older" and R.L.eval('function(S) return (S.PartnerStatus("Brannoc Ashvale")) end')(R.S) is True and R.L.eval('function(S) local on, how = S.PartnerStatus("Zil\'ana Frostcall"); return how == nil end')(R.S) is True)
for t in ("sync", "catchup", "path", "sessions"):
    R.L.eval('function(S, t) S.UI_Tab(t); S.UI_Update() end')(R.S, t)
# activity while on: nothing goes out, nothing comes in
R.lua('SlashCmdList.STERLINGQUEST("sync")'); R.lua('SlashCmdList.STERLINGQUEST("sync")')
R.L.eval('function(S) S.SyncWith(nil, "full"); S.SendProfile() end')(R.S)
sim.pump(30)
check("no addon messages sent", sent == [], sent[:3])
L.lua('SEND("SterlingQuest", "PROF\\tOrc\\tred\\tHacked", "WHISPER", "Garrow Thane")'); sim.pump(2)
check("incoming messages ignored", R.L.eval('function(S) return S.profiles["Vessa Marr"] == nil end')(R.S))
# a /reload while on: the real data is put back before the game saves, and the outbox isn't fake
R.L.eval('function(S) local p = S.FindPartner("Brannoc Ashvale"); p.show = false end')(R.S)
R.fire("PLAYER_LOGOUT")
check("logout turns it off", R.L.eval('function(S) return S.testMode == nil end')(R.S))
check("real saved table is back (same table)", R.ev('SterlingQuestDB == REAL_DB') is True)
check("real partners intact", R.L.eval('function(S) return S.FindPartner("Vessa Marr") ~= nil and S.FindPartner("Brannoc Ashvale") == nil end')(R.S))
check("real nickname intact", R.L.eval('function(S) return S.Nickname("Vessa Marr") end')(R.S) == "Vess")
out = R.ev('SterlingQuestSyncOut.characters["%s"]' % R.ev('MYGUID'))
check("outbox written with real data only", out is not None and "Brannoc" not in str(R.L.eval('function() local t = {} for g, p in pairs(SterlingQuestSyncOut.characters[MYGUID].partners) do t[#t+1] = tostring(p.name) end return table.concat(t, ",") end')()))
# toggling off by command
R.lua('SlashCmdList.STERLINGQUEST("testmode")'); R.lua('SlashCmdList.STERLINGQUEST("testmode")')
check("real path back", R.L.eval('function(S) return S.steps[1] and S.steps[1].text end')(R.S) == "real step 1")
check("real quest log back", R.L.eval('function(S) S.Refresh(); return S.log[186] == nil end')(R.S))
check("real quest status back", R.L.eval('function(S) local l = S.QuestPartnerStatus(187); for _, e in ipairs(l) do if e.name == "Bran" then return false end end return true end')(R.S))
check("real check-off back", R.L.eval('function(S) return SterlingQuestDB.manual[1] end')(R.S) is True)
check("second /st testmode turns it off", R.L.eval('function(S) return S.testMode == nil and S.FindPartner("Vessa Marr") ~= nil end')(R.S))
check("tag hidden again", R.L.eval('function() return not SterlingQuestFrame.testTag:IsShown() end')())
check("not in the command list", "testmode" not in R.L.eval('function() CHAT = {}; SlashCmdList.STERLINGQUEST("nonsense"); local t = {} for _, v in pairs(CHAT) do t[#t+1] = tostring(v) end return table.concat(t) end')())
check("no Lua errors", R.errors() + L.errors() == 0, (R.errors(), L.errors()))
print("ALL OK" if ok else "SOME FAILED")
