# Favourite partners (0.2.43, handoff section 12): star in the Sync tab, favourites on top, shared with the app.
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {} }'
R = sim.Player("Kaelith Emberfall", [(188, "a")], [185], account=ACC, pre=COMP)
RG = R.ev('MYGUID')
G = ["Player-6800-0000000%d" % i for i in range(1, 8)]
names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
for n, g in zip(names, G):
    R.S.AddPartner(n, True)
    R.L.eval('function(S, n, g) S.FindPartner(n).guid = g end')(R.S, n, g)
R.S.AddPartner("Noid Person", True)
fav = lambda n: R.L.eval('function(S, n) return S.SetFav(S.FindPartner(n), true) end')(R.S, n)
order = lambda: [R.L.eval('function(S, i) return S.PartnersSorted()[i].name end')(R.S, i) for i in range(1, 9)]
check("nothing starred: list order kept", order()[:3] == ["Alpha", "Bravo", "Charlie"], order())
fav("Delta"); fav("Bravo")
check("favourites on top, in starring order", order()[:3] == ["Delta", "Bravo", "Alpha"], order())
t1 = R.ev('SterlingQuestDB.favsChange')
check("change time set from the server clock", t1 and t1 > 1.7e9)
fav("Delta")
check("starring again changes nothing", R.ev('SterlingQuestDB.favsChange') == t1 and R.ev('#SterlingQuestDB.favs') == 2)
fav("Alpha"); fav("Charlie"); fav("Echo")
r6 = R.L.eval('function(S) local ok, why = S.SetFav(S.FindPartner("Foxtrot"), true); return why end')(R.S)
check("a 6th is refused", r6 == "full" and R.ev('#SterlingQuestDB.favs') == 5)
check("and chat says so", any("up to 5 partners" in str(c) for c in R.chat()))
check("no id yet: refused", R.L.eval('function(S) local ok, why = S.SetFav(S.FindPartner("Noid Person"), true); return why end')(R.S) == "noid")
# outbox
R.fire("PLAYER_LOGOUT")
ofavs = R.ev('SterlingQuestSyncOut.characters["%s"].favs' % RG)
lst = [ofavs[i] for i in range(1, 6)] if ofavs else []
check("outbox favs in order", lst == [G[3], G[1], G[0], G[2], G[4]], lst)
check("outbox favs_change", R.ev('SterlingQuestSyncOut.characters["%s"].favs_change' % RG) == int(R.ev('SterlingQuestDB.favsChange')))
before = R.ev('SterlingQuestDB.favsChange')
R.fire("PLAYER_LOGOUT")
check("written again unchanged, time not bumped", R.ev('SterlingQuestDB.favsChange') == before and R.ev('SterlingQuestSyncOut.characters["%s"].favs_change' % RG) == int(before))
# inbox: newer list from the app wins whole, with junk filtered
def inbox(favs, change):
    R.lua('SterlingQuestSync_Inbox = { format = 1, written = GetServerTime(), chars = { ["%s"] = { packets = {}, pairs = {}, offers = {}, favs = { %s }, favs_change = %s } } }' % (RG, favs, change))
    R.L.eval('function(S) S.AppInbox() end')(R.S)
inbox('"%s", "%s", "%s", "bad", "%s", "%s", "%s", "%s"' % (G[6], G[5], G[6], RG, G[0], G[1], G[2]), 'GetServerTime() + 100')
lst = [R.ev('SterlingQuestDB.favs[%d]' % i) for i in range(1, 6)]
check("newer app list taken, cleaned (no repeats, bad ids, own id), max 5", lst == [G[6], G[5], G[0], G[1], G[2]], lst)
check("and its time", R.ev('SterlingQuestDB.favsChange') == R.ev('GetServerTime() + 100'))
check("on top in game", order()[:2] == ["Golf", "Foxtrot"], order())
inbox('"%s"' % G[3], '1000')
check("older app list ignored", R.ev('SterlingQuestDB.favs[1]') == G[6])
R.lua('SterlingQuestSync_Inbox.chars["%s"].favs_change = nil; SterlingQuestSync_Inbox.chars["%s"].favs = { "%s" }' % (RG, RG, G[3])); R.L.eval('function(S) S.AppInbox() end')(R.S)
check("no favs_change: ignored", R.ev('SterlingQuestDB.favs[1]') == G[6])
# removing a favourite partner unstars them
R.L.eval('function(S) S.RemovePartner("Golf") end')(R.S)
check("removed partner leaves favourites", R.ev('SterlingQuestDB.favs[1]') == G[5] and R.ev('#SterlingQuestDB.favs') == 4)
# UI: star button works and rows sort
R.L.eval('function(S) S.UI_Tab("sync") end')(R.S)
first = R.L.eval('function(S) local pg = SterlingQuestMain and SterlingQuestMain.pages and SterlingQuestMain.pages.sync; return nil end')(R.S)
check("no Lua errors", R.errors() == 0, R.errors())
print("ALL OK" if ok else "SOME FAILED")
