local S = ...

local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then local ok, e = pcall(h, f, ev, ...); if not ok then print("ERR " .. ev .. ": " .. e) end end end end

fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)

SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true }, { name = "Tovak", on = true } }
S.snaps["Brannoc Ashvale"] = { log = { [123] = { title = "Tiger Mastery", complete = false, objs = { "Paw 0/1" } } }, completed = { [9001] = true }, seq = 3, at = time() - 100, level = 39, source = "live", name = "Brannoc Ashvale" }
S.snaps["Tovak"] = { log = {}, completed = {}, seq = 1, at = time() - 3 * 86400, level = 30, source = "saved", name = "Tovak" }

S.UI_Toggle(true)

for _, tab in ipairs({ "path", "sessions", "sync", "catchup" }) do S.UI_Tab(tab); S.UI_Update() end

S.UI_Options(); S.UI_Compare("Brannoc Ashvale"); S.UI_PartnerInfo("Brannoc Ashvale"); S.UI_ShareWindow("Brannoc Ashvale")

local p = S.UI_OptionsPage

-- options tabs
local optPage

for _, f in ipairs(FRAMES) do if rawget(f, "ShowTab") and rawget(f, "sections") then optPage = f end end
for _, k in ipairs({ "general", "sync", "status", "record" }) do print("opt tab " .. k, pcall(optPage.ShowTab, k)) end

-- click every button that has an OnClick, except destructive ones
local skip = { ["Empty the trash"] = true, ["Reset check-offs"] = true, ["Remove"] = true, ["Delete"] = true, ["Stop"] = true, ["Record"] = true, ["Reset counters"] = true, ["Stop following"] = true, ["Sure?"] = true, ["Discard"] = true, ["Apply"] = true }
local n, bad = 0, 0

for _, f in ipairs(FRAMES) do
    local h = f._scripts.OnClick

    if h then
        local t = f._text

        if type(t) ~= "string" or not skip[t] then
            n = n + 1

            local ok, e = pcall(h, f, "LeftButton")

            if not ok then bad = bad + 1; print("CLICK FAIL [" .. tostring(t) .. "]: " .. tostring(e)) end
            if S.HideMenus then S.HideMenus(1) end
        end
    end
end

print("clicked", n, "buttons,", bad, "failed")

-- right-click the partner rows and hover handlers
local hov, hbad = 0, 0

for _, f in ipairs(FRAMES) do
    local h = f._scripts.OnEnter

    if h then hov = hov + 1; local ok, e = pcall(h, f); if not ok then hbad = hbad + 1; print("ENTER FAIL: " .. tostring(e)) end; if f._scripts.OnLeave then pcall(f._scripts.OnLeave, f) end end
end

print("hovered", hov, "widgets,", hbad, "failed")

-- mouse wheel handlers
local wh, wbad = 0, 0

for _, f in ipairs(FRAMES) do
    local h = f._scripts.OnMouseWheel

    if h then wh = wh + 1; for _, d in ipairs({ 1, -1, -1, 1 }) do local ok, e = pcall(h, f, d); if not ok then wbad = wbad + 1; print("WHEEL FAIL: " .. tostring(e)) break end end end
end

print("wheeled", wh, "lists,", wbad, "failed")

-- every update path once more with everything open
print("final update:", pcall(S.UI_Update))

-- quest log status for each style
for _, st in ipairs({ "tooltip", "section", "plain", "bar", "thick", "thin", "ink" }) do SterlingQuestDB.opts.logStyle = st; local ok, e = pcall(S.UpdateQuestLogStatus); if not ok then print("LOGSTYLE FAIL " .. st .. ": " .. e) end end

print("log styles ok")

-- slash commands
for _, c in ipairs({ "", "options", "compare", "sessions", "sync", "status", "help", "partner Brannoc Ashvale", "journal Brannoc Ashvale" }) do local ok, e = pcall(SlashCmdList.STERLINGQUEST, c); if not ok then print("SLASH FAIL /st " .. c .. ": " .. e) end end

print("slash ok")
print("profile window:", pcall(S.UI_Profile), pcall(S.UI_Update))

for _, l in ipairs(S.TIP_LOOKS) do SterlingQuestDB.opts.logStyle = "tooltip"; SterlingQuestDB.opts.tipLook = l[1]; local ok, e = pcall(S.UpdateQuestLogStatus); if not ok then print("LOOK FAIL", l[1], e) end end

print("bar looks ok")
