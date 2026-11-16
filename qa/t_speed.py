import sim, time
P = sim.Player("Kaelith Emberfall", [], [])
L, S = P.L, P.S
L.execute('''
T = {}
local ev, tr = {}, {}
for i = 1, 400 do ev[i] = { t = 1e9 + i * 30, k = "T", q = 100 + i, map = 1413, x = 40.5 + (i % 50) / 10, y = 61.25, quest = "Quest " .. i, npc = "Npc " .. i }
  for j = 1, 6 do tr[#tr + 1] = { t = 1e9 + i * 30 + j, map = 1413, x = 40 + i / 7 + j / 100, y = 60 - i / 9 } end end
DATA = { events = ev, trail = tr }
''')
raw = L.eval('function(S) return S.Serialize(DATA) end')(S)
L.globals().RAW = raw
for lvl in (1, 3, 5, 9):
    t = time.time(); z = L.eval('function(S, l) local lib = S.LibDeflate(); return #lib:EncodeForPrint(lib:CompressDeflate(RAW, { level = l })) end')(S, lvl); dt = time.time() - t
    print("level %d: %d -> %d bytes in %.2fs" % (lvl, len(raw), z, dt))
t = time.time(); L.eval('function(S) return S.Serialize(DATA) end')(S); print("serialize %.3fs" % (time.time() - t))
