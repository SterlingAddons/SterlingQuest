import sim
ACC = 'SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }'
P = sim.Player("Kaelith Emberfall", [], [], account=ACC)
L, S = P.L, P.S
sim.pump(12)
r = L.eval('''function(S)
  local out = {}
  local function rect(n) local w = _G[n]; local l, b, wd, ht = w:GetRect(); local k = w:GetEffectiveScale(); return { l * k, b * k, (l + wd) * k, (b + ht) * k } end
  local function hits(a, b) return a[1] < b[3] - 2 and a[3] > b[1] + 2 and a[2] < b[4] - 2 and a[4] > b[2] + 2 end
  S.UI_Toggle(true)
  local tests = { { "SterlingQuestHelp", function() S.UI_Help() end }, { "SterlingQuestOptions", function() S.UI_Options() end }, { "SterlingQuestOffline", function() S.UI_Offline() end },
                  { "SterlingQuestWelcome", function() S.UI_Welcome() end }, { "SterlingQuestCoach", function() S.TourStart() end }, { "SterlingQuestAddPartner", function() S.UI_AddPartner() end } }
  for _, t in ipairs(tests) do
    for _, w in ipairs(S.windows) do if w ~= SterlingQuestFrame then w:Hide() end end
    t[2]()
    local m, r = rect("SterlingQuestFrame"), rect(t[1])
    out[#out + 1] = t[1] .. ": " .. (hits(m, r) and "OVERLAPS main" or "clear of main") .. ", " .. ((r[1] >= 0 and r[3] <= 1366 and r[2] >= 0 and r[4] <= 768) and "on screen" or ("OFF SCREEN " .. math.floor(r[1]) .. ".." .. math.floor(r[3]) .. " x " .. math.floor(r[2]) .. ".." .. math.floor(r[4])))
  end
  -- two side windows at once
  S.TourEnd(false); for _, w in ipairs(S.windows) do if w ~= SterlingQuestFrame then w:Hide() end end
  S.UI_Options(); S.UI_Help()
  out[#out + 1] = "options + help together: " .. (hits(rect("SterlingQuestOptions"), rect("SterlingQuestHelp")) and "OVERLAP each other" or "clear of each other") .. ", help " .. (hits(rect("SterlingQuestFrame"), rect("SterlingQuestHelp")) and "OVERLAPS main" or "clear of main")
  return table.concat(out, "\\n")
end''')(S)
print(r); print("errors", P.errors())
