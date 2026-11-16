local S = ...
local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end
fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")
local snag = 0
local oldSafe = S.Safe
S.Safe = function(what, fn, ...) local ok, e = pcall(fn, ...); if not ok then snag = snag + 1; print("SNAG", what, e) end end
SlashCmdList.STERLINGQUEST("")
for _, k in ipairs({ "sessions", "sync", "path", "catchup" }) do
  S.UI_Tab(k)
  SterlingQuestDB.opts.skin = "navy"; S.UI_ApplyLook()
  S.UI_Tab("sessions"); S.UI_Tab("sync"); S.UI_Tab("path"); S.UI_Tab("catchup"); S.UI_Tab(k)
  SterlingQuestDB.opts.skin = "wow"; S.UI_ApplyLook()
  S.UI_Tab("sessions"); S.UI_Tab("sync"); S.UI_Tab("path"); S.UI_Tab("catchup")
end
print("look switches done, snags:", snag)
