local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
print("cmp", S.CompareVer("5.42","5.83"), S.CompareVer("6.0","5.83"), S.CompareVer("5.9","5.42"), S.CompareVer("6.0","6.0"), S.CompareVer(nil,"6.0"))
rawset(UIParent, "GetWidth", function() return 1920 end)
rawset(UIParent, "GetEffectiveScale", function() return 1 end)
SlashCmdList.STERLINGQUEST("")
local m; for _, w in ipairs(S.windows) do if not w.sterlingSide then m = w end end; _G.SterlingQuestFrame = m
print("main", m)
local function geo(f, l, b, w, h) rawset(f, "GetRect", function() return l, b, w, h end); rawset(f, "GetEffectiveScale", function() return 1 end); rawset(f, "IsShown", function() return true end) end
geo(m, 900, 300, 420, 620)
SterlingQuestDB.pos = SterlingQuestDB.pos or {}; SterlingQuestDB.pos.SterlingQuestOptions = nil
S.UI_Options()
local o
for _, w in ipairs(S.windows) do if w ~= m and w.sterlingSide then o = w end end
print("opts", o and o:GetName())
if o then
  geo(o, 700, 300, 480, 560)  -- overlapping main
  local got
  rawset(o, "GetName", function() return "SterlingQuestOptions" end); rawset(o, "SetPoint", function(self, ...) got = { ... } end)
  S.PlaceSide(o)
  print("placed:", got and got[1], got and got[3], got and got[4])
end
