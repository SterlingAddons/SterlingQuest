import sim, re
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
# three sessions: an old long one, an old one being followed, a recent one
SV = '''
local function mk(id, name, start, n)
  local ev, tr = {}, {}
  for i = 1, n do
    ev[i] = { t = start + i * 30, k = (i % 3 == 0) and "T" or ((i % 3 == 1) and "A" or "O"), q = 100 + i, map = 1413, x = 40.5 + (i % 50) / 10, y = 61.25, quest = "Quest |with^odd:chars; " .. i, npc = "Npc " .. i, text = (i % 7 == 0) and ("a note with\\nnewline and \\"quotes\\" " .. i) or nil }
    for j = 1, 6 do tr[#tr + 1] = { t = start + i * 30 + j, map = 1413, x = 40 + i / 7 + j / 100, y = 60 - i / 9, brk = (j == 3 and i % 11 == 0) or nil } end
  end
  return { id = id, name = name, char = "Kaelith Emberfall", realm = "R", start = start, stop = start + n * 30, lvl0 = 30, lvl1 = 31, events = ev, trail = tr, zones = { Barrens = true }, note = "keep me", race = "Troll" }
end
local now = 1794700000
SterlingQuestDB = { opts = {}, sessions = { mk("old", "Old long run", now - 60 * 86400, 400), mk("followed", "Old but followed", now - 50 * 86400, 20), mk("new", "Last week", now - 5 * 86400, 30) }, following = "followed" }
'''
P = sim.Player("Kaelith Emberfall", [], [], sv=SV, account=ACC)
L, S = P.L, P.S
L.execute('''
function DEEP(a, b, path)
  path = path or ""
  if type(a) ~= type(b) then return path .. ": type " .. type(a) .. " vs " .. type(b) end
  if type(a) ~= "table" then if a ~= b then return path .. ": " .. tostring(a) .. " vs " .. tostring(b) end return nil end
  for k, v in pairs(a) do local r = DEEP(v, b[k], path .. "." .. tostring(k)); if r then return r end end
  for k in pairs(b) do if a[k] == nil then return path .. "." .. tostring(k) .. ": missing in first" end end
  return nil
end
function COPY(t) if type(t) ~= "table" then return t end local c = {}; for k, v in pairs(t) do c[k] = COPY(v) end return c end
ORIG = COPY(SterlingQuestDB.sessions[1])
''')
check("serializer round trip (numbers, strings with odd characters, booleans, holes, nesting)",
  L.eval('function(S) local t = { 1, 2.5, -3, 1e300, 0.1, "a|b^c:d;e\\n\\0f", true, false, { x = { y = { 1, 2, 3 } }, [10] = "sparse", [-1] = "neg", [1.5] = "frac" }, "" }; t[13] = "hole"; return DEEP(t, S.Deserialize(S.Serialize(t))) == nil and DEEP(S.Deserialize(S.Serialize(t)), t) == nil end')(S))
check("nothing is packed right at login", P.ev('SterlingQuestDB.sessions[1].pk == nil'))
sim.pump(29); check("...or before 30 seconds", P.ev('rawget(SterlingQuestDB.sessions[1], "pk") == nil'))
sim.pump(8)
check("the old session is packed after login", L.eval('function(S) return S.IsPacked(SterlingQuestDB.sessions[1]) end')(S))
check("its tables are gone from the saved data", P.ev('rawget(SterlingQuestDB.sessions[1], "events") == nil and rawget(SterlingQuestDB.sessions[1], "trail") == nil'))
n, before, after, waiting = L.eval('function(S) return S.PackStats() end')(S)
print("   packed %d session: %d bytes down to %d (%.0f%% smaller)" % (n, before, after, 100 - after * 100.0 / before))
check("the session being followed is left alone", P.ev('rawget(SterlingQuestDB.sessions[2], "pk") == nil'))
check("the recent session is left alone", P.ev('rawget(SterlingQuestDB.sessions[3], "pk") == nil'))
check("name, times, zones, note stay readable without unpacking", P.ev('rawget(SterlingQuestDB.sessions[1], "name") == "Old long run" and SterlingQuestDB.sessions[1].zones.Barrens and SterlingQuestDB.sessions[1].note == "keep me" and rawget(SterlingQuestDB.sessions[1], "events") == nil'))
summ = L.eval('function(S) return S.SessionSummary(SterlingQuestDB.sessions[1]) end')(S)
check("summary line works while packed (%s)" % summ, "133 turn-ins" in summ and P.ev('rawget(SterlingQuestDB.sessions[1], "events") == nil'), summ)
check("the Sessions tab and its tooltip don't unpack it", L.eval('''function(S) S.UI_Toggle(true); S.UI_Tab("sessions"); S.UI_Update()
  for _, f in ipairs(FRAMES) do if rawget(f, "sess") and f._scripts.OnEnter and f:IsVisible() then f._scripts.OnEnter(f) end end
  return rawget(SterlingQuestDB.sessions[1], "events") == nil end''')(S))
# reading it unpacks it, identical to the original
check("reading it unpacks it, identical to the original", L.eval('function(S) local s = SterlingQuestDB.sessions[1]; local n = #s.events; local d = DEEP(ORIG.events, s.events) or DEEP(ORIG.trail, s.trail); return n == 400 and d == nil, d end')(S))
check("export string matches the original's", L.eval('function(S) return S.EncodeSession(SterlingQuestDB.sessions[1]) == S.EncodeSession(ORIG) end')(S))
# logout: goes back to packed without redoing the work
pk = P.ev('SterlingQuestDB.sessions[1].pk')
P.fire("PLAYER_LOGOUT")
check("at logout an unchanged session goes back to its packed form", P.ev('rawget(SterlingQuestDB.sessions[1], "events") == nil') and P.ev('SterlingQuestDB.sessions[1].pk') == pk)
# simulate the next login on the same saved table (metatables are not saved)
L.execute('for _, s in ipairs(SterlingQuestDB.sessions) do setmetatable(s, nil) end')
check("without the addon's help the saved table really has no events", P.ev('SterlingQuestDB.sessions[1].events == nil'))
L.eval('function(S) S.PackInit() end')(S)
check("next login: it reads back, identical", L.eval('function(S) local s = SterlingQuestDB.sessions[1]; return DEEP(ORIG.events, s.events) == nil and DEEP(ORIG.trail, s.trail) == nil end')(S))
# a changed session is packed again from its tables
L.execute('table.insert(SterlingQuestDB.sessions[1].events, { t = 5, k = "N", text = "added later" }); ORIG2 = COPY(SterlingQuestDB.sessions[1].events)')
P.fire("PLAYER_LOGOUT")
L.execute('for _, s in ipairs(SterlingQuestDB.sessions) do setmetatable(s, nil) end')
L.eval('function(S) S.PackInit() end')(S)
check("a session changed while unpacked keeps the change", L.eval('function(S) local s = SterlingQuestDB.sessions[1]; return #s.events == 401 and DEEP(ORIG2, s.events) == nil end')(S))
# following a packed session, deleting and restoring it
check("following a packed session works", L.eval('function(S) local s = SterlingQuestDB.sessions[1]; S.PackSession(s); local was = S.IsPacked(s); S.FollowSession(s, false); return was and #S.steps > 0 end')(S))
check("delete and restore keep it intact", L.eval('function(S) local s = SterlingQuestDB.sessions[1]; S.StopFollowing(); S.PackSession(s); S.DeleteSession(s); S.Restore(); local r = S.FindSession("old"); return r ~= nil and #r.events == 401 end')(S))
# switching packing off unpacks everything
L.eval('function(S) S.PackSession(SterlingQuestDB.sessions[1]) end')(S)
nun = L.eval('function(S) SterlingQuestDB.opts.packOld = false; return S.UnpackAll() end')(S)
check("switching packing off unpacks everything", nun >= 1 and P.ev('(function() for _, s in ipairs(SterlingQuestDB.sessions) do if rawget(s, "pk") then return false end end return true end)()'))
sim.pump(60)
check("and nothing is packed while it is off", P.ev('(function() for _, s in ipairs(SterlingQuestDB.sessions) do if rawget(s, "pk") then return false end end return true end)()'))
# no LibDeflate: nothing is touched
L.execute('SterlingQuestDB.opts.packOld = true; REALSTUB = LibStub; LibStub = nil')
check("without LibDeflate nothing is packed and nothing breaks", L.eval('function(S) return S.PackSession(SterlingQuestDB.sessions[1]) == false and #SterlingQuestDB.sessions[1].events == 401 end')(S))
L.execute('LibStub = REALSTUB')
# a packed copy that can't be read: session shows empty, packed copy survives
L.eval('function(S) S.PackSession(SterlingQuestDB.sessions[1]) end')(S)
pk = P.ev('SterlingQuestDB.sessions[1].pk')
L.execute('LibStub = nil')
check("unreadable right now: opens empty instead of erroring", P.ev('#SterlingQuestDB.sessions[1].events == 0'))
P.fire("PLAYER_LOGOUT")
check("...and the packed copy is still there, untouched", P.ev('SterlingQuestDB.sessions[1].pk') == pk and P.ev('rawget(SterlingQuestDB.sessions[1], "events") == nil'))
L.execute('LibStub = REALSTUB')
check("...and reads back fine later", P.ev('#SterlingQuestDB.sessions[1].events == 401'))
# in combat: waits
L.execute('SterlingQuestDB.sessions[1].pk = nil; for _, s in ipairs(SterlingQuestDB.sessions) do s.pkSkip = nil end; INCOMBAT = true')
L.eval('function(S) S.UnpackAll(); S.PackSoon(1) end')(S); sim.pump(25)
check("no packing during combat", P.ev('rawget(SterlingQuestDB.sessions[1], "pk") == nil'))
L.execute('INCOMBAT = false'); sim.pump(15)
check("packing resumes after combat", P.ev('rawget(SterlingQuestDB.sessions[1], "pk") ~= nil'))
check("no Lua errors", P.errors() == 0, P.errors())
bad = [clean(c) for c in P.chat() if "snag" in c]
check("no snags in chat", not bad, bad)
print("ALL OK" if ok else "SOME FAILED")
