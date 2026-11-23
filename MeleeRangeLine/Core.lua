-- Melee Range Line: draws a line from your character to your hostile target.
-- The line is green when you're in melee range and red when you're not.
local ADDON = ...

local MRL = {}
MeleeRangeLine = MRL

local DEFAULTS = {
  enabled = true,
  thickness = 3,
  alpha = 0.9,
  outline = true,            -- dark border under the line so it shows on bright ground
  anchor = "auto",           -- "auto": your own nameplate if shown, else the screen point; "screen": always the screen point
  offsetX = 0,               -- screen point for your character, from the screen centre (UI units)
  offsetY = -60,
  targetOffsetY = 0,         -- move the target end up/down from the bottom of its nameplate
  inColor = {0.1, 1.0, 0.1},
  outColor = {1.0, 0.15, 0.15},
  unknownColor = {1.0, 0.85, 0.1},
}

-- Melee-range abilities (rank 1 spell IDs; in TBC every learned rank stays known, so rank 1 is enough).
-- The first one the character knows that gives a valid answer decides "in melee range".
local MELEE_SPELLS = {
  WARRIOR = {1715, 78, 772, 7386},       -- Hamstring, Heroic Strike, Rend, Sunder Armor
  ROGUE   = {1752, 2098, 53},            -- Sinister Strike, Eviscerate, Backstab
  HUNTER  = {2973, 2974, 1495},          -- Raptor Strike, Wing Clip, Mongoose Bite
  DRUID   = {1082, 6807, 5221, 1822},    -- Claw, Maul, Shred, Rake
  PALADIN = {35395},                     -- Crusader Strike (talent)
  SHAMAN  = {17364},                     -- Stormstrike (talent)
}

local RANGE_INTERVAL = 0.05 -- seconds between range checks; the line itself moves every frame

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MeleeRangeLine|r: " .. msg)
end

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

---------------------------------------------------------------------------
-- Range check
---------------------------------------------------------------------------
local knownSpells = {}

local function Knows(id)
  if IsSpellKnown and IsSpellKnown(id) then return true end
  if IsPlayerSpell and IsPlayerSpell(id) then return true end
  return false
end

function MRL:RefreshSpells()
  wipe(knownSpells)
  local _, class = UnitClass("player")
  for _, id in ipairs(MELEE_SPELLS[class] or {}) do
    if Knows(id) then knownSpells[#knownSpells + 1] = id end
  end
end

-- Restricted values ("secrets") can't be compared by addons in this client; treat them as "can't tell".
local function Usable(v)
  if v == nil then return false end
  if issecretvalue and issecretvalue(v) then return false end
  return true
end

local function SpellInRange(id, unit)
  if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
  local ok, r = pcall(C_Spell.IsSpellInRange, id, unit)
  if ok and Usable(r) then return r end
  return nil
end

-- Returns true (in melee range), false (out of range) or nil (can't tell).
-- The second return value names the method: "spell" (exact) or "approx" (~10 yd duel distance).
function MRL:InMeleeRange(unit)
  for _, id in ipairs(knownSpells) do
    local r = SpellInRange(id, unit)
    if r ~= nil then return (r == true or r == 1), "spell" end
  end
  -- No melee ability (casters, low-level paladins/shamans): fall back to duel distance (~9.9 yd).
  local ok, r = pcall(CheckInteractDistance, unit, 3)
  if ok and Usable(r) then return (r == true or r == 1), "approx" end
  return nil, nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local canvas = CreateFrame("Frame", "MeleeRangeLineCanvas", UIParent)
canvas:SetAllPoints(UIParent)
canvas:SetFrameStrata("BACKGROUND")
canvas:EnableMouse(false)

local shadow = canvas:CreateLine(nil, "BACKGROUND")
local line = canvas:CreateLine(nil, "ARTWORK")
shadow:SetColorTexture(0, 0, 0, 1)
canvas:Hide()

MRL.canvas, MRL.line, MRL.shadow = canvas, line, shadow

-- This client won't let addons read a nameplate's position ("Can't measure restricted regions"),
-- so the line is never measured: its ends are anchored straight to the nameplates and the game keeps them in place.
local function GetPlate(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if not ok or not plate then return nil end
  local okVis, visible = pcall(plate.IsVisible, plate)
  if okVis and Usable(visible) and not visible then return nil end
  return plate
end

-- Returns the anchor for your end of the line: (point, region, x, y).
function MRL:GetPlayerAnchor()
  local db = self.db
  if db.anchor == "auto" then
    local plate = GetPlate("player") -- your personal resource display, if it's on
    if plate then return "CENTER", plate, 0, 0 end
  end
  return "CENTER", canvas, db.offsetX, db.offsetY
end

-- Returns the anchor for the target's end, or nil when its nameplate isn't shown.
function MRL:GetTargetAnchor()
  local plate = GetPlate("target")
  if not plate then return nil end
  return "BOTTOM", plate, 0, self.db.targetOffsetY -- bottom of the nameplate sits just above the target's head
end

local function IsHostileTarget()
  return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
end

function MRL:ApplyStyle()
  local db = self.db
  line:SetThickness(db.thickness)
  shadow:SetThickness(db.thickness + 2)
  shadow:SetAlpha(db.alpha * 0.6)
  shadow:SetShown(db.outline)
end

function MRL:SetColor(state)
  local c = (state == true and self.db.inColor) or (state == false and self.db.outColor) or self.db.unknownColor
  line:SetColorTexture(c[1], c[2], c[3], self.db.alpha)
end

local rangeElapsed = 0
MRL.state, MRL.method, MRL.dirty = nil, nil, true

-- Re-anchor only when something changed; anchored lines follow their nameplates on their own.
local lastKey = {}
local function Anchor(tp, tr, tx, ty, sp, sr, sx, sy)
  if lastKey[1] == tr and lastKey[2] == tx and lastKey[3] == ty and lastKey[4] == sr
     and lastKey[5] == sx and lastKey[6] == sy and lastKey[7] == sp then return end
  lastKey[1], lastKey[2], lastKey[3], lastKey[4], lastKey[5], lastKey[6], lastKey[7] = tr, tx, ty, sr, sx, sy, sp
  line:ClearAllPoints(); shadow:ClearAllPoints()
  line:SetStartPoint(sp, sr, sx, sy); line:SetEndPoint(tp, tr, tx, ty)
  shadow:SetStartPoint(sp, sr, sx, sy); shadow:SetEndPoint(tp, tr, tx, ty)
end
function MRL:ResetAnchors() wipe(lastKey) end

function MRL:Update(elapsed)
  if not IsHostileTarget() then
    line:Hide(); shadow:Hide()
    return
  end
  local tp, tr, tx, ty = self:GetTargetAnchor()
  if not tp then
    -- The target's nameplate isn't shown (too far, or enemy nameplates are off).
    line:Hide(); shadow:Hide()
    return
  end
  local sp, sr, sx, sy = self:GetPlayerAnchor()

  rangeElapsed = rangeElapsed + (elapsed or 0)
  if rangeElapsed >= RANGE_INTERVAL or self.dirty then
    rangeElapsed, self.dirty = 0, false
    local state, method = self:InMeleeRange("target")
    self.state, self.method = state, method
    self:SetColor(state)
  end

  Anchor(tp, tr, tx, ty, sp, sr, sx, sy)
  line:Show()
  shadow:SetShown(self.db.outline)
end

-- If the game blocks something, report it once in chat and pause for a few seconds instead of
-- throwing an error every frame.
local pausedUntil, reported = 0, {}
canvas:SetScript("OnUpdate", function(_, elapsed)
  local now = GetTime()
  if now < pausedUntil then return end
  local ok, err = pcall(MRL.Update, MRL, elapsed)
  if not ok then
    line:Hide(); shadow:Hide(); MRL:ResetAnchors()
    pausedUntil = now + 5
    err = tostring(err)
    if not reported[err] then
      reported[err] = true
      Print("the game blocked the line (retrying every 5 s). Please report this: " .. err)
    end
  end
end)

function MRL:SetEnabled(on)
  self.db.enabled = on and true or false
  canvas:SetShown(self.db.enabled)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    MeleeRangeLineDB = CopyDefaults(DEFAULTS, type(MeleeRangeLineDB) == "table" and MeleeRangeLineDB or {})
    if MeleeRangeLineDB.anchor ~= "auto" and MeleeRangeLineDB.anchor ~= "screen" then MeleeRangeLineDB.anchor = "auto" end
    MRL.db = MeleeRangeLineDB
    MRL:ApplyStyle()
  elseif event == "PLAYER_LOGIN" then
    MRL:RefreshSpells()
    MRL:SetEnabled(MRL.db.enabled)
    if GetCVar("nameplateShowEnemies") == "0" then
      Print("enemy nameplates are off, so the line can't find your target. Type |cffffff00/mrl plates|r to turn them on.")
    end
  elseif event == "SPELLS_CHANGED" then
    MRL:RefreshSpells()
  elseif event == "PLAYER_TARGET_CHANGED" then
    MRL.dirty = true -- recolor on the next frame instead of waiting for the throttle
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ParseColor(rest)
  local r, g, b = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if not (r and g and b) then return nil end
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end -- accept 0-255 too
  for _, v in ipairs({r, g, b}) do if v < 0 or v > 1 then return nil end end
  return {r, g, b}
end

local function Help()
  Print("commands:")
  Print("  /mrl on | off | toggle - show or hide the line")
  Print("  /mrl thickness <1-20> - line width")
  Print("  /mrl alpha <0.1-1> - line opacity")
  Print("  /mrl outline - toggle the dark border")
  Print("  /mrl incolor <r g b> | outcolor <r g b> - colors (0-1 or 0-255)")
  Print("  /mrl anchor auto | screen - start the line at your own nameplate (auto) or a fixed screen point")
  Print("  /mrl offset <x> <y> - move the screen point for your character (from screen centre)")
  Print("  /mrl targetoffset <y> - move the target end up or down")
  Print("  /mrl plates - turn enemy nameplates on (the line needs them)")
  Print("  /mrl status | reset")
end

local function Status()
  local db = MRL.db
  Print(("%s, thickness %d, alpha %.2f, anchor %s, offset %d,%d, target offset %d"):format(
    db.enabled and "on" or "off", db.thickness, db.alpha, db.anchor, db.offsetX, db.offsetY, db.targetOffsetY))
  if #knownSpells > 0 then
    Print("range check: exact, using your melee abilities.")
  else
    Print("range check: approximate (~10 yd). Your character has no melee ability to check against.")
  end
end

SLASH_MELEERANGELINE1 = "/mrl"
SLASH_MELEERANGELINE2 = "/meleeline"
SlashCmdList.MELEERANGELINE = function(msg)
  local db = MRL.db
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "on" then MRL:SetEnabled(true); Print("on.")
  elseif cmd == "off" then MRL:SetEnabled(false); Print("off.")
  elseif cmd == "toggle" then MRL:SetEnabled(not db.enabled); Print(db.enabled and "on." or "off.")
  elseif cmd == "thickness" then
    local n = tonumber(rest)
    if n and n >= 1 and n <= 20 then db.thickness = math.floor(n + 0.5); MRL:ApplyStyle(); Print("thickness " .. db.thickness .. ".")
    else Print("usage: /mrl thickness <1-20>") end
  elseif cmd == "alpha" then
    local n = tonumber(rest)
    if n and n >= 0.1 and n <= 1 then db.alpha = n; MRL:ApplyStyle(); MRL.dirty = true; Print(("alpha %.2f."):format(n))
    else Print("usage: /mrl alpha <0.1-1>") end
  elseif cmd == "outline" then
    db.outline = not db.outline; MRL:ApplyStyle(); Print("outline " .. (db.outline and "on." or "off."))
  elseif cmd == "incolor" or cmd == "outcolor" then
    local c = ParseColor(rest)
    if c then db[cmd == "incolor" and "inColor" or "outColor"] = c; MRL.dirty = true; Print(cmd .. " set.")
    else Print("usage: /mrl " .. cmd .. " <r g b>, e.g. /mrl " .. cmd .. " 0 1 0") end
  elseif cmd == "anchor" then
    rest = rest:lower()
    if rest == "auto" or rest == "screen" then db.anchor = rest; MRL:ResetAnchors(); Print("anchor " .. rest .. ".")
    else Print("usage: /mrl anchor auto | screen") end
  elseif cmd == "offset" then
    local x, y = rest:match("^(%S+)%s+(%S+)$")
    x, y = tonumber(x), tonumber(y)
    if x and y then db.offsetX, db.offsetY = math.floor(x + 0.5), math.floor(y + 0.5); Print(("offset %d,%d."):format(db.offsetX, db.offsetY))
    else Print("usage: /mrl offset <x> <y>, e.g. /mrl offset 0 -60") end
  elseif cmd == "targetoffset" then
    local y = tonumber(rest)
    if y then db.targetOffsetY = math.floor(y + 0.5); Print("target offset " .. db.targetOffsetY .. ".")
    else Print("usage: /mrl targetoffset <y>") end
  elseif cmd == "plates" then
    if InCombatLockdown() then Print("can't change nameplates in combat.")
    else SetCVar("nameplateShowEnemies", "1"); Print("enemy nameplates on.") end
  elseif cmd == "status" then Status()
  elseif cmd == "reset" then
    wipe(db); CopyDefaults(DEFAULTS, db); MRL:ApplyStyle(); MRL:SetEnabled(true); MRL.dirty = true; Print("settings reset.")
  else Help() end
end
