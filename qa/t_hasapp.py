# Who has the Sterling Quest Sync app (handoff section 10, 0.2.40): APPV beside PROF, partners[guid].app in the outbox.
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {}, app = { version = "%s" } }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
SV = 'SterlingQuestDB = { opts = { chat_sync = 3 } }'
R = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185], account=ACC, sv=SV, pre=COMP % "0.1.9" + "; " + FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185], account=ACC, sv=SV, pre=FRIEND % "Kaelith Emberfall")
sent = []
for P in (R, L):
    orig = P.L.globals().SEND
    def wrap(prefix, text, chan, target=None, orig=orig, who=P.name):
        sent.append((who, target, str(text))); return orig(prefix, text, chan, target)
    P.L.globals().SEND = wrap
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(60)
app = lambda P, n: P.L.eval('function(S) return S.FindPartner("%s").app end' % n)(P.S)
appv = lambda who: [s[2] for s in sent if s[0] == who and s[2].startswith("APPV")]
check("Kaelith (app 0.1.9) sends his version", appv("Kaelith Emberfall") and all(x == "APPV\t0.1.9" for x in appv("Kaelith Emberfall")), appv("Kaelith Emberfall"))
check("Bran (no companion) sends an empty one", appv("Brannoc Ashvale") and all(x == "APPV\t" for x in appv("Brannoc Ashvale")), appv("Brannoc Ashvale"))
check("Bran records Kaelith has the app", app(L, "Kaelith Emberfall") == "0.1.9", app(L, "Kaelith Emberfall"))
check("Kaelith records Bran doesn't", app(R, "Brannoc Ashvale") is False, app(R, "Brannoc Ashvale"))
R.fire("PLAYER_LOGOUT")
RG, LG = R.ev('MYGUID'), L.ev('MYGUID')
check("outbox: partners[Bran].app = false", R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].app' % (RG, LG)) is False)
# bad versions are ignored, the last good value stays
L.L.eval('function(S) S.FindPartner("Kaelith Emberfall").app = "0.1.9" end')(L.S)
for bad in ["1", "0.1.9.9", "abc", "12345.1", "0.1.9 ", "0..1", "1.2.3a"]:
    R.lua('SEND("SterlingQuest", "APPV\\t%s", "WHISPER", "Brannoc Ashvale")' % bad)
sim.pump(3)
check("bad versions ignored, last value kept", app(L, "Kaelith Emberfall") == "0.1.9", app(L, "Kaelith Emberfall"))
R.lua('SEND("SterlingQuest", "APPV\\t10.2", "WHISPER", "Brannoc Ashvale")'); sim.pump(2)
check("two groups accepted", app(L, "Kaelith Emberfall") == "10.2")
R.lua('SEND("SterlingQuest", "APPV\\t1.22.333", "WHISPER", "Brannoc Ashvale")'); sim.pump(2)
check("three groups accepted", app(L, "Kaelith Emberfall") == "1.22.333")
# kept through a logout
L.fire("PLAYER_LOGOUT")
check("kept after logout", app(L, "Kaelith Emberfall") == "1.22.333")
# companion there but its inbox has no version yet: nothing sent, nothing overwritten
n = len(appv("Kaelith Emberfall"))
R.lua('SterlingQuestSync_Inbox.app = nil')
R.L.eval('function(S) S.SendProfile({ chan = "WHISPER", target = "Brannoc Ashvale", key = "W:Brannoc Ashvale" }) end')(R.S); sim.pump(3)
check("no inbox version: no APPV sent", len(appv("Kaelith Emberfall")) == n, appv("Kaelith Emberfall")[n:])
check("and Bran keeps what he had", app(L, "Kaelith Emberfall") == "1.22.333")
# a partner never seen since this update: app left out of the outbox
R.L.eval('function(S) S.FindPartner("Brannoc Ashvale").app = nil end')(R.S)
R.fire("PLAYER_LOGOUT")
check("not seen since the update: app left out", R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].app' % (RG, LG)) is None)
R.L.eval('function(S) S.FindPartner("Brannoc Ashvale").app = "0.2" end')(R.S); R.fire("PLAYER_LOGOUT")
check("has it: version in the outbox", R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].app' % (RG, LG)) == "0.2")
# no pairing codes to someone who said they have no app
R.L.eval('function(S) S.FindPartner("Brannoc Ashvale").app = false end')(R.S)
R.lua('SterlingQuestSync_Inbox = { format = 1, written = GetServerTime(), chars = { ["%s"] = { packets = {}, offers = { { partner = "%s", code = "ABCD-EFGH-JKMN", expires = GetServerTime() + 86400 } }, pairs = {} } } }' % (RG, LG))
R.L.eval('function(S) S.AppInbox() end')(R.S); sim.pump(5)
check("no code sent to a partner without the app", not [s for s in sent if s[2].startswith("PCODE")])
R.L.eval('function(S) S.FindPartner("Brannoc Ashvale").app = "0.1.9" end')(R.S); sim.pump(35)
check("but sent once they have it", len([s for s in sent if s[2].startswith("PCODE")]) == 1)
check("no Lua errors", R.errors() + L.errors() == 0, (R.errors(), L.errors()))
print("ALL OK" if ok else "SOME FAILED")
