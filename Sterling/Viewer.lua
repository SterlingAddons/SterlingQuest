-- Sterling: its own map window. Zone artwork from the client's map tiles (plus the player's explored
-- patches), the session trail, numbered event pins, a playback marker, a scrubber, and a timeline
-- panel: zones -> rows (pick up / do / turn in / flew / ran / ding / skipped). Click a row to warp.
local _, S = ...
local msg = S.msg

local BG = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local CANVAS_W, PANEL_W = 700, 300
local ROW_H, HEAD_H = 32, 22

local win, canvas, art, view, bar, panel, scroll, content
local zoom, ox, dy = 1, 0, 0          -- map zoom and pan (content offset inside the viewport, dy <= 0)
local baseH = 466
local SPEEDS = { 1, 2, 3, 4, 5, 10, 20, 30, 40, 50, 60 }
local tiles, fogs, lines, dots, pins = {}, {}, {}, {}, {}
local lineN, dotN, pinN = 0, 0, 0
local marker
local session, viewMap, playT, playing, speed = nil, nil, nil, false, 4
local autoFollow = true
local autoCenter = true               -- keep the marker centred while zoomed in
local artCache, fogCache = {}, {}
local timeline, rowFrames, headFrames, collapsed = nil, {}, {}, {}
local pinIndex = {}
local compare = nil                   -- { diff=, mine=, theirs= } when a comparison is loaded
local panelMode = "timeline"          -- or "compare"
local foldCmp = {}

local ROW_COLOR = { pickup = { S.AR, S.AG, S.AB }, turnin = { .49, .89, .64 }, ["do"] = { .95, .77, .42 }, travel = { .76, .66, 1 },
                    flight = { .76, .66, 1 }, ride = { .4, .8, .9 }, hearth = { .4, .8, .9 }, dungeon = { 1, .61, .57 }, ding = { .49, .89, .64 }, skip = { 1, .61, .57 }, note = { .95, .85, .4 } }
local ROW_LABEL = { pickup = "PICK UP", turnin = "TURN IN", ["do"] = "DO", travel = "TRAVEL", flight = "FLEW", ride = "RODE", hearth = "HEARTH", dungeon = "RAN", ding = "DING", skip = "SKIPPED", note = "NOTE" }

-- Does this event get a pin on the map?
local function isPinEvent(e)
    return e.x and (e.k == "T" or e.k == "A" or e.k == "O" or e.k == "F" or e.k == "B" or e.k == "H" or e.k == "D" or e.k == "K" or e.k == "N")
end

-- "1h 05m" from seconds
local function fmtDur(sec)
    sec = math.max(0, math.floor(sec or 0))

    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)

    if h > 0 then return h .. "h " .. m .. "m" end
    if m > 0 then return m .. " min" end

    return "<1 min"
end

---------------------------------------------------------------------------
-- Zone artwork + explored patches
---------------------------------------------------------------------------
local function artInfo(map)
    if artCache[map] ~= nil then return artCache[map] or nil end

    local info

    if C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local ok, layers = pcall(C_Map.GetMapArtLayers, map)
        local L = ok and layers and layers[1]

        if L and L.layerWidth and L.layerWidth > 0 then
            local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, map, 1)

            if ok2 and tex and #tex > 0 then
                info = { w = L.layerWidth, h = L.layerHeight, tw = L.tileWidth, th = L.tileHeight, tex = tex }
            end
        end
    end

    artCache[map] = info or false

    return info
end

-- The explored-area textures for a map (cached)
local function exploredInfo(map)
    if fogCache[map] ~= nil then return fogCache[map] or nil end

    local list

    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        local ok, r = pcall(C_MapExplorationInfo.GetExploredMapTextures, map)

        if ok and r then list = r end
    end

    fogCache[map] = list or false

    return list
end

local revealHit, revealMiss

-- Draws a map's art: base tiles, then explored and revealed areas
local function drawArt(map)
    revealHit, revealMiss = 0, 0

    for _, tile in ipairs(tiles) do tile:Hide() end
    for _, fog in ipairs(fogs) do fog:Hide() end

    local info = artInfo(map)

    baseH = info and math.floor(CANVAS_W * info.h / info.w + .5) or math.floor(CANVAS_W * 2 / 3)

    view:SetSize(CANVAS_W, baseH)

    local W, H = CANVAS_W * zoom, baseH * zoom

    -- clamp the pan so the map always fills the viewport, then place the canvas
    ox = math.max(CANVAS_W - W, math.min(0, ox)); dy = math.max(baseH - H, math.min(0, dy))

    canvas:SetSize(W, H)
    canvas:ClearAllPoints(); canvas:SetPoint("TOPLEFT", view, "TOPLEFT", ox, -dy)
    art.fallback:SetShown(not info)

    if not info then
        art.fallbackText:SetText(S.MapName(map) .. "\n|cff8891a5(no map art available on this client)|r")

        return W, H
    end

    local cols = math.ceil(info.w / info.tw)
    local sx, sy = W / info.w, H / info.h
    local n = 0

    for i, fileID in ipairs(info.tex) do
        n = n + 1

        local texture = tiles[n]

        if not texture then texture = art:CreateTexture(nil, "BACKGROUND", nil, 0); tiles[n] = texture end

        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)

        texture:SetTexture(fileID); texture:SetTexCoord(0, 1, 0, 1)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", art, "TOPLEFT", col * info.tw * sx, -row * info.th * sy)
        texture:SetSize(info.tw * sx, info.th * sy)
        texture:Show()
    end

    -- Explored patches (same layout rules as Blizzard's MapExplorationDataProvider), plus every
    -- unexplored patch we know the texture for, so the whole zone is visible.
    local ex = exploredInfo(map)
    local patches, seen = {}, {}

    if ex then
        for _, e in ipairs(ex) do
            patches[#patches + 1] = e
            seen[e.textureWidth .. ":" .. e.textureHeight .. ":" .. e.offsetX .. ":" .. e.offsetY] = true
        end
    end

    if S.Reveal then
        local zone = S.Reveal[map]

        if zone then
            for key, files in pairs(zone) do
                if not seen[key] then
                    local w, h, x, y = key:match("^(%d+):(%d+):(%d+):(%d+)$")

                    if w then
                        local ids = {}

                        for id in files:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end

                        patches[#patches + 1] = { textureWidth = tonumber(w), textureHeight = tonumber(h), offsetX = tonumber(x), offsetY = tonumber(y), fileDataIDs = ids }
                    end
                end
            end
        end
    end

    do
        local TILE = 256
        local f = 0

        for _, patch in ipairs(patches) do
            local wide, tall = math.ceil(patch.textureWidth / TILE), math.ceil(patch.textureHeight / TILE)

            for j = 1, tall do
                local ph, fh

                if j < tall then ph, fh = TILE, TILE else ph = patch.textureHeight % TILE; if ph == 0 then ph = TILE end; fh = 16; while fh < ph do fh = fh * 2 end end

                for k = 1, wide do
                    local pw, fw

                    if k < wide then pw, fw = TILE, TILE else pw = patch.textureWidth % TILE; if pw == 0 then pw = TILE end; fw = 16; while fw < pw do fw = fw * 2 end end

                    local id = patch.fileDataIDs[(j - 1) * wide + k]

                    if id then
                        f = f + 1

                        local texture = fogs[f]

                        if not texture then texture = art:CreateTexture(nil, "BACKGROUND", nil, 1); fogs[f] = texture end

                        local okT = texture:SetTexture(id)

                        if okT == false then texture:Hide(); texture:SetTexture(nil); revealMiss = (revealMiss or 0) + 1 else revealHit = (revealHit or 0) + 1 end

                        texture:SetTexCoord(0, pw / fw, 0, ph / fh)
                        texture:ClearAllPoints()
                        texture:SetPoint("TOPLEFT", art, "TOPLEFT", (patch.offsetX + (k - 1) * TILE) * sx, -(patch.offsetY + (j - 1) * TILE) * sy)
                        texture:SetSize(pw * sx, ph * sy)
                        texture:Show()
                    end
                end
            end
        end
    end

    return W, H
end

---------------------------------------------------------------------------
-- Session helpers
---------------------------------------------------------------------------
local function sessionMaps()
    local seen, list = {}, {}

    if not session then return list end

    for _, point in ipairs(session.trail) do if point.map and not seen[point.map] then seen[point.map] = true; list[#list + 1] = point.map end end
    for _, event in ipairs(session.events) do if event.map and not seen[event.map] then seen[event.map] = true; list[#list + 1] = event.map end end

    return list
end

-- The map the session was on at a time
local function sessionMapAt(t)
    if not session then return nil end

    local m

    for _, point in ipairs(session.trail) do if point.t <= t then m = point.map else break end end

    return m or (session.trail[1] and session.trail[1].map)
end

-- Where the trail was at a time, on a map
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

-- Which pins are on which map
local function indexPins()
    pinIndex = {}

    local n = 0

    for _, event in ipairs(session.events) do if isPinEvent(event) then n = n + 1; pinIndex[event] = n end end
end

---------------------------------------------------------------------------
-- Timeline: zones -> rows
---------------------------------------------------------------------------
local function joinNames(list, max)
    if #list == 0 then return "" end

    local out = {}

    for i = 1, math.min(#list, max) do out[#out + 1] = list[i] end

    local s = table.concat(out, ", ")

    if #list > max then s = s .. " +" .. (#list - max) .. " more" end

    return s
end

-- The timeline: the session split into zones, each with what happened there
local function buildTimeline()
    local zones = {}

    if not session then timeline = zones return end

    local ev = session.events
    local inProg, inOrder = {}, {}     -- quests in the log right now (by qid), names in pick-up order

    -- The quests in progress, in the order they were picked up
    local function progList()
        local l = {}

        for _, q in ipairs(inOrder) do if inProg[q] then l[#l + 1] = inProg[q] end end

        return l
    end

    -- Quests finished or dropped later without a pick-up here were in the log before the recording began.
    do
        local picked = {}

        for _, event in ipairs(ev) do
            if event.k == "A" and event.q then picked[event.q] = true
            elseif (event.k == "T" or (event.k == "N" and event.text and event.text:match("^Abandoned "))) and event.q and not picked[event.q] and not inProg[event.q] then
                inProg[event.q] = event.quest or (event.text and event.text:match("^Abandoned (.+)$")) or ("Quest #" .. event.q); inOrder[#inOrder + 1] = event.q
            end
        end
    end

    local zone, pend

    -- Starts a new zone in the timeline
    local function newZone(map, t)
        zone = { map = map, name = S.MapName(map), t = t, rows = {} }
        zones[#zones + 1] = zone
    end

    -- Writes out the place being collected as a timeline row
    local function flush(untilT)
        if not pend then return end

        local dur = (untilT or pend.t) - pend.t

        if #pend.places == 0 and pend.deaths == 0 and dur < 180 then pend = nil return end

        local quests = progList()
        local row = { t = pend.t, t2 = untilT or pend.t, map = zone.map, x = pend.x, y = pend.y, places = pend.places, deaths = pend.deaths, sick = pend.sick, quests = quests }

        if #quests > 0 then row.kind = "do"; row.label = joinNames(quests, 3)
        else row.kind = "travel"; row.label = "" end
        zone.rows[#zone.rows + 1] = row
        pend = nil
    end

    -- Starts collecting a new place if none is open
    local function touch(e)
        if not pend then pend = { t = e.t, places = {}, seen = {}, deaths = 0, x = e.x, y = e.y } end
    end

    local curMap

    for _, event in ipairs(ev) do
        -- dungeon exits report the instance map; keep them inside the outer zone
        local m = (event.k == "D") and curMap or (event.map or curMap or (session.trail[1] and session.trail[1].map))

        if m ~= curMap then
            flush(event.t)

            curMap = m

            newZone(m, event.t)
        end

        if event.k == "Z" then
            touch(event)

            if event.text and event.text ~= "" and not pend.seen[event.text] and event.text ~= zone.name then pend.seen[event.text] = true; pend.places[#pend.places + 1] = event.text end
        elseif event.k == "K" then
            touch(event); pend.deaths = pend.deaths + 1

            if event.text == "res sickness" then pend.sick = true end
        elseif event.k == "O" then
            touch(event)
        else
            flush(event.t)

            local row = { t = event.t, map = event.map, x = event.x, y = event.y, pin = pinIndex[event] }

            if event.k == "A" then
                row.kind, row.label, row.sub = "pickup", event.quest or "Quest", event.npc and ("from " .. event.npc) or nil

                if event.q and not inProg[event.q] then inProg[event.q] = event.quest or ("Quest #" .. event.q); inOrder[#inOrder + 1] = event.q end
            elseif event.k == "T" then
                row.kind, row.label, row.sub = "turnin", event.quest or "Quest", event.npc and ("to " .. event.npc) or nil

                if event.q then inProg[event.q] = nil end
            elseif event.k == "F" then
                row.kind, row.label, row.sub = "flight", "to " .. (event.text or "?"), event.from and ("from " .. event.from) or nil
            elseif event.k == "B" then
                row.kind, row.label, row.sub = "ride", "to " .. (event.text or "?"), "boat or zeppelin" .. (event.from and (" from " .. event.from) or "")
            elseif event.k == "H" then
                row.kind, row.label, row.sub = "hearth", "to " .. (event.text or "?"), (event.from and event.from ~= "Hearthstone") and event.from or "hearthstone"
            elseif event.k == "D" then
                row.kind, row.label, row.sub = "dungeon", event.text or "a dungeon", event.dur and fmtDur(event.dur) or nil
            elseif event.k == "L" then
                row.kind, row.label = "ding", "Level " .. (event.lvl or "?")
            elseif event.k == "N" then
                local skipped = event.text and event.text:match("^Skipped (.+)$")
                local aband = event.text and event.text:match("^Abandoned (.+)$")

                if skipped or aband then row.kind, row.label = "skip", skipped or aband; if event.q then inProg[event.q] = nil end
                else row.kind, row.label = "note", event.text or "" end
            else
                row = nil
            end

            if row then zone.rows[#zone.rows + 1] = row end
        end
    end

    flush(session.stop or time())

    local stop = session.stop or time()

    local function spans() for i, zone in ipairs(zones) do zone.t2 = zones[i + 1] and zones[i + 1].t or stop end end
    local function hasAnchor(zone) for _, row in ipairs(zone.rows) do if row.kind ~= "do" and row.kind ~= "travel" then return true end end return false end

    -- 1. fold zone blips (quick hop over a border and back) into the zone around them
    spans()

    local changed = true

    while changed do
        changed = false

        for i = 2, #zones do
            local zone, prev, nxt = zones[i], zones[i - 1], zones[i + 1]
            local dur = zone.t2 - zone.t

            if (dur < 120 and nxt and nxt.map == prev.map) or (dur < 45 and not hasAnchor(zone)) then
                for _, row in ipairs(zone.rows) do prev.rows[#prev.rows + 1] = row end

                table.remove(zones, i)

                if nxt and nxt.map == prev.map then
                    for _, row in ipairs(nxt.rows) do prev.rows[#prev.rows + 1] = row end

                    table.remove(zones, i)
                end

                spans(); changed = true

                break
            end
        end
    end

    -- 2. merge neighbouring do/travel rows that say the same thing, then drop the trivial ones
    for _, zone in ipairs(zones) do
        local out = {}

        for _, row in ipairs(zone.rows) do
            local last = out[#out]

            if last and (row.kind == "do" or row.kind == "travel") and last.kind == row.kind and last.label == row.label then
                last.t2 = math.max(last.t2, row.t2); last.deaths = last.deaths + row.deaths; last.sick = last.sick or row.sick

                for _, pl in ipairs(row.places) do
                    local dup = false

                    for _, place in ipairs(last.places) do if place == pl then dup = true break end end

                    if not dup then last.places[#last.places + 1] = pl end
                end
            else
                out[#out + 1] = row
            end
        end

        zone.rows = {}

        for _, r in ipairs(out) do
            if (r.kind == "do" or r.kind == "travel") and r.deaths == 0 and (r.t2 - r.t) < 90 then
                -- too short to matter
            else
                if r.kind == "do" or r.kind == "travel" then
                    local bits = {}

                    if r.kind == "travel" then r.label = #r.places > 0 and ("Through " .. joinNames(r.places, 3)) or "Moving around"
                    elseif #r.places > 0 then
                        local pl = {}

                        for i = 1, math.min(#r.places, 4) do pl[#pl + 1] = r.places[i] end

                        bits[#bits + 1] = table.concat(pl, " > ") .. (#r.places > 4 and " ..." or "")
                    end

                    bits[#bits + 1] = fmtDur(r.t2 - r.t)

                    if r.deaths > 0 then bits[#bits + 1] = "died" .. (r.deaths > 1 and (" x" .. r.deaths) or "") .. (r.sick and ", res sickness" or "") end

                    r.sub = table.concat(bits, "  -  ")
                end

                zone.rows[#zone.rows + 1] = r
            end
        end
    end

    timeline = zones
end

---------------------------------------------------------------------------
-- Timeline panel rendering
---------------------------------------------------------------------------
local function rowFrame(i)
    local row = rowFrames[i]

    if row then return row end

    row = CreateFrame("Button", nil, content)

    row:SetHeight(ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetColorTexture(1, 1, 1, .04)
    row.hl = row:CreateTexture(nil, "BORDER"); row.hl:SetAllPoints(); row.hl:SetColorTexture(S.AR, S.AG, S.AB, .18); row.hl:Hide()
    row.cur = row:CreateTexture(nil, "ARTWORK"); row.cur:SetPoint("TOPLEFT"); row.cur:SetPoint("BOTTOMLEFT"); row.cur:SetWidth(3); row.cur:SetColorTexture(1, .8, .1, 1); row.cur:Hide()
    row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.badge:SetPoint("LEFT", 6, 0); row.badge:SetWidth(20); row.badge:SetJustifyH("RIGHT"); row.badge:SetTextColor(.6, .65, .75)
    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.kind:SetPoint("TOPLEFT", 30, -4); row.kind:SetWidth(52); row.kind:SetJustifyH("LEFT")
    row.label = row:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); row.label:SetPoint("TOPLEFT", 84, -4); row.label:SetPoint("RIGHT", -50, 0); row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); row.sub:SetPoint("BOTTOMLEFT", 84, 4); row.sub:SetPoint("RIGHT", -6, 0); row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false); row.sub:SetTextColor(.6, .65, .75)
    row.time = row:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); row.time:SetPoint("TOPRIGHT", -6, -4); row.time:SetTextColor(.5, .55, .65)

    row:SetScript("OnEnter", function(self)
        self.hl:Show()

        if self.row and self.row.quests and #self.row.quests > 3 then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Quests in the log")

            for _, quest in ipairs(self.row.quests) do GameTooltip:AddLine(quest, .85, .88, .95) end

            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if not self.row then return end

        playing = false; playT = self.row.t; autoFollow = true

        S.ViewerRedraw()
    end)

    rowFrames[i] = row

    return row
end

-- A zone heading in the side panel, made when first needed
local function headFrame(i)
    local h = headFrames[i]

    if h then return h end

    h = CreateFrame("Button", nil, content)

    h:SetHeight(HEAD_H)

    h.bg = h:CreateTexture(nil, "BACKGROUND"); h.bg:SetAllPoints(); h.bg:SetColorTexture(.16, .2, .33, 1)
    h.chev = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h.chev:SetPoint("LEFT", 8, 0); h.chev:SetTextColor(.7, .75, .85)
    h.name = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.name:SetPoint("LEFT", 22, 0); h.name:SetPoint("RIGHT", -90, 0); h.name:SetJustifyH("LEFT"); h.name:SetWordWrap(false)
    h.time = h:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); h.time:SetPoint("RIGHT", -6, 0); h.time:SetTextColor(.7, .75, .85)

    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(self, btn)
        if self.cmp then foldCmp[self.cmp] = not foldCmp[self.cmp]; S.ViewerRedraw() return end
        if not self.zone then return end
        if btn == "RightButton" then collapsed[self.idx] = not collapsed[self.idx]; S.ViewerRedraw() return end

        playing = false; playT = self.zone.t; autoFollow = true

        S.ViewerRedraw()
    end)

    h:SetScript("OnEnter", function(self)
        if self.cmp then return end

        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.zone and self.zone.name or ""); GameTooltip:AddLine("Click: jump here.  Right-click: fold / unfold.", .5, .55, .65); GameTooltip:Show()
    end)

    h:SetScript("OnLeave", function() GameTooltip:Hide() end)

    headFrames[i] = h

    return h
end

-- Draws the side panel in Compare mode
local function drawCompare(now)
    local d = compare.diff
    local y, ri, hi = 0, 0, 0
    local sections =
    {
        { key = "extra", title = "EXTRA  -  they did, you didn't", list = d.extra, color = { S.AR, S.AG, S.AB } },
        { key = "missed", title = "MISSED  -  you did, they didn't", list = d.missed, color = { 1, .61, .57 } },
        { key = "same", title = "SAME  -  both did", list = d.same, color = { .49, .89, .64 } },
    }

    for si, sec in ipairs(sections) do
        hi = hi + 1

        local h = headFrame(hi)

        h.zone, h.idx, h.cmp = nil, si, sec.key

        h.chev:SetText(foldCmp[sec.key] and "+" or "-")
        h.name:SetText(sec.title .. "  (" .. #sec.list .. ")"); h.name:SetTextColor(sec.color[1], sec.color[2], sec.color[3])
        h.time:SetText("")
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); h:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        h:Show()

        y = y + HEAD_H + 1

        if not foldCmp[sec.key] then
            if #sec.list == 0 then
                ri = ri + 1

                local row = rowFrame(ri); row.row = nil

                row.kind:SetText(""); row.badge:SetText(""); row.time:SetText(""); row.sub:SetText("")
                row.label:SetText("nothing here"); row.label:SetTextColor(.5, .55, .65)
                row.cur:Hide(); row.bg:SetColorTexture(1, 1, 1, .02)
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); row:SetPoint("RIGHT", content, "RIGHT", 0, 0); row:Show()

                y = y + ROW_H + 1
            end

            for _, row in ipairs(sec.list) do
                ri = ri + 1

                local r = rowFrame(ri)

                r.row = (not row.mineOnly) and row or nil

                local color = ROW_COLOR[row.kind] or { .8, .8, .8 }

                r.kind:SetText(ROW_LABEL[row.kind] or row.kind:upper()); r.kind:SetTextColor(color[1], color[2], color[3])
                r.label:SetText(row.label or ""); r.label:SetTextColor(S.TR, S.TG, S.TB)

                local sub = row.sub

                if sec.key == "same" then sub = "them " .. S.Clock(row.t) .. "   you " .. S.Clock(row.t2) .. (row.sub and ("   " .. row.sub) or "") end
                if row.npc and sec.key ~= "same" then sub = (sub and (sub .. "   ") or "") .. "at " .. row.npc end

                r.sub:SetText(sub or "")
                r.badge:SetText("")
                r.time:SetText(row.mineOnly and "" or S.Clock(row.t))
                r.cur:SetShown(r.row ~= nil and playT ~= nil and math.abs((playT or 0) - row.t) < 30)
                r.bg:SetColorTexture(1, 1, 1, .035)
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                r:Show()

                y = y + ROW_H + 1
            end
        end
    end

    content:SetHeight(math.max(y, 10))
end

-- Draws the side panel's timeline
local function drawTimeline(now)
    for _, r in ipairs(rowFrames) do r:Hide() end
    for _, h in ipairs(headFrames) do h:Hide() end

    if compare then
        panel.tabs:Show()
        panel.tabs.tl:SetEnabled(panelMode ~= "timeline"); panel.tabs.cmp:SetEnabled(panelMode ~= "compare")
        panel.stats:SetText(compare.diff.stats)
        scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 4, -46); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    else
        panel.tabs:Hide()
        scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    end

    if compare and panelMode == "compare" then drawCompare(now) return end
    if not timeline then return end

    local y, ri, hi = 0, 0, 0
    local curY
    local curRow, curZone

    for zi, zone in ipairs(timeline) do
        if zone.t <= now then curZone = zi end

        for _, row in ipairs(zone.rows) do if row.t <= now then curRow = row end end
    end

    for zi, zone in ipairs(timeline) do
        hi = hi + 1

        local h = headFrame(hi)

        h.zone, h.idx = zone, zi

        h.chev:SetText(collapsed[zi] and "+" or "-")
        h.name:SetText(zone.name)

        if zi == curZone then h.name:SetTextColor(1, .85, .3) else h.name:SetTextColor(.9, .92, 1) end

        h.time:SetText(S.Clock(zone.t) .. "  " .. fmtDur(zone.t2 - zone.t))
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); h:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        h:Show()

        y = y + HEAD_H + 1

        if not collapsed[zi] then
            for _, row in ipairs(zone.rows) do
                ri = ri + 1

                local r = rowFrame(ri)

                r.row = row

                local color = ROW_COLOR[row.kind] or { .8, .8, .8 }

                r.kind:SetText(ROW_LABEL[row.kind] or row.kind:upper()); r.kind:SetTextColor(color[1], color[2], color[3])
                r.label:SetText(row.label or "")
                r.sub:SetText(row.sub or "")
                r.badge:SetText(row.pin and tostring(row.pin) or "")
                r.time:SetText(S.Clock(row.t))

                local past = row.t <= now

                if past then r.label:SetTextColor(S.TR, S.TG, S.TB) else r.label:SetTextColor(.7, .72, .78) end

                r.cur:SetShown(row == curRow)
                r.bg:SetColorTexture(1, 1, 1, row == curRow and .09 or .035)
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                r:Show()

                if row == curRow then curY = y end

                y = y + ROW_H + 1
            end
        end
    end

    content:SetHeight(math.max(y, 10))

    if playing and curY and scroll then
        local top = scroll:GetVerticalScroll()
        local vh = scroll:GetHeight()

        if curY < top or curY + ROW_H > top + vh then
            scroll:SetVerticalScroll(math.max(0, math.min(curY - vh / 2, content:GetHeight() - vh)))
        end
    end
end

---------------------------------------------------------------------------
-- Map drawing
---------------------------------------------------------------------------
local function getLine()
    lineN = lineN + 1

    local l = lines[lineN]

    if not l then l = canvas:CreateLine(nil, "ARTWORK"); lines[lineN] = l end

    return l
end

-- The next free trail dot
local function getDot()
    dotN = dotN + 1

    local d = dots[dotN]

    if not d then d = canvas:CreateTexture(nil, "ARTWORK"); d:SetColorTexture(1, 1, 1, 1); dots[dotN] = d end

    return d
end

-- Segment in canvas pixels (top-left origin). Native line object when the client has it, dots otherwise.
local function segment(x1, y1, x2, y2, r, g, b, a, w)
    if canvas.CreateLine then
        local l = getLine()

        l:SetColorTexture(r, g, b, a); l:SetThickness(w)
        l:SetStartPoint("TOPLEFT", canvas, x1, -y1); l:SetEndPoint("TOPLEFT", canvas, x2, -y2)
        l:Show()
    else
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local n = math.max(1, math.floor(len / 3))

        for i = 0, n do
            local d = getDot()

            d:SetSize(w, w); d:SetVertexColor(r, g, b, a)
            d:ClearAllPoints(); d:SetPoint("CENTER", canvas, "TOPLEFT", x1 + dx * i / n, -(y1 + dy * i / n))
            d:Show()
        end
    end
end

-- The next free pin
local function getPin()
    pinN = pinN + 1

    local pin = pins[pinN]

    if not pin then
        pin = CreateFrame("Frame", nil, canvas)

        pin:SetSize(14, 14); pin:SetFrameLevel(canvas:GetFrameLevel() + 5)

        pin.ring = pin:CreateTexture(nil, "BACKGROUND"); pin.ring:SetPoint("TOPLEFT", -1, 1); pin.ring:SetPoint("BOTTOMRIGHT", 1, -1); pin.ring:SetColorTexture(0, 0, 0, .7)
        pin.bg = pin:CreateTexture(nil, "BORDER"); pin.bg:SetAllPoints(); pin.bg:SetColorTexture(1, 1, 1, 1)
        pin.num = pin:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pin.num:SetPoint("CENTER", 0, 0); pin.num:SetTextColor(S.TR, S.TG, S.TB)

        pin.num:SetShadowColor(0, 0, 0, 1); pin.num:SetShadowOffset(1, -1)
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.title or "")

            if self.sub then GameTooltip:AddLine(self.sub, .8, .83, .9, true) end

            GameTooltip:AddLine("Click: jump playback here.  Right-click: set arrow.", .5, .55, .65)
            GameTooltip:Show()
        end)

        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnMouseUp", function(self, btn)
            if not self.ev then return end
            if btn == "RightButton" then
                if S.SetWaypoint and self.ev.map and self.ev.x then
                    S.SetWaypoint({ kind = "note", map = self.ev.map, x = self.ev.x, y = self.ev.y, text = self.title or "Sterling Quest Sync pin" })
                    msg("Arrow set to pin " .. (self.n or "") .. ".")
                end
            else
                playing = false; playT = self.ev.t; S.ViewerRedraw()
            end
        end)

        pins[pinN] = pin
    end

    return pin
end

-- Draws the map window: art, trail, pins, side panel
local function redraw()
    if not win or not win:IsShown() then return end

    lineN, dotN, pinN = 0, 0, 0

    for _, line in ipairs(lines) do line:Hide() end
    for _, dot in ipairs(dots) do dot:Hide() end
    for _, pin in ipairs(pins) do pin:Hide() end

    if marker then marker:Hide() end
    if not session then
        win.sub:SetText("No session. Record one or import one first.")
        drawArt(viewMap or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 1414)
        bar:Hide()

        return
    end

    local now = playT or session.stop or time()

    if autoFollow then viewMap = sessionMapAt(now) or viewMap end

    viewMap = viewMap or sessionMapAt(now) or (session.trail[1] and session.trail[1].map) or 1414

    local map = viewMap
    local W, H = drawArt(map)

    win:SetHeight(math.max(baseH + 44 + 40 + 12, 420))
    panel:SetHeight(baseH)
    bar:Show()

    -- header
    local maps = sessionMaps()
    local idx = 0

    for i, m in ipairs(maps) do if m == map then idx = i end end

    win.title:SetText(session.char .. " - " .. session.name)
    win.sub:SetText(S.MapName(map) .. (#maps > 1 and ("   " .. idx .. "/" .. #maps .. " zones") or "") .. (session.note and ("   |cfff3c56b" .. session.note .. "|r") or ""))
    win.prev:SetEnabled(#maps > 1); win.next:SetEnabled(#maps > 1)
    win.follow:SetText(autoFollow and "Auto zone: on" or "Auto zone: off")
    win.center:SetText(autoCenter and "Auto center: on" or "Auto center: off")

    if zoom > 1 then win.sub:SetText(win.sub:GetText() .. "   " .. string.format("%.1fx zoom", zoom) .. "  (wheel to zoom, drag to pan, double-click to reset)") end

    -- trail
    local prev

    for _, point in ipairs(session.trail) do
        if point.map == map and prev and prev.map == map and not point.brk then
            local past = point.t <= now

            segment(prev.x / 100 * W, prev.y / 100 * H, point.x / 100 * W, point.y / 100 * H, .23, .48, 1, past and .95 or .4, past and 3 or 2)
        end

        prev = point
    end

    -- pins
    for _, event in ipairs(session.events) do
        if isPinEvent(event) and event.map == map then
            local n = pinIndex[event]
            local pin = getPin()
            local color = S.PinColors[event.k] or { .5, .5, .5 }

            pin.bg:SetVertexColor(color[1], color[2], color[3], 1)

            pin.num:SetText(n); pin.n = n; pin.ev = event
            pin.title, pin.sub = S.PinLabel(event)
            pin.sub = (pin.sub and (pin.sub .. "  ") or "") .. S.Clock(event.t)

            pin:ClearAllPoints(); pin:SetPoint("CENTER", canvas, "TOPLEFT", event.x / 100 * W, -event.y / 100 * H)
            pin:SetAlpha(event.t <= now and .8 or .35)
            pin:Show()
        end
    end

    -- marker
    local mx, my = trailPosAt(now, map)

    if mx and autoCenter and zoom > 1 then
        ox = CANVAS_W / 2 - mx / 100 * W; dy = baseH / 2 - my / 100 * H
        ox = math.max(CANVAS_W - W, math.min(0, ox)); dy = math.max(baseH - H, math.min(0, dy))

        canvas:ClearAllPoints(); canvas:SetPoint("TOPLEFT", view, "TOPLEFT", ox, -dy)
    end

    if mx then
        if not marker then
            -- the player's face: race icon tinted in their colour, thin colour border, soft glow, name + clock above
            marker = CreateFrame("Frame", nil, canvas); marker:SetSize(30, 30); marker:SetFrameLevel(canvas:GetFrameLevel() + 9)
            marker.glow = marker:CreateTexture(nil, "BACKGROUND"); marker.glow:SetPoint("CENTER"); marker.glow:SetSize(42, 42); marker.glow:SetColorTexture(1, .85, .2, .22)
            marker.edge = marker:CreateTexture(nil, "BORDER"); marker.edge:SetPoint("TOPLEFT", -2, 2); marker.edge:SetPoint("BOTTOMRIGHT", 2, -2); marker.edge:SetColorTexture(1, .8, .1, 1)
            marker.back = marker:CreateTexture(nil, "BORDER", nil, 1); marker.back:SetAllPoints(); marker.back:SetColorTexture(.05, .05, .08, 1)
            marker.face = marker:CreateTexture(nil, "ARTWORK"); marker.face:SetPoint("TOPLEFT", 1, -1); marker.face:SetPoint("BOTTOMRIGHT", -1, 1)
            marker.lbl = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal"); marker.lbl:SetPoint("BOTTOM", marker, "TOP", 0, 8); marker.lbl:SetTextColor(1, .92, .55)
            marker.lblbg = marker:CreateTexture(nil, "BACKGROUND"); marker.lblbg:SetPoint("TOPLEFT", marker.lbl, -6, 3); marker.lblbg:SetPoint("BOTTOMRIGHT", marker.lbl, 6, -3); marker.lblbg:SetColorTexture(0, 0, 0, .7)

            local pulse = 0

            marker:SetScript("OnUpdate", function(self, dt)
                pulse = (pulse + dt * 2.5) % (2 * math.pi)

                local s = 1 + 0.15 * math.sin(pulse)

                self.glow:SetSize(42 * s, 42 * s); self.glow:SetAlpha(.5 + .5 * math.sin(pulse))
            end)
        end

        local look = S.LookFor(session.char, session)

        if marker.lookKey ~= (look.race .. look.color .. (look.female and "f" or "m")) then
            marker.lookKey = look.race .. look.color .. (look.female and "f" or "m")

            S.SetFace(marker.face, look.race, look.female)

            local r, g, b = S.ColorRGB(look.color)

            marker.face:SetVertexColor(r, g, b)
            marker.edge:SetColorTexture(r, g, b, 1)
            marker.glow:SetColorTexture(r, g, b, .25)
            marker.lbl:SetTextColor(math.min(1, r + .25), math.min(1, g + .25), math.min(1, b + .25))
        end

        marker:ClearAllPoints(); marker:SetPoint("CENTER", canvas, "TOPLEFT", mx / 100 * W, -my / 100 * H)
        marker.lbl:SetText((look.name or session.char) .. "  " .. S.Clock(now))
        marker.lbl:ClearAllPoints()

        if my < 12 then marker.lbl:SetPoint("TOP", marker, "BOTTOM", 0, -8) else marker.lbl:SetPoint("BOTTOM", marker, "TOP", 0, 10) end

        marker:Show()
    elseif not autoFollow then
        local want = sessionMapAt(now)

        if want and want ~= map then win.sub:SetText(S.MapName(map) .. "   |cfff3c56bplayback is in " .. S.MapName(want) .. "|r") end
    end

    -- scrubber
    local dur = math.max(1, (session.stop or time()) - session.start)

    bar.slider:SetValue((now - session.start) / dur)
    bar.timeText:SetText(S.Clock(now))
    bar.endText:SetText(S.Clock(session.stop or time()))
    bar.play:SetText(playing and "||" or ">")
    bar.spd:SetText(speed .. "x")

    drawTimeline(now)
end

local queued = false

-- Redraws the map window on the next frame
function S.ViewerRedraw()
    if queued then return end

    queued = true

    C_Timer.After(0.05, function() queued = false; if not S.InCombat() then S.Safe("viewer", redraw) end end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function build()
    win = CreateFrame("Frame", "SterlingQuestMapViewer", UIParent, BD)

    S.SkinWindow(win)
    win:SetSize(CANVAS_W + PANEL_W + 18, 600); win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    win:SetFrameStrata("HIGH"); win:SetToplevel(true)
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local p, _, rp, x, y = self:GetPoint(); SterlingQuestDB.pos = SterlingQuestDB.pos or {}; SterlingQuestDB.pos.viewer = { p, rp, x, y }
    end)

    local pos = SterlingQuestDB.pos and SterlingQuestDB.pos.viewer

    if pos then win:ClearAllPoints(); win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end

    tinsert(UISpecialFrames, "SterlingQuestMapViewer")

    -- header
    local head = win:CreateTexture(nil, "ARTWORK"); head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(42); head:SetColorTexture(.16, .2, .33, 1)

    if S.WowSkin() then head:SetColorTexture(0, 0, 0, 0); if win.titleTile then win.titleTile:SetHeight(42) end end

    local logo = win:CreateTexture(nil, "OVERLAY"); logo:SetSize(18, 18); logo:SetPoint("TOPLEFT", 10, -6); logo:SetTexture("Interface\\AddOns\\Sterling\\Media\\icon")

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal"); win.title:SetPoint("LEFT", logo, "RIGHT", 7, 0); win.title:SetTextColor(.96, .97, 1); win.title:SetText("Sterling Quest Sync Map")
    win.sub = win:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); win.sub:SetPoint("TOPLEFT", 10, -26); win.sub:SetTextColor(.75, .8, .9)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetScale(.8); close:SetPoint("CENTER", head, "TOPRIGHT", -17, -19)   -- centred on the title row

    win.next = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.next:SetSize(26, 20); win.next:SetPoint("TOPRIGHT", -30, -11); win.next:SetText(">")
    win.prev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.prev:SetSize(26, 20); win.prev:SetPoint("RIGHT", win.next, "LEFT", -2, 0); win.prev:SetText("<")

    -- Moves to the previous or next map the session visited
    local function step(d)
        local maps = sessionMaps(); if #maps < 2 then return end
        local idx = 1; for i, map in ipairs(maps) do if map == viewMap then idx = i end end

        idx = ((idx - 1 + d) % #maps) + 1
        viewMap = maps[idx]; autoFollow = false; S.ViewerRedraw()
    end

    win.prev:SetScript("OnClick", function() step(-1) end)
    win.next:SetScript("OnClick", function() step(1) end)

    win.follow = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.follow:SetSize(104, 20); win.follow:SetPoint("RIGHT", win.prev, "LEFT", -6, 0); win.follow:SetText("Auto zone: on")

    win.follow:SetScript("OnClick", function() autoFollow = not autoFollow; S.ViewerRedraw() end)

    win.center = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.center:SetSize(112, 20); win.center:SetPoint("RIGHT", win.follow, "LEFT", -6, 0); win.center:SetText("Auto center: on")

    win.center:SetScript("OnClick", function()
        autoCenter = not autoCenter

        if autoCenter and zoom == 1 then zoom = 2.5 end   -- turning it on from full view zooms in so it has something to do

        S.ViewerRedraw()
    end)

    win.center:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Auto center"); GameTooltip:AddLine("Keeps the playback marker in the middle while zoomed in. Zooming or dragging the map turns it off.", .6, .65, .75, true); GameTooltip:Show() end)
    win.center:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win.world = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.world:SetSize(74, 20); win.world:SetPoint("RIGHT", win.center, "LEFT", -6, 0); win.world:SetText("World map")

    win.world:SetScript("OnClick", function() S.MapToggleWorld() end)

    -- map art + canvas
    view = CreateFrame("Frame", nil, win); view:SetPoint("TOPLEFT", 6, -44); view:SetSize(CANVAS_W, 466)

    if view.SetClipsChildren then view:SetClipsChildren(true) end

    view:EnableMouse(true); view:EnableMouseWheel(true)

    -- The cursor's spot inside the map view
    local function cursorInView()
        local x, y = GetCursorPosition(); local sc = view:GetEffectiveScale()

        return x / sc - view:GetLeft(), view:GetTop() - y / sc      -- down-positive
    end

    view:SetScript("OnMouseWheel", function(_, delta)
        local cx, cy = cursorInView()
        local px, py = (cx - ox) / zoom, (cy - dy) / zoom        -- map point under the cursor
        local nz = math.max(1, math.min(6, zoom * (delta > 0 and 1.25 or 0.8)))

        if nz < 1.05 then nz = 1 end

        zoom = nz
        autoCenter = false
        ox, dy = cx - px * zoom, cy - py * zoom

        if zoom == 1 then ox, dy = 0, 0 end

        S.ViewerRedraw()
    end)

    local panning, sx0, sy0, ox0, dy0
    local lastClick = 0

    view:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end

        local now = GetTime()

        if now - lastClick < 0.35 then lastClick = 0; zoom, ox, dy = 1, 0, 0; panning = false; S.ViewerRedraw() return end

        lastClick = now

        if zoom == 1 then return end

        panning = true; autoCenter = false; sx0, sy0 = cursorInView(); ox0, dy0 = ox, dy
    end)

    view:SetScript("OnMouseUp", function() panning = false end)
    view:SetScript("OnUpdate", function()
        if not panning then return end
        if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then panning = false return end

        local cx, cy = cursorInView()
        local nox, ndy = ox0 + (cx - sx0), dy0 + (cy - sy0)

        nox = math.max(CANVAS_W - CANVAS_W * zoom, math.min(0, nox)); ndy = math.max(baseH - baseH * zoom, math.min(0, ndy))

        if nox ~= ox or ndy ~= dy then
            ox, dy = nox, ndy

            canvas:ClearAllPoints(); canvas:SetPoint("TOPLEFT", view, "TOPLEFT", ox, -dy)
        end
    end)

    art = CreateFrame("Frame", nil, view); art:SetPoint("TOPLEFT", 0, 0)
    art.fallback = art:CreateTexture(nil, "BACKGROUND", nil, 2); art.fallback:SetAllPoints(); art.fallback:SetColorTexture(.14, .16, .22, 1)
    art.fallbackText = art:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); art.fallbackText:SetPoint("CENTER")
    canvas = art

    art:SetSize(CANVAS_W, 466)

    -- timeline panel
    panel = CreateFrame("Frame", nil, win, BD)

    S.SkinBox(panel); panel:SetBackdropColor(.08, .09, .13, 1); panel:SetBackdropBorderColor(.25, .28, .4, 1)
    panel:SetPoint("TOPLEFT", view, "TOPRIGHT", 6, 0); panel:SetSize(PANEL_W, 466)

    panel.tabs = CreateFrame("Frame", nil, panel); panel.tabs:SetPoint("TOPLEFT", 4, -4); panel.tabs:SetPoint("TOPRIGHT", -4, -4); panel.tabs:SetHeight(24)
    panel.stats = panel.tabs:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); panel.stats:SetPoint("BOTTOMLEFT", panel.tabs, "BOTTOMLEFT", 4, -14); panel.stats:SetPoint("RIGHT", -4, 0); panel.stats:SetJustifyH("LEFT"); panel.stats:SetTextColor(.6, .65, .75); panel.stats:SetWordWrap(false)

    -- A side panel tab (Timeline, Compare)
    local function mkTab(text, mode, anchor)
        local button = CreateFrame("Button", nil, panel.tabs, "UIPanelButtonTemplate"); button:SetSize(96, 20); button:SetText(text)

        if anchor then button:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 0, 0) end

        button:SetScript("OnClick", function() panelMode = mode; S.ViewerRedraw() end)

        return button
    end

    panel.tabs.tl = mkTab("Timeline", "timeline")
    panel.tabs.cmp = mkTab("Compare", "compare", panel.tabs.tl)
    panel.tabs.off = CreateFrame("Button", nil, panel.tabs, "UIPanelCloseButton"); panel.tabs.off:SetPoint("RIGHT", 2, 0); panel.tabs.off:SetScale(.7)

    panel.tabs.off:SetScript("OnClick", function() compare = nil; panelMode = "timeline"; scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4); S.ViewerRedraw() end)
    panel.tabs:Hide()

    scroll = CreateFrame("ScrollFrame", "SterlingQuestViewerScroll", panel, "UIPanelScrollFrameTemplate")

    scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    content = CreateFrame("Frame", nil, scroll)

    content:SetSize(PANEL_W - 32, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

    -- scrubber
    bar = CreateFrame("Frame", nil, win, BD)

    S.SkinBox(bar); bar:SetBackdropColor(.08, .09, .13, 1); bar:SetBackdropBorderColor(.25, .28, .4, 1)
    bar:SetHeight(34); bar:SetPoint("BOTTOMLEFT", 6, 6); bar:SetPoint("BOTTOMRIGHT", -6, 6)

    bar.play = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); bar.play:SetSize(28, 22); bar.play:SetPoint("LEFT", 8, 0); bar.play:SetText(">")

    bar.play:SetScript("OnClick", function() S.ViewerPlay(not playing) end)

    bar.spd = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); bar.spd:SetSize(36, 22); bar.spd:SetPoint("LEFT", bar.play, "RIGHT", 4, 0); bar.spd:SetText("4x")

    bar.spd:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.spd:SetScript("OnClick", function(_, btn)
        local i = 1

        for k, v in ipairs(SPEEDS) do if v == speed then i = k end end

        i = btn == "RightButton" and math.max(1, i - 1) or math.min(#SPEEDS, i + 1)
        speed = SPEEDS[i]; S.ViewerRedraw()
    end)

    bar.spd:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Playback speed"); GameTooltip:AddLine("Left-click faster, right-click slower.", .6, .65, .75); GameTooltip:Show() end)
    bar.spd:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.timeText = bar:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); bar.timeText:SetPoint("LEFT", bar.spd, "RIGHT", 10, 0); bar.timeText:SetWidth(58); bar.timeText:SetJustifyH("LEFT")
    bar.endText = bar:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); bar.endText:SetPoint("RIGHT", -10, 0); bar.endText:SetTextColor(.6, .65, .75)
    bar.slider = CreateFrame("Slider", "SterlingQuestViewerSlider", bar, "OptionsSliderTemplate")

    bar.slider:SetPoint("LEFT", bar.timeText, "RIGHT", 6, 0); bar.slider:SetPoint("RIGHT", bar.endText, "LEFT", -10, 0); bar.slider:SetHeight(16)
    bar.slider:SetMinMaxValues(0, 1); bar.slider:SetValueStep(0.001); bar.slider:SetObeyStepOnDrag(true)

    if SterlingQuestViewerSliderLow then SterlingQuestViewerSliderLow:SetText(""); SterlingQuestViewerSliderHigh:SetText(""); SterlingQuestViewerSliderText:SetText("") end

    bar.slider:SetScript("OnValueChanged", function(self, v, user)
        if not session or not user then return end

        playing = false
        playT = session.start + v * math.max(1, (session.stop or time()) - session.start)

        S.ViewerRedraw()
    end)

    local acc = 0

    bar:SetScript("OnUpdate", function(_, dt)
        if not playing or not session then return end

        acc = acc + dt

        if acc < 0.1 then return end

        playT = (playT or session.start) + acc * speed * 10
        acc = 0

        if playT >= (session.stop or time()) then playT = session.stop or time(); playing = false end

        S.Safe("viewer", redraw)
    end)

    win:SetScript("OnShow", function() S.ViewerRedraw() end)
    win:SetScript("OnHide", function() playing = false end)
    win:Hide()
end

-- Starts or stops playback in the map window
function S.ViewerPlay(on)
    if not session then return end

    playing = on

    if on then autoFollow = true end
    if on and (not playT or playT >= (session.stop or time())) then playT = session.start end

    S.ViewerRedraw()
end

-- Which session the map window shows
function S.ViewerSetSession(sess)
    if compare and sess ~= compare.theirs then compare = nil; panelMode = "timeline" end

    session = sess
    playT, playing, viewMap, autoFollow = nil, false, nil, true
    collapsed = {}

    if sess then indexPins(); S.Safe("viewer", buildTimeline) end
    if win and win:IsShown() then S.ViewerRedraw() end
end

-- Compare two sessions. The one recorded by this character is "you"; the other is "them" and is the one played back.
function S.ViewerCompare(a, b)
    local theirs, mine = a, b

    if S.IsMe(a.char) and not S.IsMe(b.char) then theirs, mine = b, a end

    local diff = S.DiffSessions(theirs, mine)

    compare = { diff = diff, mine = mine, theirs = theirs }
    panelMode = "compare"; foldCmp = {}

    if not win then build() end

    S.ViewerSetSession(theirs)

    if not win:IsShown() then win:Show() end

    S.ViewerRedraw()
    msg(string.format("Comparing %s's \"%s\" against your \"%s\": %d extra, %d missed, %d same.", theirs.char or "?", theirs.name, mine.name, #diff.extra, #diff.missed, #diff.same))
end

-- Opens or closes the map window
function S.ViewerToggle()
    if not win then build() end
    if win:IsShown() then win:Hide() return end
    if not session then
        local sess = S.FindSession(SterlingQuestDB.following) or SterlingQuestDB.sessions[1]

        if sess then S.ViewerSetSession(sess) end
    end

    if not session then msg("No session to show. Record one or import one first.") return end

    win:Show(); S.ViewerRedraw()
end

-- Keep the world-map overlay and the viewer on the same session.
local oldSet = S.MapSetSession

-- Keeps the map window on the same session as the world map
function S.MapSetSession(sess)
    if oldSet then oldSet(sess) end

    S.ViewerSetSession(sess)
end
