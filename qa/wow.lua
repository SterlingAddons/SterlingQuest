-- A stand-in for the WoW UI API with real geometry: frames have parents, sizes, anchors, scale and
-- visibility that propagates like the game's, so layouts can be measured and checked.
local SCREEN_W, SCREEN_H = 1366, 768

ERRORS = 0; PRINT_CHAT = false; FONT_SCALE = 1; FOCUS = false; SEND = false
ALLREG = {}          -- every region ever made (frames, textures, font strings)
FRAMES = {}          -- frames only (kept for the older scenario files)

local FONT =
{       -- average glyph width, line height
    GameFontNormalSmall = { 5.7, 12 }, GameFontHighlightSmall = { 5.7, 12 }, SterlingFontSmall = { 5.7, 12 },
    GameFontNormal = { 6.7, 14 }, GameFontHighlight = { 6.7, 14 }, SterlingFont = { 6.7, 14 },
    GameFontNormalLarge = { 8.8, 18 }, ChatFontSmall = { 6.2, 13 }, QuestTitleFont = { 9, 20 }, QuestFont = { 6.9, 15 },
}

local function plain(t)
    t = tostring(t or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "##"):gsub("|A.-|a", "##"):gsub("|H.-|h", ""):gsub("|h", ""):gsub("||", "|")

    return t
end

PLAIN = plain

local methods = {}

local function eff(o) local s = 1; while o do s = s * (o._scale or 1); o = o._parent end return s end
local function visible(o) while o do if not o._shown then return false end o = o._parent end return true end
local function fontOf(o) return FONT[o._font or ""] or FONT.GameFontHighlightSmall end
local function textWidth(o, text)
    local w = 0

    for line in (plain(text or o._text) .. "\n"):gmatch("(.-)\n") do w = math.max(w, #line * fontOf(o)[1]) end

    return w * (FONT_SCALE or 1)
end

local RECT   -- forward

local function widthLimit(o)
    if o._w and o._w > 0 then return o._w end

    local l, r

    for _, p in ipairs(o._points) do
        if p[1]:find("LEFT") then l = true elseif p[1]:find("RIGHT") then r = true end
    end

    if l and r then local rc = RECT(o, true); if rc then return (rc[3] - rc[1]) / eff(o) end end

    return nil
end

local function textHeight(o)
    local f = fontOf(o)
    local lim = widthLimit(o)
    local lines = 0

    for line in (plain(o._text) .. "\n"):gmatch("(.-)\n") do
        local w = #line * f[1] * (FONT_SCALE or 1)

        if lim and lim > 0 and o._wrap ~= false then lines = lines + math.max(1, math.ceil(w / lim)) else lines = lines + 1 end
    end

    return math.max(1, lines) * (f[2] + (o._spacing or 0))
end

local busy = {}

RECT = function(o, widthOnly)
    if o == nil then return nil end
    if o._isUIParent then return { 0, 0, SCREEN_W, SCREEN_H } end
    if busy[o] then return nil end
    if o._scrollOwner then
        -- a scroll child sits at its scroll frame's top left, moved up by however far it is scrolled
        local sr = RECT(o._scrollOwner)

        if not sr then return nil end

        local es = eff(o)
        local w, h = (o._w or 0) * es, (o._h or 0) * es
        local top = sr[4] + (o._scrollOwner._vscroll or 0) * es

        return { sr[1], top - h, sr[1] + w, top }
    end

    busy[o] = true

    local es = eff(o)
    local L, R, CX, T, B, CY

    for _, p in ipairs(o._points) do
        local rel = p[2]

        if rel == nil then rel = o._parent end

        local rr = rel and RECT(rel) or { 0, 0, SCREEN_W, SCREEN_H }

        if rr then
            local rp = p[3]
            local ax = rp:find("LEFT") and rr[1] or (rp:find("RIGHT") and rr[3] or (rr[1] + rr[3]) / 2)
            local ay = rp:find("TOP") and rr[4] or (rp:find("BOTTOM") and rr[2] or (rr[2] + rr[4]) / 2)
            local px, py = ax + (p[4] or 0) * es, ay + (p[5] or 0) * es
            local pt = p[1]

            if pt:find("LEFT") then L = px elseif pt:find("RIGHT") then R = px else if CX and math.abs(CX - px) > 1 then o._ambX = math.abs(CX - px) end; CX = CX or px end
            if pt:find("TOP") then T = py elseif pt:find("BOTTOM") then B = py else if CY and math.abs(CY - py) > 1 then o._ambY = math.abs(CY - py) end; CY = CY or py end
        end
    end

    busy[o] = nil

    local w, h

    if L and R then w = R - L
    else
        local nat = o._w

        if (not nat or nat == 0) and o._kind == "FontString" then nat = textWidth(o) end

        w = (nat or 0) * es

        if not L then L = (R and R - w) or (CX and CX - w / 2) end
    end

    if widthOnly then if L then return { L, 0, L + w, 0 } end return nil end

    o._ambUsed = (not T and not B and o._ambY) or nil

    if T and B then h = T - B
    else
        local nat = o._h

        if (not nat or nat == 0) and o._kind == "FontString" then
            busy[o] = true; nat = textHeight(o); busy[o] = nil
        end

        h = (nat or 0) * es

        if not B then B = (T and T - h) or (CY and CY - h / 2) end
    end

    if not L or not B then return nil end

    return { L, B, L + w, B + h }
end

local function fire(o, name, ...)
    local h = o._scripts[name]

    if h then h(o, ...) end
end

local function cascade(o, name)
    fire(o, name)

    for _, c in ipairs(o._children) do if c._shown and c._scripts then cascade(c, name) end end
end

function methods.SetScript(self, n, f) self._scripts[n] = f end
function methods.HookScript(self, n, f) local old = self._scripts[n]; if old then self._scripts[n] = function(...) old(...); return f(...) end else self._scripts[n] = f end end
function methods.GetScript(self, n) return self._scripts[n] end
function methods.HasScript() return true end
function methods.SetPoint(self, p, a, b, c, d)
    if type(p) ~= "string" then error("SetPoint: bad point", 2) end

    local rel, rp, x, y

    if type(a) == "number" then rel, rp, x, y = nil, p, a, b
    elseif type(a) == "table" then
        rel = a

        if type(b) == "string" then rp, x, y = b, c, d else rp, x, y = p, b, c end
    elseif type(a) == "string" then rel, rp, x, y = nil, a, b, c        -- SetPoint("TOP", "BOTTOM", x, y) form is not used; treat as relPoint
    elseif a == nil and (type(b) == "string") then error("SetPoint: anchor frame is nil (" .. tostring(p) .. ")", 2)
    else rel, rp, x, y = nil, p, 0, 0 end
    for i, q in ipairs(self._points) do if q[1] == p then table.remove(self._points, i) break end end

    self._points[#self._points + 1] = { p, rel, rp, x or 0, y or 0 }
end

function methods.ClearAllPoints(self) self._points = {} end
function methods.SetAllPoints(self, rel) self._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } } end
function methods.GetPoint(self, i) local p = self._points[i or 1]; if p then return p[1], p[2] or self._parent, p[3], p[4], p[5] end end
function methods.GetNumPoints(self) return #self._points end
function methods.SetSize(self, w, h) self._w, self._h = w, h end
function methods.SetWidth(self, w) self._w = w end
function methods.SetHeight(self, h) self._h = h end
function methods.GetWidth(self) local r = RECT(self); return r and (r[3] - r[1]) / eff(self) or (self._w or 0) end
function methods.GetHeight(self) local r = RECT(self); return r and (r[4] - r[2]) / eff(self) or (self._h or 0) end
function methods.GetSize(self) return methods.GetWidth(self), methods.GetHeight(self) end
function methods.GetLeft(self) local r = RECT(self); return r and r[1] / eff(self) end
function methods.GetRight(self) local r = RECT(self); return r and r[3] / eff(self) end
function methods.GetTop(self) local r = RECT(self); return r and r[4] / eff(self) end
function methods.GetBottom(self) local r = RECT(self); return r and r[2] / eff(self) end
function methods.GetCenter(self) local r = RECT(self); if r then local e = eff(self); return (r[1] + r[3]) / 2 / e, (r[2] + r[4]) / 2 / e end end
function methods.GetRect(self) local r = RECT(self); if r then local e = eff(self); return r[1] / e, r[2] / e, (r[3] - r[1]) / e, (r[4] - r[2]) / e end end
function methods.SetScale(self, s) self._scale = s end
function methods.GetScale(self) return self._scale or 1 end
function methods.GetEffectiveScale(self) return eff(self) end
function methods.SetParent(self, p)
    if self._parent then for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end end

    self._parent = p

    if p then p._children[#p._children + 1] = self end
end

function methods.GetParent(self) return self._parent end
function methods.GetChildren(self) return unpack(self._children) end
function methods.GetName(self) return self._name end
function methods.GetObjectType(self) return self._kind end
function methods.Show(self)
    if self._shown then return end

    self._shown = true

    if self._scripts and visible(self) then cascade(self, "OnShow") end
end

function methods.Hide(self)
    if not self._shown then return end

    local was = visible(self)

    self._shown = false

    if self._scripts and was then
        fire(self, "OnHide")

        local function down(o) for _, c in ipairs(o._children) do if c._shown and c._scripts then fire(c, "OnHide"); down(c) end end end

        down(self)
    end
end

function methods.SetShown(self, v) if v then methods.Show(self) else methods.Hide(self) end end
function methods.IsShown(self) return self._shown end
function methods.IsVisible(self) return visible(self) end
function methods.IsMouseOver() return false end
function methods.SetText(self, v) self._text = v == nil and "" or tostring(v); if self._scripts and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end end
function methods.GetText(self) return self._text end
function methods.SetFormattedText(self, f, ...) self._text = f:format(...) end
function methods.GetStringWidth(self) return textWidth(self) end
function methods.GetUnboundedStringWidth(self) return textWidth(self) end
function methods.GetStringHeight(self) return textHeight(self) end
function methods.SetWordWrap(self, v) self._wrap = v end
function methods.SetSpacing(self, v) self._spacing = v end
function methods.SetFontObject(self, f) if type(f) == "string" then self._font = f elseif type(f) == "table" then self._font = f._fontName end end
function methods.SetJustifyH(self, v) self._jh = v end
function methods.SetJustifyV(self, v) self._jv = v end
function methods.Click(self, btn) if self._enabled ~= false and self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end end
function methods.Enable(self) self._enabled = true end
function methods.Disable(self) self._enabled = false end
function methods.SetEnabled(self, v) self._enabled = v and true or false end
function methods.IsEnabled(self) return self._enabled ~= false end
function methods.SetChecked(self, v) self._checked = v and true or false end
function methods.GetChecked(self) return self._checked or false end
function methods.SetFrameLevel(self, v) self._level = v end
function methods.GetFrameLevel(self) return self._level or ((self._parent and self._parent._level or 0) + 1) end
function methods.SetFrameStrata(self, v) self._strata = v end
function methods.GetFrameStrata(self) local o = self; while o do if o._strata then return o._strata end o = o._parent end return "MEDIUM" end
function methods.SetAlpha(self, v) self._alpha = v end
function methods.GetAlpha(self) return self._alpha or 1 end
function methods.SetTexture(self, v) self._tex = v; return true end
function methods.GetTexture(self) return self._tex end
function methods.SetColorTexture(self, r, g, b, a) self._tex = "color"; self._color = { r, g, b, a } end
function methods.SetAtlas(self, v) self._atlas = v end
function methods.GetAtlas(self) return self._atlas end
function methods.SetBackdrop(self, b) self._backdrop = b end
function methods.SetBackdropColor(self, r, g, b, a) self._bg = { r, g, b, a } end
function methods.SetBackdropBorderColor(self, r, g, b, a) self._edge = { r, g, b, a } end
function methods.SetTextColor(self, r, g, b, a) self._tc = { r, g, b, a } end
function methods.SetScrollChild(self, c) self._scrollChild = c; c._scrolled = true; c._scrollOwner = self end
function methods.GetScrollChild(self) return self._scrollChild end
function methods.GetVerticalScrollRange(self) local c = self._scrollChild; if not c then return 0 end return math.max(0, (c._h or 0) - methods.GetHeight(self)) end
function methods.SetVerticalScroll(self, v) self._vscroll = v end
function methods.GetVerticalScroll(self) return self._vscroll or 0 end
function methods.SetMinMaxValues(self, a, b) self._min, self._max = a, b end
function methods.SetValue(self, v) self._value = v; if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end
function methods.GetValue(self) return self._value or 0 end
function methods.HasFocus(self) return FOCUS == self end
function methods.GetCanvas(self) return self end
function methods.SetFocus(self) FOCUS = self; if self._scripts.OnEditFocusGained then self._scripts.OnEditFocusGained(self) end end
function methods.ClearFocus(self) if FOCUS == self then FOCUS = nil; if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end end end
function methods.NumLines(self) return self._lines and #self._lines or 0 end
function methods.AddLine(self, t) self._lines = self._lines or {}; self._lines[#self._lines + 1] = t end
function methods.AddDoubleLine(self, a, b) self._lines = self._lines or {}; self._lines[#self._lines + 1] = tostring(a) .. "  " .. tostring(b) end
function methods.ClearLines(self) self._lines = {} end
function methods.SetOwner(self) self._lines = {} end
function methods.GetColorRGB() return 1, 1, 1 end
function methods.IsObjectType(self, t) return self._kind == t end
local function new(kind, name, parent, template)
    local o = { _kind = kind, _name = name, _scripts = {}, _points = {}, _children = {}, _shown = true, _text = "", _template = template }

    if kind == "FontString" or kind == "Texture" or kind == "Line" then o._scripts = nil; o._region = true end

    setmetatable(o, { __index = function(t, k)
        local m = methods[k]

        if m then return m end
        if type(k) ~= "string" then return nil end
        if k:match("^Create") then
            return function(self, nm, layer, tpl)
                local what = k:sub(7)
                local c = new(what, nil, self, nil)

                if what == "FontString" then c._font = (type(tpl) == "string" and tpl) or "GameFontHighlightSmall" end

                return c
            end
        end

        if k:match("^Get") then return function() return 0 end end
        if k:match("^Is") or k:match("^Has") or k:match("^Can") then return function() return false end end
        if k:match("^%l") or k:match("^_") then return nil end     -- our own fields are lowercase; missing ones are nil like in the game

        return function(self) return self end
    end })

    if parent then o._parent = parent; parent._children[#parent._children + 1] = o end

    ALLREG[#ALLREG + 1] = o

    return o
end

MK = function() return new("Frame") end

function CreateFrame(kind, name, parent, template)
    if type(parent) ~= "table" or not rawget(parent, "_children") then parent = nil end

    local f = new(kind or "Frame", name, parent, template)

    FRAMES[#FRAMES + 1] = f

    if template == "UIPanelCloseButton" then f._w, f._h = 32, 32 end
    if template and template:find("UICheckButtonTemplate") then f._w, f._h = 32, 32 end
    if template == "UIPanelButtonTemplate" then f._w, f._h = 40, 22 end
    if template == "InputBoxTemplate" then f._h = 20 end
    if name and name ~= "" then rawset(_G, name, f) end

    return f
end

function CreateFont(name) local f = { _fontName = name }; f.SetFontObject = function(self, o) if FONT[o] then FONT[name] = FONT[o] end end; f.SetTextColor = function() end; rawset(_G, name, f); return f end

UIParent = new("Frame", "UIParent"); UIParent._isUIParent = true; UIParent._w, UIParent._h = SCREEN_W, SCREEN_H
Minimap = new("Frame", "Minimap", UIParent); Minimap._w, Minimap._h = 140, 140; Minimap._points = { { "TOPRIGHT", UIParent, "TOPRIGHT", -20, -20 } }
GameTooltip = new("GameTooltip", "GameTooltip", UIParent); GameTooltip._shown = false
WorldMapFrame = new("Frame", "WorldMapFrame", UIParent); WorldMapFrame._shown = false
ChatFontSmall = { _fontName = "ChatFontSmall" }
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) CHAT[#CHAT + 1] = tostring(t); if PRINT_CHAT then print("CHAT", t) end end }
UISpecialFrames = {}; tinsert = table.insert; tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end; table.wipe = wipe
SlashCmdList = {}
NOW = 1000; TIMERS = {}
GetTime = function() return NOW end

local T0 = 1794700000

time = function() return T0 + math.floor(NOW - 1000) end
date = os.date
C_Timer = { After = function(d, f) TIMERS[#TIMERS + 1] = { at = NOW + (d or 0), f = f } end,
    NewTicker = function(d, f) local dead = false; local function tick() if dead then return end; f(); TIMERS[#TIMERS + 1] = { at = NOW + d, f = tick } end; TIMERS[#TIMERS + 1] = { at = NOW + d, f = tick }; return { Cancel = function() dead = true end } end }
-- advance the clock: timers, then every frame's OnUpdate
function ADVANCE(dt)
    NOW = NOW + dt

    local guard = 0

    while true do
        local due

        for i = 1, #TIMERS do if TIMERS[i].at <= NOW then due = table.remove(TIMERS, i) break end end

        if not due then break end

        guard = guard + 1; if guard > 5000 then error("timer storm") end

        local ok, e = pcall(due.f); if not ok then print("TIMER ERR: " .. tostring(e)); ERRORS = (ERRORS or 0) + 1 end
    end

    for _, f in ipairs(FRAMES) do
        local h = f._scripts.OnUpdate

        if h and visible(f) then local ok, e = pcall(h, f, dt); if not ok then print("ONUPDATE ERR: " .. tostring(e)); ERRORS = (ERRORS or 0) + 1 end end
    end
end

function FIRE(ev, ...)
    for _, f in ipairs(FRAMES) do
        if f._events and f._events[ev] then
            local h = f._scripts.OnEvent

            if h then local ok, e = pcall(h, f, ev, ...); if not ok then print("EVENT ERR " .. ev .. ": " .. tostring(e)); ERRORS = (ERRORS or 0) + 1 end end
        end
    end
end

methods.RegisterEvent = function(self, ev) self._events = self._events or {}; self._events[ev] = true end
methods.RegisterUnitEvent = methods.RegisterEvent
methods.UnregisterEvent = function(self, ev) if self._events then self._events[ev] = nil end end
ME = "Kaelith"; MYLEVEL = 34; INCOMBAT = false
TOOLONG = 0
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function(p, t, c, tg) if #t > 255 then TOOLONG = TOOLONG + 1; return 2 end if SEND then return SEND(p, t, c, tg) end return 0 end }
C_Map = { GetBestMapForUnit = function() return 1424 end, GetPlayerMapPosition = function() return nil end, GetMapInfo = function() return { name = "Zone" } end }
QLOG, QDONE = {}, {}
C_QuestLog = { GetNumQuestLogEntries = function() return #QLOG end,
    GetInfo = function(i) local q = QLOG[i]; if q then return { title = q.title, questID = q.id, isHeader = false, isComplete = q.c } end end,
    GetAllCompletedQuestIDs = function() local t = {} for k in pairs(QDONE) do t[#t + 1] = k end return t end,
    IsQuestFlaggedCompleted = function(id) return QDONE[id] or false end,
    GetQuestObjectives = function() return {} end }
TOCMETA = {}
C_AddOns = { GetAddOnMetadata = function(_, k) return TOCMETA[k] end, IsAddOnLoaded = function() return false end }
UnitName = function(u) if u == "player" then return ME end end
GetRealmName = function() return "R" end; UnitLevel = function() return MYLEVEL end
SERVER_SKEW = 0
GetServerTime = function() return time() + SERVER_SKEW end
UnitGUID = function(u) if u == "player" then return MYGUID end end
GetUnitName = function(u, full) if u == "player" then return ME end end
UnitRace = function() return "Troll", "Troll" end; UnitClass = function() return "Hunter", "HUNTER" end
GetCursorPosition = function() return 100, 100 end
IsInGroup = function() return false end; IsInRaid = function() return false end
InCombatLockdown = function() return INCOMBAT end
GetFramerate = function() return 60 end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
HOOKS = {}
hooksecurefunc = function(a, b, c) HOOKS[#HOOKS + 1] = { a, b, c } end
securecallfunction = function(f, ...) return f(...) end

-- the game's xpcall passes extra arguments on to the function (plain Lua 5.1 doesn't)
local rawxpcall = xpcall

xpcall = function(f, h, ...) local n = select('#', ...); if n == 0 then return rawxpcall(f, h) end local args = { ... }; return rawxpcall(function() return f(unpack(args, 1, n)) end, h) end
geterrorhandler = function() return function(e) print('LUA ERR: ' .. tostring(e)); ERRORS = (ERRORS or 0) + 1; return e end end
issecurevariable = function() return true end
RAID_CLASS_COLORS = {}
C_FriendList = { GetNumFriends = function() return 0 end }
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, InvalidPrefix = 1, InvalidMessage = 2, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9 } }

local GONE = { GetQuestLogTitle = true, GetNumQuestLogEntries = true, GetQuestsCompleted = true, IsQuestFlaggedCompleted = true, GetAddOnMetadata = true, SendAddonMessage = true, RegisterAddonMessagePrefix = true, IsAddOnLoaded = true, GetSpellInfo = true }

setmetatable(_G, { __index = function(_, k) if GONE[k] then return nil end if type(k) == "string" and k:match("^[A-Z]") and not k:match("^C_") and not k:match("DB$") and not k:match("^Sterling") and not k:match("^Questie") and k ~= "TomTom" and k ~= "LibStub" and k ~= "ChatThrottleLib" and k ~= "LibDeflate" then return function() return nil end end end })

strsplit = function(sep, s) local out = {}; for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end; return unpack(out) end

GEOM = { rect = RECT, eff = eff, visible = visible, plain = plain }
