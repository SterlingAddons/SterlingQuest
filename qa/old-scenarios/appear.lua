local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
local got
ColorPickerFrame = MK()
rawset(ColorPickerFrame, "SetupColorPickerAndShow", function(self, info) got = info end)
rawset(ColorPickerFrame, "GetColorRGB", function() return .1, .2, .3 end)
rawset(ColorPickerFrame, "GetColorAlpha", function() return .5 end)
SterlingQuestDB.opts.tipLook = "rule"
print("rule look:", S.TipLook().box, S.TipLook().rule)
print(pcall(S.UI_Options))
-- click every swatch-like button in the options and fire the picker callback
local n = 0
for _, f in ipairs(FRAMES) do
  if rawget(f, "key") and f._scripts.OnClick then
    got = nil; local ok, e = pcall(f._scripts.OnClick, f)
    if not ok then print("SWATCH FAIL", f.key, e) end
    if got then local ok2, e2 = pcall(got.swatchFunc); if not ok2 then print("CB FAIL", e2) end; pcall(got.opacityFunc); n = n + 1 end
  end
end
print("swatches picked:", n, "look:", SterlingQuestDB.opts.tipLook)
local c = SterlingQuestDB.opts.tipCustom
print("custom bg:", c and c.bg[1], c and c.bg[4], "done:", c and c.text.done, "base:", c and c.base, "box:", c and c.box, "rule:", c and c.rule)
SterlingQuestDB.opts.logStyle = "tooltip"
print("update:", pcall(S.UpdateQuestLogStatus))
