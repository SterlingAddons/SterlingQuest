# Sterling Quest Sync app: outbox at logout, inbox at login. The "app" here is this test: it checks the
# outbox against the app's rules, then writes the inbox the way the app does.
import sim, re
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {} }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
R = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185, 186, 187], account=ACC, pre=COMP + "; " + FRIEND % "Brannoc Ashvale", questie=True)
L = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185], account=ACC, pre=COMP + "; " + FRIEND % "Kaelith Emberfall")
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(40)
g = lambda P, n: P.L.eval('function(S) local p = S.FindPartner("%s"); return p and p.guid end' % n)(P.S)
RG, LG = R.ev('MYGUID'), L.ev('MYGUID')
check("Kaelith learned Brannoc's character id over live sync", g(R, "Brannoc Ashvale") == LG, g(R, "Brannoc Ashvale"))
check("Brannoc learned Kaelith's", g(L, "Kaelith Emberfall") == RG)

# ---- Kaelith plays alone, then logs out ----
del sim.players["Kaelith Emberfall"]
R.lua('QLOG[#QLOG + 1] = { id = 777, title = "Played alone" }'); R.fire("QUEST_ACCEPTED", 777); R.fire("QUEST_LOG_UPDATE"); sim.pump(5)
R.lua('Questie.db.char.journey = { { Event = "Quest", SubType = "Complete", Quest = 185, Timestamp = 1700000100 }, { Event = "Quest", SubType = "Complete", Quest = 186, Timestamp = 1700000200 } }')
R.fire("PLAYER_LOGOUT")
def lua2py(v):
    if v is None or isinstance(v, (int, float, str, bool)): return v
    t = R.L.globals().type(v) if False else None
    try:
        keys = list(v.keys())
    except Exception:
        return ("NOT DATA", str(v))
    return {k: lua2py(v[k]) for k in keys}
out = lua2py(R.ev('SterlingQuestSyncOut'))
ch = out.get("characters", {}).get(RG)
check("outbox has Kaelith's character under his id", isinstance(ch, dict), list(out.get("characters", {}).keys()))
# ---- the app's rules ----
GUID = re.compile(r"^Player-\d{1,5}-[0-9A-F]{8}$"); PK = re.compile(r"^[A-Za-z0-9()]+$")
NAME = re.compile(r"^[A-Za-z \-']{1,24}$")
def data_only(v):
    if isinstance(v, dict): return all(isinstance(k, (str, int)) and data_only(x) for k, x in v.items())
    return isinstance(v, (int, float, str, bool))
check("outbox is plain data", data_only(out))
check("name and realm pass", NAME.match(ch["name"]) and len(ch["realm"]) <= 64, (ch["name"], ch["realm"]))
check("saved is server time, proto in range", isinstance(ch["saved"], int) and ch["saved"] > 1.7e9 and 1 <= ch["proto"] <= 10000)
check("every partner key is a character id", all(GUID.match(k) for k in ch["partners"]))
pk = ch["partners"].get(LG, {})
check("a packet for Brannoc, in the print alphabet, under 64 KB", PK.match(pk.get("packet", "")) and len(pk["packet"]) <= 65536, len(pk.get("packet", "")))
check("change is a whole number >= 0", isinstance(pk.get("change"), int) and pk["change"] >= 0)
check("self copy passes the packet rule", PK.match(ch.get("self", "")) is not None)
check("applied is ids to numbers", all(GUID.match(k) and isinstance(n, int) for k, n in ch.get("applied", {}).items()))
raw = repr(out)
def allkeys(t, acc):
    if isinstance(t, dict):
        for k, v in t.items(): acc.add(k); allkeys(v, acc)
    return acc
check("no keys from SterlingQuestDB in the outbox", not ({"k1", "k2"} & allkeys(out, set())))   # (a packet's text can contain "k1" by chance)
packet = pk["packet"]

# ---- the app pairs them: keys through the inbox; Brannoc logs in later ----
KR, KL = "KAELKEY0123456789ab", "BRANKEYX0123456789"
def inbox(P, me, packets, pairs, app='app = { version = "0.1.6", latest = "0.1.7", sterling_latest = "0.2.38" }'):
    pk = ",".join('{ seq = %d, from = "%s", kind = "%s", time = 1794770000, proto = 6, data = "%s" }' % p for p in packets)
    pr = ",".join('{ partner = "%s", my_key = %s, partner_key = %s, status = "%s", change = %d }' % p for p in pairs)
    P.lua('SterlingQuestSync_Inbox = { format = 1, written = 1794770123, %s, chars = { ["%s"] = { packets = { %s }, pairs = { %s } } } }' % (app, me, pk, pr))
    P.L.eval('function(S) S.AppInbox() end')(P.S)
has = lambda P, who, q: P.L.eval('function(S) local s = S.snaps["%s"]; return s ~= nil and s.log[%d] ~= nil end' % (who, q))(P.S)
# the packet Kaelith wrote was signed with their game key (no app pair yet): accepted
inbox(L, LG, [(100, RG, "partner", packet)], [])
check("Brannoc gets Kaelith's solo quest from the app", has(L, "Kaelith Emberfall", 777))
chat = " ".join(str(c) for c in L.chat())
check("she's told about the app update (and not Sterling, she's on the latest... or is told)", "Sterling Quest Sync Companion update available" in chat, chat[-300:])
# applying the same packet again is harmless; an older number is ignored
L.lua('S_SNAPSEQ = nil')
inbox(L, LG, [(100, RG, "partner", packet)], [])
check("same packet again: nothing breaks", has(L, "Kaelith Emberfall", 777) and L.errors() == 0)

# ---- now paired in the app: Kaelith's next copy is signed with the pair key ----
inbox(R, RG, [], [(LG, '"%s"' % KR, '"%s"' % KL, "active", 1794590000)])
R.lua('QLOG[#QLOG + 1] = { id = 778, title = "Second solo" }'); R.fire("QUEST_ACCEPTED", 778); R.fire("QUEST_LOG_UPDATE"); sim.pump(5)
R.fire("PLAYER_LOGOUT")
p2 = R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].packet' % (RG, LG))
inbox(L, LG, [(101, RG, "partner", p2)], [(RG, '"%s"' % KL, '"%s"' % KR, "active", 1794590000)])
check("signed with the pair key: Brannoc takes it", has(L, "Kaelith Emberfall", 778))
check("applied number stored for Kaelith", L.L.eval('function(S) return SterlingQuestDB.appApplied["%s"] end' % RG)(L.S) == 101)
# a lower number never applies
L.L.eval('function(S) S.snaps["Kaelith Emberfall"].log[778] = nil end')(L.S)
inbox(L, LG, [(99, RG, "partner", p2)], [(RG, '"%s"' % KL, '"%s"' % KR, "active", 1794590000)])
check("an older server number is not applied", not has(L, "Kaelith Emberfall", 778))

# ---- keys that don't match: missing key, resync ----
inbox(L, LG, [(102, RG, "partner", p2)], [(RG, '"WRONGKEY0000000"', '"WRONGKEY1111111"', "active", 1794590000)])
L.L.eval('function(S) local p = S.FindPartner("Kaelith Emberfall"); p.k1 = "aaaa"; p.k2 = "bbbb" end')(L.S)
inbox(L, LG, [(103, RG, "partner", p2)], [(RG, '"WRONGKEY0000000"', '"WRONGKEY1111111"', "active", 1794590000)])
check("wrong key: shown as missing key, resync", L.L.eval('function(S) return S.AppProblem("Kaelith Emberfall") end')(L.S) == "resync")
inbox(L, LG, [], [(RG, 'nil', 'nil', "ended", 1794595000)])
check("ended pairing: missing key, resync", L.L.eval('function(S) return S.AppProblem("Kaelith Emberfall") end')(L.S) == "resync")
check("ended pairing doesn't remove the partner", L.L.eval('function(S) return S.FindPartner("Kaelith Emberfall") ~= nil end')(L.S))

# ---- a pairing made in the app adds the partner in game ----
D = sim.Player("Tovak Stoneroot", [(300, "Q")], [1], account=ACC, pre=COMP)
DG = D.ev('MYGUID')
del sim.players["Tovak Stoneroot"]
KD = "TOVAKKEY012345678"
inbox(R, RG, [], [(LG, '"%s"' % KR, '"%s"' % KL, "active", 1794590000), (DG, '"%s"' % KR, '"%s"' % KD, "active", 1794600000)])
R.fire("PLAYER_LOGOUT")
pr = R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"]' % (RG, DG))
check("no packet for someone not on the list yet", pr is None)
# Tovak's side: she has Kaelith listed with his id (as after the app pairing), writes her outbox
D.L.eval('function(S) local p = S.AddPartner("Kaelith Emberfall", true); p.guid = "%s" end' % RG)(D.S)
inbox(D, DG, [], [(RG, '"%s"' % KD, '"%s"' % KR, "active", 1794600000)])
D.fire("PLAYER_LOGOUT")
dp = D.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].packet' % (DG, RG))
inbox(R, RG, [(200, DG, "partner", dp)], [(LG, '"%s"' % KR, '"%s"' % KL, "active", 1794590000), (DG, '"%s"' % KR, '"%s"' % KD, "active", 1794600000)])
check("Kaelith gets Tovak added from the app pairing, with her log", R.L.eval('function(S) local p = S.FindPartner("Tovak Stoneroot"); return p ~= nil and p.guid == "%s" end' % DG)(R.S) and has(R, "Tovak Stoneroot", 300))

# ---- removing in game writes a removal mark with the server time ----
R.L.eval('function(S) S.RemovePartner("Tovak Stoneroot") end')(R.S)
R.fire("PLAYER_LOGOUT")
rm = lua2py(R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"]' % (RG, DG)))
check("removal mark: removed = true, change = server time", rm and rm.get("removed") is True and rm.get("change", 0) > 1.7e9, rm)
# and a stale inbox (pairing older than the removal) doesn't bring her back
inbox(R, RG, [(201, DG, "partner", dp)], [(DG, '"%s"' % KR, '"%s"' % KD, "active", 1794600000)])
check("old pairing doesn't undo the removal", R.L.eval('function(S) return S.FindPartner("Tovak Stoneroot") == nil end')(R.S))

# ---- self copy: the other PC's finish times merge ----
selfp = R.ev('SterlingQuestSyncOut.characters["%s"].self' % RG)
R2 = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185, 186, 187], account=ACC, pre=COMP, questie=True)
R2.lua('Questie.db.char.journey = { { Event = "Quest", SubType = "Complete", Quest = 187, Timestamp = 1700000150 } }')
inbox(R2, RG, [(300, RG, "self", selfp)], [])
rank = R2.L.eval('function(S) local r = S.CompletedRank(); return r[185], r[187], r[186] end')(R2.S)
check("other PC's finish order merges by time (185 < 187 < 186)", tuple(rank) == (1, 2, 3), rank)

# ---- broken inboxes never error ----
for bad in ['SterlingQuestSync_Inbox = "x"', 'SterlingQuestSync_Inbox = { format = 1, chars = { ["%s"] = { packets = { { seq = "a", from = 5, data = {} }, "x" }, pairs = { 7 } } } }' % LG,
            'SterlingQuestSync_Inbox = { format = 1, chars = { ["%s"] = { packets = { { seq = 999, from = "%s", kind = "partner", data = "AAAA" } } } } }' % (LG, RG),
            'SterlingQuestSync_Inbox = nil']:
    L.lua(bad); L.L.eval('function(S) S.AppInbox() end')(L.S)
check("broken inboxes are ignored without errors", L.errors() == 0, L.errors())
# without the companion, nothing happens and nothing errors
N = sim.Player("Nobody Here", [(1, "a")], [], account=ACC)
N.fire("PLAYER_LOGOUT"); N.L.eval('function(S) S.AppInbox() end')(N.S)
check("no companion: quiet", N.errors() == 0 and N.ev('SterlingQuestSyncOut') is None)
check("no Lua errors", R.errors() + L.errors() + D.errors() + R2.errors() == 0, (R.errors(), L.errors(), D.errors(), R2.errors()))
print("ALL OK" if ok else "SOME FAILED")
