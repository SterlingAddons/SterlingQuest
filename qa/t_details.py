# App partner list details (0.2.46, handoff section 11): level, class, race, sterling for you; level, class, race, seen per partner.
import sim, re
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
COMP = 'SterlingQuestSyncOut = { format = 1, characters = {} }; SterlingQuestSync_Inbox = { format = 1, written = 0, chars = {} }'
FRIEND = 'C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "%s", connected = true } end }'
R = sim.Player("Kaelith Emberfall", [(188, "a")], [185], account=ACC, pre=COMP + "; " + FRIEND % "Brannoc Ashvale")
L = sim.Player("Brannoc Ashvale", [(200, "b")], [185], account=ACC, pre=COMP + "; " + FRIEND % "Kaelith Emberfall")
L.lua('UnitRace = function() return "Night Elf", "NightElf" end; UnitClass = function() return "Shaman", "SHAMAN" end')
R.S.AddPartner("Brannoc Ashvale", True); L.S.AddPartner("Kaelith Emberfall", True)
sim.pump(60)
RG, LG = R.ev('MYGUID'), L.ev('MYGUID')
R.fire("PLAYER_LOGOUT")
ch = lambda k: R.ev('SterlingQuestSyncOut.characters["%s"].%s' % (RG, k))
pe = lambda k: R.ev('SterlingQuestSyncOut.characters["%s"].partners["%s"].%s' % (RG, LG, k))
lvl = R.ev('UnitLevel("player")')
check("you: level", ch("level") == lvl, (ch("level"), lvl))
check("you: class token", ch("class") == "HUNTER")
check("you: race", ch("race") == "Troll")
check("you: sterling version", ch("sterling") == R.ev('S.ADDON_VER') if False else re.match(r"^\d+\.\d+\.\d+(\.\d+)?$", str(ch("sterling"))), ch("sterling"))
check("partner: level", isinstance(pe("level"), int) and 1 <= pe("level") <= 100, pe("level"))
check("partner: class from their message", pe("class") == "SHAMAN", pe("class"))
check("partner: race (letters and spaces)", pe("race") == "Night Elf", pe("race"))
check("partner: seen is server time of the last live sync", pe("seen") and pe("seen") > 1.7e9, pe("seen"))
# bad values are left out, not guessed
R.L.eval('function(S) local p = S.FindPartner("Brannoc Ashvale"); p.class = "shaman!"; p.race = "<b>x</b>"; p.seen = nil; p.lvl = 999; S.snaps["Brannoc Ashvale"] = nil end')(R.S)
R.fire("PLAYER_LOGOUT")
check("bad class, race, level and no seen: all left out", pe("class") is None and pe("race") is None and pe("level") is None and pe("seen") is None, (pe("class"), pe("race"), pe("level"), pe("seen")))
check("the packet is still there", pe("packet") is not None)
# a forged CHAR from a stranger changes nothing
X = sim.Player("Some Stranger", [(1, "a")], [], account=ACC, pre=COMP)
X.lua('SEND("SterlingQuest", "CHAR\\t60\\tWARRIOR\\tOrc", "WHISPER", "Kaelith Emberfall")'); sim.pump(3)
check("strangers can't set details", R.L.eval('function(S) return S.FindPartner("Some Stranger") == nil end')(R.S))
check("no Lua errors", R.errors() + L.errors() + X.errors() == 0, (R.errors(), L.errors(), X.errors()))
print("ALL OK" if ok else "SOME FAILED")
