import os as _os; QA = _os.path.dirname(_os.path.abspath(__file__)); ROOT = _os.path.dirname(QA)
# Static checks from the dev notes: local functions used above their definition, code after a
# comment on the same line, em dashes, leftover dev tools, messages over the wire limit.
import re, sys, glob
SRC = _os.environ.get("STERLING_SRC", _os.path.join(ROOT, "Sterling"))
bad = 0
for path in sorted(glob.glob(SRC + "/*.lua")):
    name = path.split("/")[-1]
    lines = open(path, encoding="utf-8").read().split("\n")
    code = []
    for l in lines:
        # strip strings and comments (roughly) for identifier scanning
        s = re.sub(r'"(?:\\.|[^"\\])*"', '""', l)
        s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
        s = re.sub(r"--.*$", "", s)
        code.append(s)
    decl = {}
    for i, s in enumerate(code):
        for m in re.finditer(r"^local function ([A-Za-z_]\w*)", s): decl.setdefault(m.group(1), i)
        m = re.match(r"^local ([A-Za-z_][\w, ]*?)(?:\s*=|$)", s)
        if m:
            for n in m.group(1).split(","):
                n = n.strip()
                if n: decl.setdefault(n, i)
    for n, at in decl.items():
        if at == 0: continue
        pat = re.compile(r"(?<![\w.:])" + re.escape(n) + r"\s*\(")
        for i in range(at):
            if pat.search(code[i]) and not re.match(r"^\s*local function " + re.escape(n) + r"\b", code[i]):
                # a parameter or inner local of the same name is fine: only flag when no local of that name is in scope in that function
                # (cheap check: is there a 'local n' or a parameter named n within the previous 60 lines?)
                window = "\n".join(code[max(0, i - 80):i + 1])
                if re.search(r"local\s+(?:function\s+)?(?:[\w, ]*\b)?" + re.escape(n) + r"\b", window) or re.search(r"function[^\n(]*\([^)]*\b" + re.escape(n) + r"\b[^)]*\)", window): continue
                print(f"{name}:{i+1}: '{n}' is called here but only becomes a local at line {at+1}"); bad += 1
                break
    for i, l in enumerate(lines):
        if "—" in l or "–" in l: print(f"{name}:{i+1}: em/en dash"); bad += 1
        # a full-line comment that has code-looking text after a semicolon is the 5.82 bug pattern
        m = re.match(r"^\s*--(?!-)(.*)$", l)
        if m and re.search(r"\w+:(ClearAllPoints|SetPoint|Show|Hide|SetText)\(", m.group(1)): print(f"{name}:{i+1}: code inside a comment line?"); bad += 1
        if re.search(r"PrintTabs|ViewerDebug|raceinfo|mapinfo|RECOVERED|/st glow|/st tabs", l): print(f"{name}:{i+1}: leftover dev tool: {l.strip()[:80]}"); bad += 1
print("lint findings:", bad)
