local S = ...
UnitName = function() return "Kaelith Emberfall" end
GetNormalizedRealmName = function() return "Forever" end
for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "ADDON_LOADED", "Sterling") end end
local nb = "Kaelith\194\160Store"
print("IsMe plain:", S.IsMe("Kaelith Emberfall"), "with realm:", S.IsMe("Kaelith Emberfall-Forever"), "no-break space:", S.IsMe(nb), "hyphen form:", S.IsMe("Kaelith-Emberfall-Forever"), "other:", S.IsMe("Brannoc Ashvale-Forever"), S.IsMe("Kaelith"))
print("AddPartner self (nbsp):", S.AddPartner(nb) == nil, "list size:", #S.Partners())
SterlingQuestDB.partners = { { name = nb, on = true }, { name = "Brannoc Ashvale", on = true } }
for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "CHAT_MSG_ADDON", "SterlingQuest", "PING", "PARTY", nb .. "-Forever") end end
print("after own echo, partners:", #S.Partners(), S.Partners()[1].name)
