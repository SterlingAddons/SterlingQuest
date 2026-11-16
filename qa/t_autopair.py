# Auto-pairing (handoff section 9): the app offers a pairing code in the inbox, Sterling hands it to that
# partner over live sync, the partner's Sterling saves it in the outbox for its app.
import sim, re
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {} }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
SV = 'SterlingQuestDB = { opts = { chat_sync = 3 } }'
R = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185], account=ACC, sv=SV, pre=COMP + "; " + FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185], account=ACC, sv=SV, pre=COMP + "; " + FRIEND % "Kaelith Emberfall")
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
L.L.eval('function(S) S.SetNickname("Kaelith Emberfall", "Kaelith") end')(L.S) if L.ev('true') else None
R.L.eval('function(S) if S.SetNickname then S.SetNickname("Brannoc Ashvale", "Bran") end end')(R.S)
sent = []
for P in (R, L):
    orig = P.L.globals().SEND
    def wrap(prefix, text, chan, target=None, orig=orig, who=P.name):
        sent.append((who, target, str(text))); return orig(prefix, text, chan, target)
    P.L.globals().SEND = wrap
sim.pump(60)
RG, LG = R.ev('MYGUID'), L.ev('MYGUID')
keyed = lambda P, n: P.L.eval('function(S) return S.KeyState("%s") end' % n)(P.S)
check("live sync swapped keys and ids", keyed(R, "Brannoc Ashvale") == "signed" and keyed(L, "Kaelith Emberfall") == "signed" and R.L.eval('function(S) return S.FindPartner("Brannoc Ashvale").guid end')(R.S) == LG)
CODE, CODE2 = "ABCD-EFGH-JKMN", "PQRS-TVWX-YZ23"
def inbox(P, me, offers="", pairs=""):
    P.lua('SterlingQuestSync_Inbox = { format = 1, written = GetServerTime(), chars = { ["%s"] = { packets = {}, offers = { %s }, pairs = { %s } } } }' % (me, offers, pairs))
    P.L.eval('function(S) S.AppInbox() end')(P.S)
offer = lambda g, c, dt=86400: '{ partner = "%s", code = "%s", expires = GetServerTime() + %d }' % (g, c, dt)
pcodes = lambda: [s for s in sent if s[2].startswith("PCODE")]
inbox(R, RG, offer(LG, CODE))
sim.pump(5)
check("Kaelith's Sterling sends the offered code to Bran, once", len(pcodes()) == 1 and pcodes()[0][1] == "Brannoc Ashvale", pcodes())
stored = L.L.eval('function(S) local c = SterlingQuestDB.appCodes and SterlingQuestDB.appCodes["%s"]; return c and c.code, c and c.time end' % RG)(L.S)
check("Bran's Sterling keeps it under Kaelith's id, with server time", stored[0] == CODE and stored[1] > 1.7e9, stored)
check("Kaelith's side saw the acknowledgement", R.L.eval('function(S) return SterlingQuestDB.codeSent["%s"].acked end' % LG)(R.S) is True)
# never shown: not in chat on either side (chat detail Full), not in the Sync traffic list
allchat = " ".join(str(c) for c in R.chat() + L.chat())
trace = " ".join(str(R.L.eval('function(S) return table.concat(S.sync.trace or {}, " ") end')(R.S)) for _ in [0]) + " ".join(str(L.L.eval('function(S) return table.concat(S.sync.trace or {}, " ") end')(L.S)) for _ in [0])
check("the code never appears in chat (even at Full detail)", CODE not in allchat)
check("or in the Sync traffic list", CODE not in trace and "code hidden" in trace)
# outbox on Bran's side
L.fire("PLAYER_LOGOUT")
codes = L.ev('SterlingQuestSyncOut.characters["%s"].codes' % LG)
c = codes[RG] if codes else None
check("Bran's outbox: codes[Kaelith's id] = { code, time }", c is not None and c.code == CODE and c.time > 1.7e9)
check("code matches the app's pattern", re.match(r"^[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}-[A-HJKMNP-TV-Z2-9]{4}$", c.code) is not None)
R.fire("PLAYER_LOGOUT")
nm = R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].name' % (RG, LG))
check("partner name = full character name", nm == "Brannoc Ashvale", nm)
nk = R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].nick' % (RG, LG))
check("partner nick = the nickname set in Sterling", nk == "Bran", nk)
check("own name = full character name, no nick by default", R.ev('SterlingQuestSyncOut.characters["%s"].name' % RG) == "Kaelith Emberfall" and R.ev('SterlingQuestSyncOut.characters["%s"].nick' % RG) is None, (R.ev('SterlingQuestSyncOut.characters["%s"].name' % RG), R.ev('SterlingQuestSyncOut.characters["%s"].nick' % RG)))
R.lua('SterlingQuestDB.profile.name = "Kae"'); R.fire("PLAYER_LOGOUT")
check("own nick = display name set in the profile", R.ev('SterlingQuestSyncOut.characters["%s"].nick' % RG) == "Kae")
R.lua('SterlingQuestDB.profile.name = "Kaelith"'); R.fire("PLAYER_LOGOUT")
check("first name alone isn't a nick", R.ev('SterlingQuestSyncOut.characters["%s"].nick' % RG) is None)
R.lua('SterlingQuestDB.nicknames = {}'); R.fire("PLAYER_LOGOUT")
check("no nickname set: nick left out", R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].nick' % (RG, LG)) is None)
R.lua('SterlingQuestDB.nicknames = { ["Brannoc Ashvale"] = "Bran" }')
# the same offer again (next login or the app's refresh): not resent
inbox(R, RG, offer(LG, CODE)); sim.pump(70)
check("same code isn't sent again", len(pcodes()) == 1, len(pcodes()))
# a new code from the app: sent, and Bran keeps only the newest
inbox(R, RG, offer(LG, CODE2)); sim.pump(5)
check("a new code is sent", len(pcodes()) == 2)
check("Bran keeps only the newest", L.L.eval('function(S) return SterlingQuestDB.appCodes["%s"].code end' % RG)(L.S) == CODE2)
# pairing done: the app shows an active pair; Bran clears the code, Kaelith forgets what he sent
inbox(L, LG, "", '{ partner = "%s", my_key = "BRANKEYX12345678", partner_key = "KAELKEY123456789", status = "active", change = GetServerTime() }' % RG)
L.fire("PLAYER_LOGOUT")
check("active pair: Bran's code entry is cleared", L.ev('SterlingQuestSyncOut.characters["%s"].codes' % LG) is None)
inbox(R, RG, "", '{ partner = "%s", my_key = "KAELKEY123456789", partner_key = "BRANKEYX12345678", status = "active", change = GetServerTime() }' % LG)
sim.pump(35)
check("offer gone: Kaelith forgets the sent code", R.L.eval('function(S) return SterlingQuestDB.codeSent["%s"] == nil end' % LG)(R.S))
# offline partner: held until they're online
n0 = len(pcodes())
R.lua('C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Brannoc Ashvale", connected = false } end }')
del sim.players["Brannoc Ashvale"]; sim.pump(150)
inbox(R, RG, offer(LG, "ZZZZ-2345-6789")); sim.pump(5)
check("partner looks offline: nothing sent", len(pcodes()) == n0, len(pcodes()) - n0)
sim.players["Brannoc Ashvale"] = L
R.lua('C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Brannoc Ashvale", connected = true } end }')
sim.pump(35)
check("comes online: the 30s check sends it", len(pcodes()) == n0 + 1)
# refused: bad code shapes from the app, expired offers, partners not on the list
n1 = len(pcodes())
inbox(R, RG, offer(LG, "abcd-efgh-jkmn") + "," + offer(LG, "ABCD-EFGH-JKMI") + "," + offer("Player-6800-0BADBEEF", "QQQQ-QQQQ-QQQQ"))
sim.pump(5)
check("lower case, I/L/O/U/0/1, and strangers' offers are never sent", len(pcodes()) == n1, pcodes()[n1:])
inbox(R, RG, offer(LG, "WWWW-WWWW-WWWW", -10)); sim.pump(5)
check("expired offer isn't sent", len(pcodes()) == n1)
# Bran only takes codes from an established partner with a good signature
L.L.eval('function(S) SterlingQuestDB.appCodes = {} end')(L.S)
ok1 = L.L.eval('function(S) return S.AppTakeCode("Kaelith Emberfall", "HHHH-HHHH-HHHH", "00000000deadbeef") end')(L.S)
check("bad signature: refused", ok1 is False and L.ev('next(SterlingQuestDB.appCodes) == nil'))
X = sim.Player("Some Stranger", [(1, "a")], [], account=ACC, pre=COMP)
X.lua('SEND("SterlingQuest", "PCODE\\tHHHH-HHHH-HHHH\\t0123456789abcdef", "WHISPER", "Brannoc Ashvale")'); sim.pump(3)
check("a stranger's code: ignored", L.ev('next(SterlingQuestDB.appCodes) == nil'))
check("no Lua errors", R.errors() + L.errors() + X.errors() == 0, (R.errors(), L.errors(), X.errors()))
print("ALL OK" if ok else "SOME FAILED")
