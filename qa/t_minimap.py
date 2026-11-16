# Minimap button follows round and square minimaps (0.3.08).
import sim, math
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
R = sim.Player("Kaelith Emberfall", [(188, "a")], [185], account=ACC)
def at(ang):
    R.L.eval('function(S, ang) SterlingQuestDB.minimapAngle = ang; S.MinimapPlace() end')(R.S, ang)
    return R.L.eval('function() local _, _, _, x, y = SterlingQuestMinimapButton:GetPoint(1); return x end')(), R.L.eval('function() local _, _, _, x, y = SterlingQuestMinimapButton:GetPoint(1); return y end')()
x, y = at(45)
check("round: on the circle (radius 80)", abs(math.hypot(x, y) - 80) < 0.5, (x, y))
R.lua('function GetMinimapShape() return "SQUARE" end')
x, y = at(45)
check("square: corner goes well past the circle", x > 70 and y > 70, (x, y))
x, y = at(20)
check("square: side stays on the edge", abs(x - 80) < 0.5 and y > 0, (x, y))
R.lua('function GetMinimapShape() return "CORNER-TOPRIGHT" end')
x, y = at(45)
check("corner shape: round quarter stays round", abs(math.hypot(x, y) - 80) < 0.5, (x, y))
R.lua('function GetMinimapShape() error("bad") end')
x, y = at(45)
check("a broken shape addon falls back to round", abs(math.hypot(x, y) - 80) < 0.5, (x, y))
print("ALL OK" if ok else "SOME FAILED")
