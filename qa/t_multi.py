import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
import sim, re, random
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
random.seed(11)
names = ["Kaelith Emberfall", "Brannoc Ashvale", "Tovak", "Bran", "Grukk", "Zal Jin", "Mira", "Tobben", "Ashka", "Weller", "Nyx"]
P = {}
for i, n in enumerate(names):
    done = random.sample(range(1, 3000), 150 + i * 60)
    log = [(5000 + i * 10 + k, "Quest %d-%d" % (i, k)) for k in range(12)]
    P[n] = sim.Player(n, log, done, account=ACC, level=20 + i)
me = P["Kaelith Emberfall"]
sim.pump(15)
# invites: Kaelith Emberfall invites everyone; each accepts through the prompt
for n in names[1:]:
    me.S.Invite(n)
sim.pump(3)
accepted = 0
for n in names[1:]:
    q = P[n]
    shown = q.ev('SterlingQuestInvite ~= nil and SterlingQuestInvite:IsShown()')
    if shown: q.lua('SterlingQuestInvite.yes:Click()'); accepted += 1
check("all ten got an invite prompt and accepted", accepted == 10, accepted)
t = 0
def all_synced():
    return me.L.eval('function(S) local n = 0; for _, p in ipairs(S.Partners()) do local s = S.snaps[p.name]; if s and s.source == "live" then n = n + 1 end end return n end')(me.S)
while t < 240 and all_synced() < 10:
    sim.pump(1); t += 1
check("ten partners on the list", me.ev('#SterlingQuestDB.partners') == 10, me.ev('#SterlingQuestDB.partners'))
check("all ten fully synced with me (%ds of game time)" % t, all_synced() == 10, all_synced())
def held():
    return sum(1 for n in names[1:] if P[n].L.eval('function(S) local s = S.snaps["Kaelith Emberfall"]; return s ~= nil and s.source == "live" end')(P[n].S))
t2 = 0
while t2 < 240 and (held() < 10 or not all(me.S.KeyState(n) == "signed" for n in names[1:])):
    sim.pump(1); t2 += 1
print("   my log reached all ten after %ds more (ChatThrottleLib pacing ten full copies)" % t2)
both = sum(1 for n in names[1:] if P[n].L.eval('function(S) local s = S.snaps["Kaelith Emberfall"]; return s ~= nil and s.source == "live" end')(P[n].S))
check("and all ten hold my log", both == 10, both)
for n in names[1:]:
    q = P[n]
    want = q.ev('(function() local n = 0; for _ in pairs(QDONE) do n = n + 1 end return n end)()')
    got = me.L.eval('function(S, n) local c = 0; for _ in pairs(S.snaps[n].completed) do c = c + 1 end return c end')(me.S, n)
    if want != got: check("finished count for " + n, False, (want, got))
check("every partner's finished-quest count is exact", True)
check("keys swapped with all ten", all(me.S.KeyState(n) == "signed" for n in names[1:]))
check("nobody got muted for flooding", not any("flood" in clean(c).lower() or "muted" in clean(c).lower() for n in names for c in P[n].L.globals().CHAT.values()))
# the eleventh
x = sim.Player("Eleventh", [], [1, 2], account=ACC)
sim.pump(12)
me.chat()
r = me.S.AddPartner("Eleventh", True)
check("an eleventh partner is refused", r is None and me.ev('#SterlingQuestDB.partners') == 10)
check("...with a clear chat line", any("Sync list is full" in clean(c) for c in me.chat()))
x.S.Invite("Kaelith Emberfall"); sim.pump(3)
check("an invite to a full list shows the prompt (they can still decide)", me.ev('SterlingQuestInvite:IsShown()'))
me.lua('SterlingQuestInvite.yes:Click()'); sim.pump(3)
check("accepting with a full list adds nobody", me.ev('#SterlingQuestDB.partners') == 10)
xc = [clean(c) for c in x.chat()]
check("the inviter is told not now", any("said not now" in c for c in xc), xc)
# a stranger can't push data in
x.L.eval('function(S) S.AddPartner("Kaelith Emberfall", true); S.SyncWith("Kaelith Emberfall", "full") end')(x.S); sim.pump(8)
check("a stranger's sync attempt stores nothing", me.L.eval('function(S) return S.snaps["Eleventh"] == nil end')(me.S))
# UI with ten partners
me.L.eval('function(S) S.UI_Toggle(true); S.UI_Tab("sync"); S.UI_Update() end')(me.S)
me.L.execute(open(_os.path.join(QA, "audit.lua")).read())
out = me.L.eval('function() SterlingQuestFrame.notice._outsideOK = true; return table.concat(AUDIT(SterlingQuestFrame, "sync x10"), "\\n") end')()
check("Sync tab with ten partners: nothing overlaps or spills", out == "", out)
check("the list shows six and says how many more", "4 more" in clean(me.L.eval('function(S) return S.UI_Page("sync").more:GetText() end')(me.S)))
check("header counts 10/10", "10/10" in clean(me.L.eval('function(S) return S.UI_Page("sync").plabel:GetText() end')(me.S)))
me.L.eval('function(S) S.UI_AddPartner() end')(me.S)
check("Add window says the list is full and disables Add", "full" in clean(me.ev('SterlingQuestAddPartner.hint:GetText()')) and not me.ev('SterlingQuestAddPartner.go:IsEnabled()'))
# everyone changes something at once; I get all of it
for i, n in enumerate(names[1:]):
    P[n].lua('QDONE[9000 + %d] = true' % i); P[n].fire("QUEST_TURNED_IN", 9000 + i)
sim.pump(15)
got = sum(1 for i, n in enumerate(names[1:]) if me.L.eval('function(S, n, q) return S.snaps[n].completed[q] == true end')(me.S, n, 9000 + i))
check("a change from each of ten partners at once all arrive", got == 10, got)
# Everyone window with 11 columns
me.L.eval('function(S) S.UI_Everyone() end')(me.S)
out = me.L.eval('function() return table.concat(AUDIT(SterlingQuestEveryone, "everyone x10"), "\\n") end')()
print("   everyone window findings:", out.replace("\n", " | ")[:400] or "none")
tot = sum(p.errors() for p in P.values()) + x.errors()
check("no Lua errors on any of the 12 clients", tot == 0, tot)
snags = [clean(c) for p in list(P.values()) + [x] for c in p.L.globals().CHAT.values() if "snag" in c]
check("no snags", not snags, snags[:3])
print("   messages I sent / received this session:", me.L.eval('function(S) return S.sync.sent .. " / " .. S.sync.recv .. ", refused " .. tostring(S.sync.throttled or 0) end')(me.S), " too-long refused by game:", me.ev("TOOLONG"))
print("ALL OK" if ok else "SOME FAILED")
