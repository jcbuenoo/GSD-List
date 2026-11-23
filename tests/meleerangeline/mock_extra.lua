-- Extra client pieces Melee Range Line needs, on top of ../guardaggrowatch/strict_mock.lua.
local Widget = getmetatable(W.UIParent)
local all = {}
rawset(Widget, "SetFrameStrata", function(s, v) s._strata = v end)
-- Real nameplates are restricted: measuring them throws, exactly like the live client.
local function measure(s, what)
  if rawget(s, "_restricted") then error(what .. "(): Action[FrameMeasurement] failed because[Can't measure restricted regions]", 2) end
end
rawset(Widget, "GetEffectiveScale", function(s) measure(s, "GetEffectiveScale"); return rawget(s, "_escale") or 1 end)
rawset(Widget, "IsVisible", function(s) local f = s; while f do if not rawget(f, "_shown") then return false end f = rawget(f, "_parent") end return true end)
rawset(Widget, "GetCenter", function(s) measure(s, "GetCenter"); return rawget(s, "_cx"), rawget(s, "_cy") end)
for _, m in ipairs({"GetLeft","GetRight","GetTop","GetRect","GetSize","GetWidth","GetHeight","GetScaledRect"}) do
  local base = rawget(Widget, m)
  rawset(Widget, m, function(s, ...) measure(s, m); if base then return base(s, ...) end end)
end
rawset(Widget, "GetBottom", function(s) measure(s, "GetBottom"); return rawget(s, "_bottom") end)
rawset(Widget, "SetThickness", function(s, v) s._thick = v end)
-- Nameplate dependency rule from the live client: a region may only anchor to a nameplate (or to
-- anything inside one) if the region itself is inside that same nameplate.
local function plateOf(r) local f = r; while f do if rawget(f, "_restricted") then return f end f = rawget(f, "_parent") end end
function checkDepend(s, rel, what)
  local p = rel and plateOf(rel)
  if p and plateOf(s) ~= p then error(what .. "(): Not allowed to depend on nameplate " .. tostring(rawget(p, "_npid")), 3) end
end
rawset(Widget, "SetStartPoint", function(s, rp, rel, x, y) assert(type(rp) == "string" and type(rel) == "table" and type(x) == "number" and type(y) == "number"); checkDepend(s, rel, "Line:SetStartPoint"); s._start = {rp, rel, x, y}; s._anchorCalls = (rawget(s, "_anchorCalls") or 0) + 1 end)
rawset(Widget, "SetEndPoint", function(s, rp, rel, x, y) assert(type(rp) == "string" and type(rel) == "table" and type(x) == "number" and type(y) == "number"); checkDepend(s, rel, "Line:SetEndPoint"); s._end = {rp, rel, x, y} end)
local basePoint, baseAll = rawget(Widget, "SetPoint"), rawget(Widget, "SetAllPoints")
rawset(Widget, "SetPoint", function(s, point, rel, ...) if type(rel) == "table" then checkDepend(s, rel, "SetPoint") end return basePoint(s, point, rel, ...) end)
rawset(Widget, "SetAllPoints", function(s, rel) checkDepend(s, rel or rawget(s, "_parent"), "SetAllPoints"); return baseAll(s, rel) end)
rawset(Widget, "SetParent", function(s, p) s._parent = p end)
rawset(Widget, "GetParent", function(s) return rawget(s, "_parent") end)
rawset(Widget, "GetScale", function(s) return rawget(s, "_scale") or 1 end)
rawset(Widget, "CreateMaskTexture", function(s) return W.CreateFrame("MaskTexture", nil, s) end)
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
local npid = 0
function makePlate()
  npid = npid + 1
  local f = W.CreateFrame("Frame", nil, nil); f._restricted = true; f._npid = npid; return f
end
SECRETS = {}
W.issecretvalue = function(v) return SECRETS[v] == true end
