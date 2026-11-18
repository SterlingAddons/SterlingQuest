# Sterling code style: every Lua file in the add-on and in qa/ is formatted by qa/style.py, and still compiles.
import glob
import os
import shutil
import subprocess
import sys

QA = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(QA)
sys.path.insert(0, QA)
import style

files = sorted(glob.glob(os.path.join(ROOT, "Sterling", "*.lua")) + glob.glob(os.path.join(QA, "*.lua")) + glob.glob(os.path.join(QA, "old-scenarios", "*.lua")))
bad = 0


def check(name, ok):
    global bad
    print(("PASS " if ok else "FAIL ") + name)
    bad += 0 if ok else 1


unformatted = [os.path.relpath(f, ROOT) for f in files if style.fmt(open(f, encoding="utf-8").read()) != open(f, encoding="utf-8").read()]
check("every Lua file follows the style (%d files)%s" % (len(files), (": " + ", ".join(unformatted)) if unformatted else ""), not unformatted)

long = "x" * 150
sample = "local t = {\n  a = \"%s\",\n  b = 2,\n}\nif t then\n  print(t.a)\nend\nprint(t.b)\n" % long
once = style.fmt(sample, True)
check("formatting is stable (running it twice changes nothing)", style.fmt(once) == once)
check("  braces go on their own line", "local t =\n{\n" in once)
check("  short statements stay on one line", style.fmt("f(\n  1,\n  2\n)\n", True) == "f(1, 2)\n")
check("  blank line after a block's end", "end\n\nprint" in once)

if shutil.which("luac5.1"):
    broken = [os.path.relpath(f, ROOT) for f in files if subprocess.run(["luac5.1", "-p", f], capture_output=True).returncode]
    check("every Lua file still compiles" + (": " + ", ".join(broken) if broken else ""), not broken)
else:
    print("SKIP compile check (no luac5.1)")

print("ALL OK" if not bad else "%d FAILED" % bad)
