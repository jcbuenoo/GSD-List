-- Extra client pieces Melee Range Line needs, on top of ../guardaggrowatch/strict_mock.lua.
local Widget = getmetatable(W.UIParent)
local all = {}
rawset(Widget, "SetFrameStrata", function(s, v) s._strata = v end)
rawset(Widget, "GetEffectiveScale", function(s) return rawget(s, "_escale") or 1 end)
rawset(Widget, "IsVisible", function(s) local f = s; while f do if not rawget(f, "_shown") then return false end f = rawget(f, "_parent") end return true end)
rawset(Widget, "GetCenter", function(s) return rawget(s, "_cx"), rawget(s, "_cy") end)
rawset(Widget, "GetBottom", function(s) return rawget(s, "_bottom") end)
rawset(Widget, "SetThickness", function(s, v) s._thick = v end)
rawset(Widget, "SetStartPoint", function(s, rp, rel, x, y) assert(type(rp) == "string" and type(rel) == "table" and type(x) == "number" and type(y) == "number"); s._start = {x, y} end)
rawset(Widget, "SetEndPoint", function(s, rp, rel, x, y) assert(type(rp) == "string" and type(rel) == "table" and type(x) == "number" and type(y) == "number"); s._end = {x, y} end)
rawset(Widget, "CreateLine", function(s, name, layer) local l = W.CreateFrame("Line", nil, s); l._layer = layer; return l end)

-- Melee/class state
CLASS, KNOWN, SPELLRANGE = "ROGUE", {}, {}   -- SPELLRANGE[id] = true/false/nil
W.UnitClass = function(u) return "Rogue", CLASS end
W.IsSpellKnown = function(id) return KNOWN[id] == true end
W.IsPlayerSpell = function(id) return false end
W.C_Spell = {IsSpellInRange = function(id, unit) SPELLCALLS = (SPELLCALLS or 0) + 1; return SPELLRANGE[id] end}
W.UnitIsDeadOrGhost = function(u) local x = UNITS[u]; return x and x.dead or false end
W.SetCVar = function(k, v) W.__cvars[k] = v end
W.__cvars.nameplateShowEnemies = "1"
-- Nameplates: NP[unit] = frame
NP = {}
W.C_NamePlate.GetNamePlateForUnit = function(u) return NP[u] end
function makePlate(cx, cy, bottom, scale)
  local f = W.CreateFrame("Frame", nil, nil); f._cx, f._cy, f._bottom, f._escale = cx, cy, bottom, scale or 1; return f
end
