local pass, fail = 0, 0
local function T(name, fn)
  CHAT = {}
  local ok, err = pcall(fn)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function chatHas(s) for _, m in ipairs(CHAT) do if m:find(s, 1, true) then return true end end return false end
local MRL, canvas, line, shadow, slash
local function frame(dt) canvas._scripts.OnUpdate(canvas, dt or 0.06) end
local function col() return line._color end
local function near(a, b) return math.abs(a - b) < 1e-6 end

T("load: defaults, slash, hidden until login", function()
  fire("ADDON_LOADED", "Other")
  assert(W.MeleeRangeLineDB == nil)
  fire("ADDON_LOADED", "MeleeRangeLine")
  local db = W.MeleeRangeLineDB
  assert(db.enabled and db.thickness == 3 and db.anchor == "auto")
  MRL = W.MeleeRangeLine; canvas, line, shadow = MRL.canvas, MRL.line, MRL.shadow
  assert(not canvas._shown, "canvas must not run OnUpdate before login")
  assert(line._thick == 3 and shadow._thick == 5)
  slash = W.SlashCmdList.MELEERANGELINE
  assert(W.SLASH_MELEERANGELINE1 == "/mrl")
end)

T("login shows canvas; no nameplate warning when enabled", function()
  KNOWN[1752] = true
  fire("PLAYER_LOGIN")
  assert(canvas._shown and canvas._strata == "BACKGROUND")
  assert(not chatHas("nameplates are off"))
end)

T("no target / friendly / dead target -> line hidden", function()
  UNITS.target = nil; frame(); assert(not line._shown)
  UNITS.target = {hostile=false, dist=3, guid="F"}; NP.target = makePlate(900, 700, 680); frame(); assert(not line._shown)
  UNITS.target = {hostile=true, dead=true, dist=3, guid="D"}; frame(); assert(not line._shown and not shadow._shown)
end)

T("hostile target in melee range -> green line from screen anchor to nameplate bottom", function()
  UNITS.target = {hostile=true, dist=3, guid="H1"}; NP.target = makePlate(900, 700, 680)
  SPELLRANGE[1752] = true
  fire("PLAYER_TARGET_CHANGED"); frame(0.001)
  assert(line._shown and shadow._shown)
  assert(near(col()[1], 0.1) and near(col()[2], 1.0), "expected green")
  assert(line._start[1] == 960 and line._start[2] == 540 - 60, line._start[1] .. "," .. line._start[2])
  assert(line._end[1] == 900 and line._end[2] == 680)
  assert(MRL.method == "spell")
end)

T("out of range -> red after throttle; not re-checked every frame", function()
  SPELLRANGE[1752] = false
  SPELLCALLS = 0
  frame(0.01); assert(near(col()[1], 0.1), "should still be green inside 0.05 s throttle")
  frame(0.05); assert(near(col()[1], 1.0) and near(col()[2], 0.15), "expected red")
  assert(SPELLCALLS == 1, SPELLCALLS)
end)

T("target change forces immediate recolor", function()
  SPELLRANGE[1752] = true
  fire("PLAYER_TARGET_CHANGED"); frame(0.001)
  assert(near(col()[2], 1.0))
end)

T("unknown spell answer falls through to next spell, then duel distance", function()
  KNOWN = {[1752]=true, [2098]=true}; fire("SPELLS_CHANGED")
  SPELLRANGE = {[1752]=nil, [2098]=false}
  MRL.dirty = true; frame(0.001)
  assert(MRL.state == false and MRL.method == "spell")
  SPELLRANGE = {}
  UNITS.target.dist = 8; MRL.dirty = true; frame(0.001)
  assert(MRL.state == true and MRL.method == "approx")
  UNITS.target.dist = 15; MRL.dirty = true; frame(0.001)
  assert(MRL.state == false and MRL.method == "approx")
end)

T("class without melee spells (mage) uses approx; status says so", function()
  CLASS = "MAGE"; KNOWN = {}; fire("SPELLS_CHANGED")
  UNITS.target.dist = 4; MRL.dirty = true; frame(0.001)
  assert(MRL.method == "approx" and MRL.state == true)
  CHAT = {}; slash("status"); assert(chatHas("approximate"))
  CLASS = "ROGUE"; KNOWN = {[1752]=true}; SPELLRANGE = {[1752]=true}; fire("SPELLS_CHANGED")
  CHAT = {}; slash("status"); assert(chatHas("exact"))
end)

T("CheckInteractDistance error is caught -> yellow unknown", function()
  KNOWN = {}; fire("SPELLS_CHANGED")
  local old = W.CheckInteractDistance
  W.CheckInteractDistance = function() error("blocked") end
  MRL.dirty = true; frame(0.001)
  W.CheckInteractDistance = old
  assert(MRL.state == nil and line._shown and near(col()[1], 1.0) and near(col()[2], 0.85))
  KNOWN = {[1752]=true}; fire("SPELLS_CHANGED")
end)

T("nameplate off screen / hidden -> line hidden", function()
  NP.target = nil; frame(); assert(not line._shown)
  NP.target = makePlate(900, 700, 680); NP.target._shown = false; frame(); assert(not line._shown)
  NP.target = makePlate(nil, nil, nil); frame(); assert(not line._shown)
  NP.target = makePlate(900, 700, 680); frame(); assert(line._shown)
end)

T("nameplate scale converts to canvas units", function()
  NP.target = makePlate(450, 350, 340, 2); frame()
  assert(line._end[1] == 900 and line._end[2] == 680)
  canvas._escale = 0.5; frame()
  assert(line._end[1] == 1800 and line._end[2] == 1360)
  assert(line._start[1] == 960, "screen anchor uses canvas size, not scale")
  canvas._escale = nil
end)

T("auto anchor uses own nameplate (centre); screen anchor ignores it", function()
  NP.player = makePlate(1000, 400, 380); frame()
  assert(line._start[1] == 1000 and line._start[2] == 400)
  slash("anchor screen"); frame(); assert(line._start[1] == 960 and line._start[2] == 480)
  slash("anchor AUTO"); frame(); assert(line._start[1] == 1000)
  NP.player._shown = false; frame(); assert(line._start[1] == 960)
  NP.player = nil
  CHAT = {}; slash("anchor sideways"); assert(chatHas("usage"))
end)

T("offset / targetoffset", function()
  slash("offset 10 -100"); frame(); assert(line._start[1] == 970 and line._start[2] == 440)
  slash("targetoffset -25"); frame(); assert(line._end[2] == 680 - 25)
  CHAT = {}; slash("offset 5"); assert(chatHas("usage"))
  CHAT = {}; slash("targetoffset x"); assert(chatHas("usage"))
end)

T("thickness / alpha / outline / colors validation", function()
  slash("thickness 8"); assert(line._thick == 8 and shadow._thick == 10)
  CHAT = {}; slash("thickness 0"); assert(chatHas("usage")); slash("thickness 50"); assert(W.MeleeRangeLineDB.thickness == 8)
  slash("alpha 0.5"); frame(0.001); assert(near(col()[4], 0.5))
  CHAT = {}; slash("alpha 2"); assert(chatHas("usage"))
  slash("outline"); frame(); assert(not shadow._shown and not W.MeleeRangeLineDB.outline)
  slash("outline"); frame(); assert(shadow._shown)
  slash("incolor 0 0 255"); frame(0.001); assert(near(col()[3], 1) and near(col()[1], 0))
  CHAT = {}; slash("outcolor 1 2"); assert(chatHas("usage"))
  CHAT = {}; slash("outcolor -1 0 0"); assert(chatHas("usage"))
  slash("outcolor 1 0 1"); SPELLRANGE[1752] = false; MRL.dirty = true; frame(0.001)
  assert(near(col()[1], 1) and near(col()[2], 0) and near(col()[3], 1))
end)

T("on/off/toggle + help", function()
  slash("off"); assert(not canvas._shown and not W.MeleeRangeLineDB.enabled)
  slash("toggle"); assert(canvas._shown)
  slash("TOGGLE"); assert(not canvas._shown)
  slash("on"); assert(canvas._shown)
  CHAT = {}; slash(""); assert(#CHAT > 8)
  CHAT = {}; slash("nonsense"); assert(chatHas("commands"))
end)

T("plates command respects combat", function()
  W.__cvars.nameplateShowEnemies = "0"
  P.combat = true; CHAT = {}; slash("plates"); assert(chatHas("combat") and W.__cvars.nameplateShowEnemies == "0")
  P.combat = false; slash("plates"); assert(W.__cvars.nameplateShowEnemies == "1")
end)

T("reset restores defaults", function()
  slash("reset"); local db = W.MeleeRangeLineDB
  assert(db.thickness == 3 and db.offsetY == -60 and db.anchor == "screen" == false and db.outline and db.inColor[2] == 1.0)
  assert(MRL.db == db)
end)

T("saved data upgrade: bad/missing fields repaired", function()
  W.MeleeRangeLineDB = {thickness = "big", anchor = "nowhere", inColor = 5, enabled = false}
  fire("ADDON_LOADED", "MeleeRangeLine")
  local db = W.MeleeRangeLineDB
  assert(db.thickness == 3 and db.anchor == "auto" and type(db.inColor) == "table" and db.enabled == false)
  fire("PLAYER_LOGIN"); assert(not canvas._shown)
  slash("on")
end)

T("login warns when enemy nameplates are off", function()
  W.__cvars.nameplateShowEnemies = "0"; CHAT = {}
  fire("PLAYER_LOGIN"); assert(chatHas("/mrl plates"))
  W.__cvars.nameplateShowEnemies = "1"
end)

T("performance: 10k frames", function()
  local t = os.clock(); for i = 1, 10000 do frame(0.016) end
  assert(os.clock() - t < 1.0, "too slow: " .. (os.clock() - t))
end)

print(pass .. " passed, " .. fail .. " failed")
TEST_FAILURES = fail
