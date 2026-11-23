-- Range Ring: a ring around your character that grows with the distance to your hostile target.
-- Colors: melee, dead zone (hunters, 5-8 yd), in range (up to 35 yd), out of range.
--
-- How distance is found: WoW doesn't give addons other units' positions, so the addon combines yes/no range
-- checks (your spells, a few items and the game's interact distances) into a "between X and Y yards" bracket.
-- Nothing touches nameplates, so none of the nameplate restrictions apply.
local ADDON = ...

local RR = {}
RangeRing = RR

local VERSION = "1.0.0"
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local CHECK_INTERVAL = 0.1   -- seconds between range checks; the ring animates every frame
local MELEE_YD, DEAD_YD, MAX_YD = 5, 8, 35

local DEFAULTS = {
  enabled = true,
  x = 0, y = -40,            -- ring centre, from the screen centre (UI units). Drag it with /rr unlock.
  pxPerYard = 5,             -- ring radius per yard of distance
  flat = 0.45,               -- height/width: < 1 makes the ring lie flat like it's on the ground
  alpha = 0.9,
  fill = true,               -- faint colored fill inside the ring
  label = true,              -- "8-10 yd  IN RANGE" text under the ring
  guides = false,            -- faint fixed rings at 5, 8 and 35 yd
  combatBlocked = {},        -- range checks the game refused in combat; skipped in combat from then on
  colors = {
    melee   = {1.0, 0.82, 0.1},
    dead    = {1.0, 0.15, 0.15},
    ranged  = {0.15, 1.0, 0.25},
    out     = {0.6, 0.6, 0.6},
    unknown = {1.0, 1.0, 1.0},
  },
}

local ZONE_TEXT = {melee = "MELEE", dead = "DEAD ZONE", ranged = "IN RANGE", out = "OUT OF RANGE", unknown = "?"}

-- Melee abilities (rank 1 IDs; every learned rank stays known in TBC).
local MELEE_SPELLS = {
  WARRIOR = {1715, 78, 772, 7386},       -- Hamstring, Heroic Strike, Rend, Sunder Armor
  ROGUE   = {1752, 2098, 53},            -- Sinister Strike, Eviscerate, Backstab
  HUNTER  = {2973, 2974, 1495},          -- Raptor Strike, Wing Clip, Mongoose Bite
  DRUID   = {1082, 6807, 5221, 1822},    -- Claw, Maul, Shred, Rake
  PALADIN = {35395},                     -- Crusader Strike (talent)
  SHAMAN  = {17364},                     -- Stormstrike (talent)
}
-- Spells with no minimum range: {spellID, yards}. "In range" means within that many yards.
local RANGE_SPELLS = {
  MAGE    = {{2136, 20}, {116, 30}, {133, 35}},  -- Fire Blast, Frostbolt, Fireball
  WARLOCK = {{686, 30}},                          -- Shadow Bolt
  PRIEST  = {{585, 30}, {589, 30}},               -- Smite, Shadow Word: Pain
  DRUID   = {{5176, 30}, {8921, 30}},             -- Wrath, Moonfire
  SHAMAN  = {{8042, 20}, {403, 30}},              -- Earth Shock, Lightning Bolt
  PALADIN = {{20271, 10}, {853, 10}},             -- Judgement, Hammer of Justice
}
local AUTO_SHOT = 75 -- hunters: in range from 8 to 35 yd; "out of range" both inside 8 yd and past 35 yd
-- Items the game can range-check without you owning them (hostile targets): {itemID, yards}
local RANGE_ITEMS = {
  {34368, 8},   -- Attuned Crystal Cores
  {32321, 10},  -- Sparrowhawk Net
  {33069, 15},  -- Sturdy Rope
  {10645, 20},  -- Gnomish Death Ray
  {24268, 25},  -- Netherweave Net
  {835, 30},    -- Large Rope Net
  {24269, 35},  -- Heavy Netherweave Net
  {28767, 40},  -- The Decapitator
}
-- CheckInteractDistance indexes: {index, yards}
local INTERACT = {{3, 9.9}, {2, 11.1}, {4, 28}}

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RangeRing|r: " .. msg) end

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil or type(dst[k]) ~= type(v) then
      dst[k] = v
    end
  end
  return dst
end

-- Secret (hidden) values can't be compared by addons in this client: treat them as "no answer".
local function Answer(ok, v)
  if not ok or v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v == true or v == 1
end

---------------------------------------------------------------------------
-- Range checks
---------------------------------------------------------------------------
local class
local meleeSpells, rangeSpells, hasAutoShot = {}, {}, false

local function Knows(id)
  return (IsSpellKnown and IsSpellKnown(id)) or (IsPlayerSpell and IsPlayerSpell(id)) or false
end

function RR:RefreshSpells()
  local _, c = UnitClass("player")
  class = c
  wipe(meleeSpells); wipe(rangeSpells)
  for _, id in ipairs(MELEE_SPELLS[class] or {}) do
    if Knows(id) then meleeSpells[#meleeSpells + 1] = id end
  end
  for _, s in ipairs(RANGE_SPELLS[class] or {}) do
    if Knows(s[1]) then rangeSpells[#rangeSpells + 1] = s end
  end
  hasAutoShot = class == "HUNTER" and Knows(AUTO_SHOT)
end

local function SpellInRange(id)
  if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
  return Answer(pcall(C_Spell.IsSpellInRange, id, "target"))
end

function RR:RequestItems()
  if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, it in ipairs(RANGE_ITEMS) do pcall(C_Item.RequestLoadItemDataByID, it[1]) end
end

-- Can this kind of check run right now? Item and interact checks are skipped in combat once the game has refused one.
local function Allowed(kind)
  return not (RR.db.combatBlocked[kind] and InCombatLockdown())
end

local function Blocked(kind)
  if InCombatLockdown() and not RR.db.combatBlocked[kind] then
    RR.db.combatBlocked[kind] = true
    Print(("the game blocks %s checks in combat, so the ring is less precise in combat. Out of combat it's unaffected."):format(kind))
  end
end

-- Works out the distance bracket and zone for the current target.
-- Returns zone, low, high (yards; high may be math.huge).
function RR:Measure()
  local L, U = 0, math.huge
  local function within(r, res)
    if res == true then if r < U then U = r end
    elseif res == false then if r > L then L = r end end
  end

  local melee
  for _, id in ipairs(meleeSpells) do
    melee = SpellInRange(id)
    if melee ~= nil then break end
  end

  if Allowed("item") and C_Item and C_Item.IsItemInRange then
    for _, it in ipairs(RANGE_ITEMS) do
      local ok, v = pcall(C_Item.IsItemInRange, it[1], "target")
      if not ok then Blocked("item"); break end
      within(it[2], Answer(true, v))
    end
  end
  if Allowed("interact") and CheckInteractDistance then
    for _, ci in ipairs(INTERACT) do
      local ok, v = pcall(CheckInteractDistance, "target", ci[1])
      if not ok then Blocked("interact"); break end
      within(ci[2], Answer(true, v))
    end
  end
  for _, s in ipairs(rangeSpells) do within(s[2], SpellInRange(s[1])) end

  if melee == false and L < MELEE_YD then L = MELEE_YD end

  local auto = nil
  if hasAutoShot then auto = SpellInRange(AUTO_SHOT) end -- careful: "x and false or nil" would turn false into nil
  if auto == true then
    if L < DEAD_YD then L = DEAD_YD end
    if U > MAX_YD then U = MAX_YD end
  elseif auto == false then
    -- Inside 8 yd or past 35 yd. Use the other checks to decide which. If they can't (spells only, in
    -- combat): it's near if it was already near, or if it's attacking you (closing in on you);
    -- otherwise it's past 35 yd.
    local near
    if U <= MAX_YD then near = true
    elseif L >= DEAD_YD then near = false
    elseif self.zone == "dead" or self.zone == "melee" then near = true
    elseif self.zone == "out" then near = false
    else near = UnitIsUnit("targettarget", "player") and true or false end
    if near then if U > DEAD_YD then U = DEAD_YD end else if L < MAX_YD then L = MAX_YD end end
  end
  if L > U then U = L end -- checks disagreed (big hitboxes); trust the lower bound

  local zone
  if melee == true then zone = "melee"
  elseif auto == true then zone = "ranged"
  elseif auto == false then zone = (U <= DEAD_YD) and "dead" or "out"
  elseif U <= MELEE_YD and melee == nil then zone = "melee"
  elseif U <= MAX_YD then zone = "ranged"
  elseif L >= MAX_YD then zone = "out"
  else zone = "unknown" end
  if zone == "melee" then L, U = 0, math.min(U, MELEE_YD) end
  return zone, L, U
end

local function EstimateYards(zone, L, U)
  if zone == "melee" then return 2.5 end
  if U == math.huge then
    if L == 0 then return nil end
    return math.min(L + 5, 45)
  end
  return (L + U) / 2
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "RangeRingAnchor", UIParent)
anchor:SetSize(40, 40)
anchor:SetFrameStrata("BACKGROUND")
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:EnableMouse(false)
anchor:Hide()

local fill = anchor:CreateTexture(nil, "BACKGROUND")
fill:SetTexture(MEDIA .. "disc")
fill:SetPoint("CENTER")
local ring = anchor:CreateTexture(nil, "ARTWORK")
ring:SetTexture(MEDIA .. "ring1")
ring:SetPoint("CENTER")
-- Four ring textures with different line widths, picked by size so the line stays ~4-6 px wide.
local RING_TEX = {{45, "ring1"}, {90, "ring2"}, {150, "ring3"}, {math.huge, "ring4"}}
local ringTex = "ring1"
local guides = {}
for i, yd in ipairs({MELEE_YD, DEAD_YD, MAX_YD}) do
  local g = anchor:CreateTexture(nil, "BORDER")
  g:SetTexture(MEDIA .. "guide")
  g:SetPoint("CENTER")
  g.yards = yd
  guides[i] = g
end
local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOP", ring, "BOTTOM", 0, -2)

RR.anchor, RR.ring, RR.fill, RR.label, RR.guides = anchor, ring, fill, label, guides

local function Radius(yards) return 14 + yards * RR.db.pxPerYard end

local function SetRingSize(tex, r)
  -- The ring texture's circle fills ~98% of the image, so size the texture to the radius.
  tex:SetSize(r * 2, r * 2 * RR.db.flat)
end

function RR:ApplyLayout()
  local db = self.db
  anchor:ClearAllPoints()
  anchor:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
  for _, g in ipairs(guides) do
    SetRingSize(g, Radius(g.yards))
    g:SetVertexColor(1, 1, 1, 0.25 * db.alpha)
    g:SetShown(db.guides)
  end
  fill:SetShown(db.fill)
  label:SetShown(db.label)
end

function RR:Paint(zone)
  local c = self.db.colors[zone] or self.db.colors.unknown
  ring:SetVertexColor(c[1], c[2], c[3], self.db.alpha)
  fill:SetVertexColor(c[1], c[2], c[3], 0.15 * self.db.alpha)
end

local function IsHostileTarget()
  return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
end

local function RangeText(L, U)
  if U == math.huge then return (">%d yd"):format(L) end
  if L <= 0 then return ("<%g yd"):format(U) end
  return ("%g-%g yd"):format(math.floor(L + 0.5), math.floor(U + 0.5))
end

RR.zone, RR.low, RR.high = nil, nil, nil
local checkElapsed, curRadius, targetRadius = 0, nil, nil
RR.dirty = true

function RR:SetTargetYards(yards)
  targetRadius = Radius(yards)
  if not curRadius then curRadius = targetRadius end
end

function RR:Update(elapsed)
  local db = self.db
  if self.unlocked then
    self:Paint("ranged"); label:SetText("drag me, then /rr lock"); label:Show()
    self:SetTargetYards(10)
  elseif self.testUntil then
    local now = GetTime()
    if now > self.testUntil then
      self.testUntil = nil
      anchor:SetShown(db.enabled or self.unlocked)
      return self:Update(0)
    end
    local yd = ((now % 4) / 4) * 42
    local zone = (yd <= MELEE_YD and "melee") or (yd <= DEAD_YD and "dead") or (yd <= MAX_YD and "ranged") or "out"
    self:Paint(zone); label:SetText(("TEST  %d yd  %s"):format(math.floor(yd), ZONE_TEXT[zone]))
    self:SetTargetYards(yd)
  else
    if not IsHostileTarget() then
      ring:Hide(); fill:Hide(); label:Hide()
      for _, g in ipairs(guides) do g:Hide() end
      curRadius = nil
      return
    end
    checkElapsed = checkElapsed + (elapsed or 0)
    if checkElapsed >= CHECK_INTERVAL or self.dirty then
      checkElapsed, self.dirty = 0, false
      local zone, L, U = self:Measure()
      local est = EstimateYards(zone, L, U)
      self.zone, self.low, self.high = zone, L, U
      if est then self:SetTargetYards(est) elseif not targetRadius then self:SetTargetYards(MAX_YD) end
      self:Paint(zone)
      label:SetText(RangeText(L, U) .. "  " .. ZONE_TEXT[zone])
    end
  end

  if not targetRadius then targetRadius = Radius(MAX_YD) end
  if not curRadius then curRadius = targetRadius end
  -- Grow/shrink smoothly toward the measured size.
  curRadius = curRadius + (targetRadius - curRadius) * math.min(1, (elapsed or 0) * 10)
  SetRingSize(ring, curRadius)
  SetRingSize(fill, curRadius)
  for _, rt in ipairs(RING_TEX) do
    if curRadius < rt[1] then
      if ringTex ~= rt[2] then ringTex = rt[2]; ring:SetTexture(MEDIA .. ringTex) end
      break
    end
  end
  ring:Show(); fill:SetShown(db.fill); label:SetShown(db.label or self.unlocked)
  for _, g in ipairs(guides) do g:SetShown(db.guides) end
end

anchor:SetScript("OnUpdate", function(_, elapsed) RR:Update(elapsed) end)

-- Dragging (only while unlocked). The ring's own frame isn't restricted, so reading its position is fine.
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", function(self) if RR.unlocked then self:StartMoving() end end)
anchor:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local x, y = self:GetCenter()
  local ux, uy = UIParent:GetCenter()
  RR.db.x, RR.db.y = math.floor(x - ux + 0.5), math.floor(y - uy + 0.5)
  RR:ApplyLayout()
end)

function RR:SetUnlocked(on)
  self.unlocked = on
  anchor:EnableMouse(on)
  if on then anchor:Show() else anchor:SetShown(self.db.enabled) end
end

function RR:SetEnabled(on)
  self.db.enabled = on and true or false
  anchor:SetShown(self.db.enabled or self.unlocked)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    RangeRingDB = CopyDefaults(DEFAULTS, type(RangeRingDB) == "table" and RangeRingDB or {})
    RR.db = RangeRingDB
    RR:ApplyLayout()
  elseif event == "PLAYER_LOGIN" then
    RR:RefreshSpells()
    RR:RequestItems()
    RR:SetEnabled(RR.db.enabled)
    Print("v" .. VERSION .. " loaded. Target an enemy, or type /rr test to preview. /rr for options.")
  elseif event == "SPELLS_CHANGED" then
    RR:RefreshSpells()
  elseif event == "PLAYER_TARGET_CHANGED" then
    RR.dirty, RR.zone = true, nil
  elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and arg1 == ADDON then
    local fn = tostring(arg2 or "")
    if fn:find("IsItemInRange", 1, true) then Blocked("item")
    elseif fn:find("CheckInteractDistance", 1, true) then Blocked("interact") end
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ParseColor(rest)
  local r, g, b = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if not (r and g and b) then return nil end
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
  for _, v in ipairs({r, g, b}) do if v < 0 or v > 1 then return nil end end
  return {r, g, b}
end

local function Help()
  Print("commands:")
  Print("  /rr on | off | toggle - show or hide the ring")
  Print("  /rr test - 8 second preview: the ring grows from 0 to 42 yd through every zone")
  Print("  /rr unlock | lock - drag the ring onto your character's feet")
  Print("  /rr size <1-15> - pixels per yard (default 5)")
  Print("  /rr flat <0.2-1> - squash the ring so it lies flat (1 = circle, default 0.45)")
  Print("  /rr alpha <0.1-1> | fill | label | guides")
  Print("  /rr color melee|dead|ranged|out <r g b> - zone colors (0-1 or 0-255)")
  Print("  /rr status | reset")
end

local function Status()
  local db = RR.db
  Print(("v%s: %s, centre %d,%d, %d px/yd, flat %.2f, alpha %.2f"):format(
    VERSION, db.enabled and "on" or "off", db.x, db.y, db.pxPerYard, db.flat, db.alpha))
  local parts = {}
  if #meleeSpells > 0 then parts[#parts + 1] = "melee abilities" end
  if hasAutoShot then parts[#parts + 1] = "Auto Shot" end
  if #rangeSpells > 0 then parts[#parts + 1] = "ranged spells" end
  parts[#parts + 1] = db.combatBlocked.item and "items (not in combat)" or "items"
  parts[#parts + 1] = db.combatBlocked.interact and "interact distance (not in combat)" or "interact distance"
  Print("range checks: " .. table.concat(parts, ", ") .. ".")
  if RR.zone then Print(("target: %s, %s"):format(ZONE_TEXT[RR.zone], RangeText(RR.low, RR.high))) end
end

SLASH_RANGERING1 = "/rr"
SLASH_RANGERING2 = "/rangering"
SlashCmdList.RANGERING = function(msg)
  local db = RR.db
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local n = tonumber(rest)
  if cmd == "on" then RR:SetEnabled(true); Print("on.")
  elseif cmd == "off" then RR:SetEnabled(false); Print("off.")
  elseif cmd == "toggle" then RR:SetEnabled(not db.enabled); Print(db.enabled and "on." or "off.")
  elseif cmd == "test" then RR.testUntil = GetTime() + 8; anchor:Show(); Print("preview for 8 seconds.")
  elseif cmd == "unlock" then RR:SetUnlocked(true); Print("drag the ring onto your character's feet, then type /rr lock.")
  elseif cmd == "lock" then RR:SetUnlocked(false); Print(("locked at %d,%d."):format(db.x, db.y))
  elseif cmd == "size" then
    if n and n >= 1 and n <= 15 then db.pxPerYard = n; RR:ApplyLayout(); RR.dirty = true; Print("size " .. n .. " px per yard.")
    else Print("usage: /rr size <1-15>") end
  elseif cmd == "flat" then
    if n and n >= 0.2 and n <= 1 then db.flat = n; RR:ApplyLayout(); Print(("flat %.2f."):format(n))
    else Print("usage: /rr flat <0.2-1>") end
  elseif cmd == "alpha" then
    if n and n >= 0.1 and n <= 1 then db.alpha = n; RR:ApplyLayout(); RR.dirty = true; Print(("alpha %.2f."):format(n))
    else Print("usage: /rr alpha <0.1-1>") end
  elseif cmd == "fill" or cmd == "label" or cmd == "guides" then
    db[cmd] = not db[cmd]; RR:ApplyLayout(); Print(cmd .. " " .. (db[cmd] and "on." or "off."))
  elseif cmd == "color" then
    local zone, crest = rest:match("^(%S+)%s*(.-)$")
    zone = zone and zone:lower()
    local c = crest and ParseColor(crest)
    if zone and DEFAULTS.colors[zone] and zone ~= "unknown" and c then db.colors[zone] = c; RR.dirty = true; Print(zone .. " color set.")
    else Print("usage: /rr color melee|dead|ranged|out <r g b>, e.g. /rr color dead 1 0 0") end
  elseif cmd == "status" then Status()
  elseif cmd == "reset" then
    wipe(db); CopyDefaults(DEFAULTS, db); RR:ApplyLayout(); RR:SetEnabled(true); RR.dirty = true; Print("settings reset.")
  else Help() end
end
