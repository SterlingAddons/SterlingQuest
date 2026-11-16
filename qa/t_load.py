import sim
p = sim.Player("Kaelith Emberfall", [(188, "Tiger Mastery")], [185, 186])
sim.pump(12)
print("errors:", p.errors())
for c in p.chat(): print("CHAT:", sim.re.sub(r"\|c\w{8}|\|r", "", c))
print("version", p.ev("select(1, ...)") if False else p.S.ADDON_VER, "build", p.S.BUILD, "buildof", p.S.BuildOf(p.S.ADDON_VER))
print("CTL", p.ev("ChatThrottleLib and ChatThrottleLib.version"), "LibDeflate", p.ev("LibStub and LibStub('LibDeflate', true) and LibStub('LibDeflate')._VERSION"))
print("welcome shown:", p.ev("SterlingQuestWelcome and SterlingQuestWelcome:IsShown()"), "main shown:", p.ev("SterlingQuestFrame:IsShown()"))
