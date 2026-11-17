# Partner sync status worded like the Sterling Quest Sync app 0.1.24, and the "helper add-on isn't loaded" note (0.3.10, 0.3.11).
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {}, app = { version = "0.1.22" } }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
SV = 'SterlingQuestDB = { opts = { chat_sync = 3 } }'
R = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185], account=ACC, sv=SV, pre=FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "Raptor Mastery")], [185], account=ACC, sv=SV, pre=COMP + "; " + FRIEND % "Kaelith Emberfall")
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(60)
state = lambda P, n: P.L.eval('function(S) local k, t = S.PartnerSyncState("%s"); return k, t end' % n)(P.S)
k, t = state(R, "Brannoc Ashvale")
check("synced partner: Up to date", k == "current" and t.endswith("Up to date"), (k, t))
check("Up to date is green", R.L.eval('function(S) local _, _, r, g, b = S.PartnerSyncState("Brannoc Ashvale"); return g > r and g > b end')(R.S))
R.L.eval('function(S) S.pending["Brannoc Ashvale"] = { mode = "quick", at = GetTime() } end')(R.S)
k, t = state(R, "Brannoc Ashvale")
check("live sync running: Syncing...", k == "syncing" and t == "Syncing...", (k, t))
R.L.eval('function(S) S.pending["Brannoc Ashvale"] = nil end')(R.S)
check("sync over: back to Up to date", state(R, "Brannoc Ashvale")[0] == "current")
# paired through the app, nothing from them yet
R.L.eval('''function(S)
  S.AddPartner("Tovak Stoneroot", true)
  local p = S.FindPartner("Tovak Stoneroot"); p.guid = "Player-6800-0000ABCD"
  local real = S.AppPairKey
  S.AppPairKey = function(g) if g == "Player-6800-0000ABCD" then return "k" end return real and real(g) end
end''')(R.S)
k, t = state(R, "Tovak Stoneroot")
check("paired, no copy yet: Paired. Waiting for their next save", k == "paired" and t == "Paired. Waiting for their next save", (k, t))
R.L.eval('function(S) S.AddPartner("Mirelle Duskwhisper", true) end')(R.S)
check("no app, never synced: Not synced yet", state(R, "Mirelle Duskwhisper")[1] == "Not synced yet", state(R, "Mirelle Duskwhisper"))
R.L.eval('function(S) S.FindPartner("Mirelle Duskwhisper").on = false end')(R.S)
check("sync switched off", state(R, "Mirelle Duskwhisper")[1] == "Sync disabled")
# the Sync tab row shows it
R.L.eval('function(S) S.UI_Toggle(true); S.UI_Tab("sync"); S.UI_Update() end')(R.S)
rows = R.L.eval('''function(S) local t = {}
  for _, r in ipairs(S.UI_Page("sync").rows or {}) do if r:IsShown() and r.p then t[#t + 1] = r.p.name .. "=" .. (r.last:GetText() or "") end end
  return table.concat(t, ";") end''')(R.S)
check("rows show the new wording", "Up to date" in rows and "Paired. Waiting for their next save" in rows, rows)
check("no 'synced ... ago' on the rows any more", "synced " not in rows, rows)
# helper add-on not loaded
miss = lambda P: P.L.eval('function(S) return S.AppAddonMissing() end')(P.S)
check("no app anywhere: no note", miss(R) is False)
check("companion loaded: no note", miss(L) is False)
check("companion seen at login is remembered for the account", L.ev('SterlingQuestAccountDB.appSeen') is True)
R.lua('C_AddOns = C_AddOns or {}; C_AddOns.GetAddOnInfo = function(n) return n, "Sterling Quest Sync", "", false, "DISABLED" end')
check("installed but unticked: note", miss(R) is True)
R.lua('C_AddOns.GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end')
check("game doesn't know it: no note on that alone", miss(R) is False)
R.lua('SterlingQuestAccountDB.appSeen = true')
check("ran before on this account but not now: note", miss(R) is True)
R.lua('SterlingQuestAccountDB.appSeen = nil; SterlingQuestDB.appPairs = { ["Player-6800-0000ABCD"] = { key = "x" } }')
check("pairings from the app but no add-on: note", miss(R) is True)
R.L.eval('function(S) S.UI_Update() end')(R.S)
w = R.L.eval('function(S) local w = S.UI_Page("sync").appWarn; return w:IsShown() and w:GetText() or "" end')(R.S)
check("Sync tab shows the exact message", "The Companion add-on (Sterling Quest Sync Companion) isn't loaded. Exit WoW completely and start it again, then make sure it's ticked in AddOns at character select." in w, w)
check("App line hidden while the note shows", R.L.eval('function(S) return S.UI_Page("sync").v.app:IsShown() end')(R.S) is False)
# with the app: what we know about each partner's app
L.L.eval('''function(S)
  S.AddPartner("Zil'ana Frostcall", true); S.FindPartner("Zil'ana Frostcall").app = "0.1.24"
  S.AddPartner("Tovak Stoneroot", true); S.FindPartner("Tovak Stoneroot").app = false
  S.AddPartner("Mirelle Duskwhisper", true)
end''')(L.S)
k, t = state(L, "Zil'ana Frostcall")
check("they have the app, not paired: Pairs when you're both next online", k == "pairsoon" and t == "Pairs when you're both next online", (k, t))
k, t = state(L, "Tovak Stoneroot")
check("they don't have the app: red Doesn't have the app yet", k == "noapp" and t.endswith("Doesn't have the app yet"), (k, t))
check("  and it's red", L.L.eval('function(S) local _, _, r, g = S.PartnerSyncState("Tovak Stoneroot"); return r > g end')(L.S))
k, t = state(L, "Mirelle Duskwhisper")
check("nothing known about their app: Not online with you yet", k == "unknown" and t == "Not online with you yet", (k, t))
L.L.eval('function(S) S.UI_Toggle(true); S.UI_Tab("sync"); S.UI_Update() end')(L.S)
tip = L.L.eval('''function(S)
  S.UI_PartnerTooltip(UIParent, S.FindPartner("Tovak Stoneroot"))
  local t = {}
  for _, l in ipairs(GameTooltip._lines or {}) do t[#t + 1] = tostring(l) end
  GameTooltip:Hide(); return table.concat(t, " | ") end''')(L.S)
check("no-app hover explains live sync still works", "You still sync live in game when you're both online. Offline syncing starts once they install the Sterling Quest Sync Companion app." in tip, tip)
# no player-facing jargon in the add-on's own text
import re, glob, os
bad = []
for f in glob.glob(os.path.join(sim.SRC, "*.lua")):
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        code = line.split("--")[0]
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', code):
            txt = m.group(1)
            if " " in txt.strip() and re.search(r"(?i)\b(inbox|outbox|packets?|guids?|proto|wtf)\b", txt):
                bad.append(os.path.basename(f) + ":" + str(i) + " " + txt[:60])
check("no inbox/outbox/packet/GUID/proto/WTF in visible text", not bad, bad)
old = []
for f in glob.glob(os.path.join(sim.SRC, "*.lua")):
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        code = line.split("--")[0]
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', code):
            if re.search(r"Sterling Sync|Sterling Quest Sync app|helper add-on|Quest Tracker", m.group(1)): old.append(os.path.basename(f) + ":" + str(i))
check("no old app names in visible text", not old, old)
print("ALL OK" if ok else "SOME FAILED")
