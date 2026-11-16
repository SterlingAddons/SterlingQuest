local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
S.UI_Toggle(true); S.UI_Options()
print("wow:", S.WowSkin(), S.AR)
SterlingQuestDB.opts.skin = "navy"; print("apply navy:", pcall(S.UI_ApplyLook), S.WowSkin(), S.AR)
for _, t in ipairs({ "sync", "catchup", "path", "sessions" }) do print(t, pcall(function() S.UI_Tab(t); S.UI_Update() end)) end
SterlingQuestDB.opts.skin = "wow"; print("apply wow:", pcall(S.UI_ApplyLook), S.WowSkin(), S.AR)
print("windows after:", #S.windows, "compare:", pcall(S.UI_Compare), "profile:", pcall(S.UI_Profile), "share:", pcall(S.UI_ShareWindow))
