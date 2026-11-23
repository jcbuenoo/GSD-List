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
  dot = true,                -- range-colored dot at your character when the line can't be drawn
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

local VERSION = "1.0.2"
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
--
-- This client restricts nameplates: addons can't read their position ("Can't measure restricted regions"),
-- and a region outside a nameplate can't be anchored to it ("Not allowed to depend on nameplate").
-- So the line lives on a holder frame that we parent *inside* the target's nameplate (the way nameplate
-- addons like Plater attach their frames). Its far end anchors to that nameplate; its near end anchors
-- to a fixed screen point for your character. Nothing is ever measured.
---------------------------------------------------------------------------
-- canvas: on-screen root; owns the OnUpdate and the fallback dot.
local canvas = CreateFrame("Frame", "MeleeRangeLineCanvas", UIParent)
canvas:SetAllPoints(UIParent)
canvas:SetFrameStrata("BACKGROUND")
canvas:EnableMouse(false)
canvas:Hide()

-- holder: moved into the target's nameplate. Ignores the nameplate's scale and fade so the line looks the same on every target.
local holder = CreateFrame("Frame", nil, canvas)
holder:SetIgnoreParentScale(true)
holder:SetIgnoreParentAlpha(true)
holder:EnableMouse(false)
holder:Hide()

local shadow = holder:CreateLine(nil, "BACKGROUND")
local line = holder:CreateLine(nil, "ARTWORK")
shadow:SetColorTexture(0, 0, 0, 1)

-- Fallback dot at your character's screen point. Shows the range color when the line can't be drawn
-- (target's nameplate off screen / out of nameplate range, or the game refuses the line).
local dot = canvas:CreateTexture(nil, "ARTWORK")
dot:SetSize(14, 14)
dot:SetColorTexture(1, 1, 1, 1)
local dotMask = canvas:CreateMaskTexture()
dotMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
dotMask:SetAllPoints(dot)
dot:AddMaskTexture(dotMask)
dot:Hide()

MRL.canvas, MRL.holder, MRL.line, MRL.shadow, MRL.dot = canvas, holder, line, shadow, dot


local function GetTargetPlate()
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
  if not ok or not plate then return nil end
  local okVis, visible = pcall(plate.IsVisible, plate)
  if okVis and Usable(visible) and not visible then return nil end
  return plate
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
  self:ResetAnchors()
end

function MRL:SetColor(state)
  local c = (state == true and self.db.inColor) or (state == false and self.db.outColor) or self.db.unknownColor
  line:SetColorTexture(c[1], c[2], c[3], self.db.alpha)
  dot:SetVertexColor(c[1], c[2], c[3], self.db.alpha)
end

local rangeElapsed = 0
MRL.state, MRL.method, MRL.dirty = nil, nil, true

-- Attach the holder to a nameplate and anchor the line. Only redone when the plate or the settings change.
local attachedPlate, attachedKey
local blockedPlates = setmetatable({}, {__mode = "k"}) -- plates the game refused, skipped until the target changes

function MRL:ResetAnchors() attachedPlate, attachedKey = nil, nil end

function MRL:Detach()
  holder:Hide()
  holder:ClearAllPoints()
  holder:SetParent(canvas)
  attachedPlate, attachedKey = nil, nil
end

function MRL:Attach(plate)
  local db = self.db
  local key = db.offsetX .. ":" .. db.offsetY .. ":" .. db.targetOffsetY .. ":" .. tostring(db.outline)
  if attachedPlate == plate and attachedKey == key then return true end
  if blockedPlates[plate] then return false end
  local ok, err = pcall(function()
    holder:SetParent(plate)
    holder:SetIgnoreParentScale(true)
    holder:SetIgnoreParentAlpha(true)
    holder:SetScale(UIParent:GetScale())
    holder:ClearAllPoints()
    holder:SetAllPoints(plate)
    line:ClearAllPoints(); shadow:ClearAllPoints()
    line:SetStartPoint("CENTER", UIParent, db.offsetX, db.offsetY)
    line:SetEndPoint("BOTTOM", holder, 0, db.targetOffsetY)
    shadow:SetStartPoint("CENTER", UIParent, db.offsetX, db.offsetY)
    shadow:SetEndPoint("BOTTOM", holder, 0, db.targetOffsetY)
  end)
  if not ok then
    blockedPlates[plate] = true
    self:Detach()
    self:Report(err)
    return false
  end
  attachedPlate, attachedKey = plate, key
  holder:Show()
  return true
end

local reported = {}
function MRL:Report(err)
  err = tostring(err)
  if reported[err] then return end
  reported[err] = true
  self.lastError = err
  Print("the game refused the line, showing the range dot instead. Please report this: " .. err)
end

function MRL:ShowDot(show)
  if show and self.db.dot then
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", canvas, "CENTER", self.db.offsetX, self.db.offsetY)
    dot:Show()
  else
    dot:Hide()
  end
end

function MRL:Update(elapsed)
  if not IsHostileTarget() then
    if attachedPlate then self:Detach() end
    self:ShowDot(false)
    return
  end

  rangeElapsed = rangeElapsed + (elapsed or 0)
  if rangeElapsed >= RANGE_INTERVAL or self.dirty then
    rangeElapsed, self.dirty = 0, false
    local state, method = self:InMeleeRange("target")
    self.state, self.method = state, method
    self:SetColor(state)
  end

  local plate = GetTargetPlate()
  if plate and self:Attach(plate) then
    line:Show()
    shadow:SetShown(self.db.outline)
    self:ShowDot(false)
  else
    if attachedPlate then self:Detach() end
    self:ShowDot(true)
  end
end

-- Anything else the game blocks: report once, pause 5 s, never throw every frame.
local pausedUntil = 0
canvas:SetScript("OnUpdate", function(_, elapsed)
  local now = GetTime()
  if now < pausedUntil then return end
  local ok, err = pcall(MRL.Update, MRL, elapsed)
  if not ok then
    pcall(MRL.Detach, MRL)
    dot:Hide()
    pausedUntil = now + 5
    MRL:Report(err)
  end
end)

function MRL:SetEnabled(on)
  self.db.enabled = on and true or false
  canvas:SetShown(self.db.enabled)
  if not self.db.enabled then self:Detach() end
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
    MeleeRangeLineDB.anchor = nil -- 1.0.0/1.0.1 setting; your own nameplate can't be used as an anchor
    MRL.db = MeleeRangeLineDB
    MRL:ApplyStyle()
  elseif event == "PLAYER_LOGIN" then
    Print("v" .. VERSION .. " loaded. /mrl for options.")
    MRL:RefreshSpells()
    MRL:SetEnabled(MRL.db.enabled)
    if GetCVar("nameplateShowEnemies") == "0" then
      Print("enemy nameplates are off, so the line can't find your target. Type |cffffff00/mrl plates|r to turn them on.")
    end
  elseif event == "SPELLS_CHANGED" then
    MRL:RefreshSpells()
  elseif event == "PLAYER_TARGET_CHANGED" then
    wipe(blockedPlates)
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
  Print("  /mrl dot - toggle the range dot shown when the line can't be drawn")
  Print("  /mrl offset <x> <y> - move the screen point for your character (from screen centre)")
  Print("  /mrl targetoffset <y> - move the target end up or down")
  Print("  /mrl plates - turn enemy nameplates on (the line needs them)")
  Print("  /mrl status | reset")
end

local function Status()
  local db = MRL.db
  Print(("v%s: %s, thickness %d, alpha %.2f, dot %s, offset %d,%d, target offset %d"):format(
    VERSION, db.enabled and "on" or "off", db.thickness, db.alpha, db.dot and "on" or "off", db.offsetX, db.offsetY, db.targetOffsetY))
  if MRL.lastError then Print("last blocked: " .. MRL.lastError) end
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
  elseif cmd == "dot" then
    db.dot = not db.dot; Print("dot " .. (db.dot and "on." or "off."))
  elseif cmd == "offset" then
    local x, y = rest:match("^(%S+)%s+(%S+)$")
    x, y = tonumber(x), tonumber(y)
    if x and y then db.offsetX, db.offsetY = math.floor(x + 0.5), math.floor(y + 0.5); MRL:ResetAnchors(); Print(("offset %d,%d."):format(db.offsetX, db.offsetY))
    else Print("usage: /mrl offset <x> <y>, e.g. /mrl offset 0 -60") end
  elseif cmd == "targetoffset" then
    local y = tonumber(rest)
    if y then db.targetOffsetY = math.floor(y + 0.5); MRL:ResetAnchors(); Print("target offset " .. db.targetOffsetY .. ".")
    else Print("usage: /mrl targetoffset <y>") end
  elseif cmd == "plates" then
    if InCombatLockdown() then Print("can't change nameplates in combat.")
    else SetCVar("nameplateShowEnemies", "1"); Print("enemy nameplates on.") end
  elseif cmd == "status" then Status()
  elseif cmd == "reset" then
    wipe(db); CopyDefaults(DEFAULTS, db); MRL:ApplyStyle(); MRL:SetEnabled(true); MRL.dirty = true; Print("settings reset.")
  else Help() end
end
