local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
print("open wow", pcall(S.UI_Options))
SterlingQuestDB.opts.skin = "navy"; print("toggle", pcall(S.UI_FlatShown))
SterlingQuestDB.opts.skin = "wow"; print("toggle back", pcall(S.UI_FlatShown))
SterlingQuestDB.opts.skin = "navy"; print("apply flat", pcall(S.UI_ApplyLook)); print("options in flat", pcall(S.UI_Options))
