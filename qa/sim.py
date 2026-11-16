import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
import sys, re, random
from lupa import lua51
SRC = _os.environ.get("STERLING_SRC", _os.path.join(ROOT, "Sterling"))
wire = []      # (to, prefix, text, chan, sender)
players = {}
LOSS = {}
GUIDS = {}        # guid -> character name, what GetPlayerInfoByGUID knows
UNCACHED = set()  # guids the client hasn't seen yet (returns nothing)
def _pinfo(guid):
    if guid in UNCACHED or guid not in GUIDS: return None
    return (None, None, None, None, None, GUIDS[guid], "")
def toc(src=SRC):
    meta, files = {}, []
    for line in open(f"{src}/Sterling.toc", encoding="utf-8"):
        line = line.strip()
        m = re.match(r"##\s*([^:]+):\s*(.*)", line)
        if m: meta[m.group(1).strip()] = m.group(2).strip()
        elif line and not line.startswith("#"): files.append(line.replace("\\", "/"))
    return meta, files
class Player:
    def __init__(self, name, quests=(), done=(), level=34, src=SRC, sv=None, account=None, questie=False, tomtom=False, pre=None):
        self.name = name
        L = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.L = L
        L.execute(open(_os.path.join(QA, "wow.lua")).read())
        g = L.globals()
        g.ME = name; g.MYLEVEL = level
        import zlib
        g.MYGUID = 'Player-6800-%08X' % (zlib.crc32(name.encode()) & 0xffffffff)
        GUIDS[g.MYGUID] = name
        g.PY_PINFO = _pinfo
        L.execute('GetPlayerInfoByGUID = function(g) return PY_PINFO(g) end')
        meta, files = toc(src)
        for k, v in meta.items(): L.execute(f'TOCMETA[{k!r}] = {v!r}')
        for i, (qid, t) in enumerate(quests): L.execute(f'QLOG[{i+1}] = {{ id = {qid}, title = "{t}" }}')
        for q in done: L.execute(f'QDONE[{q}] = true')
        me = name
        g.SEND = lambda prefix, text, chan, target=None: (wire.append((target, prefix, text, chan, me)), 0)[1]
        if questie: L.execute(open(_os.path.join(QA, "questie.lua")).read())
        if tomtom: L.execute('TomTom = { AddWaypoint = function() return {} end, RemoveWaypoint = function() end }')
        import os
        if os.environ.get('FONT_SCALE'): L.execute('FONT_SCALE = ' + os.environ['FONT_SCALE'])
        if sv: L.execute(sv)
        if account: L.execute(account)
        if pre: L.execute(pre)
        self.S = L.eval("{}")
        load = L.eval("function(src, name) local f, e = loadstring(src, name); if not f then error(e) end return f end")
        for f in files:
            if f.lower().endswith(".xml"): continue
            load(open(f"{src}/{f}", encoding="utf-8").read(), "@" + f)("Sterling", self.S)
        self.fire = L.eval("FIRE")
        self.fire("ADDON_LOADED", "Sterling"); self.fire("PLAYER_LOGIN"); self.fire("PLAYER_ENTERING_WORLD", True, False)
        players[name] = self
    def lua(self, code): return self.L.execute(code)
    def ev(self, code): return self.L.eval(code)
    def chat(self):
        out = [str(t) for t in self.L.globals().CHAT.values()]; self.L.execute("CHAT = {}"); return out
    def errors(self): return self.L.eval("ERRORS or 0")
def pump(seconds=10, step=0.25):
    for _ in range(int(seconds / step)):
        for p in list(players.values()): p.L.globals().ADVANCE(step)
        while wire:
            to, prefix, text, chan, sender = wire.pop(0)
            if LOSS.get(sender) and text.split("\t")[0] in ("SNAP", "DELT") and random.random() < LOSS[sender]: continue
            if chan == "WHISPER":
                if to in players: players[to].fire("CHAT_MSG_ADDON", prefix, text, chan, sender)
            else:
                for p in list(players.values()): p.fire("CHAT_MSG_ADDON", prefix, text, chan, sender)
def reset():
    players.clear(); wire.clear(); LOSS.clear()
