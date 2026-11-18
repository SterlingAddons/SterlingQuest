-- Sterling Quest Sync: partner quest status
-- 1) Tooltips: under each quest title Questie adds to a mob/object/item tooltip (and its map pins),
--    one line per status: "Done: Brannoc, Tovak" / "In log: Grukk 3/8". Nothing if no partner started it.
-- 2) Quest log and the NPC quest window: under the quest title, one line per status, including "Not started".
local ADDON, S = ...

local C_DONE, C_READY, C_LOG, C_NONE, C_NAME = "|cff7ee2a2", "|cffb5f0cf", "|cfff3c56b", "|cff8a93a8", "|cffd6dbe8"

-- darker set for the "Dark ink" quest log style (no outline, on parchment)
-- tooltip bar: the game's tooltip frame with the warm colours of the quest window's Rewards banner
-- all four picked for similar brightness (none pops) and about 5:1 contrast on the bar
-- Tooltip bar looks (Options > Quest status > Bar colours). Picked in game, since screenshots (HDR) look brighter.
-- bg/edge nil = no box. dark = text is dark ink with no shadow.
S.TIP_LOOKS =
{
    { "warm",  "Warm brown (light text)",      bg = { .28, .2, .12, .75 }, edge = { .8, .68, .44, .85 }, text = { done = "b3e6b6", ready = "cdf0cf", log = "f7e0a6", none = "e6dcc6" } },
    { "tan",   "Reward box (tan, dark text)",  bg = { .84, .73, .51, .95 }, edge = { .54, .42, .2, 1 }, dark = true, text = { done = "1f5a2c", ready = "2a6b3a", log = "6a4500", none = "5a4a30" } },
    { "shade", "Faint shade (dark text)",      bg = { .47, .35, .16, .16 }, edge = { .47, .35, .16, .45 }, dark = true, text = { done = "1f5a2c", ready = "2a6b3a", log = "6a4500", none = "5a4a30" } },
    { "wood",  "Dark wood (gold text)",        bg = { .29, .21, .13, .95 }, edge = { .54, .42, .2, 1 }, text = { done = "a8d99b", ready = "c4e8b8", log = "ffd100", none = "d9c7a0" } },
    { "glass", "Soft tooltip (grey glass)",    bg = { .1, .09, .07, .62 }, edge = { .66, .55, .33, 1 }, text = { done = "a9e0ad", ready = "c8eccb", log = "f4dc9a", none = "e2d9c6" } },
    { "rule",  "Clear with a gold side line", box = false, rule = true, ruleColor = { .8, .52, .1, 1 }, dark = true, text = { done = "17502a", ready = "205f33", log = "5e3d00", none = "3f3018" } },
}

-- box = false: no frame, the text sits right on the page. rule: a coloured line down the left edge.
local function copyLook(l)
    local c = { box = l.box ~= false, rule = l.rule and true or false, dark = l.dark and true or false, text = {} }

    c.bg = { unpack(l.bg or { .28, .2, .12, .75 }) }
    c.edge = { unpack(l.edge or { .8, .68, .44, .85 }) }
    c.ruleColor = { unpack(l.ruleColor or { .8, .52, .1, 1 }) }

    for k, v in pairs(l.text or {}) do c.text[k] = v end

    c.base = l.base or l[1]

    return c
end

S.CopyLook = copyLook

-- One of the quest log status looks by key
local function presetLook(key)
    for _, l in ipairs(S.TIP_LOOKS) do if l[1] == key then return l end end

    return nil
end

-- The look the quest log status uses (a preset or your custom one)
local function tipLook()
    local key = S.Opt("tipLook", "warm")

    if key == "custom" then
        local c = SterlingQuestDB and SterlingQuestDB.opts and SterlingQuestDB.opts.tipCustom

        if type(c) == "table" and type(c.text) == "table" then return c end

        key = "warm"
    end

    return presetLook(key) or S.TIP_LOOKS[1]
end

S.TipLook = tipLook

-- The custom look, made from whatever is showing now the first time it is edited.
function S.TipCustom()
    local o = SterlingQuestDB.opts

    if S.Opt("tipLook", "warm") ~= "custom" or type(o.tipCustom) ~= "table" then
        o.tipCustom = copyLook(tipLook()); o.tipLook = "custom"
    end

    return o.tipCustom
end

local TIP = setmetatable({}, { __index = function(_, st) local t = tipLook().text[st]; return t and ("|cff" .. t) or nil end })
local INK = { done = "|cff11542a", ready = "|cff1b6136", log = "|cff6a4400", none = "|cff5a4a2e" }
local MARK = "|cff7ee2a3"
local SPACER = "Interface\\Minimap\\UI-bonusobjectiveblob-inside.blp"   -- Questie's blank indent texture   -- unique tag so a tooltip line is never decorated twice

local function short(n) return n and (n:match("^([^%-]+)") or n) or "?" end

-- Your nickname for them, else the name they chose, else their character's first name.
local function display(name)
    if S.PartnerLabel then return S.PartnerLabel(name) end

    local n = short(name)

    return n:match("^(%S+)") or n
end

-- Is this person in your group?
local function inMyGroup(name)
    local n = short(name)

    return (UnitInParty and UnitInParty(n)) or (UnitInRaid and UnitInRaid(n)) and true or false
end

-- People in the Sync list with the eye on whose quest log we have (never yourself), sorted by name.
local function knownSnaps()
    local out = {}
    local groupOnly = S.Opt("statusGroupOnly", false)
    local me = UnitName("player")

    for _, partner in ipairs(S.Partners and S.Partners() or {}) do
        local snap = S.snaps and S.snaps[partner.name]

        if type(snap) == "table" and type(snap.log) == "table" and partner.name ~= me and not (S.IsMe and S.IsMe(partner.name)) and partner.show ~= false and (not groupOnly or inMyGroup(partner.name)) then
            out[#out + 1] = { name = partner.name, sn = snap }
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)

    return out
end

-- "3/8" progress for a partner's quest, from its objectives
local function progress(quest)
    local done, total, a1, b1 = 0, 0, nil, nil

    for _, objective in ipairs(quest.objs or {}) do
        local a, b = tostring(objective):match("(%d+)%s*/%s*(%d+)")

        if a then
            a, b = tonumber(a), tonumber(b)
            total = total + 1

            if a >= b then done = done + 1 end

            a1, b1 = a1 or a, b1 or b
        end
    end

    if total == 1 then return a1 .. "/" .. b1 end
    if total > 1 then return done .. " of " .. total .. " done" end

    return nil
end

-- state: done (turned in), ready (complete, not turned in), log (working on it), none (not started)
function S.QuestPartnerStatus(qid)
    local list = {}

    for _, p in ipairs(knownSnaps()) do
        local snap, st, extra = p.sn, "none", nil

        if snap.completed and snap.completed[qid] then st = "done"
        elseif snap.log[qid] then
            if snap.log[qid].complete then st = "ready" else st = "log"; if S.Opt("statusProgress", true) then extra = progress(snap.log[qid]) end end
        end

        list[#list + 1] = { name = display(p.name), state = st, extra = extra }
    end

    return list
end

---------------------------------------------------------------------------
-- Quest title lookup (tooltip lines carry titles, not ids)
---------------------------------------------------------------------------
local function norm(s)
    s = tostring(s or ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")   -- icons and Questie's spacer textures
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", "")
    s = s:gsub("^%s*%[[^%]]*%]%s*", "")        -- Questie's "[37] " level prefix
    s = s:gsub("%s*%([^%)]*%)%s*$", "")         -- trailing "(Complete)" and similar
    s = s:gsub("[|;,~%^:]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")

    return s:lower()
end

-- Partners send only IDs for quests they finished. Look up names for any
-- we don't know (Questie DB first, then the game), a batch at a time, once each.
local tried = {}

-- Names for quests partners finished, a few at a time so tooltips stay fast
local function resolvePartnerNames(budget)
    local saved = SterlingQuestDB and SterlingQuestDB.names or {}

    for _, snap in pairs(S.snaps or {}) do
        if type(snap) == "table" then
            for _, set in ipairs({ snap.completed or {}, snap.log or {} }) do
                for qid in pairs(set) do
                    if not tried[qid] then
                        tried[qid] = true

                        if not S.names[qid] and not saved[qid] then
                            local n = S.QuestName(qid)

                            if n and not n:find("^Quest #") then S.LearnName(qid, n) end

                            budget = budget - 1

                            if budget <= 0 then return false end
                        end
                    end
                end
            end
        end
    end

    return true
end

S.ResolvePartnerNames = resolvePartnerNames

local index, indexAt = {}, -100

-- Which quest a line of tooltip text is (by its title)
local function lookup(text)
    local now = GetTime()

    if now - indexAt > 3 then
        index, indexAt = {}, now

        resolvePartnerNames(400)

        for qid, title in pairs(SterlingQuestDB and SterlingQuestDB.names or {}) do index[norm(title)] = qid end
        for qid, title in pairs(S.names or {}) do index[norm(title)] = qid end
        for qid, quest in pairs(S.log or {}) do if quest.title then index[norm(quest.title)] = qid end end
        for _, snap in pairs(S.snaps or {}) do
            if type(snap) == "table" and snap.log then for qid, quest in pairs(snap.log) do if quest.title and quest.title ~= "" then index[norm(quest.title)] = index[norm(quest.title)] or qid end end end
        end
    end

    local k = norm(text)

    if k == "" then return nil end

    return index[k]
end

---------------------------------------------------------------------------
-- Status lines: one per state. Shared by tooltips and the quest log.
---------------------------------------------------------------------------
local ORDER = { "done", "ready", "log", "none" }
local LABEL = { done = "Done", ready = "Ready", log = "In log", none = "Not started" }
local COLOR = { done = C_DONE, ready = C_READY, log = C_LOG, none = C_NONE }

-- lines(list, opts): opts.none includes Not started; opts.compact drops the labels; opts.ink uses the dark colours.
local function lines(list, o)
    o = o or {}

    local g = { done = {}, ready = {}, log = {}, none = {} }

    for _, s in ipairs(list) do
        local grp = g[s.state]

        if grp then grp[#grp + 1] = s.name .. ((s.state == "log" and s.extra) and (" " .. s.extra) or "") end
    end

    local out = {}

    for _, st in ipairs(ORDER) do
        if #g[st] > 0 and (st ~= "none" or o.none) then
            local c = (o.tip and TIP[st]) or (o.ink and INK[st]) or COLOR[st]

            -- colour-blind mode always keeps the label: "names only" tells the states apart by colour alone
            out[#out + 1] = c .. ((o.compact and not S.ColorBlind()) and "" or (LABEL[st] .. ": ")) .. table.concat(g[st], ", ") .. "|r"
        end
    end

    return out
end

S.StatusLines = lines

local function tipLines(qid) return lines(S.QuestPartnerStatus(qid), { compact = S.Opt("tipStyle", "labels") == "compact" }) end

-- Sample lines for the Options page, using the current settings.
function S.StatusPreview()
    local p = S.Opt("statusProgress", true)
    local l = lines({ { name = "Bran", state = "done" }, { name = "Tovak", state = "done" },
                      { name = "Grukk", state = "log", extra = p and "3/8" or nil }, { name = "Zal", state = "ready" } },
                    { compact = S.Opt("tipStyle", "labels") == "compact" })
    return table.concat(l, "\n")
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local busy = false
local lastDump = ""

-- What is this tooltip about?  npc (friendly unit: quest givers and turn-ins), mob (attackable unit),
-- player, map (a pin on the world map or minimap), other (objects, items, anything else).
local function tooltipKind(tt)
    local ok, _, unit = pcall(tt.GetUnit, tt)

    if ok and type(unit) == "string" and not (issecretvalue and issecretvalue(unit)) then
        local okP, isPlayer = pcall(UnitIsPlayer, unit); if okP and isPlayer then return "player", unit end
        local okA, hostile = pcall(UnitCanAttack, "player", unit)

        if okA and hostile then return "mob", unit end

        return "npc", unit
    end

    local okO, f = pcall(tt.GetOwner, tt)
    local hops = 0

    while okO and type(f) == "table" and hops < 15 do
        if f == WorldMapFrame then return "map" end
        if f == Minimap then return "map" end

        local okG, parent = pcall(f.GetParent, f)

        if not okG then break end

        f = parent; hops = hops + 1
    end

    return "other"
end

-- Quests a friendly NPC starts or ends (Questie's database), from the unit's GUID.
local function npcQuests(unit)
    local okG, guid = pcall(UnitGUID, unit)

    if not okG or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end

    local kind, _, _, _, _, id = strsplit("-", guid)

    if kind ~= "Creature" then return nil end

    id = tonumber(id)

    if not id or not S.QuestieNPC then return nil end

    local out, seen = {}, {}

    for _, key in ipairs({ "questStarts", "questEnds" }) do
        local list = S.QuestieNPC(id, key)

        if type(list) == "table" then
            for _, qid in ipairs(list) do if not seen[qid] then seen[qid] = true; out[#out + 1] = qid end end
        end
    end

    return out
end

-- Is this tooltip line one of Questie's progress lines under a quest title ("0/15 Beast Entrails")?
local function isProgress(text)
    local plain = text:gsub("|T.-|t", " "):gsub("|A.-|a", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    if plain:match("^%s*$") then return false end

    return plain:match("^%s") ~= nil or plain:match("%d+%s*/%s*%d+") ~= nil or plain:match("^%s*%-") ~= nil
end

-- The text and font string of one tooltip line
local function textOf(name, i)
    local label = _G[name .. "TextLeft" .. i]

    if not label then return nil, nil end

    local ok, t = pcall(label.GetText, label)

    if not ok or type(t) ~= "string" or (issecretvalue and issecretvalue(t)) then return nil, label end

    return t, label
end

-- Adds partner status under each quest title in a tooltip
local function decorate(tt)
    if busy or not tt or not S.Opt("tipStatus", true) then return end
    if not next(S.snaps or {}) or not tt.IsShown or not tt:IsShown() then return end

    local name = tt.GetName and tt:GetName()

    if not name then return end

    local n = tt:NumLines() or 0

    -- already done for this showing?
    for i = 1, n do local t = textOf(name, i); if t and t:find(MARK, 1, true) then return end end

    busy = true

    local changed = false
    local dbgOn = S.ChatLevel and S.ChatLevel("tooltip") >= 3 and S.Debug
    local report = dbgOn and {} or nil
    local kind, unit = tooltipKind(tt)
    local compact = S.Opt("tipStyle", "labels") == "compact"

    if kind == "npc" then
        -- quest givers and turn-ins: list each of their quests that a partner has started or finished
        local qs = npcQuests(unit) or {}
        local first = true

        for _, qid in ipairs(qs) do
            local ls = lines(S.QuestPartnerStatus(qid), { compact = compact })

            if report then report[#report + 1] = "npc quest " .. qid .. " (" .. S.QuestName(qid) .. "): " .. #ls .. " line(s)" end
            if #ls > 0 then
                if first then tt:AddLine(" "); first = false end

                tt:AddLine(MARK .. "|r" .. S.ACCENT_HEX .. S.QuestName(qid) .. "|r")

                for _, l in ipairs(ls) do tt:AddLine("   " .. l) end

                changed = true
            end
        end
    elseif kind == "map" or ((kind == "mob" or kind == "other") and S.Opt("tipMobs", false)) then
        -- Questie's quest lines: our status goes under the quest's progress lines, not under the title
        local i = 2

        while i <= n do
            local text, fs = textOf(name, i)
            local qid = text and lookup(text)

            if text and qid then
                local ls = lines(S.QuestPartnerStatus(qid), { compact = compact })

                -- the last progress line under this title
                local j = i

                for k = i + 1, n do
                    local t2 = textOf(name, k)

                    if not t2 or lookup(t2) or not isProgress(t2) then break end

                    j = k
                end

                if report then report[#report + 1] = "line " .. i .. ": quest " .. qid .. " (" .. norm(text) .. "), progress to line " .. j .. ": " .. (#ls > 0 and ("added " .. #ls) or "nothing to add") end
                if #ls > 0 then
                    -- line up with the title: reuse its leading spaces and spacer textures
                    local lead = text:match("^([%s]*)") or ""
                    local rest = text:sub(#lead + 1)

                    while true do
                        local tex = rest:match("^(|T.-|t%s*)")

                        if not tex then break end

                        rest = rest:sub(#tex + 1)

                        if tex:find(SPACER, 1, true) then lead = lead .. tex
                        else
                            local h, w = tex:match("^|T[^:|]*:(%d+):?(%d*)")

                            w = tonumber(w) or tonumber(h) or 14
                            lead = lead .. "|T" .. SPACER .. ":1:" .. w .. "|t" .. (tex:match("(%s*)$") or "")
                        end
                    end

                    local add = {}

                    for k, l in ipairs(ls) do add[k] = lead .. (k == 1 and (MARK .. "  |r") or "  ") .. l end

                    local tj, fsj = textOf(name, j)

                    if fsj and tj then fsj:SetText(tj .. "\n" .. table.concat(add, "\n")); changed = true end
                end

                i = j + 1
            else
                if report and text and (text:find("%[%d") or text:find("|T")) then report[#report + 1] = "line " .. i .. ": no quest matches \"" .. norm(text) .. "\"" end

                i = i + 1
            end
        end
    elseif report then
        report[#report + 1] = "skipped: " .. kind .. " tooltip (status shows on quest givers and map pins" .. (kind == "mob" and "; Options > Quest status turns it on for mobs" or "") .. ")"
    end

    if report then
        local first = _G[name .. "TextLeft1"]
        local okT, title = pcall(function() return first and first:GetText() end)
        local head = (okT and type(title) == "string" and not (issecretvalue and issecretvalue(title))) and title or "?"
        local dump = head .. "|" .. kind .. "|" .. table.concat(report, "|")

        if dump ~= lastDump then
            lastDump = dump

            S.Debug("tooltip", name .. " (" .. kind .. ") \"" .. head .. "\": " .. (#report > 0 and "" or "no quest lines found"))

            for _, line in ipairs(report) do S.Debug("tooltip", "   " .. line) end
        end
    end

    if changed then pcall(tt.Show, tt) end

    busy = false
end

-- Tooltips fire constantly, in and out of combat. Whatever goes wrong in there must never leave the
-- "busy" flag stuck (that would switch the status lines off until a reload) or throw into the game's
-- own tooltip code.
local decorateRaw = decorate

-- Same, but an error can never leave the tooltip hook broken
decorate = function(tt)
    if busy then return end

    local ok, err = pcall(decorateRaw, tt)

    if not ok then busy = false; if S.Debug then S.Debug("tooltip", "skipped a tooltip: " .. tostring(err)) end end
end

S.DecorateTooltip = decorate

-- Hooks every tooltip that can show quests (mobs, Questie pins, items)
local function hookTooltips()
    if not GameTooltip then return end

    -- Hook Show on every game-style tooltip (mob tooltips, Questie's world map and minimap pins, items).
    local mt = getmetatable(GameTooltip)
    local proto = mt and type(mt.__index) == "table" and mt.__index
    local how

    if proto and type(proto.Show) == "function" then hooksecurefunc(proto, "Show", decorate); how = "all tooltips (shared Show)"
    else hooksecurefunc(GameTooltip, "Show", decorate); how = "GameTooltip only" end
    -- some clients give GameTooltip its own Show; hook that too so it can't slip past
    if rawget(GameTooltip, "Show") and proto and rawget(GameTooltip, "Show") ~= proto.Show then hooksecurefunc(GameTooltip, "Show", decorate); how = how .. " + GameTooltip's own Show" end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        for _, kind in ipairs({ "Unit", "Object", "Item" }) do
            local t = Enum.TooltipDataType[kind]

            if t then
                pcall(TooltipDataProcessor.AddTooltipPostCall, t, function(tt)
                    if tt ~= GameTooltip then return end

                    -- Questie may add its lines after us; look again on the next frame too.
                    C_Timer.After(0, function() decorate(GameTooltip) end)
                end)
            end
        end

        how = how .. ", plus post-calls for units, objects and items"
    end

    if S.Debug then S.Debug("tooltip", "hooked: " .. how) end
end

---------------------------------------------------------------------------
-- Quest log details and the NPC quest window
---------------------------------------------------------------------------
local blocks = {}; S.QuestLogBlocks = blocks   -- the details panel moves between windows; one status block per parent, only one shown

-- section: its own "Party progress:" heading below the objectives (like "Required items:")
-- plain: ink lines right under the title, one per partner (like objective text)
S.LOG_STYLES = { { "tooltip", "Tooltip bar" }, { "section", "Party progress section" }, { "plain", "Plain lines under the title" }, { "bar", "Dark bar" }, { "thick", "Thick outline" }, { "thin", "Thin outline" }, { "ink", "Dark ink" } }

function S.LogStyleName(key) for _, s in ipairs(S.LOG_STYLES) do if s[1] == key then return s[2] end end return S.LOG_STYLES[1][2] end
local function logStyle() return S.Opt("logStyle", "tooltip") end
local function parchment(style) return style == "section" or style == "plain" end

-- The quest shown in the NPC quest window or the quest log, if any
local function selectedQuest()
    -- the NPC quest window (accept / progress / turn in) shows one quest; GetQuestID names it
    if type(QuestFrame) == "table" and QuestFrame.IsShown and QuestFrame:IsShown() and type(GetQuestID) == "function" then
        local ok, q = pcall(GetQuestID); if ok and q and q > 0 then return q end
    end

    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, q = pcall(C_QuestLog.GetSelectedQuest); if ok and q and q > 0 then return q end
    end

    if GetQuestLogSelection then
        local i = GetQuestLogSelection()

        if i and i > 0 then
            if GetQuestLogTitle then local id = select(8, GetQuestLogTitle(i)); if id and id > 0 then return id end end
            if C_QuestLog and C_QuestLog.GetInfo then local info = C_QuestLog.GetInfo(i); if info and info.questID then return info.questID end end
        end
    end

    return nil
end

-- One line per partner, quest-text style: "Bran: Not started"
local function perPartner(list)
    local out = {}

    for _, st in ipairs(list) do
        local t

        if st.state == "done" then t = INK.done .. st.name .. ": Done|r"
        elseif st.state == "ready" then t = INK.ready .. st.name .. ": Ready to turn in|r"
        elseif st.state == "log" then t = INK.log .. st.name .. ": In log" .. (st.extra and (", " .. st.extra) or "") .. "|r"
        elseif S.Opt("logNone", true) then t = "|cff7a1414" .. st.name .. ": Not started|r" end
        if t then out[#out + 1] = t end
    end

    return out
end

-- The status text for one quest, in the chosen style
local function listText(list, style)
    if parchment(style) then return table.concat(perPartner(list), "\n") end

    return table.concat(lines(list, { none = S.Opt("logNone", true), ink = style == "ink", tip = style == "tooltip" }), "\n")
end

local function logText(qid) return listText(S.QuestPartnerStatus(qid), logStyle()) end

-- Every title a quest's details can sit under: the quest log / map panel, the NPC accept and
-- reward panels (all QuestInfoTitleHeader), and the NPC progress panel.
local function titleHeader()
    for _, n in ipairs({ "QuestInfoTitleHeader", "QuestLogQuestTitle", "QuestProgressTitleText" }) do
        local h = _G[n]

        if type(h) == "table" and h.IsVisible and h:IsVisible() then return h end
    end

    return nil
end

-- Where the "Party progress" section goes: after the objective lines, else after the objective text.
local function objectivesAnchor()
    for _, n in ipairs({ "QuestInfoObjectivesFrame", "QuestInfoObjectivesText", "QuestProgressText" }) do
        local h = _G[n]

        if type(h) == "table" and h.IsVisible and h:IsVisible() and (h:GetHeight() or 0) > 1 then return h end
    end

    return nil
end

-- Sets a font, falling back when the first one doesn't exist
local function setFont(label, objName, fallback)
    if not pcall(label.SetFontObject, label, objName) then pcall(label.SetFontObject, label, fallback) end
end

-- Applies the chosen look (box, side line, text colour) to the status block
local function applyStyle(block, style)
    local label = block.fs

    style = style or logStyle()

    block.head:Hide()

    if parchment(style) then
        -- the quest window's own fonts: QuestTitleFont for the heading, QuestFont for the lines
        setFont(label, S.Opt("logFont", "normal") == "normal" and "QuestFont" or "QuestFontNormalSmall", "GameFontHighlight")

        if not (label.GetFont and select(2, pcall(label.GetFont, label))) then setFont(label, "QuestFont", "GameFontHighlight") end

        pcall(label.SetShadowOffset, label, 0, 0)

        if block.SetBackdrop then block:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end

        block:SetBackdropColor(0, 0, 0, 0); block:SetBackdropBorderColor(0, 0, 0, 0)
        label:ClearAllPoints()

        if style == "section" then
            setFont(block.head, "QuestTitleFont", "GameFontNormalLarge")
            block.head:SetTextColor(.18, .11, .03); pcall(block.head.SetShadowOffset, block.head, 0, 0)
            block.head:SetText("Party progress:"); block.head:ClearAllPoints(); block.head:SetPoint("TOPLEFT", 0, 0); block.head:Show()
            label:SetPoint("TOPLEFT", block.head, "BOTTOMLEFT", 0, -4)
        else
            label:SetPoint("TOPLEFT", 0, 0)
        end

        block.pad, block.padX = 0, 0

        return
    end

    if style == "tooltip" then
        local look = tipLook()

        block.rule = block.rule or block:CreateTexture(nil, "ARTWORK")

        block.rule:Hide()

        local box = look.box ~= false and look.bg ~= nil

        if box then
            -- the tooltip frame: tooltip background and edge, coloured per look
            if block.SetBackdrop then block:SetBackdrop(S.BG_TIP or { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }) end

            block:SetBackdropColor(unpack(look.bg)); block:SetBackdropBorderColor(unpack(look.edge or { 0, 0, 0, 0 }))
        else
            -- clear: nothing behind the text
            if block.SetBackdrop then block:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end

            block:SetBackdropColor(0, 0, 0, 0); block:SetBackdropBorderColor(0, 0, 0, 0)
        end

        if look.rule then
            local color = look.ruleColor or { .8, .52, .1, 1 }
            local inset = box and 5 or 0

            block.rule:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            block.rule:SetWidth(3)
            block.rule:ClearAllPoints()
            block.rule:SetPoint("TOPLEFT", inset, -inset)
            block.rule:SetPoint("BOTTOMLEFT", inset, inset)
            block.rule:Show()
        end

        if look.dark then
            setFont(label, S.Opt("logFont", "normal") == "normal" and "QuestFont" or "QuestFontNormalSmall", "GameFontHighlight")
            pcall(label.SetShadowOffset, label, 0, 0)
        else
            pcall(label.SetFontObject, label, S.Opt("logFont", "normal") == "normal" and GameFontHighlight or GameFontHighlightSmall)
            pcall(label.SetShadowOffset, label, 1, -1); pcall(label.SetShadowColor, label, 0, 0, 0, 1)
        end

        label:ClearAllPoints()

        if box then
            label:SetPoint("TOPLEFT", look.rule and 14 or 8, -6); block.pad, block.padX = 12, look.rule and 22 or 16
        else
            label:SetPoint("TOPLEFT", look.rule and 10 or 0, -3); block.pad, block.padX = 6, look.rule and 12 or 2
        end

        return
    end

    if rawget(block, "rule") then block.rule:Hide() end
    if block.SetBackdrop then block:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end

    local base = S.Opt("logFont", "normal") == "normal" and GameFontHighlight or GameFontHighlightSmall
    local flag = (style == "thick" and "THICKOUTLINE") or (style == "thin" and "OUTLINE") or ""

    pcall(label.SetFontObject, label, base)

    local ok, file, size = pcall(label.GetFont, label)

    if ok and file then pcall(label.SetFont, label, file, size, flag) end
    if style == "thin" or style == "thick" then pcall(label.SetShadowOffset, label, 0, 0) else pcall(label.SetShadowOffset, label, 1, -1); pcall(label.SetShadowColor, label, 0, 0, 0, style == "ink" and 0 or .8) end
    if style == "bar" then
        block:SetBackdropColor(.08, .1, .18, .82); block:SetBackdropBorderColor(.2, .24, .36, .9)
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", 6, -4)

        block.pad, block.padX = 8, 12
    else
        block:SetBackdropColor(0, 0, 0, 0); block:SetBackdropBorderColor(0, 0, 0, 0)
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", 0, 0)

        block.pad, block.padX = 0, 0
    end
end

-- Put back anything we moved last time, so switching styles never leaves a frame anchored to our block.
-- Only if it is still hanging off our block: if the game re-laid the panel out since, its anchors are fresh.
local function stillOnBlock(r, block)
    local ok, n = pcall(r.GetNumPoints, r)

    if not ok or not n then return false end

    for i = 1, n do local _, rel = r:GetPoint(i); if rel == block then return true end end

    return false
end

-- Puts back the quest log pieces we moved to make room
local function restoreMoved(block)
    for _, m in ipairs(block.moved or {}) do
        if stillOnBlock(m.r, block) then
            if m.points then
                pcall(m.r.ClearAllPoints, m.r)

                for _, pt in ipairs(m.points) do pcall(m.r.SetPoint, m.r, unpack(pt)) end
            else pcall(m.r.SetPoint, m.r, m.p, m.rel, m.rp, m.x, m.y) end
        end
    end

    block.moved = {}
end

-- A sample block for the Options preview, drawn exactly like the quest log one.
local SAMPLE = { { name = "Bran", state = "done" }, { name = "Tovak", state = "ready" },
                 { name = "Grukk", state = "log", extra = "2/5" }, { name = "Zal", state = "none" } }
-- The live preview in Options, drawn by the same code as the real block
function S.StatusSample(parent)
    local frame = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)

    frame.fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); frame.fs:SetJustifyH("LEFT"); frame.fs:SetSpacing(2)
    frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); frame.head:SetJustifyH("LEFT")

    -- Redraws the preview at a width
    function frame.Render(maxW)
        local style = logStyle()

        applyStyle(frame, style)

        local list = {}

        for _, x in ipairs(SAMPLE) do
            list[#list + 1] = { name = x.name, state = x.state, extra = (x.extra and S.Opt("statusProgress", true)) and x.extra or nil }
        end

        local txt = listText(list, style)

        frame.fs:SetWidth(0); frame.fs:SetText(txt)

        local need = (frame.fs:GetStringWidth() or 100) + frame.padX

        if style == "section" then need = math.max(need, (frame.head:GetStringWidth() or 0)) end

        maxW = maxW or 260

        if need > maxW then frame.fs:SetWidth(maxW - frame.padX); need = maxW end

        frame:SetWidth(math.max(1, need))

        local h = (frame.fs:GetStringHeight() or 10) + frame.pad

        if style == "section" then h = h + (frame.head:GetStringHeight() or 16) + 4 end

        frame:SetHeight(math.max(1, h))

        return h
    end

    return frame
end

-- Shows or updates the partner status block in the quest log
function S.UpdateQuestLogStatus()
    local header = titleHeader()

    if not header then
        for _, block in pairs(blocks) do restoreMoved(block); block:Hide() end

        return
    end

    local parent = header:GetParent()
    local block = blocks[parent]

    if not block then
        block = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)

        if block.SetBackdrop then block:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }) end

        block.fs = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

        block.fs:SetJustifyH("LEFT"); block.fs:SetSpacing(2)

        block.head = block:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); block.head:SetJustifyH("LEFT")
        block.moved = {}
        blocks[parent] = block
    end

    for p, block in pairs(blocks) do if p ~= parent then restoreMoved(block); block.fs:SetText(""); block:Hide() end end

    restoreMoved(block)

    local qid = S.Opt("logStatus", true) and selectedQuest() or nil
    local txt = qid and logText(qid) or ""
    local style = logStyle()

    applyStyle(block)

    -- where it goes: the section takes the Description heading's place and pushes it down;
    -- without a Description heading it goes under the objectives; plain lines go under the title
    local anchor = header
    local desc = _G.QuestInfoDescriptionHeader
    local takeDesc = style == "section" and txt ~= "" and type(desc) == "table" and desc.IsVisible and desc:IsVisible() and desc:GetNumPoints() > 0

    if style == "section" and not takeDesc then anchor = objectivesAnchor() or header end

    local gap = (style == "section") and 10 or 4

    block:ClearAllPoints()

    if takeDesc then
        local pts = {}

        for i = 1, desc:GetNumPoints() do pts[i] = { desc:GetPoint(i) } end

        local p1 = pts[1]

        block:SetPoint("TOPLEFT", p1[2], p1[3] == "BOTTOMLEFT" and "BOTTOMLEFT" or p1[3], p1[4] or 0, p1[5] or -gap)

        block.moved[#block.moved + 1] = { r = desc, points = pts }

        desc:ClearAllPoints(); desc:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, -10)
    else
        block:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    end

    -- only as wide as the text needs; wrap only if it would run past the title's width
    local maxW = math.max(200, header:GetWidth() or 260)

    block.fs:SetWidth(0); block.fs:SetText(txt)

    local need = (block.fs:GetStringWidth() or 100) + block.padX

    if style == "section" then need = math.max(need, (block.head:GetStringWidth() or 0)) end
    if need > maxW then block.fs:SetWidth(maxW - block.padX); need = maxW end

    block:SetWidth(math.max(1, need))

    local h = (block.fs:GetStringHeight() or 10) + block.pad

    if style == "section" then h = h + (block.head:GetStringHeight() or 16) + 4 end

    block:SetHeight(math.max(1, h))
    block:SetShown(txt ~= "")

    if txt == "" or takeDesc then return end

    -- whatever sat right under our anchor now sits under our block (remembered, so it can be put back)
    local function fix(row)
        if row == block or row == block.fs or row == block.head or not row.GetNumPoints then return end

        for i = 1, row:GetNumPoints() do
            local p, rel, rp, x, y = row:GetPoint(i)

            if rel == anchor and p == "TOPLEFT" and rp == "BOTTOMLEFT" then
                block.moved[#block.moved + 1] = { r = row, p = p, rel = rel, rp = rp, x = x, y = y }

                row:SetPoint(p, block, rp, x, (y or 0) - 4)
            end
        end
    end

    for _, r in ipairs({ parent:GetRegions() }) do pcall(fix, r) end
    for _, c in ipairs({ parent:GetChildren() }) do pcall(fix, c) end
end

local function later() C_Timer.After(0, function() pcall(S.UpdateQuestLogStatus) end) end

-- Hooks the quest log and quest windows so the block follows them
local function hookQuestLog()
    for _, fn in ipairs({ "QuestInfo_Display", "QuestLog_UpdateQuestDetails", "QuestLog_Update", "SelectQuestLogEntry", "QuestMapFrame_ShowQuestDetails", "QuestFrameProgressPanel_OnShow", "QuestFrameDetailPanel_OnShow", "QuestFrameRewardPanel_OnShow" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, later) end
    end
end

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")

for _, ev in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_GREETING" }) do pcall(frame.RegisterEvent, frame, ev) end

frame:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGIN" then
        pcall(hookTooltips); pcall(hookQuestLog)
    elseif ev == "QUEST_LOG_UPDATE" then
        indexAt = -100; later()
    else
        later(); C_Timer.After(0.2, function() pcall(S.UpdateQuestLogStatus) end)
    end
end)
