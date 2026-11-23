local pass, fail = 0, 0
local function T(name, fn)
  CHAT = {}
  local ok, err = pcall(fn)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function chatHas(s) for _, m in ipairs(CHAT) do if m:find(s, 1, true) then return true end end return false end
local RR, anchor, ring, fill, label, slash
local function frame(dt) anchor._scripts.OnUpdate(anchor, dt or 0.11) end
local function settle() for i = 1, 40 do frame(0.11) end end
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end
local function colorIs(zone) local c, z = ring._color, W.RangeRingDB.colors[zone]; return near(c[1], z[1]) and near(c[2], z[2]) and near(c[3], z[3]) end
local function radius() return ring._w / 2 end
local function at(d) UNITS.target.dist = d; RR.dirty = true; settle() end

T("load + login", function()
  fire("ADDON_LOADED", "RangeRing")
  local db = W.RangeRingDB
  assert(db.enabled and db.pxPerYard == 5 and near(db.flat, 0.45) and db.colors.dead[1] == 1.0)
  RR = W.RangeRing; anchor, ring, fill, label = RR.anchor, RR.ring, RR.fill, RR.label
  assert(ring._tex == "Interface\\AddOns\\RangeRing\\media\\ring1")
  assert(not anchor._shown)
  KNOWN = {[2973]=true, [75]=true}
  fire("PLAYER_LOGIN")
  assert(anchor._shown and chatHas("v1.0.0 loaded"))
  assert(ITEMS_LOADED[32321], "item data requested")
  slash = W.SlashCmdList.RANGERING; assert(W.SLASH_RANGERING1 == "/rr")
  assert(anchor._points[1][2] == W.UIParent and anchor._points[1][5] == -40)
end)

T("no / friendly / dead target -> ring hidden", function()
  UNITS.target = nil; frame(); assert(not ring._shown and not label._shown)
  UNITS.target = {hostile=false, dist=3, guid="F"}; frame(); assert(not ring._shown)
  UNITS.target = {hostile=true, dead=true, dist=3, guid="D"}; frame(); assert(not ring._shown)
end)

T("hunter zones out of combat: melee, dead zone, in range, out", function()
  UNITS.target = {hostile=true, dist=3, guid="H"}; fire("PLAYER_TARGET_CHANGED"); settle()
  assert(ring._shown and RR.zone == "melee" and colorIs("melee"), RR.zone)
  at(6.5); assert(RR.zone == "dead" and colorIs("dead"), RR.zone .. " " .. RR.low .. "-" .. RR.high)
  assert(RR.low >= 5 and RR.high <= 8)
  at(12); assert(RR.zone == "ranged" and colorIs("ranged") and RR.low == 11.1 and RR.high == 15, RR.low .. "-" .. RR.high)
  at(33); assert(RR.zone == "ranged" and RR.low == 30 and RR.high == 35)
  at(38); assert(RR.zone == "out" and colorIs("out") and RR.low == 35 and RR.high == 40)
  at(60); assert(RR.zone == "out" and RR.high == math.huge)
  assert(label._text:find("OUT OF RANGE", 1, true) and label._text:find(">40 yd", 1, true), label._text)
end)

T("ring grows with distance and is squashed flat", function()
  local sizes = {}
  for _, d in ipairs({3, 6.5, 9, 12, 18, 23, 28, 33, 38}) do at(d); sizes[#sizes + 1] = radius() end
  for i = 2, #sizes do assert(sizes[i] > sizes[i - 1], ("size did not grow at step %d: %s -> %s"):format(i, sizes[i-1], sizes[i])) end
  assert(near(ring._h, ring._w * 0.45, 1e-3))
  assert(near(fill._w, ring._w))
  assert(ring._tex:find("ring4$"), "big ring uses thin texture: " .. ring._tex)
  at(3); assert(ring._tex:find("ring1$"), "small ring uses thick texture")
end)

T("ring animates instead of jumping", function()
  at(3); local small = radius()
  UNITS.target.dist = 33; RR.dirty = true; frame(0.016)
  local mid = radius()
  assert(mid > small and mid < 14 + 32.5 * 5 - 1, "should be partway: " .. mid)
end)

T("labels", function()
  at(3); assert(label._text == "<5 yd  MELEE", label._text)
  at(12); assert(label._text == "11-15 yd  IN RANGE", label._text)
end)

T("checks throttled to 10/s", function()
  SPELLCALLS = 0; for i = 1, 10 do frame(0.01) end
  assert(SPELLCALLS == 0, SPELLCALLS)
  frame(0.01); assert(SPELLCALLS > 0)
end)

T("combat: blocked item/interact -> one notice, saved, spells still work", function()
  P.combat = true; COMBAT_BLOCK = {item=true, interact=true}; CHAT = {}
  at(20)
  assert(W.RangeRingDB.combatBlocked.item and W.RangeRingDB.combatBlocked.interact)
  local n = 0; for _, m in ipairs(CHAT) do if m:find("blocks", 1, true) then n = n + 1 end end
  assert(n == 2, n)
  assert(RR.zone == "ranged" and RR.low == 8 and RR.high == 35, RR.low .. "-" .. RR.high)
  at(3); assert(RR.zone == "melee")
end)

T("combat spells-only: dead zone vs out of range", function()
  at(3); at(6.5); assert(RR.zone == "dead", "from melee -> dead: " .. RR.zone)
  at(20); assert(RR.zone == "ranged")
  UNITS.target.target = "player"
  at(6.5); assert(RR.zone == "dead", "mob attacking you closes in -> dead: " .. RR.zone)
  at(20); UNITS.target.target = nil
  at(50); assert(RR.zone == "out", "not on you, left range -> out: " .. RR.zone)
  at(60); assert(RR.zone == "out", "stays out")
  at(20); assert(RR.zone == "ranged")
end)

T("out of combat: blocked checks come back", function()
  P.combat = false; COMBAT_BLOCK = {}
  at(12); assert(RR.low == 11.1 and RR.high == 15)
end)

T("ADDON_ACTION_FORBIDDEN for our addon marks that check", function()
  W.RangeRingDB.combatBlocked = {}
  P.combat = true; CHAT = {}
  fire("ADDON_ACTION_FORBIDDEN", "OtherAddon", "IsItemInRange()"); assert(not W.RangeRingDB.combatBlocked.item)
  fire("ADDON_ACTION_FORBIDDEN", "RangeRing", "C_Item.IsItemInRange()"); assert(W.RangeRingDB.combatBlocked.item)
  fire("ADDON_ACTION_BLOCKED", "RangeRing", "CheckInteractDistance()"); assert(W.RangeRingDB.combatBlocked.interact)
  P.combat = false; W.RangeRingDB.combatBlocked = {}
end)

T("secret answers ignored", function()
  local s = {}; SECRETS[s] = true; SPELL_OVERRIDE = s
  at(12); assert(RR.zone == "ranged" and RR.low == 11.1, "items still decide")
  SPELL_OVERRIDE = nil
end)

T("mage: no dead zone, spells + items", function()
  CLASS = "MAGE"; KNOWN = {[116]=true, [133]=true, [2136]=true}; fire("SPELLS_CHANGED")
  at(3); assert(RR.zone == "ranged" and RR.high == 8, "a mage can only tell 'within 8 yd': " .. RR.zone)
  at(6.5); assert(RR.zone == "ranged", RR.zone)
  at(38); assert(RR.zone == "out")
  P.combat = true; W.RangeRingDB.combatBlocked = {item=true, interact=true}
  at(25); assert(RR.zone == "ranged" and RR.low == 20 and RR.high == 30, RR.low .. "-" .. RR.high)
  P.combat = false; W.RangeRingDB.combatBlocked = {}
  CLASS = "HUNTER"; KNOWN = {[2973]=true, [75]=true}; fire("SPELLS_CHANGED")
end)

T("warrior in combat with nothing to check -> white unknown, no error", function()
  CLASS = "WARRIOR"; KNOWN = {}; fire("SPELLS_CHANGED")
  P.combat = true; W.RangeRingDB.combatBlocked = {item=true, interact=true}
  at(20); assert(RR.zone == "unknown" and ring._shown and colorIs("unknown"))
  P.combat = false; W.RangeRingDB.combatBlocked = {}
  CLASS = "HUNTER"; KNOWN = {[2973]=true, [75]=true}; fire("SPELLS_CHANGED")
end)

T("test preview runs without a target and stops after 8 s", function()
  UNITS.target = nil
  slash("test"); frame(); assert(ring._shown and label._text:find("TEST", 1, true))
  local zones = {}
  for i = 1, 40 do CLOCK = CLOCK + 0.1; frame(0.1); zones[label._text:match("yd  (.+)$")] = true end
  assert(zones.MELEE and zones["DEAD ZONE"] and zones["IN RANGE"] and zones["OUT OF RANGE"])
  CLOCK = CLOCK + 9; frame(); frame(); assert(not ring._shown)
end)

T("unlock / drag / lock saves position", function()
  slash("unlock"); assert(anchor._mouse and RR.unlocked)
  frame(); assert(ring._shown and label._text:find("drag", 1, true))
  anchor._cx, anchor._cy = 1000, 450
  anchor._scripts.OnDragStop(anchor)
  assert(W.RangeRingDB.x == 40 and W.RangeRingDB.y == -90)
  slash("lock"); assert(not anchor._mouse and not RR.unlocked)
  local p = anchor._points[#anchor._points]; assert(p[4] == 40 and p[5] == -90)
end)

T("settings commands + validation", function()
  UNITS.target = {hostile=true, dist=12, guid="H2"}; fire("PLAYER_TARGET_CHANGED"); settle()
  local r5 = radius(); slash("size 10"); settle(); assert(radius() > r5 * 1.5)
  CHAT = {}; slash("size 0"); assert(chatHas("usage"))
  slash("flat 1"); settle(); assert(near(ring._h, ring._w, 1e-3))
  CHAT = {}; slash("flat 5"); assert(chatHas("usage"))
  slash("alpha 0.5"); settle(); assert(near(ring._color[4], 0.5))
  slash("fill"); settle(); assert(not fill._shown); slash("fill"); settle(); assert(fill._shown)
  slash("label"); settle(); assert(not label._shown); slash("label")
  slash("guides"); settle(); assert(RR.guides[3]._shown and near(RR.guides[3]._w / 2, 14 + 35 * 10))
  slash("guides"); settle(); assert(not RR.guides[1]._shown)
  slash("color ranged 0 0 255"); settle(); assert(near(ring._color[3], 1) and near(ring._color[1], 0))
  CHAT = {}; slash("color nope 1 0 0"); assert(chatHas("usage"))
  CHAT = {}; slash("color dead 1 0"); assert(chatHas("usage"))
  CHAT = {}; slash("status"); assert(chatHas("Auto Shot") and chatHas("IN RANGE"))
end)

T("on/off/toggle/help/reset", function()
  slash("off"); assert(not anchor._shown)
  slash("toggle"); assert(anchor._shown)
  CHAT = {}; slash(""); assert(chatHas("commands"))
  slash("reset"); local db = W.RangeRingDB
  assert(db.pxPerYard == 5 and db.flat == 0.45 and db.colors.ranged[3] == 0.25 and RR.db == db)
end)

T("saved-data repair", function()
  W.RangeRingDB = {pxPerYard = "huge", colors = {dead = 3}, enabled = false}
  fire("ADDON_LOADED", "RangeRing")
  local db = W.RangeRingDB
  assert(db.pxPerYard == 5 and type(db.colors.dead) == "table" and db.colors.melee and db.enabled == false)
  fire("PLAYER_LOGIN"); assert(not anchor._shown)
  slash("on")
end)

T("performance: 10k frames", function()
  local t = os.clock(); for i = 1, 10000 do frame(0.016) end
  assert(os.clock() - t < 1.5, "too slow: " .. (os.clock() - t))
end)

print(pass .. " passed, " .. fail .. " failed")
TEST_FAILURES = fail
