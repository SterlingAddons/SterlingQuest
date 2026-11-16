import sim, re
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
SV = ACC + '\nSterlingQuestDB = { opts = { chat_sync = 1 }, partners = { { name = "Kaelith", on = true } } }'
P = sim.Player("Brannoc Ashvale", [(1, "A")], [], level=41, sv=SV)
L, S = P.L, P.S
def do(code): return L.eval("function(S) " + code + " end")(S)
do('STATE = "on"; SRC = "guild"; S.PartnerStatus = function(n) if STATE == "on" then return true, SRC elseif STATE == "off" then return false, SRC else return false, nil end end; S.RequestPartner = function() end; S.AutoSync = function() end')
sim.pump(40)
SEEN = [0]
def notes():
    SEEN[0] += sum(1 for c in P.chat() if "is online" in str(c)); return SEEN[0]
P.fire("GUILD_ROSTER_UPDATE"); base = notes()
check("first sighting after login can note once", base <= 1, base)
def roster(state, wait):
    do('STATE = "%s"' % state); sim.pump(wait); P.fire("GUILD_ROSTER_UPDATE")
# roster can't find them for a long stretch (empty list), then finds them
for _ in range(6): roster("unknown", 60)
roster("on", 5)
check("an empty roster read for 6 minutes doesn't make a new 'is online'", notes() == base, notes())
# they were whispering us recently, roster says offline for a while
do('S.LastHeard = function() return 100 end')
for _ in range(5): roster("off", 60)
roster("on", 5)
check("heard from them in the last 10 min: no 'is online'", notes() == base, notes())
# a real logout: roster says offline, nothing heard, 4 minutes, then back
do('S.LastHeard = function() return nil end')
sim.pump(700)
for _ in range(5): roster("off", 60)
roster("on", 5)
check("a real logout and back still notes it", notes() == base + 1, notes())
# Quiet chat detail: no line
do('SterlingQuestDB.opts.chat_sync = 0')
sim.pump(700)
for _ in range(5): roster("off", 60)
roster("on", 5)
check("Quiet sync chat: no line", notes() == base + 1, notes())
check("no Lua errors", P.errors() == 0, P.errors())
print("ALL OK" if ok else "FAILED")
