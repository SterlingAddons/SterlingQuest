# One character played on two PCs. Each PC keeps its own saved copy-counter; the server clock keeps
# the numbers rising across both, so partners never drop the second PC's updates as "old".
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
S = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185, 186], account=ACC, pre=FRIEND % "Kaelith Emberfall")
S.S.AddPartner("Kaelith Emberfall", True)
def theirs(): return S.L.eval('function(S) local s = S.snaps["Kaelith Emberfall"]; return s and s.seq or 0 end')(S.S)
def has(q): return S.L.eval('function(S) local s = S.snaps["Kaelith Emberfall"]; return s ~= nil and (s.log[%d] ~= nil or s.completed[%d] == true) end' % (q, q))(S.S)
# PC A: a long-played PC, counter far ahead
A = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185], account=ACC, sv='SterlingQuestDB = { syncSeq = 900 }', pre=FRIEND % "Brannoc Ashvale")
A.S.AddPartner("Brannoc Ashvale", True)
sim.pump(40)
A.lua('QLOG[#QLOG + 1] = { id = 301, title = "From PC A" }'); A.fire("QUEST_ACCEPTED", 301); A.fire("QUEST_LOG_UPDATE"); sim.pump(15)
check("Brannoc has PC A's change", has(301))
seqA = theirs()
del sim.players["Kaelith Emberfall"]
sim.pump(3600)
# PC B: counter far behind (rarely used), its own older saved data
B = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery"), (301, "From PC A")], [185], account=ACC, sv='SterlingQuestDB = { syncSeq = 10 }', pre=(FRIEND % "Brannoc Ashvale") + '; NOW = %r' % S.ev('NOW'))
B.S.AddPartner("Brannoc Ashvale", True)
sim.pump(40)
check("PC B's copies are numbered above PC A's (%d > %d)" % (theirs(), seqA), theirs() > seqA)
for k, q in enumerate((302, 303, 304)):
    B.lua('QLOG[#QLOG + 1] = { id = %d, title = "From PC B %d" }' % (q, k)); B.fire("QUEST_ACCEPTED", q); B.fire("QUEST_LOG_UPDATE"); sim.pump(15)
check("every small update from PC B arrives", has(302) and has(303) and has(304))
del sim.players["Kaelith Emberfall"]
sim.pump(600)
# back on PC A, which still holds its own older saved counter
A2 = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery"), (301, "From PC A"), (302, "x"), (303, "y"), (304, "z")], [185], account=ACC, sv='SterlingQuestDB = { syncSeq = 905 }', pre=(FRIEND % "Brannoc Ashvale") + '; NOW = %r' % S.ev('NOW'))
A2.S.AddPartner("Brannoc Ashvale", True)
sim.pump(40)
A2.lua('QLOG[#QLOG + 1] = { id = 305, title = "Back on A" }'); A2.fire("QUEST_ACCEPTED", 305); A2.fire("QUEST_LOG_UPDATE"); sim.pump(15)
check("and back on PC A, its update arrives too", has(305))
check("no Lua errors", S.errors() == 0 and A2.errors() == 0)
print("ALL OK" if ok else "SOME FAILED")
