# Release zip safety check (security audit): no runnable file types, no names ending in a dot or space,
# no Windows device names. Usage: python3 zipcheck.py <zip>...
import sys, zipfile, re
BAD_EXT = {".exe",".dll",".bat",".cmd",".com",".scr",".msi",".ps1",".vbs",".js",".lnk",".url",".jar",".reg"}
DEV = re.compile(r"^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(\..*)?$", re.I)
bad = 0
for z in sys.argv[1:]:
    names = zipfile.ZipFile(z).namelist()
    exts = {}
    for n in names:
        for part in n.rstrip("/").split("/"):
            low = part.lower()
            why = None
            if any(low.endswith(e) for e in BAD_EXT): why = "runnable type"
            elif part.endswith(".") or part.endswith(" "): why = "ends in dot or space"
            elif DEV.match(part): why = "device name"
            if why: print(f"BAD {z}: {n} ({why})"); bad += 1
        if not n.endswith("/"):
            e = ("." + n.rsplit(".", 1)[-1].lower()) if "." in n.rsplit("/", 1)[-1] else "(none)"
            exts[e] = exts.get(e, 0) + 1
    print(f"{z}: {len(names)} entries, types {dict(sorted(exts.items()))}")
print("ZIP OK" if bad == 0 else f"ZIP HAS {bad} PROBLEMS")
