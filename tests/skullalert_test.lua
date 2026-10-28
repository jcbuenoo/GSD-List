-- Offline test for SkullAlert against a mocked WoW API (Lua 5.1, like the game client).
-- Run from the repo root:  lua5.1 tests/skullalert_test.lua

local ADDON_FILE = "SkullAlert/SkullAlert.lua"
local passed, failed = 0, 0

local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end

-- ---------------------------------------------------------------- mock API
local W -- world state, rebuilt per scenario

local function newWorld(opts)
    W = {
        out = {}, sent = {}, warnings = 0, sounds = 0, registered = {}, units = {},
        now = 1000, playerLevel = opts.level or 53, playerFaction = opts.faction or "Horde",
        raid = false, party = false, leader = false, assist = false, cle = {},
    }
end

local frameObj = {}
function frameObj:RegisterEvent(e) W.registered[e] = true end
function frameObj:UnregisterEvent(e) W.registered[e] = nil end
function frameObj:SetScript(_, f) self.onEvent = f end

local env = {
    CreateFrame = function() return frameObj end,
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(W.out, m) end },
    RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } },
    GetZoneText = function() return "Stranglethorn Vale" end,
    GetSubZoneText = function() return "Booty Bay" end,
    GetTime = function() return W.now end,
    IsInRaid = function() return W.raid end,
    IsInGroup = function() return W.raid or W.party end,
    UnitIsGroupLeader = function() return W.leader end,
    UnitIsGroupAssistant = function() return W.assist end,
    SendChatMessage = function(t, c) table.insert(W.sent, { text = t, channel = c }) end,
    RaidWarningFrame = {},
    ChatTypeInfo = { RAID_WARNING = {} },
    RaidNotice_AddMessage = function(_, t) W.warnings = W.warnings + 1; W.lastWarning = t end,
    SOUNDKIT = { RAID_WARNING = 8959 },
    PlaySound = function() W.sounds = W.sounds + 1 end,
    COMBATLOG_OBJECT_TYPE_PLAYER = 0x400,
    COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40,
    CombatLogGetCurrentEventInfo = function() return unpack(W.cle) end,
    UnitExists = function(u) return W.units[u] ~= nil end,
    UnitIsPlayer = function(u) return W.units[u] and W.units[u].player end,
    UnitFactionGroup = function(u)
        if u == "player" then return W.playerFaction end
        return W.units[u] and W.units[u].faction
    end,
    UnitGUID = function(u) return W.units[u] and W.units[u].guid end,
    -- Units 10+ levels above you report -1 (shown as ??). Applied to friendly units too so
    -- the faction filter is tested on its own.
    UnitLevel = function(u)
        local d = W.units[u]
        if d.level >= W.playerLevel + 10 then return -1 end
        return d.level
    end,
    UnitClass = function(u) return W.units[u].class or "Rogue", W.units[u].classFile or "ROGUE" end,
    UnitName = function(u) return W.units[u].name, W.units[u].realm end,
    UnitRace = function() return "Night Elf" end,
    GetGuildInfo = function(u) return W.units[u].guild end,
    UNKNOWN = "Unknown",
    strlower = string.lower,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    SlashCmdList = {},
    bit = { bor = function(a, b) return a + b end,
            band = function(a, b) local r, p = 0, 1
                while a > 0 and b > 0 do
                    if a % 2 == 1 and b % 2 == 1 then r = r + p end
                    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
                end
                return r end },
}
setmetatable(env, { __index = _G })
local baseline = {}
for k in pairs(env) do baseline[k] = true end

local function boot(opts, savedDB)
    newWorld(opts or {})
    env.SkullAlertDB = savedDB
    env.SlashCmdList = {}
    local chunk = assert(loadfile(ADDON_FILE))
    setfenv(chunk, env)
    chunk("SkullAlert")
    frameObj.onEvent(frameObj, "ADDON_LOADED", "SomeOtherAddon")
    frameObj.onEvent(frameObj, "ADDON_LOADED", "SkullAlert")
    frameObj.onEvent(frameObj, "PLAYER_LOGIN")
end

local function fire(event, ...)
    if W.registered[event] then frameObj.onEvent(frameObj, event, ...) end
end
local function slash(s) env.SlashCmdList.SKULLALERT(s) end
local function enemy(unit, guid, level, extra)
    local d = { player = true, faction = W.playerFaction == "Horde" and "Alliance" or "Horde",
        guid = guid, level = level, name = "Enemy" .. guid }
    for k, v in pairs(extra or {}) do d[k] = v end
    W.units[unit] = d
end
local function cle(src, srcFlags, dst, dstFlags)
    W.cle = { 0, "SPELL_DAMAGE", false, src, "x", srcFlags, 0, dst, "y", dstFlags or 0 }
    fire("COMBAT_LOG_EVENT_UNFILTERED")
end
local HOSTILE_PLAYER_FLAGS = 0x548 -- player + hostile + outsider

-- ---------------------------------------------------------------- scenarios
-- Level threshold at 53: 62 is visible, 63+ is ??
boot()
enemy("target", "G62", 62); fire("PLAYER_TARGET_CHANGED")
check("level 62 enemy does not alert at 53", W.warnings == 0)
enemy("target", "G63", 63); fire("PLAYER_TARGET_CHANGED")
check("level 63 enemy alerts at 53", W.warnings == 1 and W.sounds == 1)
enemy("target", "G70", 70); fire("PLAYER_TARGET_CHANGED")
check("level 70 enemy alerts at 53", W.warnings == 2)
check("warning names opposing faction", W.lastWarning:find("SKULL ALLIANCE", 1, true) ~= nil)
check("chat line printed", W.out[#W.out]:find("Level ??", 1, true) ~= nil)

-- Filters
boot()
W.units.target = { player = true, faction = "Horde", guid = "F1", level = 70, name = "Friend" }
fire("PLAYER_TARGET_CHANGED")
check("same faction 70 ignored", W.warnings == 0)
W.units.target = { player = false, faction = "Alliance", guid = "NPC", level = 70, name = "Guard" }
fire("PLAYER_TARGET_CHANGED")
check("?? NPC ignored", W.warnings == 0)
W.units.target = nil; fire("PLAYER_TARGET_CHANGED")
check("no target does not error", W.warnings == 0)

-- Every detection source
boot()
enemy("focus", "S1", 70); fire("PLAYER_FOCUS_CHANGED")
enemy("mouseover", "S2", 70); fire("UPDATE_MOUSEOVER_UNIT")
enemy("nameplate7", "S3", 70); fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
enemy("party2target", "S4", 70); fire("UNIT_TARGET", "party2")
enemy("raid17target", "S5", 70); fire("UNIT_TARGET", "raid17")
enemy("targettarget", "S6", 70); fire("UNIT_TARGET", "target")
check("all six sources alert", W.warnings == 6)
check("source label strips digits", W.out[3]:find("via nameplate near", 1, true) ~= nil)
enemy("playertarget", "S7", 70); fire("UNIT_TARGET", "player")
check("UNIT_TARGET player ignored (PLAYER_TARGET_CHANGED covers it)", W.warnings == 6)

-- Cooldown and dedupe across sources
boot()
enemy("nameplate1", "C1", 70); enemy("target", "C1", 70); enemy("mouseover", "C1", 70)
fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); fire("PLAYER_TARGET_CHANGED"); fire("UPDATE_MOUSEOVER_UNIT")
check("same player via 3 sources = 1 alert", W.warnings == 1)
W.now = W.now + 59; fire("PLAYER_TARGET_CHANGED")
check("no re-alert inside cooldown", W.warnings == 1)
W.now = W.now + 1; fire("PLAYER_TARGET_CHANGED")
check("re-alert after cooldown", W.warnings == 2)

-- Combat log is only registered while skulls are known
boot()
check("combat log not registered with no skulls", not W.registered.COMBAT_LOG_EVENT_UNFILTERED)
enemy("target", "K1", 70); fire("PLAYER_TARGET_CHANGED")
check("combat log registered after first skull", W.registered.COMBAT_LOG_EVENT_UNFILTERED)
W.now = W.now + 61
cle("unknown", HOSTILE_PLAYER_FLAGS, nil, 0)
check("unknown guid in combat log ignored", W.warnings == 1)
cle("K1", 0x511, nil, 0) -- friendly flags
check("known guid with friendly flags ignored", W.warnings == 1)
cle("someone", 0x511, "K1", HOSTILE_PLAYER_FLAGS)
check("known skull as destination alerts", W.warnings == 2)
W.now = W.now + 61
cle("K1", HOSTILE_PLAYER_FLAGS, nil, 0)
check("known skull as source alerts", W.warnings == 3)
slash("reset")
check("reset unregisters combat log", not W.registered.COMBAT_LOG_EVENT_UNFILTERED)
enemy("target", "K1", 70); fire("PLAYER_TARGET_CHANGED")
fire("PLAYER_LEVEL_UP", 54)
check("level up unregisters combat log", not W.registered.COMBAT_LOG_EVENT_UNFILTERED)

-- Player becomes visible (you dinged) -> forgotten
boot()
enemy("target", "D1", 63); fire("PLAYER_TARGET_CHANGED")
W.playerLevel = 54; fire("PLAYER_TARGET_CHANGED")
check("no longer ?? gets forgotten", not W.registered.COMBAT_LOG_EVENT_UNFILTERED)

-- Disable / enable
boot()
slash("off")
check("off unregisters scan events", not W.registered.PLAYER_TARGET_CHANGED and not W.registered.UNIT_TARGET)
enemy("target", "E1", 70); fire("PLAYER_TARGET_CHANGED")
check("no alert while off", W.warnings == 0)
slash("on"); fire("PLAYER_TARGET_CHANGED")
check("alerts again after on", W.warnings == 1)
slash("combatlog off")
check("combatlog off unregisters", not W.registered.COMBAT_LOG_EVENT_UNFILTERED)

-- Output toggles
boot()
slash("warning off"); slash("sound off"); slash("chat off")
local lines = #W.out
enemy("target", "T1", 70); fire("PLAYER_TARGET_CHANGED")
check("all outputs off = silent", W.warnings == 0 and W.sounds == 0 and #W.out == lines)

-- Broadcast channels
boot()
enemy("target", "B1", 70, { guild = "Gankers" }); W.party = true; fire("PLAYER_TARGET_CHANGED")
check("broadcast off by default", #W.sent == 0)
slash("broadcast on")
W.now = W.now + 61; fire("PLAYER_TARGET_CHANGED")
check("party -> PARTY", W.sent[1] and W.sent[1].channel == "PARTY")
check("broadcast text has guild and {skull}", W.sent[1].text:find("<Gankers>", 1, true) and W.sent[1].text:find("{skull}", 1, true))
check("broadcast has no UI escape codes", not W.sent[1].text:find("|", 1, true))
W.raid = true
enemy("target", "B2", 70); W.now = W.now + 1; fire("PLAYER_TARGET_CHANGED")
check("broadcast gap throttles", #W.sent == 1)
W.now = W.now + 3; enemy("target", "B3", 70); fire("PLAYER_TARGET_CHANGED")
check("raid member -> RAID", W.sent[2] and W.sent[2].channel == "RAID")
W.assist = true; W.now = W.now + 3; enemy("target", "B4", 70); fire("PLAYER_TARGET_CHANGED")
check("raid assist -> RAID_WARNING", W.sent[3] and W.sent[3].channel == "RAID_WARNING")
W.raid, W.party = false, false; W.now = W.now + 3; enemy("target", "B5", 70); fire("PLAYER_TARGET_CHANGED")
check("solo sends nothing", #W.sent == 3)
W.party = true; W.now = W.now + 3; slash("test")
check("test never broadcasts", #W.sent == 3 and W.warnings > 0)

-- Slash parsing
boot()
slash("BROADCAST  ON")
check("uppercase + double space parses", env.SkullAlertDB.broadcast == true)
slash("broadcast")
check("bare toggle flips", env.SkullAlertDB.broadcast == false)
slash("cd 2.7")
check("cd floors to integer", env.SkullAlertDB.cooldown == 2)
slash("cd abc"); check("bad cd shows usage", W.out[#W.out]:find("usage", 1, true) ~= nil)
slash("cd -5"); check("negative cd rejected", env.SkullAlertDB.cooldown == 2)
local before = #W.out; slash("")
check("empty shows help", #W.out > before)
before = #W.out; slash("blah"); check("unknown shows help", #W.out > before)
slash("status"); check("status prints", W.out[#W.out]:find("cooldown 2s", 1, true) ~= nil)

-- Saved variables
boot({}, { broadcast = true, cooldown = 30 })
check("saved settings kept", env.SkullAlertDB.broadcast == true and env.SkullAlertDB.cooldown == 30)
check("missing keys filled", env.SkullAlertDB.sound == true and env.SkullAlertDB.combatLog == true)

-- Alliance perspective, realm names, unknown class colour
boot({ faction = "Alliance" })
enemy("target", "R1", 70, { realm = "Spineshatter", classFile = "NOTACLASS" }); fire("PLAYER_TARGET_CHANGED")
check("alliance player sees HORDE", W.lastWarning:find("SKULL HORDE", 1, true) ~= nil)
check("realm appended", W.lastWarning:find("EnemyR1-Spineshatter", 1, true) ~= nil)

-- No globals leaked besides the saved variable and slash registration
local allowed = { SkullAlertDB = true, SLASH_SKULLALERT1 = true, SLASH_SKULLALERT2 = true }
local leaked = {}
for k in pairs(env) do
    if not baseline[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end
end
check("no leaked globals (" .. table.concat(leaked, ",") .. ")", #leaked == 0)

-- ---------------------------------------------------------------- cost
boot()
local N = 200000
W.cle = { 0, "SWING_DAMAGE", false, "a", "x", 0x548, 0, "b", "y", 0x511 }
local t = os.clock()
for _ = 1, N do fire("COMBAT_LOG_EVENT_UNFILTERED") end
local idle = os.clock() - t
enemy("target", "P1", 70); fire("PLAYER_TARGET_CHANGED")
t = os.clock()
for _ = 1, N do fire("COMBAT_LOG_EVENT_UNFILTERED") end
local busy = os.clock() - t
W.units.nameplate1 = { player = false, faction = "Alliance", guid = "M", level = 30 }
t = os.clock()
for _ = 1, N do fire("NAME_PLATE_UNIT_ADDED", "nameplate1") end
local plates = os.clock() - t
print(string.format("cost: %d combat log events with no skulls known: %.3fs (handler not registered)", N, idle))
print(string.format("cost: %d combat log events with a skull known: %.3fs (%.2f us each)", N, busy, busy / N * 1e6))
print(string.format("cost: %d mob nameplate events: %.3fs (%.2f us each)", N, plates, plates / N * 1e6))

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
