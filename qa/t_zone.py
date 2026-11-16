import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
P = sim.Player("Kaelith Emberfall", [(2, "Fishy Business")], [6], level=38, sv=ACC, questie=True, tomtom=True)
L, S = P.L, P.S
def do(code): return L.eval("function(S) " + code + " end")(S)
do('''
HERE, HERENAME = 1600, ""
C_Map.GetBestMapForUnit = function() return HERE end
C_Map.GetMapInfo = function(id)
  if id == 1500 then return { name = "Riverglades", mapType = 3, parentMapID = 13 } end
  if id == 1600 then return { name = "Riverpaw Hollow", mapType = 3, parentMapID = 13 } end
  if id == 1601 then return { name = "Hollow Mine", mapType = 6, parentMapID = 1600 } end
  if id == 13 then return { name = "Continent", mapType = 2, parentMapID = 0 } end
  if id == 1700 then return { name = "Nowhere", mapType = 3, parentMapID = 13 } end
  return nil
end
GetRealZoneText = function() return HERENAME end
GetZoneText = function() return HERENAME end
S.ReadCompleted = function() return { [6] = true } end
SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true, k1 = "aa", k2 = "bb" } }
S.snaps["Brannoc Ashvale"] = { log = {}, completed = { [1] = true, [3] = true, [4] = true, [5] = true, [9] = true }, rank = {}, seq = 3, at = time() - 100, level = 39, source = "live", name = "Brannoc Ashvale" }
S.UI_Toggle(true)
''')
def zone(): return do('return S.UI_Page("catchup").zone')
def seltext(): return do('local p = S.UI_Page("catchup"); for _, r in ipairs(p.zoneRows) do if r:IsShown() and r.sel:IsShown() then return r.text:GetText() end end')
def fire(ev): do('for _, f in ipairs(FRAMES or {}) do end'); P.fire(ev) if hasattr(P, "fire") else None

do('S.UI_Tab("catchup")')
check("list is alphabetical: Riverglades first", do('return S.CatchupZones("Brannoc Ashvale")[1].name') == "Riverglades")
check("opens on the zone you're standing in, not the first", zone() == 600, zone())
check("that row is the highlighted one", seltext() == "Riverpaw Hollow", seltext())
check("the plan is for that zone", "Riverpaw Hollow" in do('return S.UI_Page("catchup").summary:GetText()'))

do('HERE = 1601; S.UI_Tab("sync"); S.UI_Page("catchup").zone = 500; S.UI_Tab("catchup")')
check("inside a cave or sub-map: still the parent zone", zone() == 600, zone())

do('HERE = 4242; HERENAME = "Riverpaw Hollow"; S.UI_Tab("sync"); S.UI_Page("catchup").zone = 500; S.UI_Tab("catchup")')
check("map unknown: matched by zone name", zone() == 600, zone())

do('HERE = 1700; HERENAME = "Nowhere"; S.UI_Tab("sync"); S.UI_Page("catchup").zone = nil; S.UI_Tab("catchup")')
check("nothing to catch up where you stand: falls back to the first", zone() == 500, zone())
do('S.UI_Tab("sync"); S.UI_Page("catchup").zone = 600; S.UI_Tab("catchup")')
check("...and keeps an earlier choice rather than jumping", zone() == 600, zone())

# picking by hand sticks while the tab stays open
do('HERE = 1600; HERENAME = ""; S.UI_Tab("sync"); S.UI_Tab("catchup")')
do('local p = S.UI_Page("catchup"); for _, r in ipairs(p.zoneRows) do if r.key == 500 then r:Click() end end')
check("clicking a zone selects it", zone() == 500, zone())
do('S.UI_Update(); S.UI_ZoneChanged(); S.UI_Update()')
check("a hand-picked zone survives updates and zone changes", zone() == 500, zone())
do('S.UI_Tab("path"); S.UI_Tab("catchup")')
check("coming back to the tab follows you again", zone() == 600, zone())

# walking into a new zone with the tab open and nothing hand-picked
do('HERE = 1500; S.UI_ZoneChanged()')
check("walking into a new zone moves the choice", zone() == 500, zone())
# the real event, with the 1s settle; a flight path doesn't drag the choice along
do('HERE = 1600'); P.fire("ZONE_CHANGED_NEW_AREA"); sim.pump(2)
check("ZONE_CHANGED_NEW_AREA moves it after a moment", zone() == 600, zone())
do('HERE = 1500; UnitOnTaxi = function() return true end'); P.fire("ZONE_CHANGED_NEW_AREA"); sim.pump(2)
check("not while on a flight path", zone() == 600, zone())
do('UnitOnTaxi = function() return false end; S.UI_Page("catchup").zone = 500')
check("hidden window: reopening follows too", do('S.UI_Toggle(false); HERE = 1600; S.UI_Toggle(true); return S.UI_Page("catchup").zone') == 600)

# search still works and counts as a hand pick
do('local p = S.UI_Page("catchup"); p.search:SetText("glades"); local f = p.search:GetScript("OnTextChanged"); f(p.search, true)')
check("searching picks the match", zone() == 500, zone())
do('S.UI_ZoneChanged()')
check("and stays put", zone() == 500, zone())
check("no Lua errors", P.errors() == 0, P.errors())
# only quests they turned in, unless the option says otherwise
do('S.snaps["Brannoc Ashvale"].log = { [8] = { title = "A Very Long Quest Name That Goes On And On", complete = false, objs = {} } }; S.snaps["Brannoc Ashvale"].seq = 4')
def has(q): return do('for _, z in ipairs(S.CatchupZones("Brannoc Ashvale")) do for _, id in ipairs(z.quests) do if id == %d then return true end end end return false' % q)
check("a quest only in their log is left out", has(8) == False)
check("turned-in quests still listed", has(9) == True)
do('SterlingQuestDB.opts.catchupLog = true')
check("option on: their in-log quest comes back", has(8) == True)
do('SterlingQuestDB.opts.catchupLog = nil')
check("option off again: gone", has(8) == False)
print("ALL OK" if ok else "FAILED")
