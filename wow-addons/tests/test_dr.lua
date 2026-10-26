local dir = ADDONS .. "/GSD_DRTracker"
UNITS.player = { guid = "me", name = "Me" }
local ns = LoadAddon("GSD_DRTracker", { "Data.lua", "Core.lua" }, dir)
Fire("PLAYER_LOGIN"); Fire("PLAYER_ENTERING_WORLD")
local A = GSD_DRTrackerAnchor
local H = 0x440 -- hostile player
local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print("FAIL: " .. msg) else print("ok   " .. msg) end end
local function find(rows, name) for _, r in ipairs(rows) do if r.name == name or r.name == "> " .. name then return r end end end
local function icon(r, label) if r then for _, i in ipairs(r.icons) do if i.label == label then return i end end end end
local function step(dt) NOW = NOW + dt; RunTickers() end
PLAYERINFO["e1"] = { "PRIEST", "Human" }

Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e1", "Healbot-Realm", H, 11297) -- Sap
step(0)
local r = find(Rows(A), "Healbot")
check(r ~= nil, "row created with realm stripped")
local i = icon(r, "Incap")
check(i and i.level == "50%" and i.timer == "", "Sap -> Incap 50% next, active (no timer)")

step(2); Log("SPELL_AURA_REMOVED", "me", "Me", 0x511, "e1", "Healbot", H, 11297)
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e1", "Healbot", H, 1833) -- Cheap Shot
step(4); Log("SPELL_AURA_REMOVED", "me", "Me", 0x511, "e1", "Healbot", H, 1833)
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e1", "Healbot", H, 8643) -- Kidney
step(0.1)
r = find(Rows(A), "Healbot")
check(icon(r, "Stun").level == "50%" and icon(r, "Stun").timer == "20", "Cheap Shot faded -> Stun 50%, 20s reset timer")
check(icon(r, "Kidney") and icon(r, "Kidney").level == "50%", "Kidney Shot is its own category (50%)")
check(icon(r, "Incap").timer == "16", "Sap reset timer counting down (16s left)")
check(r.icons[1].label == "Stun" and r.icons[2].label == "Kidney" and r.icons[3].label == "Incap", "category order Stun, Kidney, Incap")

step(5); Log("SPELL_AURA_APPLIED", "x", "Pally", H, "e1", "Healbot", H, 10308) -- HoJ, DR shared with Cheap Shot
step(0.1); r = find(Rows(A), "Healbot")
check(icon(r, "Stun").level == "25%", "HoJ within window -> Stun 25% next")
step(3); Log("SPELL_AURA_REMOVED", "x", "Pally", H, "e1", "Healbot", H, 10308)
Log("SPELL_AURA_APPLIED", "x", "War", H, "e1", "Healbot", H, 25274) -- Intercept stun
step(0.1); r = find(Rows(A), "Healbot")
check(icon(r, "Stun").level == "IMM", "third stun -> immune")
Log("SPELL_AURA_REFRESH", "x", "War", H, "e1", "Healbot", H, 25274)
step(0.1); r = find(Rows(A), "Healbot")
check(icon(r, "Stun").level == "IMM", "level capped at immune")
Log("SPELL_AURA_REMOVED", "x", "War", H, "e1", "Healbot", H, 25274)
step(19.5); r = find(Rows(A), "Healbot")
check(icon(r, "Stun") ~= nil, "stun DR still present at 19.5s")
step(0.6); r = find(Rows(A), "Healbot")
check(r == nil or icon(r, "Stun") == nil, "stun DR gone after 20s")

-- friendly dest ignored
Log("SPELL_AURA_APPLIED", "e9", "Enemy", H, "f1", "Buddy", 0x411, 1833)
step(0.1); check(find(Rows(A), "Buddy") == nil, "friendly player not tracked")
-- self tracking off by default
Log("SPELL_AURA_APPLIED", "e9", "Enemy", H, "me", "Me", 0x511, 1833)
step(0.1); check(find(Rows(A), "You") == nil, "self not tracked by default")
SlashCmdList.GSDDR("self")
Log("SPELL_AURA_REMOVED", "e9", "Enemy", H, "me", "Me", 0x511, 1833)
Log("SPELL_AURA_APPLIED", "e9", "Enemy", H, "me", "Me", 0x511, 1833)
step(0.1); check(find(Rows(A), "You") ~= nil, "self tracked after /gdr self")

-- failsafe when aura removal is never seen
Log("SPELL_AURA_APPLIED", "x", "Lock", H, "e2", "Runner", H, 6215) -- Fear
step(59); r = find(Rows(A), "Runner"); check(icon(r, "Fear").timer == "", "fear still active at 59s without removal")
step(2); r = find(Rows(A), "Runner"); check(icon(r, "Fear").timer ~= "", "failsafe started reset timer after 60s")
step(20); check(find(Rows(A), "Runner") == nil, "failsafe entry gone 20s later")

-- spellID 0 fallback by name
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e3", "Zero", H, 0)
CLEU[12] = 0; CLEU[13] = "Spell2094"; Fire("COMBAT_LOG_EVENT_UNFILTERED")
step(0.1); r = find(Rows(A), "Zero"); check(icon(r, "Blind/Cyc") ~= nil, "spellID 0 resolved by name (Blind)")

-- presets
Log("SPELL_AURA_APPLIED", "x", "Lock", H, "e3", "Zero", H, 6215)
step(0.1); check(icon(find(Rows(A), "Zero"), "Fear") ~= nil, "fear shown with all categories")
SlashCmdList.GSDDR("preset rogue")
step(0.1); r = find(Rows(A), "Zero"); check(icon(r, "Fear") == nil and icon(r, "Blind/Cyc") ~= nil, "rogue preset hides fear, keeps Blind")
SlashCmdList.GSDDR("preset all")

-- unit died
Log("UNIT_DIED", nil, nil, 0, "e3", "Zero", H, nil)
step(0.1); check(find(Rows(A), "Zero") == nil, "UNIT_DIED clears unit")

-- target goes first
UNITS.target = { guid = "e5" }
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e4", "Alpha", H, 1833)
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e5", "Bravo", H, 1833)
Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "e4", "Alpha", H, 2094)
step(0.1); check(Rows(A)[1].name == "> Bravo", "current target sorted first and marked")

-- test mode + commands don't error
SlashCmdList.GSDDR("test"); step(0.1); check(find(Rows(A), "Healbot") ~= nil, "/gdr test shows sample rows")
for _, c in ipairs({ "lock", "unlock", "scale 1.5", "size 40", "rows 3", "reset 18", "cats", "cat fear", "", "bogus" }) do SlashCmdList.GSDDR(c) end
step(0.1); check(#Rows(A) <= 3, "rows limit respected")
print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
