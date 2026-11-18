local S = ...
local chat = {}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) chat[#chat + 1] = t end }

for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "ADDON_LOADED", "Sterling") end end

local function msgIn(text, sender) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "CHAT_MSG_ADDON", "SterlingQuest", text, "PARTY", sender) end end end

SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true } }
SterlingQuestDB.opts.groupSync = false; msgIn("REQ\t6", "Randompug-Forever"); msgIn("REQ\t6", "Randompug-Forever")

print("stranger not added:", #S.Partners() == 1, "| one note:", #(function() local n = {} for _, t in ipairs(chat) do if t:find("trying to sync") then n[#n+1] = t end end return n end)())

SterlingQuestDB.opts.groupSync = true

msgIn("REQ\t6", "Randompug-Forever")
print("with group sync on, added:", S.FindPartner("Randompug") ~= nil)

IsInGroup = function() return true end; IsInRaid = function() return false end
SterlingQuestDB.opts.groupSync = false

local t = S.Targets(); local hasGroup = false; for _, x in ipairs(t) do if x.key == "GROUP" then hasGroup = true end end

print("group sync off: no party broadcast:", not hasGroup)
