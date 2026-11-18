local S = ...

local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end

fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")

for i = 1, 12 do table.insert(SterlingQuestDB.sessions, { id = "x" .. i, name = "Run " .. i, char = "Kaelith", start = 1000 + i, stop = 2000 + i, events = {}, trail = {}, zones = {} }) end

S.UI_Toggle(true); S.UI_Tab("sessions"); S.UI_Update()

local pg; for _, f in ipairs(FRAMES) do if rawget(f, "recstate") then pg = f end end

print("rows show first:", pg.rows[1].sess and pg.rows[1].sess.name, "scrollbar shown:", pg.sb._shown)
pg.listArea._scripts.OnMouseWheel(pg.listArea, -1); pg.listArea._scripts.OnMouseWheel(pg.listArea, -1)
print("after scrolling down 2:", pg.rows[1].sess and pg.rows[1].sess.name, "offset", pg.offset)

for i = 1, 30 do pg.listArea._scripts.OnMouseWheel(pg.listArea, -1) end

print("clamped at bottom, last row:", pg.rows[7].sess and pg.rows[7].sess.name, "offset", pg.offset, "of", #SterlingQuestDB.sessions)
