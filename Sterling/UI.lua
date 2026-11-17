-- Sterling UI: one tabbed window (Path / Sessions / Compare), record bar, save dialog,
-- export/import box, minimap button.
local _, S = ...
local msg = S.msg

local KIND_COLOR = { turnin = { .49, .89, .64 }, pickup = { S.AR, S.AG, S.AB }, deliver = { .49, .89, .64 }, ["do"] = { .95, .77, .42 }, objective = { .95, .77, .42 },
                     skip = { 1, .61, .57 }, travel = { .76, .66, 1 }, flight = { .76, .66, 1 }, ride = { .4, .8, .9 }, hearth = { .4, .8, .9 }, dungeon = { 1, .61, .57 }, ding = { .49, .89, .64 }, note = { .95, .85, .4 } }
local BG = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil

-- flat = plain one-pixel box in both skins (pills, tiny chips)
-- Open the game's colour picker. onChange(r, g, b, a) fires as you drag; Cancel puts the old colour back.
function S.PickColor(r, g, b, a, hasAlpha, onChange)
  local CPF = _G.ColorPickerFrame
  if type(CPF) ~= "table" then return end
  local function now()
    local nr, ng, nb = CPF:GetColorRGB()
    local na = a
    if hasAlpha then
      if CPF.GetColorAlpha then na = CPF:GetColorAlpha()
      elseif _G.OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
    end
    return nr, ng, nb, na
  end
  local function changed() onChange(now()) end
  local function cancel() onChange(r, g, b, a) end
  if CPF.SetupColorPickerAndShow then
    CPF:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha, swatchFunc = changed, opacityFunc = changed, cancelFunc = cancel })
  else
    CPF.hasOpacity = hasAlpha; CPF.opacity = 1 - (a or 1); CPF.previousValues = { r, g, b, a }
    CPF.func, CPF.opacityFunc, CPF.cancelFunc = changed, changed, cancel
    CPF:SetColorRGB(r, g, b); CPF:Hide(); ShowUIPanel(CPF)
  end
end

local function Box(parent, name, flat)
  local f = CreateFrame("Frame", name, parent, BD)
  S.SkinBox(f, flat)
  return f
end

local function Movable(f, name)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not S.Opt("lock", false) then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    SterlingQuestDB.pos = SterlingQuestDB.pos or {}; SterlingQuestDB.pos[name] = { p, rp, x, y }
  end)
  f.Restore = function(self)
    local p = SterlingQuestDB.pos and SterlingQuestDB.pos[name]
    if p then self:ClearAllPoints(); self:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
  end
end


-- Window rectangles in UIParent units, for keeping side windows apart.
local function winRect(w)
  local ok, l, b, wd, ht = pcall(w.GetRect, w)
  if not ok or type(l) ~= "number" or type(wd) ~= "number" then return nil end
  local k = (w:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return { l * k, b * k, (l + wd) * k, (b + ht) * k }
end
local function hits(a, b) return a and b and a[1] < b[3] - 2 and a[3] > b[1] + 2 and a[2] < b[4] - 2 and a[4] > b[2] + 2 end
function S.PlaceSide(self)
  local saved = SterlingQuestDB.pos and SterlingQuestDB.pos[self:GetName() or ""]
  if saved then self:Restore() end
  local m = _G.SterlingQuestFrame
  if not (m and m ~= self and m:IsShown()) then return end
  local others = {}
  for _, w in ipairs(S.windows or {}) do
    if w ~= self and w:IsShown() and (w == m or w.sterlingSide) then others[#others + 1] = winRect(w) end
  end
  local function clear(r)
    if not r then return false end
    for _, o in ipairs(others) do if hits(r, o) then return false end end
    return true
  end
  local mine = winRect(self)
  -- a spot you dragged it to is always kept: windows layer properly now, so overlapping is your call
  if saved then return end
  if clear(mine) and not hits(mine, winRect(m)) then return end
  local mr = winRect(m)
  if not (mr and mine) then return end
  local w, h = mine[3] - mine[1], mine[4] - mine[2]
  local sw = UIParent:GetWidth() or 1920
  local k = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  -- try left of the main window, then right, then a little lower on either side
  local tries = {
    { "TOPRIGHT", "TOPLEFT", -8, 0, mr[1] - 8 - w, mr[4] - h },
    { "TOPLEFT", "TOPRIGHT", 8, 0, mr[3] + 8, mr[4] - h },
    { "TOPRIGHT", "TOPLEFT", -8, -60, mr[1] - 8 - w, mr[4] - 60 - h },
    { "TOPLEFT", "TOPRIGHT", 8, -60, mr[3] + 8, mr[4] - 60 - h },
  }
  local pick
  for _, t in ipairs(tries) do
    local r = { t[5], t[6], t[5] + w, t[6] + h }
    if r[1] >= 0 and r[3] <= sw and clear(r) then pick = t break end
  end
  pick = pick or ((mr[1] > w + 8) and tries[1] or tries[2])
  self:ClearAllPoints()
  self:SetPoint(pick[1], m, pick[2], pick[3] / k, pick[4] / k)
end

local function Window(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, BD)
  f:SetSize(w, h); f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:SetFrameStrata("HIGH")   -- above raid frames like Grid, which sit in MEDIUM
  S.SkinWindow(f)
  S.windows = S.windows or {}; S.windows[#S.windows + 1] = f
  f:SetAlpha(S.Opt("alpha", 1)); f:SetScale(S.Opt("scale", 1))   -- every window follows Window size and opacity
  -- each window is its own layer: the one you click or open comes to the front, whole. Without this
  -- two windows share frame levels and their pieces draw through each other.
  pcall(f.SetToplevel, f, true)
  -- remember the window you last opened or clicked, so pop-ups can open over it
  local function front(self) pcall(self.Raise, self); if self.sterlingSide ~= nil then S.activeWin = self end end
  f:HookScript("OnShow", front)
  f:HookScript("OnMouseDown", front)
  -- side windows never sit on top of the main window or each other: each time one opens (or the
  -- main window opens) it keeps its saved spot if that is clear, else moves beside the main window
  if name ~= "SterlingQuestSaveFrame" and name ~= "SterlingQuestShareAsk" and name ~= "SterlingQuestInvite" then
    f:HookScript("OnShow", function(self)
      if name == "SterlingQuestFrame" then
        for _, w in ipairs(S.windows or {}) do if w ~= self and w.sterlingSide and w:IsShown() then pcall(S.PlaceSide, w) end end
      else
        pcall(S.PlaceSide, self)
      end
    end)
    f.sterlingSide = name ~= "SterlingQuestFrame"
  end
  Movable(f, name)
  -- the title row lives on its own child frame so it draws above the window's border art
  -- head draws above the border art (a child frame always covers its parent's own textures), so the
  -- title tile is kept inside the border instead of running under the corner pieces
  local head = CreateFrame("Frame", nil, f); head:SetFrameLevel(f:GetFrameLevel() + 4)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(28)
  f.head = head
  local bar = head:CreateTexture(nil, "ARTWORK"); bar:SetAllPoints(); bar:SetColorTexture(S.Navy(.16, .2, .33)); bar:SetAlpha(1)
  if S.WowSkin() then
    bar:SetColorTexture(0, 0, 0, 0)
    if rawget(f, "titleTile") then f.titleTile:SetParent(head); f.titleTile:ClearAllPoints(); f.titleTile:SetPoint("TOPLEFT", head, "TOPLEFT", 10, -8); f.titleTile:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -10, 1) end
    if rawget(f, "titleLine") then f.titleLine:SetParent(head); f.titleLine:ClearAllPoints(); f.titleLine:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 10, 0); f.titleLine:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -10, 0) end
  end
  f.bar = bar
  local logo = head:CreateTexture(nil, "OVERLAY"); logo:SetSize(16, 16); logo:SetPoint("LEFT", head, "LEFT", S.WowSkin() and 16 or 9, 0); logo:SetTexture("Interface\\AddOns\\Sterling\\Media\\glyph")
  f.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("LEFT", logo, "RIGHT", 7, 0); f.title:SetText(title)
  if S.WowSkin() then f.title:SetTextColor(1, .82, 0) else f.title:SetTextColor(.96, .97, 1) end
  f.right = head:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.right:SetPoint("RIGHT", head, "RIGHT", -34, 0); f.right:SetTextColor(.65, .7, .8)
  -- a long title is cut short instead of running under whatever sits on the right of the title bar
  f.title:SetPoint("RIGHT", f.right, "LEFT", -8, 0); f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
  -- controls on a top layer so nothing covers them
  local top = CreateFrame("Frame", nil, f); top:SetAllPoints(head); top:SetFrameLevel(f:GetFrameLevel() + 8)
  f.top = top
  local close = CreateFrame("Button", nil, top, "UIPanelCloseButton"); close:SetScale(.8); close:SetPoint("CENTER", head, "RIGHT", -17, 0)   -- centred on the title bar
  close:SetScript("OnClick", function() f:Hide() end)   -- the template's default hides its parent, which here is the title layer, not the window
  f.close = close
  f:Hide()
  -- Escape closes it. The game looks the name up in _G when Escape is pressed, so after Apply rebuilds
  -- the windows the name must point at the new frame, not the old hidden one.
  _G[name] = f
  local listed = false
  for _, n in ipairs(UISpecialFrames) do if n == name then listed = true break end end
  if not listed then tinsert(UISpecialFrames, name) end
  return f
end

local function Button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 60, 21); b:SetText(text); return b
end

-- A dropdown: looks like a field with an arrow (not a red action button), opens a menu of choices.
-- textFn() gives the shown value, itemsFn() the menu items (S.ShowMenu format, use checked = for the current one).
local function Dropdown(parent, w, textFn, itemsFn)
  local d = CreateFrame("Button", nil, parent, BD)
  d:SetSize(w, 22)
  if d.SetBackdrop then d:SetBackdrop(S.BG_FLAT) end
  local function idle()
    if not d.SetBackdropColor then return end
    if S.WowSkin() then d:SetBackdropColor(.06, .05, .04, .9); d:SetBackdropBorderColor(.5, .42, .26, 1)
    else d:SetBackdropColor(0, 0, 0, .4); local r, g, b = S.Navy(.3, .35, .48); d:SetBackdropBorderColor(r, g, b, 1) end
  end
  idle()
  d.text = d:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); d.text:SetPoint("LEFT", 8, 0); d.text:SetPoint("RIGHT", -24, 0); d.text:SetJustifyH("LEFT"); d.text:SetWordWrap(false)
  d.arrow = d:CreateTexture(nil, "OVERLAY"); d.arrow:SetSize(20, 20); d.arrow:SetPoint("RIGHT", -1, 0)
  if not S.TexOK(d.arrow, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up") then
    d.arrow:Hide()
    d.arrowText = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); d.arrowText:SetPoint("RIGHT", -7, 0); d.arrowText:SetText("v")
  end
  d:SetScript("OnEnter", function(self) if self:IsEnabled() and self.SetBackdropBorderColor then self:SetBackdropBorderColor(S.AR, S.AG, S.AB, 1) end end)
  d:SetScript("OnLeave", idle)
  d:SetScript("OnClick", function(self)
    local items = itemsFn() or {}
    if #items > 0 then S.ShowMenu(items, self) end
  end)
  d.Refresh = function(self)
    self.text:SetText(textFn() or "")
    local on = self:IsEnabled()
    if on then self.text:SetTextColor(S.TR, S.TG, S.TB) else self.text:SetTextColor(.5, .5, .5) end
    self.arrow:SetDesaturated(not on)
  end
  d:Refresh()
  return d
end
S.UI_Dropdown = Dropdown
S.UI_Window, S.UI_Button, S.UI_Box = Window, Button, Box

local function Pill(parent)
  local p = Box(parent, nil, true)
  if p.SetBackdropColor then p:SetBackdropColor(0, 0, 0, 0); p:SetBackdropBorderColor(0, 0, 0, 0) end   -- nothing shows until Set gives it a kind
  p:SetSize(52, 15)
  p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); p.text:SetPoint("CENTER")
  -- one small coloured pill: a box with a label, sized to the text
  local function mini(parent)
    local b = Box(parent, nil, true)
    b:SetHeight(15)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("CENTER")
    b.Paint = function(self, label, c)
      self:SetBackdropColor(c[1], c[2], c[3], .16); self:SetBackdropBorderColor(c[1], c[2], c[3], .35)
      self.text:SetText(label); self.text:SetTextColor(c[1], c[2], c[3])
      self:SetWidth(math.max(44, self.text:GetStringWidth() + 14))
    end
    return b
  end
  p.Set = function(self, kind)
    if kind == "deliver" then
      -- pick up and turn in, back to back: both pills joined by an arrow (PICK UP > TURN IN)
      if not rawget(self, "a") then
        self.a = mini(self); self.a:SetPoint("LEFT", 0, 0)
        self.arrow = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.arrow:SetPoint("LEFT", self.a, "RIGHT", 3, 0); self.arrow:SetText(">"); self.arrow:SetTextColor(.55, .52, .45)
        self.b = mini(self); self.b:SetPoint("LEFT", self.arrow, "RIGHT", 3, 0)
      end
      self:SetBackdropColor(0, 0, 0, 0); self:SetBackdropBorderColor(0, 0, 0, 0); self.text:Hide()
      self.a:Paint("PICK UP", KIND_COLOR.pickup); self.b:Paint("TURN IN", KIND_COLOR.turnin)
      self.a:Show(); self.b:Show(); self.arrow:Show()
      self:SetWidth(self.a:GetWidth() + 6 + (self.arrow:GetStringWidth() or 6) + self.b:GetWidth())
      return
    end
    if rawget(self, "a") then self.a:Hide(); self.b:Hide(); self.arrow:Hide() end
    self.text:Show()
    local c = KIND_COLOR[kind] or { .8, .8, .8 }
    self:SetBackdropColor(c[1], c[2], c[3], .16); self:SetBackdropBorderColor(c[1], c[2], c[3], .35)
    self.text:SetText((S.KIND_LABEL[kind] or kind):upper()); self.text:SetTextColor(c[1], c[2], c[3])
    self:SetWidth(math.max(rawget(self, "minW") or 44, self.text:GetStringWidth() + 14))
  end
  return p
end

-- Slim scrollbar for the row lists: a track with a draggable thumb. onScroll(newOffset) is called while dragging.
local function MiniScroll(parent, onScroll)
  local sb = CreateFrame("Frame", nil, parent); sb:SetWidth(6)
  sb.track = sb:CreateTexture(nil, "BACKGROUND"); sb.track:SetAllPoints(); sb.track:SetColorTexture(1, 1, 1, .06)
  sb.thumb = CreateFrame("Button", nil, sb); sb.thumb:SetPoint("TOP", 0, 0); sb.thumb:SetWidth(6)
  sb.thumb.tex = sb.thumb:CreateTexture(nil, "ARTWORK"); sb.thumb.tex:SetAllPoints(); sb.thumb.tex:SetColorTexture(S.AR, S.AG, S.AB, .7)
  sb.thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(.7, .84, 1, .9) end)
  sb.thumb:SetScript("OnLeave", function(self) if not sb.drag then self.tex:SetColorTexture(S.AR, S.AG, S.AB, .7) end end)
  sb.thumb:SetScript("OnMouseDown", function() sb.drag = true; sb.startY = select(2, GetCursorPosition()) / sb:GetEffectiveScale(); sb.startOff = sb.offset end)
  sb.thumb:SetScript("OnMouseUp", function(self) sb.drag = false; self.tex:SetColorTexture(S.AR, S.AG, S.AB, .7) end)
  sb:SetScript("OnUpdate", function()
    if not sb.drag then return end
    if not IsMouseButtonDown("LeftButton") then sb.drag = false return end
    local y = select(2, GetCursorPosition()) / sb:GetEffectiveScale()
    local range = sb.total - sb.visible
    if range <= 0 then return end
    local px = (sb:GetHeight() - sb.thumb:GetHeight())
    local off = math.floor(sb.startOff + (sb.startY - y) / math.max(1, px) * range + .5)
    off = math.max(0, math.min(range, off))
    if off ~= sb.offset then sb.offset = off; onScroll(off) end
  end)
  -- offset: first visible index (0-based); visible: rows on screen; total: rows overall
  sb.Set = function(self, offset, visible, total)
    self.offset, self.visible, self.total = offset, visible, total
    if total <= visible then self:Hide() return end
    self:Show()
    local h = self:GetHeight()
    local th = math.max(14, h * visible / total)
    self.thumb:SetHeight(th)
    self.thumb:ClearAllPoints(); self.thumb:SetPoint("TOP", 0, -((h - th) * offset / (total - visible)))
  end
  sb:Hide()
  return sb
end

---------------------------------------------------------------------------
-- Main window with tabs
---------------------------------------------------------------------------
local main, tabs, pages, builders = nil, {}, {}, {}
local save, box
local addWin, invWin, offWin   -- Add a partner window, sync invite prompt, offline sync window
local ROWS = 24          -- rows that exist; how many show depends on "expanded" and how tall the window is
-- In the full view, as many step rows as fit between the card and the bottom buttons (the window can be any size).
local function pathRowsFit(page)
  local top, bottom = page.listArea and page.listArea:GetTop(), page:GetBottom()
  if not (top and bottom) then page.rowGap = 18; return 12 end
  local room = top - bottom - 26                      -- the button row (22) plus a little air
  local n = math.max(4, math.min(ROWS, math.floor(room / 18)))
  -- spread the rows over the room that's left so there's no dead band above the buttons (18 to 21 apart)
  page.rowGap = math.max(18, math.min(21, room / n))
  return n
end
local STD_H = 510        -- one window height for every tab; only "Less" on Path collapses it
local SHOW_SMALL = 0     -- "Less" shows only the active step
local current = "catchup"

local function Tab(parent, key, text, x, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 70, 24); b:SetPoint("TOPLEFT", x, -30)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("CENTER"); b.text:SetText(text)
  b.line = b:CreateTexture(nil, "ARTWORK"); b.line:SetPoint("BOTTOMLEFT", 8, 0); b.line:SetPoint("BOTTOMRIGHT", -8, 0); b.line:SetHeight(2); b.line:SetColorTexture(S.AR, S.AG, S.AB, 1)
  b:SetScript("OnClick", function() S.UI_Tab(key) end)
  b.own = true
  tabs[key] = b
  return b
end
local tabOrder = {}   -- key -> index, for Blizzard's bottom tabs

function S.UI_Tab(key)
  current = key
  if builders[key] then local b = builders[key]; builders[key] = nil; b(pages[key]) end
  for k, b in pairs(tabs) do
    local on = (k == key)
    if rawget(b, "own") then
      b.text:SetTextColor(on and 1 or .56, on and 1 or .6, on and 1 or .7)
      if on then b.line:Show() else b.line:Hide() end
    end
    if pages[k] then if on then pages[k]:Show() else pages[k]:Hide() end end
  end
  if main and rawget(main, "Tabs") and tabOrder[key] then S.BlizzSelectTab(main, tabOrder[key]) end
  S.UI_Update()
  if S.GuideTab then S.Safe("tips", S.GuideTab, key) end
end
-- You walked into a new zone: the Catch-up tab follows, unless you picked a zone yourself.
function S.UI_ZoneChanged()
  local page = pages.catchup
  if page and not page.manual then page.follow = true; if current == "catchup" and main and main:IsShown() then S.UI_Update() end end
end
-- For the tour and tips (Guide.lua): the main window, a tab's page, the tab showing now.
function S.UI_Main() return main end
function S.UI_Page(key) return pages[key] end
function S.UI_CurrentTab() return current end

local function BuildPath(page)
  -- record bar
  local rb = Box(page); rb:SetPoint("TOPLEFT", 0, 0); rb:SetPoint("TOPRIGHT", 0, 0); rb:SetHeight(30)
  rb.dot = rb:CreateTexture(nil, "ARTWORK"); rb.dot:SetSize(10, 10); rb.dot:SetPoint("LEFT", 10, 0); rb.dot:SetTexture("Interface\\COMMON\\Indicator-Red")
  rb.text = rb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); rb.text:SetPoint("LEFT", rb.dot, "RIGHT", 7, 0)
  rb.meta = rb:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); rb.meta:SetPoint("LEFT", rb.text, "RIGHT", 8, 0); rb.meta:SetTextColor(.78, .8, .86)
  rb.btn = Button(rb, "Record", 70); rb.btn:SetPoint("RIGHT", -6, 0)
  rb.btn:SetScript("OnClick", function() if S.IsRecording() then S.RecordStop() else S.RecordStart() end end)
  rb.note = Button(rb, "Note", 46); rb.note:SetPoint("RIGHT", rb.btn, "LEFT", -4, 0); rb.note:Hide()
  rb.meta:SetPoint("RIGHT", rb.note, "LEFT", -6, 0); rb.meta:SetJustifyH("LEFT"); rb.meta:SetWordWrap(false)
  rb.note:SetScript("OnClick", function() S.UI_Prompt("Add a note", "Shows as a step for whoever follows this session.", "", "Add", function(text) if text ~= "" then S.RecordNote(text); msg("Noted.") end end) end)
  page.rec = rb

  page.follow = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.follow:SetPoint("TOPLEFT", rb, "BOTTOMLEFT", 4, -9); page.follow:SetTextColor(.56, .6, .7)
  page.chip = Pill(page); page.chip:SetPoint("RIGHT", rb, "BOTTOMRIGHT", 0, -15); page.chip:Hide()
  page.dist = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.dist:SetPoint("RIGHT", page.chip, "LEFT", -8, 0); page.dist:SetTextColor(.42, .46, .55)
  page.follow:SetPoint("RIGHT", page.dist, "LEFT", -8, 0); page.follow:SetJustifyH("LEFT"); page.follow:SetWordWrap(false)

  local card = Box(page); card:SetPoint("TOPLEFT", rb, "BOTTOMLEFT", 0, -28); card:SetPoint("TOPRIGHT", rb, "BOTTOMRIGHT", 0, -28); card:SetHeight(58)
  card:SetBackdropColor(.17, .21, .32, 1); card:SetBackdropBorderColor(.35, .5, .84, 1)
  card.accent = card:CreateTexture(nil, "ARTWORK"); card.accent:SetPoint("TOPLEFT", 1, -1); card.accent:SetPoint("BOTTOMLEFT", 1, 1); card.accent:SetWidth(3); card.accent:SetColorTexture(S.AR, S.AG, S.AB, 1)
  card.pill = Pill(card); card.pill:SetPoint("TOPLEFT", 12, -9)
  -- Done sits on the card (it acts on this step); Undo lives on the bottom row
  card.done = Button(card, "Done", 54); card.done:SetPoint("BOTTOMRIGHT", -8, 6)
  card.done:SetScript("OnClick", function() SterlingQuestDB.manual[S.CurrentIndex()] = true; S.Recalc(false) end)
  card.done:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Mark this step done"); GameTooltip:AddLine("For steps Sterling can't see finish. Undo puts it back.", 1, 1, 1, true); GameTooltip:Show() end)
  card.done:HookScript("OnLeave", function() GameTooltip:Hide() end)
  card.way = card:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); card.way:SetPoint("RIGHT", card, "RIGHT", -10, 0); card.way:SetPoint("TOP", card.pill, "TOP", 0, -1); card.way:SetTextColor(.72, .8, .96)
  card.q = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); card.q:SetPoint("LEFT", card.pill, "RIGHT", 8, 0); card.q:SetPoint("RIGHT", card.way, "LEFT", -8, 0); card.q:SetTextColor(S.TR, S.TG, S.TB); card.q:SetJustifyH("LEFT"); card.q:SetWordWrap(false)
  card.npc = card:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); card.npc:SetPoint("TOPLEFT", card.pill, "BOTTOMLEFT", 0, -7); card.npc:SetPoint("RIGHT", card.done, "LEFT", -8, 0); card.npc:SetJustifyH("LEFT"); card.npc:SetTextColor(.72, .76, .85); card.npc:SetWordWrap(false)
  page.card = card

  page.prog = page:CreateTexture(nil, "ARTWORK"); page.prog:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -6); page.prog:SetHeight(2); page.prog:SetColorTexture(S.AR, S.AG, S.AB, 1); page.prog:SetWidth(1)
  local progbg = page:CreateTexture(nil, "BACKGROUND"); progbg:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -6); progbg:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -6); progbg:SetHeight(3); progbg:SetColorTexture(S.Navy(.2, .23, .3))

  page.rows = {}
  -- wheel over the list scrolls through the whole path (done steps above, upcoming below)
  page.listArea = CreateFrame("Frame", nil, page); page.listArea:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -14); page.listArea:SetPoint("RIGHT", page, "RIGHT", 0, 0); page.listArea:SetHeight(ROWS * 18)
  page.listArea:EnableMouseWheel(true)
  page.sb = MiniScroll(page, function(off) page.top = off + 1; page.scrolled = true; S.UI_Update() end)
  page.sb:SetPoint("TOPRIGHT", page.listArea, "TOPRIGHT", 0, 0); page.sb:SetPoint("BOTTOMRIGHT", page.listArea, "BOTTOMRIGHT", 0, 0)
  page.listArea:SetScript("OnMouseWheel", function(_, delta)
    local maxRows = SterlingQuestDB.opts.expanded and pathRowsFit(page) or SHOW_SMALL
    if maxRows == 0 then return end
    local i = S.CurrentIndex()
    page.top = (page.top or (i + 1)) - delta * 3
    page.top = math.max(1, math.min(page.top, math.max(1, #S.steps - maxRows + 1)))
    page.scrolled = true
    S.UI_Update()
  end)
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, page); r:SetHeight(17)
    r:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 14, -16 - (i - 1) * 18); r:SetPoint("RIGHT", page, "RIGHT", -12, 0)
    r.dotl = r:CreateTexture(nil, "ARTWORK"); r.dotl:SetSize(7, 7); r.dotl:SetPoint("LEFT", -12, 0); r.dotl:SetTexture("Interface\\Buttons\\WHITE8x8"); r.dotl:SetVertexColor(.33, .38, .5, 1)
    r.pill = Pill(r); r.pill:SetPoint("LEFT", 0, 0); r.pill:SetScale(.85); r.pill.minW = 62   -- PICK UP, TURN IN, DO, TRAVEL... all one width
    r.text = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.text:SetPoint("LEFT", r.pill, "RIGHT", 8, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -40, 0); r.text:SetTextColor(.84, .86, .92); r.text:SetWordWrap(false); r.text:SetJustifyH("LEFT")   -- fills whatever the pill leaves (the joined PICK UP > TURN IN pill is wider)
    r.time = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.time:SetPoint("RIGHT", -4, 0); r.time:SetTextColor(.42, .46, .55)
    r:EnableMouse(true)
    r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, .06); r.hl:Hide()
    r.cur = r:CreateTexture(nil, "BACKGROUND"); r.cur:SetAllPoints(); r.cur:SetColorTexture(S.AR, S.AG, S.AB, .14); r.cur:Hide()
    r:SetScript("OnEnter", function(self)
      self.hl:Show()
      if self.step then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(S.StepLabel(self.step))
        if self.step.text and self.step.kind ~= "objective" then GameTooltip:AddLine(self.step.text, .8, .83, .9, true) end
        if self.done then GameTooltip:AddLine("Click: go back to this step (un-checks it and everything after).  Right-click: arrow here.", .5, .8, 1, true)
        elseif self.isCurrent then GameTooltip:AddLine("This is the current step.", .5, .8, 1, true)
        else GameTooltip:AddLine("Click: jump here (skips the steps before it).  Right-click: point the arrow here for a moment.", .5, .8, 1, true) end
        GameTooltip:Show()
      end
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnMouseUp", function(self, btn)
      if not self.step then return end
      if btn == "RightButton" then if self.step.x then S.SetWaypoint(self.step) end return end
      local target
      for k, st in ipairs(S.steps) do if st == self.step then target = k end end
      if not target then return end
      page.scrolled = false; page.top = nil
      if self.done then
        -- go back: forget check-offs from here on
        for k = target, #S.steps do SterlingQuestDB.manual[k] = nil end
        S.lastJump = nil
        S.Recalc(false)
        if S.CurrentIndex() ~= target then
          msg("Step " .. target .. " is already complete in your quest log, so it stays done. Arrow set there for now.")
          if self.step.x then S.SetWaypoint(self.step) end
        else msg("Back to step " .. target .. ".") end
        return
      end
      if self.isCurrent then return end
      -- jump: everything before this step counts as done
      S.lastJump = {}
      for k = 1, target - 1 do if not SterlingQuestDB.manual[k] and not S.StepSatisfied(S.steps[k], k) then SterlingQuestDB.manual[k] = true; S.lastJump[#S.lastJump + 1] = k end end
      S.Recalc(false); msg("Jumped to step " .. target .. ". Undo puts the skipped steps back.")
    end)
    page.rows[i] = r
  end
  local line = page:CreateTexture(nil, "BACKGROUND"); line:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 6, -12); line:SetWidth(2); line:SetHeight(ROWS * 18); line:SetColorTexture(S.Navy(.25, .3, .42))
  page.tlline = line

  page.b1 = card.done   -- Done lives on the card now
  -- Auto arrow first, where Done and Undo used to be: the arrow follows each next step by itself
  -- (same setting as Options > General > Guided arrow)
  page.auto = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate"); page.auto:SetSize(22, 22); page.auto:SetPoint("BOTTOMLEFT", -2, 0)
  page.auto.text = page.auto:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.auto.text:SetPoint("LEFT", page.auto, "RIGHT", 1, 0); page.auto.text:SetText("Auto arrow"); page.auto.text:SetTextColor(.84, .86, .92)
  page.auto.text:SetWidth(70); page.auto.text:SetJustifyH("LEFT"); page.auto.text:SetWordWrap(false)
  page.auto:SetScript("OnClick", function(self)
    SterlingQuestDB.opts.arrowopt = self:GetChecked() and true or false
    SterlingQuestDB.path = SterlingQuestDB.opts.arrowopt
    if SterlingQuestDB.path then local st = S.steps[S.CurrentIndex()]; if st then S.SetWaypoint(st) end else S.ClearWaypoint() end
    S.Recalc(false)
  end)
  page.auto:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Auto arrow"); GameTooltip:AddLine("On: the arrow moves to each next step by itself. Off: no arrow; click the /way on the card to place one when you want it.", 1, 1, 1, true); GameTooltip:Show() end)
  page.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.undo = Button(page, "Undo", 46); page.undo:SetPoint("BOTTOMLEFT", 94, 0)
  page.undo:SetScript("OnClick", function() SlashCmdList.STERLINGQUEST("undo") end)
  page.b2 = page.undo
  page.clear = Button(page, "Clear", 46); page.clear:SetPoint("LEFT", page.undo, "RIGHT", 4, 0)
  -- the /way on the card is a button too: one click puts the arrow on this step
  card.wayBtn = CreateFrame("Button", nil, card); card.wayBtn:SetAllPoints(card.way)
  card.wayBtn:SetScript("OnClick", function() local st = S.steps[S.CurrentIndex()]; if st and st.x then S.SetWaypoint(st); msg("Arrow set: " .. S.StepLabel(st)) end end)
  card.wayBtn:SetScript("OnEnter", function(self) card.way:SetTextColor(1, .93, .45); GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Click to put the arrow here"); GameTooltip:Show() end)
  card.wayBtn:SetScript("OnLeave", function() card.way:SetTextColor(.72, .8, .96); GameTooltip:Hide() end)
  page.clear:SetScript("OnClick", function()
    local what = S.catchupLabel or (S.FindSession(SterlingQuestDB.following) and ("following " .. S.FindSession(SterlingQuestDB.following).name)) or "this path"
    S.UI_Confirm("Clear the path?", "Stops " .. what .. " and removes the arrow. Your sessions and check-offs stay saved; you can start it again any time.", "Clear",
      function() S.StopFollowing(); msg("Path cleared."); S.UI_Update() end)
  end)
  page.b4 = Button(page, "Import", 54); page.b4:SetPoint("BOTTOMRIGHT", 0, 0)
  page.b4:SetScript("OnClick", function() S.UI_ShowImport() end)
  page.b3 = Button(page, "Map", 42); page.b3:SetPoint("RIGHT", page.b4, "LEFT", -4, 0)
  page.b3:SetScript("OnClick", function() S.MapToggle() end)
  page.more = Button(page, "More", 44); page.more:SetPoint("RIGHT", page.b3, "LEFT", -4, 0)
  page.scrollHint = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.scrollHint:SetPoint("BOTTOM", page.undo, "TOP", 0, 6); page.scrollHint:SetPoint("LEFT", 0, 0); page.scrollHint:SetJustifyH("LEFT"); page.scrollHint:SetTextColor(.42, .46, .55)
  page.more:SetScript("OnClick", function() SterlingQuestDB.opts.expanded = not SterlingQuestDB.opts.expanded; S.UI_Update() end)
  page.empty = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.empty:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -16); page.empty:SetWidth(330); page.empty:SetJustifyH("LEFT"); page.empty:SetTextColor(.56, .6, .7)
end

local SROWS = 7
local function BuildSessions(page)
  local top = CreateFrame("Frame", nil, page); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(26)
  page.recbtn = Button(top, "Record", 76); page.recbtn:SetPoint("LEFT", 0, 0)
  page.recbtn:SetScript("OnClick", function() if S.IsRecording() then S.RecordStop() else S.RecordStart() end end)
  page.recstate = top:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.recstate:SetPoint("LEFT", page.recbtn, "RIGHT", 8, 0); page.recstate:SetTextColor(.56, .6, .7)
  page.count = top:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.count:SetPoint("RIGHT", -4, 0); page.count:SetTextColor(.42, .46, .55)
  page.rows = {}; page.offset = 0
  -- the list scrolls with the mouse wheel and a slim bar once there are more sessions than rows
  page.listArea = CreateFrame("Frame", nil, page); page.listArea:SetPoint("TOPLEFT", 0, -32); page.listArea:SetPoint("RIGHT", 0, 0); page.listArea:SetHeight(SROWS * 50 - 4)
  page.listArea:EnableMouseWheel(true)
  page.listArea:SetScript("OnMouseWheel", function(_, d) page.offset = math.max(0, math.min((page.offset or 0) - d, #SterlingQuestDB.sessions - SROWS)); S.UI_Update() end)
  page.sb = MiniScroll(page, function(off) page.offset = off; S.UI_Update() end)
  page.sb:SetPoint("TOPRIGHT", page.listArea, "TOPRIGHT", 0, 0); page.sb:SetPoint("BOTTOMRIGHT", page.listArea, "BOTTOMRIGHT", 0, 0)
  for i = 1, SROWS do
    local r = Box(page); r:SetHeight(46)
    r:SetPoint("TOPLEFT", 0, -32 - (i - 1) * 50); r:SetPoint("RIGHT", -10, 0)
    r:EnableMouseWheel(true); r:SetScript("OnMouseWheel", function(_, d) page.listArea:GetScript("OnMouseWheel")(page.listArea, d) end)
    r:SetBackdropColor(1, 1, 1, .025); r:SetBackdropBorderColor(.2, .23, .32, 1)
    r.accent = r:CreateTexture(nil, "ARTWORK"); r.accent:SetPoint("TOPLEFT", 1, -1); r.accent:SetPoint("BOTTOMLEFT", 1, 1); r.accent:SetWidth(3)
    r.nm = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.nm:SetPoint("TOPLEFT", 12, -7); r.nm:SetTextColor(S.TR, S.TG, S.TB)
    r.meta = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.meta:SetPoint("TOPLEFT", r.nm, "BOTTOMLEFT", 0, -3); r.meta:SetTextColor(.56, .6, .7); r.meta:SetWidth(190); r.meta:SetJustifyH("LEFT"); r.meta:SetWordWrap(false)
    r.who = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.who:SetPoint("LEFT", r.nm, "RIGHT", 8, 0)
    r.b1 = Button(r, "Export", 56); r.b1:SetPoint("RIGHT", -34, 0)
    r.b2 = Button(r, ">", 26); r.b2:SetPoint("RIGHT", -6, 0)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self, btn)
      if btn == "RightButton" and self.sess then S.UI_SessionMenu(self.sess) end
    end)
    r:SetScript("OnEnter", function(self)
      if not self.sess then return end
      local sess = self.sess
      local c = S.SessionCounts(sess)
      local zones = {}
      for z in pairs(sess.zones or {}) do zones[#zones + 1] = z end
      table.sort(zones)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(sess.name, 1, 1, 1)
      GameTooltip:AddDoubleLine((sess.char or "?") .. (sess.imported and "  (received)" or "  (yours)"), S.Clock(sess.start) .. " - " .. S.Clock(sess.stop or time()), .72, .76, .85, .72, .76, .85)
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("|cff7ee2a2Turn-ins|r", c.turnin, 1, 1, 1, .49, .89, .64)
      GameTooltip:AddDoubleLine("|cff8ab8ffPick-ups|r", c.pickup, 1, 1, 1, S.AR, S.AG, S.AB)
      if c.skip > 0 then GameTooltip:AddDoubleLine("|cffff9b92Skipped|r", c.skip, 1, 1, 1, 1, .61, .57) end
      if c.dungeon > 0 then GameTooltip:AddDoubleLine("|cffff9b92Dungeon runs|r", c.dungeon, 1, 1, 1, 1, .61, .57) end
      if c.flight > 0 then GameTooltip:AddDoubleLine("|cffc3a8ffFlights|r", c.flight, 1, 1, 1, .76, .66, 1) end
      if sess.lvl0 and sess.lvl1 and sess.lvl1 > sess.lvl0 then GameTooltip:AddDoubleLine("|cff7ee2a2Levels|r", sess.lvl0 .. " -> " .. sess.lvl1, 1, 1, 1, .49, .89, .64) end
      if c.death > 0 then GameTooltip:AddDoubleLine("Deaths", c.death, .7, .74, .84, .7, .74, .84) end
      GameTooltip:AddDoubleLine("Played", S.Duration(sess), .7, .74, .84, .7, .74, .84)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(#zones > 0 and table.concat(zones, ", ") or "no zones recorded", .56, .6, .7, true)
      if sess.note then GameTooltip:AddLine(sess.note, .95, .77, .42, true) end
      GameTooltip:AddLine((c.ev or 0) .. " events, " .. (c.tr or 0) .. " trail points" .. (S.IsPacked(sess) and "  (packed; opens normally)" or ""), .45, .5, .6)
      GameTooltip:AddLine("Right-click: follow, map, export, send, compare, rename, delete", .5, .8, 1, true)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.rows[i] = r
  end
  page.hint = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.hint:SetPoint("BOTTOMLEFT", 4, 4); page.hint:SetTextColor(.42, .46, .55)
  page.hint:SetJustifyH("LEFT"); page.hint:SetWordWrap(false)
  page.hint:SetText("Right-click: rename, delete, more")
  page.imp = Button(page, "Import", 60); page.imp:SetPoint("BOTTOMRIGHT", 0, 0); page.imp:SetScript("OnClick", function() S.UI_ShowImport() end)
  page.rest = Button(page, "Restore", 64); page.rest:SetPoint("RIGHT", page.imp, "LEFT", -4, 0); page.rest:SetScript("OnClick", function() S.Restore() end)
  page.hint:SetPoint("RIGHT", page.rest, "LEFT", -6, 0)
  page.rest:SetScript("OnEnter", function(self)
    local t = SterlingQuestDB.trash and SterlingQuestDB.trash[1]
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Bring back \"" .. (t.name or "session") .. "\"", 1, 1, 1)
    GameTooltip:AddLine(#SterlingQuestDB.trash .. " deleted session" .. (#SterlingQuestDB.trash == 1 and "" or "s") .. " kept (last 5).", .56, .6, .7)
    GameTooltip:Show()
  end)
  page.rest:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildCompare(page)
  local sf = CreateFrame("ScrollFrame", "SterlingQuestDiffScroll", page, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -28); sf:SetPoint("BOTTOMRIGHT", -22, 28)
  page.who = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); page.who:SetPoint("TOPLEFT", 4, -4); page.who:SetTextColor(.9, .92, 1)
  local content = CreateFrame("Frame", nil, sf); content:SetSize(300, 10); sf:SetScrollChild(content)
  page.content = content; page.lines = {}
  local b = Button(page, "Ask for update", 100); b:SetPoint("BOTTOMLEFT", 0, 0)
  b:SetScript("OnClick", function() S.RequestPartner(); S.Broadcast(true, true); msg("Asked your partners for a fresh snapshot.") end)
  local b2 = Button(page, "Export log", 76); b2:SetPoint("LEFT", b, "RIGHT", 4, 0)
  b2:SetScript("OnClick", function() S.UI_ShowExport("log") end)
  local b3 = Button(page, "Everyone", 70); b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)
  b3:SetScript("OnClick", function() S.UI_Everyone() end)
  -- who to compare against
  page.pick = Dropdown(page, 120, function() return S.partner and S.PartnerLabel(S.partner.name or "?") or "nobody yet" end, function()
    local items = {}
    for _, p in ipairs(S.Partners()) do
      if S.snaps[p.name] then items[#items + 1] = { text = S.PartnerLabel(p.name), checked = S.partner and S.partner.name == p.name, func = function() S.SelectPartner(p.name); S.UI_Update() end } end
    end
    if #items == 0 then items[1] = { text = "Nobody synced yet", disabled = true } end
    return items
  end)
  page.pick:SetPoint("TOPRIGHT", 0, 0)
  page.who:SetPoint("RIGHT", page.pick, "LEFT", -8, 0); page.who:SetJustifyH("LEFT"); page.who:SetWordWrap(false)
  page.foot = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.foot:SetPoint("BOTTOMRIGHT", -4, 4); page.foot:SetTextColor(.42, .46, .55)
  page.foot:SetPoint("LEFT", b3, "RIGHT", 8, 0); page.foot:SetJustifyH("RIGHT"); page.foot:SetWordWrap(false)
end

local function Check(parent, label, key, default, y, onchange)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", 0, y); cb:SetSize(24, 24)
  cb.text = cb:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0); cb.text:SetText(label); cb.text:SetTextColor(.84, .86, .92)
  cb:SetChecked(S.Opt(key, default))
  cb:SetScript("OnClick", function(self) SterlingQuestDB.opts[key] = self:GetChecked() and true or false; if onchange then onchange() end end)
  return cb
end

local function ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 60 then return d .. "s ago" elseif d < 3600 then return math.floor(d / 60) .. " min ago" else return math.floor(d / 3600) .. "h " .. math.floor(d % 3600 / 60) .. "m ago" end
end

local function agoShort(t)
  if not t then return nil end
  local d = time() - t
  if d < 60 then return "just now" elseif d < 3600 then return math.floor(d / 60) .. "m ago" elseif d < 86400 then return math.floor(d / 3600) .. "h ago" else return math.floor(d / 86400) .. "d ago" end
end

-- Colour for a partner's face and name: their profile colour, else their class colour, else grey.
local function partnerRGB(name)
  local prof = S.profiles and S.profiles[name]
  if prof and prof.color then return S.ColorRGB(prof.color) end
  local cls = S.PartnerClass and S.PartnerClass(name)
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if c then return c.r, c.g, c.b end
  return .6, .64, .74
end

---------------------------------------------------------------------------
-- Your profile: how you look to partners. Opened from the "You" row on the Sync page.
---------------------------------------------------------------------------
local profWin
local function buildProfile()
  profWin = Window("SterlingQuestProfile", 340, 274, "Your profile")
  local page = CreateFrame("Frame", nil, profWin); page:SetPoint("TOPLEFT", 12, -38); page:SetPoint("BOTTOMRIGHT", -12, 12)
  local inset = S.Inset(profWin); if inset then inset:SetPoint("TOPLEFT", 6, -30); inset:SetPoint("BOTTOMRIGHT", -6, 6); page:SetFrameLevel(inset:GetFrameLevel() + 2) end
  local ui = profWin
  local y = 0
  -- Profile: how you appear on everyone's map
  local prof = S.Profile()
  local pt = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pt:SetPoint("TOPLEFT", 2, y); pt:SetWidth(310); pt:SetJustifyH("LEFT"); pt:SetTextColor(.6, .64, .74)
  pt:SetText("How you look to your partners: your name in their Sync list and status lines, and your face and colour on their map.")
  y = y - 34
  -- preview + name
  ui.preview = CreateFrame("Frame", nil, page); ui.preview:SetSize(30, 30); ui.preview:SetPoint("TOPLEFT", 6, y)
  ui.preview.edge = ui.preview:CreateTexture(nil, "BORDER"); ui.preview.edge:SetPoint("TOPLEFT", -2, 2); ui.preview.edge:SetPoint("BOTTOMRIGHT", 2, -2)
  ui.preview.back = ui.preview:CreateTexture(nil, "BORDER", nil, 1); ui.preview.back:SetAllPoints(); ui.preview.back:SetColorTexture(.05, .05, .08, 1)
  ui.preview.face = ui.preview:CreateTexture(nil, "ARTWORK"); ui.preview.face:SetPoint("TOPLEFT", 1, -1); ui.preview.face:SetPoint("BOTTOMRIGHT", -1, 1)
  local nl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); nl:SetPoint("LEFT", ui.preview, "RIGHT", 12, 6); nl:SetText("Display name"); nl:SetTextColor(.84, .86, .92)
  ui.nameBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); ui.nameBox:SetSize(150, 20); ui.nameBox:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 6, -2); ui.nameBox:SetAutoFocus(false); ui.nameBox:SetMaxLetters(16)
  ui.nameBox:SetText(prof.name or "")
  local function saveName() local v = ui.nameBox:GetText(); if v == "" then v = S.MyName() end; S.Profile().name = v; ui.nameBox:ClearFocus(); S.SendProfile(); S.UI_Update() end
  ui.nameBox:SetScript("OnEnterPressed", saveName); ui.nameBox:SetScript("OnEditFocusLost", saveName); ui.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  y = y - 40
  -- races: male faces on the first row, female on the second
  ui.raceBtns = {}
  for row, female in ipairs({ false, true }) do
    for i, race in ipairs(S.RACES) do
      local b = CreateFrame("Button", nil, page); b:SetSize(28, 28); b:SetPoint("TOPLEFT", 6 + (i - 1) * 34, y - (row - 1) * 34)
      b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2); b.sel:SetColorTexture(S.AR, S.AG, S.AB, 1)
      b.back = b:CreateTexture(nil, "BORDER"); b.back:SetAllPoints(); b.back:SetColorTexture(.05, .05, .08, 1)
      b.face = b:CreateTexture(nil, "ARTWORK"); b.face:SetPoint("TOPLEFT", 1, -1); b.face:SetPoint("BOTTOMRIGHT", -1, 1); S.SetFace(b.face, race, female)
      b.race, b.female = race, female
      b:SetScript("OnClick", function() local pr = S.Profile(); pr.race = race; pr.female = female or nil; S.SendProfile(); S.UI_Update() end)
      b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(S.RACE_NAME[race] .. (female and " (female)" or " (male)")); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      ui.raceBtns[#ui.raceBtns + 1] = b
    end
  end
  y = y - 68
  -- colours
  ui.colorBtns = {}
  for i, c in ipairs(S.COLORS) do
    local b = CreateFrame("Button", nil, page); b:SetSize(22, 18); b:SetPoint("TOPLEFT", 6 + (i - 1) * 30, y)
    b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2); b.sel:SetColorTexture(1, 1, 1, 1)
    b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetAllPoints(); b.sw:SetColorTexture(c.rgb[1], c.rgb[2], c.rgb[3], 1)
    b.key = c.key
    b:SetScript("OnClick", function() S.Profile().color = c.key; S.SendProfile(); S.UI_Update() end)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(c.name); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.colorBtns[i] = b
  end
  y = y - 30
  local done = Button(page, "Done", 70); done:SetPoint("BOTTOMRIGHT", 0, 0); local win = profWin; done:SetScript("OnClick", function() win:Hide() end)
  profWin:HookScript("OnShow", function() S.UI_Update() end)
  profWin:SetScale(S.Opt("scale", 1))
end
function S.UI_Profile()
  if not profWin then buildProfile() end
  profWin:Show(); S.UI_Update()
end
local function refreshProfile()
  if not (profWin and profWin:IsShown()) then return end
  local pg = profWin
  local prof = S.Profile()
  local r, g, b = S.ColorRGB(prof.color)
  for _, bt in ipairs(pg.raceBtns) do bt.sel:SetShown(bt.race == prof.race and bt.female == (prof.female and true or false)); bt.face:SetVertexColor(r, g, b) end
  for _, bt in ipairs(pg.colorBtns) do bt.sel:SetShown(bt.key == prof.color) end
  S.SetFace(pg.preview.face, prof.race, prof.female); pg.preview.face:SetVertexColor(r, g, b); pg.preview.edge:SetColorTexture(r, g, b, 1)
  if not pg.nameBox:HasFocus() then pg.nameBox:SetText(prof.name or "") end
end

-- Status light, Blizzard's friends-list icons: green online, grey offline, yellow "can't tell".
-- Falls back to a small flat dot if those files aren't on this client.
local STATUS = { online = { "Interface\\FriendsFrame\\StatusIcon-Online", .35, .8, .45 }, offline = { "Interface\\FriendsFrame\\StatusIcon-Offline", .45, .45, .48 },
                 unknown = { "Interface\\FriendsFrame\\StatusIcon-Away", .9, .75, .3 } }
local function SetStatus(tex, state)
  local d = STATUS[state] or STATUS.offline
  if S.TexOK(tex, d[1]) then tex:SetVertexColor(1, 1, 1, 1); tex:SetTexCoord(0, 1, 0, 1)
  else tex:SetTexture("Interface\\COMMON\\Indicator-Gray"); tex:SetVertexColor(d[2], d[3], d[4], .9) end
end

-- A box holding a link you can copy (click selects it all, Ctrl+C). Typing can't change it.
function S.UI_LinkBox(parent, text)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate"); eb:SetHeight(20); eb:SetAutoFocus(false)
  eb:SetFontObject(S.FONT_SMALL); eb:SetText(text); eb:SetCursorPosition(0)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text); self:HighlightText() end end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end
local function BuildSync(page)
  local y = 0
  -- status card
  local card = Box(page); card:SetPoint("TOPLEFT", 0, 0); card:SetPoint("TOPRIGHT", 0, 0); card:SetHeight(50)
  card:SetBackdropColor(1, 1, 1, .04); card:SetBackdropBorderColor(.23, .27, .37, 1)
  card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetSize(14, 14); card.dot:SetPoint("TOPLEFT", 10, -9); SetStatus(card.dot, "offline")
  card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); card.title:SetPoint("LEFT", card.dot, "RIGHT", 6, 0); card.title:SetTextColor(S.TR, S.TG, S.TB)
  card.refresh = Button(card, "Refresh", 64); card.refresh:SetPoint("TOPRIGHT", -8, -7)
  card.refresh:SetScript("OnClick", function() S.RefreshPartners() end)
  card.refresh:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Refresh", 1, 1, 1)
    GameTooltip:AddLine("Checks who's online and pings your partners. Their answers update this page.", .7, .74, .84, true)
    if S.lastRefresh then GameTooltip:AddLine("Last refresh: " .. date("%I:%M:%S %p", S.lastRefresh), .56, .6, .7) end
    GameTooltip:Show()
  end)
  card.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.sub = card:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); card.sub:SetPoint("TOPLEFT", 10, -30); card.sub:SetPoint("RIGHT", -8, 0); card.sub:SetJustifyH("LEFT"); card.sub:SetTextColor(.7, .74, .84); card.sub:SetWordWrap(false)
  page.card = card
  y = y - 56
  -- you: how you look to partners (no sync box or eye: you can't sync with yourself)
  local me = Box(page); me:SetPoint("TOPLEFT", 0, y); me:SetPoint("RIGHT", 0, 0); me:SetHeight(32)
  me:SetBackdropColor(1, 1, 1, .03); me:SetBackdropBorderColor(.23, .27, .37, 1)
  me.youTag = me:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); me.youTag:SetPoint("LEFT", 10, 0); me.youTag:SetText("You"); me.youTag:SetTextColor(S.LabelColor())
  me.faceBack = me:CreateTexture(nil, "BORDER"); me.faceBack:SetSize(20, 20); me.faceBack:SetPoint("LEFT", 52, 0); me.faceBack:SetColorTexture(.05, .05, .08, 1)
  me.faceEdge = me:CreateTexture(nil, "BACKGROUND", nil, 2); me.faceEdge:SetPoint("TOPLEFT", me.faceBack, -1, 1); me.faceEdge:SetPoint("BOTTOMRIGHT", me.faceBack, 1, -1)
  me.face = me:CreateTexture(nil, "ARTWORK"); me.face:SetPoint("TOPLEFT", me.faceBack, 1, -1); me.face:SetPoint("BOTTOMRIGHT", me.faceBack, -1, 1)
  me.name = me:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); me.name:SetPoint("TOPLEFT", 80, -4); me.name:SetPoint("RIGHT", -60, 0); me.name:SetJustifyH("LEFT"); me.name:SetWordWrap(false)
  me.st = me:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); me.st:SetPoint("TOPLEFT", 80, -17); me.st:SetPoint("RIGHT", -60, 0); me.st:SetJustifyH("LEFT"); me.st:SetTextColor(.6, .64, .74); me.st:SetWordWrap(false)
  me.edit = Button(me, "Edit", 48); me.edit:SetPoint("RIGHT", -6, 0); me.edit:SetScript("OnClick", function() S.UI_Profile() end)
  me:EnableMouse(true)
  me:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("How partners see you", 1, 1, 1)
    GameTooltip:AddLine("Your name in their Sync list and status lines, and your face and colour on their map. Edit to change it.", .7, .74, .84, true)
    GameTooltip:Show()
  end)
  me:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.me = me
  y = y - 38
  -- partners header with the Add button on the right
  -- two lines: "Partners 2/10", then the hint under it
  local pl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pl:SetPoint("TOPLEFT", 4, y + 1); pl:SetTextColor(.84, .86, .92)
  pl:SetText("Partners")
  page.plabel = pl
  page.add = Button(page, "+ Add", 58); page.add:SetPoint("TOPRIGHT", 0, y - 1)
  pl:SetPoint("RIGHT", page.add, "LEFT", -6, 0); pl:SetJustifyH("LEFT"); pl:SetWordWrap(false)   -- never runs under the button
  local ph = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); ph:SetPoint("TOPLEFT", 4, y - 12); ph:SetPoint("RIGHT", page.add, "LEFT", -6, 0)
  ph:SetJustifyH("LEFT"); ph:SetWordWrap(false); ph:SetTextColor(.54, .58, .66)
  -- icons instead of words, so it fits beside + Add
  ph:SetText("|TInterface\\AddOns\\Sterling\\Media\\star:11:11:0:0:32:32:0:32:0:32:255:209:64|t favourite   |TInterface\\AddOns\\Sterling\\Media\\eye:11:11|t tooltips   right-click: more")
  page.phint = ph
  page.add:SetScript("OnClick", function() S.UI_AddPartner() end)
  y = y - 26
  -- partners list in a box; four rows show, wheel for the rest
  local ROWH = 30
  page.rows = {}; page.VISIBLE = 6; page.offset = 0
  page.listBox = Box(page); page.listBox:SetPoint("TOPLEFT", 0, y); page.listBox:SetPoint("RIGHT", 0, 0); page.listBox:SetHeight(page.VISIBLE * ROWH + 4)
  page.listBox:SetBackdropColor(1, 1, 1, .025); page.listBox:SetBackdropBorderColor(.23, .27, .37, 1)
  page.rowsTop = -2
  page.listBox:EnableMouseWheel(true)
  page.listBox:SetScript("OnMouseWheel", function(_, delta)
    page.offset = math.max(0, math.min(page.offset - delta, #S.Partners() - page.VISIBLE))
    S.UI_Update()
  end)
  page.empty = page.listBox:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.empty:SetPoint("CENTER"); page.empty:SetWidth(300); page.empty:SetTextColor(.5, .55, .65)
  page.empty:SetText("No partners yet. Click + Add and enter a friend's character name.")
  page.sb = MiniScroll(page.listBox, function(off) page.offset = off; S.UI_Update() end)
  page.sb:SetPoint("TOPRIGHT", page.listBox, "TOPRIGHT", -1, -2); page.sb:SetPoint("BOTTOMRIGHT", page.listBox, "BOTTOMRIGHT", -1, 2)
  page.more = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.more:SetPoint("TOPRIGHT", page.listBox, "BOTTOMRIGHT", -2, -1); page.more:SetTextColor(.5, .55, .65)   -- under the list, clear of + Add
  page.Row = function(i)
    local r = page.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, page.listBox); r:SetHeight(ROWH); r:SetPoint("LEFT", 2, 0); r:SetPoint("RIGHT", -8, 0)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(S.AR, S.AG, S.AB, .1); r.sel:Hide()
    r.line = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.line:SetPoint("BOTTOMLEFT", 4, 0); r.line:SetPoint("BOTTOMRIGHT", -4, 0); r.line:SetHeight(1); r.line:SetColorTexture(1, 1, 1, .06)
    -- eye: show in tooltips and the quest log (sync on/off lives in the right-click menu)
    r.eye = CreateFrame("Button", nil, r); r.eye:SetSize(18, 18); r.eye:SetPoint("LEFT", 6, 0)
    r.eye.tex = r.eye:CreateTexture(nil, "ARTWORK"); r.eye.tex:SetAllPoints()
    r.eye:SetScript("OnClick", function()
      if not r.p then return end
      r.p.show = (r.p.show == false) and true or false
      if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end
      S.UI_Update()
    end)
    r.eye:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Show in tooltips and the quest log", 1, 1, 1); GameTooltip:AddLine((r.p and S.PartnerShown(r.p)) and "On. Click to hide their status lines." or "Off. Click to show their status lines.", .7, .74, .84, true); GameTooltip:Show() end)
    r.eye:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- face, softly tinted with their colour, with a thin outline in it
    r.faceBack = r:CreateTexture(nil, "BORDER"); r.faceBack:SetSize(22, 22); r.faceBack:SetPoint("LEFT", 30, 0); r.faceBack:SetColorTexture(.05, .05, .08, 1)
    r.face = r:CreateTexture(nil, "ARTWORK"); r.face:SetPoint("TOPLEFT", r.faceBack, 1, -1); r.face:SetPoint("BOTTOMRIGHT", r.faceBack, -1, 1)
    r.faceEdge = r:CreateTexture(nil, "BACKGROUND", nil, 2); r.faceEdge:SetPoint("TOPLEFT", r.faceBack, -1, 1); r.faceEdge:SetPoint("BOTTOMRIGHT", r.faceBack, 1, -1)
    -- star: favourite (up to 5; favourites sit on top here and in the Companion app)
    r.star = CreateFrame("Button", nil, r); r.star:SetSize(13, 13); r.star:SetFrameLevel(r:GetFrameLevel() + 3)
    r.star:SetPoint("CENTER", r.faceBack, "TOPLEFT", 1, -1)   -- a small badge on the face's corner
    r.star.tex = r.star:CreateTexture(nil, "ARTWORK"); r.star.tex:SetAllPoints()
    if not S.TexOK(r.star.tex, "Interface\\AddOns\\Sterling\\Media\\star") then pcall(r.star.tex.SetAtlas, r.star.tex, "PetJournal-FavoritesIcon") end
    r.star:SetScript("OnClick", function()
      if not r.p then return end
      local ok, why = S.ToggleFav(r.p)
      if not ok and why == "noid" then S.msg("Favourites need one live sync with " .. S.PartnerLabel(r.p.name) .. " first (Sterling 0.2.38 or newer on their side).") end
      S.UI_Update()
    end)
    r.star:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local fav = r.p and S.IsFav(r.p)
      GameTooltip:AddLine(fav and "Favourite" or "Add to favourites", 1, 1, 1)
      if not (r.p and S.ValidGUID(r.p.guid)) then GameTooltip:AddLine("Needs one live sync with them first.", .95, .77, .42, true)
      elseif fav then GameTooltip:AddLine("Shown on top. Click to remove.", .7, .74, .84, true)
      elseif #S.Favs() >= S.MAX_FAVS then GameTooltip:AddLine("You can favourite up to " .. S.MAX_FAVS .. " partners.", .95, .77, .42, true)
      else GameTooltip:AddLine("Favourites show on top, here and in the Companion app.", .7, .74, .84, true) end
      GameTooltip:Show()
    end)
    r.star:SetScript("OnLeave", function() GameTooltip:Hide(); r.paintStar() end)
    -- gold when a favourite; otherwise only shown (faint) while the row is under the mouse
    r.paintStar = function()
      local p = r.p
      if not p then r.star:Hide() return end
      local hover = r:IsMouseOver()
      local fav = S.IsFav(p)
      -- a favourite's star sits in front of their name; otherwise it's a faint badge on the face, on hover
      r.star:ClearAllPoints()
      if fav then r.star:SetSize(11, 11); r.star:SetPoint("TOPLEFT", r, "TOPLEFT", 58, -3)
      else r.star:SetSize(13, 13); r.star:SetPoint("CENTER", r.faceBack, "TOPLEFT", 1, -1) end
      if r.name then r.name:SetPoint("TOPLEFT", fav and 72 or 58, -3) end
      if fav then r.star.tex:SetVertexColor(1, .82, .25, 1); r.star:Show()
      elseif hover then
        if S.ValidGUID(p.guid) then r.star.tex:SetVertexColor(.8, .82, .88, .8) else r.star.tex:SetVertexColor(.5, .5, .55, .4) end
        r.star:Show()
      else r.star:Hide() end
    end
    -- right column: status word on top, sync age (or "Sync disabled") under it
    r.stat = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.stat:SetPoint("TOPRIGHT", -4, -3); r.stat:SetJustifyH("RIGHT"); r.stat:SetWordWrap(false)
    r.last = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.last:SetPoint("TOPRIGHT", -4, -16); r.last:SetJustifyH("RIGHT"); r.last:SetWordWrap(false)
    -- left column: name, then character · level · version
    -- their Sterling version, just left of the status word (amber "Outdated" / red when they can't sync)
    r.ver = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.ver:SetPoint("TOPRIGHT", r.stat, "TOPLEFT", -8, 0); r.ver:SetJustifyH("RIGHT"); r.ver:SetWordWrap(false)
    r.name = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.name:SetPoint("TOPLEFT", 58, -3); r.name:SetPoint("RIGHT", r.ver, "LEFT", -8, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.st = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.st:SetPoint("TOPLEFT", 58, -16); r.st:SetPoint("RIGHT", r.last, "LEFT", -8, 0); r.st:SetJustifyH("LEFT"); r.st:SetTextColor(.6, .64, .74); r.st:SetWordWrap(false)
    -- click: select; right-click: menu (sync on/off, compare, details...)
    r.hit = CreateFrame("Button", nil, r); r.hit:SetPoint("TOPLEFT", 26, 0); r.hit:SetPoint("BOTTOMRIGHT", 0, 0)
    r.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hit:SetScript("OnClick", function(_, btn)
      if not r.p then return end
      if btn == "RightButton" then S.UI_PartnerMenu(r.p.name) return end
      page.selected = r.p.name; S.UI_Update()
    end)
    r.hit:SetScript("OnEnter", function(self) r.sel:SetAlpha(.6); r.sel:Show(); r.paintStar(); if r.p then S.UI_PartnerTooltip(self, r.p, r.cantTell) end end)
    r.hit:SetScript("OnLeave", function() r.sel:SetAlpha(1); if page.selected ~= (r.p and r.p.name) then r.sel:Hide() end; GameTooltip:Hide(); r.paintStar() end)
    page.rows[i] = r
    return r
  end
  y = y - (page.VISIBLE * ROWH + 4) - 10
  -- this session
  local st = CreateFrame("Frame", nil, page); st:SetPoint("TOPLEFT", 0, y); st:SetPoint("RIGHT", 0, 0); st:SetHeight(96)
  page.stats = st
  st.title = st:CreateFontString(nil, "OVERLAY", "GameFontNormal"); st.title:SetPoint("TOPLEFT", 4, 0); st.title:SetTextColor(.96, .97, 1)
  st.title:SetText("This session  |cff8a93a8since login or reload|r")
  page.v = {}
  local function cell(label, col, row)
    local x = col == 1 and 4 or 176
    local yy = -20 - (row - 1) * 16
    local l = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetPoint("TOPLEFT", x, yy); l:SetText(label); l:SetTextColor(S.LabelColor())
    local v = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); v:SetPoint("TOPLEFT", x + 62, yy); v:SetPoint("RIGHT", col == 1 and -174 or -4, 0); v:SetJustifyH("LEFT"); v:SetTextColor(.9, .92, 1); v:SetWordWrap(false)
    return v
  end
  page.v.syncs = cell("Syncs", 1, 1); page.v.changes = cell("Changes", 2, 1)
  page.v.resent = cell("Resent", 1, 2); page.v.msgs = cell("Messages", 2, 2)
  local ll = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); ll:SetPoint("TOPLEFT", 4, -52); ll:SetText("Last"); ll:SetTextColor(S.LabelColor())
  page.v.last = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.v.last:SetPoint("TOPLEFT", 66, -52); page.v.last:SetPoint("RIGHT", -4, 0); page.v.last:SetJustifyH("LEFT"); page.v.last:SetWordWrap(false)
  -- the Companion app (only when its companion add-on is installed)
  page.appL = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.appL:SetPoint("TOPLEFT", 4, -67); page.appL:SetText("App"); page.appL:SetTextColor(S.LabelColor())
  page.v.app = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.v.app:SetPoint("TOPLEFT", 66, -67); page.v.app:SetPoint("RIGHT", -4, 0); page.v.app:SetJustifyH("LEFT"); page.v.app:SetWordWrap(false)
  -- the app is installed but its helper add-on isn't running (a new add-on needs a full game restart)
  page.appWarn = st:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.appWarn:SetPoint("TOPLEFT", 4, -67); page.appWarn:SetPoint("RIGHT", -4, 0); page.appWarn:SetJustifyH("LEFT"); page.appWarn:SetJustifyV("TOP"); page.appWarn:SetWordWrap(true); page.appWarn:SetTextColor(.95, .77, .42); page.appWarn:Hide()
  page.progBg = st:CreateTexture(nil, "ARTWORK"); page.progBg:SetPoint("TOPLEFT", page.v.last, "BOTTOMLEFT", 0, -1); page.progBg:SetPoint("RIGHT", -4, 0); page.progBg:SetHeight(2); page.progBg:SetColorTexture(.2, .18, .14, 1); page.progBg:Hide()
  page.prog = st:CreateTexture(nil, "OVERLAY"); page.prog:SetPoint("TOPLEFT", page.progBg, "TOPLEFT", 0, 0); page.prog:SetHeight(2); page.prog:SetColorTexture(.49, .89, .64, 1); page.prog:Hide()
  -- Sync all at the bottom
  page.syncAll = Button(page, "Sync all", 100); page.syncAll:SetPoint("BOTTOM", 0, 0)   -- same baseline as the other tabs' bottom buttons
  page.syncAll:SetScript("OnClick", function(self)
    S.ShowMenu({
      { text = "Sync with everyone online", isTitle = true },
      { text = "Quick  (send my changes, ask for theirs)", func = function() S.SyncWith(nil, "quick") end },
      { text = "Send mine  (my changes only)", func = function() S.SyncWith(nil, "send") end },
      { text = "Get theirs  (ask for their changes)", func = function() S.SyncWith(nil, "receive") end },
      { text = "Full from the start  (both ways)", func = function() S.SyncWith(nil, "full") end },
    }, self)
  end)
  page.autoNote = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.autoNote:SetPoint("BOTTOMLEFT", 4, 26); page.autoNote:SetPoint("RIGHT", -4, 0); page.autoNote:SetJustifyH("LEFT"); page.autoNote:SetJustifyV("BOTTOM"); page.autoNote:SetTextColor(.5, .55, .65); page.autoNote:SetWordWrap(true)
end

-- Hover card for a partner: every name they go by, plus their addon version.
function S.UI_PartnerTooltip(owner, p, attention)
  local prof = S.profiles and S.profiles[p.name]
  local nick = S.Nickname(p.name)
  local sn = S.snaps[p.name]
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(S.PartnerLabel(p.name), 1, 1, 1)
  GameTooltip:AddDoubleLine("Character", p.name, .56, .6, .7, .9, .92, 1)
  do
    local on, how = S.PartnerStatus(p.name)
    local txt = on and (({ addon = "online, Sterling answering", group = "online, in your group", friend = "online (friends list)", guild = "online (guild)" })[how] or "online") or (how and "offline" or "can't tell (not a friend or guildmate)")
    GameTooltip:AddDoubleLine("Status", txt, .56, .6, .7, on and .49 or 1, on and .89 or .61, on and .64 or .57)
  end
  GameTooltip:AddDoubleLine("Their chosen name", (prof and prof.name and prof.name ~= "" and prof.name) or "none sent", .56, .6, .7, .9, .92, 1)
  GameTooltip:AddDoubleLine("Your nickname", nick or "none", .56, .6, .7, nick and .54 or .6, nick and .72 or .64, nick and 1 or .74)
  local vs, vwho, ver = S.VersionState(p.name)
  local vr, vg, vb = .9, .92, 1
  if vs == "nosync" then vr, vg, vb = 1, .61, .57 elseif vs == "older" or vs == "newer" then vr, vg, vb = .95, .77, .42 end
  GameTooltip:AddDoubleLine("Sterling version", ver and ("v" .. ver) or "not known yet", .56, .6, .7, vr, vg, vb)
  if vs == "nosync" then
    GameTooltip:AddLine(S.Mark("bad") .. "Can't sync: update needed. " .. (vwho == "they" and "Their copy is too old to talk to yours (v" .. tostring(S.ADDON_VER) .. "). Have them update in WowUp, or send them your zip." or "Their copy is newer than yours. Update Sterling in WowUp, or get their zip."), 1, .61, .57, true)
  elseif vs == "older" then
    GameTooltip:AddLine(S.Mark("warn") .. "Outdated: they're on an older version than you (v" .. tostring(S.ADDON_VER) .. "). Sync still works; newer features may not until they update.", .95, .77, .42, true)
  elseif vs == "newer" then
    GameTooltip:AddLine(S.Mark("warn") .. "They're on a newer version than you. Sync still works; update Sterling to match.", .95, .77, .42, true)
  end
  do
    local ks = S.KeyState(p.name)
    GameTooltip:AddDoubleLine("Offline sync", ks == "signed" and "ready (keys swapped)" or "needs one live sync", .56, .6, .7, ks == "signed" and .49 or .95, ks == "signed" and .89 or .77, ks == "signed" and .64 or .42)
  end
  if S.AppPresent and S.AppPresent() then
    local prob = S.AppProblem and S.AppProblem(p.name)
    local paired = p.guid and S.AppPairKey and S.AppPairKey(p.guid)
    local txt, r, g, b = "not paired", .6, .64, .74
    if prob then txt, r, g, b = "missing key, resync", .95, .77, .42
    elseif paired then txt, r, g, b = "paired", .49, .89, .64
    elseif type(p.app) == "string" then txt, r, g, b = "they have it (v" .. p.app .. "), pairs when you're both next online", .95, .77, .42
    elseif p.app == false then txt, r, g, b = "they don't have it yet", .95, .48, .45 end
    GameTooltip:AddDoubleLine("Companion app", txt, .56, .6, .7, r, g, b)
    if not prob and not paired and p.app == false then GameTooltip:AddLine(S.NOAPP_TIP, .7, .74, .84, true) end
    if prob then GameTooltip:AddLine("The Companion app no longer has a key for you two (one of you reinstalled, or the pairing ended). Pair again in the app with a new code, then sync.", .7, .74, .84, true) end
  end
  if sn and sn.level then GameTooltip:AddDoubleLine("Level", tostring(sn.level), .56, .6, .7, .9, .92, 1) end
  local ls = S.LastSynced(p.name)
  GameTooltip:AddDoubleLine("Last synced", ls and (agoShort(ls) .. "  (" .. date("%m/%d %I:%M %p", ls) .. ")") or "never", .56, .6, .7, .9, .92, 1)
  if attention then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Can't tell if " .. S.PartnerLabel(p.name) .. " is online.", .95, .77, .42, true)
    GameTooltip:AddLine("They're not on your friends list, in your guild or in your group, so the game won't say. Add them as a friend in game and the light turns green when they log in. Sync still works if they're online.", .7, .74, .84, true)
  end
  GameTooltip:AddLine("Right-click for sync, compare, details and more.", .42, .46, .55)
  GameTooltip:Show()
end

function S.UI_SetNicknamePrompt(name)
  S.UI_Prompt("Nickname for " .. name, "Only you see this. It replaces their name everywhere in Sterling on your screen. Leave empty to use the name they chose.", S.Nickname(name) or "", "Save",
    function(text) S.SetNickname(name, text); S.UI_Update() end)
end

function S.UI_PartnerMenu(name)
  local p = S.FindPartner(name)
  local label = S.PartnerLabel(name)
  local inGrp = (UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name))
  local menu = {
    { text = label .. (label ~= name and ("  |cff8a93a8" .. name .. "|r") or ""), isTitle = true },
    { text = "Sync", menuList = {
      { text = "Quick  (send my changes, ask for theirs)", func = function() S.SyncWith(name, "quick") end },
      { text = "Send mine  (my changes only)", func = function() S.SyncWith(name, "send") end },
      { text = "Get theirs  (ask for their changes)", func = function() S.SyncWith(name, "receive") end },
      { text = "Full from the start  (both ways)", func = function() S.SyncWith(name, "full") end },
    } },
    { text = "Offline sync...", func = function() S.UI_Offline(name) end },
    { text = "Compare", disabled = S.snaps[name] == nil, func = function() S.UI_Compare(name) end },
    { text = "Catch up to them", disabled = S.snaps[name] == nil or not S.Opt("catchupTab", true), func = function() S.catchupWho = name; S.UI_Tab("catchup") end },
    { text = "Quest sharing...", disabled = not inGrp, func = function() if S.UI_ShareWindow then S.UI_ShareWindow(name) end end },
    { text = "Show detailed info", func = function() S.UI_PartnerInfo(name) end },
    { text = "Show in tooltips and log", checked = p and S.PartnerShown(p), func = function() if p then p.show = (p.show == false) and true or false; if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end; S.UI_Update() end end },
    { text = "Sync with " .. label, checked = p and p.on, func = function() if p then p.on = not p.on; if p.on and S.PartnerOnline(p.name) then S.RequestPartner(p.name); S.ScheduleBroadcast() end; S.UI_Update() end end },
    { text = (p and S.IsFav(p)) and "Remove from favourites" or "Add to favourites", disabled = not (p and S.ValidGUID(p.guid)) or (not S.IsFav(p) and #S.Favs() >= S.MAX_FAVS), func = function() if p then S.ToggleFav(p) end end },
    { text = "Set nickname...", func = function() S.UI_SetNicknamePrompt(name) end },
    { text = "Clear nickname", disabled = S.Nickname(name) == nil, func = function() S.SetNickname(name, nil); S.UI_Update() end },
    { text = "Remove partner", danger = true, func = function() S.RemovePartner(name); S.UI_Update() end },
  }
  S.ShowMenu(menu, "cursor")
end

local function UpdateSync(page)
  local st = S.sync or {}
  do -- the You row
    local me, prof = page.me, S.Profile()
    local r, g, b = S.ColorRGB(prof.color)
    S.SetFace(me.face, prof.race, prof.female); me.face:SetVertexColor(.55 + .45 * r, .55 + .45 * g, .55 + .45 * b); me.faceEdge:SetColorTexture(r, g, b, .9)
    local nm = prof.name and prof.name ~= "" and prof.name or S.MyName()
    me.name:SetText(nm); me.name:SetTextColor(.35 + .65 * r, .35 + .65 * g, .35 + .65 * b)
    me.st:SetText(S.MyName() .. " · lvl " .. ((S.MyLevel and S.MyLevel()) or UnitLevel("player") or "?") .. " · v" .. tostring(S.ADDON_VER) .. " · " .. (S.RACE_NAME and S.RACE_NAME[prof.race] or prof.race or ""))
  end
  local partners = S.PartnersSorted()
  local c = page.card
  local online, enabled = 0, 0
  for _, p in ipairs(partners) do if p.on then enabled = enabled + 1; if S.PartnerOnline(p.name) then online = online + 1 end end end
  local autoOn = S.Opt("autoSync", true) and SterlingQuestDB.sync
  if #partners == 0 then
    SetStatus(c.dot, "offline"); c.title:SetText("No partners yet")
    c.sub:SetText("Click + Add and enter a friend's character name.")
  elseif online > 0 then
    SetStatus(c.dot, "online"); c.title:SetText(online .. " of " .. enabled .. " online")
    c.sub:SetText(not SterlingQuestDB.sync and "Live sync is off (Options). Nothing is sent." or (autoOn and "Live sync and auto sync are on." or "Live sync on. Changes go out as they happen."))
  else
    SetStatus(c.dot, "offline"); c.title:SetText("Everyone offline")
    c.sub:SetText(enabled > 0 and "Nothing is sent while they're away." or "All partners are switched off.")
  end
  -- rows: a window of VISIBLE partners starting at page.offset
  for _, r in ipairs(page.rows) do r:Hide() end
  page.offset = math.max(0, math.min(page.offset or 0, math.max(0, #partners - page.VISIBLE)))
  page.empty:SetShown(#partners == 0)
  local y = page.rowsTop
  local shownRows = 0
  for i = page.offset + 1, math.min(#partners, page.offset + page.VISIBLE) do
    local p = partners[i]
    shownRows = shownRows + 1
    local r = page.Row(shownRows); r.p = p
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", page.listBox, "TOPLEFT", 2, y); r:SetPoint("RIGHT", page.listBox, "RIGHT", -8, 0)
    local shown = S.PartnerShown(p)
    r.eye.tex:SetTexture("Interface\\AddOns\\Sterling\\Media\\" .. (shown and "eye" or "eye-off"))
    r.eye.tex:SetVertexColor(shown and 1 or .5, shown and 1 or .55, shown and 1 or .65, 1)
    local on, how = S.PartnerStatus(p.name)
    local sn = S.snaps[p.name]
    local cr, cg, cb = partnerRGB(p.name)
    local prof = S.profiles and S.profiles[p.name]
    -- face: a soft tint (their colour mixed toward white) so the portrait still reads; dimmed and grey when offline
    S.SetFace(r.face, prof and prof.race or "Troll", prof and prof.female)
    local tr, tg, tb = .55 + .45 * cr, .55 + .45 * cg, .55 + .45 * cb
    r.face:SetVertexColor(tr, tg, tb); r.face:SetDesaturated(not on); r.face:SetAlpha(on and 1 or .55)
    r.faceEdge:SetColorTexture(cr, cg, cb, on and .9 or .35)
    r.paintStar()
    r.name:SetText(S.PartnerLabel(p.name) .. (S.Nickname(p.name) and " |cff8a93a8*|r" or ""))
    if p.on then r.name:SetTextColor(.35 + .65 * cr, .35 + .65 * cg, .35 + .65 * cb) else r.name:SetTextColor(.6, .62, .7) end
    -- version beside the status word; second line: level, then character
    local vs, _, ver = S.VersionState(p.name)
    if vs == "nosync" then r.ver:SetText(S.Mark("bad") .. "Update needed"); r.ver:SetTextColor(1, .61, .57)
    elseif vs == "older" then r.ver:SetText(S.Mark("warn") .. "Outdated v" .. ver); r.ver:SetTextColor(.95, .77, .42)
    elseif vs == "newer" then r.ver:SetText("v" .. ver .. " (newer)"); r.ver:SetTextColor(.95, .77, .42)
    elseif ver then r.ver:SetText("v" .. ver); r.ver:SetTextColor(.6, .64, .74)
    else r.ver:SetText("") end
    local bits = {}
    if sn and sn.level then bits[#bits + 1] = "lvl " .. sn.level end
    if S.PartnerLabel(p.name) ~= p.name then bits[#bits + 1] = p.name end
    r.st:SetText(table.concat(bits, " · "))
    -- status word
    r.cantTell = not on and not how
    if on then r.stat:SetText(S.Mark("good") .. "Online"); r.stat:SetTextColor(.44, .84, .54)
    elseif how then r.stat:SetText("Offline"); r.stat:SetTextColor(.55, .53, .48)
    else r.stat:SetText(S.Mark("warn") .. "Can't tell"); r.stat:SetTextColor(.91, .72, .35) end
    -- sync state, worded like the Companion app (when they last synced is on the hover card)
    local _, stxt, sr, sg, sb2 = S.PartnerSyncState(p.name)
    r.last:SetText(stxt or ""); r.last:SetTextColor(sr or .55, sg or .53, sb2 or .48)
    r.sel:SetShown(page.selected == p.name); r.sel:SetAlpha(1)
    r.line:SetShown(shownRows < page.VISIBLE)
    r:Show()
    y = y - 30
  end
  local above, below = page.offset, #partners - (page.offset + shownRows)
  page.more:SetText((above > 0 and ("^ " .. above .. "  ") or "") .. (below > 0 and (below .. " more v") or ""))
  page.sb:Set(page.offset, page.VISIBLE, #partners)
  -- this session
  local v = page.v
  local sIn, sOut, cIn, cOut, mIn, mOut = 0, 0, 0, 0, st.recv or 0, st.sent or 0
  for _, p in ipairs(partners) do
    local ss = S.SessionStat(p.name)
    sIn = sIn + (ss.snapsIn or 0); sOut = sOut + (ss.snapsOut or 0); cIn = cIn + (ss.deltasIn or 0); cOut = cOut + (ss.deltasOut or 0)
  end
  v.syncs:SetText(sIn .. " in, " .. sOut .. " out")
  v.changes:SetText(cIn .. " in, " .. cOut .. " out")
  v.resent:SetText(tostring(st.partsResent or 0) .. (st.throttled and st.throttled > 0 and ("  |cff8a93a8(" .. st.throttled .. " refused)|r") or ""))
  v.msgs:SetText(mOut .. " out, " .. mIn .. " in")
  do
    local n = S.FoundNewCount and S.FoundNewCount() or 0
    page.add:SetText(n > 0 and ("+ Add  |cffffd100" .. n .. "|r") or "+ Add"); page.add:SetWidth(n > 0 and 72 or 58)
    page.plabel:SetText("Partners " .. #partners .. "/" .. S.MAX_PARTNERS)
  end
  local le = st.lastEvent
  local waiting
  for name, p in pairs(S.pending or {}) do waiting = (p.mode == "full" and "Full sync" or (p.auto and "Auto sync" or "Sync")) .. " with " .. S.PartnerLabel(name) end
  -- live progress: parts of a log coming in or going out, as a percentage plus a thin bar
  local pr = st.prog
  local live = pr and (GetTime() - pr.t) < 6 and pr.got < pr.n
  if live then
    local pct = math.floor(pr.got / pr.n * 100)
    local who = pr.who == "group" and "your group" or S.PartnerLabel(pr.who)
    v.last:SetText("|cfff3c56b" .. (pr.dir == "in" and ("Receiving " .. who .. "'s log") or ("Sending your log to " .. who)) .. "  " .. pct .. "%|r  |cff8a93a8(" .. pr.got .. " of " .. pr.n .. ")|r")
    page.progBg:Show(); page.prog:Show(); page.prog:SetWidth(math.max(1, (page.progBg:GetWidth() or 200) * pr.got / pr.n))
  else
    page.progBg:Hide(); page.prog:Hide()
  end
  if live then
  elseif waiting then v.last:SetText("|cfff3c56b" .. waiting .. " running...|r")
  elseif le then
    local good = le.text:find("complete") or le.text:find("up to date")
    v.last:SetText("|cff8a93a8" .. date("%I:%M", le.at) .. "|r  " .. (good and "|cff7ee2a2" or "|cffd6dbe8") .. le.text .. "|r")
  else v.last:SetText("|cff8a93a8nothing yet this session|r") end
  do
    local a = S.app or {}
    local present = S.AppPresent and S.AppPresent()
    page.appL:SetShown(present); page.v.app:SetShown(present)
    local missing = not present and S.AppAddonMissing and S.AppAddonMissing()
    page.appWarn:SetShown(missing and true or false)
    if missing then page.appWarn:SetText(S.Mark("warn") .. S.APP_ADDON_MISSING) end
    if present then
      local t
      if not a.written or a.written == 0 then t = "|cff8a93a8Waiting for the Companion app|r"
      else
        local nprob = 0
        for _ in pairs(a.problems or {}) do nprob = nprob + 1 end
        t = "|cff8a93a8checked " .. date("%I:%M", a.written) .. "|r  "
        if nprob > 0 then t = t .. "|cfff3c56b" .. nprob .. " missing key, resync|r"
        elseif a.appUpdate or a.sterlingUpdate then t = t .. "|cfff3c56b" .. (a.appUpdate and "app" or "Sterling") .. " update available|r"
        elseif a.got and #a.got > 0 then
          local names = {}
          for _, n in ipairs(a.got) do names[#names + 1] = S.PartnerLabel(n) end
          t = t .. "|cff7ee2a2got " .. table.concat(names, ", ") .. "|r"
        else t = t .. "|cffd6dbe8up to date|r" end
      end
      page.v.app:SetText(t)
    end
  end
  page.autoNote:SetText(autoOn and "Auto sync: at login, when partners come online, and every 5 min." or "Auto sync is off (Options > Sync).")
  main.right:SetText("")
end

---------------------------------------------------------------------------
-- Detailed info window for one partner: this session next to all time
---------------------------------------------------------------------------
local info
function S.UI_PartnerInfo(name)
  if not info then
    info = Window("SterlingQuestPartnerInfo", 400, 250, "Detailed info")
    info:SetFrameStrata("HIGH")
    info.lines = {}
    info.refresh = Button(info, "Refresh", 64); info.refresh:SetPoint("BOTTOMRIGHT", -14, 10); info.refresh:SetScript("OnClick", function() S.UI_PartnerInfo(info.who) end)
    info.reset = Button(info, "Reset counters", 100); info.reset:SetPoint("BOTTOMLEFT", 14, 10)
    info.reset:SetScript("OnClick", function()
      if not info.who then return end
      SterlingQuestDB.syncStats = SterlingQuestDB.syncStats or {}; SterlingQuestDB.syncStats[info.who] = nil
      S.sync.per[info.who] = nil
      S.UI_PartnerInfo(info.who)
    end)
  end
  info.who = name
  for _, l in ipairs(info.lines) do l[1]:Hide(); l[2]:Hide(); l[3]:Hide() end
  info.title:SetText("Detailed info: " .. S.PartnerLabel(name))
  local ss, ps = S.SessionStat(name), S.PerStat(name)
  local conf, confAt, confLabel = S.Confirmed("W:" .. name)
  local sn = S.snaps[name]
  local prof = S.profiles and S.profiles[name]
  local rows = {
    { "", "|cff8a93a8This session|r", "|cff8a93a8All time|r" },
    { "Syncs out", ("%d full, %d changes"):format(ss.snapsOut or 0, ss.deltasOut or 0), ("%d full, %d changes"):format(ps.snapsOut or 0, ps.deltasOut or 0) },
    { "Syncs in", ("%d full, %d changes"):format(ss.snapsIn or 0, ss.deltasIn or 0), ("%d full, %d changes"):format(ps.snapsIn or 0, ps.deltasIn or 0) },
    { "Messages", ("%d out, %d in"):format(ss.sent or 0, ss.recv or 0), ("%d out, %d in"):format(ps.sent or 0, ps.recv or 0) },
    { "Data", ("%.1f KB out, %.1f KB in"):format((ss.bytesOut or 0) / 1024, (ss.bytesIn or 0) / 1024), ("%.0f KB out, %.0f KB in"):format((ps.bytesOut or 0) / 1024, (ps.bytesIn or 0) / 1024) },
    { "Confirmed", ("%d"):format(ss.acks or 0), ("%d"):format(ps.acks or 0) },
    { "Resyncs", ("%d"):format(ss.resyncs or 0), ("%d"):format(ps.resyncs or 0) },
    { "Sessions", ("%d sent, %d got"):format(ss.sessOut or 0, ss.sessIn or 0), ("%d sent, %d got"):format(ps.sessOut or 0, ps.sessIn or 0) },
    { "Their copy of mine", conf and ((confLabel or ("#" .. conf)) .. ", " .. ago(confAt)) or "nothing confirmed yet" },
    { "My copy of theirs", sn and (("#" .. tostring(sn.seq or 0)) .. (sn.label and sn.label ~= "" and (" " .. sn.label) or "") .. (sn.at and (", " .. ago(sn.at)) or "")) or "none" },
    { "Last heard", ps.lastIn and ago(ps.lastIn) or "nothing yet" },
    { "Character", name .. (prof and prof.name and prof.name ~= name and (" · chose \"" .. prof.name .. "\"") or "") .. (S.Nickname(name) and (" · your nickname \"" .. S.Nickname(name) .. "\"") or "") },
    { "Version", "v" .. tostring((S.addonVers and S.addonVers[name]) or (S.FindPartner(name) and S.FindPartner(name).ver) or "?") .. " · protocol " .. tostring(S.sync.vers and S.sync.vers[name] or "?") .. (sn and sn.level and (" · level " .. sn.level) or "") },
  }
  local y = -38
  for i, row in ipairs(rows) do
    local l = info.lines[i]
    if not l then
      l = {}
      l[1] = info:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l[1]:SetPoint("TOPLEFT", 14, y); l[1]:SetTextColor(S.LabelColor()); l[1]:SetWidth(112); l[1]:SetJustifyH("LEFT"); l[1]:SetWordWrap(false)
      l[2] = info:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l[2]:SetPoint("TOPLEFT", 130, y); l[2]:SetWidth(124); l[2]:SetJustifyH("LEFT"); l[2]:SetWordWrap(false)
      l[3] = info:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l[3]:SetPoint("TOPLEFT", 260, y); l[3]:SetWidth(126); l[3]:SetJustifyH("LEFT"); l[3]:SetWordWrap(false)
      info.lines[i] = l
    end
    l[1]:SetText(row[1]); l[1]:Show()
    if row[3] then l[2]:SetWidth(124); l[2]:SetText(row[2]); l[3]:SetText(row[3]); l[2]:Show(); l[3]:Show()
    else l[2]:SetWidth(256); l[2]:SetText(row[2]); l[2]:Show() end
    y = y - 15
  end
  info:SetHeight(-y + 44)
  info:Show()
end

-- Options: four tabs (General, Sync, Quest status, Recording), each a scrolling page.
-- optTabs(outer) makes the tab buttons; BuildOptions fills the pages.
local OPT_TABS = { { "general", "General" }, { "sync", "Sync" }, { "status", "Quest status" }, { "record", "Recording" } }
local function BuildOptions(outer)
  local OPT_W = 448
  outer.inner = {}          -- widgets UI_Update refreshes (profile preview, trash count)
  local ui = outer.inner
  outer.sections = {}
  local page, y
  -- one scrolling page per tab
  for _, t in ipairs(OPT_TABS) do
    local sf = CreateFrame("ScrollFrame", nil, outer); sf:SetPoint("TOPLEFT", 0, 0); sf:SetPoint("BOTTOMRIGHT", -8, 0)
    local child = CreateFrame("Frame", nil, sf); child:SetSize(OPT_W, 10); sf:SetScrollChild(child)
    local bar = outer:CreateTexture(nil, "ARTWORK"); bar:SetWidth(3); bar:SetColorTexture(S.AR, S.AG, S.AB, .45)
    local function updBar()
      if not sf:IsShown() then bar:Hide() return end
      local max = sf:GetVerticalScrollRange() or 0
      if max <= 0 then bar:Hide() return end
      local h = sf:GetHeight() or 1
      local th = math.max(24, h * h / (h + max))
      bar:SetHeight(th); bar:ClearAllPoints(); bar:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -1, -((h - th) * (sf:GetVerticalScroll() or 0) / max)); bar:Show()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
      local max = self:GetVerticalScrollRange() or 0
      self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 40))); updBar()
    end)
    sf:SetScript("OnScrollRangeChanged", updBar); sf:SetScript("OnShow", updBar); sf:SetScript("OnHide", function() bar:Hide() end)
    sf:Hide()
    outer.sections[t[1]] = { sf = sf, child = child, updBar = updBar }
  end
  local function use(key) page = outer.sections[key].child; y = 0 end
  local function done(key) outer.sections[key].child:SetHeight(-y + 10) end
  outer.Show = outer.Show   -- (keep)
  outer.ShowTab = function(key)
    outer.tab = key
    for k, sec in pairs(outer.sections) do sec.sf:SetShown(k == key) end
    local sec = outer.sections[key]; if sec then sec.updBar() end
    if rawget(outer, "tabButtons") then
      if rawget(outer, "Tabs") then S.BlizzSelectTab(outer, outer.tabIndex[key] or 1)
      else for k, b in pairs(outer.tabButtons) do local on = (k == key); b.text:SetTextColor(on and 1 or .56, on and 1 or .6, on and 1 or .7); b.line:SetShown(on) end end
    end
  end
  use("general")
  local function Section(title)
    y = y - 8
    S.SectionBar(page, title, y, OPT_W - 6)
    y = y - 26
  end
  local function Note(text)
    local n = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); n:SetPoint("TOPLEFT", 26, y + 3); n:SetWidth(OPT_W - 40); n:SetJustifyH("LEFT"); n:SetTextColor(.6, .64, .74); n:SetText(text)
    y = y - math.max(12, n:GetStringHeight() or 12) - 5
    return n
  end
  local function Row(label, key, default, onchange, note)
    local cb = Check(page, label, key, default, y, onchange); y = y - 22
    if note then Note(note) end
    return cb
  end
  -- a button that steps through choices; labelFn() gives its current text
  -- label on the left, dropdown on the right. list = { {value, text}, ... }
  local function Choice(label, list, get, set)
    local l = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetPoint("TOPLEFT", 4, y - 5); l:SetText(label); l:SetTextColor(.84, .86, .92)
    local function textOf(v) for _, c in ipairs(list) do if c[1] == v then return c[2] end end return tostring(v) end
    local d
    d = Dropdown(page, 230, function() return textOf(get()) end, function()
      local items = {}
      for _, c in ipairs(list) do items[#items + 1] = { text = c[2], checked = get() == c[1], func = function() set(c[1]); d:Refresh() end } end
      return items
    end)
    d:SetPoint("TOPLEFT", 196, y)
    y = y - 28
    return d
  end

  Section("Path and arrow")
  Row("Guided arrow on the next step", "arrowopt", true, function() SterlingQuestDB.path = S.Opt("arrowopt", true); S.Recalc(false); if not SterlingQuestDB.path then S.ClearWaypoint() end end)
  Row("Sound when the next step changes", "sound", true)
  Row("Chat line when the next step changes", "chat", true)
  y = y - 2
  local r1 = Button(page, "Reset check-offs", 116); r1:SetPoint("TOPLEFT", 4, y); r1:SetScript("OnClick", function() SlashCmdList.STERLINGQUEST("reset") end)
  local r2 = Button(page, "Stop following", 100); r2:SetPoint("LEFT", r1, "RIGHT", 4, 0); r2:SetScript("OnClick", function() S.StopFollowing(); msg("Not following anything now."); S.UI_Update() end)
  y = y - 28

  Section("Map")
  Row("Trail on the minimap", "trail", true, function() SterlingQuestDB.hideMinimapTrail = not S.Opt("trail", true) end)
  Row("Show the minimap button", "mmbtn", true, function() SterlingQuestDB.hideMinimap = not S.Opt("mmbtn", true); if SterlingQuestMinimapButton then if SterlingQuestDB.hideMinimap then SterlingQuestMinimapButton:Hide() else SterlingQuestMinimapButton:Show() end end end)

  Section("Window")
  Row("Lock the window in place", "lock", false)
  local lookDD = Choice("Look", { { "wow", "WoW (game frames)" }, { "navy", "Flat (your colours)" } }, function() return S.Opt("skin", "wow") end,
    function(v) SterlingQuestDB.opts.skin = v; if S.UI_FlatShown then S.UI_FlatShown() end end)
  lookDD:SetWidth(164)
  local applyBtn = Button(page, "Apply", 60); applyBtn:SetPoint("LEFT", lookDD, "RIGHT", 6, 0)
  applyBtn:SetScript("OnClick", function() S.UI_ApplyLook() end)
  Note("Pick a look, then Apply: the windows switch right away, no /reload. WoW uses the game's own frame pieces; Flat is Sterling's own flat look; with Flat picked, its colours appear at the bottom of this tab.")
  local lbl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); lbl:SetPoint("TOPLEFT", 4, y); lbl:SetTextColor(.84, .86, .92)
  local sl = CreateFrame("Slider", "SterlingQuestScaleSlider", page, "OptionsSliderTemplate")
  sl:SetPoint("TOPLEFT", 4, y - 18); sl:SetWidth(200); sl:SetHeight(16)
  sl:SetMinMaxValues(0.6, 1.6); sl:SetValueStep(0.05); sl:SetObeyStepOnDrag(true); sl:SetValue(S.Opt("scale", 1))
  if SterlingQuestScaleSliderLow then SterlingQuestScaleSliderLow:SetText("60%"); SterlingQuestScaleSliderHigh:SetText("160%"); SterlingQuestScaleSliderText:SetText("") end
  lbl:SetText(("Window size  %d%%"):format(S.Opt("scale", 1) * 100))
  sl:SetScript("OnValueChanged", function(_, v) v = math.floor(v * 20 + .5) / 20; SterlingQuestDB.opts.scale = v; lbl:SetText(("Window size  %d%%"):format(v * 100)); S.UI_ApplyOptions() end)
  y = y - 50
  -- see-through: the whole window (frame, text and buttons) at this opacity
  local albl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); albl:SetPoint("TOPLEFT", 4, y); albl:SetTextColor(.84, .86, .92)
  local asl = CreateFrame("Slider", "SterlingQuestAlphaSlider", page, "OptionsSliderTemplate")
  asl:SetPoint("TOPLEFT", 4, y - 18); asl:SetWidth(200); asl:SetHeight(16)
  asl:SetMinMaxValues(0.2, 1); asl:SetValueStep(0.05); asl:SetObeyStepOnDrag(true); asl:SetValue(S.Opt("alpha", 1))
  if SterlingQuestAlphaSliderLow then SterlingQuestAlphaSliderLow:SetText("20%"); SterlingQuestAlphaSliderHigh:SetText("100%"); SterlingQuestAlphaSliderText:SetText("") end
  albl:SetText(("Window opacity  %d%%"):format(S.Opt("alpha", 1) * 100))
  asl:SetScript("OnValueChanged", function(_, v) v = math.floor(v * 20 + .5) / 20; SterlingQuestDB.opts.alpha = v; albl:SetText(("Window opacity  %d%%"):format(v * 100)); S.UI_ApplyOptions() end)
  y = y - 50
  local p = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); p:SetPoint("TOPLEFT", 4, y); p:SetWidth(OPT_W - 16); p:SetJustifyH("LEFT"); p:SetTextColor(.6, .64, .74)
  p:SetText("Keybinds: Escape > Key Bindings > Sterling Quest Sync (record/stop, mark done, map, window).\nEverything here also works as /st commands: /st for the list.")
  y = y - 40
  ui.partnerText = p

  Section("Accessibility")
  Row("Colour-blind mode", "cb", false, function()
    if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end
    if ui.worksWith then ui.worksWith() end
    S.UI_Update()
  end, "Adds a symbol or a word wherever red and green carry meaning: who's online, version notices, stale syncs, finished steps and quest status lines (which always keep their labels).")

  Section("Works with")
  do
    local wl = {}
    for i, w in ipairs(S.WORKS_WITH) do
      local has = S.HasAddon(w.key)
      local l = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetPoint("TOPLEFT", 4, y); l:SetWidth(OPT_W - 14); l:SetJustifyH("LEFT")
      wl[i] = l
      y = y - 16
      Note(has and ("Adds: " .. w.adds .. ".") or w.without)
    end
    ui.worksWith = function()
      for i, w in ipairs(S.WORKS_WITH) do
        local has = S.HasAddon(w.key)
        wl[i]:SetText(S.Mark(has and "good" or "warn", true) .. S.TEXT_HEX .. w.name .. "|r   " .. (has and "|cff7ee2a2installed|r" or "|cfff3c56bnot installed|r"))
      end
    end
    ui.worksWith()
    Note("Sterling runs without either. Each one adds the things listed.")
  end

  Section("Reset")
  local resetAll = Button(page, "Reset all settings", 130); resetAll:SetPoint("TOPLEFT", 4, y)
  resetAll:SetScript("OnClick", function()
    S.UI_Confirm("Reset all settings?", "Every option goes back to its default and the windows return to where they started. Your partners, quest data and sessions are not touched.", "Reset", function() S.ResetSettings() end)
  end)
  local rtour = Button(page, "Help and tour", 110); rtour:SetPoint("LEFT", resetAll, "RIGHT", 4, 0)
  rtour:SetScript("OnClick", function() if S.UI_Help then S.UI_Help() end end)
  y = y - 28
  -- Flat look colours: only shown while the Look is set to Flat. Built in its own frame at the end of
  -- the tab so hiding it leaves no gap.
  local baseY = y
  local flatBox = CreateFrame("Frame", nil, page); flatBox:SetPoint("TOPLEFT", 0, y); flatBox:SetSize(OPT_W, 10)
  local realPage = page
  page, y = flatBox, 0
  Section("Flat look colours")
  -- Flat look colours: preset tiles, two colour swatches and a live preview
  do
    local function getPanel() local c = S.Opt("navyColor", nil); if type(c) == "table" then return c end return { .16, .2, .33 } end
    local function getAccent() local c = S.Opt("navyAccent", nil); if type(c) == "table" then return c end return { .54, .72, 1 } end
    local function same(a, b) return math.abs(a[1] - b[1]) < .01 and math.abs(a[2] - b[2]) < .01 and math.abs(a[3] - b[3]) < .01 end
    local tiles, sw, refreshFlat = {}, {}


    -- live preview: a small window in the chosen colours
    local pv = CreateFrame("Frame", nil, page, BD); pv:SetPoint("TOPLEFT", 4, y); pv:SetSize(OPT_W - 14, 74)
    if pv.SetBackdrop then pv:SetBackdrop(S.BG_FLAT) end
    local pvBar = pv:CreateTexture(nil, "ARTWORK"); pvBar:SetPoint("TOPLEFT", 1, -1); pvBar:SetPoint("TOPRIGHT", -1, -1); pvBar:SetHeight(20)
    local pvTitle = pv:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pvTitle:SetPoint("LEFT", pvBar, "LEFT", 8, 0); pvTitle:SetText("Sterling Quest Sync"); pvTitle:SetTextColor(.96, .97, 1)
    local pvTab = pv:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pvTab:SetPoint("TOPLEFT", 10, -26); pvTab:SetText("Catch-up")
    local pvTabLine = pv:CreateTexture(nil, "ARTWORK"); pvTabLine:SetPoint("TOPLEFT", pvTab, "BOTTOMLEFT", -2, -2); pvTabLine:SetPoint("TOPRIGHT", pvTab, "BOTTOMRIGHT", 2, -2); pvTabLine:SetHeight(2)
    local pvTab2 = pv:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pvTab2:SetPoint("LEFT", pvTab, "RIGHT", 22, 0); pvTab2:SetText("Path"); pvTab2:SetTextColor(.56, .6, .7)
    local pvCard = CreateFrame("Frame", nil, pv, BD); pvCard:SetPoint("TOPLEFT", 8, -46); pvCard:SetPoint("BOTTOMRIGHT", -8, 6)
    if pvCard.SetBackdrop then pvCard:SetBackdrop(S.BG_FLAT) end
    local pvHead = pvCard:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pvHead:SetPoint("LEFT", 8, 0); pvHead:SetText("Ready now (3)")
    local pvBody = pvCard:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); pvBody:SetPoint("LEFT", pvHead, "RIGHT", 10, 0); pvBody:SetText("The Corrupter, Highway Robbery"); pvBody:SetTextColor(1, 1, 1)
    y = y - 82

    -- preset tiles: each one drawn in its own colours, name in its accent
    local function Tile(p, i, col, row)
      local t = CreateFrame("Button", nil, page, BD)
      t:SetSize(140, 26); t:SetPoint("TOPLEFT", 4 + col * 147, y - row * 30)
      if t.SetBackdrop then t:SetBackdrop(S.BG_FLAT) end
      local pr, pg, pb = S.NavyWith(p[2], .16, .2, .33); t:SetBackdropColor(pr, pg, pb, 1)
      t.edge = { S.NavyWith(p[2], .26, .3, .4) }
      t:SetBackdropBorderColor(t.edge[1], t.edge[2], t.edge[3], 1)
      local bar = t:CreateTexture(nil, "ARTWORK"); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("BOTTOMLEFT", 1, 1); bar:SetWidth(4); bar:SetColorTexture(p[3][1], p[3][2], p[3][3], 1)
      local tx = t:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); tx:SetPoint("LEFT", 10, 0); tx:SetPoint("RIGHT", -4, 0); tx:SetJustifyH("LEFT"); tx:SetWordWrap(false)
      tx:SetText(p[1]); tx:SetTextColor(p[3][1], p[3][2], p[3][3])
      t:SetScript("OnClick", function()
        SterlingQuestDB.opts.navyColor = { p[2][1], p[2][2], p[2][3] }
        SterlingQuestDB.opts.navyAccent = { p[3][1], p[3][2], p[3][3] }
        refreshFlat()
      end)
      t:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(p[1]); GameTooltip:AddLine(p[4] == "match" and "Panel and accent in one colour." or "Panel with a complementary accent.", 1, 1, 1, true); GameTooltip:AddLine("Click to use, then Apply.", .7, .74, .84, true); GameTooltip:Show() end)
      t:SetScript("OnLeave", function() GameTooltip:Hide() end)
      t.preset = p
      tiles[#tiles + 1] = t
    end
    for _, grp in ipairs({ { "match", "Matching" }, { "contrast", "Contrast" } }) do
      local gl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); gl:SetPoint("TOPLEFT", 4, y - 2); gl:SetText(grp[2]); gl:SetTextColor(.6, .64, .74)
      y = y - 16
      local n = 0
      for i, p in ipairs(S.FLAT_PRESETS) do
        if p[4] == grp[1] then Tile(p, i, n % 3, math.floor(n / 3)); n = n + 1 end
      end
      y = y - math.ceil(n / 3) * 30 - 4
    end

    -- your own: two swatches with the colour picker
    local function swatch(label, x, get, set)
      local b = CreateFrame("Button", nil, page, BD)
      b:SetPoint("TOPLEFT", x, y); b:SetSize(18, 18)
      if b.SetBackdrop then b:SetBackdrop(S.BG_FLAT); b:SetBackdropColor(0, 0, 0, 1); b:SetBackdropBorderColor(.8, .7, .5, 1) end
      b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT", 2, -2); b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
      b.label = b:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); b.label:SetPoint("LEFT", b, "RIGHT", 6, 0); b.label:SetText(label); b.label:SetTextColor(.84, .86, .92)
      b.get = get
      b:SetScript("OnClick", function()
        local c = get()
        S.PickColor(c[1], c[2], c[3], 1, false, function(nr, ng, nb) set(nr, ng, nb); refreshFlat() end)
      end)
      b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label); GameTooltip:AddLine("Pick any colour. The preview follows; Apply puts it on the windows.", 1, 1, 1, true); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      sw[#sw + 1] = b
    end
    swatch("Panel colour", 4, getPanel, function(r, g, b) SterlingQuestDB.opts.navyColor = { r, g, b } end)
    swatch("Accent colour", 154, getAccent, function(r, g, b) SterlingQuestDB.opts.navyAccent = { r, g, b } end)
    local applyFlat = Button(page, "Apply", 60); applyFlat:SetPoint("TOPLEFT", 310, y + 2)
    applyFlat:SetScript("OnClick", function() SterlingQuestDB.opts.skin = "navy"; S.UI_ApplyLook() end)
    local rc = Button(page, "Reset", 60); rc:SetPoint("LEFT", applyFlat, "RIGHT", 4, 0)
    rc:SetScript("OnClick", function() SterlingQuestDB.opts.navyColor, SterlingQuestDB.opts.navyAccent = nil, nil; refreshFlat() end)
    y = y - 26
    Note("Apply here switches to the Flat look with these colours. Warnings stay red whatever you pick.")

    refreshFlat = function()
      local pc, ac = getPanel(), getAccent()
      local function nv(r, g, b) return S.NavyWith(pc, r, g, b) end
      local r, g, b = nv(.1, .12, .17); pv:SetBackdropColor(r, g, b, .96)
      r, g, b = nv(.26, .3, .4); pv:SetBackdropBorderColor(r, g, b, 1)
      pvBar:SetColorTexture(nv(.16, .2, .33))
      pvTab:SetTextColor(ac[1], ac[2], ac[3]); pvTabLine:SetColorTexture(ac[1], ac[2], ac[3], 1)
      r, g, b = nv(.16, .2, .33); pvCard:SetBackdropColor(r, g, b, .6)
      r, g, b = nv(.23, .27, .37); pvCard:SetBackdropBorderColor(r, g, b, 1)
      pvHead:SetTextColor(ac[1], ac[2], ac[3])
      for _, t in ipairs(tiles) do
        local on = same(t.preset[2], pc) and same(t.preset[3], ac)
        if on then t:SetBackdropBorderColor(1, 1, 1, 1) else t:SetBackdropBorderColor(t.edge[1], t.edge[2], t.edge[3], 1) end
      end
      for _, b in ipairs(sw) do local c = b.get(); b.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    refreshFlat()
  end
  local flatH = -y
  page, y = realPage, baseY
  flatBox:SetHeight(flatH)
  local function flatShown()
    local on = S.Opt("skin", "wow") == "navy"
    flatBox:SetShown(on)
    local sec = outer.sections.general
    sec.child:SetHeight(-baseY + 10 + (on and flatH or 0)); sec.updBar()
  end
  S.UI_FlatShown = flatShown
  flatShown()

  use("sync")
  Section("Sync")
  Row("Live sync with partner or group", "syncopt", true, function() SterlingQuestDB.sync = S.Opt("syncopt", true) end, "Partners are added and managed in the Sync tab.")
  Row("Sync with anyone in my group who has Sterling", "groupSync", false, nil, "Off (default): partners are only ever added by you, with + Add on the Sync tab; anyone else who tries gets a one-time chat note to add them. On: everyone in your party or raid running Sterling is added and synced.")
  Row("Auto sync", "autoSync", true, nil, "A quick sync when you log in, when a partner comes online or joins your group, and a check every 5 minutes.")
  Row("Quest sharing hints in a group", "groupHints", true, nil, "When a partner joins your group: what each of you could share. Ask sends them a one-click Share prompt.")
  Section("Finding other Sterling users")
  Row("Let others see I have Sterling", "discoverable", true, nil, "Answers a quiet hello from your party, guild and friends. Off: you can still invite people, but nobody finds you.")
  Row("Look for Sterling users in my guild", "findGuild", true, nil, "One hello to the guild when you log in and every 15 minutes.")
  Row("Chat line when someone in my party has Sterling", "partyNote", true, nil, "Once per person per session, with a link to invite them.")
  Row("Chat line when a partner logs in", "loginNote", true, nil, "Shown when Sync chat detail is Simple or more. Quiet keeps chat to failures only.")
  do
    local bl = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); bl:SetPoint("TOPLEFT", 4, y - 5); bl:SetTextColor(.84, .86, .92)
    local cb = Button(page, "Clear", 60); cb:SetPoint("TOPLEFT", 196, y)
    local function upd() local n = S.BlockedCount and S.BlockedCount() or 0; bl:SetText("Hidden players: " .. n) end
    cb:SetScript("OnClick", function() S.ClearBlocked(); upd() end)
    cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Hidden players"); GameTooltip:AddLine("People you hid with x in the Add window. They can't invite or sync with you. Clear lets them back.", 1, 1, 1, true); GameTooltip:Show() end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    upd()
    page:HookScript("OnShow", upd)
    y = y - 28
  end
  Row("Catch-up tab", "catchupTab", true, function() if S.UI_TabShown then S.UI_TabShown("catchup", S.Opt("catchupTab", true)) end if not S.Opt("catchupTab", true) and current == "catchup" then S.UI_Tab("sync") end end, "Quests a partner finished in a zone that you haven't, as a plan and a path. Needs Questie.")
  Row("Catch-up: include quests they only picked up", "catchupLog", false, function() if SterlingQuestDB.catchup then local c = SterlingQuestDB.catchup; S.CatchupStart(c.who, c.zone, true) end S.UI_Update() end, "Off: Catch-up only lists quests your partner turned in. On: quests still sitting in their log are added too.")
  local r3 = Button(page, "Send my log now", 110); r3:SetPoint("TOPLEFT", 4, y); r3:SetScript("OnClick", function() S.SyncWith(nil, "send") end)
  y = y - 28

  Section("Sterling Quest Sync Companion app")
  Note("Want syncing even when you're not online together? Try the optional Sterling Quest Sync Companion app. Copy the link below.")
  y = y + 2
  do
    local eb = S.UI_LinkBox(page, S.APP_LINK); eb:SetPoint("TOPLEFT", 26, y); eb:SetPoint("RIGHT", page, "LEFT", OPT_W - 14, 0)
    y = y - 28
  end

  Section("Chat detail")
  Note("Quiet prints only failures. Simple adds the syncs you start. Advanced adds auto syncs, resends and timeouts. Full prints everything, for debugging.")
  for _, area in ipairs({ { "sync", "Sync" }, { "tooltip", "Tooltips" } }) do
    Choice(area[2], { { 0, "Quiet" }, { 1, "Simple" }, { 2, "Advanced" }, { 3, "Full" } }, function() return S.ChatLevel(area[1]) end,
      function(v) SterlingQuestDB.opts["chat_" .. area[1]] = v; SterlingQuestDB.opts["debug_" .. area[1]] = nil end)
  end

  done("sync")

  use("status")
  Section("Partner quest status")
  local preview
  local function refresh()
    if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end
    if preview and S.StatusPreview then preview:SetText("Tooltip preview:\n" .. S.StatusPreview()) end
  end
  Note("One line per status (Done, Ready, In log, Not started). Only partners with the eye on in the Sync tab are shown.")
  Row("On quest givers and map pins", "tipStatus", true, refresh, "Hover a quest giver or turn-in NPC: their quests a partner has started or finished. On world map and minimap pins: under the quest's progress. Nothing is added for quests no one has started.")
  Row("Also on mobs and objects you need for quests", "tipMobs", false, refresh, "Off keeps mob tooltips clean. On adds the status under Questie's progress lines there too.")
  Choice("Tooltip style", { { "labels", "Labels (Done: Bran)" }, { "compact", "Colored names only" } }, function() return S.Opt("tipStyle", "labels") end,
    function(v) SterlingQuestDB.opts.tipStyle = v; refresh() end)
  Row("In the quest log and the NPC quest window", "logStatus", true, refresh)
  Row("Include partners who haven't started it", "logNone", true, refresh, "Quest log only. Shows them as Not started.")
  Choice("Quest log style", S.LOG_STYLES, function() return S.Opt("logStyle", "tooltip") end, function(v) SterlingQuestDB.opts.logStyle = v; refresh() end)
  Note("Tooltip bar: the game's tooltip frame under the title, warm colours. Party progress section: its own heading under the objectives, like Required items. Plain lines: one line per partner under the title. The rest are the older looks. Changes show right away on an open quest.")
  Choice("Quest log text size", { { "small", "Small" }, { "normal", "Normal" } }, function() return S.Opt("logFont", "normal") end, function(v) SterlingQuestDB.opts.logFont = v; refresh() end)
  Row("Show progress like 3/8", "statusProgress", true, refresh)
  Row("Only people in my group right now", "statusGroupOnly", false, refresh, "Off: everyone with the eye on.")
  preview = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); preview:SetPoint("TOPLEFT", 4, y); preview:SetWidth(OPT_W - 14); preview:SetJustifyH("LEFT"); preview:SetTextColor(.6, .64, .74)
  y = y - 58

  -- Appearance: presets, colour swatches and a live preview of the quest log block
  Section("Quest log appearance")
  Note("For the Tooltip bar style. Pick a preset, or click any colour to make your own: the first change copies the preset into Custom.")
  local presetDD
  local swatches, checks = {}, {}
  local function isCustom() return S.Opt("tipLook", "warm") == "custom" end
  local list = {}
  for _, x in ipairs(S.TIP_LOOKS) do list[#list + 1] = { x[1], x[2] } end
  list[#list + 1] = { "custom", "Custom (your colours)" }
  presetDD = Choice("Preset", list, function() return S.Opt("tipLook", "warm") end, function(v)
    if v == "custom" then S.TipCustom() end
    SterlingQuestDB.opts.tipLook = v; refresh()
  end)

  -- the preview: a strip of quest page with a title and the block under it
  local pv = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
  pv:SetPoint("TOPLEFT", 4, y - 2); pv:SetSize(OPT_W - 14, 150)
  local paper = pv:CreateTexture(nil, "BACKGROUND"); paper:SetAllPoints()
  if not (paper.SetAtlas and pcall(paper.SetAtlas, paper, "QuestBG-Parchment") and paper:GetAtlas()) then
    paper:SetTexture("Interface\\QuestFrame\\QuestBG"); paper:SetTexCoord(0, .6, 0, .3)
  end
  local tint = pv:CreateTexture(nil, "BORDER"); tint:SetAllPoints(); tint:SetColorTexture(.87, .78, .58, 0)
  if not paper:GetTexture() and not (paper.GetAtlas and paper:GetAtlas()) then tint:SetColorTexture(.87, .78, .58, 1) end
  local edge = CreateFrame("Frame", nil, pv, BackdropTemplateMixin and "BackdropTemplate" or nil); edge:SetAllPoints()
  if edge.SetBackdrop then edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 }); edge:SetBackdropBorderColor(.5, .4, .25, .9) end
  local ptitle = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  pcall(ptitle.SetFontObject, ptitle, "QuestTitleFont"); ptitle:SetTextColor(.18, .11, .03); pcall(ptitle.SetShadowOffset, ptitle, 0, 0)
  ptitle:SetPoint("TOPLEFT", 12, -10); ptitle:SetText("Hate the Hatefury")
  local sample = S.StatusSample(pv); sample:SetPoint("TOPLEFT", ptitle, "BOTTOMLEFT", 0, -4)
  local pdesc = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pcall(pdesc.SetFontObject, pdesc, "QuestFont"); pdesc:SetTextColor(.18, .11, .03); pcall(pdesc.SetShadowOffset, pdesc, 0, 0)
  pdesc:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -6); pdesc:SetWidth(OPT_W - 44); pdesc:SetJustifyH("LEFT")
  pdesc:SetText("Defeat a variety of Hatefury satyrs in Desolace.")
  y = y - 160

  -- colour helpers: text colours are kept as hex, the rest as r,g,b,a
  local function hex2rgb(h) h = h or "ffffff"; return (tonumber(h:sub(1, 2), 16) or 255) / 255, (tonumber(h:sub(3, 4), 16) or 255) / 255, (tonumber(h:sub(5, 6), 16) or 255) / 255 end
  local function rgb2hex(r, g, b) return ("%02x%02x%02x"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5)) end
  local function getColor(key)
    local look = S.TipLook()
    if key == "bg" or key == "edge" or key == "ruleColor" then
      local c = look[key] or { .5, .5, .5, 1 }
      return c[1], c[2], c[3], c[4] or 1
    end
    local r, g, b = hex2rgb(look.text and look.text[key]); return r, g, b, 1
  end
  local function setColor(key, r, g, b, a)
    local c = S.TipCustom()
    if key == "bg" or key == "edge" or key == "ruleColor" then c[key] = { r, g, b, a or 1 }
    else c.text[key] = rgb2hex(r, g, b) end
  end
  local function pick(key, hasAlpha)
    local r, g, b, a = getColor(key)
    local CPF = _G.ColorPickerFrame
    if type(CPF) ~= "table" then return end
    local function now()
      local nr, ng, nb = CPF:GetColorRGB()
      local na = a
      if hasAlpha then
        if CPF.GetColorAlpha then na = CPF:GetColorAlpha()
        elseif _G.OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
      end
      return nr, ng, nb, na
    end
    local function changed() setColor(key, now()); refresh() end
    local function cancel() setColor(key, r, g, b, a); refresh() end
    if CPF.SetupColorPickerAndShow then
      CPF:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha, swatchFunc = changed, opacityFunc = changed, cancelFunc = cancel })
    else
      CPF.hasOpacity = hasAlpha; CPF.opacity = 1 - (a or 1); CPF.previousValues = { r, g, b, a }
      CPF.func, CPF.opacityFunc, CPF.cancelFunc = changed, changed, cancel
      CPF:SetColorRGB(r, g, b); CPF:Hide(); ShowUIPanel(CPF)
    end
  end
  local function Swatch(label, key, hasAlpha, col)
    local x = 4 + (col - 1) * 150
    local b = CreateFrame("Button", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetPoint("TOPLEFT", x, y); b:SetSize(18, 18)
    if b.SetBackdrop then b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }); b:SetBackdropColor(0, 0, 0, 1); b:SetBackdropBorderColor(.8, .7, .5, 1) end
    b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT", 2, -2); b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    b.label = b:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); b.label:SetPoint("LEFT", b, "RIGHT", 6, 0); b.label:SetText(label); b.label:SetTextColor(.84, .86, .92)
    b:SetScript("OnClick", function() pick(key, hasAlpha) end)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label); GameTooltip:AddLine("Click to pick a colour.", 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.key = key
    swatches[#swatches + 1] = b
  end
  Swatch("Background", "bg", true, 1); Swatch("Edge", "edge", true, 2); y = y - 24
  Swatch("Side line", "ruleColor", true, 1); Swatch("Done", "done", false, 2); y = y - 24
  Swatch("Ready to turn in", "ready", false, 1); Swatch("In log", "log", false, 2); y = y - 24
  Swatch("Not started", "none", false, 1); y = y - 28

  local function LookCheck(label, field, col, tip)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", (col - 1) * 150, y); cb:SetSize(24, 24)
    cb.text = cb:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0); cb.text:SetText(label); cb.text:SetTextColor(.84, .86, .92)
    cb:SetScript("OnClick", function(self)
      local c = S.TipCustom()
      if field == "box" then c.box = self:GetChecked() and true or false else c[field] = self:GetChecked() and true or false end
      refresh()
    end)
    if tip then
      cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
      cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb.field = field
    checks[#checks + 1] = cb
  end
  LookCheck("Box behind the text", "box", 1, "Off: clear, the text sits right on the page.")
  LookCheck("Side line", "rule", 2, "A coloured line down the left edge that marks the space.")
  y = y - 24
  LookCheck("Dark text (no shadow)", "dark", 1, "Ink like the quest text. Off: light text with a shadow, for dark boxes.")
  y = y - 28
  local reset = Button(page, "Reset to preset", 120); reset:SetPoint("TOPLEFT", 4, y)
  reset:SetScript("OnClick", function()
    -- only Custom has anything to reset; a preset stays the preset it is
    if S.Opt("tipLook", "warm") == "custom" then
      local c = SterlingQuestDB.opts.tipCustom
      SterlingQuestDB.opts.tipLook = (c and c.base and c.base ~= "custom") and c.base or "warm"
      SterlingQuestDB.opts.tipCustom = nil
    end
    refresh()
  end)
  y = y - 30

  -- keep the swatches, checks and preview in step with the current look
  local baseRefresh = refresh
  refresh = function()
    baseRefresh()
    local look = S.TipLook()
    for _, b in ipairs(swatches) do local r, g, bb, a = getColor(b.key); b.fill:SetColorTexture(r, g, bb, a) end
    for _, cb in ipairs(checks) do
      local v = look[cb.field]
      if cb.field == "box" then v = look.box ~= false and look.bg ~= nil end
      cb:SetChecked(v and true or false)
    end
    if presetDD and presetDD.Refresh then presetDD:Refresh() end
    sample.Render(OPT_W - 44)
  end
  refresh()

  done("status")

  use("record")
  Section("Recording")
  Row("Auto record when I log in", "autoRecord", false, nil, "Starts a recording on login and after a /reload, if one isn't already running.")
  Row("Continue an unfinished recording", "autoResume", true, nil, "After a relog, disconnect or game restart, pick up where you left off instead of starting over.")
  do
    local list = {}
    for _, v in ipairs(S.ResumeChoices) do list[#list + 1] = { v, S.ResumeLabel(v) } end
    Choice("Continue if back within", list, function() return S.Opt("resumeWithin", 3 * 3600) end, function(v) SterlingQuestDB.opts.resumeWithin = v end)
  end
  Note("Longer than that, the old recording is saved as its own session and (with auto record on) a new one starts. A game crash only keeps what was saved at your last /reload or logout.")

  Section("Deleted sessions")
  Row("Delete for good (skip the trash)", "noTrash", false, nil, "Off: deleted sessions wait in the trash (last 5) and Restore on the Sessions page brings them back.")
  local et = Button(page, "Empty the trash", 110); et:SetPoint("TOPLEFT", 4, y)
  local etn = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); etn:SetPoint("LEFT", et, "RIGHT", 8, 0); etn:SetTextColor(.56, .6, .7)
  local function trashCount() local n = SterlingQuestDB.trash and #SterlingQuestDB.trash or 0; etn:SetText(n == 0 and "Trash is empty" or (n .. " deleted session" .. (n == 1 and "" or "s") .. " in the trash")); et:SetEnabled(n > 0) end
  et:SetScript("OnClick", function()
    local n = SterlingQuestDB.trash and #SterlingQuestDB.trash or 0
    if n == 0 then return end
    S.UI_Prompt("Empty the trash?", n .. " deleted session" .. (n == 1 and "" or "s") .. " will be gone for good. This can't be undone.", nil, "Empty", function() S.EmptyTrash(); trashCount() end)
    save.eb:Hide()
  end)
  et:SetScript("OnShow", trashCount); trashCount()
  ui.trashCount = trashCount
  y = y - 28

  Section("Old sessions")
  local packNote
  local function packText()
    if not packNote then return end
    local n, before, after, waiting = S.PackStats()
    local t = n == 0 and "Nothing packed yet." or ((n == 1 and "1 session packed" or (n .. " sessions packed")) .. (before > 0 and (": %d KB down to %d KB."):format(math.ceil(before / 1024), math.ceil(after / 1024)) or "."))
    if waiting > 0 and S.Opt("packOld", true) then t = t .. " " .. waiting .. " waiting; they go one at a time while you play." end
    packNote:SetText(t)
  end
  Row("Pack sessions older than 30 days", "packOld", true, function()
    if S.Opt("packOld", true) then S.PackSoon(2) else local n = S.UnpackAll(); if n > 0 then msg(n .. " session" .. (n == 1 and "" or "s") .. " unpacked.") end end
    packText()
  end, "Squeezes an old session's trail and events into one compressed block so your saved data stays small and logging in stays quick. Nothing is lost: a packed session opens by itself when you follow, map, export or send it. Partner quest data is never packed or trimmed.")
  packNote = Note("Nothing packed yet.")
  page:HookScript("OnShow", packText); packText()
  ui.packText = packText

  done("record")
  outer.ShowTab(outer.tab or "general")
end

function S.UI_ApplyOptions()
  local sc, al = S.Opt("scale", 1), S.Opt("alpha", 1)
  for _, w in ipairs(S.windows or {}) do w:SetAlpha(al); w:SetScale(sc) end
end

---------------------------------------------------------------------------
-- Catch-up tab: a partner, a zone, and the quests they did there that you haven't
---------------------------------------------------------------------------
local function BuildCatchup(page)
  local y = 0
  page.whoLabel = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.whoLabel:SetPoint("TOPLEFT", 4, y - 5); page.whoLabel:SetText("Catch up to"); page.whoLabel:SetTextColor(S.LabelColor())
  page.who = Dropdown(page, 112, function() return S.catchupWho and S.PartnerLabel(S.catchupWho) or "pick someone" end, function()
    local items = {}
    for _, p in ipairs(S.Partners()) do
      if S.snaps[p.name] then items[#items + 1] = { text = S.PartnerLabel(p.name), checked = S.catchupWho == p.name, func = function() S.catchupWho = p.name; page.zone = nil; page.follow = true; page.manual = nil; S.UI_Update() end } end
    end
    if #items == 0 then items[1] = { text = "Nobody synced yet", disabled = true } end
    return items
  end)
  page.who:SetPoint("LEFT", page.whoLabel, "RIGHT", 6, 0)
  page.search = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); page.search:SetHeight(20); page.search:SetPoint("LEFT", page.who, "RIGHT", 14, 0); page.search:SetPoint("RIGHT", page, "RIGHT", -4, 0); page.search:SetPoint("TOP", page.who, "TOP", 0, -1); page.search:SetAutoFocus(false)
  page.search:SetScript("OnTextChanged", function(self, user) page.scrollToSel = true; if user then page.manual = true end; S.UI_Update() end)
  page.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  page.search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if page.firstZone then page.zone = page.firstZone; page.manual = true; S.UI_Update() end end)
  page.searchHint = page.search:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.searchHint:SetPoint("LEFT", 4, 0); page.searchHint:SetText("type to find a zone"); page.searchHint:SetTextColor(.42, .46, .55)
  y = y - 28
  -- Opening the tab starts on the zone you're standing in. A zone you pick yourself stays until you
  -- leave the tab; until then, walking into a new zone moves the choice with you.
  page.follow = true
  page:HookScript("OnShow", function() page.follow = true; page.manual = nil end)
  -- zone list: 5 rows, wheel for more
  local ZH, ZN = 18, 5
  page.zoneBox = Box(page); page.zoneBox:SetPoint("TOPLEFT", 0, y); page.zoneBox:SetPoint("RIGHT", 0, 0); page.zoneBox:SetHeight(ZN * ZH + 4)
  page.zoneBox:SetBackdropColor(1, 1, 1, .025); page.zoneBox:SetBackdropBorderColor(.23, .27, .37, 1)
  page.zoneBox:EnableMouseWheel(true)
  page.zoneBox:SetScript("OnMouseWheel", function(_, d) page.zoneOffset = math.max(0, (page.zoneOffset or 0) - d); S.UI_Update() end)
  page.zoneRows = {}; page.zoneOffset = 0
  for i = 1, ZN do
    local r = CreateFrame("Button", nil, page.zoneBox); r:SetHeight(ZH); r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ZH); r:SetPoint("RIGHT", -2, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(S.AR, S.AG, S.AB, .15)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(S.AR, S.AG, S.AB, .18); r.sel:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.text:SetPoint("LEFT", 6, 0); r.text:SetJustifyH("LEFT")
    r.n = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.n:SetPoint("RIGHT", -6, 0); r.n:SetTextColor(.56, .6, .7)
    r:SetScript("OnClick", function() if r.key then page.zone = r.key; page.manual = true; page.offset = 0; S.UI_Update() end end)
    page.zoneRows[i] = r
  end
  page.zoneEmpty = page.zoneBox:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.zoneEmpty:SetPoint("CENTER"); page.zoneEmpty:SetWidth(310); page.zoneEmpty:SetTextColor(.5, .55, .65)
  y = y - (ZN * ZH + 4) - 6
  page.summary = page:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.summary:SetPoint("TOPLEFT", 4, y); page.summary:SetPoint("RIGHT", -4, 0); page.summary:SetJustifyH("LEFT"); page.summary:SetTextColor(.7, .74, .84); page.summary:SetWordWrap(false)
  y = y - 18
  -- column headers so the right-hand side reads at a glance
  page.hdr = CreateFrame("Frame", nil, page); page.hdr:SetPoint("TOPLEFT", 0, y); page.hdr:SetPoint("RIGHT", 0, 0); page.hdr:SetHeight(14)
  local h1 = page.hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h1:SetPoint("LEFT", 4, 0); h1:SetText("Quest"); h1:SetTextColor(S.Accent())
  local h3 = page.hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h3:SetPoint("RIGHT", -14, 0); h3:SetWidth(34); h3:SetJustifyH("RIGHT"); h3:SetText("Lvl"); h3:SetTextColor(S.Accent())
  local h2 = page.hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h2:SetPoint("RIGHT", h3, "LEFT", -8, 0); h2:SetText("Details"); h2:SetTextColor(S.Accent())
  page.hdrLine = page.hdr:CreateTexture(nil, "ARTWORK"); page.hdrLine:SetPoint("BOTTOMLEFT", 2, -1); page.hdrLine:SetPoint("BOTTOMRIGHT", -12, -1); page.hdrLine:SetHeight(1); page.hdrLine:SetColorTexture(S.AR, S.AG, S.AB, .35)
  y = y - 18
  -- plan list
  local PH = 16
  page.plan = CreateFrame("Frame", nil, page); page.plan:SetPoint("TOPLEFT", 0, y); page.plan:SetPoint("BOTTOMRIGHT", 0, 30)
  page.plan:EnableMouseWheel(true)
  page.plan:SetScript("OnMouseWheel", function(_, d) page.offset = math.max(0, (page.offset or 0) - d * 3); S.UI_Update() end)
  page.psb = MiniScroll(page.plan, function(off) page.offset = off; S.UI_Update() end)
  page.psb:SetPoint("TOPRIGHT", 0, 0); page.psb:SetPoint("BOTTOMRIGHT", 0, 0)
  page.planRows = {}; page.offset = 0; page.PH = PH
  page.PlanRow = function(i)
    local r = page.planRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.plan); r:SetHeight(PH); r:SetPoint("TOPLEFT", 0, -(i - 1) * PH); r:SetPoint("RIGHT", -10, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(S.AR, S.AG, S.AB, .1)
    -- three columns: quest (takes what it needs, capped), starts at (the rest), level (fixed)
    r.text = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.text:SetPoint("LEFT", 4, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.lvl = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.lvl:SetPoint("RIGHT", -4, 0); r.lvl:SetWidth(34); r.lvl:SetJustifyH("RIGHT"); r.lvl:SetWordWrap(false)
    r.meta = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.meta:SetPoint("LEFT", r.text, "RIGHT", 8, 0); r.meta:SetPoint("RIGHT", r.lvl, "LEFT", -8, 0); r.meta:SetJustifyH("RIGHT"); r.meta:SetWordWrap(false); r.meta:SetTextColor(.7, .74, .84)
    r:SetScript("OnEnter", function(self)
      if not r.it then return end
      local it = r.it
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if r.chainRow then
        GameTooltip:AddLine("After " .. it.name, 1, 1, 1)
        for k, c in ipairs(it.chain or {}) do GameTooltip:AddDoubleLine(k .. ". " .. c.name, (c.giver and c.giver.name or "") .. (c.level and c.level > 0 and ("  lvl " .. c.level) or ""), .95, .77, .42, .7, .74, .84) end
        GameTooltip:AddLine("Each one opens up when the one before it is turned in.", .56, .6, .7, true)
        GameTooltip:Show(); return
      end
      GameTooltip:AddLine(it.name, 1, 1, 1)
      GameTooltip:AddLine("Quest " .. it.qid .. (it.qlevel and it.qlevel > 0 and ("  ·  level " .. it.qlevel) or "") .. (it.level and it.level > 0 and ("  ·  needs " .. it.level) or ""), .56, .6, .7)
      if it.giver then GameTooltip:AddDoubleLine("Starts at", it.giver.name .. (it.giver.x and (("  (%.0f, %.0f)"):format(it.giver.x, it.giver.y)) or ""), .56, .6, .7, .9, .92, 1) end
      if it.turnin then GameTooltip:AddDoubleLine("Ends at", it.turnin.name .. (it.turnin.x and (("  (%.0f, %.0f)"):format(it.turnin.x, it.turnin.y)) or ""), .56, .6, .7, .9, .92, 1) end
      if it.why then GameTooltip:AddLine(it.why, .95, .77, .42, true) end
      if it.state == "locked" and it.afterId then
        local pre = S.CatchupPlan and nil
        local giverName
        if S.PrereqSpot then local sp = S.PrereqSpot(it.afterId); if sp then giverName = sp.name .. (sp.x and ((" (%.0f, %.0f)"):format(sp.x, sp.y)) or "") end end
        if giverName then GameTooltip:AddDoubleLine("Prerequisite starts at", giverName .. (it.afterZone and (", " .. it.afterZone) or ""), .56, .6, .7, .9, .92, 1) end
      end
      GameTooltip:AddLine(S.PartnerLabel(S.catchupWho or "") .. ": " .. (it.theirs == "done" and "turned in" or "in their log"), .7, .74, .84)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.planRows[i] = r
    return r
  end
  page.planEmpty = page.plan:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); page.planEmpty:SetPoint("TOP", 0, -30); page.planEmpty:SetWidth(300); page.planEmpty:SetJustifyH("CENTER"); page.planEmpty:SetTextColor(.5, .55, .65)
  -- buttons
  page.start = Button(page, "Start path", 86); page.start:SetPoint("BOTTOMLEFT", 0, 0)   -- same spot and spacing as the Path and Sessions rows
  page.start:SetScript("OnClick", function() if S.catchupWho and page.zone then if S.CatchupStart(S.catchupWho, page.zone) then S.UI_Tab("path") end end end)
  page.map = Button(page, "Show on map", 92); page.map:SetPoint("LEFT", page.start, "RIGHT", 4, 0)
  page.map:SetScript("OnClick", function() local z = page.zoneInfo; if z then S.ShowZoneOnMap(z.map) end end)
  page.stop = Button(page, "Stop", 48); page.stop:SetPoint("LEFT", page.map, "RIGHT", 4, 0)
  -- path order: the order your partner did them, or the shortest walk
  page.order = Dropdown(page, 92, function() return S.CatchupOrder() == "theirs" and "Their order" or "Shortest" end, function()
    local function pick(v) SterlingQuestDB.opts.catchupOrder = v; page.order:Refresh(); if S.catchupLabel and SterlingQuestDB.catchup then local c = SterlingQuestDB.catchup; S.CatchupStart(c.who, c.zone) end; S.UI_Update() end
    return { { text = "Path order", isTitle = true },
             { text = "Their order (how " .. (S.catchupWho and S.PartnerLabel(S.catchupWho) or "they") .. " did it)", checked = S.CatchupOrder() == "theirs", func = function() pick("theirs") end },
             { text = "Shortest route", checked = S.CatchupOrder() ~= "theirs", func = function() pick("route") end } }
  end)
  page.order:SetPoint("BOTTOMRIGHT", 0, 0); page.order:SetHeight(21)   -- same height as the buttons it shares the row with
  page.order:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Path order"); GameTooltip:AddLine("Their order: the order your partner finished these quests (they need 6.20 or newer). Shortest route: the nearest next stop each time. Changing it rebuilds a running path.", 1, 1, 1, true); GameTooltip:Show() end)
  page.order:HookScript("OnLeave", function() GameTooltip:Hide() end)
  page.stop:SetScript("OnClick", function() S.StopFollowing(); S.UI_Update() end)
end

local GROUP_COLOR = { ready = "|cff7ee2a2", inlog = "|cff8ab8ff", locked = "|cfff3c56b", level = "|cffff9b92", other = "|cff8a93a8" }
local function UpdateCatchup(page)
  main:SetHeight(STD_H); main.right:SetText("")
  -- partner
  if not S.catchupWho or not S.snaps[S.catchupWho] then
    S.catchupWho = nil
    for _, p in ipairs(S.Partners()) do if S.snaps[p.name] and not S.catchupWho then S.catchupWho = p.name end end
  end
  local who = S.catchupWho
  page.who:Refresh()
  page.searchHint:SetShown(page.search:GetText() == "" and not page.search:HasFocus())
  for _, r in ipairs(page.zoneRows) do r:Hide() end
  for _, r in ipairs(page.planRows) do r:Hide() end
  page.psb:Hide()
  page.zoneInfo = nil
  local zones = who and S.CatchupZones(who)
  if not S.HasAddon("Questie") or (who and zones == nil) then
    page.zoneEmpty:SetText("|cffffd100Catch-up needs Questie|r\nIt reads Questie's quest database to work out what you're missing. Install or enable Questie, then /reload. Sync, Compare, Path and recording all work without it."); page.zoneEmpty:Show()
    page.summary:SetText(""); page.planEmpty:SetText(""); page.start:SetEnabled(false); page.map:SetEnabled(false); page.stop:SetShown(S.catchupLabel ~= nil)
    return
  end
  if not who then
    page.zoneEmpty:SetText("Sync with a partner first. Their quests show up here."); page.zoneEmpty:Show()
    page.summary:SetText(""); page.planEmpty:SetText(""); page.start:SetEnabled(false); page.map:SetEnabled(false); page.stop:SetShown(S.catchupLabel ~= nil)
    return
  end
  -- filter
  local q = (page.search:GetText() or ""):lower():gsub("^%s+", "")
  local shown = {}
  for _, z in ipairs(zones) do if q == "" or z.name:lower():find(q, 1, true) then shown[#shown + 1] = z end end
  page.firstZone = shown[1] and shown[1].key or nil
  -- keep the chosen zone if it's still in the list; only pick a new one when the search filtered it out
  if page.follow and q == "" then
    local here = S.CatchupHere(zones)
    if here and here.key ~= page.zone then page.zone = here.key; page.offset = 0 end
    if here then page.scrollToSel = true end
  end
  page.follow = nil
  local selIdx
  for k, z in ipairs(shown) do if z.key == page.zone then selIdx = k end end
  if not selIdx and q ~= "" and shown[1] then page.zone = shown[1].key; page.offset = 0; selIdx = 1 end
  if page.scrollToSel and selIdx then page.zoneOffset = selIdx - 1 end
  page.scrollToSel = nil
  page.zoneOffset = math.max(0, math.min(page.zoneOffset or 0, math.max(0, #shown - #page.zoneRows)))
  if #shown == 0 then
    page.zoneEmpty:SetText(#zones == 0 and ("You're caught up with " .. S.PartnerLabel(who) .. " everywhere.") or "No zone matches that."); page.zoneEmpty:Show()
  else page.zoneEmpty:Hide() end
  local have = false
  for i = 1, #page.zoneRows do
    local z = shown[page.zoneOffset + i]
    local r = page.zoneRows[i]
    if z then
      r.key = z.key; r.text:SetText(z.name); r.n:SetText(z.count .. " to catch up")
      r.sel:SetShown(page.zone == z.key)
      if page.zone == z.key then have = true end
      r:Show()
    end
  end
  -- nothing chosen and you're not standing in a listed zone: the first one
  if (not page.zone or not selIdx) and shown[1] then
    local pick = shown[1].key
    if pick ~= page.zone then page.zone = pick; page.offset = 0; for i = 1, #page.zoneRows do local r = page.zoneRows[i]; r.sel:SetShown(r:IsShown() and r.key == pick) end end
  end
  local plan = page.zone and S.CatchupPlan(who, page.zone)
  if not plan then
    page.summary:SetText(""); page.planEmpty:SetText(#zones == 0 and "" or "Pick a zone above."); page.start:SetEnabled(false); page.map:SetEnabled(false); page.stop:SetShown(S.catchupLabel ~= nil)
    return
  end
  page.zoneInfo = plan.zone
  page.summary:SetText(("|cffd6dbe8%s|r: %s finished %d here, you finished %d.  " .. S.TEXT_HEX .. "%d to go.|r"):format(plan.zone.name, S.PartnerLabel(who), plan.theirs, plan.mine, plan.total))
  -- flat rows
  local flat = {}
  local n = 0
  for _, g in ipairs(plan.groups) do
    flat[#flat + 1] = { header = g }
    for _, it in ipairs(g.items) do
      n = n + 1; flat[#flat + 1] = { it = it, n = n }
      if it.chain then flat[#flat + 1] = { chain = it } end     -- one compact line: what this quest leads to
    end
  end
  local visible = math.floor((page.plan:GetHeight() or 200) / page.PH)
  page.offset = math.max(0, math.min(page.offset or 0, math.max(0, #flat - visible)))
  for i = 1, visible do
    local row = flat[page.offset + i]
    if not row then break end
    local r = page.PlanRow(i)
    r.it = row.it or row.chain
    r.chainRow = row.chain ~= nil
    if row.chain then
      local names = {}
      for _, c in ipairs(row.chain.chain) do names[#names + 1] = c.name end
      r.text:SetText("        |cff8a93a8then|r " .. GROUP_COLOR.locked .. table.concat(names, " > ") .. "|r")
      r.text:SetWidth(0); r.text:SetWidth(math.min(r.text:GetStringWidth() or 200, 300))
      r.meta:SetText(""); r.lvl:SetText(""); r.hl:SetAlpha(1)
    elseif row.header then
      local g = row.header
      r.text:SetText(GROUP_COLOR[g.key] .. g.title .. " (" .. #g.items .. ")|r"); r.text:SetWidth(0); r.text:SetWidth(math.min(r.text:GetStringWidth() or 200, 300)); r.meta:SetText(""); r.lvl:SetText("")
      r.hl:SetAlpha(0)
    else
      local it = row.it
      local c = GROUP_COLOR[it.state] or S.TEXT_HEX
      r.text:SetText("   " .. row.n .. ".  " .. c .. it.name .. "|r")
      r.text:SetWidth(0); r.text:SetWidth(math.min(r.text:GetStringWidth() or 200, 215))
      local meta, lvl = "", (it.level and it.level > 0) and tostring(it.level) or ""
      if it.state == "ready" then meta = it.giver and it.giver.name or ""
      elseif it.state == "inlog" then meta = "|cff8ab8ff" .. (it.why or "in your log") .. "|r"
      elseif it.state == "locked" then meta = it.why or ("Prerequisite: " .. (it.after or "?"))
      elseif it.state == "level" then meta = (it.giver and it.giver.name or ""); lvl = "|cffff9b92" .. it.level .. (S.ColorBlind() and "!" or "") .. "|r"
      else meta = "|cff8a93a8" .. (it.why or "") .. "|r" end
      r.meta:SetText(meta); r.lvl:SetText(lvl)
      r.hl:SetAlpha(1)
    end
    r:Show()
  end
  page.psb:Set(page.offset, visible, #flat)
  page.planEmpty:SetText(#flat == 0 and "Nothing to catch up on here." or "")
  local active = SterlingQuestDB.catchup and SterlingQuestDB.catchup.who == who and SterlingQuestDB.catchup.zone == page.zone
  page.start:SetEnabled(plan.total > 0); page.start:SetText(active and "Restart" or "Start path")
  page.map:SetEnabled(plan.zone.map ~= nil)
  page.stop:SetShown(S.catchupLabel ~= nil)
end

---------------------------------------------------------------------------
-- Quest sharing in a group: what a partner could share with you, and you with them
---------------------------------------------------------------------------
local share
local function groupPartners()
  local out = {}
  for _, p in ipairs(S.Partners()) do
    if p.on and ((UnitInParty and UnitInParty(p.name)) or (UnitInRaid and UnitInRaid(p.name))) then out[#out + 1] = p.name end
  end
  return out
end

local function buildShare()
  share = Window("SterlingQuestShare", 320, 200, "Quest sharing")
  share:SetFrameStrata("HIGH")
  share.rows = {}
  share.whoLabel = share:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); share.whoLabel:SetPoint("TOPLEFT", 12, -41); share.whoLabel:SetText("With"); share.whoLabel:SetTextColor(S.LabelColor())
  share.who = Dropdown(share, 150, function() return share.name and S.PartnerLabel(share.name) or "nobody in your group" end, function()
    local items = {}
    for _, n in ipairs(groupPartners()) do items[#items + 1] = { text = S.PartnerLabel(n), checked = share.name == n, func = function() S.UI_ShareWindow(n) end } end
    return items
  end)
  share.who:SetPoint("LEFT", share.whoLabel, "RIGHT", 6, 0)
  share.refresh = Button(share, "Refresh", 64); share.refresh:SetPoint("TOPRIGHT", -10, -36)
  share.refresh:SetScript("OnClick", function() if share.name then S.RequestPartner(share.name) end; S.UI_ShareWindow(share.name) end)
  share.note = share:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); share.note:SetPoint("BOTTOMLEFT", 10, 8); share.note:SetPoint("RIGHT", -10, 0); share.note:SetJustifyH("LEFT"); share.note:SetTextColor(.5, .55, .65)
  share.Row = function(i)
    local r = share.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, share); r:SetHeight(20); r:SetPoint("LEFT", 10, 0); r:SetPoint("RIGHT", -10, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.text:SetPoint("LEFT", 0, 0); r.text:SetPoint("RIGHT", -70, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.btn = Button(r, "", 60); r.btn:SetPoint("RIGHT", 0, 0)
    r.hit = CreateFrame("Frame", nil, r); r.hit:SetPoint("TOPLEFT"); r.hit:SetPoint("BOTTOMRIGHT", -70, 0)
    r.hit:SetScript("OnEnter", function(self) if r.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(r.tip, 1, 1, 1, true); GameTooltip:Show() end end)
    r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    share.rows[i] = r
    return r
  end
end

function S.UI_ShareWindow(name)
  if not share then buildShare() end
  local gp = groupPartners()
  if not name or not S.FindPartner(name) then name = gp[1] end
  share.name = name
  for _, r in ipairs(share.rows) do r:Hide() end
  if not name then
    share.title:SetText("Quest sharing"); share.who:SetEnabled(false); share.who:Refresh()
    share.note:SetText("Group up with a partner to see what you can share."); share:SetHeight(110); share:Show(); return
  end
  local label = S.PartnerLabel(name)
  share.title:SetText("Quest sharing with " .. label)
  share.who:SetEnabled(#gp > 1); share.who:Refresh()
  local c = S.ShareCandidates(name)
  local y, i = -62, 0
  local function header(text)
    i = i + 1; local r = share.Row(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); r:SetPoint("RIGHT", -10, 0)
    r.text:SetText(text); r.text:SetTextColor(S.AR, S.AG, S.AB); r.btn:Hide(); r.tip = nil; r:Show(); y = y - 18
  end
  local function item(it, btnText, onClick)
    i = i + 1; local r = share.Row(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); r:SetPoint("RIGHT", -10, 0)
    r.text:SetText((it.ok and "" or "|cff8a93a8") .. it.name .. (it.ok and "" or ("|r  |cff8a93a8" .. (it.why or "") .. "|r")))
    r.text:SetTextColor(S.TR, S.TG, S.TB)
    r.tip = it.why
    r.btn:SetText(btnText); r.btn:SetEnabled(it.ok); r.btn:SetScript("OnClick", onClick); r.btn:Show()
    r:Show(); y = y - 20
  end
  local MAX = 7
  header(label .. " can share with you" .. (#c.theirs == 0 and "  |cff8a93a8(nothing)|r" or ""))
  for k, it in ipairs(c.theirs) do
    if k > MAX then i = i + 1; local r = share.Row(i); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); r.text:SetText("|cff8a93a8+" .. (#c.theirs - MAX) .. " more|r"); r.btn:Hide(); r:Show(); y = y - 18; break end
    item(it, "Ask", function() S.AskShare(name, it.qid) end)
  end
  y = y - 6
  header("You can share with " .. label .. (#c.mine == 0 and "  |cff8a93a8(nothing)|r" or ""))
  for k, it in ipairs(c.mine) do
    if k > MAX then i = i + 1; local r = share.Row(i); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); r.text:SetText("|cff8a93a8+" .. (#c.mine - MAX) .. " more|r"); r.btn:Hide(); r:Show(); y = y - 18; break end
    item(it, "Share", function() S.ShareQuest(it.qid) end)
  end
  share.note:SetText("Ask sends them a one-click Share prompt. The game decides if a quest can be shared, and you need to be near each other.")
  share:SetHeight(-y + 44)
  share:Show()
end
function S.UI_ShareRefresh() if share and share:IsShown() then S.UI_ShareWindow(share.name) end end

-- When a partner joins the group: open the sharing window (after combat if needed).
local pendingJoin
function S.OnPartnerJoined(name)
  if not S.Opt("groupHints", true) then return end
  local function open()
    local c = S.ShareCandidates(name)
    if #c.theirs == 0 and #c.mine == 0 then return end
    S.UI_ShareWindow(name)
  end
  if S.InCombat() then pendingJoin = name return end
  -- give their snapshot a moment to arrive
  C_Timer.After(3, open)
end
-- Fresh data from a partner: refresh whatever shows it
function S.OnPartnerData(name)
  S.UI_ShareRefresh()
  if S.UpdateQuestLogStatus then pcall(S.UpdateQuestLogStatus) end
end

-- "X would like you to share <quest>": one click to share
local ask
local askQueue = {}
local function showAsk()
  local item = table.remove(askQueue, 1)
  if not item then return end
  if not ask then
    ask = Window("SterlingQuestShareAsk", 300, 96, "Share request")
    ask:SetFrameStrata("DIALOG")
    ask.text = ask:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); ask.text:SetPoint("TOPLEFT", 14, -38); ask.text:SetPoint("RIGHT", -14, 0); ask.text:SetJustifyH("LEFT")
    ask.yes = Button(ask, "Share", 76); ask.no = Button(ask, "Not now", 76)
    ask.yes:SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -3, 10); ask.no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 3, 10)   -- centred pair, same as the invite prompt
    ask:HookScript("OnHide", function() C_Timer.After(0.2, showAsk) end)
  end
  ask.text:SetText("|cff8ab8ff" .. S.PartnerLabel(item.from) .. "|r would like you to share\n" .. S.TEXT_HEX .. S.QuestName(item.qid) .. "|r")
  ask.yes:SetScript("OnClick", function() ask:Hide(); S.ShareQuest(item.qid) end)
  ask.no:SetScript("OnClick", function() ask:Hide() end)
  ask.yes:SetEnabled(S.log[item.qid] ~= nil)
  ask:SetHeight(70 + (ask.text:GetStringHeight() or 24))
  ask:Show()
end
function S.UI_ShareAsk(from, qid)
  for _, it in ipairs(askQueue) do if it.from == from and it.qid == qid then return end end
  askQueue[#askQueue + 1] = { from = from, qid = qid }
  if ask and ask:IsShown() then return end
  if S.InCombat() then return end
  showAsk()
end
local regen = CreateFrame("Frame"); regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
  if pendingJoin then local n = pendingJoin; pendingJoin = nil; S.OnPartnerJoined(n) end
  if #askQueue > 0 and not (ask and ask:IsShown()) then showAsk() end
  if S.AfterCombat then S.Safe("after combat", S.AfterCombat) end
end)


-- Add a partner: type a name, or invite someone Sterling found in your party, guild or friends.
local SRC_LABEL = { party = "In your party", guild = "In your guild", friend = "On your friends list", other = "Found elsewhere" }
local function classRGB(cls)
  local c = cls and cls ~= "" and ((type(C_ClassColor) == "table" and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(cls)) or (type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[cls]))
  if c and c.r then return c.r, c.g, c.b end
  return .6, .62, .7
end
function S.UI_AddPartner()
  if not addWin then
    addWin = Window("SterlingQuestAddPartner", 330, 400, "Add a partner")
    local f = addWin
    f.eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.eb:SetSize(204, 22); f.eb:SetPoint("TOPLEFT", 19, -38); f.eb:SetAutoFocus(false); f.eb:SetMaxLetters(30)
    f.go = Button(f, "Add", 70); f.go:SetPoint("TOPRIGHT", -14, -38)
    local function addTyped()
      local n = (f.eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if n == "" then return end
      if not S.FindPartner(n) and S.PartnersFull() then f.refresh() return end
      SlashCmdList.STERLINGQUEST("partner " .. n); S.Invite(n); f.eb:SetText(""); f.eb:ClearFocus()
    end
    f.go:SetScript("OnClick", addTyped); f.eb:SetScript("OnEnterPressed", addTyped); f.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.hint = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.hint:SetPoint("TOPLEFT", 14, -66); f.hint:SetPoint("RIGHT", -14, 0); f.hint:SetJustifyH("LEFT"); f.hint:SetTextColor(.6, .64, .74)
    f.hint:SetText("Adds them on your side and sends an invite. They need to accept (or add you back on an older version).")
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.head:SetPoint("TOPLEFT", 14, -96); f.head:SetText("Found with Sterling"); f.head:SetTextColor(S.LabelColor())
    f.look = Button(f, "Look now", 70); f.look:SetPoint("TOPRIGHT", -14, -92); f.look:SetScript("OnClick", function() S.DiscoverNow(); C_Timer.After(4, function() if f:IsShown() then f.refresh() end end) end)
    f.rows = {}
    for i = 1, 11 do
      local r = CreateFrame("Frame", nil, f); r:SetHeight(24); r:SetPoint("TOPLEFT", 14, -114 - (i - 1) * 25); r:SetPoint("RIGHT", -14, 0)
      r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, .04)
      r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetSize(8, 8); r.dot:SetPoint("LEFT", 6, 0)
      r.name = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.name:SetPoint("LEFT", 20, 0); r.name:SetJustifyH("LEFT")
      r.meta = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.meta:SetPoint("LEFT", r.name, "RIGHT", 8, 0); r.meta:SetTextColor(.6, .62, .7); r.meta:SetPoint("RIGHT", -92, 0); r.meta:SetJustifyH("LEFT"); r.meta:SetWordWrap(false)
      r.inv = Button(r, "Invite", 58); r.inv:SetPoint("RIGHT", -24, 0)
      r.x = CreateFrame("Button", nil, r); r.x:SetSize(18, 18); r.x:SetPoint("RIGHT", -2, 0)
      r.x.t = r.x:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.x.t:SetPoint("CENTER"); r.x.t:SetText("x"); r.x.t:SetTextColor(.6, .62, .7)
      r.x:SetScript("OnEnter", function(self) self.t:SetTextColor(1, .61, .57); GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Hide " .. (r.who or "")); GameTooltip:AddLine("Hides them here for good and ignores their invites and sync. Undo: Options > Sync > Hidden players.", 1, 1, 1, true); GameTooltip:Show() end)
      r.x:SetScript("OnLeave", function(self) self.t:SetTextColor(.6, .62, .7); GameTooltip:Hide() end)
      r.x:SetScript("OnClick", function() if r.who then S.Block(r.who); f.refresh() end end)
      r.head = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.head:SetPoint("LEFT", 4, -2); r.head:SetTextColor(.6, .64, .74)
      f.rows[i] = r
    end
    f.empty = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.empty:SetPoint("TOPLEFT", 14, -118); f.empty:SetPoint("RIGHT", -14, 0); f.empty:SetJustifyH("LEFT"); f.empty:SetTextColor(.6, .64, .74)
    f.empty:SetText("No one yet. Sterling says a quiet hello to your party, guild and online friends; anyone running it shows up here. Only people on the newest version answer.")
    f.more = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.more:SetPoint("BOTTOMLEFT", 14, 10); f.more:SetTextColor(.6, .64, .74)
    f.refresh = function()
      local list = S.FoundList and S.FoundList() or {}
      local full = S.PartnersFull()
      f.go:SetEnabled(not full)
      f.hint:SetText(full and ("|cffff9b92" .. S.Mark("bad") .. "Your Sync list is full (" .. S.MAX_PARTNERS .. " partners).|r Remove someone on the Sync tab to add another.")
        or "Adds them on your side and sends an invite. They need to accept (or add you back on an older version).")
      local lines, lastSrc = {}, nil
      for _, it in ipairs(list) do
        if it.src ~= lastSrc then lines[#lines + 1] = { head = SRC_LABEL[it.src] or "Found" }; lastSrc = it.src end
        lines[#lines + 1] = it
      end
      f.empty:SetShown(#list == 0)
      for i, r in ipairs(f.rows) do
        local it = lines[i]
        r:SetShown(it ~= nil)
        if it then
          local isHead = it.head ~= nil
          r.bg:SetShown(not isHead); r.dot:SetShown(not isHead); r.name:SetShown(not isHead); r.meta:SetShown(not isHead); r.x:SetShown(not isHead); r.inv:SetShown(not isHead)
          r.head:SetShown(isHead)
          if isHead then r.head:SetText(it.head); r.who = nil
          else
            r.who = it.name
            local cr, cg, cb = classRGB(it.class)
            r.dot:SetColorTexture(cr, cg, cb, 1)
            r.name:SetText(it.name); r.name:SetTextColor(.35 + .65 * cr, .35 + .65 * cg, .35 + .65 * cb)
            local cmp = S.CompareVer and S.CompareVer(it.ver, S.ADDON_VER) or 0
            local verTxt = it.ver and ((cmp < 0 and "|cffff9b92v" .. it.ver .. " (older)|r") or ("v" .. it.ver)) or ""
            r.meta:SetText((it.level and ("lvl " .. it.level .. " · ") or "") .. verTxt)
            if it.partner then
              r.inv:SetText("Added"); r.inv:Disable(); r.x:Hide()
            elseif S.PendingInvite and S.PendingInvite(it.name) then
              r.inv:SetText("Sent"); r.inv:Disable()
            else
              r.inv:SetText("Invite"); r.inv:SetEnabled(not full)
              r.inv:SetScript("OnClick", function() S.Invite(it.name); f.refresh() end)
            end
          end
        end
      end
      f.more:SetText(#lines > #f.rows and ("+" .. (#lines - #f.rows) .. " more not shown") or "")
    end
  end
  addWin:Show(); addWin.refresh()
end

-- The prompt the other player sees when you invite them.
local invQueue = {}
local function showInvite()
  local it = table.remove(invQueue, 1)
  if not it then return end
  if not invWin then
    invWin = Window("SterlingQuestInvite", 300, 104, "Sync invite")
    invWin:SetFrameStrata("DIALOG")
    invWin.text = invWin:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); invWin.text:SetPoint("TOPLEFT", 14, -38); invWin.text:SetPoint("RIGHT", -14, 0); invWin.text:SetJustifyH("LEFT")
    invWin.yes = Button(invWin, "Accept", 76); invWin.no = Button(invWin, "Not now", 76)
    invWin.yes:SetPoint("BOTTOMRIGHT", invWin, "BOTTOM", -3, 10); invWin.no:SetPoint("BOTTOMLEFT", invWin, "BOTTOM", 3, 10)
    invWin:HookScript("OnHide", function() C_Timer.After(0.3, showInvite) end)
  end
  invWin.text:SetText("|cffffd100" .. it.from .. "|r wants to sync quest logs with you.\nAccept adds each of you to the other's Sync list.")
  invWin.yes:SetScript("OnClick", function() invWin.answered = true; invWin:Hide(); S.AcceptInvite(it.from, it.code) end)
  invWin.no:SetScript("OnClick", function() invWin.answered = true; invWin:Hide(); S.DeclineInvite(it.from, it.code) end)
  invWin:SetHeight(70 + (invWin.text:GetStringHeight() or 24))
  invWin:Show()
end
function S.UI_InvitePrompt(from, code)
  for _, it in ipairs(invQueue) do if it.from == from then it.code = code return end end
  invQueue[#invQueue + 1] = { from = from, code = code }
  if invWin and invWin:IsShown() then return end
  if S.InCombat() then return end   -- shown when the fight is over
  showInvite()
end
-- Things held back during a fight: pop-ups, and the Catch-up list (it is the one heavy rebuild).
local dirtyAfterCombat = false
function S.AfterCombat()
  if #invQueue > 0 and not (invWin and invWin:IsShown()) then showInvite() end
  if dirtyAfterCombat then dirtyAfterCombat = false; S.UI_Update() end
  if S.GuideAfterCombat then S.GuideAfterCombat() end
end
local lastCatchup = 0
local function catchupNow()
  if not S.InCombat() then return true end
  if GetTime() - lastCatchup >= 3 then lastCatchup = GetTime(); return true end
  dirtyAfterCombat = true
  return false
end

local function BuildMain()
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Sterling", "Version")) or (GetAddOnMetadata and GetAddOnMetadata("Sterling", "Version")) or "?"
  main = Window("SterlingQuestFrame", 370, 330, "Sterling Quest Sync")
  -- the version sits beside the title in the small font, so the title row has room for Options and Help
  main.ver = main.head:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); main.ver:SetText("v" .. ver); main.ver:SetTextColor(.53, .57, .65)
  -- tabs: Blizzard's bottom tabs in the WoW skin (hanging under the window), our own strip in navy
  local TABS = { { "catchup", "Catch-up" }, { "path", "Path" }, { "sessions", "Sessions" }, { "sync", "Sync" } }
  local blizz = {}
  for i, t in ipairs(TABS) do
    local b = S.BlizzTab(main, "SterlingQuestFrameTab" .. i, i, t[2])
    if not b then blizz = nil break end
    b:SetScript("OnClick", function() S.UI_Tab(t[1]) end)
    blizz[i] = b; tabs[t[1]] = b; tabOrder[t[1]] = i
  end
  local pagesTop = -34
  if blizz then
    main.Tabs = blizz; main.numTabs = #blizz
    S.LayoutTabs(main, blizz)
  else
    pagesTop = -64
    local xs = { 8, 94, 172, 254 }; local ws = { 84, 76, 80, 76 }
    for i, t in ipairs(TABS) do Tab(main, t[1], t[2], xs[i], ws[i]) end
    local sep = main:CreateTexture(nil, "ARTWORK"); sep:SetPoint("TOPLEFT", 1, -54); sep:SetPoint("TOPRIGHT", -1, -54); sep:SetHeight(1); sep:SetColorTexture(S.Navy(.23, .27, .37))
    main.sep = sep
  end
  S.UI_TabShown = function(key, shown)
    if not tabs[key] then return end
    tabs[key]:SetShown(shown)
    if rawget(main, "Tabs") then S.LayoutTabs(main, main.Tabs) end
  end
  -- sunken content panel behind the pages (WoW skin)
  local inset = S.Inset(main, nil)
  if inset then inset:SetPoint("TOPLEFT", 6, pagesTop + 2); inset:SetPoint("BOTTOMRIGHT", -6, 6); inset:SetFrameLevel(main:GetFrameLevel() + 1); main.inset = inset end
  main.pagesTop = pagesTop
  -- recording indicator in the title bar (used in the compact view); click toggles recording
  main.recbtn = CreateFrame("Button", nil, main); main.recbtn:SetSize(70, 20); main.recbtn:SetPoint("LEFT", main.title, "LEFT", 70, 0)
  main.recbtn.dot = main.recbtn:CreateTexture(nil, "ARTWORK"); main.recbtn.dot:SetSize(9, 9); main.recbtn.dot:SetPoint("LEFT", 0, 0); main.recbtn.dot:SetColorTexture(.5, .5, .55, 1)
  main.recbtn.text = main.recbtn:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); main.recbtn.text:SetPoint("LEFT", main.recbtn.dot, "RIGHT", 5, 0); main.recbtn.text:SetTextColor(.7, .74, .84)
  main.recbtn:SetScript("OnClick", function() S.ConfirmStop() end)
  main.recbtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(S.IsRecording() and "Recording. Click to stop." or "Not recording. Click to start."); GameTooltip:Show() end)
  main.recbtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.recbtn:Hide()
  -- version warning strip, hangs below the window so no tab has to make room for it
  main.notice = Box(main); main.notice:SetPoint("BOTTOMLEFT", main, "TOPLEFT", 0, 2); main.notice:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", 0, 2); main.notice:SetHeight(24)
  main.notice:SetBackdropColor(.45, .12, .12, .95); main.notice:SetBackdropBorderColor(1, .4, .4, .6)
  main.notice.text = main.notice:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); main.notice.text:SetPoint("LEFT", 10, 0); main.notice.text:SetPoint("RIGHT", -10, 0); main.notice.text:SetJustifyH("LEFT"); main.notice.text:SetTextColor(1, .85, .85); main.notice.text:SetWordWrap(false)
  main.notice:Hide()
  for _, key in ipairs({ "path", "sessions", "sync", "catchup" }) do
    local p = CreateFrame("Frame", nil, main); p:SetPoint("TOPLEFT", 12, main.pagesTop - 4); p:SetPoint("BOTTOMRIGHT", -12, 12); p:Hide()
    p:SetFrameLevel(main:GetFrameLevel() + 3)
    pages[key] = p
  end
  BuildPath(pages.path)
  builders.sessions, builders.sync, builders.catchup = BuildSessions, BuildSync, BuildCatchup
  if tabs.catchup then S.UI_TabShown("catchup", S.Opt("catchupTab", true)) end
  if not S.Opt("catchupTab", true) then current = "path" end
  -- Options button in the title bar, left of the X
  main.optBtn = Button(main.top, "Options", 62); main.optBtn:SetPoint("RIGHT", main.close, "LEFT", -4, 0); main.optBtn:SetScale(.85)
  main.optBtn:SetScript("OnClick", function() S.UI_Options() end)
  -- Help: a "?" beside Options, same height and scale so the two read as a pair
  main.helpBtn = Button(main.top, "?", 22); main.helpBtn:SetPoint("RIGHT", main.optBtn, "LEFT", -3, 0); main.helpBtn:SetScale(.85)
  main.helpBtn:SetScript("OnClick", function() if S.UI_Help then S.UI_Help() end end)
  main.helpBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Help"); GameTooltip:AddLine("How everything works, the tour, and troubleshooting.", 1, 1, 1, true); GameTooltip:Show() end)
  main.helpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.titleFull = main.title:GetText()
  -- title on the left, then (right-aligned) the version, Help, Options and the X: nothing can run into anything
  main.ver:SetPoint("RIGHT", main.helpBtn, "LEFT", -8, 0)
  main.right:ClearAllPoints(); main.right:SetPoint("RIGHT", main.ver, "LEFT", -8, 0)
  main:Restore()
  S.UI_ApplyOptions()
  -- live timer while recording
  local acc = 0
  main:SetScript("OnUpdate", function(_, dt) acc = acc + dt; if acc > 1 then acc = 0; if main:IsShown() and (S.IsRecording() or current == "sync") then S.UI_Update() end end end)
end

local function StepText(st)
  if st.kind == "objective" then return st.text or ((st.quest or "Quest") .. " |cff8a93a8objective|r") end
  if st.kind == "note" then return st.text or "" end
  if st.kind == "dungeon" then return "Ran " .. (st.text or "dungeon") end
  if st.kind == "flight" or st.kind == "ride" then return st.from and (st.from .. " to " .. (st.text or "")) or (st.text or "") end
  if st.kind == "hearth" then return "to " .. (st.text or "") .. ((st.from and st.from ~= "Hearthstone") and ("  (" .. st.from .. ")") or "") end
  if st.kind == "travel" then return st.text or st.subzone or "" end
  if st.kind == "ding" then return "Level " .. st.level end
  return st.quest or ""
end

local QUEST_KINDS = { pickup = true, turnin = true, deliver = true, ["do"] = true, objective = true }
local function UpdatePath(page)
  do
    local card = page.card
    if page.undo then
      local any = (S.lastJump and #S.lastJump > 0) or (SterlingQuestDB.manual and next(SterlingQuestDB.manual) ~= nil)
      page.undo:SetEnabled(any and true or false)
    end
    if card and card.done then card.done:SetEnabled(S.steps[S.CurrentIndex()] ~= nil) end
    if page.auto then page.auto:SetChecked(S.Opt("arrowopt", true)) end
  end
  local rb = page.rec
  local rec = S.Recording()
  if rec then
    rb:SetBackdropColor(1, .3, .3, .1); rb:SetBackdropBorderColor(1, .4, .4, .35); rb.dot:Show()
    rb.text:SetText("Recording"); rb.text:SetTextColor(S.TR, S.TG, S.TB)
    rb.meta:SetText(S.Duration(rec) .. "  |  " .. #rec.events .. " events")
    rb.btn:SetText("Stop"); rb.note:Show()
  else
    rb:SetBackdropColor(1, 1, 1, .03); rb:SetBackdropBorderColor(.23, .27, .37, 1); rb.dot:Hide()
    rb.text:SetText("Not recording"); rb.text:SetTextColor(.56, .6, .7)
    rb.meta:SetText("")
    rb.btn:SetText("Record"); rb.note:Hide()
  end
  if rec then main.recbtn.dot:SetColorTexture(1, .3, .3, 1); main.recbtn.text:SetText("|cffff8080REC|r " .. S.Duration(rec))
  else main.recbtn.dot:SetColorTexture(.5, .5, .55, 1); main.recbtn.text:SetText("not recording") end
  main.recbtn:SetWidth(main.recbtn.text:GetStringWidth() + 16)
  local sess = S.FindSession(SterlingQuestDB.following)
  page.clear:SetShown(sess ~= nil or S.catchupLabel ~= nil or #S.steps > 0)
  local i = S.CurrentIndex()
  local st = S.steps[i]
  main.right:SetText("")
  local stepTxt = st and ("  |cff8a93a8step " .. i .. " of " .. #S.steps .. "|r") or ""
  if sess then
    page.follow:SetText("Following |cff8ab8ff" .. sess.char .. " - " .. sess.name .. "|r" .. stepTxt)
    local d = S.TrailDistance()
    if d then
      page.chip:Show(); page.chip:Set(d < 2.5 and "turnin" or "skip"); page.chip.text:SetText(d < 2.5 and "ON TRAIL" or ((S.ColorBlind() and "! " or "") .. "OFF TRAIL"))
      page.chip:SetWidth(page.chip.text:GetStringWidth() + 14)
      page.dist:SetText(d < 2.5 and "" or ("%.1f away"):format(d))
    else page.chip:Hide(); page.dist:SetText("trail in another zone") end
  elseif S.catchupLabel then
    page.follow:SetText("|cff8ab8ff" .. S.catchupLabel .. "|r" .. stepTxt); page.chip:Hide(); page.dist:SetText("")
  else
    page.follow:SetText("Not following a session"); page.chip:Hide(); page.dist:SetText("")
  end
  local card = page.card
  if st then
    card.pill:Set(st.kind); card.q:SetText(StepText(st))
    local bits = {}
    if st.npc and st.npc ~= "" then bits[#bits + 1] = st.npc end
    if st.kind == "objective" and st.quest then bits[#bits + 1] = st.quest end
    if st.t then bits[#bits + 1] = "at " .. S.Clock(st.t) end
    card.npc:SetText(table.concat(bits, "  |cff55607a|||r  "))
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if st.map and st.kind ~= "dungeon" then
      local zone = S.MapName(st.map)
      if here and here ~= st.map then zone = "|cfff3c56b" .. zone .. " (not here)|r" else zone = "|cff8ab8ff" .. zone .. "|r" end
      local rest = card.npc:GetText() or ""
      card.npc:SetText(zone .. (rest ~= "" and ("  |cff55607a|||r  " .. rest) or ""))
    end
    card.way:SetText(st.x and ("/way " .. st.x .. " " .. st.y) or "")
    card.wayBtn:SetShown(st.x ~= nil)
    page.empty:SetText("")
    local w = (i - 1) / math.max(1, #S.steps) * card:GetWidth(); page.prog:SetShown(w >= 1); page.prog:SetWidth(math.max(1, w))
  elseif #S.steps == 0 then
    card.pill:Set("travel"); card.q:SetText(sess and "Nothing left to do" or "No path yet"); card.way:SetText("")
    card.npc:SetText(sess and "You've done everything in this session." or "Import a friend's session string, or pick one in Sessions and press Follow.")
    page.prog:SetWidth(1); page.prog:Hide()
  else
    card.pill:Set("ding"); card.q:SetText("Caught up"); card.npc:SetText("Every step in this session is done."); card.way:SetText("")
    page.prog:SetWidth(card:GetWidth()); page.prog:Show()
  end
  local shown = 0
  if SterlingQuestDB.opts.expanded == nil then SterlingQuestDB.opts.expanded = true end
  local compact = not SterlingQuestDB.opts.expanded
  -- compact: no tabs, no record bar; the "Following" line sits right under the title
  if page.compactState ~= compact then
    page.compactState = compact
    for _, b in pairs(tabs) do b:SetShown(not compact) end
    if main.sep then main.sep:SetShown(not compact) end
    if main.inset then main.inset:SetPoint("TOPLEFT", 6, compact and -30 or (main.pagesTop + 2)) end
    page.rec:SetShown(not compact)
    main.recbtn:SetShown(compact)
    -- the small view shares the title row with the recording timer: shorter title, no "?" (Help is in Options)
    main.title:SetText(compact and "Sterling" or main.titleFull)
    main.helpBtn:SetShown(not compact)
    main.ver:ClearAllPoints(); main.ver:SetPoint("RIGHT", compact and main.optBtn or main.helpBtn, "LEFT", -8, 0)
    main.recbtn:ClearAllPoints(); main.recbtn:SetPoint("LEFT", main.title, "LEFT", (main.title:GetStringWidth() or 54) + 10, 0)
    page.tlline:SetShown(not compact)
    page:ClearAllPoints()
    if compact then
      page:SetPoint("TOPLEFT", 12, -38); page:SetPoint("BOTTOMRIGHT", -12, 12)
      page.follow:ClearAllPoints(); page.follow:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -2); page.follow:SetPoint("RIGHT", page.dist, "LEFT", -8, 0)
      page.chip:ClearAllPoints(); page.chip:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -1)
      page.card:ClearAllPoints(); page.card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -20); page.card:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -20)
    else
      page:SetPoint("TOPLEFT", 12, main.pagesTop - 4); page:SetPoint("BOTTOMRIGHT", -12, 12)
      page.follow:ClearAllPoints(); page.follow:SetPoint("TOPLEFT", page.rec, "BOTTOMLEFT", 4, -9); page.follow:SetPoint("RIGHT", page.dist, "LEFT", -8, 0)
      page.chip:ClearAllPoints(); page.chip:SetPoint("RIGHT", page.rec, "BOTTOMRIGHT", 0, -15)
      page.card:ClearAllPoints(); page.card:SetPoint("TOPLEFT", page.rec, "BOTTOMLEFT", 0, -28); page.card:SetPoint("TOPRIGHT", page.rec, "BOTTOMRIGHT", 0, -28)
    end
    page.b4:SetShown(not compact)   -- Import only in the full view
    page.b3:ClearAllPoints(); if compact then page.b3:SetPoint("BOTTOMRIGHT", 0, 0) else page.b3:SetPoint("RIGHT", page.b4, "LEFT", -4, 0) end
  end
  local maxRows = SterlingQuestDB.opts.expanded and pathRowsFit(page) or SHOW_SMALL
  local gap = SterlingQuestDB.opts.expanded and (page.rowGap or 18) or 18
  if page.lastGap ~= gap then
    page.lastGap = gap
    for i, r in ipairs(page.rows) do r:ClearAllPoints(); r:SetPoint("TOPLEFT", page.card, "BOTTOMLEFT", 14, -16 - (i - 1) * gap); r:SetPoint("RIGHT", page, "RIGHT", -12, 0) end
  end
  page.listArea:SetHeight(math.max(18, maxRows * gap))
  page.more:SetText(SterlingQuestDB.opts.expanded and "Less" or "More")
  -- list window: by default the steps after the current one; wheel to look back at done steps
  if page.lastIndex ~= i then page.scrolled = false; page.lastIndex = i end
  local top = (page.scrolled and page.top) or (i + 1)
  top = math.max(1, math.min(top, math.max(1, #S.steps - maxRows + 1)))
  page.top = top
  for r = 1, ROWS do
    local idx = top + r - 1
    local nx = r <= maxRows and S.steps[idx] or nil
    local row = page.rows[r]
    row.step = nx
    if nx then
      shown = r; row:Show(); row.pill:Set(nx.kind)
      -- a quest step further down that you've already finished (out of order) says done too
      local isDone = idx < i or (idx > i and nx.qid ~= nil and QUEST_KINDS[nx.kind] and S.StepSatisfied(nx, idx) and true or false)
      row.done, row.isCurrent = isDone, (idx == i)
      row.cur:SetShown(idx == i)
      local prevMap = (S.steps[idx - 1] or {}).map
      local zoneTag = (nx.map and nx.kind ~= "dungeon" and nx.map ~= prevMap) and ("  |cff8ab8ff" .. S.MapName(nx.map) .. "|r") or ""
      row.text:SetText(StepText(nx) .. ((nx.kind == "objective" and nx.text and nx.quest) and ("  |cff8a93a8" .. nx.quest .. "|r") or "") .. (nx.npc and nx.npc ~= "" and ("  |cff8a93a8" .. nx.npc .. "|r") or "") .. zoneTag)
      row.time:SetText(isDone and ("|cff7ee2a2" .. S.Mark("good") .. "done|r") or (nx.t and S.Clock(nx.t) or ""))
      row:SetAlpha(isDone and .55 or 1)
      row.dotl:SetVertexColor(isDone and .3 or .33, isDone and .6 or .38, isDone and .4 or .5, 1)
    else row:Hide() end
  end
  if maxRows > 0 then page.sb:Set(top - 1, maxRows, #S.steps) else page.sb:Hide() end
  -- the "earlier / more" line is gone: the scroll bar shows it, and the follow line says "step x of y"
  page.scrollHint:SetText("")
  page.tlline:SetHeight(math.max(1, shown * (page.lastGap or 18) - 6))
  if compact then main:SetHeight(38 + 20 + 58 + 8 + 21 + 12)
  else main:SetHeight(STD_H) end
end

local function UpdateSessions(page)
  local rec = S.Recording()
  page.recbtn:SetText(rec and "Stop" or "Record")
  page.recstate:SetText(rec and ("|cffff6060Recording|r " .. S.Duration(rec)) or "Not recording")
  local list = SterlingQuestDB.sessions
  page.rest:SetShown(SterlingQuestDB.trash ~= nil and #SterlingQuestDB.trash > 0)
  page.count:SetText(#list .. (#list == 1 and " session" or " sessions"))
  local shown = 0
  page.offset = math.max(0, math.min(page.offset or 0, math.max(0, #list - SROWS)))
  page.sb:Set(page.offset, SROWS, #list)
  for i = 1, SROWS do
    local r, sess = page.rows[i], list[page.offset + i]
    r.sess = sess
    if sess then
      shown = i; r:Show()
      local mine = not sess.imported
      r.accent:SetColorTexture(mine and .54 or .49, mine and .72 or .89, mine and 1 or .64, 1)
      r.nm:SetText(sess.name)
      r.meta:SetText(S.SessionSummary(sess))
      r.who:SetText(mine and "|cff8ab8ffyou|r" or ("|cff7ee2a2" .. sess.char .. "|r"))
      local following = SterlingQuestDB.following == sess.id
      r.b1:SetText(mine and "Export" or (following and "Stop" or "Follow"))
      r.b1:SetScript("OnClick", function()
        if mine then S.UI_ShowExport(sess.id) elseif following then S.StopFollowing(); S.UI_Update() else S.FollowSession(sess, true); S.UI_Tab("path") end
      end)
      r.b2:SetScript("OnClick", function() S.MapSetSession(sess); S.MapToggle() end)
    else r:Hide() end
  end
  main:SetHeight(STD_H)
end

local function Line(page, idx)
  local l = page.lines[idx]
  if not l then l = page.content:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); l:SetWidth(300); l:SetJustifyH("LEFT"); page.lines[idx] = l end
  l:Show(); return l
end

local function UpdateCompare(page)
  for _, l in ipairs(page.lines) do l:Hide() end
  local d = S.Diff()
  local y, n = -2, 0
  local function add(text, r, g, b, indent)
    n = n + 1; local l = Line(page, n); l:ClearAllPoints(); l:SetPoint("TOPLEFT", page.content, "TOPLEFT", indent or 0, y)
    l:SetText(text); l:SetTextColor(r, g, b); y = y - (l:GetStringHeight() + 4)
  end
  local nsn = 0; for _ in pairs(S.snaps) do nsn = nsn + 1 end
  page.pick:Refresh()
  if not d then
    page.who:SetText("Compare: nobody yet")
    add("No partner data yet.", .9, .9, .9)
    add("Add a partner in the Sync tab, or import a quest-log export.", .64, .67, .75)
  else
    local p = S.partner
    page.who:SetText(("You (lvl %d) vs %s (lvl %d), %s"):format(UnitLevel("player"), p.name, p.level, p.source == "live" and "live" or (p.source == "import" and "imported" or ("saved " .. ago(p.at)))))
    y = y - 2
    local function section(title, list, fmt, r, g, b)
      add(title .. "  (" .. #list .. ")", r, g, b)
      if #list == 0 then add("nothing", .5, .55, .65, 12) end
      for _, q in ipairs(list) do add(fmt(q), .85, .87, .92, 12) end
      y = y - 8
    end
    -- current quest logs only; finished-quest history lives in Everyone
    section("In their log, not yours", d.theyHave, function(q)
      local done = S.IsFlaggedDone(q.qid)
      return q.title .. (q.complete and "  |cff7ee2a2(they're ready to turn in)|r" or "") .. (done and "  |cff8a93a8(you finished it)|r" or "") end, S.AR, S.AG, S.AB)
    section("In your log, not theirs", d.youHave, function(q)
      return q.title .. (q.complete and "  |cff7ee2a2(you're ready to turn in)|r" or "") .. (p.completed[q.qid] and "  |cff8a93a8(they finished it)|r" or "") end, .95, .77, .42)
    add("Both have, different progress  (" .. #d.shared .. ")", .76, .66, 1)
    if #d.shared == 0 then add("nothing", .5, .55, .65, 12) end
    for _, q in ipairs(d.shared) do
      add(q.title .. (q.theyDone and not q.youDone and "  |cff7ee2a2(they're ready to turn in)|r" or (q.youDone and not q.theyDone and "  |cfff3c56b(you're ready to turn in)|r" or "")), .85, .87, .92, 12)
      for _, o in ipairs(q.diff) do add("you: " .. tostring(o.you or "-") .. "   they: " .. tostring(o.they or "-"), .6, .64, .74, 24) end
    end
    y = y - 8
    local ahead, behind = #d.theyFinished, #d.youFinished
    add(("History: they've finished %d quest%s you haven't, you've finished %d they haven't. Everyone shows them."):format(ahead, ahead == 1 and "" or "s", behind), .5, .55, .65)
  end
  page.content:SetHeight(-y + 10)
  page.foot:SetText(SterlingQuestDB.sync and "Live sync on" or "Live sync off")
end

-- The strip above the window. Red: a partner can't sync with you until someone updates.
-- Amber: everything still syncs, but your copy is the older one.
local function versionNotice()
  local red, newer = {}, nil
  for _, p in ipairs(S.Partners()) do
    local vs, who, ver = S.VersionState(p.name)
    if vs == "nosync" then red[#red + 1] = S.PartnerLabel(p.name) .. (who == "they" and " needs to update" or " is ahead of you")
    elseif vs == "newer" and not newer then newer = { S.PartnerLabel(p.name), ver } end
  end
  local n = main.notice
  if #red > 0 then
    n:SetBackdropColor(.45, .12, .12, .95); n:SetBackdropBorderColor(1, .4, .4, .6); n.text:SetTextColor(1, .85, .85)
    n.text:SetText(S.Mark("bad") .. "Can't sync: update needed.  " .. table.concat(red, ", "))
    n:Show()
  elseif newer then
    n:SetBackdropColor(.4, .28, .06, .95); n:SetBackdropBorderColor(1, .78, .3, .6); n.text:SetTextColor(1, .92, .75)
    n.text:SetText(S.Mark("warn") .. "Outdated: " .. newer[1] .. " has a newer Sterling (v" .. tostring(newer[2]) .. "). Sync still works; update yours.")
    n:Show()
  else n:Hide() end
end

-- Screenshot mode tag: a clear amber "TEST DATA" in the title bar while /st testmode is on.
function S.UI_TestTag()
  if not main then return end
  if not main.testTag then
    -- just above the window, so it never covers the title or the buttons
    main.testTag = main.head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    main.testTag:SetPoint("BOTTOM", main, "TOP", 0, 4); main.testTag:SetTextColor(.95, .62, .25)
    main.testTag:SetText("TEST DATA  ·  nothing is saved or sent")
  end
  main.testTag:SetShown(S.testMode ~= nil)
end
function S.UI_Update()
  if main and (main.testTag or S.testMode) then S.UI_TestTag() end
  if not main or not main:IsShown() then if SterlingQuestMinimapButton then S.UI_MinimapState() end return end
  versionNotice()
  -- a tab that hasn't been built yet (right after Apply rebuilds the windows) gets built before it's filled in
  if builders[current] and pages[current] then local b = builders[current]; builders[current] = nil; b(pages[current]) end
  if current == "path" then S.Safe("the Path tab", UpdatePath, pages.path)
  elseif current == "sessions" then S.Safe("the Sessions tab", UpdateSessions, pages.sessions)
  elseif current == "sync" then S.Safe("the Sync tab", UpdateSync, pages.sync)
  elseif current == "catchup" then if catchupNow() then S.Safe("the Catch-up tab", UpdateCatchup, pages.catchup) end
  end
  if pages.compare and pages.compare:IsShown() then UpdateCompare(pages.compare) end
  if addWin and addWin:IsShown() and addWin.refresh then S.Safe("the Add window", addWin.refresh) end
  if pages.options and pages.options:IsShown() then
    local pg = pages.options.inner
    if pg.trashCount then pg.trashCount() end
    if pg.packText then pg.packText() end
  end
  refreshProfile()
  S.UI_MinimapState()
end

-- Compare: its own window, opened from a partner's right-click menu (or /st compare)
local cmpWin
function S.UI_Compare(name)
  if name then S.SelectPartner(name) end
  if not cmpWin then
    cmpWin = Window("SterlingQuestCompare", 370, STD_H, "Compare")
    local p = CreateFrame("Frame", nil, cmpWin); p:SetPoint("TOPLEFT", 12, -38); p:SetPoint("BOTTOMRIGHT", -12, 12)
    local inset = S.Inset(cmpWin); if inset then inset:SetPoint("TOPLEFT", 6, -30); inset:SetPoint("BOTTOMRIGHT", -6, 6); p:SetFrameLevel(inset:GetFrameLevel() + 2) end
    pages.compare = p
    BuildCompare(p)
    cmpWin:HookScript("OnShow", function() S.UI_Update() end)
  end
  cmpWin:Show(); S.UI_Update()
end

-- Options: a wider window of its own, so the page has room and scales
local optWin
function S.UI_Options()
  if not optWin then
    optWin = Window("SterlingQuestOptions", 480, 560, "Sterling Quest Sync options")
    local p = CreateFrame("Frame", nil, optWin); p:SetPoint("TOPLEFT", 12, -38); p:SetPoint("BOTTOMRIGHT", -10, 12)
    local inset = S.Inset(optWin); if inset then inset:SetPoint("TOPLEFT", 6, -30); inset:SetPoint("BOTTOMRIGHT", -6, 6); p:SetFrameLevel(inset:GetFrameLevel() + 2) end
    pages.options = p
    BuildOptions(p)
    -- tabs for the options window: Blizzard bottom tabs, or our strip in the title area
    p.tabButtons, p.tabIndex = {}, {}
    local blizz = {}
    for i, t in ipairs(OPT_TABS) do
      local b = S.BlizzTab(optWin, "SterlingQuestOptionsTab" .. i, i, t[2])
      if not b then blizz = nil break end
      b:SetScript("OnClick", function() p.ShowTab(t[1]) end)
      blizz[i] = b; p.tabButtons[t[1]] = b; p.tabIndex[t[1]] = i
    end
    if blizz then
      p.Tabs = blizz; p.numTabs = #blizz; optWin.Tabs = blizz; optWin.numTabs = #blizz
      p.Tabs = blizz
      S.LayoutTabs(optWin, blizz)
      -- tabs belong to the window, but selecting goes through the page: point it at the window's layout
      p.sterlingApplyTabs = function() if optWin.sterlingApplyTabs then optWin.sterlingApplyTabs() end end
    else
      p:SetPoint("TOPLEFT", 12, -64); if inset then inset:SetPoint("TOPLEFT", 6, -56) end
      local x = 8
      for _, t in ipairs(OPT_TABS) do
        local b = CreateFrame("Button", nil, optWin); b:SetSize(100, 24); b:SetPoint("TOPLEFT", x, -30); x = x + 104
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("CENTER"); b.text:SetText(t[2])
        b.line = b:CreateTexture(nil, "ARTWORK"); b.line:SetPoint("BOTTOMLEFT", 8, 0); b.line:SetPoint("BOTTOMRIGHT", -8, 0); b.line:SetHeight(2); b.line:SetColorTexture(S.AR, S.AG, S.AB, 1)
        b.own = true
        b:SetScript("OnClick", function() p.ShowTab(t[1]) end)
        p.tabButtons[t[1]] = b
      end
    end
    p.ShowTab("general")
    optWin:HookScript("OnShow", function() S.UI_Update() end)
    optWin:SetScale(S.Opt("scale", 1))
  end
  optWin:Show(); S.UI_Update()
end

function S.UI_Toggle(show)
  if show == nil then show = not main:IsShown() end
  if show then main:Show(); S.UI_Tab(current) else main:Hide() end
end

---------------------------------------------------------------------------
-- Everyone: one table, every quest anyone has or finished, a column per person
---------------------------------------------------------------------------
local every
local COLW = 78

local function cellFor(st)
  -- st: nil | { done=true } | { inLog=true, complete=bool, prog="3/8" }
  if not st then return "-", .45, .48, .56 end
  if st.done then return "done", .49, .89, .64 end
  if st.complete then return "ready", .95, .85, .4 end
  return st.prog or "in log", S.AR, S.AG, S.AB
end

function S.UI_Everyone()
  if not every then
    every = Window("SterlingQuestEveryone", 560, 420, "Everyone's quests")
    every:SetFrameStrata("HIGH")
    every.sf = CreateFrame("ScrollFrame", "SterlingQuestEveryoneScroll", every, "UIPanelScrollFrameTemplate")
    every.sf:SetPoint("TOPLEFT", 14, -70); every.sf:SetPoint("BOTTOMRIGHT", -36, 34)
    every.content = CreateFrame("Frame", nil, every.sf); every.content:SetSize(500, 10); every.sf:SetScrollChild(every.content)
    every.sf:SetScript("OnSizeChanged", function(self, w) every.content:SetWidth(w) end)
    every.head = CreateFrame("Frame", nil, every); every.head:SetPoint("TOPLEFT", 14, -38); every.head:SetPoint("RIGHT", -36, 0); every.head:SetHeight(30)
    every.head.bg = every.head:CreateTexture(nil, "BACKGROUND"); every.head.bg:SetAllPoints(); every.head.bg:SetColorTexture(S.Navy(.16, .2, .33))
    every.head.cols = {}
    every.rows = {}
    every.legend = every:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); every.legend:SetPoint("BOTTOMLEFT", 14, 10); every.legend:SetPoint("RIGHT", -14, 0); every.legend:SetJustifyH("LEFT"); every.legend:SetTextColor(.56, .6, .7)
    every.legend:SetText("|cff7ee2a2done|r  |cfff3c56bready|r (complete, not turned in)  |cff8ab8ff3/8|r in log  |cff737a88-|r never had it.   Rows: |cffff9b92red|r = someone finished it and you haven't,  |cfff3c56byellow|r = you finished it and someone hasn't.  Dim columns are logs older than a day.")
    -- in the title bar beside the X, on the same layer and at the same size as the main window's Options button
    every.refresh = Button(every.top, "Refresh", 62); every.refresh:SetPoint("RIGHT", every.close, "LEFT", -4, 0); every.refresh:SetScale(.85)
    every.refresh:SetScript("OnClick", function() S.RequestPartner(); S.UI_Everyone() end)
    every.right:ClearAllPoints(); every.right:SetPoint("RIGHT", every.refresh, "LEFT", -8, 0)
    every:HookScript("OnShow", function() S.UI_Everyone() end)
  end
  -- columns: you + every partner (enabled or not) that has a log, in partner order
  local people = { { name = S.MyName(), me = true } }
  local listed = {}
  for _, p in ipairs(S.Partners()) do listed[p.name] = true; if p.on and S.snaps[p.name] then people[#people + 1] = { name = p.name, snap = S.snaps[p.name] } end end
  for n, sn in pairs(S.snaps) do if not listed[n] then people[#people + 1] = { name = n, snap = sn } end end   -- imports with no partner entry
  for _, pp in ipairs(people) do if pp.snap then pp.stale = pp.snap.source ~= "live" and (time() - (pp.snap.at or 0)) > 86400 end end
  S.Refresh()
  -- gather quests
  local quests, order = {}, {}
  local function touch(qid, title)
    if not quests[qid] then quests[qid] = { qid = qid, title = title, st = {} }; order[#order + 1] = qid end
    if title and (not quests[qid].title or quests[qid].title:find("^Quest #")) then quests[qid].title = title end
    return quests[qid]
  end
  for qid, q in pairs(S.log) do
    local objs = {}
    if S.ObjectiveList then for _, o in ipairs(S.ObjectiveList(qid, q.index)) do local a, b = tostring(o.text or ""):match("(%d+)%s*/%s*(%d+)"); if a then objs[#objs + 1] = a .. "/" .. b end end end
    touch(qid, q.title).st[1] = { inLog = true, complete = q.complete, prog = #objs > 0 and table.concat(objs, " ") or nil }
  end
  for qid in pairs(S.completed) do touch(qid, S.QuestName(qid)).st[1] = { done = true } end
  for i = 2, #people do
    local sn = people[i].snap
    for qid, q in pairs(sn.log) do
      local objs = {}
      for _, t in ipairs(q.objs or {}) do local a, b = tostring(t):match("(%d+)%s*/%s*(%d+)"); if a then objs[#objs + 1] = a .. "/" .. b end end
      touch(qid, q.title).st[i] = { inLog = true, complete = q.complete, prog = #objs > 0 and table.concat(objs, " ") or nil }
    end
    for qid in pairs(sn.completed) do if not quests[qid] or not quests[qid].st[i] then touch(qid, nil).st[i] = { done = true } end end
  end
  -- only quests that matter: anyone has it in the log, or it's done by some but not all
  local rows = {}
  for _, qid in ipairs(order) do
    local q = quests[qid]
    local anyLog, doneCount = false, 0
    for i = 1, #people do local st = q.st[i]; if st and st.inLog then anyLog = true end; if st and st.done then doneCount = doneCount + 1 end end
    if anyLog or (doneCount > 0 and doneCount < #people) then
      local me = q.st[1]
      q.behind = (not (me and me.done)) and (function() for i = 2, #people do if q.st[i] and q.st[i].done then return true end end return false end)()
      q.ahead = (me and me.done) and (function() for i = 2, #people do if not (q.st[i] and q.st[i].done) then return true end end return false end)()
      q.title = q.title or S.QuestName(qid)
      rows[#rows + 1] = q
    end
  end
  table.sort(rows, function(a, b)
    local ra, rb = (a.behind and 0 or a.ahead and 1 or 2), (b.behind and 0 or b.ahead and 1 or 2)
    if ra ~= rb then return ra < rb end
    return (a.title or "") < (b.title or "")
  end)
  -- header
  for _, c in ipairs(every.head.cols) do c:Hide() end
  -- the window grows with the number of people (up to 860 wide), then the columns narrow, so ten
  -- partners still fit without anything running off the side
  local np = #people
  local W = math.max(560, math.min(860, 50 + 170 + np * COLW))
  every:SetWidth(W)
  local headW = W - 50
  local COLW = math.max(44, math.min(COLW, math.floor((headW - 150) / np)))
  local nameW = math.max(120, headW - COLW * np - 8)
  for i, pp in ipairs(people) do
    local c = every.head.cols[i]
    if not c then c = every.head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); every.head.cols[i] = c end
    c:ClearAllPoints(); c:SetPoint("LEFT", every.head, "LEFT", nameW + (i - 1) * COLW, 0); c:SetWidth(COLW); c:SetJustifyH("CENTER"); c:SetWordWrap(false)
    c:SetText(pp.me and "You" or (S.PartnerLabel(pp.name) .. (pp.stale and "\n|cff8891a5" .. agoShort(pp.snap.at) .. "|r" or ""))); c:SetTextColor(S.TR, S.TG, S.TB); c:Show()
  end
  for i = np + 1, #every.head.cols do every.head.cols[i]:Hide() end
  -- rows
  for _, r in ipairs(every.rows) do r:Hide() end
  local y = 0
  for n, q in ipairs(rows) do
    local r = every.rows[n]
    if not r then
      r = CreateFrame("Frame", nil, every.content); r:SetHeight(18)
      r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
      r.title = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.title:SetPoint("LEFT", 4, 0); r.title:SetJustifyH("LEFT"); r.title:SetWordWrap(false)
      r.cells = {}
      every.rows[n] = r
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0)
    r.title:SetWidth(nameW - 8); r.title:SetText((q.behind and S.Mark("bad") or (q.ahead and S.Mark("warn") or "")) .. q.title)
    if q.behind then r.bg:SetColorTexture(1, .3, .3, .12); r.title:SetTextColor(1, .75, .72)
    elseif q.ahead then r.bg:SetColorTexture(1, .8, .2, .1); r.title:SetTextColor(1, .92, .7)
    else r.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and .03 or 0); r.title:SetTextColor(.9, .92, 1) end
    for i = 1, #people do
      local c = r.cells[i]
      if not c then c = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.cells[i] = c end
      c:ClearAllPoints(); c:SetPoint("LEFT", r, "LEFT", nameW + (i - 1) * COLW, 0); c:SetWidth(COLW); c:SetJustifyH("CENTER")
      local t, cr, cg, cb = cellFor(q.st[i])
      if people[i].stale then cr, cg, cb = cr * .55, cg * .55, cb * .55 end
      c:SetText(t); c:SetTextColor(cr, cg, cb); c:Show()
    end
    for i = #people + 1, #r.cells do r.cells[i]:Hide() end
    r:Show()
    y = y + 19
  end
  every.content:SetHeight(math.max(y, 10))
  every.right:SetText(#rows .. " quests  |  " .. (#people - 1) .. " partner" .. (#people == 2 and "" or "s"))
  every:Show()
end

---------------------------------------------------------------------------
-- Right-click menus. Our own, because EasyMenu/UIDropDownMenu don't exist on this client.
-- Items: { text, func, isTitle, disabled, danger, menuList = { ...submenu items } }
---------------------------------------------------------------------------
S.menus = S.menus or {}
local function HideMenus(from) for l = from or 1, #S.menus do S.menus[l]:Hide() end end
S.HideMenus = HideMenus

local function MenuFrame(level)
  local m = S.menus[level]
  if m then return m end
  m = Box(UIParent, "SterlingQuestMenu" .. level)
  m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetFrameLevel(50 + level * 5); m:SetClampedToScreen(true); m:EnableMouse(true)
  m:SetBackdropColor(.1, .12, .17, .98); m:SetBackdropBorderColor(.33, .38, .5, 1)
  m.rows = {}
  m:Hide()
  if level == 1 then
    tinsert(UISpecialFrames, "SterlingQuestMenu1")
    m:SetScript("OnHide", function() HideMenus(2) end)
    m:RegisterEvent("GLOBAL_MOUSE_DOWN")
    m:SetScript("OnEvent", function(self)
      if not self:IsShown() then return end
      for _, f in ipairs(S.menus) do if f:IsShown() and f:IsMouseOver() then return end end
      HideMenus(1)
    end)
  end
  S.menus[level] = m
  return m
end

function S.ShowMenu(items, anchor, level)
  level = level or 1
  HideMenus(level)
  local m = MenuFrame(level)
  local w = 110
  for i, it in ipairs(items) do
    local r = m.rows[i]
    if not r then
      r = CreateFrame("Button", nil, m); r:SetHeight(18)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(S.AR, S.AG, S.AB, .18)
      r.text = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.text:SetPoint("LEFT", 10, 0); r.text:SetJustifyH("LEFT")
      r.arrow = r:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); r.arrow:SetPoint("RIGHT", -8, 0); r.arrow:SetText(">"); r.arrow:SetTextColor(.56, .6, .7)
      r.check = r:CreateTexture(nil, "ARTWORK"); r.check:SetSize(14, 14); r.check:SetPoint("RIGHT", -6, 0); r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      m.rows[i] = r
    end
    local pad = S.WowSkin() and 7 or 4
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", pad, -pad - (i - 1) * 18); r:SetPoint("RIGHT", m, "RIGHT", -pad, 0)
    r.text:SetText(it.text or "")
    if it.isTitle then r.text:SetTextColor(S.AR, S.AG, S.AB)
    elseif it.disabled then r.text:SetTextColor(.42, .46, .55)
    elseif it.danger then r.text:SetTextColor(1, .61, .57)
    else r.text:SetTextColor(.9, .92, .97) end
    r.arrow:SetShown(it.menuList ~= nil)
    r.check:SetShown(it.checked == true)
    if it.isTitle or it.disabled then r.hl:SetAlpha(0) else r.hl:SetAlpha(1) end
    r:SetScript("OnEnter", function(self)
      if it.menuList and not it.disabled then S.ShowMenu(it.menuList, self, level + 1) else HideMenus(level + 1) end
    end)
    r:SetScript("OnClick", function()
      if it.isTitle or it.disabled or it.menuList then return end
      HideMenus(1)
      if it.func then it.func() end
    end)
    r:Show()
    w = math.max(w, r.text:GetStringWidth() + ((it.menuList or it.checked ~= nil) and 40 or 26))
  end
  for i = #items + 1, #m.rows do m.rows[i]:Hide() end
  local pad2 = S.WowSkin() and 14 or 8
  m:SetSize(math.min(w, 320) + pad2, #items * 18 + pad2)
  m:ClearAllPoints()
  if level > 1 then m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 4)
  elseif type(anchor) == "table" then m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else
    local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 4, y / s + 4)
  end
  m:Show()
end

---------------------------------------------------------------------------
-- Save dialog, rename, session menu
---------------------------------------------------------------------------
local function BuildSave()
  save = Window("SterlingQuestSaveFrame", 250, 120, "Save session?")
  save:SetFrameStrata("DIALOG")
  save.meta = save:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); save.meta:SetPoint("TOPLEFT", 14, -38); save.meta:SetTextColor(.56, .6, .7); save.meta:SetWidth(222); save.meta:SetJustifyH("LEFT")
  save.eb = CreateFrame("EditBox", nil, save, "InputBoxTemplate"); save.eb:SetSize(216, 22); save.eb:SetPoint("TOPLEFT", 19, -60); save.eb:SetAutoFocus(true)
  save.ok = Button(save, "Save", 60); save.ok:SetPoint("BOTTOMLEFT", 12, 10)
  save.no = Button(save, "Discard", 64); save.no:SetPoint("LEFT", save.ok, "RIGHT", 4, 0)
  save.eb:SetScript("OnEnterPressed", function() save.ok:Click() end)
  -- every pop-up on this frame: buttons centred along the bottom, the box centred over the window you're using
  save:HookScript("OnShow", function(self)
    local okW = self.ok:GetWidth() or 60
    local total = okW + (self.no:IsShown() and (4 + (self.no:GetWidth() or 64)) or 0)
    self.ok:ClearAllPoints(); self.ok:SetPoint("BOTTOMLEFT", self, "BOTTOM", -total / 2, 10)
    local w = S.activeWin
    if not (w and w ~= self and w:IsShown()) then w = _G.SterlingQuestFrame end
    if w and w ~= self and w:IsShown() then self:ClearAllPoints(); self:SetPoint("CENTER", w, "CENTER", 0, 0) end
  end)
  save.eb:SetScript("OnEscapePressed", function() save.eb:ClearFocus() end)
end

-- size the small dialog to its hint text so nothing overlaps the edit box
local function fitSave()
  local h = math.max(12, save.meta:GetStringHeight() or 12)
  save.eb:ClearAllPoints(); save.eb:SetPoint("TOPLEFT", 19, -(40 + h + 8))
  save:SetHeight(40 + h + 8 + 22 + 44)
end

-- The session is already saved when this opens; it only names it (or deletes it, with a second click).
function S.UI_SaveDialog(sess)
  save.eb:Show()
  save.title:SetText("Saved. Name it?")
  save.meta:SetText(S.Duration(sess) .. "  |  " .. #sess.events .. " events  |  " .. #sess.trail .. " trail points")
  save.eb:SetText(sess.name or "")
  save.ok:SetText("OK")
  save.ok:SetScript("OnClick", function() local n = save.eb:GetText(); if n ~= "" then sess.name = n end; save:Hide(); S.UI_Update() end)
  save.no:SetText("Delete"); save.no:Show()
  local armed = false
  save.no:SetScript("OnClick", function()
    if not armed then armed = true; save.no:SetText("Sure?"); return end
    save:Hide(); S.DeleteSession(sess); msg("Deleted. /st restore brings it back."); S.UI_Update()
  end)
  fitSave(); save:Show()
end

-- Stopping from a small control (title bar dot, minimap coin) asks first.
function S.ConfirmStop()
  if not S.IsRecording() then S.RecordStart() return end
  S.UI_Prompt("Stop recording?", S.Duration(S.Recording()) .. " recorded so far. It will be saved.", nil, "Stop", function() S.RecordStop() end)
  if save.eb then save.eb:Hide() end
end

-- Yes/no question built on the save window (no text box).
function S.UI_Confirm(title, hint, okText, onOk)
  save.title:SetText(title)
  save.meta:SetText(hint or "")
  save.eb:Hide()
  save.ok:SetText(okText or "OK"); save.no:SetText("Cancel"); save.no:Show()
  save.ok:SetScript("OnClick", function() save:Hide(); onOk() end)
  save.no:SetScript("OnClick", function() save:Hide() end)
  local h = math.max(12, save.meta:GetStringHeight() or 12)
  save:SetHeight(40 + h + 8 + 44)
  save:Show()
end

-- Generic one-line prompt built on the save window.
function S.UI_Prompt(title, hint, default, okText, onOk)
  save.eb:Show()
  save.title:SetText(title)
  save.meta:SetText(hint or "")
  save.eb:SetText(default or "")
  save.ok:SetText(okText or "OK"); save.no:SetText("Cancel"); save.no:Show()
  save.ok:SetScript("OnClick", function() local v = save.eb:GetText(); save:Hide(); onOk(v) end)
  save.no:SetScript("OnClick", function() save:Hide() end)
  fitSave(); save:Show(); save.eb:SetFocus()
end

function S.UI_Rename(sess)
  save.eb:Show()
  save.title:SetText("Rename session")
  save.meta:SetText(S.SessionSummary(sess))
  save.eb:SetText(sess.name or "")
  save.ok:SetText("Rename"); save.no:SetText("Cancel"); save.no:Show()
  save.ok:SetScript("OnClick", function()
    local n = (save.eb:GetText() or ""):gsub("[%^:;,|~]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if n ~= "" then sess.name = n:sub(1, 40) end
    save:Hide(); S.UI_Update()
  end)
  save.no:SetScript("OnClick", function() save:Hide() end)
  fitSave(); save:Show(); save.eb:SetFocus(); save.eb:HighlightText()
end

function S.UI_ConfirmDelete(sess)
  S.UI_Prompt("Delete session?", "\"" .. (sess.name or "session") .. "\" (" .. (sess.imported and ("from " .. (sess.char or "?")) or "yours") .. ", " .. S.Duration(sess) .. ")." .. (S.Opt("noTrash", false) and " This can't be undone." or " Restore on the Sessions page brings it back."), nil, "Delete",
    function() S.DeleteSession(sess); msg("Deleted \"" .. (sess.name or "session") .. "\"."); S.UI_Update() end)
  save.eb:Hide()
end

function S.UI_SessionMenu(sess)
  local menu = {
    { text = sess.name, isTitle = true, notCheckable = true },
    { text = "Follow", notCheckable = true, func = function() S.FollowSession(sess, true); S.UI_Tab("path") end },
    { text = "Show on map", notCheckable = true, func = function() S.MapSetSession(sess); S.MapToggle() end },
    { text = "Export string", notCheckable = true, func = function() S.UI_ShowExport(sess.id) end },
    { text = "Send to partner / group", notCheckable = true, func = function() S.SendSession(sess) end },
    { text = "Rename", notCheckable = true, func = function() S.UI_Rename(sess) end },
    { text = "Merge with...", notCheckable = true, hasArrow = true, menuList = (function()
        local sub = {}
        for _, other in ipairs(SterlingQuestDB.sessions) do
          if other ~= sess then sub[#sub + 1] = { text = other.name .. "  (" .. S.Duration(other) .. ")", notCheckable = true,
            func = function() local m = S.MergeSessions(sess, other); msg("Merged into \"" .. m.name .. "\"."); S.UI_Update() end } end
        end
        if #sub == 0 then sub[1] = { text = "no other sessions", notCheckable = true, disabled = true } end
        return sub
      end)() },
    { text = "Compare with...", notCheckable = true, hasArrow = true, menuList = (function()
        local sub = {}
        for _, other in ipairs(SterlingQuestDB.sessions) do
          if other ~= sess then sub[#sub + 1] = { text = other.name .. "  (" .. (other.char or "?") .. ", " .. S.Duration(other) .. ")", notCheckable = true,
            func = function() if S.ViewerCompare then S.ViewerCompare(sess, other) end end } end
        end
        if #sub == 0 then sub[1] = { text = "no other sessions", notCheckable = true, disabled = true } end
        return sub
      end)() },
    { text = "Delete", danger = true, func = function() S.UI_ConfirmDelete(sess) end },
  }
  local tr = SterlingQuestDB.trash and SterlingQuestDB.trash[1]
  if tr then menu[#menu + 1] = { text = "Restore \"" .. (tr.name or "session") .. "\"", func = function() S.Restore() end } end
  if SterlingQuestDB.following == sess.id then menu[2] = { text = "Stop following", notCheckable = true, func = function() S.StopFollowing(); S.UI_Update() end } end
  S.ShowMenu(menu, "cursor")
end

---------------------------------------------------------------------------
-- Export / import box
---------------------------------------------------------------------------
local function BuildBox()
  box = Window("SterlingQuestBoxFrame", 460, 250, "Sterling")
  box:SetFrameStrata("DIALOG")
  local sf = CreateFrame("ScrollFrame", "SterlingQuestBoxScroll", box, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 18, -60); sf:SetPoint("BOTTOMRIGHT", -36, 42)
  local field = Box(box); field:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4); field:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 22, -4)
  field:SetBackdropColor(0, 0, 0, .35); field:SetBackdropBorderColor(.3, .35, .48, 1); field:SetFrameLevel(math.max(0, sf:GetFrameLevel() - 1))
  box.field = field
  local eb = CreateFrame("EditBox", nil, sf); eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontSmall); eb:SetMaxLetters(0)
  eb:SetWidth(408); eb:SetTextInsets(4, 4, 4, 4); eb:SetTextColor(S.TR, S.TG, S.TB); eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if eb.SetBlinkSpeed then eb:SetBlinkSpeed(0.5) end
  -- the field lights up while it has focus and shows a placeholder when empty, so there's never any doubt it's active
  box.placeholder = eb:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); box.placeholder:SetPoint("TOPLEFT", 6, -5); box.placeholder:SetTextColor(.45, .5, .6); box.placeholder:SetText("Ctrl+V to paste here")
  eb:SetScript("OnEditFocusGained", function(self) if box.field then box.field:SetBackdropBorderColor(S.AR, S.AG, S.AB, 1); box.field:SetBackdropColor(0, 0, 0, .5) end; if self:GetText() == "" then box.placeholder:SetText("|cff8ab8ff|  |rCtrl+V to paste here") end end)
  eb:SetScript("OnEditFocusLost", function(self) if box.field then box.field:SetBackdropBorderColor(.3, .35, .48, 1); box.field:SetBackdropColor(0, 0, 0, .35) end; box.placeholder:SetText("Ctrl+V to paste here") end)
  sf:SetScrollChild(eb); box.eb = eb
  -- an empty multi-line edit box has no height, so clicks in the empty area would miss it
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
  sf:SetScript("OnSizeChanged", function(self, w, h) eb:SetWidth(w - 4); if eb:GetHeight() < h then eb:SetHeight(h) end end)
  eb:SetScript("OnTextChanged", function(self) local h = sf:GetHeight(); if self:GetHeight() < h then self:SetHeight(h) end; box.placeholder:SetShown(self:GetText() == "" and box.ok:IsShown()) end)
  eb:SetHeight(150)
  box.hint = box:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); box.hint:SetPoint("TOPLEFT", 14, -38); box.hint:SetWidth(432); box.hint:SetJustifyH("LEFT"); box.hint:SetWordWrap(false); box.hint:SetTextColor(.72, .76, .85)
  box.ok = Button(box, "Import", 80); box.ok:SetPoint("BOTTOMRIGHT", -14, 10)
  box.ok:SetScript("OnClick", function() S.ImportString(box.eb:GetText()); box:Hide() end)
  local c = Button(box, "Close", 60); c:SetPoint("RIGHT", box.ok, "LEFT", -4, 0); c:SetScript("OnClick", function() box:Hide() end)
end

-- what: a session id/name, "log" for the quest snapshot, or empty (latest own session, else log)
function S.UI_ShowExport(what)
  local text, label
  if what == "log" then
    text, label = S.MakeSnapshot(), "quest log"
  else
    local sess = S.FindSession(what)
    if not sess and (what == nil or what == "") then
      for _, s in ipairs(SterlingQuestDB.sessions) do if not s.imported then sess = s break end end
    end
    if sess then text, label = S.EncodeSession(sess), "session \"" .. sess.name .. "\""
    else text, label = S.MakeSnapshot(), "quest log (no sessions recorded yet)" end
  end
  box.title:SetText("Export: " .. label)
  box.hint:SetText("Ctrl+C to copy, send it to your friend, they paste it into Import.  (" .. #text .. " characters)")
  box.eb:SetText(text); box.ok:Hide(); box:Show(); box.placeholder:Hide()
  box.eb:SetFocus(); box.eb:HighlightText()
end

function S.UI_ShowImport()
  box.title:SetText("Import"); box.hint:SetText("Paste a session (SES1...) or quest-log (STR3...) string, then Import.")
  box.eb:SetText(""); box.ok:Show(); box:Show(); box.placeholder:Show(); box.eb:SetFocus(); box.eb:SetCursorPosition(0)
end

---------------------------------------------------------------------------
-- Offline sync window: your string for one partner on top, theirs pasted underneath.
---------------------------------------------------------------------------
-- A boxed, scrolling, multi-line text field (the same field the Export / Import box uses).
local function TextField(parent, scrollName, placeholder)
  local sf = CreateFrame("ScrollFrame", scrollName, parent, "UIPanelScrollFrameTemplate")
  local field = Box(parent); field:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4); field:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 22, -4)
  field:SetBackdropColor(0, 0, 0, .35); field:SetBackdropBorderColor(.3, .35, .48, 1); field:SetFrameLevel(math.max(0, sf:GetFrameLevel() - 1))
  local eb = CreateFrame("EditBox", nil, sf); eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontSmall); eb:SetMaxLetters(0)
  eb:SetWidth(380); eb:SetTextInsets(4, 4, 4, 4); eb:SetTextColor(S.TR, S.TG, S.TB); eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sf:SetScrollChild(eb)
  local ph = eb:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); ph:SetPoint("TOPLEFT", 6, -5); ph:SetTextColor(.45, .5, .6); ph:SetText(placeholder or "")
  eb:SetScript("OnEditFocusGained", function() field:SetBackdropBorderColor(S.AR, S.AG, S.AB, 1); field:SetBackdropColor(0, 0, 0, .5) end)
  eb:SetScript("OnEditFocusLost", function() field:SetBackdropBorderColor(.3, .35, .48, 1); field:SetBackdropColor(0, 0, 0, .35) end)
  -- an empty multi-line edit box has no height, so clicks in the empty area would miss it
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
  sf:SetScript("OnSizeChanged", function(self, w, h) eb:SetWidth(w - 4); if eb:GetHeight() < h then eb:SetHeight(h) end end)
  eb:SetHeight(72)
  return { sf = sf, eb = eb, field = field, placeholder = ph }
end

local function offlineStatus(f)
  local name = f.who
  if not name then
    f.keyLine:SetText("|cff8a93a8Pick a partner at the top right, or paste a string from anyone below.|r")
    f.make:SetEnabled(false); f.full:SetEnabled(false)
    return
  end
  f.make:SetEnabled(true); f.full:SetEnabled(true)
  local who = S.PartnerLabel(name)
  if S.KeyState(name) == "signed" then
    f.keyLine:SetText("|cff7ee2a2" .. S.Mark("good", true) .. "Signed.|r You and " .. who .. " have swapped keys, so strings are checked on both sides.")
  else
    f.keyLine:SetText("|cfff3c56b" .. S.Mark("warn", true) .. "Offline sync needs one live sync|r to swap keys. Until then you can send a full copy; " .. who .. " gets a warning to confirm.")
  end
end
local function offlineShowPart(f)
  local parts = f.parts
  if not parts then
    f.out.eb:SetText(""); f.out.placeholder:Show(); f.outInfo:SetText(""); f.nextBtn:Hide(); f.copy:SetEnabled(false)
    return
  end
  local i = f.part or 1
  f.out.placeholder:Hide()
  f.out.eb:SetText(parts[i]); f.out.eb:SetCursorPosition(0)
  local info = f.info or {}
  local what = info.kind == "D" and ((info.changes or 0) .. (info.changes == 1 and " change" or " changes") .. " since their copy #" .. tostring(info.base)) or "Full copy"
  f.outInfo:SetText(what .. (#parts > 1 and ("  ·  part " .. i .. " of " .. #parts) or "") .. "  ·  " .. #parts[i] .. " characters")
  f.nextBtn:SetShown(#parts > 1); f.nextBtn:SetText(i < #parts and "Next part" or "First part")
  f.copy:SetEnabled(true)
end
local function offlineMake(f, forceFull)
  if not f.who then return end
  local parts, info = S.OfflineExport(f.who, forceFull)
  if not parts then f.result:SetText("|cffff9b92" .. S.Mark("bad") .. tostring(info) .. "|r"); return end
  f.parts, f.info, f.part = parts, info, 1
  offlineShowPart(f)
  f.out.eb:SetFocus(); f.out.eb:HighlightText()
  f.result:SetText("|cff8a93a8Ctrl+C to copy" .. (#parts > 1 and (" this part; it comes in " .. #parts .. " parts so each fits a Discord message. Send them all.") or ", then send it to " .. S.PartnerLabel(f.who) .. " any way you like.") .. "|r")
end
local function offlineImport(f)
  local text = f.inn.eb:GetText() or ""
  local packed, got, need = S.OfflineCollect(text)
  if not packed then
    if need > 0 then f.result:SetText("|cfff3c56b" .. S.Mark("warn") .. "Got part " .. got .. " of " .. need .. ".|r Paste the other part" .. (need - got == 1 and "" or "s") .. " after it (any order), then Import.")
    else f.result:SetText("|cffff9b92" .. S.Mark("bad") .. "No offline sync string in there.|r It starts with STO1: (a session or quest-log string goes in Import on the Path tab).") end
    return
  end
  local d, err = S.OfflineRead(packed)
  if not d then f.result:SetText("|cffff9b92" .. S.Mark("bad") .. tostring(err) .. "|r"); return end
  local verdict, why = S.OfflineCheck(d)
  local function apply()
    local ok, line = S.OfflineApply(d, verdict)
    if ok then
      f.result:SetText("|cff7ee2a2" .. S.Mark("good") .. line .. "|r"); f.inn.eb:SetText(""); f.inn.placeholder:Show()
      local p = S.FindPartner(d.from); if p then f.who = p.name; f.title:SetText("Offline sync: " .. S.PartnerLabel(p.name)); f.pick:Refresh() end
      msg(line)
    else f.result:SetText("|cffff9b92" .. S.Mark("bad") .. tostring(line) .. "|r") end
    offlineStatus(f)
  end
  if verdict == "ok" then apply()
  elseif verdict == "confirm" then
    f.result:SetText("|cfff3c56b" .. S.Mark("warn") .. "Waiting for you to confirm.|r")
    S.UI_Confirm("Import an unsigned string?", why, "Import", apply)
  else f.result:SetText("|cffff9b92" .. S.Mark("bad") .. "|r" .. tostring(why)) end
end
-- name: the partner to make a string for (nil = none picked yet). text: a string to drop in the paste box.
function S.UI_Offline(name, text)
  if not offWin then
    offWin = Window("SterlingQuestOffline", 460, 430, "Offline sync")
    local f = offWin
    f:SetFrameStrata("DIALOG")
    f.hint = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.hint:SetPoint("TOPLEFT", 14, -38); f.hint:SetJustifyH("LEFT"); f.hint:SetTextColor(.72, .76, .85); f.hint:SetWordWrap(false)
    f.hint:SetText("Sync without being online together: send your string, paste theirs.")
    f.pick = Dropdown(f, 130, function() return f.who and S.PartnerLabel(f.who) or "pick a partner" end, function()
      local items = {}
      for _, p in ipairs(S.Partners()) do
        items[#items + 1] = { text = S.PartnerLabel(p.name), checked = f.who == p.name, func = function() S.UI_Offline(p.name) end }
      end
      if #items == 0 then items[1] = { text = "No partners yet", disabled = true } end
      return items
    end)
    f.pick:SetPoint("TOPRIGHT", -14, -34)
    f.hint:SetPoint("RIGHT", f.pick, "LEFT", -8, 0)
    f.keyLine = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.keyLine:SetPoint("TOPLEFT", 14, -62); f.keyLine:SetPoint("RIGHT", -14, 0); f.keyLine:SetJustifyH("LEFT"); f.keyLine:SetHeight(24); f.keyLine:SetJustifyV("TOP")
    -- your string
    f.outHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.outHead:SetPoint("TOPLEFT", 14, -94); f.outHead:SetText("Your string"); f.outHead:SetTextColor(S.LabelColor())
    f.outInfo = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.outInfo:SetPoint("TOPLEFT", f.outHead, "TOPRIGHT", 10, -1); f.outInfo:SetPoint("RIGHT", -14, 0); f.outInfo:SetJustifyH("RIGHT"); f.outInfo:SetTextColor(.56, .6, .7); f.outInfo:SetWordWrap(false)
    f.out = TextField(f, "SterlingQuestOfflineOut", "Press Make string")
    f.out.sf:SetPoint("TOPLEFT", 18, -116); f.out.sf:SetPoint("TOPRIGHT", -36, -116); f.out.sf:SetHeight(72)
    f.make = Button(f, "Make string", 96); f.make:SetPoint("TOPLEFT", 14, -198)
    f.make:SetScript("OnClick", function() offlineMake(f, false) end)
    f.make:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Make string"); GameTooltip:AddLine("Everything that changed since the last copy your partner confirmed. If they hold nothing yet, or you haven't swapped keys, it is a full copy.", 1, 1, 1, true); GameTooltip:Show() end)
    f.make:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.full = Button(f, "Full copy", 80); f.full:SetPoint("LEFT", f.make, "RIGHT", 4, 0)
    f.full:SetScript("OnClick", function() offlineMake(f, true) end)
    f.full:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Full copy"); GameTooltip:AddLine("Your whole quest log and history, whatever they hold. Use it when their side says a string doesn't continue from the update they have.", 1, 1, 1, true); GameTooltip:Show() end)
    f.full:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.copy = Button(f, "Select all", 80); f.copy:SetPoint("LEFT", f.full, "RIGHT", 4, 0)
    f.copy:SetScript("OnClick", function() f.out.eb:SetFocus(); f.out.eb:HighlightText() end)
    f.nextBtn = Button(f, "Next part", 80); f.nextBtn:SetPoint("TOPRIGHT", -14, -198)
    f.nextBtn:SetScript("OnClick", function() if f.parts then f.part = (f.part or 1) % #f.parts + 1; offlineShowPart(f); f.out.eb:SetFocus(); f.out.eb:HighlightText() end end)
    -- their string
    f.inHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.inHead:SetPoint("TOPLEFT", 14, -234); f.inHead:SetText("Their string"); f.inHead:SetTextColor(S.LabelColor())
    f.inn = TextField(f, "SterlingQuestOfflineIn", "Ctrl+V to paste here. Several parts can go in one after another.")
    f.inn.sf:SetPoint("TOPLEFT", 18, -256); f.inn.sf:SetPoint("TOPRIGHT", -36, -256); f.inn.sf:SetHeight(72)
    f.inn.eb:SetScript("OnTextChanged", function(self) f.inn.placeholder:SetShown(self:GetText() == "") end)
    f.result = f:CreateFontString(nil, "OVERLAY", S.FONT_SMALL); f.result:SetPoint("TOPLEFT", 14, -338); f.result:SetPoint("RIGHT", -14, 0); f.result:SetJustifyH("LEFT"); f.result:SetJustifyV("TOP"); f.result:SetHeight(48)
    f.imp = Button(f, "Import", 80); f.imp:SetPoint("BOTTOMRIGHT", -14, 10)
    f.imp:SetScript("OnClick", function() offlineImport(f) end)
    f.clr = Button(f, "Clear", 60); f.clr:SetPoint("RIGHT", f.imp, "LEFT", -4, 0)
    f.clr:SetScript("OnClick", function() f.inn.eb:SetText(""); f.inn.placeholder:Show(); f.result:SetText("") end)
    f.help = Button(f, "How it works", 100); f.help:SetPoint("BOTTOMLEFT", 14, 10)
    f.help:SetScript("OnClick", function() if S.UI_Help then S.UI_Help("offline") end end)
    f:SetScale(S.Opt("scale", 1))
  end
  local f = offWin
  if name then local p = S.FindPartner(name); name = p and p.name or nil end
  if name ~= f.who or not f.shownOnce then f.parts, f.info, f.part = nil, nil, nil end
  f.shownOnce = true
  f.who = name or f.who
  if f.who and not S.FindPartner(f.who) then f.who = nil end
  f.title:SetText(f.who and ("Offline sync: " .. S.PartnerLabel(f.who)) or "Offline sync")
  f.pick:Refresh()
  f.result:SetText("")
  offlineStatus(f); offlineShowPart(f)
  if text and text ~= "" then f.inn.eb:SetText(text); f.inn.placeholder:Hide() end
  f:Show()
  if text and text ~= "" then offlineImport(f) end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mm
local function BuildMinimap()
  mm = CreateFrame("Button", "SterlingQuestMinimapButton", Minimap)
  mm:SetSize(31, 31); mm:SetFrameStrata("MEDIUM"); mm:SetFrameLevel(8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp"); mm:RegisterForDrag("LeftButton")
  local overlay = mm:CreateTexture(nil, "OVERLAY"); overlay:SetSize(53, 53); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
  local bg = mm:CreateTexture(nil, "BACKGROUND"); bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetPoint("TOPLEFT", 7, -5)
  local icon = mm:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 7, -6); icon:SetTexture("Interface\\AddOns\\Sterling\\Media\\glyph")
  mm.dot = mm:CreateTexture(nil, "OVERLAY", nil, 7); mm.dot:SetSize(11, 11); mm.dot:SetPoint("TOPRIGHT", -3, -3); mm.dot:SetTexture("Interface\\COMMON\\Indicator-Red"); mm.dot:Hide()
  -- Follows the minimap's edge: round, square (square map addons set GetMinimapShape) and the corner/side shapes.
  -- true = that quarter is round. Quarters: 1 bottom-right, 2 bottom-left, 3 top-right, 4 top-left.
  local SHAPES = {
    ["ROUND"] = { true, true, true, true }, ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
  }
  local function place()
    local a = math.rad(SterlingQuestDB.minimapAngle or 200)
    local x, y = math.cos(a), math.sin(a)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = "ROUND"
    if type(GetMinimapShape) == "function" then local ok, v = pcall(GetMinimapShape); if ok and type(v) == "string" then shape = v end end
    local quads = SHAPES[shape] or SHAPES.ROUND
    local w = (Minimap:GetWidth() or 140) / 2 + 10
    local h = (Minimap:GetHeight() or 140) / 2 + 10
    if quads[q] then x, y = x * w, y * h
    else
      local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
      x = math.max(-w, math.min(x * dw, w)); y = math.max(-h, math.min(y * dh, h))
    end
    mm:ClearAllPoints(); mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  S.MinimapPlace = place
  -- a square map addon may load after us or resize the map: place again then
  Minimap:HookScript("OnSizeChanged", function() pcall(place) end)
  local ev = CreateFrame("Frame"); ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", function() C_Timer.After(1, function() pcall(place) end) end)
  mm:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
    SterlingQuestDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)); place()
  end) end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnClick", function(_, btn)
    if IsShiftKeyDown() then S.ConfirmStop()
    elseif btn == "RightButton" then S.MapToggle() else S.UI_Toggle() end
  end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Sterling Quest Sync")
    local rec = S.Recording()
    if rec then GameTooltip:AddLine("|cffff6060Recording|r " .. S.Duration(rec) .. ", " .. #rec.events .. " events") end
    local st = S.steps[S.CurrentIndex()]
    if st then GameTooltip:AddLine("Next: " .. S.StepLabel(st), .8, .83, .9, true) end
    local d = S.TrailDistance()
    if d then GameTooltip:AddLine(d < 2.5 and "On trail" or ("Off trail by " .. ("%.1f"):format(d)), .49, .89, .64) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left: window   Right: map   Shift: record/stop   Drag: move", .5, .8, 1)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  if SterlingQuestDB.hideMinimap then mm:Hide() end
end

function S.UI_MinimapState()
  if not mm then return end
  if S.IsRecording() then mm.dot:Show() else mm.dot:Hide() end
end

-- Key bindings (Bindings.xml)
BINDING_HEADER_STERLINGQUEST = "Sterling Quest Sync"
BINDING_NAME_STERLINGQUEST_RECORD = "Record / Stop"
BINDING_NAME_STERLINGQUEST_DONE = "Mark current step done"
BINDING_NAME_STERLINGQUEST_MAP = "Toggle map playback"
BINDING_NAME_STERLINGQUEST_WINDOW = "Toggle window"
function SterlingQuest_Bind(what)
  if what == "record" then if S.IsRecording() then S.RecordStop() else S.RecordStart() end
  elseif what == "done" then SterlingQuestDB.manual[S.CurrentIndex()] = true; S.Recalc(false)
  elseif what == "map" then S.MapToggle()
  elseif what == "window" then S.UI_Toggle() end
end

function S.UI_Init()
  BuildMain(); BuildSave(); BuildBox(); BuildMinimap()
  S.UI_Tab(current)
  if SterlingQuestDB.shown ~= false then main:Show() end
  main:HookScript("OnShow", function() SterlingQuestDB.shown = true; S.UI_Update() end)
  main:HookScript("OnHide", function() SterlingQuestDB.shown = false end)
end

-- Switch the look (WoW / Navy) without a /reload: build every Sterling window again in the new look.
-- The old frames are hidden and left alone (the game can't delete frames); the new ones take their names.
function S.UI_ApplyLook()
  local wasShown = main and main:IsShown()
  local optOpen, optTab = optWin and optWin:IsShown(), pages.options and pages.options.tab
  for _, w in ipairs(S.windows or {}) do pcall(w.Hide, w) end
  if S.HideMenus then S.HideMenus(1) end
  for _, m in ipairs(S.menus or {}) do pcall(m.Hide, m) end
  S.windows, S.menus = {}, {}
  main, tabs, pages, builders = nil, {}, {}, {}
  save, box, info, share, ask, cmpWin, optWin, profWin, every = nil, nil, nil, nil, nil, nil, nil, nil, nil
  addWin, invWin, offWin = nil, nil, nil
  if S.GuideReset then S.GuideReset() end
  tabOrder = {}
  S.tabTextPt = nil
  if S.ThemeInit then S.ThemeInit() end
  BuildMain(); BuildSave(); BuildBox()
  main:HookScript("OnShow", function() SterlingQuestDB.shown = true; S.UI_Update() end)
  main:HookScript("OnHide", function() SterlingQuestDB.shown = false end)
  S.UI_Tab(current)
  if wasShown then main:Show() end
  if optOpen then S.UI_Options(); if optTab and pages.options and pages.options.ShowTab then pages.options.ShowTab(optTab) end end
  S.UI_Update()
  msg("Look applied: " .. (S.WowSkin() and "WoW" or "Flat") .. ". The map window and map bar switch at your next /reload.")
end
