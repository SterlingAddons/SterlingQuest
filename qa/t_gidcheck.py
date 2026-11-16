# GID is only stored when GetPlayerInfoByGUID says the id belongs to the sender (security audit, 0.3.02).
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
R = sim.Player("Kaelith Emberfall", [(188, "a")], [185], account=ACC, pre=FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "b")], [185], account=ACC, pre=FRIEND % "Kaelith Emberfall")
LG = L.ev('MYGUID')
sim.UNCACHED.add(LG)                     # the game doesn't know Bran's id yet
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(60)
g = lambda: R.L.eval('function(S) return S.FindPartner("Brannoc Ashvale").guid end')(R.S)
check("unknown to the game: not stored", g() is None, g())
check("kept aside to try again", R.L.eval('function(S) return S.pendingGID["Brannoc Ashvale"] end')(R.S) == LG)
sim.UNCACHED.discard(LG)                 # now the client knows them
L.lua('SEND("SterlingQuest", "AVER\\t0.3.02", "WHISPER", "Kaelith Emberfall")'); sim.pump(2)
check("next message: confirmed and stored", g() == LG, g())
check("nothing left pending", R.L.eval('function(S) return S.pendingGID["Brannoc Ashvale"] end')(R.S) is None)
# someone claiming another character's id
X = sim.Player("Tovak Stoneroot", [(1, "a")], [], account=ACC)
R.S.AddPartner("Tovak Stoneroot", True)
X.lua('SEND("SterlingQuest", "GID\\t%s", "WHISPER", "Kaelith Emberfall")' % LG); sim.pump(2)
check("someone else's id is refused", R.L.eval('function(S) return S.FindPartner("Tovak Stoneroot").guid end')(R.S) is None)
check("and Bran keeps his", g() == LG)
check("refused id isn't retried", R.L.eval('function(S) return S.pendingGID["Tovak Stoneroot"] end')(R.S) is None)
# their own id works
XG = X.ev('MYGUID')
X.lua('SEND("SterlingQuest", "GID\\t%s", "WHISPER", "Kaelith Emberfall")' % XG); sim.pump(2)
check("their own id is stored", R.L.eval('function(S) return S.FindPartner("Tovak Stoneroot").guid end')(R.S) == XG)
check("no Lua errors", R.errors() + L.errors() + X.errors() == 0, (R.errors(), L.errors(), X.errors()))
print("ALL OK" if ok else "SOME FAILED")
