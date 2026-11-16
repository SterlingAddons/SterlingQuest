import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
import sim, sys, re
skin = sys.argv[1] if len(sys.argv) > 1 else "wow"
quiet = "-q" in sys.argv
SV = '''
SterlingQuestDB = { opts = { skin = "%s", cb = %s }, sessions = {
  { id = "a1", name = "Evening in the Glades", char = "Kaelith Emberfall", start = 1794600000, stop = 1794607200, lvl0 = 33, lvl1 = 34, events = { { t = 1794600100, k = "A", q = 1, quest = "Riverglade Cleanup", map = 1500, x = 40.5, y = 60.2, npc = "Warden Tal" }, { t = 1794600900, k = "T", q = 1, quest = "Riverglade Cleanup", map = 1500, x = 40.5, y = 60.2, npc = "Warden Tal" } }, trail = { { t = 1794600000, map = 1500, x = 40, y = 60 } }, zones = { Riverglades = true, ["Stranglethorn Vale"] = true } },
  { id = "b2", name = "Bran run", char = "Brannoc Ashvale", imported = true, start = 1794500000, stop = 1794504000, events = {}, trail = {}, zones = { Riverglades = true } },
  { id = "c3", name = "Old one", char = "Kaelith Emberfall", start = 1790000000, stop = 1790004000, events = {}, trail = {}, zones = {} },
} }
SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }
SterlingQuestSyncOut = { format = 1, characters = {} }
''' % (skin, "true" if "cb" in sys.argv else "false")
p = sim.Player("Kaelith Emberfall", [(2, "Fishy Business"), (188, "Tiger Mastery")], [6, 185, 186], level=38, sv=SV, questie=True, tomtom=True)
L, S = p.L, p.S
L.execute(open(_os.path.join(QA, "audit.lua")).read())
p.lua('''
local S = ...
S.ReadCompleted = function() return { [6] = true } end
SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true, k1 = "aa", k2 = "bb" }, { name = "Tovak", on = true, k1 = "cc" }, { name = "Branthepaladin", on = true, k1 = "dd" }, { name = "Grukk", on = false, k1 = "ee" } }
local function snap(name, lvl) S.snaps[name] = { log = { [2] = { title = "Fishy Business", complete = false, objs = { "Fish 3/8" } } }, completed = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true }, rank = {}, seq = 3, at = time() - 100, level = lvl, source = "live", name = name } end
snap("Brannoc Ashvale", 39); snap("Tovak", 30); snap("Branthepaladin", 41)
S.snaps["Tovak"].at = time() - 3 * 86400
S.addonVers = { ["Brannoc Ashvale"] = S.ADDON_VER, Tovak = "6.29", Branthepaladin = "0.9.99" }
S.sync.vers = { ["Brannoc Ashvale"] = 6, Tovak = 6, Branthepaladin = 6, Grukk = 5 }
S.profiles["Brannoc Ashvale"] = { name = "Bran", race = "Troll", color = "gold" }
''' if False else "")
L.eval('''function(S)
S.ReadCompleted = function() return { [6] = true } end
SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true, k1 = "aa", k2 = "bb" }, { name = "Tovak", on = true, k1 = "cc" }, { name = "Branthepaladin", on = true, k1 = "dd" }, { name = "Grukk", on = false, k1 = "ee" } }
local function snap(name, lvl) S.snaps[name] = { log = { [2] = { title = "Fishy Business", complete = false, objs = { "Fish 3/8" } } }, completed = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true }, rank = {}, seq = 3, at = time() - 100, level = lvl, source = "live", name = name } end
snap("Brannoc Ashvale", 39); snap("Tovak", 30); snap("Branthepaladin", 41)
S.snaps["Tovak"].at = time() - 3 * 86400
S.addonVers = { ["Brannoc Ashvale"] = S.ADDON_VER, Tovak = "6.29", Branthepaladin = "0.9.99" }
S.sync.vers = { ["Brannoc Ashvale"] = 6, Tovak = 6, Branthepaladin = 6, Grukk = 5 }
S.profiles["Brannoc Ashvale"] = { name = "Bran", race = "Troll", color = "gold" }
SterlingQuestDB.partners[1].guid = "Player-6800-0A1B2C3D"; SterlingQuestDB.partners[3].guid = "Player-6800-0000BEEF"
S.app = { written = time() - 60, got = { "Brannoc Ashvale" }, problems = { ["Player-6800-0000BEEF"] = "resync" }, appUpdate = true }
end''')(S)
sim.pump(12)
findings = []
def audit(win, name):
    res = L.eval('function(w, n) local out = AUDIT(_G[w], n); return table.concat(out, "\\n"), PADS(_G[w], n) end')(win, name)
    out, pads = res
    for line in str(out).split("\n"):
        if line: findings.append(line)
    if not quiet: print(pads)
def do(code): L.eval("function(S) " + code + " end")(S)
do('S.UI_Toggle(true); SterlingQuestFrame.notice._outsideOK = true')
for tab in ["catchup", "path", "sessions", "sync"]:
    do(f'S.UI_Tab("{tab}"); S.UI_Update()')
    audit("SterlingQuestFrame", "main/" + tab)
# catch-up with a path started, then the Path tab in both views
do('S.UI_Tab("catchup"); S.UI_Update(); S.CatchupStart("Brannoc Ashvale", 500); S.UI_Update()')
audit("SterlingQuestFrame", "main/catchup+path")
do('S.UI_Tab("path"); S.UI_Update()'); audit("SterlingQuestFrame", "main/path steps")
do('S.RecordStart("test"); S.UI_Update()'); audit("SterlingQuestFrame", "main/path recording")
do('SterlingQuestDB.opts.expanded = false; S.UI_Update()'); audit("SterlingQuestFrame", "main/path small")
do('S.RecordStop(); SterlingQuestSaveFrame:Hide(); S.UI_Update()'); audit("SterlingQuestFrame", "main/path small idle")
do('SterlingQuestDB.opts.expanded = true; S.UI_Update()')
do('S.UI_Tab("sync"); S.UI_Update()')
do('S.UI_Options()')
for t in ["general", "sync", "status", "record"]:
    do(f'for _, f in ipairs(FRAMES) do if rawget(f, "ShowTab") and rawget(f, "sections") and f:IsVisible() then f.ShowTab("{t}") end end')
    audit("SterlingQuestOptions", "options/" + t)
do('SterlingQuestOptions:Hide(); S.UI_Compare("Brannoc Ashvale")'); audit("SterlingQuestCompare", "compare")
do('SterlingQuestCompare:Hide(); S.UI_PartnerInfo("Brannoc Ashvale")'); audit("SterlingQuestPartnerInfo", "partner info")
do('SterlingQuestPartnerInfo:Hide(); S.UI_Profile()'); audit("SterlingQuestProfile", "profile")
do('SterlingQuestProfile:Hide(); S.UI_AddPartner()'); audit("SterlingQuestAddPartner", "add partner (empty)")
do('S.found = { Zal = { ver = "0.2.30", class = "MAGE", level = 40, src = "party" }, Verylongnameperson = { ver = "6.29", class = "WARRIOR", level = 12, src = "guild" }, Bob = { ver = "0.2.30", class = "PRIEST", level = 60, src = "friend" } }; SterlingQuestAddPartner.refresh()'); audit("SterlingQuestAddPartner", "add partner (found)")
do('SterlingQuestAddPartner:Hide(); S.UI_Everyone()'); audit("SterlingQuestEveryone", "everyone")
do('SterlingQuestEveryone:Hide(); S.UI_Offline("Brannoc Ashvale")'); audit("SterlingQuestOffline", "offline (signed)")
do('for _, f in ipairs(FRAMES) do if f._text == "Make string" then f:Click() end end'); audit("SterlingQuestOffline", "offline (made)")
do('S.UI_Offline("Tovak")'); audit("SterlingQuestOffline", "offline (no key)")
do('SterlingQuestOffline:Hide(); S.UI_Help("start")'); audit("SterlingQuestHelp", "help/start")
for k in ["sync", "offline", "catchup", "path", "record", "status", "trouble", "credits"]:
    do(f'S.UI_Help("{k}")'); audit("SterlingQuestHelp", "help/" + k)
do('SterlingQuestHelp:Hide(); S.UI_Welcome()'); audit("SterlingQuestWelcome", "welcome")
do('S.TourStart()'); audit("SterlingQuestCoach", "tour 1"); audit("SterlingQuestFrame", "main/tour1")
do('SterlingQuestCoach.next:Click()'); audit("SterlingQuestCoach", "tour 2")
do('SterlingQuestCoach.next:Click()'); audit("SterlingQuestCoach", "tour 3")
do('SterlingQuestCoach.next:Click()')
do('SterlingQuestAccountDB.hints = {}; S.UI_Tab("sessions")'); audit("SterlingQuestCoach", "tip sessions")
do('SterlingQuestCoach:Hide()')
do('S.UI_ShowExport("log")'); audit("SterlingQuestBoxFrame", "export")
do('S.UI_ShowImport()'); audit("SterlingQuestBoxFrame", "import")
do('SterlingQuestBoxFrame:Hide(); S.UI_Confirm("Clear the path?", "Stops following and removes the arrow. Your sessions and check-offs stay saved; you can start it again any time.", "Clear", function() end)'); audit("SterlingQuestSaveFrame", "confirm")
do('S.UI_Prompt("Nickname for Brannoc Ashvale", "Only you see this. It replaces their name everywhere in Sterling on your screen.", "", "Save", function() end)'); audit("SterlingQuestSaveFrame", "prompt")
do('SterlingQuestSaveFrame:Hide(); S.UI_InvitePrompt("Verylongnameperson", "123456")'); audit("SterlingQuestInvite", "invite")
do('SterlingQuestInvite.no:Click(); S.UI_ShareAsk("Brannoc Ashvale", 188)'); audit("SterlingQuestShareAsk", "share ask")
print("--- findings (%s) ---" % skin)
for f in findings: print(f)
print("errors:", p.errors(), " chat with snag:", [re.sub(r"\|c\w{8}|\|r", "", c) for c in p.chat() if "snag" in c or "Couldn" in c][:6])
