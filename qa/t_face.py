# Female portraits (0.2.41): profile picker has a second row, FACE travels after PROF.
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
R = sim.Player("Kaelith Emberfall", [(188, "a")], [185], account=ACC, pre=FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "b")], [185], account=ACC, pre=FRIEND % "Kaelith Emberfall")
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(60)
fem = lambda: L.L.eval('function(S) local p = S.profiles["Kaelith Emberfall"]; return p and p.female end')(L.S)
check("male by default", not fem())
R.L.eval('function(S) S.UI_Profile() end')(R.S)
n = R.L.eval('function(S) return #SterlingQuestProfile.raceBtns end')(R.S)
nr = R.L.eval('function(S) return #S.RACES end')(R.S)
check("two rows of faces", n == 2 * nr, (n, nr))
# click the female Troll
R.L.eval('function(S) for _, b in ipairs(SterlingQuestProfile.raceBtns) do if b.race == "Troll" and b.female then b:GetScript("OnClick")(b) end end end')(R.S)
sim.pump(5)
check("profile saved as female Troll", R.L.eval('function(S) local p = S.Profile(); return p.race == "Troll" and p.female == true end')(R.S))
check("only that button is selected", R.L.eval('function(S) local c = 0; for _, b in ipairs(SterlingQuestProfile.raceBtns) do if b.sel:IsShown() then c = c + (b.female and b.race == "Troll" and 1 or 100) end end; return c end')(R.S) == 1)
check("partner sees female", fem() is True)
check("a later PROF keeps it", (L.L.eval('function(S) return S.profiles["Kaelith Emberfall"].race end')(L.S) == "Troll"))
R.L.eval('function(S) for _, b in ipairs(SterlingQuestProfile.raceBtns) do if b.race == "Orc" and not b.female then b:GetScript("OnClick")(b) end end end')(R.S)
sim.pump(5)
check("back to male Orc", not fem() and L.L.eval('function(S) return S.profiles["Kaelith Emberfall"].race end')(L.S) == "Orc")
# female atlas tried first
got = R.L.eval('''function(S) local t = UIParent:CreateTexture(); local seen = {}
  local orig = t.SetAtlas; t.SetAtlas = function(self, n) seen[#seen + 1] = n; return orig(self, n) end
  S.SetFace(t, "Troll", true); return seen[1] end''')(R.S)
check("female atlas asked for first", got == "raceicon-troll-female", got)
check("no Lua errors", R.errors() + L.errors() == 0, (R.errors(), L.errors()))
print("ALL OK" if ok else "SOME FAILED")
