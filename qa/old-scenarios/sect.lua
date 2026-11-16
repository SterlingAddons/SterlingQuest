local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
S.Partners = function() return { { name = "Brannoc" } } end
S.snaps = { Brannoc = { log = {}, completed = { [101] = true } } }
local parent = MK()
local function region(name, rel)
  local r = MK(); local pts = { { "TOPLEFT", rel, "BOTTOMLEFT", 0, -5 } }
  rawset(r, "IsVisible", function() return true end); rawset(r, "GetParent", function() return parent end)
  rawset(r, "GetWidth", function() return 280 end); rawset(r, "GetHeight", function() return 20 end)
  rawset(r, "GetNumPoints", function() return #pts end); rawset(r, "GetPoint", function(_, i) return unpack(pts[i]) end)
  rawset(r, "SetPoint", function(_, p, rel2, rp, x, y) pts[1] = { p, rel2, rp, x, y } end); rawset(r, "ClearAllPoints", function() end)
  r._pts = pts; _G[name] = r; return r
end
local title = region("QuestInfoTitleHeader", parent)
local objText = region("QuestInfoObjectivesText", title)
local objFrame = region("QuestInfoObjectivesFrame", objText)
local desc = region("QuestInfoDescriptionHeader", objFrame)
rawset(parent, "GetRegions", function() return title, objText, objFrame, desc end); rawset(parent, "GetChildren", function() end)
C_QuestLog.GetSelectedQuest = function() return 101 end
local function blk() for _, b in pairs(S.QuestLogBlocks) do return b end end
SterlingQuestDB.opts.logStyle = "section"; S.UpdateQuestLogStatus()
print("section: head", blk().head._text, "| description under ours:", desc._pts[1][2] == blk(), "| objectives text untouched:", objText._pts[1][2] == title)
SterlingQuestDB.opts.logStyle = "plain"; S.UpdateQuestLogStatus()
print("plain: description back on objectives:", desc._pts[1][2] == objFrame, "| objectives text under ours:", objText._pts[1][2] == blk(), "| head hidden:", not blk().head._shown)
SterlingQuestDB.opts.logStyle = "section"; S.UpdateQuestLogStatus()
print("section again: objectives text back under title:", objText._pts[1][2] == title, "| description under ours:", desc._pts[1][2] == blk())
