import sim, re
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
# ---------- a brand new install: nothing saved at all
P = sim.Player("Newbie", [(188, "Tiger Mastery")], [1, 2, 3])
L, S = P.L, P.S
def do(code): return L.eval("function(S) " + code + " end")(S)
check("nothing pops up in the first seconds", not P.ev('SterlingQuestWelcome ~= nil and SterlingQuestWelcome:IsShown()'))
sim.pump(12)
lines = [clean(c) for c in P.chat()]
check("welcome page appears once, a few seconds in", P.ev('SterlingQuestWelcome:IsShown()'))
check("first login is quiet: only the two works-with notes", len(lines) == 2 and all("isn't installed" in l for l in lines), lines)
check("no tip while the welcome page is up", not P.ev('SterlingQuestCoach ~= nil and SterlingQuestCoach:IsShown()'))
do('SterlingQuestWelcome.go:Click()')
check("Take the tour: welcome closes, tour opens on step 1", (not P.ev('SterlingQuestWelcome:IsShown()')) and P.ev('SterlingQuestCoach:IsShown()') and "Step 1 of 3" in P.ev('SterlingQuestCoach.step:GetText()'))
check("step 1 is the Sync tab with the spotlight on + Add", do('return S.UI_CurrentTab()') == "sync" and "Add a friend" in P.ev('SterlingQuestCoach.headline:GetText()'))
check("Back is hidden on the first step", not P.ev('SterlingQuestCoach.back:IsShown()'))
do('SterlingQuestCoach.next:Click()')
check("step 2: Catch-up, and it says Questie is missing", do('return S.UI_CurrentTab()') == "catchup" and "needs Questie" in clean(P.ev('SterlingQuestCoach.body:GetText()')))
do('SterlingQuestCoach.back:Click()'); check("Back returns to step 1", do('return S.UI_CurrentTab()') == "sync")
do('S.UI_Tab("path")'); check("clicking a tab mid-tour jumps to that tab's step", "Step 3 of 3" in P.ev('SterlingQuestCoach.step:GetText()'))
check("last step says Finish", P.ev('SterlingQuestCoach.next:GetText()') == "Finish")
do('SterlingQuestCoach.next:Click()')
check("Finish closes the tour and remembers it", (not P.ev('SterlingQuestCoach:IsShown()')) and P.ev('SterlingQuestAccountDB.tour == true'))
check("toured tabs get no tip afterwards", do('S.UI_Tab("sync"); S.UI_Tab("catchup"); S.UI_Tab("path"); return SterlingQuestCoach:IsShown()') == False)
do('S.UI_Tab("sessions")')
check("Sessions (not in the tour) shows its one-time tip", P.ev('SterlingQuestCoach:IsShown()') and "Sessions" in P.ev('SterlingQuestCoach.headline:GetText()') and P.ev('SterlingQuestCoach.title:GetText()') == "Tip")
check("the tip has no Tour button once the tour is done", not P.ev('SterlingQuestCoach.skip:IsShown()'))
do('S.UI_Tab("sync")'); check("a tip closes when you leave its tab", not P.ev('SterlingQuestCoach:IsShown()'))
do('S.UI_Tab("sessions")'); check("and never comes back", not P.ev('SterlingQuestCoach:IsShown()'))
check("welcome doesn't come back on the next entering-world", (P.fire("PLAYER_ENTERING_WORLD", False, True), sim.pump(12), not P.ev('SterlingQuestWelcome:IsShown()'))[2])
lines = [clean(c) for c in P.chat()]
check("works-with notes are said once, not at every loading screen", not any("isn't installed" in l for l in lines), lines)
# ---------- help window
do('SterlingQuestFrame.helpBtn:Click()')
check("? opens Help on Getting started", P.ev('SterlingQuestHelp:IsShown()') and P.ev('SterlingQuestHelp.key') == "start")
n = 0
for k in ["sync", "offline", "catchup", "path", "record", "status", "trouble", "credits"]:
    do(f'for _, b in ipairs(SterlingQuestHelp.nav) do if b.key == "{k}" then b:Click() end end')
    if P.ev('SterlingQuestHelp.key') == k: n += 1
check("all nine Help sections open", n == 8)
txt = do('local t = {}; for _, l in ipairs(SterlingQuestHelp.lines) do if l:IsShown() then t[#t + 1] = l:GetText() end end; return table.concat(t, " ")')
check("Credits names Questie, TomTom, ChatThrottleLib, LibDeflate", all(w in txt for w in ["Questie", "TomTom", "ChatThrottleLib", "LibDeflate"]))
check("Credits doesn't mention Leatrix", "Leatrix" not in txt)
alltext = ""
for k in ["start", "sync", "offline", "catchup", "path", "record", "status", "trouble", "credits"]:
    do(f'S.UI_Help("{k}")')
    alltext += do('local t = {}; for _, l in ipairs(SterlingQuestHelp.lines) do if l:IsShown() then t[#t + 1] = l:GetText() end end; return table.concat(t, " ")')
check("no em dashes anywhere in Help", "—" not in alltext and "–" not in alltext)
do('S.UI_Help("trouble")')
check("Troubleshooting has the two print buttons, other sections don't", P.ev('SterlingQuestHelp.state:IsShown()') and (do('S.UI_Help("path"); return SterlingQuestHelp.state:IsShown()') == False))
do('S.UI_Help("trouble"); SterlingQuestHelp.state:Click(); SterlingQuestHelp.traffic:Click()')
check("print buttons work", any("STQ state" in c for c in P.chat()))
do('SterlingQuestHelp.tour:Click()')
check("Replay the tour starts it again", P.ev('SterlingQuestCoach:IsShown()') and "Step 1" in P.ev('SterlingQuestCoach.step:GetText()'))
do('SterlingQuestCoach.close:Click()')
check("closing the tour with X ends it cleanly", (not P.ev('SterlingQuestCoach:IsShown()')) and do('return S.TourRunning()') == False and P.ev('SterlingQuestAccountDB.tour == true'))
do('SterlingQuestHelp.welcome:Click()'); check("Welcome page reopens from Help", P.ev('SterlingQuestWelcome:IsShown()'))
do('SterlingQuestWelcome.later:Click()')
# ---------- slash commands reach the same things
for c in ["help", "tour", "welcome", "offline", "add", "options", "bogus"]:
    okc = L.eval('function(c) return pcall(SlashCmdList.STERLINGQUEST, c) end')(c)
    if not (okc if isinstance(okc, bool) else okc[0]): check("/st " + c, False)
check("slash commands for help, tour, welcome, offline work", True)
check("/st tabs, mapinfo, raceinfo are gone (dev tools)", all(any("Commands:" in clean(x) for x in (P.chat(), L.eval('function(c) SlashCmdList.STERLINGQUEST(c) end')(c), P.chat())[2]) for c in ["tabs", "mapinfo", "raceinfo"]))
do('for _, w in ipairs(S.windows) do w:Hide() end')
# ---------- skipping the tour: every tab gets its tip once
Q = sim.Player("Skipper", [], [])
sim.pump(12)
def qdo(code): return Q.L.eval("function(S) " + code + " end")(Q.S)
qdo('SterlingQuestWelcome.later:Click()')
check("Skip for now: the tab you're on gives its tip straight away", Q.ev('SterlingQuestCoach:IsShown()') and Q.ev('SterlingQuestCoach.tipFor') == qdo('return S.UI_CurrentTab()'))
check("the tip offers the tour", Q.ev('SterlingQuestCoach.skip:IsShown()') and Q.ev('SterlingQuestCoach.skip:GetText()') == "Tour")
seen = 0
for t in ["path", "sessions", "sync", "catchup"]:
    qdo(f'S.UI_Tab("{t}")')
    if Q.ev('SterlingQuestCoach:IsShown()') and Q.ev('SterlingQuestCoach.tipFor') == t: seen += 1
check("the other three tabs each tip once", seen == 3, seen)
qdo('SterlingQuestCoach.next:Click()')
again = 0
for t in ["path", "sessions", "sync", "catchup"]:
    qdo(f'S.UI_Tab("{t}")')
    if Q.ev('SterlingQuestCoach:IsShown()'): again += 1
check("and never again", again == 0)
# ---------- account-wide: a second character on the same account sees none of it
acc = Q.L.eval('function(S) return S.Serialize(SterlingQuestAccountDB) end')(Q.S)
R = sim.Player("Altchar", [], [], pre='ACCRAW = %r' % acc)
R.L.eval('function(S) local a = S.Deserialize(ACCRAW); for k, v in pairs(a) do SterlingQuestAccountDB[k] = v end end')(R.S)
sim.pump(12)
check("flags are account-wide (welcomed, hints carry to another character)", R.ev('SterlingQuestAccountDB.welcomed == true and SterlingQuestAccountDB.hints.path == true'))
# ---------- combat: nothing pops up mid-fight
C = sim.Player("Fighter", [], [], pre='INCOMBAT = true')
sim.pump(12)
check("in combat at login: no welcome page yet", not C.ev('SterlingQuestWelcome ~= nil and SterlingQuestWelcome:IsShown()'))
C.lua('INCOMBAT = false'); C.fire("PLAYER_REGEN_ENABLED")
check("it appears when the fight ends", C.ev('SterlingQuestWelcome:IsShown()'))
C.L.eval('function(S) SterlingQuestWelcome.later:Click(); SterlingQuestCoach:Hide(); INCOMBAT = true; S.TourStart() end')(C.S)
check("tour asked for in combat waits", not C.ev('SterlingQuestCoach:IsShown()'))
C.lua('INCOMBAT = false'); C.fire("PLAYER_REGEN_ENABLED")
check("and starts after", C.ev('SterlingQuestCoach:IsShown()'))
C.L.eval('function(S) S.TourEnd(false); INCOMBAT = true; S.UI_InvitePrompt("Someone", "123456") end')(C.S)
check("an invite during combat doesn't pop up", not C.ev('SterlingQuestInvite ~= nil and SterlingQuestInvite:IsShown()'))
C.lua('INCOMBAT = false'); C.fire("PLAYER_REGEN_ENABLED")
check("it shows when combat ends", C.ev('SterlingQuestInvite:IsShown()'))
# ---------- look switch rebuilds the guide windows too
do('S.UI_Help("start"); SterlingQuestDB.opts.skin = "navy"; S.UI_ApplyLook(); S.UI_Help("sync"); S.TourStart()')
check("after switching the look, Help and the tour still work", P.ev('SterlingQuestHelp:IsShown()') and P.ev('SterlingQuestCoach:IsShown()'))
do('S.TourEnd(false); SterlingQuestDB.opts.skin = "wow"; S.UI_ApplyLook()')
tot = P.errors() + Q.errors() + R.errors() + C.errors()
check("no Lua errors", tot == 0, tot)
snags = [clean(c) for p in (P, Q, R, C) for c in p.L.globals().CHAT.values() if "snag" in c]
check("no snags", not snags, snags[:3])
print("ALL OK" if ok else "SOME FAILED")
