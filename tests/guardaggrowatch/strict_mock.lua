-- Strict mock of the WoW client: unknown widget methods or undefined globals raise errors.
W = {}            -- the fake game globals the addon sees
ACCESSED, CREATED = {}, {}
local REAL_METHODS = REAL_METHODS  -- injected set
local all_frames = {}

local Widget = {}
local function widget(kind, parent, name)
  local o = {_kind=kind, _parent=parent, _shown=true, _w=0, _h=0, _points={}, _scripts={},
             _events={}, _children={}, _level=(parent and parent._level or 0) + 1, _scale=1, _name=name}
  if parent then table.insert(parent._children, o) end
  table.insert(all_frames, o)
  return setmetatable(o, Widget)
end
Widget.__index = function(t, k)
  local impl = rawget(Widget, k)
  if not REAL_METHODS[k] then
    error("CALL TO NON-EXISTENT WIDGET METHOD: " .. tostring(k), 2)
  end
  return impl or function() end
end
Widget.SetSize = function(s, w, h) s._w, s._h = w, h end
Widget.SetWidth = function(s, w) s._w = w end
Widget.GetWidth = function(s) return s._w end
Widget.GetHeight = function(s) return s._h end
Widget.SetAllPoints = function(s, p) p = p or s._parent; if p then s._w, s._h = p._w, p._h end; s._allpoints = p end
Widget.SetPoint = function(s, point, rel, relPoint, x, y)
  if type(rel) == "number" then point, rel, relPoint, x, y = point, s._parent, point, rel, relPoint end
  table.insert(s._points, {point, rel, relPoint, x or 0, y or 0})
end
Widget.ClearAllPoints = function(s) s._points = {} end
Widget.GetPoint = function(s) local p = s._points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
Widget.Show = function(s) s._shown = true; if s._scripts.OnShow then s._scripts.OnShow(s) end end
Widget.Hide = function(s) s._shown = false end
Widget.IsShown = function(s) return s._shown end
Widget.SetShown = function(s, v) s._shown = not not v end
Widget.SetScript = function(s, k, f) s._scripts[k] = f end
Widget.HookScript = function(s, k, f) local old = s._scripts[k]; s._scripts[k] = function(...) if old then old(...) end f(...) end end
Widget.SetTexture = function(s, t) s._tex = t end
Widget.SetVertexColor = function(s, r, g, b, a) s._color = {r, g, b, a or 1} end
Widget.SetColorTexture = function(s, r, g, b, a) s._color = {r, g, b, a}; s._tex = "color" end
Widget.SetText = function(s, t) s._text = t end
Widget.GetText = function(s) return s._text end
Widget.SetRotation = function(s, r) s._rot = r end
Widget.GetFrameLevel = function(s) return s._level end
Widget.SetFrameLevel = function(s, l) s._level = l end
Widget.SetScale = function(s, v) s._scale = v end
Widget.SetAlpha = function(s, a) s._alpha = a end
Widget.RegisterEvent = function(s, e) s._events[e] = true end
Widget.RegisterUnitEvent = function(s, e, u) s._events[e] = u end
Widget.UnregisterEvent = function(s, e) s._events[e] = nil end
Widget.EnableMouse = function(s, v) s._mouse = v end
Widget.CreateTexture = function(s, name, layer, inherits, sub) local t = widget("Texture", s); t._layer = layer; return t end
Widget.CreateFontString = function(s) return widget("FontString", s) end
Widget.GetZoom = function(s) return W.__zoom end
Widget.SetZoom = function(s, z) W.__zoom = z; W.__cvars[W.__indoors and "minimapInsideZoom" or "minimapZoom"] = tostring(z) end
Widget.StartMoving = function(s) end
Widget.StopMovingOrSizing = function(s) end

function fire(event, ...)
  for _, f in ipairs(all_frames) do
    if f._events[event] and f._scripts.OnEvent then
      local u = f._events[event]
      if u == true or u == (...) then f._scripts.OnEvent(f, event, ...) end
    end
  end
end

-- Game state
P = {a=1000, b=500, inst=0, facing=0, level=70, combat=false}
W.__zoom, W.__indoors = 0, false
W.__cvars = {minimapZoom="0", minimapInsideZoom="0", rotateMinimap="0"}
PLATES, UNITS = {}, {}   -- UNITS[token] = {name=, level=, hostile=, player=, target=, guid=}
CLOCK = 1000
SOUNDS, CHAT = {}, {}

W.CreateFrame = function(kind, name, parent) local f = widget(kind, parent, name); if name then W[name] = f end; return f end
W.UIParent = widget("Frame"); W.UIParent._w, W.UIParent._h = 1920, 1080
W.Minimap = widget("Minimap"); W.Minimap._w, W.Minimap._h = 140, 140
W.GameTooltip = widget("GameTooltip")
W.DEFAULT_CHAT_FRAME = {AddMessage = function(_, m) table.insert(CHAT, m) end}
W.UnitPosition = function(u) if P.noPos then return nil end return P.a, P.b, 0, P.inst end
W.GetPlayerFacing = function() return P.facing end
W.IsIndoors = function() return W.__indoors end
W.GetTime = function() return CLOCK end
W.time = os.time
W.date = os.date
W.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
W.hooksecurefunc = function(tbl, name, f)
  if type(tbl) == "string" then error("global hooks unused") end
  local old = tbl[name]; assert(type(old) == "function", "hooking missing method " .. name)
  rawset(tbl, name, function(...) local r = old(...); f(...); return r end)
end
local function U(u) if u == "player" then return {name="Rogue", level=P.level, player=true, guid="Player-1"} end
  local base, suffix = u:match("^(.-)(target)$")
  if base and base ~= "" and UNITS[base] then local t = UNITS[base].target; return t == "player" and {player=true, guid="Player-1", isPlayerUnit=true} or UNITS[t] end
  return UNITS[u] end
W.UnitExists = function(u) return U(u) ~= nil end
W.UnitName = function(u) local x = U(u); return x and x.name end
W.UnitLevel = function(u) local x = U(u); return x and x.level end
W.UnitIsPlayer = function(u) local x = U(u); return x and x.player or false end
W.UnitCanAttack = function(a, u) local x = U(u); return x and x.hostile or false end
W.UnitIsDead = function(u) local x = U(u); return x and x.dead or false end
W.UnitGUID = function(u) local x = U(u); return x and x.guid end
W.UnitIsUnit = function(a, b) local x, y = U(a), U(b); return x ~= nil and y ~= nil and x.guid == y.guid end
W.UnitAffectingCombat = function(u) return true end
W.InCombatLockdown = function() return P.combat end
W.CheckInteractDistance = function(u, i) local x = U(u); if not x then return false end
  return (i == 3 and x.dist <= 9.9) or (i == 4 and x.dist <= 28) or false end
W.GetCVar = function(k) return W.__cvars[k] end
W.PlaySound = function(id, ch) table.insert(SOUNDS, id) end
W.CreateVector2D = function(x, y) return {x=x, y=y, GetXY=function(s) return s.x, s.y end} end
-- Two fake maps: 84 = city (1000x800 yd, top-left A=1400 B=900), 1415 = continent, 999 = no world data
W.C_Map = {
  GetBestMapForUnit = function() return P.map or 84 end,
  GetMapInfo = function(id) return {name = id == 84 and "Stormwind City" or "Other"} end,
  GetPlayerMapPosition = function(id) return W.CreateVector2D(0.5, 0.5) end,
  GetWorldPosFromMapPos = function(id, v)
    if id == 84 then return 0, W.CreateVector2D(1400 - v.y * 800, 900 - v.x * 1000) end
    if id == 1415 then return 0, W.CreateVector2D(5000 - v.y * 10000, 5000 - v.x * 10000) end
    return nil end,
}
W.C_Timer = {NewTicker = function(i, f) TICK = f; TICK_INTERVAL = i end}
W.C_NamePlate = {GetNamePlates = function() local t = {} for _, tok in ipairs(PLATES) do t[#t+1] = {namePlateUnitToken = tok} end return t end}
W.StaticPopupDialogs = {}
W.StaticPopup_Show = function(which) LAST_POPUP = which end
W.GameTooltip_Hide = function() end
W.SlashCmdList = {}
W.SOUNDKIT = {RAID_WARNING = 8959, TELL_MESSAGE = 3081}
W.YES, W.NO = "Yes", "No"
-- World map frame with a mixin-style canvas
W.WorldMapFrame = widget("Frame", W.UIParent, "WorldMapFrame")
local canvas = widget("Frame", W.WorldMapFrame); canvas._w, canvas._h = 1002, 668
rawset(W.WorldMapFrame, "GetCanvas", function() return canvas end)
rawset(W.WorldMapFrame, "GetMapID", function() return WM_MAP or 84 end)
rawset(W.WorldMapFrame, "OnMapChanged", function() end)
rawset(W.WorldMapFrame, "OnCanvasScaleChanged", function() end)
rawset(W.WorldMapFrame, "ScrollContainer", {GetCanvasScale = function() return WM_SCALE or 1 end})
W.WorldMapFrame._shown = false
WM_CANVAS = canvas
for _, k in ipairs({"math","string","table","pairs","ipairs","type","tonumber","tostring","select","error","assert","setmetatable","getmetatable","next","unpack","print","rawget","rawset","pcall"}) do W[k] = _G[k] end
