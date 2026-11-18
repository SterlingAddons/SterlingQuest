local S = ...

local function fire(ev, ...) for _, f in ipairs(FRAMES) do local h = f._scripts.OnEvent; if h then pcall(h, f, ev, ...) end end end

local tt = MK(); tt._shown = true; tt._lines = {}

rawset(tt, "GetName", function() return "GameTooltip" end)
rawset(tt, "NumLines", function(self) return #self._lines end)
rawset(tt, "IsShown", function(self) return self._shown end)
rawset(tt, "Show", function() end)

local function add(self, t) local fs = MK(); fs._text = t; self._lines[#self._lines + 1] = fs; _G["GameTooltipTextLeft" .. #self._lines] = fs end

rawset(tt, "AddLine", add)

GameTooltip = tt
HOOKS = {}
hooksecurefunc = function(a, b, c) if type(a) == "string" then HOOKS[a] = b else HOOKS["tt:" .. b] = c end end

local NPCDB = { [3341] = { questStarts = { 101, 102 }, questEnds = { 101 } } }

QuestieLoader = { ImportModule = function(_, n) return { QueryQuestSingle = function(id, k) if k == "name" then return ({ [101] = "Clam Bait", [102] = "Fishy Business", [200] = "It Takes Guts" })[id] end end, QueryNPCSingle = function(id, k) return NPCDB[id] and NPCDB[id][k] end } end }

fire("ADDON_LOADED", "Sterling"); fire("PLAYER_LOGIN")

S.Partners = function() return { { name = "Brannoc Ashvale" } } end
S.snaps = { ["Brannoc Ashvale"] = { log = { [101] = { title = "Clam Bait", objs = { "0/10" } }, [200] = { title = "It Takes Guts", objs = { "0 of 2" } } }, completed = { [102] = true } } }

local mode = "npc"

rawset(tt, "GetUnit", function() if mode == "map" then return nil, nil end return "Mai'Lahii", "mouseover" end)

UnitIsPlayer = function() return false end
UnitCanAttack = function() return mode == "mob" end
UnitGUID = function() return "Creature-0-1-2-3-3341-0000" end

-- 1. friendly quest giver
add(tt, "Mai'Lahii")
HOOKS["tt:Show"](tt)

for i, l in ipairs(tt._lines) do print("npc " .. i .. ": " .. l._text) end

HOOKS["tt:Show"](tt); print("npc lines after second show:", #tt._lines)

-- 2. mob with Questie lines: nothing by default
mode = "mob"; tt._lines = {}

add(tt, "Roving Tallstrider"); add(tt, "|cffff9b92[42] It Takes Guts|r"); add(tt, "   0/15 Beast Entrails")

local t0 = GetTime; GetTime = function() return t0() + 100 end

HOOKS["tt:Show"](tt)
print("mob default:", tt._lines[2]._text, "|", tt._lines[3]._text)

-- 3. mob with the option on: status goes under the progress line
SterlingQuestDB.opts.tipMobs = true

HOOKS["tt:Show"](tt)
print("mob on, title untouched:", not tt._lines[2]._text:find("\n"), " progress line:", (tt._lines[3]._text:gsub("\n", " // ")))
