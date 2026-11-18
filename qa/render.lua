-- dump a window as a flat list of drawable things, in drawing order
local rect, plain = GEOM.rect, GEOM.plain

function DUMP(win)
    local out = {}
    local wr = rect(win)

    local function add(o, clip)
        local r = rect(o)

        if not r then return end

        local kind = o._kind
        local e = { kind, r[1] - wr[1], wr[4] - r[4], r[3] - r[1], r[4] - r[2] }
        local c = o._color or o._bg

        if kind == "Texture" then
            if not o._color then return end

            e[6] = table.concat({ c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }, ",")
        elseif kind == "FontString" then
            local t = plain(o._text or ""); if t:gsub("%s", "") == "" then return end
            local tc = o._tc or { .9, .87, .8 }

            e[6] = table.concat({ tc[1] or 1, tc[2] or 1, tc[3] or 1 }, ",")
            e[7] = t; e[8] = o._font or ""; e[9] = o._jh or (#o._points >= 2 and "CENTER" or "LEFT"); e[10] = o._wrap == false and "nowrap" or "wrap"
        else
            local bg, ed = o._bg, o._edge

            e[6] = bg and table.concat({ bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1 }, ",") or ""
            e[7] = plain(o._text or ""); e[8] = o._template or ""; e[9] = ed and table.concat({ ed[1] or 0, ed[2] or 0, ed[3] or 0, ed[4] or 1 }, ",") or ""
            e[10] = (o._enabled == false) and "off" or ((o._checked and "checked") or "")
        end

        if clip then e[11] = table.concat({ clip[1] - wr[1], wr[4] - clip[4], clip[3] - clip[1], clip[4] - clip[2] }, ",") end

        for i = 1, 11 do e[i] = tostring(e[i] or "") end

        out[#out + 1] = table.concat(e, "\t")
    end

    local function walk(o, clip)
        -- a frame's own regions first, then child frames by level
        local regs, frames = {}, {}

        for _, c in ipairs(o._children) do if c._shown then if c._region then regs[#regs + 1] = c else frames[#frames + 1] = c end end end
        for _, c in ipairs(regs) do add(c, clip) end

        table.sort(frames, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)

        for _, c in ipairs(frames) do
            add(c, clip)

            local nc = clip

            if c._kind == "ScrollFrame" then nc = rect(c) end

            walk(c, nc)
        end
    end

    add(win); walk(win, nil)

    return table.concat(out, "\n"), wr[3] - wr[1], wr[4] - wr[2]
end
