local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
SterlingQuestDB.opts.skin = "navy"; SterlingQuestDB.opts.navyColor = { .3, .08, .08 }; SterlingQuestDB.opts.navyAccent = { 1, .4, .4 }
S.UI_ApplyLook()
print("navy panel ->", S.Navy(.16, .2, .33)); print("alert kept ->", S.Navy(.8, .2, .2)); print("accent", S.AR, S.AG, S.AB, S.ACCENT_HEX)
SlashCmdList.STERLINGQUEST("")
for _, k in ipairs({ "sessions", "sync", "path", "catchup" }) do print(k, pcall(S.UI_Tab, k)) end
print("options", pcall(S.UI_Options))
SterlingQuestDB.opts.skin = "wow"; S.UI_ApplyLook(); print("wow ignores tint ->", S.Navy(.16, .2, .33))
