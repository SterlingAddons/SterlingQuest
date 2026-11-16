import sim, re, random
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
random.seed(3)
R = sim.Player("Kaelith Emberfall", [(5000 + k, "Q%d" % k) for k in range(20)], random.sample(range(1, 3000), 450), account=ACC, level=38)
D = sim.Player("Tovak Stoneroot", [(6000 + k, "D%d" % k) for k in range(18)], random.sample(range(1, 3000), 420), account=ACC, level=39)
sim.pump(40)
# Tovak types Kaelith's name in the Add window: adds him and invites
D.lua('SlashCmdList.STERLINGQUEST("partner Kaelith Emberfall"); STQ_S = ...') if False else None
D.L.eval('function(S) SlashCmdList.STERLINGQUEST("partner Kaelith Emberfall"); S.Invite("Kaelith Emberfall") end')(D.S)
sim.pump(3)
shown = R.ev('SterlingQuestInvite ~= nil and SterlingQuestInvite:IsShown()')
check("Kaelith gets the invite prompt", shown)
if shown: R.lua('SterlingQuestInvite.yes:Click()')
def live(P, who): return P.L.eval('function(S) local s = S.snaps["%s"]; return s ~= nil and s.source == "live" end' % who)(P.S)
t = 0
while t < 180 and not (live(R, "Tovak Stoneroot") and live(D, "Kaelith Emberfall")): sim.pump(1); t += 1
rc = [clean(c) for c in R.chat()]; dc = [clean(c) for c in D.chat()]
check("Kaelith has Tovak's log", live(R, "Tovak Stoneroot"))
check("Tovak has Kaelith's log", live(D, "Kaelith Emberfall"))
check("nobody got muted", not any("Ignoring" in c for c in rc + dc), [c for c in rc + dc if "Ignoring" in c])
print("  took", t, "s")
for c in rc[-12:]: print("  R:", c)
for c in dc[-12:]: print("  D:", c)

# the real case: Tovak invites, Kaelith only accepts 8 minutes later (fight, away), and Tovak reloads in between
sim.reset() if False else None
R2 = sim.Player("Kaelith Emberfall", [(5000 + k, "Q%d" % k) for k in range(20)], random.sample(range(1, 3000), 450), account=ACC, level=38)
D2 = sim.Player("Tovak Stoneroot", [(6000 + k, "D%d" % k) for k in range(18)], random.sample(range(1, 3000), 420), account=ACC, level=39)
sim.pump(40)
D2.L.eval('function(S) S.Invite("Kaelith Emberfall") end')(D2.S)
sim.pump(480)
inv = D2.ev('SterlingQuestDB.invites and SterlingQuestDB.invites["Kaelith Emberfall"] ~= nil')
check("Tovak's invite is kept in saved data", inv)
check("Kaelith's prompt is still up 8 minutes later", R2.ev('SterlingQuestInvite ~= nil and SterlingQuestInvite:IsShown()'))
R2.lua('SterlingQuestInvite.yes:Click()')
t = 0
while t < 180 and not (live(R2, "Tovak Stoneroot") and live(D2, "Kaelith Emberfall")): sim.pump(1); t += 1
rc = [clean(c) for c in R2.chat()]; dc = [clean(c) for c in D2.chat()]
check("a late accept still pairs them: Kaelith has Tovak's log", live(R2, "Tovak Stoneroot"))
check("...and Tovak has Kaelith's", live(D2, "Kaelith Emberfall"))
check("nobody muted", not any("Ignoring" in c for c in rc + dc))
check("invite cleared after use", not D2.ev('SterlingQuestDB.invites["Kaelith Emberfall"] ~= nil'))
check("no Lua errors", R2.errors() == 0 and D2.errors() == 0)

# today's case after the reload: Kaelith has Tovak listed, Tovak lost the invite and doesn't have Kaelith.
R3 = sim.Player("Kaelith Emberfall", [(5000 + k, "Q%d" % k) for k in range(20)], random.sample(range(1, 3000), 450), account=ACC, level=38)
D3 = sim.Player("Tovak Stoneroot", [(6000 + k, "D%d" % k) for k in range(18)], random.sample(range(1, 3000), 420), account=ACC, level=39)
sim.pump(40)
R3.L.eval('function(S) S.AddPartner("Tovak Stoneroot", true); S.SyncWith("Tovak Stoneroot", "full") end')(R3.S)
sim.pump(30)
rc = [clean(c) for c in R3.chat()]; dc = [clean(c) for c in D3.chat()]
check("Tovak isn't told she's ignoring Kaelith", not any("Ignoring" in c for c in dc), dc)
check("Tovak is told Kaelith is trying to sync", any("trying to sync" in c for c in dc), dc)
check("Kaelith is told Tovak hasn't added him", any("hasn't added you" in c for c in rc), rc)
# Tovak adds Kaelith with + Add (adds and invites); Kaelith's copy answers by itself
D3.L.eval('function(S) SlashCmdList.STERLINGQUEST("partner Kaelith Emberfall"); S.Invite("Kaelith Emberfall") end')(D3.S)
t = 0
while t < 120 and not (live(R3, "Tovak Stoneroot") and live(D3, "Kaelith Emberfall")): sim.pump(1); t += 1
check("after she adds him, both have each other's log (%ds)" % t, live(R3, "Tovak Stoneroot") and live(D3, "Kaelith Emberfall"))
check("no Lua errors (case 3)", R3.errors() == 0 and D3.errors() == 0)
print("ALL OK" if ok else "FAILED")
