import sim, re
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
P = sim.Player("Kaelith Emberfall", [(2, "Fishy Business"), (9, "Marsh Lights")], [6], level=38, sv=ACC, questie=True, tomtom=True)
L, S = P.L, P.S
def do(code): return L.eval("function(S) " + code + " end")(S)
do('''
S.steps = {
  { kind = "turnin", qid = 2, quest = "Fishy Business", npc = "Old Marn" },
  { kind = "do", qid = 9, quest = "Marsh Lights" },
  { kind = "turnin", qid = 9, quest = "Marsh Lights" },
  { kind = "travel", text = "Somewhere", map = 1500, x = 1, y = 1 },
}

S.UI_Toggle(true); S.UI_Tab("path"); S.Recalc(false)
''')
def rowtxt(n): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(do('local r = S.UI_Page("path").rows[%d]; return r:IsShown() and (r.text:GetText() .. " | " .. (r.time:GetText() or "")) or ""' % n)))
cur = do('return S.CurrentIndex()')
check("current is step 1 (turn in Fishy Business)", cur == 1, cur)
check("DO Marsh Lights not done yet", "done" not in rowtxt(2), rowtxt(2))
do('for _, q in ipairs(QLOG) do if q.id == 9 then q.c = true end end; S.Recalc(false)')
check("still on step 1", do('return S.CurrentIndex()') == 1)
check("DO Marsh Lights (finished out of order) says done", "done" in rowtxt(2), rowtxt(2))
check("its turn-in doesn't", "done" not in rowtxt(3), rowtxt(3))
check("travel step never guessed done", "done" not in rowtxt(4), rowtxt(4))
check("no Lua errors", P.errors() == 0, P.errors())
print("ALL OK" if ok else "FAILED")
