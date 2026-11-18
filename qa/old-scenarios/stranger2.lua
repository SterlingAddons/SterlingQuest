local S = ...

for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "ADDON_LOADED", "Sterling") end end

local function msgIn(text, sender, ch) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "CHAT_MSG_ADDON", "SterlingQuest", text, ch or "WHISPER", sender) end end end

SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true } }
SterlingQuestDB.opts.groupSync = nil

msgIn("REQ\t6", "Randompug-Forever")
print("default, stranger whisper added:", S.FindPartner("Randompug") ~= nil)

SterlingQuestDB.opts.groupSync = true

msgIn("REQ\t6", "Whisperer-Forever")
print("group sync on, whisper from someone not grouped added:", S.FindPartner("Whisperer") ~= nil)

IsInGroup = function() return true end; IsInRaid = function() return false end
GetNumGroupMembers = function() return 2 end
UnitName = function(u) if u == "party1" then return "Groupmate" end if u == "player" then return "Kaelith" end return nil end
UnitIsConnected = function() return true end

msgIn("REQ\t6", "Groupmate-Forever", "PARTY")
print("group sync on, groupmate added:", S.FindPartner("Groupmate") ~= nil)
msgIn("REQ\t6", "Brannoc Ashvale-Forever")
print("existing partner still syncs:", S.FindPartner("Brannoc Ashvale") ~= nil)
