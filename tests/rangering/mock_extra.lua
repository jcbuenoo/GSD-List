-- Extra client pieces Range Ring needs, on top of ../guardaggrowatch/strict_mock.lua.
local Widget = getmetatable(W.UIParent)
rawset(Widget, "SetFrameStrata", function(s, v) s._strata = v end)
rawset(Widget, "SetMovable", function(s, v) s._movable = v end)
rawset(Widget, "SetClampedToScreen", function() end)
rawset(Widget, "RegisterForDrag", function(s, b) s._drag = b end)
rawset(Widget, "GetCenter", function(s) return rawget(s, "_cx"), rawget(s, "_cy") end)
W.UIParent._cx, W.UIParent._cy = 960, 540

-- One target at DIST yards. Every check answers from DIST like the real game would.
CLASS, KNOWN, COMBAT_BLOCK = "HUNTER", {}, {}
local function T() return UNITS.target end
W.UnitClass = function(u) return "Hunter", CLASS end
W.IsSpellKnown = function(id) return KNOWN[id] == true end
W.IsPlayerSpell = function() return false end
W.UnitIsDeadOrGhost = function(u) local x = UNITS[u]; return x and x.dead or false end
local RANGES = {[2973]={0,5}, [2974]={0,5}, [1752]={0,5}, [75]={8,35}, [116]={0,30}, [133]={0,35}, [2136]={0,20}}
SPELLCALLS = 0
W.C_Spell = {IsSpellInRange = function(id, unit)
  SPELLCALLS = SPELLCALLS + 1
  local t, r = T(), RANGES[id]
  if not t or not r or not KNOWN[id] then return nil end
  if SPELL_OVERRIDE then return SPELL_OVERRIDE end
  return t.dist >= r[1] and t.dist <= r[2]
end}
ITEMS_LOADED = {}
W.C_Item = {
  RequestLoadItemDataByID = function(id) ITEMS_LOADED[id] = true end,
  IsItemInRange = function(id, unit)
    if COMBAT_BLOCK.item and P.combat then error("IsItemInRange(): blocked in combat") end
    local yd = ({[34368]=8, [32321]=10, [33069]=15, [10645]=20, [24268]=25, [835]=30, [24269]=35, [28767]=40})[id]
    local t = T(); if not t or not ITEMS_LOADED[id] then return nil end
    return t.dist <= yd
  end,
}
W.CheckInteractDistance = function(u, i)
  if COMBAT_BLOCK.interact and P.combat then error("CheckInteractDistance(): blocked in combat") end
  local t = T(); if not t then return false end
  return t.dist <= ({[1]=28, [2]=11.1, [3]=9.9, [4]=28})[i]
end
SECRETS = {}
W.issecretvalue = function(v) return SECRETS[v] == true end
