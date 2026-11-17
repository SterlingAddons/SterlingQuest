import sim, re, random
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", c)
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
A = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery"), (200, "Raptor Mastery")], [185, 186, 187], account=ACC)
B = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185, 186, 187, 188] + list(range(1000, 1700)), account=ACC, level=39)
A.S.AddPartner("Brannoc Ashvale", True); B.S.AddPartner("Kaelith Emberfall", True)
A.lua('SterlingQuestDB.opts.chat_sync = 1'); B.lua('SterlingQuestDB.opts.chat_sync = 1')
check("versions: build from toc", A.S.BUILD == 311 and A.S.BuildOf("0.2.30") == 230)
check("BuildOf old scheme", A.S.BuildOf("6.29") == 229 and A.S.BuildOf("5.84") == 184 and A.S.BuildOf("6.0") == 200 and A.S.BuildOf("5.37") == 137)
check("BuildOf future", A.S.BuildOf("0.3.0") == 300 and A.S.BuildOf("1.0.0") == 10000 and A.S.BuildOf("0.2.31") == 231)
check("CompareVer 6.29 < 0.2.30 < 0.2.31", A.S.CompareVer("6.29", "0.2.30") == -1 and A.S.CompareVer("0.2.31", "0.2.30") == 1 and A.S.CompareVer("0.2.30", "0.2.30") == 0)
check("CompareVer unknown", A.S.CompareVer(None, "0.2.30") == 0 and A.S.CompareVer("?", "0.2.30") == 0)
sim.pump(15)
A.chat(); B.chat()
A.S.SyncWith("Brannoc Ashvale", "full")
t = 0
while t < 90 and not any("Full sync complete" in c for c in A.L.globals().CHAT.values()):
    sim.pump(1); t += 1
ac = [clean(c) for c in A.chat()]
check("full sync completes through ChatThrottleLib", any("Full sync complete" in c for c in ac), ac)
print("   full sync of 704 finished quests took about %ds of game time" % t)
check("A holds B's log", A.ev('(function() local n = 0; for _ in pairs(SterlingQuestDB.snaps) do n = n + 1 end return n end)()') == 1)
nd = A.L.eval('function(S) local n = 0; for _ in pairs(S.snaps["Brannoc Ashvale"].completed) do n = n + 1 end return n end')(A.S)
check("A sees all 704 of B's finished quests", nd == 704, nd)
check("keys swapped by whisper (both halves on both sides)", A.S.KeyState("Brannoc Ashvale") == "signed" and B.S.KeyState("Kaelith Emberfall") == "signed")
ka = A.L.eval('function(S) local p = S.FindPartner("Brannoc Ashvale"); return p.k1 .. "/" .. p.k2 end')(A.S)
kb = B.L.eval('function(S) local p = S.FindPartner("Kaelith Emberfall"); return p.k2 .. "/" .. p.k1 end')(B.S)
check("the two sides hold the same pair of halves", ka == kb, (ka, kb))
check("confirmed copy remembered for offline sync", A.ev('SterlingQuestDB.offline and SterlingQuestDB.offline["Brannoc Ashvale"] and SterlingQuestDB.offline["Brannoc Ashvale"].base ~= nil'))
check("version state: same", A.S.VersionState("Brannoc Ashvale") == "same" or A.L.eval('function(S) return (S.VersionState("Brannoc Ashvale")) end')(A.S) == "same")
# a change on B travels as a delta
B.lua('QLOG = {}; QDONE[200] = true'); B.fire("QUEST_TURNED_IN", 200); sim.pump(12)
check("B's turn-in arrives at A as a change", A.L.eval('function(S) return S.snaps["Brannoc Ashvale"].completed[200] == true and S.snaps["Brannoc Ashvale"].log[200] == nil end')(A.S))
# version states
A.L.eval('function(S) S.addonVers["Brannoc Ashvale"] = "6.29" end')(A.S)
st = A.L.eval('function(S) local a, b, c = S.VersionState("Brannoc Ashvale"); return a .. "," .. tostring(b) .. "," .. tostring(c) end')(A.S)
check("older addon, same protocol = older/they", st == "older,they,6.29", st)
A.L.eval('function(S) S.addonVers["Brannoc Ashvale"] = "0.9.99" end')(A.S)
st = A.L.eval('function(S) local a, b = S.VersionState("Brannoc Ashvale"); return a .. "," .. tostring(b) end')(A.S)
check("newer addon = newer/you", st == "newer,you", st)
A.L.eval('function(S) S.sync.vers["Brannoc Ashvale"] = 5 end')(A.S)
st = A.L.eval('function(S) local a, b = S.VersionState("Brannoc Ashvale"); return a .. "," .. tostring(b) end')(A.S)
check("protocol differs = nosync/they", st == "nosync,they", st)
A.L.eval('function(S) S.sync.vers["Brannoc Ashvale"] = 6; S.addonVers["Brannoc Ashvale"] = "0.2.30" end')(A.S)
# real protocol mismatch on the wire
B.L.eval('function(S) S.VERSION = 7 end')(B.S)
A.chat(); B.chat()
B.S.SyncWith("Kaelith Emberfall", "quick"); sim.pump(8)
ac = [clean(c) for c in A.chat()]; bc = [clean(c) for c in B.chat()]
check("mismatch says Can't sync on the old side", any("Can't sync with Brannoc Ashvale: update needed" in c for c in ac), ac)
check("mismatch says Can't sync on the new side", any("Can't sync with Kaelith Emberfall: update needed" in c for c in bc), bc)
B.L.eval('function(S) S.VERSION = 6; S.sync.vers = {}; S.warned = {} end')(B.S); A.L.eval('function(S) S.sync.vers = {}; S.warned = {} end')(A.S)
# lossy line still completes
sim.LOSS["Brannoc Ashvale"] = 0.3; random.seed(5)
A.chat(); A.S.SyncWith("Brannoc Ashvale", "full")
t = 0
while t < 120 and not any("Full sync complete" in c for c in A.L.globals().CHAT.values()):
    sim.pump(1); t += 1
check("full sync completes with 30%% of parts lost (%ds)" % t, any("Full sync complete" in clean(c) for c in A.chat()))
sim.LOSS.clear()
check("no Lua errors", A.errors() == 0 and B.errors() == 0, (A.errors(), B.errors()))
print("ALL OK" if ok else "SOME FAILED")
