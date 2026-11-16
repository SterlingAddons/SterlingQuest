import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
import sim, re, sys
def clean(c): return re.sub(r"\|c\w{8}|\|r|\|T.-\|t ?", "", str(c))
ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))
    if not cond: ok = False
for skin, cb in (("wow", False), ("navy", False), ("wow", True)):
    sim.reset()
    SV = open(_os.path.join(QA, "t_layout.py")).read().split("SV = '''")[1].split("''' % ")[0] % (skin, "true" if cb else "false")
    SV = SV.replace('SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }', '')
    P = sim.Player("Kaelith Emberfall", [(2, "Fishy Business"), (188, "Tiger Mastery")], [6, 185, 186], level=38, sv=SV, questie=True, tomtom=(skin == "wow"))
    L, S = P.L, P.S
    def do(code): return L.eval("function(S) " + code + " end")(S)
    do('''
      S.ReadCompleted = function() return { [6] = true } end
      SterlingQuestDB.partners = { { name = "Brannoc Ashvale", on = true, k1 = "aa", k2 = "bb" }, { name = "Tovak", on = true, k1 = "cc" }, { name = "Bran", on = true, k1 = "dd" } }
      local function snap(name, lvl) S.snaps[name] = { log = { [2] = { title = "Fishy Business", complete = false, objs = { "Fish 3/8" } } }, completed = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true }, rank = {}, seq = 3, at = time() - 100, level = lvl, source = "live", name = name } end
      snap("Brannoc Ashvale", 39); snap("Tovak", 30); snap("Bran", 41)
      S.addonVers = { ["Brannoc Ashvale"] = "0.2.30", Tovak = "6.29", Bran = "0.2.31" }
      S.sync.vers = { ["Brannoc Ashvale"] = 6, Tovak = 6, Bran = 5 }''')
    sim.pump(12)
    do('''S.UI_Toggle(true)
      for _, tab in ipairs({ "path", "sessions", "sync", "catchup" }) do S.UI_Tab(tab); S.UI_Update() end
      S.CatchupStart("Brannoc Ashvale", 500)
      S.UI_Options(); S.UI_Compare("Brannoc Ashvale"); S.UI_PartnerInfo("Brannoc Ashvale"); S.UI_ShareWindow("Brannoc Ashvale"); S.UI_Profile(); S.UI_AddPartner(); S.UI_Everyone()
      S.UI_Offline("Brannoc Ashvale"); S.UI_Help("start"); S.UI_Welcome(); S.UI_ShowExport("log"); S.UI_ShowImport()''')
    res = do('''
      local skip = { ["Empty the trash"] = true, ["Reset check-offs"] = true, ["Remove"] = true, ["Delete"] = true, ["Stop"] = true, ["Record"] = true, ["Reset counters"] = true, ["Stop following"] = true, ["Sure?"] = true, ["Discard"] = true, ["Apply"] = true, ["Reset"] = true, ["Clear"] = true }
      local n, bad, msgs = 0, 0, {}
      local seen = {}
      for round = 1, 2 do
        for i = 1, #FRAMES do
          local f = FRAMES[i]
          local h = f._scripts.OnClick
          if h and not seen[f] then
            seen[f] = true
            local t = f._text
            if type(t) ~= "string" or not skip[PLAIN(t)] then
              n = n + 1
              local okc, e = pcall(h, f, "LeftButton")
              if not okc then bad = bad + 1; msgs[#msgs + 1] = "[" .. tostring(t) .. "] " .. tostring(e) end
              local okr, e2 = pcall(h, f, "RightButton")
              if not okr then bad = bad + 1; msgs[#msgs + 1] = "[R " .. tostring(t) .. "] " .. tostring(e2) end
              if S.HideMenus then S.HideMenus(1) end
            end
          end
        end
      end
      local hov, hbad = 0, 0
      for _, f in ipairs(FRAMES) do
        local h = f._scripts.OnEnter
        if h then hov = hov + 1; local okh, e = pcall(h, f); if not okh then hbad = hbad + 1; msgs[#msgs + 1] = "ENTER " .. tostring(e) end; if f._scripts.OnLeave then pcall(f._scripts.OnLeave, f) end end
        for _, ev in ipairs({ "OnMouseUp", "OnMouseDown" }) do
          local h2 = f._scripts[ev]
          if h2 then for _, b in ipairs({ "LeftButton", "RightButton" }) do local okm, e = pcall(h2, f, b); if not okm then hbad = hbad + 1; msgs[#msgs + 1] = ev .. " " .. tostring(e) end end if S.HideMenus then S.HideMenus(1) end end
        end
        local w = f._scripts.OnMouseWheel
        if w then for _, d in ipairs({ 1, -1, -1, 1 }) do local okw, e = pcall(w, f, d); if not okw then hbad = hbad + 1; msgs[#msgs + 1] = "WHEEL " .. tostring(e) break end end end
      end
      local oku, eu = pcall(S.UI_Update)
      if not oku then msgs[#msgs + 1] = "UPDATE " .. tostring(eu) end
      return n .. " clicks, " .. hov .. " hovers; failed " .. (bad + hbad) .. (#msgs > 0 and ("\\n" .. table.concat(msgs, "\\n")) or "")''')
    first = str(res).split("\n")[0]
    check("[%s%s] every button clicked (both mouse buttons), everything hovered and wheeled: %s" % (skin, " +cb" if cb else "", first), "failed 0" in first, res)
    sim.pump(5)
    # every option toggled, every dropdown item picked
    res = do('''
      S.UI_Options()
      local msgs, n = {}, 0
      for _, f in ipairs(FRAMES) do
        if f._kind == "CheckButton" and f._scripts.OnClick and f:IsVisible() ~= nil then
          for i = 1, 2 do f:SetChecked(not f:GetChecked()); local okc, e = pcall(f._scripts.OnClick, f, "LeftButton"); n = n + 1; if not okc then msgs[#msgs + 1] = tostring(e) end end
        end
        if f._kind == "Slider" and f._scripts.OnValueChanged then for _, v in ipairs({ f._min or 0, f._max or 1, 1 }) do local okc, e = pcall(f.SetValue, f, v); if not okc then msgs[#msgs + 1] = tostring(e) end end end
      end
      return n .. " toggles; failed " .. #msgs .. (#msgs > 0 and ("\\n" .. table.concat(msgs, "\\n")) or "")''')
    check("[%s] every checkbox toggled twice and sliders moved: %s" % (skin, str(res).split("\n")[0]), "failed 0" in str(res), res)
    res = do('''
      local msgs, n = {}, 0
      local function runMenu(items, depth)
        for _, it in ipairs(items) do
          if it.menuList and depth < 2 then runMenu(it.menuList, depth + 1)
          elseif it.func and not it.disabled and not it.danger and not (it.text or ""):find("Remove") then n = n + 1; local okc, e = pcall(it.func); if not okc then msgs[#msgs + 1] = tostring(it.text) .. ": " .. tostring(e) end end
        end
      end
      local real = S.ShowMenu
      S.ShowMenu = function(items, anchor, level) real(items, anchor, level); if not level or level == 1 then runMenu(items, 0) end end
      for _, name in ipairs({ "Brannoc Ashvale", "Tovak", "Bran" }) do local okc, e = pcall(S.UI_PartnerMenu, name); if not okc then msgs[#msgs + 1] = tostring(e) end end
      for _, sess in ipairs(SterlingQuestDB.sessions) do local okc, e = pcall(S.UI_SessionMenu, sess); if not okc then msgs[#msgs + 1] = tostring(e) end end
      for _, f in ipairs(FRAMES) do if f._kind == "Button" and rawget(f, "arrow") and rawget(f, "Refresh") and f._scripts.OnClick then local okc, e = pcall(f._scripts.OnClick, f); if not okc then msgs[#msgs + 1] = tostring(e) end end end
      S.ShowMenu = real
      return n .. " menu items run; failed " .. #msgs .. (#msgs > 0 and ("\\n" .. table.concat(msgs, "\\n")) or "")''')
    check("[%s] every menu and dropdown item run: %s" % (skin, str(res).split("\n")[0]), "failed 0" in str(res), res)
    sim.pump(10)
    snags = [clean(c) for c in P.chat() if "snag" in c]
    check("[%s] no snags, no Lua errors" % skin, not snags and P.errors() == 0, (snags[:4], P.errors()))
    # reset all settings
    do('SterlingQuestDB.opts.scale = 1.3; SterlingQuestDB.opts.cb = true; SterlingQuestDB.opts.skin = "navy"; SterlingQuestDB.pos = { SterlingQuestFrame = { "CENTER", "CENTER", 5, 5 } }; SterlingQuestDB.sync = false')
    np = P.ev('#SterlingQuestDB.partners'); ns = P.ev('#SterlingQuestDB.sessions')
    do('S.ResetSettings()')
    check("[%s] Reset all settings: options and positions cleared, partners and sessions kept" % skin, P.ev('next(SterlingQuestDB.opts) == nil or (SterlingQuestDB.opts.expanded ~= nil and SterlingQuestDB.opts.cb == nil)') and P.ev('SterlingQuestDB.sync == true') and P.ev('#SterlingQuestDB.partners') == np and P.ev('#SterlingQuestDB.sessions') == ns and do('return S.WowSkin()'))
    check("[%s] still no errors after reset" % skin, P.errors() == 0, P.errors())
print("ALL OK" if ok else "SOME FAILED")
