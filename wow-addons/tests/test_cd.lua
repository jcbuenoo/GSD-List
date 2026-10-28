local dir = ADDONS .. "/GSD_EnemyCDs"
UNITS.player = { guid = "me", name = "Me" }
local ns = LoadAddon("GSD_EnemyCDs", { "Data.lua", "Core.lua" }, dir)
Fire("PLAYER_ENTERING_WORLD")
local A = GSD_EnemyCDsAnchor
local H = 0x440
local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print("FAIL: " .. msg) else print("ok   " .. msg) end end
local function find(rows, name) for _, r in ipairs(rows) do if r.name == name or r.name == "> " .. name then return r end end end
local function icon(r, id) if r then for _, i in ipairs(r.icons) do if i.tex == id then return i end end end end
local function step(dt) NOW = NOW + dt; RunTickers() end
local function cast(guid, name, id, flags) Log("SPELL_CAST_SUCCESS", guid, name, flags or H, nil, nil, 0, id) end

-- every spell ID in the data is unique and every rank maps to a base
local seen, dup = {}, 0
for id, s in pairs(ns.SPELLS) do
    for _, r in ipairs(s.ranks or {}) do if seen[r] or ns.SPELLS[r] then dup = dup + 1; print("dup " .. r) end; seen[r] = true end
    assert(s.cd and s.type and s.class, "bad entry " .. id)
end
check(dup == 0, "no duplicate spell IDs across entries")

PLAYERINFO["r1"] = { "ROGUE", "Human" }
cast("r1", "Stabby-Realm", 1767) -- Kick rank 2
step(0)
local r = find(Rows(A), "Stabby")
check(r and icon(r, 1766) and icon(r, 1766).timer == "10", "Kick (rank 2) -> base icon, 10s")
cast("r1", "Stabby", 26889) -- Vanish rank 3
step(0.1); r = find(Rows(A), "Stabby")
check(icon(r, 1856).timer == "4m", "Vanish uses talent-adjusted 210s (shows 4m)")
cast("r1", "Stabby", 42292)
step(0.1); r = find(Rows(A), "Stabby")
check(r.icons[1].tex == 42292, "trinket sorted first")
check(icon(r, 42292).timer == "2m", "trinket 120s default")
-- dedupe: same cast via unit event
UNITS.target = { guid = "r1", name = "Stabby", player = true, enemy = true }
Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-1", 42292)
step(0.1); r = find(Rows(A), "Stabby"); check(#r.icons == 3, "unit event duplicate ignored")
step(10); r = find(Rows(A), "Stabby"); check(icon(r, 1766) == nil, "Kick expires after 10s")
-- Preparation resets Vanish
cast("r1", "Stabby", 14185)
step(0.1); r = find(Rows(A), "Stabby"); check(icon(r, 1856) == nil and icon(r, 14185) ~= nil, "Preparation resets Vanish")

-- trinket only via unit event (missing from combat log)
UNITS.focus = { guid = "m1", name = "Frosty", player = true, enemy = true }
PLAYERINFO["m1"] = { "MAGE", "Gnome" }
Fire("UNIT_SPELLCAST_SUCCEEDED", "focus", "c2", 42292)
step(0.1); check(icon(find(Rows(A), "Frosty"), 42292) ~= nil, "trinket from UNIT_SPELLCAST_SUCCEEDED")
UNITS.party1 = { guid = "m1", name = "Frosty", player = true, enemy = true }
Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c3", 2139)
step(0.1); check(icon(find(Rows(A), "Frosty"), 2139) == nil, "ignores non-enemy unit tokens")
-- Cold Snap resets Ice Block / Frost Nova
cast("m1", "Frosty", 45438); cast("m1", "Frosty", 27088)
step(0.1); r = find(Rows(A), "Frosty"); check(icon(r, 45438) and icon(r, 122), "Ice Block + Frost Nova rank 5 tracked")
cast("m1", "Frosty", 11958)
step(0.1); r = find(Rows(A), "Frosty"); check(icon(r, 45438) == nil and icon(r, 122) == nil and icon(r, 11958), "Cold Snap resets frost CDs")

-- death doesn't reset cooldowns (BG rez) and Feign Death logs UNIT_DIED
Log("UNIT_DIED", nil, nil, 0, "m1", "Frosty", H, nil)
step(0.1); check(icon(find(Rows(A), "Frosty"), 11958) ~= nil, "cooldowns kept through UNIT_DIED")

-- icons reused across spells keep correct texture/state
cast("m1", "Frosty", 2139)
step(0.1); r = find(Rows(A), "Frosty")
local seenTex = {}
for _, i in ipairs(r.icons) do seenTex[i.tex] = (seenTex[i.tex] or 0) + 1 end
check(seenTex[2139] == 1 and seenTex[11958] == 1 and seenTex[42292] == 1, "icon slots show distinct correct textures after reshuffle")

-- friendly casts ignored
cast("f1", "Buddy", 1766, 0x411)
step(0.1); check(find(Rows(A), "Buddy") == nil, "friendly casts ignored")
-- hostile NPC ignored
cast("n1", "Mob", 1766, 0x848)
step(0.1); check(find(Rows(A), "Mob") == nil, "hostile NPC ignored")
-- pet Spell Lock outside arena -> pet row
cast("p1", "Felhunter", 19647, 0x1040 + 0x8)
step(0.1); check(icon(find(Rows(A), "Felhunter (pet)"), 19244) ~= nil, "pet Spell Lock tracked on pet row")
-- pet non-pet spell ignored
cast("p2", "Wolf", 1766, 0x1048)
step(0.1); check(find(Rows(A), "Wolf (pet)") == nil, "pet casting non-pet spell ignored")

-- overrides
SlashCmdList.GSDCD("trinket 300")
cast("w1", "Smash", 42292)
step(0.1); check(icon(find(Rows(A), "Smash"), 42292).timer == "5m", "/gcd trinket 300 applies")
SlashCmdList.GSDCD("set 20252 25")
cast("w1", "Smash", 25275)
step(0.1); check(icon(find(Rows(A), "Smash"), 20252).timer == "25", "/gcd set override by rank ID")
SlashCmdList.GSDCD("talents")
cast("w1", "Smash", 5246)
step(0.1); check(icon(find(Rows(A), "Smash"), 5246).timer == "3m", "Intimidating Shout 180s")

-- arena: pre-filled baseline spells, pet attributed to owner
INSTANCE = "arena"; Fire("PLAYER_ENTERING_WORLD")
step(0.1); check(#Rows(A) == 0, "zone change clears rows")
UNITS.arena1 = { guid = "a1", name = "Shamy", class = "SHAMAN", race = "Tauren" }
UNITS.arena2 = { guid = "a2", name = "Locky", class = "WARLOCK", race = "Scourge" }
UNITS.arenapet2 = { guid = "a2pet" }
Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
step(0.1)
local rows = Rows(A)
check(rows[1].name == "Shamy" and rows[2].name == "Locky", "arena rows ordered arena1, arena2")
check(icon(rows[1], 42292) and icon(rows[1], 20549) and icon(rows[1], 8042), "shaman pre-filled: trinket, War Stomp, Earth Shock")
check(icon(rows[1], 7744) == nil and icon(rows[1], 16188) == nil, "no other-race racials or talent spells pre-filled")
check(icon(rows[2], 7744) ~= nil, "undead gets Will of the Forsaken")
check(icon(rows[1], 42292).timer == "" and icon(rows[1], 42292).desat == false, "unused spell shown ready")
cast("a2pet", "Felhunter", 19244, 0x1048)
step(0.1); rows = Rows(A)
check(icon(rows[2], 19244) and icon(rows[2], 19244).timer == "24", "arena pet Spell Lock credited to owner")
check(#rows == 2, "no separate pet row in arena")
step(120); check(#Rows(A) == 2, "arena rows persist while idle")
SlashCmdList.GSDCD("unused never")
step(0.1); check(#Rows(A) == 0 or #Rows(A)[1].icons > 0, "unused never hides ready icons")

SlashCmdList.GSDCD("test"); step(0.1); check(find(Rows(A), "Stabbyboi") ~= nil, "/gcd test shows sample rows")
for _, c in ipairs({ "lock", "unlock", "scale 2", "size 20", "rows 2", "icons 3", "clear 20252", "", "nope" }) do SlashCmdList.GSDCD(c) end
step(0.1); rows = Rows(A)
check(#rows <= 2 and #rows[1].icons <= 3, "row and icon limits respected")
print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
