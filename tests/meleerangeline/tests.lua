local pass, fail = 0, 0
local function T(name, fn)
  CHAT = {}
  local ok, err = pcall(fn)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function chatHas(s) for _, m in ipairs(CHAT) do if m:find(s, 1, true) then return true end end return false end
local MRL, canvas, holder, line, shadow, dot, slash
local function frame(dt) canvas._scripts.OnUpdate(canvas, dt or 0.06) end
local function col() return line._color end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function drawn() return line._shown and holder._shown and holder:IsVisible() end

T("load: defaults, slash, hidden until login; old anchor setting dropped", function()
  W.MeleeRangeLineDB = {anchor = "auto"}
  fire("ADDON_LOADED", "Other")
  fire("ADDON_LOADED", "MeleeRangeLine")
  local db = W.MeleeRangeLineDB
  assert(db.enabled and db.thickness == 3 and db.dot and db.anchor == nil)
  MRL = W.MeleeRangeLine
  canvas, holder, line, shadow, dot = MRL.canvas, MRL.holder, MRL.line, MRL.shadow, MRL.dot
  assert(not canvas._shown, "no OnUpdate before login")
  assert(line._thick == 3 and shadow._thick == 5)
  slash = W.SlashCmdList.MELEERANGELINE
  assert(W.SLASH_MELEERANGELINE1 == "/mrl")
end)

T("login: version message, canvas shown", function()
  KNOWN[1752] = true
  fire("PLAYER_LOGIN")
  assert(canvas._shown and chatHas("v1.0.2 loaded") and not chatHas("nameplates are off"))
end)

T("no target / friendly / dead -> nothing drawn", function()
  UNITS.target = nil; frame(); assert(not holder._shown and not dot._shown)
  UNITS.target = {hostile=false, dist=3, guid="F"}; NP.target = makePlate(); frame(); assert(not holder._shown)
  UNITS.target = {hostile=true, dead=true, dist=3, guid="D"}; frame(); assert(not holder._shown and not dot._shown)
end)

T("hostile in melee -> green line living INSIDE the target nameplate, no rule violations", function()
  UNITS.target = {hostile=true, dist=3, guid="H1"}; NP.target = makePlate()
  SPELLRANGE[1752] = true; CHAT = {}
  fire("PLAYER_TARGET_CHANGED"); frame(0.001)
  assert(not chatHas("refused"), table.concat(CHAT, "|"))
  assert(drawn() and shadow._shown and not dot._shown)
  assert(holder._parent == NP.target, "holder must be parented to the nameplate")
  assert(line._start[1] == "CENTER" and line._start[2] == W.UIParent and line._start[3] == 0 and line._start[4] == -60)
  assert(line._end[1] == "BOTTOM" and line._end[2] == holder and line._end[4] == 0)
  assert(near(col()[1], 0.1) and near(col()[2], 1.0), "expected green")
end)

T("anchors set once, redone on new plate", function()
  local n = line._anchorCalls
  for i = 1, 50 do frame(0.016) end
  assert(line._anchorCalls == n)
  NP.target = makePlate(); frame()
  assert(line._anchorCalls == n + 1 and holder._parent == NP.target)
end)

T("out of range -> red after throttle", function()
  SPELLRANGE[1752] = false; SPELLCALLS = 0
  frame(0.01); assert(near(col()[1], 0.1))
  frame(0.05); assert(near(col()[1], 1.0) and near(col()[2], 0.15))
  assert(SPELLCALLS == 1, SPELLCALLS)
  SPELLRANGE[1752] = true; fire("PLAYER_TARGET_CHANGED"); frame(0.001); assert(near(col()[2], 1.0))
end)

T("spell fallthrough then duel distance", function()
  KNOWN = {[1752]=true, [2098]=true}; fire("SPELLS_CHANGED")
  SPELLRANGE = {[2098]=false}; MRL.dirty = true; frame(0.001)
  assert(MRL.state == false and MRL.method == "spell")
  SPELLRANGE = {}; UNITS.target.dist = 8; MRL.dirty = true; frame(0.001)
  assert(MRL.state == true and MRL.method == "approx")
  UNITS.target.dist = 15; MRL.dirty = true; frame(0.001)
  assert(MRL.state == false)
end)

T("mage uses approx; status reports it", function()
  CLASS = "MAGE"; KNOWN = {}; fire("SPELLS_CHANGED")
  UNITS.target.dist = 4; MRL.dirty = true; frame(0.001)
  assert(MRL.method == "approx" and MRL.state == true)
  CHAT = {}; slash("status"); assert(chatHas("approximate") and chatHas("v1.0.2"))
  CLASS = "ROGUE"; KNOWN = {[1752]=true}; SPELLRANGE = {[1752]=true}; fire("SPELLS_CHANGED")
end)

T("range API errors and secret values -> yellow", function()
  local oldSR, oldCID = W.C_Spell.IsSpellInRange, W.CheckInteractDistance
  W.C_Spell.IsSpellInRange = function() error("blocked") end
  W.CheckInteractDistance = function() error("blocked") end
  MRL.dirty = true; frame(0.001)
  assert(MRL.state == nil and near(col()[2], 0.85))
  local secret = {}; SECRETS[secret] = true
  W.C_Spell.IsSpellInRange = function() return secret end
  W.CheckInteractDistance = function() return secret end
  MRL.dirty = true; frame(0.001)
  assert(MRL.state == nil and drawn())
  W.C_Spell.IsSpellInRange, W.CheckInteractDistance = oldSR, oldCID
end)

T("nameplate missing/hidden -> dot at character in range color, line hidden", function()
  MRL.dirty = true
  NP.target = nil; frame(0.001)
  assert(not holder._shown and dot._shown and holder._parent == canvas)
  assert(dot._points[1][2] == canvas and dot._points[1][5] == -60)
  assert(near(dot._color[2], 1.0), "dot uses range color")
  NP.target = makePlate(); NP.target._shown = false; frame(); assert(not holder._shown and dot._shown)
  NP.target = makePlate(); frame(); assert(drawn() and not dot._shown)
  slash("dot"); NP.target = nil; frame(); assert(not dot._shown)
  slash("dot"); frame(); assert(dot._shown)
  NP.target = makePlate(); frame()
end)

T("game refuses the line -> one report, dot fallback, retried on next target", function()
  local old = rawget(getmetatable(W.UIParent), "SetEndPoint")
  rawset(getmetatable(W.UIParent), "SetEndPoint", function() error("Line:SetEndPoint()(): Not allowed to depend on nameplate 1") end)
  NP.target = makePlate(); CHAT = {}
  for i = 1, 30 do frame(0.016) end
  local n = 0; for _, m in ipairs(CHAT) do if m:find("refused", 1, true) then n = n + 1 end end
  assert(n == 1, n)
  assert(not holder._shown and dot._shown and holder._parent == canvas)
  rawset(getmetatable(W.UIParent), "SetEndPoint", old)
  frame(); assert(not holder._shown, "same plate stays blocked")
  fire("PLAYER_TARGET_CHANGED"); frame(); assert(drawn(), "retried after target change")
  CHAT = {}; slash("status"); assert(chatHas("last blocked"))
end)

T("other blocked API -> one report, 5 s pause, recovers", function()
  local old = W.UnitCanAttack
  W.UnitCanAttack = function() error("Action[X] failed because[restricted]") end
  CHAT = {}
  for i = 1, 20 do frame(0.016) end
  local n = 0; for _, m in ipairs(CHAT) do if m:find("refused", 1, true) then n = n + 1 end end
  assert(n == 1, n)
  W.UnitCanAttack = old
  frame(); assert(not holder._shown)
  CLOCK = CLOCK + 6; frame(); assert(drawn())
end)

T("offset / targetoffset re-anchor", function()
  slash("offset 10 -100"); frame(); assert(line._start[3] == 10 and line._start[4] == -100)
  slash("targetoffset -25"); frame(); assert(line._end[4] == -25)
  CHAT = {}; slash("offset 5"); assert(chatHas("usage"))
  CHAT = {}; slash("targetoffset x"); assert(chatHas("usage"))
end)

T("thickness / alpha / outline / colors", function()
  slash("thickness 8"); assert(line._thick == 8 and shadow._thick == 10)
  CHAT = {}; slash("thickness 0"); assert(chatHas("usage"))
  slash("alpha 0.5"); frame(0.001); assert(near(col()[4], 0.5))
  CHAT = {}; slash("alpha 2"); assert(chatHas("usage"))
  slash("outline"); frame(); assert(not shadow._shown)
  slash("outline"); frame(); assert(shadow._shown)
  slash("incolor 0 0 255"); frame(0.001); assert(near(col()[3], 1) and near(col()[1], 0))
  CHAT = {}; slash("outcolor 1 2"); assert(chatHas("usage"))
  CHAT = {}; slash("outcolor -1 0 0"); assert(chatHas("usage"))
end)

T("on/off/toggle/help; off detaches from nameplate", function()
  slash("off"); assert(not canvas._shown and holder._parent == canvas)
  slash("toggle"); assert(canvas._shown)
  slash("on"); frame(); assert(drawn())
  CHAT = {}; slash(""); assert(chatHas("commands") and chatHas("/mrl dot"))
  CHAT = {}; slash("anchor screen"); assert(chatHas("commands"), "anchor command removed")
end)

T("plates command respects combat", function()
  W.__cvars.nameplateShowEnemies = "0"
  P.combat = true; CHAT = {}; slash("plates"); assert(chatHas("combat") and W.__cvars.nameplateShowEnemies == "0")
  P.combat = false; slash("plates"); assert(W.__cvars.nameplateShowEnemies == "1")
end)

T("reset + saved-data repair", function()
  slash("reset"); local db = W.MeleeRangeLineDB
  assert(db.thickness == 3 and db.offsetY == -60 and db.dot and MRL.db == db)
  W.MeleeRangeLineDB = {thickness = "big", inColor = 5, enabled = false}
  fire("ADDON_LOADED", "MeleeRangeLine")
  db = W.MeleeRangeLineDB
  assert(db.thickness == 3 and type(db.inColor) == "table" and db.enabled == false)
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
