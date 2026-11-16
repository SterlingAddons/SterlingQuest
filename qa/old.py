import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
# run one of the older scenario files against the new stub, loading the addon in toc order
import sys, sim
from lupa import lua51
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(_os.path.join(QA, "wow.lua")).read())
L.execute('ME = "Kaelith"; PRINT_CHAT = true')
meta, files = sim.toc()
for k, v in meta.items(): L.execute(f'TOCMETA[{k!r}] = {v!r}')
L.execute('SterlingDB = { sessions = { { id="a1", name="Old run", char="Kaelith", start=1000, stop=2000, events={}, trail={}, zones={} }, { id="b2", name="Bran run", char="Brannoc", imported=true, start=3000, stop=4000, events={}, trail={}, zones={} } }, opts = {} }')
L.execute('SterlingQuestAccountDB = { welcomed = true, tour = true, hints = { catchup = true, path = true, sessions = true, sync = true }, told = { Questie = true, TomTom = true } }')
S = L.eval("{}")
load = L.eval("function(src, name) local f, e = loadstring(src, name); if not f then error(e) end return f end")
for f in files:
    if f.lower().endswith(".xml"): continue
    load(open(f"{sim.SRC}/{f}", encoding="utf-8").read(), "@" + f)("Sterling", S)
load(open(sys.argv[1]).read(), "@scenario")(S)
print("ERRORS:", L.eval("ERRORS"))
