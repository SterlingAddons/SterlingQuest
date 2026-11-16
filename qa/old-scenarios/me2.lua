local S = ...
UnitName = function() return "Kaelith" end
for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "ADDON_LOADED", "Sterling") end end
local function msgIn(text, sender) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "CHAT_MSG_ADDON", "SterlingQuest", text, "PARTY", sender) end end end
SterlingQuestDB.partners = { { name = "Kaelith Emberfall", on = true }, { name = "Brannoc Ashvale", on = true } }
print("before: IsMe('Kaelith Emberfall') =", S.IsMe("Kaelith Emberfall"))
msgIn("ME\t" .. S.SESSION_TOKEN, "Kaelith Emberfall-Forever")
print("after token echo: partners", #S.Partners(), S.Partners()[1].name, "| learned", SterlingQuestDB.myFullName, "| IsMe now", S.IsMe("Kaelith Emberfall"))
msgIn("VER\t6", "Kaelith Emberfall-Forever"); print("echo VER ignored, partners:", #S.Partners())
msgIn("ME\t123", "Brannoc Ashvale-Forever"); print("someone else's token keeps them:", #S.Partners())
-- profile heuristic
SterlingQuestDB.myFullName = nil
SterlingQuestDB.partners = { { name = "Kaelith Emberfall", on = true } }
local p = S.Profile()
msgIn("PROF\t" .. (p.race or "Troll") .. "\t" .. (p.color or "gold") .. "\t" .. (p.name or ""), "Kaelith Emberfall-Forever")
print("identical profile + first name match removed:", #S.Partners())
