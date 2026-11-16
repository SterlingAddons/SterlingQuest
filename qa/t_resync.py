import sim, re
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
A = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185, 186] + list(range(2000, 2600)), account=ACC)
B = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185] + list(range(1000, 1600)), account=ACC)
A.S.AddPartner("Brannoc Ashvale", True); B.S.AddPartner("Kaelith Emberfall", True)
# they are on each other's friends list; now and then the list comes back empty for a moment (it does in game)
for P, other in ((A, "Brannoc Ashvale"), (B, "Kaelith Emberfall")):
    P.lua('FRIEND_OK = true; C_FriendList = { GetNumFriends = function() return FRIEND_OK and 1 or 0 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }' % other)
    P.fire("FRIENDLIST_UPDATE")
sim.pump(40)
def stats(P): return P.L.eval('function(S) return (S.sync.snapsOut or 0), (S.sync.deltasOut or 0), S.sync.sent end')(P.S)
a0, b0 = stats(A), stats(B)
print("   after login and first sync: A full/changes/messages", a0, " B", b0)
# an hour of quiet play: nobody's quest log changes; the game fires roster and friend-list events now and then
for minute in range(60):
    sim.pump(60, step=1.0)
    for P in (A, B):
        blip = (minute % 7 == 3)
        P.lua('FRIEND_OK = %s' % ('false' if blip else 'true'))
        P.fire("GUILD_ROSTER_UPDATE"); P.fire("FRIENDLIST_UPDATE")
        P.lua('FRIEND_OK = true')
a1, b1 = stats(A), stats(B)
print("   after an idle hour:         A", a1, " B", b1)
check("an idle hour sends no more full copies (A sent %d, B sent %d)" % (a1[0] - a0[0], b1[0] - b0[0]), a1[0] == a0[0] and b1[0] == b0[0])
check("and stays quiet: under 60 messages each for the hour (A %d, B %d)" % (a1[2] - a0[2], b1[2] - b0[2]), a1[2] - a0[2] < 60 and b1[2] - b0[2] < 60)
# one real change still gets through, as a change not a full copy
B.lua('QDONE[200] = true; QLOG = {}'); B.fire("QUEST_TURNED_IN", 200); sim.pump(15)
b2 = stats(B)
check("a real change still arrives", A.L.eval('function(S) return S.snaps["Brannoc Ashvale"].completed[200] == true end')(A.S))
check("and travels as a change, not a full copy", b2[0] == b1[0] and b2[1] == b1[1] + 1, (b1, b2))
# partner reloads (keeps saved copy): no full copy needed
check("no Lua errors", A.errors() + B.errors() == 0)
print("ALL OK" if ok else "SOME FAILED")
