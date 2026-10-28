local pass, fail = 0, 0
local function T(name, fn)
  CHAT, SOUNDS = {}, {}
  local ok, err = pcall(fn)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function lastChat() return CHAT[#CHAT] or "" end
local function chatHas(s) for _, m in ipairs(CHAT) do if m:find(s, 1, true) then return true end end return false end
local function tick(n) for i = 1, (n or 1) do CLOCK = CLOCK + 0.1; TICK() end end
local slash

T("load + first-run defaults", function()
  fire("ADDON_LOADED", "SomeOtherAddon")
  fire("ADDON_LOADED", "GuardAggroWatch")
  fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD")
  local db = W.GuardAggroWatchDB
  assert(db and db.settings.radarRange == 60 and #db.points == 0)
  assert(TICK and TICK_INTERVAL == 0.1)
  slash = W.SlashCmdList.GUARDAGGROWATCH
  assert(slash and W.SLASH_GUARDAGGROWATCH1 == "/gaw")
  tick(3)
end)
local GAW = W.GuardAggroWatch
local function pts() return W.GuardAggroWatchDB.points end
local function pos() return GAW:GetPlayerPos() end

T("help on empty / unknown command", function() slash(""); assert(#CHAT > 5); CHAT = {}; slash("blah"); assert(#CHAT > 5) end)

T("guard mark uses target level; case-insensitive command", function()
  UNITS.target = {name="Stormwind City Guard", level=72, hostile=false, guid="C-1"}
  slash("GUARD"); UNITS.target = nil
  local g = pts()[1]
  assert(g.kind == "guard" and g.level == 72 and g.name == "Stormwind City Guard")
  assert(GAW:GuardRadius(g) == 22, GAW:GuardRadius(g))
  assert(chatHas("22 yd"))
end)

T("radius formula clamps & ?? level", function()
  assert(GAW:GuardRadius({level=-1}) == 30)
  assert(GAW:GuardRadius({level=200}) == 45)
  assert(GAW:GuardRadius({level=1}) == 5)
  assert(GAW:GuardRadius({}) == 20)
end)

T("non-guard target is ignored for level", function()
  UNITS.target = {name="Innkeeper Allison", level=30, guid="C-2"}
  slash("guard"); UNITS.target = nil
  assert(pts()[2].level == nil and pts()[2].name == nil); slash("undo"); assert(#pts() == 1)
end)

T("bad numeric input", function()
  slash("guard abc"); assert(pts()[2].r == nil); slash("undo")
  slash("range -5"); assert(chatHas("Usage")); slash("range"); slash("warn 0")
  assert(W.GuardAggroWatchDB.settings.radarRange == 60 and W.GuardAggroWatchDB.settings.warnYards == 5)
  slash("setr"); assert(chatHas("Usage"))
  slash("safe ahead"); -- no number: treated as note "ahead"
  assert(pts()[#pts()].note == "ahead"); slash("undo")
end)

T("walk path: states, sounds, flash", function()
  CLOCK = CLOCK + 5
  P.a = 1000 + 60; tick()
  P.a = 1000 + 25; tick(); assert(SOUNDS[#SOUNDS] == 3081, "caution sound")
  P.a = 1000 + 23; tick(); local n = #SOUNDS
  P.a = 1000 + 15; tick(); assert(SOUNDS[#SOUNDS] == 8959 and #SOUNDS == n + 1, "inside sound: " .. table.concat(SOUNDS, ",") .. " n=" .. n .. " r=" .. GAW:GuardRadius(pts()[1]) .. " guards=" .. #pts())
  assert(GAW.flash:IsShown())
  tick(10); assert(#SOUNDS == n + 1, "no repeat while inside")
  P.a = 1000 + 60; tick(); assert(not GAW.flash:IsShown())
  P.a = 1000 + 15; tick(); assert(#SOUNDS == n + 1, "2s throttle"); P.a = 1060; tick(30)
  P.a = 1015; tick(); assert(#SOUNDS == n + 2)
  P.a = 1060; tick()
end)

T("sound/flash toggles", function()
  slash("sound"); slash("flash"); P.a = 1010; CLOCK = CLOCK + 5; tick()
  assert(#SOUNDS == 0 and not GAW.flash:IsShown())
  slash("sound"); slash("flash"); P.a = 1060; tick()
end)

T("overlapping rings counted", function()
  P.a, P.b = 1000, 515; slash("guard 20")   -- second guard 15 yd east-west apart
  P.a, P.b = 1000, 507; local st = GAW:ComputeStatus(pos()); assert(st.inside == 2 and st.state == "inside")
  P.a, P.b = 1060, 500; tick()
end)

T("other continent ignored", function()
  P.inst = 1; local st = GAW:ComputeStatus(pos()); assert(st.state == "none"); tick(); P.inst = 0
end)

T("instance: no position -> graceful", function()
  P.noPos = true; tick(); slash("guard"); assert(chatHas("Can't read")); slash("del"); slash("setr 5"); slash("safe ahead 5 x")
  local radar = W.GuardAggroWatchRadar; tick(); P.noPos = false; tick()
end)

T("facing nil", function()
  local f = W.GetPlayerFacing; W.GetPlayerFacing = function() return nil end; tick(); slash("safe ahead 5 x"); slash("undo"); W.GetPlayerFacing = f
end)

T("ahead marking geometry (west)", function()
  P.a, P.b, P.facing = 1100, 600, math.pi / 2
  slash("safe ahead 10 behind the bank"); local s = pts()[#pts()]
  assert(math.abs(s.a - 1100) < 1e-9 and math.abs(s.b - 610) < 1e-9 and s.note == "behind the bank")
  local e, n = GAW:Offset(pos(), s); assert(e < -9.99 and math.abs(n) < 1e-9, "west = negative east")
  -- map coords from rect: mx=(900-610)/1000
  assert(math.abs(s.mx - 0.29) < 1e-9 and math.abs(s.my - 0.375) < 1e-9)
  P.facing = 0
  slash("safe ahead 10"); local s2 = pts()[#pts()]; assert(math.abs(s2.a - 1110) < 1e-9, "north")
  slash("undo"); slash("undo"); P.a, P.b = 1060, 500
end)

-- nameplate auto-learning
local function plate(tok, t) UNITS[tok] = t; table.insert(PLATES, tok) end
T("auto-learn clean pull calibrates matching guard", function()
  PLATES, UNITS = {}, {}
  P.a, P.b = 1000 + 18, 500  -- 18 yd from guard #1 (level 72 -> 22)
  plate("nameplate1", {name="Stormwind City Guard", level=72, hostile=true, guid="G-1", target="player", dist=18})
  tick(3)
  local last = pts()[#pts()]; assert(last.kind == "aggro" and last.clean, "aggro point")
  assert(pts()[1].learned == 18, tostring(pts()[1].learned))
  assert(GAW:GuardRadius(pts()[1]) == 18)
  local n = #pts(); tick(20); assert(#pts() == n, "deduped within 60s")
end)

T("pull after you attacked: not clean, no calibration", function()
  PLATES, UNITS = {}, {}
  UNITS.target = {name="Enemy Player", hostile=true, player=true, guid="P-9"}
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 1)
  fire("PLAYER_REGEN_DISABLED")
  plate("nameplate2", {name="Stormwind City Guard", level=72, hostile=true, guid="G-2", target="player", dist=10})
  P.a = 1000 + 12; tick(3)
  local last = pts()[#pts()]; assert(last.kind == "aggro" and not last.clean)
  assert(pts()[1].learned == 18, "unchanged")
  fire("PLAYER_REGEN_ENABLED"); UNITS.target = nil
end)

T("spellcast with no hostile target is not offense; other unit events ignored", function()
  PLATES, UNITS = {}, {}; CLOCK = CLOCK + 10
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 1)   -- e.g. Stealth, no target
  fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "x", 1)
  plate("nameplate3", {name="Stormwind City Guard", level=72, hostile=true, guid="G-3", target="player", dist=10})
  tick(3); assert(pts()[#pts()].clean, "still clean")
end)

T("name mismatch / friendly / players / dead ignored", function()
  PLATES, UNITS = {}, {}; local n = #pts(); CLOCK = CLOCK + 10
  plate("nameplate4", {name="Stormwind City Guard", hostile=false, guid="G-4", target="player", dist=5})
  plate("nameplate5", {name="Guardianangel", hostile=true, player=true, guid="P-5", target="player", dist=5})
  plate("nameplate6", {name="Stormwind City Guard", hostile=true, dead=true, guid="G-6", target="player", dist=5})
  plate("nameplate7", {name="Defias Thug", hostile=true, guid="G-7", target="player", dist=5})
  tick(3); assert(#pts() == n)
  assert(GAW.live.count == 0)
  PLATES, UNITS = {}, {}
  plate("nameplate8", {name="Orgrimmar Grunt", level=70, hostile=true, guid="G-8", target="nameplate9", dist=8})
  tick(3); assert(GAW.live.count == 1 and GAW.live.nearest == 10, tostring(GAW.live.nearest))
  P.combat = true; tick(3); assert(GAW.live.nearest == nil); P.combat = false
  PLATES, UNITS = {}, {}
end)

T("calibration never below 5 yd", function()
  local g = {kind="guard", a=P.a, b=P.b, inst=0}; table.insert(pts(), g)
  GAW:RecordAggro(pos(), "Some Guard", true); assert(g.learned == 5, tostring(g.learned))
  table.remove(pts(), #pts()); table.remove(pts(), #pts() - 0)
end)

T("addname extends matching", function()
  UNITS.target = {name="Royal Dreadguard"}; slash("addname"); UNITS.target = nil
  assert(GAW:NameIsGuard("Captain Glynn") == false); slash("addname Captain"); assert(GAW:NameIsGuard("Captain Glynn"))
end)

T("setr / auto", function()
  P.a, P.b = 1005, 500
  slash("setr 33"); assert(GAW:GuardRadius(pts()[1]) == 33)
  slash("setr auto"); assert(GAW:GuardRadius(pts()[1]) == 22, "auto drops learned too")
end)

T("radar geometry", function()
  local s = W.GuardAggroWatchDB.settings
  s.radarRange = 50; s.radarRotate = true
  -- isolate one guard 10 yd north of the player
  SAVED = pts(); W.GuardAggroWatchDB.points = {{kind="guard", a=1010, b=500, inst=0, r=8}}
  P.a, P.b, P.facing = 1000, 500, 0; tick()
  local radar = W.GuardAggroWatchRadar
  local fills = {}
  local function walk(f) for _, c in ipairs(f._children) do if c._kind == "Texture" and c._shown and c._tex and c._tex:find("disc") then fills[#fills+1] = c end; walk(c) end end
  walk(radar)
  assert(#fills == 1, "#fills " .. #fills)
  local p = fills[1]._points[1]; local ppy = 100 / 50
  assert(math.abs(p[4]) < 1e-9 and math.abs(p[5] - 10 * ppy) < 1e-9, "north up: " .. p[4] .. "," .. p[5])
  assert(math.abs(fills[1]._w - 16 * ppy) < 1e-9)
  -- face west: north is on your right
  P.facing = math.pi / 2; tick(); p = fills[1]._points[1]
  assert(p[4] > 19.99 and math.abs(p[5]) < 1e-6, "west: " .. p[4] .. "," .. p[5])
  -- face east: north is on your left
  P.facing = -math.pi / 2; tick(); p = fills[1]._points[1]; assert(p[4] < -19.99)
  -- rotation off: always north up and arrow rotates
  slash("rotate"); tick(); p = fills[1]._points[1]; assert(math.abs(p[5] - 20) < 1e-6)
  slash("rotate"); P.facing = 0
  W.GuardAggroWatchDB.points = SAVED; s.radarRange = 60
end)

T("minimap: outdoor/indoor sizes, rotation, clipping, square", function()
  SAVED = pts(); W.GuardAggroWatchDB.points = {{kind="guard", a=1000, b=500, inst=0, r=40}}
  P.a, P.b = 1000, 500; GAW:Refresh()
  local function dots() local n = 0; for _, c in ipairs(W.Minimap._children[1]._children) do if c._shown and c._kind == "Texture" and c._tex and c._tex:find("disc") then n = n + 1 end end return n end
  fire("MINIMAP_UPDATE_ZOOM"); tick(); local outdoorDots = dots()
  assert(outdoorDots >= 12, "dots " .. outdoorDots)
  -- indoor: CVar follows inside zoom; ring bigger in pixels -> more dots
  W.__indoors = true; W.__cvars.minimapInsideZoom = "0"; W.__cvars.minimapZoom = "1"
  fire("MINIMAP_UPDATE_ZOOM"); tick(); local indoorDots = dots()
  assert(indoorDots > outdoorDots, indoorDots .. " vs " .. outdoorDots)
  -- missing CVars -> IsIndoors fallback (should not crash, uses indoor)
  W.__cvars.minimapZoom = nil; fire("MINIMAP_UPDATE_ZOOM"); tick(); assert(dots() == indoorDots)
  W.__cvars.minimapZoom = "0"; W.__indoors = false; W.__cvars.minimapInsideZoom = "1"
  fire("MINIMAP_UPDATE_ZOOM")
  -- far guard: no dots outside circle
  W.GuardAggroWatchDB.points = {{kind="guard", a=1000 + 220, b=500, inst=0, r=20}}
  GAW:Refresh(); local farDots = dots(); assert(farDots < 30)
  W.GetMinimapShape = function() return "SQUARE" end; GAW:Refresh(); assert(dots() >= farDots); W.GetMinimapShape = nil
  W.__cvars.rotateMinimap = "1"; P.facing = 1; tick(); W.__cvars.rotateMinimap = "0"; P.facing = 0
  slash("minimap"); assert(dots() == 0); slash("minimap")
  W.GuardAggroWatchDB.points = SAVED
end)

T("world map: pins, rings, fallback, toggle, scale", function()
  W.WorldMapFrame:Show(); local ov = WM_CANVAS._children[1]; assert(ov, "overlay")
  local function count(kind) local n = 0; for _, c in ipairs(ov._children) do if c._shown and ((kind == "pin" and c._kind == "Frame") or (kind == "fill" and c._kind == "Texture" and c._tex and c._tex:find("disc"))) then n = n + 1 end end return n end
  local total = #pts(); assert(count("pin") == total, count("pin") .. " vs " .. total)
  local guards = 0; for _, p in ipairs(pts()) do if p.kind == "guard" then guards = guards + 1 end end
  assert(count("fill") == guards)
  -- guard 1 at A=1000,B=500 -> (0.4,0.5) -> (400.8, -334)
  local pin; for _, c in ipairs(ov._children) do if c._kind == "Frame" and c.point == pts()[1] then pin = c end end
  local p = pin._points[1]; assert(math.abs(p[4] - 400.8) < 1e-6 and math.abs(p[5] + 334) < 1e-6, p[4] .. "," .. p[5])
  -- zoomed map: pin scale inverse, offsets scaled
  WM_SCALE = 2; W.WorldMapFrame.OnCanvasScaleChanged(W.WorldMapFrame)
  p = pin._points[1]; assert(pin._scale == 0.5 and math.abs(p[4] - 801.6) < 1e-6)
  WM_SCALE = 1
  -- continent map converts too; map without world data uses stored coords only on same map
  WM_MAP = 1415; W.WorldMapFrame.OnMapChanged(W.WorldMapFrame); assert(count("pin") == total)
  WM_MAP = 999; W.WorldMapFrame.OnMapChanged(W.WorldMapFrame); assert(count("pin") == 0)
  WM_MAP = nil; W.WorldMapFrame.OnMapChanged(W.WorldMapFrame)
  -- tooltip
  pin._scripts.OnEnter(pin)
  slash("map"); assert(count("pin") == 0); slash("map"); assert(count("pin") == total)
  W.WorldMapFrame:Hide(); GAW:Refresh(); assert(count("pin") == 0)
end)

T("del removes nearest, undo, list", function()
  P.a, P.b = 1000, 500; local n = #pts()
  slash("edge"); slash("del")
  assert(#pts() == n and chatHas("Deleted Aggro line"))
  slash("list"); assert(chatHas("Stormwind City"))
end)

T("radar lock/unlock/scale/drag save", function()
  local r = W.GuardAggroWatchRadar
  slash("lock"); assert(r._mouse == false); slash("unlock"); assert(r._mouse == true)
  slash("scale 1.5"); assert(r._scale == 1.5); slash("scale 1")
  r._scripts.OnDragStart(r); r:ClearAllPoints(); r:SetPoint("TOPLEFT", W.UIParent, "TOPLEFT", 50, -60); r._scripts.OnDragStop(r)
  local rp = W.GuardAggroWatchDB.settings.radarPoint; assert(rp[1] == "TOPLEFT" and rp[3] == 50 and rp[4] == -60)
  slash("radar"); assert(not r:IsShown()); slash("radar"); assert(r:IsShown())
end)

T("key bindings", function()
  local fh = io.open(ADDON_DIR .. "/Bindings.xml"); local xml = fh:read("*a"); fh:close()
  local n0 = #pts(); local count = 0
  for name, body in xml:gmatch('name="([%w_]+)"[^>]*>(.-)</Binding>') do
    assert(W["BINDING_NAME_" .. name], "missing label " .. name)
    local f = assert(loadstring(body)); setfenv(f, ENV); f(); count = count + 1
  end
  assert(count == 5 and W.BINDING_HEADER_GUARDAGGROWATCH)
  slash("radar")  -- toggle back after binding toggled it
end)

T("clear map/all via popups", function()
  slash("clear"); assert(LAST_POPUP == "GUARDAGGROWATCH_CLEAR_MAP")
  table.insert(pts(), {kind="safe", a=0, b=0, inst=0, map=12})
  W.StaticPopupDialogs.GUARDAGGROWATCH_CLEAR_MAP.OnAccept(); for _, p in ipairs(pts()) do  end; assert(#pts() == 1 and pts()[1].map == 12)
  slash("clear all"); assert(LAST_POPUP == "GUARDAGGROWATCH_CLEAR_ALL")
  W.StaticPopupDialogs.GUARDAGGROWATCH_CLEAR_ALL.OnAccept(); assert(#pts() == 0)
end)

T("saved data from older version reloads (missing new keys)", function()
  local db = W.GuardAggroWatchDB; db.settings = {radarRange = 45}; db.points = {{kind="guard", a=1, b=2, inst=0}}
  -- simulate a /reload: re-run ADDON_LOADED handler
  GAW:RegisterEvent("ADDON_LOADED"); fire("ADDON_LOADED", "GuardAggroWatch")
  assert(GAW.db.settings.radarRange == 45 and GAW.db.settings.warnYards == 5 and type(GAW.db.settings.extraNames) == "table")
  tick()
end)

T("performance: 100 marks (a busy city)", function()
  local db = W.GuardAggroWatchDB.points
  for i = 1, 100 do db[#db+1] = {kind = (i % 3 == 0) and "guard" or "safe", a = 1000 + (i % 10) * 12, b = 500 + math.floor(i / 10) * 12, inst = 0, map = 84} end
  local t0 = os.clock(); for i = 1, 50 do tick() end
  print(string.format("   PERF: %.2f ms per tick with 100 marks, standing still", (os.clock() - t0) / 50 * 1000))
  t0 = os.clock(); for i = 1, 50 do P.a = P.a + 0.5; tick() end
  print(string.format("   PERF: %.2f ms per tick with 100 marks, moving", (os.clock() - t0) / 50 * 1000)); P.a = 1060; W.wipe(db)
end)
T("performance: 1000 marks", function()
  local db = W.GuardAggroWatchDB.points
  for i = 1, 1000 do db[#db+1] = {kind = (i % 3 == 0) and "guard" or "safe", a = 1000 + (i % 40) * 5, b = 500 + math.floor(i / 40) * 5, inst = 0, map = 84} end
  local t0 = os.clock(); for i = 1, 50 do P.a = P.a + 0.5; tick() end
  local per = (os.clock() - t0) / 50 * 1000
  print(string.format("   PERF: %.2f ms per tick with 1000 marks (ticks every 100 ms)", per))
  W.WorldMapFrame:Show(); t0 = os.clock(); GAW:Refresh(); print(string.format("   PERF: world map refresh %.2f ms", (os.clock() - t0) * 1000)); W.WorldMapFrame:Hide()
  W.wipe(db)
end)

print(string.format("\n%d passed, %d failed", pass, fail))
TEST_FAILURES = fail
