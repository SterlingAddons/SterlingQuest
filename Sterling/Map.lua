-- Sterling: world map overlay. Draws the followed session's trail and event pins on the zone map,
-- with a scrubber bar for playback (drag, play, speed).
local _, S = ...

local overlay, bar, session
local lines, pins, lineN, pinN = {}, {}, 0, 0
local marker
local playT, playing, speed = nil, false, 4
local worldActive = false   -- true only when playback was opened on the stock map via "World map"
local pinColors = { T = { .11, .48, .24 }, A = { .17, .37, .66 }, O = { .69, .43, 0 }, Z = { .45, .35, .75 }, F = { .45, .35, .75 }, B = { .15, .55, .65 }, H = { .15, .55, .65 }, D = { .7, .25, .25 }, L = { .11, .48, .24 }, K = { .4, .4, .4 }, N = { .9, .75, .2 } }
local LINE_TEX = "Interface\\TaxiFrame\\UI-Taxi-Line"
local F = 128 / 126 / 2

-- Standard rotated-texture line. (sx,sy)->(ex,ey) in pixels from the overlay's bottom-left.
local function DrawLine(T, C, sx, sy, ex, ey, w)
    if sx > ex then sx, ex, sy, ey = ex, sx, ey, sy end

    local dx, dy = ex - sx, ey - sy
    local cx, cy = (sx + ex) / 2, (sy + ey) / 2

    if dx < 0 then dx, dy = -dx, -dy end

    local l = math.sqrt(dx * dx + dy * dy)

    if l < 0.5 then T:Hide() return end

    local s, c = -dy / l, dx / l
    local sc = s * c
    local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy

    if dy >= 0 then
        Bwid = ((l * c) - (w * s)) * F; Bhgt = ((w * c) - (l * s)) * F
        BLx, BLy, BRy = (w / l) * sc, s * s, (l / w) * sc
        BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx
        TRy = BRx
    else
        Bwid = ((l * c) + (w * s)) * F; Bhgt = ((w * c) + (l * s)) * F
        BLx, BLy, BRx = s * s, -(l / w) * sc, 1 + (w / l) * sc
        BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy
        TRx = TLy
    end

    T:ClearAllPoints()
    T:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy)
    T:SetPoint("BOTTOMLEFT", C, "BOTTOMLEFT", cx - Bwid, cy - Bhgt)
    T:SetPoint("TOPRIGHT", C, "BOTTOMLEFT", cx + Bwid, cy + Bhgt)
    T:Show()
end

S.DrawLine, S.PinColors, S.LINE_TEX = DrawLine, pinColors, LINE_TEX

-- The next free line on the world map overlay
local function getLine()
    lineN = lineN + 1

    local line = lines[lineN]

    if not line then line = overlay:CreateTexture(nil, "ARTWORK"); line:SetTexture(LINE_TEX); lines[lineN] = line end

    return line
end

-- The next free pin on the world map overlay
local function getPin()
    pinN = pinN + 1

    local pin = pins[pinN]

    if not pin then
        pin = CreateFrame("Frame", nil, overlay)

        pin:SetSize(18, 18); pin:SetFrameLevel(overlay:GetFrameLevel() + 5)

        -- Solid color textures only: this client doesn't ship the old minimap BLP files.
        pin.ring = pin:CreateTexture(nil, "BACKGROUND"); pin.ring:SetPoint("TOPLEFT", -2, 2); pin.ring:SetPoint("BOTTOMRIGHT", 2, -2); pin.ring:SetColorTexture(0, 0, 0, .85)
        pin.bg = pin:CreateTexture(nil, "BORDER"); pin.bg:SetAllPoints(); pin.bg:SetColorTexture(1, 1, 1, 1)
        pin.num = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); pin.num:SetPoint("CENTER", 0, 0); pin.num:SetTextColor(S.TR, S.TG, S.TB)

        pin.num:SetShadowColor(0, 0, 0, 1); pin.num:SetShadowOffset(1, -1)
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.title or "")

            if self.sub then GameTooltip:AddLine(self.sub, .8, .83, .9, true) end

            GameTooltip:Show()
        end)

        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

        pins[pinN] = pin
    end

    return pin
end

-- The text on a pin, with a better quest name if one is known now
local function pinLabel(event)
    if event.quest and event.quest:find("^Quest #") and event.q and S.QuestName then
        local n = S.QuestName(tonumber(event.q)); if n and not n:find("^Quest #") then event.quest = n end
    end

    if event.k == "T" then return "Turned in " .. (event.quest or ""), event.npc
    elseif event.k == "A" then return "Picked up " .. (event.quest or ""), event.npc
    elseif event.k == "O" then return (event.text and event.text:find("%S")) and event.text or "Objective", event.quest
    elseif event.k == "Z" then return "Arrived: " .. (event.text or "")
    elseif event.k == "F" then return "Flew to " .. (event.text or ""), event.from and ("from " .. event.from)
    elseif event.k == "B" then return "Boat or zeppelin to " .. (event.text or ""), event.from and ("from " .. event.from)
    elseif event.k == "H" then return ((event.from == "Hearthstone" or not event.from) and "Hearthed to " or "Teleported to ") .. (event.text or ""), (event.from ~= "Hearthstone") and event.from or nil
    elseif event.k == "D" then return "Ran " .. (event.text or "dungeon"), event.dur and (math.floor(event.dur / 60) .. " min")
    elseif event.k == "L" then return "Level " .. (event.lvl or "")
    elseif event.k == "K" then return "Died here", event.text == "res sickness" and "took res sickness at the spirit healer" or nil
    elseif event.k == "N" then return "Note: " .. (event.text or "") end
    return event.k
end

-- Position on the trail at time t (interpolated), for the current map.
S.PinLabel = pinLabel

-- Where the trail was at a time, on a map (for playback)
local function trailPosAt(t, map)
    local trail = session and session.trail or {}
    local prev

    for _, point in ipairs(trail) do
        if point.t > t then
            if prev and prev.map == map and point.map == map and not point.brk then
                local f = (t - prev.t) / math.max(1, point.t - prev.t)

                return prev.x + (point.x - prev.x) * f, prev.y + (point.y - prev.y) * f
            end

            return prev and prev.map == map and prev.x or nil, prev and prev.map == map and prev.y or nil
        end

        prev = point
    end

    if prev and prev.map == map then return prev.x, prev.y end
end

-- Map the session is on at time t (last trail point at or before t, else first point).
local function sessionMapAt(t)
    if not session then return nil end

    local m

    for _, point in ipairs(session.trail) do if point.t <= t then m = point.map else break end end

    return m or (session.trail[1] and session.trail[1].map)
end

-- Switches the world map to a map
local function showMap(map)
    if map and WorldMapFrame and WorldMapFrame.SetMapID and WorldMapFrame:GetMapID() ~= map then pcall(WorldMapFrame.SetMapID, WorldMapFrame, map) end
end

-- The map the world map is showing
local function currentMapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then return WorldMapFrame:GetMapID() end
end

local redrawQueued = false

-- Draws the session's trail and pins on the world map
local function realRedraw()
    if not overlay then return end

    lineN, pinN = 0, 0

    for _, line in ipairs(lines) do line:Hide() end
    for _, pin in ipairs(pins) do pin:Hide() end

    if marker then marker:Hide() end
    if not (session and WorldMapFrame and WorldMapFrame:IsShown()) then if bar then bar:Hide() end return end

    local map = currentMapID()
    local W, H = overlay:GetWidth(), overlay:GetHeight()

    if not map or W < 10 then return end

    local now = playT or session.stop or time()

    if not worldActive then
        -- Quiet mode: just a faint trail so the stock map isn't cluttered. Playback lives in Sterling's own window.
        if bar then bar:Hide() end

        local prev

        for _, point in ipairs(session.trail) do
            if point.map == map and prev and prev.map == map and not point.brk then
                local tex = getLine(); tex:SetVertexColor(.23, .48, 1, .45)

                DrawLine(tex, overlay, prev.x / 100 * W, H - prev.y / 100 * H, point.x / 100 * W, H - point.y / 100 * H, 3)
            end

            prev = point
        end

        return
    end

    -- Trail
    local prev

    for _, point in ipairs(session.trail) do
        if point.map == map and prev and prev.map == map and not point.brk then
            local tex = getLine()
            local past = point.t <= now

            tex:SetVertexColor(.23, .48, 1, past and .95 or .35)
            DrawLine(tex, overlay, prev.x / 100 * W, H - prev.y / 100 * H, point.x / 100 * W, H - point.y / 100 * H, past and 4 or 3)
        end

        prev = point
    end

    -- Pins (quest events and arrivals), numbered in order
    local n = 0

    for _, event in ipairs(session.events) do
        if event.map == map and event.x and (event.k == "T" or event.k == "A" or event.k == "O" or event.k == "F" or event.k == "B" or event.k == "H" or event.k == "D" or event.k == "K" or event.k == "N") then
            n = n + 1

            local pin = getPin()
            local c = pinColors[event.k] or { .5, .5, .5 }

            pin.bg:SetVertexColor(c[1], c[2], c[3], 1)
            pin.num:SetText(n)

            pin.title, pin.sub = pinLabel(event)
            pin.sub = (pin.sub and (pin.sub .. "  ") or "") .. S.Clock(event.t)

            pin:ClearAllPoints(); pin:SetPoint("CENTER", overlay, "TOPLEFT", event.x / 100 * W, -event.y / 100 * H)
            pin:SetAlpha(event.t <= now and 1 or .45)
            pin:Show()
        end
    end

    -- Marker
    local mx, my = trailPosAt(now, map)

    if mx then
        if not marker then
            marker = CreateFrame("Frame", nil, overlay); marker:SetSize(30, 30); marker:SetFrameLevel(overlay:GetFrameLevel() + 8)

            -- Solid color layers only (no texture files): pulsing gold halo, black border, gold core, white dot.
            marker.ring = marker:CreateTexture(nil, "BACKGROUND"); marker.ring:SetPoint("CENTER"); marker.ring:SetSize(44, 44); marker.ring:SetColorTexture(1, .85, .2, .35)
            marker.glow = marker:CreateTexture(nil, "BORDER"); marker.glow:SetPoint("CENTER"); marker.glow:SetSize(30, 30); marker.glow:SetColorTexture(0, 0, 0, .9)
            marker.t = marker:CreateTexture(nil, "ARTWORK"); marker.t:SetPoint("CENTER"); marker.t:SetSize(24, 24); marker.t:SetColorTexture(1, .8, .1, 1)
            marker.dot = marker:CreateTexture(nil, "OVERLAY"); marker.dot:SetPoint("CENTER"); marker.dot:SetSize(8, 8); marker.dot:SetColorTexture(1, 1, 1, 1)
            marker.lbl = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal"); marker.lbl:SetPoint("BOTTOM", marker, "TOP", 0, 10); marker.lbl:SetTextColor(1, .92, .55)
            marker.lblbg = marker:CreateTexture(nil, "BACKGROUND"); marker.lblbg:SetPoint("TOPLEFT", marker.lbl, -6, 3); marker.lblbg:SetPoint("BOTTOMRIGHT", marker.lbl, 6, -3); marker.lblbg:SetColorTexture(0, 0, 0, .7)

            local pulse = 0

            marker:SetScript("OnUpdate", function(self, dt)
                pulse = (pulse + dt * 2) % (2 * math.pi)

                local s = 1 + 0.18 * math.sin(pulse)

                self.ring:SetSize(44 * s, 44 * s); self.ring:SetAlpha(.5 + .5 * math.sin(pulse))
            end)
        end

        marker:ClearAllPoints(); marker:SetPoint("CENTER", overlay, "TOPLEFT", mx / 100 * W, -my / 100 * H)
        marker.lbl:SetText(session.char .. "  " .. S.Clock(now))
        marker:Show()
    end

    -- Scrubber
    if bar then
        bar:Show()

        local want = sessionMapAt(now)

        if want and want ~= map then bar.gotoBtn:SetText("Go to trail (" .. S.MapName(want) .. ")"); bar.gotoBtn:SetWidth(math.max(120, bar.gotoBtn:GetTextWidth() + 24)); bar.gotoBtn:Show() else bar.gotoBtn:Hide() end

        local dur = math.max(1, (session.stop or time()) - session.start)

        bar.slider:SetValue((now - session.start) / dur)
        bar.timeText:SetText(S.Clock(now))
        bar.endText:SetText(S.Clock(session.stop or time()))
        bar.title:SetText(session.char .. " - " .. session.name)
        bar.play:SetText(playing and "||" or ">")
        bar.spd:SetText(speed .. "x")
    end
end

-- Redraws the world map overlay on the next frame (several requests become one)
function S.MapRedraw()
    if redrawQueued then return end

    redrawQueued = true

    C_Timer.After(0.1, function() redrawQueued = false; if not S.InCombat() then S.Safe("map", realRedraw) end end)
end

-- The playback bar under the world map
local function buildBar()
    bar = CreateFrame("Frame", "SterlingQuestScrubber", WorldMapFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)

    bar:SetHeight(34)
    bar:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 8, 6)
    bar:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -8, 6)
    bar:SetFrameStrata("HIGH")

    if bar.SetBackdrop then
        S.SkinBox(bar); bar:SetBackdropColor(.08, .09, .13, .92); bar:SetBackdropBorderColor(.25, .28, .4, 1)
    end

    bar.play = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); bar.play:SetSize(28, 22); bar.play:SetPoint("LEFT", 8, 0); bar.play:SetText(">")

    bar.play:SetScript("OnClick", function() S.MapPlay(not playing) end)

    bar.spd = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); bar.spd:SetSize(36, 22); bar.spd:SetPoint("LEFT", bar.play, "RIGHT", 4, 0); bar.spd:SetText("4x")

    bar.spd:SetScript("OnClick", function() speed = ({ [1] = 4, [4] = 16, [16] = 60, [60] = 1 })[speed] or 4; S.MapRedraw() end)

    bar.timeText = bar:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); bar.timeText:SetPoint("LEFT", bar.spd, "RIGHT", 10, 0); bar.timeText:SetWidth(58); bar.timeText:SetJustifyH("LEFT")
    bar.endText = bar:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); bar.endText:SetPoint("RIGHT", -10, 0); bar.endText:SetTextColor(.6, .65, .75)
    bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); bar.title:SetPoint("BOTTOM", bar, "TOP", 0, 2); bar.title:SetTextColor(.85, .88, .95)
    bar.slider = CreateFrame("Slider", "SterlingQuestScrubSlider", bar, "OptionsSliderTemplate")

    bar.slider:SetPoint("LEFT", bar.timeText, "RIGHT", 6, 0); bar.slider:SetPoint("RIGHT", bar.endText, "LEFT", -10, 0); bar.slider:SetHeight(16)
    bar.slider:SetMinMaxValues(0, 1); bar.slider:SetValueStep(0.001); bar.slider:SetObeyStepOnDrag(true)

    if SterlingQuestScrubSliderLow then SterlingQuestScrubSliderLow:SetText(""); SterlingQuestScrubSliderHigh:SetText(""); SterlingQuestScrubSliderText:SetText("") end

    bar.slider:SetScript("OnValueChanged", function(self, v, user)
        if not session or not user then return end

        playing = false
        playT = session.start + v * math.max(1, (session.stop or time()) - session.start)

        showMap(sessionMapAt(playT))
        S.MapRedraw()
    end)

    bar.ticks = {}
    bar.gotoBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); bar.gotoBtn:SetSize(120, 22); bar.gotoBtn:SetPoint("BOTTOM", bar, "TOP", 0, 30); bar.gotoBtn:SetText("Go to trail"); bar.gotoBtn:Hide()

    bar.gotoBtn:SetScript("OnClick", function() showMap(sessionMapAt(playT or (session and session.start))); S.MapRedraw() end)
    bar:Hide()

    -- playback ticker
    local acc = 0

    bar:SetScript("OnUpdate", function(_, dt)
        if not playing or not session then return end

        acc = acc + dt

        if acc < 0.1 then return end

        playT = (playT or session.start) + acc * speed * 10
        acc = 0

        if playT >= (session.stop or time()) then playT = session.stop or time(); playing = false end

        showMap(sessionMapAt(playT))
        S.Safe("map", realRedraw)
    end)
end

-- Starts or stops playback
function S.MapPlay(on)
    if not session then return end

    playing = on

    if on and (not playT or playT >= (session.stop or time())) then playT = session.start end

    showMap(sessionMapAt(playT or session.start))
    S.MapRedraw()
end

-- Which session the map shows
function S.MapSetSession(sess)
    session = sess
    playT, playing = nil, false

    S.MapRedraw()
end

-- Opens or closes the map (Sterling's own map window when it's there)
function S.MapToggle()
    if S.ViewerToggle then return S.ViewerToggle() end

    return S.MapToggleWorld()
end

-- Shows the session on the game's world map
function S.MapToggleWorld()
    if not WorldMapFrame then return end

    worldActive = true

    if not session then
        local sess = S.FindSession(SterlingQuestDB.following) or SterlingQuestDB.sessions[1]

        if sess then S.MapSetSession(sess) end
    end

    if not session then S.msg("No session to show. Record one or import one first.") return end
    if type(WorldMapFrame) == "table" and not WorldMapFrame:IsShown() then ToggleWorldMap() end

    C_Timer.After(0.1, function() showMap(sessionMapAt(playT or session.start)); S.MapRedraw() end)
end

-- Hooks the world map so the overlay follows it
function S.MapInit()
    if not WorldMapFrame then return end

    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)

    if not canvas then return end

    overlay = CreateFrame("Frame", "SterlingQuestMapOverlay", canvas)

    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel((canvas:GetFrameLevel() or 0) + 20)
    buildBar()
    canvas:HookScript("OnSizeChanged", function() S.MapRedraw() end)
    WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0.05, S.MapRedraw) end)
    WorldMapFrame:HookScript("OnHide", function() playing = false; worldActive = false; if bar then bar:Hide() end end)

    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() S.MapRedraw() end) end
end

---------------------------------------------------------------------------
-- Minimap trail: the followed session's path drawn around the player, plus the next step.
---------------------------------------------------------------------------
local mmOverlay, mmLines, mmLineN, mmPin = nil, {}, 0, nil
local yardsCache = {}
local RADII_OUT = { 233.33, 200, 166.67, 133.33, 100, 66.67 }
local RADII_IN  = { 300, 240, 180, 120, 80, 50 }

-- Yards per 1% of the map, east and south. Cached per map.
local function yardsPerUnit(map)
    local c = yardsCache[map]

    if c then return c.x, c.y end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end

    local ok1, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
    local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))

    if not (ok1 and ok2 and a and b) then return nil end

    -- world x runs north, world y runs west; map x runs east, map y runs south
    local east = (a.y - b.y) / 100
    local south = (a.x - b.x) / 100

    if east <= 0 or south <= 0 then return nil end

    yardsCache[map] = { x = east, y = south }

    return east, south
end

-- How many yards the minimap shows from centre to edge, for the current zoom
local function minimapRadius()
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local indoors = GetCVar and GetCVar("minimapZoom") ~= GetCVar("minimapInsideZoom")
    local r = (IsIndoors and IsIndoors()) and RADII_IN or RADII_OUT

    return r[zoom + 1] or 233.33
end

-- The next free line on the minimap overlay
local function mmGetLine()
    mmLineN = mmLineN + 1

    local line = mmLines[mmLineN]

    if not line then line = mmOverlay:CreateTexture(nil, "ARTWORK"); line:SetTexture(LINE_TEX); line:SetVertexColor(.23, .48, 1, .9); mmLines[mmLineN] = line end

    return line
end

-- Draws the trail on the minimap
function S.MinimapRedraw()
    if not mmOverlay then return end

    mmLineN = 0

    for _, t in ipairs(mmLines) do t:Hide() end

    if mmPin then mmPin:Hide() end
    if SterlingQuestDB.hideMinimapTrail then return end

    local sess = S.FindSession(SterlingQuestDB.following)

    if not sess then return end

    local map, px, py = S.PlayerPos()

    if not map then return end

    local ux, uy = yardsPerUnit(map)

    if not ux then return end

    local radius = minimapRadius()
    local W, H = mmOverlay:GetWidth(), mmOverlay:GetHeight()
    local cx, cy = W / 2, H / 2
    local scale = (W / 2) / radius
    local rot = (GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing) and GetPlayerFacing() or 0
    local cosr, sinr = math.cos(rot), math.sin(rot)

    -- A world position as a spot on the minimap (rotating with it when it rotates)
    local function project(x, y)
        local dx, dy = (x - px) * ux, (y - py) * uy   -- yards east, yards south

        if rot ~= 0 then dx, dy = dx * cosr - dy * sinr, dx * sinr + dy * cosr end

        local d = math.sqrt(dx * dx + dy * dy)

        return cx + dx * scale, cy - dy * scale, d
    end

    local limit = radius * 0.92
    local prev, prevIn

    for _, point in ipairs(sess.trail) do
        if point.map == map then
            local sx, sy, d = project(point.x, point.y)
            local inside = d < limit

            if point.brk then prev = nil end
            if prev and prevIn and inside then DrawLine(mmGetLine(), mmOverlay, prev.sx, prev.sy, sx, sy, 3) end

            prev, prevIn = { sx = sx, sy = sy }, inside
        else prev = nil end
    end

    local step = S.steps[S.CurrentIndex()]

    if step and step.map == map and step.x then
        local sx, sy, d = project(step.x, step.y)

        if d < limit then
            if not mmPin then
                mmPin = CreateFrame("Frame", nil, mmOverlay); mmPin:SetSize(14, 14)
                mmPin.t = mmPin:CreateTexture(nil, "OVERLAY"); mmPin.t:SetAllPoints(); mmPin.t:SetTexture("Interface\\Minimap\\ObjectIconsAtlas")

                mmPin.t:SetTexture("Interface\\COMMON\\Indicator-Green")
            end

            mmPin:ClearAllPoints(); mmPin:SetPoint("CENTER", mmOverlay, "BOTTOMLEFT", sx, sy); mmPin:Show()
        end
    end
end

-- The minimap trail overlay
local function MinimapInit()
    if not Minimap then return end

    mmOverlay = CreateFrame("Frame", "SterlingQuestMinimapOverlay", Minimap)

    mmOverlay:SetAllPoints(Minimap)
    mmOverlay:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 2)

    local acc = 0

    mmOverlay:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt

        if acc < 0.25 then return end

        acc = 0

        if not S.InCombat() then S.Safe("minimap", S.MinimapRedraw) end
    end)
end

local oldMapInit = S.MapInit

-- Adds the minimap overlay to the map setup
function S.MapInit()
    if oldMapInit then oldMapInit() end

    MinimapInit()
end
