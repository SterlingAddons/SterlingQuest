-- Layout audit: measure every visible widget in a window and report overlaps, things outside the
-- window, and the padding on each side. AUDIT(win, label) returns a list of findings (strings).
local rect, plain = GEOM.rect, GEOM.plain

local function isAncestor(a, b) local o = b._parent; while o do if o == a then return true end o = o._parent end return false end
local function label(o)
    local t = o._text and plain(o._text):gsub("\n", " / ") or ""

    if t == "" and o._name then t = o._name end
    if #t > 34 then t = t:sub(1, 31) .. "..." end

    return (o._kind or "?") .. "[" .. t .. "]"
end

local function hasText(o) return o._text and plain(o._text):gsub("%s", "") ~= "" end

local EXEMPT_OUTSIDE = function(o)
    local q = o

    while q do
        if q._name and (q._name:find("FrameTab%d") or q._name:find("OptionsTab%d")) then return true end
        if q._outsideOK then return true end

        q = q._parent
    end

    return false
end

function WIDGETS(win)
    local items = {}

    local function walk(o, clip)
        for _, c in ipairs(o._children) do
            if c._shown then
                local r = rect(c)
                local kind = c._kind
                local widget = (kind == "Button" and (c._template or hasText(c))) or kind == "CheckButton" or kind == "EditBox" or kind == "Slider" or (kind == "FontString" and hasText(c))

                if widget and r then
                    local rr = { r[1], r[2], r[3], r[4] }

                    -- a one-line text in a wider slot only inks part of it: measure the ink, not the slot
                    if kind == "FontString" and c._wrap == false then
                        local ink = c:GetStringWidth() * GEOM.eff(c)

                        if ink < rr[3] - rr[1] then
                            if c._jh == "LEFT" then rr[3] = rr[1] + ink elseif c._jh == "RIGHT" then rr[1] = rr[3] - ink
                            else local mid = (rr[1] + rr[3]) / 2; rr[1], rr[3] = mid - ink / 2, mid + ink / 2 end
                            r = { rr[1], rr[2], rr[3], rr[4] }
                        end
                    end

                    if clip then rr = { math.max(rr[1], clip[1]), math.max(rr[2], clip[2]), math.min(rr[3], clip[3]), math.min(rr[4], clip[4]) } end
                    if rr[3] - rr[1] > 0.5 and rr[4] - rr[2] > 0.5 then items[#items + 1] = { o = c, r = rr, full = r, clipped = clip ~= nil, clip = clip } end
                end

                if rawget(c, "_children") and kind ~= "EditBox" then
                    local nc = clip

                    if kind == "ScrollFrame" and r then nc = r end

                    walk(c, nc)
                end
            end
        end
    end

    walk(win, nil)

    return items
end

function AUDIT(win, name, opts)
    opts = opts or {}

    local out = {}
    local wr = rect(win)

    if not wr then return { name .. ": window has no rect" } end

    local items = WIDGETS(win)

    -- 1. outside the window
    for _, it in ipairs(items) do
        local r = it.r

        if not EXEMPT_OUTSIDE(it.o) and (r[1] < wr[1] - 0.6 or r[3] > wr[3] + 0.6 or r[2] < wr[2] - 0.6 or r[4] > wr[4] + 0.6) then
            out[#out + 1] = ("%s: OUTSIDE %s by L%.0f R%.0f B%.0f T%.0f"):format(name, label(it.o), math.max(0, wr[1] - r[1]), math.max(0, r[3] - wr[3]), math.max(0, wr[2] - r[2]), math.max(0, r[4] - wr[4]))
        end
    end

    -- 1a. inside a scrolling area but wider than it: the game cuts it off at the side
    for _, it in ipairs(items) do
        if it.clip and it.o._kind ~= "EditBox" and (it.full[1] < it.clip[1] - 0.6 or it.full[3] > it.clip[3] + 0.6) then
            out[#out + 1] = ("%s: CUT OFF sideways %s (L%.0f R%.0f)"):format(name, label(it.o), math.max(0, it.clip[1] - it.full[1]), math.max(0, it.full[3] - it.clip[3]))
        end
    end

    -- 1c. a button whose label needs more room than the button has (button labels use the 12pt font)
    for _, it in ipairs(items) do
        local o = it.o

        if o._kind == "Button" and o._template == "UIPanelButtonTemplate" and o._text and o._text ~= "" then
            local need = #plain(o._text) * 6.2 * (FONT_SCALE or 1) + 12   -- calibrated on labels known to fit in game
            local have = (it.full[3] - it.full[1]) / GEOM.eff(o)

            if need > have + 0.5 then out[#out + 1] = ("%s: TIGHT button %s needs %.0f, has %.0f"):format(name, label(o), need, have) end
        end
    end

    -- 1b. anchors that disagree about where the middle is (two centre anchors, no top or bottom): the game picks one
    for _, it in ipairs(items) do
        if it.o._ambUsed then out[#out + 1] = ("%s: AMBIGUOUS vertical anchors on %s (%.0f apart)"):format(name, label(it.o), it.o._ambUsed) end
    end

    -- 2. overlaps
    for i = 1, #items do
        for j = i + 1, #items do
            local a, b = items[i], items[j]

            if not isAncestor(a.o, b.o) and not isAncestor(b.o, a.o) and not (a.o._overlapOK or b.o._overlapOK) then
                local ox = math.min(a.r[3], b.r[3]) - math.max(a.r[1], b.r[1])
                local oy = math.min(a.r[4], b.r[4]) - math.max(a.r[2], b.r[2])
                local bothChecks = a.o._kind == "CheckButton" and b.o._kind == "CheckButton"   -- their frames are bigger than the box art

                if ox > 1.5 and oy > 1.5 and not (bothChecks and math.min(ox, oy) <= 2.5) then
                    out[#out + 1] = ("%s: OVERLAP %s x %s (%.0fx%.0f)"):format(name, label(a.o), label(b.o), ox, oy)
                end
            end
        end
    end

    return out, items
end

-- padding of the content inside the window, and the bottom row
function PADS(win, name)
    local wr = rect(win)
    local items = WIDGETS(win)
    local L, R, B, T = 1e9, -1e9, 1e9, -1e9
    local keep = {}

    for _, it in ipairs(items) do
        if not EXEMPT_OUTSIDE(it.o) and it.r[4] < wr[4] - 29 then      -- below the title bar
            keep[#keep + 1] = it
            L = math.min(L, it.r[1]); R = math.max(R, it.r[3]); B = math.min(B, it.r[2]); T = math.max(T, it.r[4])
        end
    end

    local row = {}

    for _, it in ipairs(keep) do
        if it.o._kind ~= "FontString" and math.abs(it.r[2] - B) < 6 then row[#row + 1] = ("%s@%.0f-%.0f,b%.0f,h%.0f"):format(plain(it.o._text or ""):sub(1, 12), it.r[1] - wr[1], wr[3] - it.r[3], it.r[2] - wr[2], it.r[4] - it.r[2]) end
    end

    return ("%-22s size %.0fx%.0f  pad L%.0f R%.0f T%.0f B%.0f  | bottom row: %s"):format(name, wr[3] - wr[1], wr[4] - wr[2], L - wr[1], wr[3] - R, wr[4] - T, B - wr[2], table.concat(row, "  "))
end
