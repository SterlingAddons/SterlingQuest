import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
import sim, re
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
A = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery"), (200, "Raptor Mastery")], [185, 186, 187] + list(range(2000, 2400)), account=ACC)
B = sim.Player("Tovak", [(200, "Raptor Mastery")], [185, 186, 187, 188] + list(range(1000, 1500)), src=_os.path.join(QA, "fixtures", "sterling-6.29"), level=30)
check("old copy really is 6.29", str(B.S.ADDON_VER) == "6.29")
A.S.AddPartner("Tovak", True); B.S.AddPartner("Kaelith Emberfall", True)
A.lua('SterlingQuestDB.opts.chat_sync = 1'); B.lua('SterlingQuestDB.opts.chat_sync = 1')
sent = {"n": 0}
sim.pump(15)
A.chat(); B.chat()
A.S.SyncWith("Tovak", "full")
t = 0
while t < 200 and not any("Full sync complete" in c for c in A.L.globals().CHAT.values()):
    sim.pump(1); t += 1
check("0.2.30 full sync with a 6.29 partner completes (%ds)" % t, any("Full sync complete" in clean(c) for c in A.chat()))
B.chat()
B.S.SyncWith("Kaelith Emberfall", "full")
t = 0
while t < 200 and not any("Full sync complete" in c for c in B.L.globals().CHAT.values()):
    sim.pump(1); t += 1
check("and started from the 6.29 side (%ds)" % t, any("Full sync complete" in clean(c) for c in B.chat()))
na = A.L.eval('function(S) local n = 0; for _ in pairs(S.snaps["Tovak"].completed) do n = n + 1 end return n end')(A.S)
nb = B.L.eval('function(S) local n = 0; for _ in pairs(S.snaps["Kaelith Emberfall"].completed) do n = n + 1 end return n end')(B.S)
check("both sides hold the other's whole history", na == 504 and nb == 403, (na, nb))
st = A.L.eval('function(S) local a, b, c = S.VersionState("Tovak"); return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end')(A.S)
check("new side shows the 6.29 partner as Outdated, still syncing", st == "older,they,6.29", st)
A.L.eval('function(S) S.UI_Toggle(true); S.UI_Tab("sync"); S.UI_Update() end')(A.S)
row = clean(A.L.eval('function(S) return S.UI_Page("sync").rows[1].ver:GetText() end')(A.S))
check("row reads: " + row, "Outdated v6.29" in row)
check("no red strip for a merely outdated partner", not A.ev('SterlingQuestFrame.notice:IsShown()'))
check("offline sync with them waits for a key (they can't send one)", A.S.KeyState("Tovak") == "half")
# changes both ways
A.lua('QDONE[188] = true; QLOG = { { id = 200, title = "Raptor Mastery" } }'); A.fire("QUEST_TURNED_IN", 188)
B.lua('QDONE[200] = true; QLOG = {}'); B.fire("QUEST_TURNED_IN", 200)
sim.pump(15)
check("a change from new to old arrives", B.L.eval('function(S) return S.snaps["Kaelith Emberfall"].completed[188] == true end')(B.S))
check("a change from old to new arrives", A.L.eval('function(S) return S.snaps["Tovak"].completed[200] == true end')(A.S))
# quiet line: no ping-pong
before = (A.L.eval('function(S) return S.sync.sent end')(A.S), B.L.eval('function(S) return S.sync.sent end')(B.S))
sim.pump(60)
after = (A.L.eval('function(S) return S.sync.sent end')(A.S), B.L.eval('function(S) return S.sync.sent end')(B.S))
check("idle for a minute: no message ping-pong between versions %s -> %s" % (before, after), after[0] - before[0] <= 6 and after[1] - before[1] <= 6)
# invites across versions
C = sim.Player("Bran", [], [1, 2], src=_os.path.join(QA, "fixtures", "sterling-6.29"))
sim.pump(12)
A.S.Invite("Bran"); sim.pump(3)
check("an invite from 0.2.30 reaches a 6.29 player", C.ev('SterlingQuestInvite ~= nil and SterlingQuestInvite:IsShown()'))
C.lua('SterlingQuestInvite.yes:Click()'); sim.pump(20)
check("accepting adds both and syncs", A.L.eval('function(S) return S.FindPartner("Bran") ~= nil and S.snaps["Bran"] ~= nil end')(A.S) and C.L.eval('function(S) return S.snaps["Kaelith Emberfall"] ~= nil end')(C.S))
check("no Lua errors on any side", A.errors() + B.errors() + C.errors() == 0, (A.errors(), B.errors(), C.errors()))
snags = [clean(c) for p in (A, B, C) for c in p.L.globals().CHAT.values() if "snag" in c]
check("no snags", not snags, snags[:3])
print("ALL OK" if ok else "SOME FAILED")
