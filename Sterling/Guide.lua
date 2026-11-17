-- Sterling Quest Sync: first-run welcome, the three-step tour, one-time tab tips and the Help window.
-- Everything here is optional reading: nothing in the addon depends on it, and every piece can be
-- reopened from Help (the "?" in the title bar) or Options > General.
local _, S = ...
local msg = S.msg
local Window, Button, Box = S.UI_Window, S.UI_Button, S.UI_Box

local welcome, coach, help, spot
local tour                      -- { steps = {...}, i = n } while the tour runs
local pendingWelcome, pendingTip
local function acct()
  if type(SterlingQuestAccountDB) ~= "table" then SterlingQuestAccountDB = {} end
  local a = SterlingQuestAccountDB
  a.hints = a.hints or {}; a.told = a.told or {}
  return a
end
-- After the look is switched every window is rebuilt; ours start over too.
function S.GuideReset()
  if spot then pcall(spot.Hide, spot) end
  welcome, coach, help, spot, tour = nil, nil, nil, nil, nil
end
function S.GuideScale() end   -- windows follow the Window size setting by themselves; kept for callers

---------------------------------------------------------------------------
-- Spotlight: a soft gold frame around the thing a tour step is talking about
---------------------------------------------------------------------------
local function Spot(target, pad)
  local main = S.UI_Main()
  if not target or not main then if spot then spot:Hide() end return end
  if not spot then
    spot = CreateFrame("Frame", nil, main)
    spot.fill = spot:CreateTexture(nil, "BACKGROUND"); spot.fill:SetAllPoints(); spot.fill:SetColorTexture(1, .82, 0, .07)
    local function edge(p1, p2, w, h)
      local t = spot:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(1, .82, 0, .95)
      t:SetPoint(p1); t:SetPoint(p2)
      if w then t:SetWidth(w) else t:SetHeight(h) end
      return t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 2); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    edge("TOPLEFT", "BOTTOMLEFT", 2, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
    local acc = 0
    spot:SetScript("OnUpdate", function(self, dt) acc = acc + dt; self:SetAlpha(.7 + .3 * math.sin(acc * 3)) end)
  end
  pad = pad or 3
  spot:SetParent(main)
  spot:SetFrameLevel(main:GetFrameLevel() + 30)
  spot:ClearAllPoints()
  spot:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad); spot:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
  spot:Show()
end

---------------------------------------------------------------------------
-- The coach: one small window beside the main one, used by the tour and by the tab tips
---------------------------------------------------------------------------
local COACH_W = 270
local function buildCoach()
  coach = Window("SterlingQuestCoach", COACH_W, 190, "Tour")
  local f = coach
  f.step = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.step:SetPoint("TOPLEFT", 14, -38); f.step:SetTextColor(S.LabelColor())
  f.dots = {}
  for i = 1, 3 do
    local d = f:CreateTexture(nil, "ARTWORK"); d:SetSize(7, 7); d:SetPoint("TOPRIGHT", -14 - (3 - i) * 12, -40)
    f.dots[i] = d
  end
  f.headline = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.headline:SetPoint("TOPLEFT", 14, -56); f.headline:SetPoint("RIGHT", -14, 0); f.headline:SetJustifyH("LEFT"); f.headline:SetTextColor(S.TR, S.TG, S.TB)
  f.body = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.body:SetPoint("TOPLEFT", 14, -76); f.body:SetWidth(COACH_W - 28); f.body:SetJustifyH("LEFT"); f.body:SetTextColor(.78, .8, .86)
  if f.body.SetSpacing then f.body:SetSpacing(2) end
  f.next = Button(f, "Next", 64); f.next:SetPoint("BOTTOMRIGHT", -14, 10)
  f.back = Button(f, "Back", 54); f.back:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
  f.skip = Button(f, "Skip", 54); f.skip:SetPoint("BOTTOMLEFT", 14, 10)
  -- closing it with the X (or Escape) ends whatever it was doing
  f:HookScript("OnHide", function()
    Spot(nil)
    if tour then tour = nil; if acct().tour ~= true then acct().tour = "skipped" end end
  end)
end
local function fitCoach()
  local h = math.max(12, coach.body:GetStringHeight() or 12)
  coach:SetHeight(76 + h + 16 + 21 + 10)
end

-- The tour. Each step opens a tab, puts the spotlight on one thing and says what it is for.
local STEPS = {
  { tab = "sync", title = "Add a friend",
    target = function(pg) return pg.add end, pad = 4,
    body = "Click |cffffd100+ Add|r and type a friend's character name, or pick someone Sterling found in your party, guild or friends list.\n\nThey get a prompt to accept. After that your quest logs sync by themselves whenever you're both online. Never online together? Right-click a partner for Offline sync." },
  { tab = "catchup", title = "Catch up",
    target = function(pg) return pg.zoneBox end, pad = 3,
    body = "Pick the friend and a zone. Sterling lists the quests they did there that you haven't, sorted into what you can pick up now, what's in your log and what's still locked.\n\n|cffffd100Start path|r turns that list into steps.",
    extra = function() if not S.HasAddon("Questie") then return "\n\n|cfff3c56bThis tab needs Questie, which isn't installed.|r" end end },
  { tab = "path", title = "Follow the path",
    target = function(pg) return pg.card end, pad = 3,
    body = "The card is your next step. |cffffd100Auto arrow|r points you at it, |cffffd100Done|r skips one Sterling can't see finish, and the list underneath is everything still to come.\n\nYou can also record your own run here and send it to a friend to follow." },
}
local function showStep()
  if not tour then return end
  if not coach then buildCoach() end
  local st = tour.steps[tour.i]
  local n = #tour.steps
  S.UI_Tab(st.tab)
  local pg = S.UI_Page(st.tab)
  local f = coach
  f.title:SetText("Tour")
  f.step:SetText("Step " .. tour.i .. " of " .. n); f.step:Show()
  for i, d in ipairs(f.dots) do
    d:SetShown(i <= n)
    if i == tour.i then d:SetColorTexture(1, .82, 0, 1) else d:SetColorTexture(.45, .43, .38, 1) end
  end
  f.headline:SetText(st.title)
  f.body:SetText(st.body .. ((st.extra and st.extra()) or ""))
  f.skip:SetText("Skip"); f.skip:Show(); f.skip:SetScript("OnClick", function() S.TourEnd(false) end)
  f.back:SetShown(tour.i > 1); f.back:SetScript("OnClick", function() if tour and tour.i > 1 then tour.i = tour.i - 1; showStep() end end)
  f.next:SetText(tour.i == n and "Finish" or "Next"); f.next:SetWidth(64)
  f.next:SetScript("OnClick", function()
    if not tour then return end
    if tour.i >= #tour.steps then S.TourEnd(true) else tour.i = tour.i + 1; showStep() end
  end)
  fitCoach()
  f:Show()
  Spot(pg and st.target(pg) or nil, st.pad)
end
function S.TourStart()
  if S.InCombat() then msg("The tour starts when you're out of combat.") pendingTip = "tour" return end
  if welcome then welcome:Hide() end
  local steps = {}
  for _, st in ipairs(STEPS) do
    if st.tab ~= "catchup" or S.Opt("catchupTab", true) then steps[#steps + 1] = st end
  end
  SterlingQuestDB.opts.expanded = true          -- the small Path view hides the tabs
  S.UI_Toggle(true)
  tour = { steps = steps, i = 1 }
  showStep()
end
function S.TourEnd(finished)
  local was = tour
  tour = nil
  local a = acct()
  if finished then
    a.tour = true
    for _, st in ipairs(was and was.steps or {}) do a.hints[st.tab] = true end   -- no tip needed for tabs the tour covered
    msg("That's the tour. The |cffffd100?|r in the title bar opens Help any time.")
  elseif a.tour ~= true then a.tour = "skipped" end
  Spot(nil)
  if coach then coach:Hide() end
end
function S.TourRunning() return tour ~= nil end

-- One-time tips: the first time a tab opens, if the tour didn't already cover it.
local TIPS = {
  catchup = { "Catch-up", "Pick a friend and a zone to see the quests they did there that you haven't. Start path turns the list into steps you can follow." },
  path = { "Path", "Your next step is on the card, with the rest listed under it. Record your own run here, or follow one a friend sent you. Auto arrow points at each step in turn." },
  sessions = { "Sessions", "Runs you recorded or were sent. Right-click one to follow it, see it on the map, export it as a string, send it to a partner, rename or delete it.\n\nSessions older than 30 days are packed to save room and open normally." },
  sync = { "Sync", "Your partners. + Add invites a friend; they accept and your quest logs stay in step whenever you're both online. Right-click a partner for Compare, Offline sync and more." },
}
local function showTip(key)
  local tip = TIPS[key]
  if not tip then return end
  if not coach then buildCoach() end
  local f = coach
  f.title:SetText("Tip")
  f.step:Hide(); for _, d in ipairs(f.dots) do d:Hide() end
  f.headline:SetText(tip[1]); f.body:SetText(tip[2])
  f.back:Hide()
  f.next:SetText("Got it"); f.next:SetWidth(64); f.next:SetScript("OnClick", function() f:Hide() end)
  local toured = acct().tour == true
  f.skip:SetShown(not toured); f.skip:SetText("Tour"); f.skip:SetScript("OnClick", function() f:Hide(); S.TourStart() end)
  f.tipFor = key
  fitCoach()
  f:Show()
end
-- Called whenever a tab is opened.
function S.GuideTab(key)
  if tour then
    -- you clicked a tab mid-tour: go to that tab's step if it has one
    local st = tour.steps[tour.i]
    if st and st.tab ~= key then
      for i, other in ipairs(tour.steps) do if other.tab == key then tour.i = i; showStep(); return end end
      Spot(nil)
    end
    return
  end
  local main = S.UI_Main()
  if not (main and main:IsShown()) then return end
  -- a tip about another tab has nothing to say here
  if coach and coach:IsShown() and coach.tipFor and coach.tipFor ~= key then coach:Hide() end
  if welcome and welcome:IsShown() then return end
  local a = acct()
  if a.hints[key] or not TIPS[key] then return end
  if S.InCombat() then pendingTip = key return end
  a.hints[key] = true
  showTip(key)
end

---------------------------------------------------------------------------
-- Welcome: once per account, at the first login with Sterling installed
---------------------------------------------------------------------------
local WELCOME_W = 400
local function buildWelcome()
  welcome = Window("SterlingQuestWelcome", WELCOME_W, 380, "Welcome")
  local f = welcome
  local inset = S.Inset(f); if inset then inset:SetPoint("TOPLEFT", 6, -30); inset:SetPoint("BOTTOMRIGHT", -6, 6) end
  local page = CreateFrame("Frame", nil, f); page:SetPoint("TOPLEFT", 12, -38); page:SetPoint("BOTTOMRIGHT", -12, 12)
  if inset then page:SetFrameLevel(inset:GetFrameLevel() + 2) end
  local W = WELCOME_W - 24
  local y = 0
  local mark = page:CreateTexture(nil, "OVERLAY"); mark:SetSize(22, 22); mark:SetPoint("TOPLEFT", 2, y - 1); mark:SetTexture("Interface\\AddOns\\Sterling\\Media\\icon")
  local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); head:SetPoint("LEFT", mark, "RIGHT", 6, 0); head:SetText("Sterling Quest Sync"); head:SetTextColor(1, .82, 0)
  y = y - 26
  local sub = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); sub:SetPoint("TOPLEFT", 4, y); sub:SetWidth(W - 8); sub:SetJustifyH("LEFT"); sub:SetTextColor(.78, .8, .86)
  sub:SetText("Quest with friends without losing track of who has done what.")
  y = y - 24
  local ITEMS = {
    { "Sync quest logs", "Add a friend on the Sync tab. Each of you sees what the other has in their log and has finished, on tooltips and in the quest log." },
    { "Catch up", "Pick a zone to get the quests they did there that you haven't, laid out as a path." },
    { "Follow a path", "Step by step, with an arrow on the next stop. Record your own run and send it to a friend." },
  }
  for i, it in ipairs(ITEMS) do
    local num = Box(page, nil, true); num:SetSize(20, 20); num:SetPoint("TOPLEFT", 4, y - 1)
    if num.SetBackdropColor then num:SetBackdropColor(1, .82, 0, .14); num:SetBackdropBorderColor(1, .82, 0, .45) end
    num.t = num:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); num.t:SetPoint("CENTER"); num.t:SetText(tostring(i)); num.t:SetTextColor(1, .82, 0)
    local t = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 34, y); t:SetText(it[1]); t:SetTextColor(S.TR, S.TG, S.TB)
    local d = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); d:SetPoint("TOPLEFT", 34, y - 16); d:SetWidth(W - 38); d:SetJustifyH("LEFT"); d:SetTextColor(.7, .74, .84)
    d:SetText(it[2])
    y = y - 16 - math.max(24, (d:GetStringHeight() or 24)) - 10
  end
  y = y - 2
  S.SectionBar(page, "Works with", y, W)
  y = y - 28
  f.works = {}
  for i, w in ipairs(S.WORKS_WITH) do
    local l = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetPoint("TOPLEFT", 4, y); l:SetWidth(W - 8); l:SetJustifyH("LEFT"); l:SetWordWrap(false)
    f.works[i] = l
    y = y - 16
  end
  local foot = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); foot:SetPoint("TOPLEFT", 4, y - 2); foot:SetWidth(W - 8); foot:SetJustifyH("LEFT"); foot:SetTextColor(.56, .6, .7)
  foot:SetText("Both are optional. The |cffffd100?|r in the title bar opens Help any time.")
  y = y - 2 - math.max(12, foot:GetStringHeight() or 12)
  f:SetHeight(38 + (-y) + 16 + 21 + 12)   -- title, content, gap, buttons, bottom margin
  -- centred pair, like every other pop-up
  f.go = Button(page, "Take the tour", 110); f.later = Button(page, "Skip for now", 100)
  f.go:SetPoint("BOTTOMRIGHT", page, "BOTTOM", -3, 0); f.later:SetPoint("BOTTOMLEFT", page, "BOTTOM", 3, 0)
  f.go:SetScript("OnClick", function() S.TourStart() end)
  f.later:SetScript("OnClick", function() f:Hide(); if S.UI_Main() and S.UI_Main():IsShown() then S.GuideTab(S.UI_CurrentTab()) end end)
  f.refresh = function()
    for i, w in ipairs(S.WORKS_WITH) do
      local has = S.HasAddon(w.key)
      f.works[i]:SetText(S.Mark(has and "good" or "warn", true) .. S.TEXT_HEX .. w.name .. "|r  " .. (has and "|cff7ee2a2installed|r" or "|cfff3c56bnot installed|r") .. "  |cff8a93a8" .. (w.key == "Questie" and "Catch-up, quest names, status on quest givers" or "the arrow to your next step") .. "|r")
    end
  end
end
function S.UI_Welcome()
  if not welcome then buildWelcome() end
  welcome.refresh()
  welcome:Show()
end
-- A few seconds after the first login: the welcome page, once per account.
function S.GuideLogin()
  local a = acct()
  if a.welcomed then return end
  if S.InCombat() then pendingWelcome = true return end
  a.welcomed = true
  S.UI_Welcome()
end
function S.GuideAfterCombat()
  if pendingWelcome then pendingWelcome = nil; S.GuideLogin() end
  if pendingTip == "tour" then pendingTip = nil; S.TourStart()
  elseif pendingTip then local k = pendingTip; pendingTip = nil; if S.UI_CurrentTab() == k then S.GuideTab(k) end end
end

---------------------------------------------------------------------------
-- Help: sections on the left, the text on the right
---------------------------------------------------------------------------
-- { key, title, { blocks } }   block = { h = "heading" } | { p = "paragraph" } | { l = { "bullet", ... } }
local HELP = {
  { "start", "Getting started", {
    { p = "Sterling Quest Sync keeps you and your friends in step while you level. It shares quest logs, shows who has done what, works out what you still need in a zone, and walks you along a path." },
    { h = "Three things to try" },
    { l = { "Sync tab: + Add a friend. They accept, and your logs sync whenever you're both online.",
            "Catch-up tab: pick that friend and a zone, then Start path.",
            "Path tab: follow the steps. The arrow moves to each next stop." } },
    { h = "Getting around" },
    { l = { "The minimap button opens this window. Right-click it for the map, Shift-click to record or stop.",
            "Options is in the title bar. Everything is also a slash command: type /st for the list.",
            "Keybinds: Escape > Key Bindings > Sterling Quest Sync.",
            "Windows can be dragged anywhere and remember where you left them." } },
  } },
  { "sync", "Partners and sync", {
    { h = "Adding a partner" },
    { p = "Click + Add on the Sync tab and type a character name, or pick someone from the list Sterling found in your party, guild or friends. They get a prompt and both of you have to agree: nobody is ever added without clicking." },
    { p = "You can have up to 10 partners. Each one is a full quest history kept in your saved data." },
    { h = "What syncs" },
    { p = "Your quest log, your finished quests (in the order you did them), and your level. The first sync sends everything; after that only changes go out. Auto sync runs at login, when a partner comes online or joins your group, and every 5 minutes." },
    { h = "The partner list" },
    { l = { "Eye: show or hide that partner's status lines on tooltips and in the quest log.",
            "Right-click: Sync, Offline sync, Compare, Catch up, quest sharing, nickname, remove.",
            "Online needs them on your friends list, in your guild or in your group. Otherwise it says Can't tell; sync still works." } },
    { h = "Version notices" },
    { l = { "|cfff3c56bOutdated|r: their copy is older than yours. Sync still works. Newer features may not until they update.",
            "|cffff9b92Can't sync: update needed|r: the two copies speak different sync versions. Nothing is exchanged until the older one updates." } },
  } },
  { "offline", "Offline sync", {
    { p = "For when you and a partner are never online at the same time. Each of you makes a string and sends it to the other any way you like: Discord, a text, an email." },
    { h = "How to" },
    { l = { "Right-click a partner > Offline sync.",
            "Make string, then Ctrl+C. Long strings come in parts so each fits a Discord message; send every part.",
            "Paste the string they send you into Their string and press Import. Parts can go in one after another, in any order." } },
    { h = "What is in a string" },
    { p = "Only what changed since the last copy your partner confirmed, or everything if they hold nothing yet. If their side says a string doesn't continue from the update they have, press Full copy and send that instead." },
    { h = "Signing" },
    { p = "Strings are signed with a key only the two of you hold, so nobody else can feed you a fake quest log. The key is swapped by itself at your next live sync." },
    { p = "Before that, you can still send a full copy. It arrives unsigned and your partner is asked to confirm it. That first full copy carries your half of the key; once each of you has imported one from the other, strings are signed." },
    { p = "A key swapped by string is only as private as the place you pasted it. A live sync is the safer way to swap." },
    { h = "Sterling Quest Sync Companion app (optional)" },
    { p = "Want syncing even when you're not online together, without pasting strings? Try the optional Sterling Quest Sync Companion app, a Windows app that syncs your quests with friends when you play at different times. It carries your progress each way when you log out and in, and shows its status on the Sync tab. Options > Sync has the link in a box you can copy." },
    { p = "After installing the Companion app, exit WoW completely and start it again. The app adds a small Companion add-on (Sterling Quest Sync Companion in your AddOns list), and WoW only finds new add-ons when the game starts, so /reload isn't enough. Then make sure it's ticked in AddOns at character select." },
    { p = "Your Sterling partners pair in the Companion app on their own the next time you're both online in game. Pairing codes are only for people who aren't your partners in Sterling yet." },
    { h = "What the statuses mean" },
    { l = { "|cff7ee2a2Up to date|r: you have their latest progress and it's loaded.",
            "|cfff3c56bSyncing...|r: a live sync with them is running right now.",
            "|cfff3c56bNew copy, /reload to see it|r (in the Companion app): newer progress arrived; Sterling loads it at your next login or /reload.",
            "Paired. Waiting for their next save: paired in the Companion app, nothing from them yet.",
            "|cfff3c56bPairs when you're both next online|r: they have the app; pairing finishes next time you're both in game.",
            "|cffff7a73Doesn't have the app yet|r: you still sync live when you're both online. Offline syncing starts once they install the Companion app.",
            "Not online with you yet: Sterling hasn't heard from them about the app yet." } },
    { p = "\"Missing key, resync\" on a partner means the Companion app no longer has a key for you two (one of you reinstalled, or the pairing ended). Pair again in the app with a new code." },
  } },
  { "catchup", "Catch-up", {
    { p = "Shows the quests a partner finished in a zone that you haven't, and builds a path through them. It reads Questie's quest database, so it needs Questie installed." },
    { h = "The list" },
    { l = { "|cff7ee2a2Ready now|r: you can pick these up.",
            "|cff8ab8ffIn your log|r: you already have them.",
            "|cfff3c56bLocked|r: needs another quest first. The line says which.",
            "|cffff9b92Level|r: you're too low. The level you need is on the right." } },
    { h = "Path order" },
    { l = { "Shortest: the shortest walk from where you stand, picking up before doing before turning in.",
            "Their order: the order your partner finished them in." } },
    { p = "Start path sends the list to the Path tab. Show on map opens the zone." },
  } },
  { "path", "Path", {
    { p = "A list of steps to follow, from a Catch-up plan or from a recorded session." },
    { h = "The card" },
    { l = { "Shows the current step: what to do, where, and who to talk to.",
            "Click the /way to put the arrow there.",
            "Done marks a step finished when Sterling can't see it finish by itself." } },
    { h = "The list" },
    { l = { "Click a step to jump to it. Steps before it count as done.",
            "Click a done step to go back to it.",
            "Right-click a step to point the arrow there for a moment." } },
    { h = "The bottom row" },
    { l = { "Auto arrow: the arrow follows each next step by itself.",
            "Undo: takes back your last Done or jump.",
            "Clear: stops following. Nothing is deleted.",
            "Less / More: a small view with only the current step.",
            "Map: the path on a map, with playback. Import: paste a string a friend sent." } },
  } },
  { "record", "Recording and sessions", {
    { p = "Record a play session and a friend can follow your exact route: where you went, what you picked up and turned in, flights, boats, hearths, dungeons, levels and deaths." },
    { h = "Recording" },
    { l = { "Record and Stop are on the Path and Sessions tabs.",
            "Note adds a line for whoever follows you.",
            "Options > Recording: record automatically at login, and pick up an unfinished recording after a relog." } },
    { h = "Sessions" },
    { p = "Right-click a session to follow it, see it on the map, export it as a string, send it to a partner, rename it, merge it with another, compare two, or delete it. Deleted sessions wait in a trash of the last five; Restore brings one back." },
    { h = "Packing" },
    { p = "Sessions older than 30 days are packed: their trail and events are squeezed into one compressed block so your saved data stays small. Nothing is lost and you don't have to do anything. A packed session opens by itself when you use it. You can switch packing off in Options > Recording." },
  } },
  { "status", "Quest status", {
    { p = "Where your partners stand on a quest, shown where you're already looking." },
    { l = { "Tooltips: hover a quest giver, a turn-in or a map pin.",
            "Quest log and the NPC quest window: a block under the quest title.",
            "Four states: Done, Ready (to turn in), In log, Not started." } },
    { p = "Only partners with the eye on are shown. Options > Quest status picks the style, the colours and what gets a line." },
    { h = "Colour-blind mode" },
    { p = "Options > General > Accessibility. Adds a symbol or a word wherever red and green carry meaning, and keeps the labels on every status line." },
  } },
  { "trouble", "Troubleshooting", {
    { h = "A sync didn't finish" },
    { p = "Press Refresh on the Sync tab, then sync again. If it keeps failing, check the partner's row: a red Can't sync notice means one of you needs to update." },
    { h = "It says Can't tell" },
    { p = "The game only tells addons who is online for friends, guildmates and group members. Add them as a friend." },
    { h = "Catch-up is empty" },
    { p = "It needs Questie, and a partner who has synced at least once." },
    { h = "No arrow" },
    { p = "The arrow is TomTom's. Without TomTom, Sterling marks the next step with the game's own map pin." },
    { h = "After an update" },
    { p = "If something looks half-updated, quit the game fully and start it again. A /reload doesn't pick up brand new files." },
    { h = "Something looks wrong" },
    { p = "Options > General > Reset all settings puts every option back. Your partners, quest data and sessions stay. If you're asked for details, Sync state and Sync traffic below print what sync is doing into chat." },
  } },
  { "credits", "Credits", {
    { p = "Sterling Quest Sync is made by Sterling for WoW Forever." },
    { h = "Works with" },
    { l = { "Questie, by the Questie team: the quest database behind Catch-up, quest names and tooltip status.",
            "TomTom, by Cladhaire: the waypoint arrow." } },
    { h = "Built with" },
    { l = { "ChatThrottleLib, by Mikk: keeps addon messages inside the game's limits.",
            "LibDeflate, by Haoqian He: compression for offline sync strings and packed sessions.",
            "LibStub: the library loader both of those use." } },
    { p = "Thank you to everyone who tested it and sent bug reports." },
  } },
}
local HELP_W, HELP_H, NAV_W = 480, 560, 128   -- the same size as Options, so it fits beside the main window the same way
local function helpShow(key)
  local f = help
  local sec
  for _, s in ipairs(HELP) do if s[1] == key then sec = s end end
  sec = sec or HELP[1]
  f.key = sec[1]
  for _, b in ipairs(f.nav) do
    local on = b.key == sec[1]
    b.sel:SetShown(on); b.rule:SetShown(on)
    if on then b.text:SetTextColor(S.Accent()) else b.text:SetTextColor(.78, .8, .86) end
  end
  for _, l in ipairs(f.lines) do l:Hide() end
  local W = f.textW
  local y, n = -2, 0
  local function line(font)
    n = n + 1
    local l = f.lines[n]
    if not l then l = f.content:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetJustifyH("LEFT"); l:SetJustifyV("TOP"); f.lines[n] = l end
    l:SetFontObject(font); l:Show(); l:ClearAllPoints()
    if l.SetSpacing then l:SetSpacing(font == S.FONT_SMALL and 2 or 0) end
    return l
  end
  local title = line("GameFontNormalLarge"); title:SetPoint("TOPLEFT", 0, y); title:SetWidth(W); title:SetText(sec[2]); title:SetTextColor(1, .82, 0)
  y = y - 26
  for _, blk in ipairs(sec[3]) do
    if blk.h then
      y = y - 4
      local l = line("GameFontNormal"); l:SetPoint("TOPLEFT", 0, y); l:SetWidth(W); l:SetText(blk.h); l:SetTextColor(S.LabelColor())
      y = y - 18
    elseif blk.p then
      local l = line(S.FONT_SMALL); l:SetPoint("TOPLEFT", 0, y); l:SetWidth(W); l:SetText(blk.p); l:SetTextColor(.82, .84, .9)
      y = y - math.max(12, l:GetStringHeight() or 12) - 8
    elseif blk.l then
      for _, item in ipairs(blk.l) do
        local dot = line(S.FONT_SMALL); dot:SetPoint("TOPLEFT", 2, y); dot:SetWidth(10); dot:SetText("|cffffd100-|r")
        local l = line(S.FONT_SMALL); l:SetPoint("TOPLEFT", 14, y); l:SetWidth(W - 14); l:SetText(item); l:SetTextColor(.82, .84, .9)
        y = y - math.max(12, l:GetStringHeight() or 12) - 5
      end
      y = y - 3
    end
  end
  f.content:SetHeight(-y + 8)
  f.scroll:SetVerticalScroll(0)
  local trouble = sec[1] == "trouble"
  f.state:SetShown(trouble); f.traffic:SetShown(trouble)
end
local function buildHelp()
  help = Window("SterlingQuestHelp", HELP_W, HELP_H, "Sterling Quest Sync help")
  local f = help
  local inset = S.Inset(f); if inset then inset:SetPoint("TOPLEFT", 6, -30); inset:SetPoint("BOTTOMRIGHT", -6, 6) end
  local page = CreateFrame("Frame", nil, f); page:SetPoint("TOPLEFT", 12, -38); page:SetPoint("BOTTOMRIGHT", -12, 12)
  if inset then page:SetFrameLevel(inset:GetFrameLevel() + 2) end
  -- sections down the left
  f.nav = {}
  for i, sec in ipairs(HELP) do
    local b = CreateFrame("Button", nil, page); b:SetSize(NAV_W, 22); b:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    b.key = sec[1]
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(S.AR, S.AG, S.AB, .12)
    b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(S.AR, S.AG, S.AB, .14); b.sel:Hide()
    b.rule = b:CreateTexture(nil, "ARTWORK"); b.rule:SetPoint("TOPLEFT"); b.rule:SetPoint("BOTTOMLEFT"); b.rule:SetWidth(3); b.rule:SetColorTexture(1, .76, .2, 1); b.rule:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); b.text:SetPoint("LEFT", 10, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false); b.text:SetText(sec[2])
    b:SetScript("OnClick", function() helpShow(sec[1]) end)
    f.nav[i] = b
  end
  local div = page:CreateTexture(nil, "ARTWORK"); div:SetPoint("TOPLEFT", NAV_W + 7, 0); div:SetPoint("BOTTOMLEFT", NAV_W + 7, 28); div:SetWidth(1); div:SetColorTexture(1, 1, 1, .08)
  -- the text
  f.scroll = CreateFrame("ScrollFrame", "SterlingQuestHelpScroll", page, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", NAV_W + 16, 0); f.scroll:SetPoint("BOTTOMRIGHT", -24, 30)
  f.textW = HELP_W - 24 - (NAV_W + 16) - 24 - 6
  f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(f.textW, 10); f.scroll:SetScrollChild(f.content)
  f.lines = {}
  -- bottom row: same baseline and gaps as every other window
  f.tour = Button(page, "Replay the tour", 112); f.tour:SetPoint("BOTTOMLEFT", 0, 0)
  f.tour:SetScript("OnClick", function() S.TourStart() end)
  f.welcome = Button(page, "Welcome page", 100); f.welcome:SetPoint("LEFT", f.tour, "RIGHT", 4, 0)
  f.welcome:SetScript("OnClick", function() S.UI_Welcome() end)
  f.traffic = Button(page, "Sync traffic", 92); f.traffic:SetPoint("BOTTOMRIGHT", 0, 0)
  f.traffic:SetScript("OnClick", function()
    local t = S.sync and S.sync.trace or {}
    msg("Last " .. #t .. " sync messages (newest first). Refused by the game so far: " .. tostring(S.sync and S.sync.throttled or 0) .. ", missing-part requests answered: " .. tostring(S.sync and S.sync.partsResent or 0) .. ".")
    for i = 1, #t do DEFAULT_CHAT_FRAME:AddMessage("|cff8a93a8  " .. t[i] .. "|r") end
  end)
  f.state = Button(page, "Sync state", 84); f.state:SetPoint("RIGHT", f.traffic, "LEFT", -4, 0)
  f.state:SetScript("OnClick", function() S.PrintSyncState() end)
end
function S.UI_Help(key)
  if not help then buildHelp() end
  helpShow(key or help.key or "start")
  help:Show()
end
