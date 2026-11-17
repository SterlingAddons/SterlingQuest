-- Sterling Quest Sync: the look. "wow" (default) builds windows from Blizzard's own frame pieces
-- (metal nine-slice border, rock background, title tile, inset panels, bottom tabs) so the addon
-- looks like it shipped with the game. "navy" is Sterling's flat dark-blue look from before 5.46.
-- Every Blizzard piece is tried in a pcall with a flat fallback, since this client drops old textures.
local ADDON, S = ...

function S.WowSkin() return S.Opt("skin", "wow") == "wow" end

S.BG_FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
S.BG_TIP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
S.BG_DIALOG = { bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 256, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }

-- Accent colour used for selected tabs, headers and highlights: Blizzard gold, or Sterling blue.
-- Saved settings arrive after this file loads, so ThemeInit runs from ADDON_LOADED before any window is built.
S.AR, S.AG, S.AB, S.ACCENT_HEX = 1, .82, 0, "|cffffd100"
function S.ThemeInit()
  local o = SterlingQuestDB and SterlingQuestDB.opts
  if o then o.glowX, o.glowY, o.glowW, o.glowH, o.tabNudgeX, o.tabNudgeY = nil, nil, nil, nil, nil, nil end   -- old tuning nudges, now built in
  if S.WowSkin() then S.AR, S.AG, S.AB, S.ACCENT_HEX = 1, .82, 0, "|cffffd100" else S.AR, S.AG, S.AB, S.ACCENT_HEX = .54, .72, 1, "|cff8ab8ff" end
  local ac = not S.WowSkin() and S.Opt("navyAccent", nil)
  if type(ac) == "table" then
    S.AR, S.AG, S.AB = ac[1], ac[2], ac[3]
    S.ACCENT_HEX = ("|cff%02x%02x%02x"):format(math.floor(ac[1] * 255 + .5), math.floor(ac[2] * 255 + .5), math.floor(ac[3] * 255 + .5))
  end
  S.ApplyTextColor()
end
-- Flat look colour: every navy shade is re-coloured from the panel colour you pick (Options > General),
-- keeping its brightness, so the window, panels and edges stay in step. Reds (warnings) are left alone.
local NAVY_L = .3 * .16 + .59 * .2 + .11 * .33   -- brightness of the standard panel navy
function S.NavyWith(c, r, g, b)
  if type(c) ~= "table" or not r then return r, g, b end
  if r > .55 and g < .5 then return r, g, b end
  local L = .3 * r + .59 * g + .11 * b
  local k = L / NAVY_L
  return math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k)
end
function S.Navy(r, g, b)
  if S.WowSkin() then return r, g, b end
  return S.NavyWith(S.Opt("navyColor", nil), r, g, b)
end
-- Flat look colour presets: panel colour plus accent. "Matching" keeps one hue; "Contrast" pairs it with its complement.
S.FLAT_PRESETS = {
  { "Navy",      { .16, .2, .33 },  { .54, .72, 1 },   "match" },
  { "Slate",     { .2, .21, .23 },  { .76, .79, .84 }, "match" },
  { "Crimson",   { .3, .09, .09 },  { 1, .47, .45 },   "match" },
  { "Forest",    { .1, .22, .14 },  { .52, .9, .6 },   "match" },
  { "Plum",      { .22, .12, .28 }, { .8, .62, 1 },    "match" },
  { "Teal",      { .08, .22, .24 }, { .45, .88, .88 }, "match" },
  { "Midnight & amber", { .12, .14, .22 }, { 1, .72, .3 },   "contrast" },
  { "Charcoal & gold",  { .18, .18, .19 }, { 1, .82, .35 },  "contrast" },
  { "Crimson & gold",   { .3, .09, .09 },  { 1, .8, .4 },    "contrast" },
  { "Forest & copper",  { .1, .22, .14 },  { .95, .6, .38 }, "contrast" },
  { "Plum & mint",      { .22, .12, .28 }, { .52, .95, .76 }, "contrast" },
  { "Teal & coral",     { .08, .22, .24 }, { 1, .58, .48 },  "contrast" },
}
function S.Accent() return S.AR, S.AG, S.AB end
-- Body text: Blizzard's pure white hurts on dark panels, so the WoW skin uses a warm off-white.
S.TR, S.TG, S.TB, S.TEXT_HEX = .9, .87, .8, "|cffe6deca"
-- Our own font objects (same fonts as the game's, our text colour). Fall back to the game's names.
S.FONT_SMALL, S.FONT = "GameFontHighlightSmall", "GameFontHighlight"
do
  local ok1, f1 = pcall(CreateFont, "SterlingFontSmall")
  local ok2, f2 = pcall(CreateFont, "SterlingFont")
  if ok1 and type(f1) == "table" and f1.SetFontObject then f1:SetFontObject("GameFontHighlightSmall"); S.FONT_SMALL = "SterlingFontSmall"; S.fontSmall = f1 end
  if ok2 and type(f2) == "table" and f2.SetFontObject then f2:SetFontObject("GameFontHighlight"); S.FONT = "SterlingFont"; S.font = f2 end
end
function S.ApplyTextColor()
  if S.WowSkin() then S.TR, S.TG, S.TB, S.TEXT_HEX = .9, .87, .8, "|cffe6deca" else S.TR, S.TG, S.TB, S.TEXT_HEX = 1, 1, 1, "|cffffffff" end
  if S.fontSmall then pcall(S.fontSmall.SetTextColor, S.fontSmall, S.TR, S.TG, S.TB) end
  if S.font then pcall(S.font.SetTextColor, S.font, S.TR, S.TG, S.TB) end
end
function S.TextColor() return S.TR, S.TG, S.TB end
-- Label colour: gold in the WoW skin (like "Health:"), soft grey in navy.
function S.LabelColor() if S.WowSkin() then return 1, .82, 0 end return .56, .6, .7 end

-- Colour-blind mode (Options > General): wherever red and green carry meaning, a symbol goes with
-- the colour. S.Mark("good" | "bad" | "warn") gives that symbol as text to put in front of a label,
-- or "" when the mode is off. always = true gives it regardless (used where a symbol reads well anyway).
local MARK_TEX = { good = "Interface\\RaidFrame\\ReadyCheck-Ready", bad = "Interface\\RaidFrame\\ReadyCheck-NotReady", warn = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
local MARK_TXT = { good = "[+] ", bad = "[x] ", warn = "[!] " }
local markTex
function S.ColorBlind() return S.Opt("cb", false) and true or false end
function S.Mark(kind, always)
  if not always and not S.ColorBlind() then return "" end
  if markTex == nil then
    local ok, t = pcall(UIParent.CreateTexture, UIParent)
    markTex = (ok and t and S.TexOK(t, MARK_TEX.good)) and true or false
    if ok and t then pcall(t.Hide, t) end
  end
  if markTex and MARK_TEX[kind] then return "|T" .. MARK_TEX[kind] .. ":0|t " end
  return MARK_TXT[kind] or ""
end

-- Did a texture path actually load? (missing files come back false / nil on this client)
local function texOK(t, path, ...)
  local ok, res = pcall(t.SetTexture, t, path, ...)
  if not ok or res == false then return false end
  local ok2, got = pcall(t.GetTexture, t)
  return ok2 and got ~= nil
end
S.TexOK = texOK

-- Panels inside windows (cards, lists, menus). In the WoW skin: black tooltip panel with the gold-brown
-- tooltip edge, and colour calls from the old look are mapped onto it (navy tints become black,
-- blue borders become the edge's own gold; reds and other alerts keep their colour).
function S.SkinBox(f, flat)
  if not f.SetBackdrop then return f end
  if flat or not S.WowSkin() then
    f:SetBackdrop(S.BG_FLAT)
    if not S.WowSkin() then
      local rawBg, rawEdge = f.SetBackdropColor, f.SetBackdropBorderColor
      f.SetBackdropColor = function(self, r, g, b, a) local nr, ng, nb = S.Navy(r, g, b); rawBg(self, nr, ng, nb, a) end
      f.SetBackdropBorderColor = function(self, r, g, b, a) local nr, ng, nb = S.Navy(r, g, b); rawEdge(self, nr, ng, nb, a) end
    end
    return f
  end
  f:SetBackdrop(S.BG_TIP)
  -- warm dark grey rather than black, and the edge toned down: less of a jump from the text
  local EDGE_R, EDGE_G, EDGE_B = .78, .68, .5
  f:SetBackdropColor(.16, .14, .12, .85); f:SetBackdropBorderColor(EDGE_R, EDGE_G, EDGE_B, 1)
  local rawBg, rawEdge = f.SetBackdropColor, f.SetBackdropBorderColor
  local function alert(r, g, b) return (r or 0) > .55 and (g or 0) < .5 end         -- red-ish warnings keep their tint
  f.SetBackdropColor = function(self, r, g, b, a)
    if alert(r, g, b) then rawBg(self, r, g, b, a) return end
    a = a or 1
    rawBg(self, .16, .14, .12, math.max(a, .55))
  end
  f.SetBackdropBorderColor = function(self, r, g, b, a)
    if alert(r, g, b) then rawEdge(self, r, g, b, a) return end
    rawEdge(self, EDGE_R, EDGE_G, EDGE_B, a or 1)
  end
  return f
end

-- A top-level window's chrome. Returns nothing; sets f.bg / f.nine / f.titleTile as it goes.
function S.SkinWindow(f)
  if not f.SetBackdrop then return end
  if not S.WowSkin() then
    f:SetBackdrop(S.BG_FLAT)
    local r, g, b = S.Navy(.1, .12, .17); f:SetBackdropColor(r, g, b, .96)
    r, g, b = S.Navy(.26, .3, .4); f:SetBackdropBorderColor(r, g, b, 1)
    return
  end
  -- solid dark floor so a missing texture never leaves a see-through window
  f.base = f:CreateTexture(nil, "BACKGROUND", nil, -8); f.base:SetPoint("TOPLEFT", 4, -4); f.base:SetPoint("BOTTOMRIGHT", -4, 4); f.base:SetColorTexture(.09, .09, .09, .97)
  -- rock background, tiled (what the profession, character and bag windows use)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -7); f.bg:SetPoint("TOPLEFT", 4, -4); f.bg:SetPoint("BOTTOMRIGHT", -4, 4)
  if texOK(f.bg, "Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT") then
    pcall(f.bg.SetHorizTile, f.bg, true); pcall(f.bg.SetVertTile, f.bg, true); f.bg:SetVertexColor(.9, .9, .9, 1)
  else f.bg:Hide() end
  -- gold metal nine-slice edge; fall back to the classic dialog border
  local okNine = pcall(function()
    local ns = CreateFrame("Frame", nil, f, "NineSlicePanelTemplate")
    ns:SetAllPoints(); ns:SetFrameLevel(f:GetFrameLevel() + 2)   -- above the inset (+1) and the selected tab (+1)
    NineSliceUtil.ApplyLayoutByName(ns, "ButtonFrameTemplateNoPortrait")
    assert(ns.TopEdge and ns.TopEdge.GetAtlas and ns.TopEdge:GetAtlas())
    ns:EnableMouse(false)
    f.nine = ns
  end)
  if okNine then
    f:SetBackdrop(S.BG_FLAT); f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0)
  else
    f:SetBackdrop(S.BG_DIALOG); f:SetBackdropColor(1, 1, 1, 1); f:SetBackdropBorderColor(1, 1, 1, 1)
    f.base:SetPoint("TOPLEFT", 10, -10); f.base:SetPoint("BOTTOMRIGHT", -10, 10)
  end
  -- title band
  f.titleTile = f:CreateTexture(nil, "BORDER"); f.titleTile:SetPoint("TOPLEFT", okNine and 4 or 10, okNine and -4 or -10); f.titleTile:SetPoint("TOPRIGHT", okNine and -4 or -10, okNine and -4 or -10); f.titleTile:SetHeight(okNine and 24 or 20)
  if texOK(f.titleTile, "Interface\\FrameGeneral\\_UI-Frame-TitleTile", "REPEAT", "CLAMP") then pcall(f.titleTile.SetHorizTile, f.titleTile, true)
  else f.titleTile:SetColorTexture(.13, .11, .08, 1) end
  f.titleLine = f:CreateTexture(nil, "BORDER", nil, 1); f.titleLine:SetPoint("BOTTOMLEFT", f.titleTile, "BOTTOMLEFT", 0, 0); f.titleLine:SetPoint("BOTTOMRIGHT", f.titleTile, "BOTTOMRIGHT", 0, 0); f.titleLine:SetHeight(1); f.titleLine:SetColorTexture(.42, .34, .16, 1)
end

-- The sunken dark panel behind a window's content (same as the recipe list in the cooking window).
function S.Inset(parent, name)
  if not S.WowSkin() then return nil end
  local ok, inset = pcall(CreateFrame, "Frame", name, parent, "InsetFrameTemplate")
  if ok and inset then
    inset:EnableMouse(false)
    -- let the rock show through a little so the panel isn't pitch black behind white text
    local bg = rawget(inset, "Bg")
    if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, .6) end
    return inset
  end
  return nil
end

-- Blizzard bottom tabs (the character window kind). Returns the tab or nil if no template exists.
function S.BlizzTab(parent, name, index, text)
  if not S.WowSkin() then return nil end
  local tab
  for _, tpl in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "TabButtonTemplate" }) do
    local ok, t = pcall(CreateFrame, "Button", name, parent, tpl)
    if ok and type(t) == "table" and (rawget(t, "Left") or rawget(t, "LeftActive") or rawget(t, "Text") or _G[name .. "Left"] or _G[name .. "LeftActive"]) then tab = t break end
    if ok and t then pcall(t.Hide, t) end
  end
  if not tab then return nil end
  tab:SetID(index); tab:SetText(text)
  pcall(PanelTemplates_TabResize, tab, 0)
  return tab
end

-- Lay Blizzard tabs out under a window, evenly sharing its full width (hidden tabs skipped).
-- Tabs sit at the window's own frame level so the border art draws over their tops, like the character frame.
-- A Blizzard tab's left and right art pieces (deselected art).
function S.TabArt(t)
  local n = t.GetName and t:GetName() or ""
  local L = rawget(t, "Left") or _G[n .. "Left"]
  local R = rawget(t, "Right") or _G[n .. "Right"]
  if type(L) ~= "table" or type(R) ~= "table" or not L.GetLeft or not R.GetRight then return nil end
  return L, R
end

function S.LayoutTabs(parent, list)
  local vis = {}
  for _, t in ipairs(list) do if t:IsShown() then vis[#vis + 1] = t end end
  local n = #vis
  if n == 0 then return end
  local W = parent:GetWidth() or 0
  if W < 100 then W = 370 end
  local inset = 9   -- clear of the frame's rounded metal corners
  -- The tab art has about 8px of empty space on each side of the button (Blizzard's own tabs
  -- overlap by 16 for the same reason), so buttons are made 16 wider than their share and
  -- overlapped by 16: the visible art then runs edge to edge across the window.
  local PAD = 4   -- measured in game: the art has about 4px of air each side
  local GAP = 2                          -- visible space between tabs: they never overlap
  local a = (W - 2 * inset - GAP * (n - 1)) / n          -- visible width per tab
  -- The template's art doesn't sit evenly on its button (its left and right pieces hang past the
  -- button by different amounts), so measure how far the art runs past each side and place the
  -- tabs by their art. That keeps the gap to each corner the same on both sides.
  local function artExt(t)
    local L, R = S.TabArt(t)
    local tl, tr = t:GetLeft(), t:GetRight()
    if not (L and R and tl and tr) then return 0, 0 end
    local ll, rr = L:GetLeft(), R:GetRight()
    if not (ll and rr) then return 0, 0 end
    return tl - ll, rr - tr
  end
  -- Measured in game (6.07, with a measuring command and a screenshot): a tab's visible art starts right at its
  -- button's left edge and stops about 4 short of its right edge (the art pieces' own overhang and
  -- see-through edges cancel out that way). The metal border sits evenly on the frame, so the row is
  -- centred on the frame, each tab placed by its visible art.
  local VIS_R = 4
  local function apply()
    -- whole pixels only: fractional widths made the gaps between tabs come out uneven
    local vw = math.floor((W - 2 * inset - GAP * (n - 1)) / n)   -- visible width per tab
    local left = math.floor((W - (vw * n + GAP * (n - 1))) / 2)  -- same space on both ends
    local width = vw + VIS_R
    for i, t in ipairs(vis) do
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", left + (i - 1) * (vw + GAP), 4)   -- position approved in game (6.12)   -- +1: measured 6.08, the metal sits 1 further right
      t.sterlingWidth = width
      if not pcall(PanelTemplates_TabResize, t, 0, width) then t:SetWidth(width) end
      if (t:GetWidth() or 0) ~= width then t:SetWidth(width) end
      t:SetFrameLevel(parent:GetFrameLevel())
    end
  end
  apply()
  -- whatever the template does on show or select, put ours back right after
  if C_Timer and C_Timer.After then C_Timer.After(0, apply) end
  parent.sterlingApplyTabs = apply
  for _, t in ipairs(vis) do
    if not t.sterlingHooked then
      t.sterlingHooked = true
      t:HookScript("OnShow", function() if parent.sterlingApplyTabs then parent.sterlingApplyTabs() end end)
    end
  end
  if not parent.sterlingTabHook then
    parent.sterlingTabHook = true
    parent:HookScript("OnShow", function(self) if rawget(self, "Tabs") then S.LayoutTabs(self, self.Tabs) end end)
  end
end

-- All tabs keep the same (unselected) shape; the chosen one just lights up: a gold glow and bright text.
local function glowFor(t)
  local g = rawget(t, "sterlingGlow")
  if g then return g end
  -- a soft yellow wash over the tab, fading out toward the bottom, plus a thin lit rim on top
  g = t:CreateTexture(nil, "ARTWORK", nil, 7)
  -- pinned to the tab's own art pieces, so it lines up with what you see rather than the button frame
  local L, R = S.TabArt(t)
  if L and R then g:SetPoint("TOPLEFT", L, "TOPLEFT", 7, -6); g:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", -7, 5)
  else g:SetPoint("TOPLEFT", 8, -6); g:SetPoint("BOTTOMRIGHT", -8, 5) end
  g:SetColorTexture(1, .86, .2, 1)
  if g.SetGradient and CreateColor then
    pcall(g.SetGradient, g, "VERTICAL", CreateColor(1, .86, .2, .02), CreateColor(1, .86, .2, .16))
  else g:SetAlpha(.1) end
  local line = t:CreateTexture(nil, "ARTWORK", nil, 7)
  line:SetPoint("TOPLEFT", g, "TOPLEFT", 1, 0); line:SetPoint("TOPRIGHT", g, "TOPRIGHT", -1, 0); line:SetHeight(1); line:SetColorTexture(1, .86, .2, .55)
  g.line = line
  t.sterlingGlow = g
  return g
end
-- The selected tab's glow: our own texture over the tab's art. (The game's hover glow got re-sized
-- by the tab template every time the tabs were laid out.) Offsets lined up by eye in game (6.12).
function S.FitTabGlow(t)
  local g = rawget(t, "sterlingGlow")
  if not g then return end
  local L, R = S.TabArt(t)
  g:ClearAllPoints()
  if L and R then
    g:SetPoint("TOPLEFT", L, "TOPLEFT", 4, -6)
    g:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", -8, 5)
  else
    g:SetPoint("TOPLEFT", 5, -6)
    g:SetPoint("BOTTOMRIGHT", -9, 5)
  end
end

function S.BlizzSelectTab(parent, index)
  pcall(PanelTemplates_SetNumTabs, parent, #parent.Tabs)
  parent.selectedTab = index
  for i, t in ipairs(parent.Tabs) do
    pcall(PanelTemplates_DeselectTab, t)          -- same shape for every tab
    local on = (i == index)
    local g = glowFor(t)
    S.FitTabGlow(t)
    pcall(t.UnlockHighlight, t)
    g:SetShown(on); g.line:SetShown(on)
    local okF, fs = pcall(t.GetFontString, t)
    if okF and fs and fs.SetTextColor then
      -- every tab's label sits at the same spot (the template nudges the selected one up; undo that)
      if not S.tabTextPt and i ~= index then
        local okP, p, _, rp, x, y = pcall(fs.GetPoint, fs, 1)
        if okP and p then S.tabTextPt = { p, rp or p, x or 0, y or 0 } end
      end
      local pt = S.tabTextPt
      if pt then fs:ClearAllPoints(); fs:SetPoint(pt[1], t, pt[2], pt[3], pt[4]) end
      pcall(t.SetPushedTextOffset, t, 0, 0)
      if on then fs:SetTextColor(1, .93, .45) else fs:SetTextColor(.85, .7, .2) end
    end
  end
  if rawget(parent, "sterlingApplyTabs") then
    parent.sterlingApplyTabs()
    -- the template can resize tabs to their text a frame later: put our widths back after that too
    if C_Timer and C_Timer.After then C_Timer.After(0, function() if parent.sterlingApplyTabs then parent.sterlingApplyTabs() end end) end
  end
  -- the selected tab sits on top of its neighbours and the window's bottom edge, like Blizzard's
  -- (apply() above already put the selected tab one level over its neighbours, under the frame's edge)
end

-- Section header bar (Options page, like "Camping" in the cooking window): gold text on a dark strip.
function S.SectionBar(parent, text, y, width)
  local bar = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  bar:SetPoint("TOPLEFT", 0, y); bar:SetHeight(20)
  if width then bar:SetWidth(width) else bar:SetPoint("RIGHT", parent, "RIGHT", -2, 0) end
  if S.WowSkin() then
    S.SkinBox(bar); bar:SetBackdropColor(.09, .07, .03, .9)
  else
    S.SkinBox(bar, true); bar:SetBackdropColor(.16, .2, .33, 1); bar:SetBackdropBorderColor(.23, .27, .37, 1)
  end
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal"); bar.text:SetPoint("LEFT", 8, 0); bar.text:SetText(text); bar.text:SetTextColor(S.Accent())
  return bar
end
