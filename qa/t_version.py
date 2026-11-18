# Versioning from 0.3.17.01: internal builds add a fourth part (0.3.17.01, .02 ...), releases drop it and bump the third.
# Internal builds sort after the release they started from and before the next one; older copies still read them.
import os
import re
import sim

QA = os.path.dirname(os.path.abspath(__file__))
ok = True


def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if extra and not cond else ""))

    if not cond:
        ok = False


A = sim.Player("Kaelith Emberfall")
B = A.S.BuildOf
toc = open(os.path.join(sim.SRC, "Sterling.toc"), encoding="utf-8").read()
ver = re.search(r"## Version: (\S+)", toc).group(1)
build = int(re.search(r"## X-Build: (\d+)", toc).group(1))

check("toc X-Build matches the version (%s = %d)" % (ver, build), B(ver) == build and A.S.BUILD == build)
check("internal builds sort between releases: 0.3.17 < 0.3.17.01 < 0.3.17.14 < 0.3.18",
      B("0.3.17") < B("0.3.17.01") < B("0.3.17.14") < B("0.3.18") < B("0.3.18.01") < B("0.3.19"))
check("  0.3.17 = 317000, 0.3.17.03 = 317003, 0.3.18 = 318000", (B("0.3.17"), B("0.3.17.03"), B("0.3.18")) == (317000, 317003, 318000))
check("  a leading zero doesn't matter (0.3.17.03 = 0.3.17.3)", B("0.3.17.03") == B("0.3.17.3"))
check("  three-digit internal parts if ever needed (0.3.17.99 < 0.3.17.100 < 0.3.18)", B("0.3.17.99") < B("0.3.17.100") < B("0.3.18"))
check("older versions keep their order: 5.84 < 6.29 < 0.2.30 < 0.3.17 < 1.0.0",
      B("5.84") < B("6.29") < B("0.2.30") < B("0.3.17") < B("1.0.0"))
check("CompareVer: an internal build is newer than its release, older than the next",
      A.S.CompareVer("0.3.17.02", "0.3.17") == 1 and A.S.CompareVer("0.3.17.02", "0.3.18") == -1 and A.S.CompareVer("0.3.17.02", "0.3.17.2") == 0)

# A partner's version, as their AVER message would leave it, against this copy
me = A.S.ADDON_VER
A.S.AddPartner("Brannoc Ashvale", True)


def state(theirs):
    A.S.FindPartner("Brannoc Ashvale")[0].ver = theirs
    return A.S.VersionState("Brannoc Ashvale")[0]


check("partner on the release this build started from shows as older", state("0.3.17") == "older")
check("partner on the next release shows as newer", state("0.3.18") == "newer")
check("partner on the same internal build is the same", state(me) == "same")

# What a copy from before this change makes of a four-part version: its BuildOf (0.3.17) is copied here as it was.
OLD = '''
local function oldBuildOf(ver)
    if not ver then return nil end
    local p = {}
    for n in tostring(ver):gmatch("%d+") do p[#p + 1] = tonumber(n) end
    if #p == 0 then return nil end
    local a, b, c = p[1], p[2] or 0, p[3] or 0
    if a == 0 then return b * 100 + c end
    if a >= 5 and #p <= 2 then return (a - 4) * 100 + b end
    return a * 10000 + b * 100 + c
end
return oldBuildOf
'''
old = A.L.execute(OLD)
check("an older copy reads 0.3.17.01 without an error (as 0.3.17)", old("0.3.17.01") == 317)
check("  so a friend on 0.3.16 sees it as newer, and one on 0.3.17 as the same", old("0.3.17.01") > old("0.3.16") and old("0.3.17.01") == old("0.3.17"))
check("  and 0.3.18 still reads as newer than any 0.3.17.x", old("0.3.18") > old("0.3.17.99"))
check("AVER accepts a four-part version (digits and dots)", re.fullmatch(r"[\d.]+", "0.3.17.01") is not None)
check("no Lua errors", A.errors() == 0, A.errors())
print("ALL OK" if ok else "SOME FAILED")
