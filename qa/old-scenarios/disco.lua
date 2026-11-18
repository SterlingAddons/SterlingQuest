local S = ...
local chat, sent = {}, {}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) chat[#chat + 1] = t end }
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.SendAddonMessage = function(p, text, chan, target) sent[#sent + 1] = { text = text, chan = chan, target = target }; return true end

for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "ADDON_LOADED", "Sterling") end end

local function msgIn(text, sender, ch) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, "CHAT_MSG_ADDON", "SterlingQuest", text, ch or "WHISPER", sender) end end end
local function pump() for i = 1, 40 do if S._tick then S._tick() end end end
local function lastSent(pat) for i = #sent, 1, -1 do if sent[i].text:find(pat) then return sent[i] end end end
local function saw(pat) for _, t in ipairs(chat) do if t:find(pat, 1, true) then return true end end return false end

SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true } }
IsInGroup = function() return true end; IsInRaid = function() return false end
GetNumGroupMembers = function() return 2 end
UnitName = function(u) if u == "party1" then return "Grukk" end if u == "player" then return "Kaelith" end return nil end
UnitIsConnected = function() return true end

-- party hello comes in
msgIn("HELLO\t6.18\tWARRIOR\t37", "Grukk-Forever", "PARTY")
print("found Grukk:", S.found.Grukk ~= nil and S.found.Grukk.src, "| party chat line:", saw("Grukk in your party has Sterling"), "| not a partner:", S.FindPartner("Grukk") == nil)
print("badge count:", S.FoundNewCount())

-- forged accept with no invite: ignored
msgIn("INVOK\t123456", "Grukk-Forever")
print("forged accept ignored:", S.FindPartner("Grukk") == nil)

-- real invite flow
S.Invite("Grukk")

local code = S.Invites().Grukk and S.Invites().Grukk.code

msgIn("INVOK\t999999", "Grukk-Forever")
print("wrong code ignored:", S.FindPartner("Grukk") == nil)
msgIn("INVOK\t" .. code, "Mallory-Forever")
print("right code from someone else ignored:", S.FindPartner("Mallory") == nil and S.FindPartner("Grukk") == nil)
msgIn("INVOK\t" .. code, "Grukk-Forever")
print("right code from Grukk accepted:", S.FindPartner("Grukk") ~= nil, saw("Grukk accepted"))

-- incoming invite shows a prompt, accept adds and answers with the code
local prompted

S.UI_InvitePrompt = function(from, c) prompted = { from, c } end

msgIn("INV\t424242", "Zalanya-Forever", "WHISPER")
print("invite prompt from Zalanya:", prompted and prompted[1], "| not added before click:", S.FindPartner("Zalanya") == nil)
S.AcceptInvite("Zalanya", "424242")
print("accepted adds Zalanya:", S.FindPartner("Zalanya") ~= nil)

-- block: x hides and ignores
msgIn("HELLO\t6.18\tMAGE\t40", "Pest-Forever", "GUILD")
S.Block("Pest")

prompted = nil

msgIn("INV\t111111", "Pest-Forever")
print("blocked: no prompt:", prompted == nil, "| hidden from list:", S.found.Pest == nil)

-- flood from a stranger gets muted
for i = 1, 40 do msgIn("HELLO\t6.18\tROGUE\t20", "Spammer-Forever", "GUILD") end

print("flooder muted:", saw("Ignoring Spammer"))

-- malformed: pipes in profile name stripped, bad version ignored
msgIn("PROF\tTroll\tgold\t|cffff0000|Hitem:1|hEvil|h", "Brannoc Ashvale-Forever")
print("profile name cleaned:", S.profiles["Brannoc Ashvale"] and S.profiles["Brannoc Ashvale"].name)
msgIn("HELLO\tabc\tMAGE\t40", "Weird-Forever", "GUILD")
print("bad hello ignored:", S.found.Weird == nil)

-- options window and add window build and refresh
print("add window:", pcall(S.UI_AddPartner)); print("options:", pcall(S.UI_Options))
print("link text:", S.InviteLink("Grukk"))

local f = _G.SterlingQuestAddPartner

-- sync progress on the Sync tab
SlashCmdList.STERLINGQUEST(""); S.UI_Tab("sync")

S.sync.prog = { who = "Brannoc Ashvale", dir = "in", got = 12, n = 20, t = GetTime() }

print("progress update:", pcall(S.UI_Update))
