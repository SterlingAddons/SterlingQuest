# Hovering the quest log status block lists each partner's objective lines (0.3.20.01).
import sim
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
R = sim.Player("Kaelith Emberfall", [(300, "The Star, the Hand and the Heart")], [], account=ACC)
R.L.eval('''function(S)
  S.AddPartner("Brannoc Ashvale", true); S.AddPartner("Tovak Stoneroot", true); S.AddPartner("Mirelle Duskwhisper", true)
  S.snaps["Brannoc Ashvale"] = { completed = {}, log = { [300] = { title = "The Star, the Hand and the Heart", complete = false,
    objs = { "Star of Xil'yeh: 1/1", "Hand of Dagun: 1/1", "The Legacy Heart: 0/1" } } } }
  S.snaps["Tovak Stoneroot"] = { completed = { [300] = true }, log = {} }
  S.snaps["Mirelle Duskwhisper"] = { completed = {}, log = {} }
end''')(R.S)
tip = lambda: R.L.eval('''function(S)
  local shown = S.QuestStatusTooltip(UIParent, 300)
  local t = {}
  for _, l in ipairs(GameTooltip._lines or {}) do t[#t + 1] = tostring(l) end
  return shown, table.concat(t, " | ") end''')(R.S)
shown, t = tip()
check("tooltip shows", shown is True, t)
check("partner working on it: progress on their line", "Brannoc" in t and "2 of 3 done" in t, t)
check("every objective line listed", all(x in t for x in ("Star of Xil'yeh: 1/1", "Hand of Dagun: 1/1", "The Legacy Heart: 0/1")), t)
check("finished partner says Done, no objective lines", "Done" in t and t.count("Hand of Dagun") == 1, t)
check("not started listed", "Not started" in t, t)
done = R.L.eval('function(S) return S.ObjectiveDone("1/1 Hand of Dagun"), S.ObjectiveDone("The Legacy Heart: 0/1"), S.ObjectiveDone("Bring the note (Complete)") end')(R.S)
check("done / not done / (Complete) read right", tuple(done) == (True, False, True), done)
# the block in the quest log carries the quest and opens the tooltip on hover
R.L.eval('''function(S)
  local panel = CreateFrame("Frame", nil, UIParent); panel:SetSize(300, 400); panel:Show()
  local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10); h:SetWidth(280); h:SetText("x"); h:Show()
  _G.QuestInfoTitleHeader = h
  C_QuestLog = C_QuestLog or {}; C_QuestLog.GetSelectedQuest = function() return 300 end
  S.UpdateQuestLogStatus()
end''')(R.S)
hov = R.L.eval('''function(S)
  for _, b in pairs(S.QuestLogBlocks) do
    if b:IsShown() then
      GameTooltip._lines = {}
      b:GetScript("OnEnter")(b)
      local t = {}
      for _, l in ipairs(GameTooltip._lines or {}) do t[#t + 1] = tostring(l) end
      return b.qid, table.concat(t, " | ")
    end
  end
  return nil, "" end''')(R.S)
check("block knows its quest", hov[0] == 300, hov)
check("hovering the block lists the objectives", "The Legacy Heart: 0/1" in hov[1], hov)
# no partners: nothing to show
R.L.eval('function(S) S.snaps = {} end')(R.S)
shown, t = tip()
check("no partners: no tooltip", shown is False, t)
print("ALL OK" if ok else "SOME FAILED")
