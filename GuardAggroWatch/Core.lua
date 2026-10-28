-- Guard Aggro Watch: core data, position math, alerts, auto-learning and slash commands.
local ADDON, ns = ...

local GAW = CreateFrame("Frame")
ns.GAW = GAW
GuardAggroWatch = GAW

local sqrt, sin, cos, abs, max, min, floor = math.sqrt, math.sin, math.cos, math.abs, math.max, math.min, math.floor
local format, lower, tinsert, tremove = string.format, string.lower, table.insert, table.remove

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
ns.ICON = {
    guard = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", -- skull
    edge  = "Interface\\RaidFrame\\ReadyCheck-NotReady",         -- red X
    aggro = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    safe  = "Interface\\RaidFrame\\ReadyCheck-Ready",            -- green check
}
ns.KIND_LABEL = { guard = "Guard", edge = "Aggro line", aggro = "Auto aggro point", safe = "Blind spot" }

-- Aggro radius rule of thumb: ~20 yd vs an equal-level mob, +/-1 yd per level difference, clamped 5..45.
local BASE_AGGRO, MIN_AGGRO, MAX_AGGRO = 20, 5, 45

local DEFAULTS = {
    defaultRadius = 20,   -- used when a guard mark has no known level
    warnYards = 5,        -- caution buffer outside the aggro ring
    safeYards = 3,        -- how close counts as "standing on" a blind spot
    radarRange = 60,
    radarRotate = true,
    radarShown = true,
    radarLocked = false,
    radarScale = 1,
    radarPoint = { "CENTER", "CENTER", 300, -100 },
    minimap = true,
    worldmap = true,
    autoLearn = true,
    sound = true,
    flash = true,
    extraNames = {},
}

-- Lower-case substrings that identify capital guards (enUS). Only matched against non-player units.
local GUARD_PATTERNS = { "guard", "grunt", "sentinel", "peacekeeper", "bluffwatcher", "mountaineer", "kor'kron" }

local function Print(msg, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555GuardAggroWatch|r: " .. format(msg, ...))
end
ns.Print = Print

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Small texture pool: Acquire() hands out textures, ReleaseAll() hides every one of them.
function ns.NewTexturePool(parent, layer, sublevel)
    local pool = { items = {}, used = 0 }
    function pool:Acquire()
        self.used = self.used + 1
        local t = self.items[self.used]
        if not t then
            t = parent:CreateTexture(nil, layer, nil, sublevel)
            self.items[self.used] = t
        end
        t:ClearAllPoints()
        t:SetVertexColor(1, 1, 1, 1)
        t:Show()
        return t
    end
    function pool:ReleaseAll()
        for i = 1, #self.items do self.items[i]:Hide() end
        self.used = 0
    end
    return pool
end

---------------------------------------------------------------------------
-- Positions
--
-- UnitPosition returns (A, B, z, instanceID) in yards. A grows to the north, B grows to the west,
-- so for a point P seen from the player: east = player.B - P.B, north = P.A - player.A.
---------------------------------------------------------------------------

function GAW:GetPlayerPos()
    local a, b, _, inst = UnitPosition("player")
    if not a then return nil end
    return { a = a, b = b, inst = inst, facing = (GetPlayerFacing and GetPlayerFacing()) or 0 }
end

function GAW:Offset(pos, p)
    return pos.b - p.b, p.a - pos.a
end

function GAW:Distance(pos, p)
    local e, n = self:Offset(pos, p)
    return sqrt(e * e + n * n)
end

local rectCache = {}
-- World-space rectangle of a UI map, used to place world points on any map (city, zone, continent).
function GAW:MapRect(mapID)
    if not mapID then return nil end
    local cached = rectCache[mapID]
    if cached ~= nil then return cached or nil end
    local rect = false
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local inst, tl = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, mid = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if inst and tl and mid then
            local top, left = tl:GetXY()
            local midTop, midLeft = mid:GetXY()
            local width, height = (left - midLeft) * 2, (top - midTop) * 2
            if width ~= 0 and height ~= 0 then
                rect = { inst = inst, top = top, left = left, width = width, height = height }
            end
        end
    end
    rectCache[mapID] = rect
    return rect or nil
end

-- Returns normalized map x, y (and the rect when the conversion is exact) for point p on mapID.
function GAW:WorldToMap(p, mapID)
    local rect = self:MapRect(mapID)
    if rect and rect.inst == p.inst then
        return (rect.left - p.b) / rect.width, (rect.top - p.a) / rect.height, rect
    end
    if p.map == mapID and p.mx then
        return p.mx, p.my
    end
end

---------------------------------------------------------------------------
-- Guards
---------------------------------------------------------------------------

function GAW:NameIsGuard(name)
    if not name then return false end
    local n = lower(name)
    for _, pat in ipairs(GUARD_PATTERNS) do
        if n:find(pat, 1, true) then return true end
    end
    for _, pat in ipairs(self.db.settings.extraNames) do
        if n:find(lower(pat), 1, true) then return true end
    end
    return false
end

function GAW:IsHostileGuard(unit)
    return UnitExists(unit) and not UnitIsPlayer(unit) and UnitCanAttack("player", unit)
        and not UnitIsDead(unit) and self:NameIsGuard(UnitName(unit))
end

function GAW:GuardRadius(p)
    if p.r then return p.r end
    if p.learned then return p.learned end
    if p.level then
        local diff = (p.level == -1) and 10 or (p.level - UnitLevel("player"))
        return max(MIN_AGGRO, min(MAX_AGGRO, BASE_AGGRO + diff))
    end
    return self.db.settings.defaultRadius
end

---------------------------------------------------------------------------
-- Marks
---------------------------------------------------------------------------

function GAW:NewPoint(kind, pos, a, b, extra)
    local p = { kind = kind, a = a, b = b, inst = pos.inst, t = time() }
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        p.map = mapID
        local info = C_Map.GetMapInfo(mapID)
        p.zone = info and info.name
        local mx, my = self:WorldToMap(p, mapID)
        if not mx and a == pos.a and b == pos.b then
            local mp = C_Map.GetPlayerMapPosition(mapID, "player")
            if mp then mx, my = mp:GetXY() end
        end
        p.mx, p.my = mx, my
    end
    if extra then
        for k, v in pairs(extra) do p[k] = v end
    end
    tinsert(self.db.points, p)
    self:Refresh()
    return p
end

function GAW:AddMark(kind, extra)
    local pos = self:GetPlayerPos()
    if not pos then
        Print("Can't read your position here (the game hides it in instances).")
        return
    end
    local p = self:NewPoint(kind, pos, pos.a, pos.b, extra)
    if kind ~= "aggro" then
        Print("%s marked%s.", ns.KIND_LABEL[kind], p.note and (" - " .. p.note) or "")
    end
    return p
end

-- Places a mark <yards> straight ahead of where your character is facing.
function GAW:AddMarkAhead(yards, kind, extra)
    local pos = self:GetPlayerPos()
    if not pos then
        Print("Can't read your position here.")
        return
    end
    local f = pos.facing
    local p = self:NewPoint(kind, pos, pos.a + yards * cos(f), pos.b + yards * sin(f), extra)
    Print("%s marked %.0f yd ahead of you.", ns.KIND_LABEL[kind], yards)
    return p
end

function GAW:GuardExtraFromTarget(radius)
    local extra = { r = radius }
    if UnitExists("target") and not UnitIsPlayer("target") and self:NameIsGuard(UnitName("target")) then
        extra.name = UnitName("target")
        extra.level = UnitLevel("target")
    end
    return extra
end

function GAW:MarkGuard(radius, ahead)
    local extra = self:GuardExtraFromTarget(radius)
    local p
    if ahead then
        p = self:AddMarkAhead(ahead, "guard", extra)
    else
        p = self:AddMark("guard", extra)
    end
    if p then
        local how = p.r and "fixed" or (p.level and format("from level %s", p.level == -1 and "??" or p.level) or "default")
        Print("Aggro radius %.0f yd (%s)%s.", self:GuardRadius(p), how, p.name and (" for " .. p.name) or "")
    end
end

function GAW:Nearest(pos, maxYards, kind)
    local best, bestD, bestI
    for i, p in ipairs(self.db.points) do
        if p.inst == pos.inst and (not kind or p.kind == kind) then
            local d = self:Distance(pos, p)
            if d <= maxYards and (not bestD or d <= bestD) then best, bestD, bestI = p, d, i end
        end
    end
    return best, bestD, bestI
end

function GAW:Undo()
    local p = tremove(self.db.points)
    if p then Print("Removed last mark (%s).", ns.KIND_LABEL[p.kind]) else Print("Nothing to undo.") end
    self:Refresh()
end

function GAW:DeleteNearest()
    local pos = self:GetPlayerPos()
    if not pos then return end
    local p, d, i = self:Nearest(pos, 10)
    if not p then Print("No mark within 10 yd.") return end
    tremove(self.db.points, i)
    Print("Deleted %s %.1f yd away.", ns.KIND_LABEL[p.kind], d)
    self:Refresh()
end

function GAW:SetNearestRadius(value)
    local pos = self:GetPlayerPos()
    if not pos then return end
    local p = self:Nearest(pos, 60, "guard")
    if not p then Print("No guard mark within 60 yd.") return end
    if value == "auto" then
        p.r, p.learned = nil, nil
    else
        p.r = value
    end
    Print("Nearest guard radius is now %.0f yd.", self:GuardRadius(p))
    self:Refresh()
end

function GAW:Clear(scope)
    local pts = self.db.points
    if scope == "all" then
        wipe(pts)
        Print("All marks deleted.")
    else
        local mapID = C_Map.GetBestMapForUnit("player")
        local n = 0
        for i = #pts, 1, -1 do
            if pts[i].map == mapID then tremove(pts, i); n = n + 1 end
        end
        Print("Deleted %d marks on this map.", n)
    end
    self:Refresh()
end

function GAW:List()
    local zones = {}
    for _, p in ipairs(self.db.points) do
        local z = p.zone or "?"
        zones[z] = zones[z] or { guard = 0, edge = 0, aggro = 0, safe = 0 }
        zones[z][p.kind] = zones[z][p.kind] + 1
    end
    local any
    for z, c in pairs(zones) do
        any = true
        Print("%s: %d guards, %d aggro-line, %d auto-aggro, %d blind spots", z, c.guard, c.edge, c.aggro, c.safe)
    end
    if not any then Print("No marks yet. Type /gaw for help.") end
end

---------------------------------------------------------------------------
-- Status, alerts and auto-learning
---------------------------------------------------------------------------

-- How you stand relative to every marked guard ring.
function GAW:ComputeStatus(pos)
    local s = self.db.settings
    local st = { state = "none", inside = 0 }
    local bestMargin
    for _, p in ipairs(self.db.points) do
        if p.inst == pos.inst then
            local d = self:Distance(pos, p)
            if p.kind == "guard" and d < 150 then
                local r = self:GuardRadius(p)
                local margin = d - r
                if margin < 0 then st.inside = st.inside + 1 end
                if not bestMargin or margin < bestMargin then
                    bestMargin = margin
                    st.guard, st.dist, st.radius, st.margin = p, d, r, margin
                end
            elseif p.kind == "safe" and d <= s.safeYards then
                st.safeSpot = p
            end
        end
    end
    if bestMargin then
        if bestMargin < 0 then st.state = "inside"
        elseif bestMargin < s.warnYards then st.state = "caution"
        else st.state = "safe" end
    end
    st.live = self.live
    return st
end

-- Each alert has its own throttle, so a caution chime never swallows the inside alarm.
local lastState, lastSound = "none", {}
function GAW:Alert(st)
    local s = self.db.settings
    if st.state ~= lastState then
        local now = GetTime()
        local sound
        if st.state == "inside" then
            sound = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        elseif st.state == "caution" and lastState == "safe" then
            sound = SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081
        end
        if s.sound and sound and now - (lastSound[st.state] or 0) > 2 then
            PlaySound(sound, "Master")
            lastSound[st.state] = now
        end
        lastState = st.state
    end
    if s.flash and st.state == "inside" then self.flash:Show() else self.flash:Hide() end
end

local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("BACKGROUND")
flash:Hide()
local flashTex = flash:CreateTexture(nil, "BACKGROUND")
flashTex:SetAllPoints()
flashTex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
flashTex:SetBlendMode("ADD")
flash:SetScript("OnUpdate", function(self)
    self:SetAlpha(0.45 + 0.35 * sin(GetTime() * 6))
end)
GAW.flash = flash

-- Scans enemy nameplates: counts visible guards, estimates the closest one, and records where a
-- guard first turned on you (only when you were out of combat a moment before, so the point is
-- a real proximity pull rather than guards answering a fight).
GAW.live = { count = 0 }
local seenAggro = {}
local combatStart, lastOffense
function GAW:ScanNameplates(pos)
    local live = self.live
    live.count, live.nearest = 0, nil
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local now = GetTime()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if unit and self:IsHostileGuard(unit) then
            live.count = live.count + 1
            if not InCombatLockdown() then
                local bucket = (CheckInteractDistance(unit, 3) and 10) or (CheckInteractDistance(unit, 4) and 28)
                if bucket and (not live.nearest or bucket < live.nearest) then live.nearest = bucket end
            end
            if self.db.settings.autoLearn and pos and UnitIsUnit(unit .. "target", "player") then
                local guid = UnitGUID(unit)
                if guid and (not seenAggro[guid] or now - seenAggro[guid] > 60) then
                    seenAggro[guid] = now
                    local clean = ((not combatStart) or (now - combatStart < 1.5))
                        and ((not lastOffense) or (now - lastOffense > 5))
                    self:RecordAggro(pos, UnitName(unit), clean)
                end
            end
        end
    end
end

function GAW:RecordAggro(pos, guardName, clean)
    local p = self:NewPoint("aggro", pos, pos.a, pos.b, { name = guardName, clean = clean or nil })
    local msg = format("Pulled %s here", guardName or "a guard")
    if clean then
        -- Calibrate the nearest guard mark: you were at least this close when it noticed you.
        local g, d = self:Nearest(pos, MAX_AGGRO + 5, "guard")
        if g and not g.r and (not g.name or g.name == guardName) then
            g.learned = max(g.learned or MIN_AGGRO, min(MAX_AGGRO, d))
            msg = msg .. format(" - nearest guard mark now uses %.0f yd", g.learned)
        end
    end
    Print("%s.", msg)
    self:Refresh()
    return p
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------

function GAW:Refresh()
    if ns.WorldMap then ns.WorldMap:Refresh() end
    self:Update(true)
end

-- Nothing on screen can change while you stand still with the same guards in view, so the
-- redraw is skipped then (lurking is mostly standing still).
local scanElapsed, lastKey = 0, nil
function GAW:Update(force)
    if not self.db then return end
    local pos = self:GetPlayerPos()
    local live = self.live
    local key = pos and format("%.2f:%.2f:%.3f:%d:%s:%s:%s:%d", pos.a, pos.b, pos.facing, live.count,
        tostring(live.nearest), tostring(Minimap:GetZoom()), tostring(GetCVar("rotateMinimap")), UnitLevel("player"))
    if not force and key and key == lastKey then return end
    lastKey = key
    local st = pos and self:ComputeStatus(pos) or { state = "none", inside = 0, live = self.live }
    if pos then self:Alert(st) else self.flash:Hide() end
    if ns.Radar then ns.Radar:Update(pos, st) end
    if ns.Minimap then ns.Minimap:Update(pos) end
end

function GAW:OnTick(elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.25 then
        scanElapsed = 0
        self:ScanNameplates(self:GetPlayerPos())
    end
    self:Update()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local TOGGLES = {
    radar = "radarShown", minimap = "minimap", map = "worldmap", auto = "autoLearn",
    sound = "sound", flash = "flash", rotate = "radarRotate",
}

function GAW:ToggleSetting(key)
    local s = self.db.settings
    s[key] = not s[key]
    Print("%s %s.", key, s[key] and "|cff55ff55on|r" or "|cffff5555off|r")
    if ns.Radar then ns.Radar:ApplySettings() end
    self:Refresh()
end

local HELP = {
    "|cffffff00Marking|r (marks are shared by all your characters):",
    "  /gaw guard [yd] - mark a guard at your feet. Target the guard first to use its level. Easiest on a character of the guard's faction.",
    "  /gaw guard ahead <yd> [radius] - mark a guard <yd> in front of you",
    "  /gaw edge - mark a point of the aggro line (where a guard pulled you)",
    "  /gaw safe [note] - mark a blind spot;  /gaw safe ahead <yd> [note]",
    "  /gaw undo | del (nearest within 10 yd) | clear (this map) | clear all",
    "  /gaw setr <yd>|auto - set the nearest guard's aggro radius",
    "  /gaw list",
    "|cffffff00Display|r: /gaw radar | minimap | map | rotate | lock | unlock | range <yd> | scale <n>",
    "|cffffff00Alerts|r: /gaw sound | flash | warn <yd> | auto (record guard pulls automatically)",
    "|cffffff00Guards|r: /gaw default <yd> (radius when level unknown) | addname [text] (default: your target's name)",
}

local function SplitAhead(rest)
    local yd, tail = rest:match("^ahead%s+(%d+%.?%d*)%s*(.*)$")
    return tonumber(yd), tail
end

function GAW:Slash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = lower(cmd or "")
    local s = self.db.settings

    if cmd == "guard" then
        local ahead, tail = SplitAhead(rest)
        if ahead then
            self:MarkGuard(tonumber(tail), ahead)
        else
            self:MarkGuard(tonumber(rest))
        end
    elseif cmd == "edge" then
        self:AddMark("edge")
    elseif cmd == "safe" then
        local ahead, tail = SplitAhead(rest)
        if ahead then
            self:AddMarkAhead(ahead, "safe", { note = tail ~= "" and tail or nil })
        else
            self:AddMark("safe", { note = rest ~= "" and rest or nil })
        end
    elseif cmd == "undo" then
        self:Undo()
    elseif cmd == "del" or cmd == "delete" then
        self:DeleteNearest()
    elseif cmd == "clear" then
        if rest == "all" then
            StaticPopup_Show("GUARDAGGROWATCH_CLEAR_ALL")
        else
            StaticPopup_Show("GUARDAGGROWATCH_CLEAR_MAP")
        end
    elseif cmd == "setr" then
        local v = rest == "auto" and "auto" or tonumber(rest)
        if v then self:SetNearestRadius(v) else Print("Usage: /gaw setr <yards>|auto") end
    elseif cmd == "list" then
        self:List()
    elseif TOGGLES[cmd] then
        self:ToggleSetting(TOGGLES[cmd])
    elseif cmd == "lock" or cmd == "unlock" then
        s.radarLocked = (cmd == "lock")
        if ns.Radar then ns.Radar:ApplySettings() end
        Print("Radar %s.", s.radarLocked and "locked" or "unlocked (drag to move)")
    elseif cmd == "range" or cmd == "warn" or cmd == "default" or cmd == "scale" then
        local key = ({ range = "radarRange", warn = "warnYards", default = "defaultRadius", scale = "radarScale" })[cmd]
        local v = tonumber(rest)
        if v and v > 0 then
            s[key] = v
            if ns.Radar then ns.Radar:ApplySettings() end
            self:Refresh()
            Print("%s set to %s.", cmd, v)
        else
            Print("Usage: /gaw %s <number> (now %s)", cmd, s[key])
        end
    elseif cmd == "addname" then
        local name = rest ~= "" and rest or UnitName("target")
        if name then
            tinsert(s.extraNames, name)
            Print("NPCs named like \"%s\" now count as guards.", name)
        else
            Print("Usage: /gaw addname <text> (or target the NPC)")
        end
    else
        for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage(line) end
    end
end

StaticPopupDialogs["GUARDAGGROWATCH_CLEAR_ALL"] = {
    text = "Delete ALL Guard Aggro Watch marks in every city?",
    button1 = YES, button2 = NO,
    OnAccept = function() GAW:Clear("all") end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["GUARDAGGROWATCH_CLEAR_MAP"] = {
    text = "Delete all Guard Aggro Watch marks on this map?",
    button1 = YES, button2 = NO,
    OnAccept = function() GAW:Clear("map") end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

SLASH_GUARDAGGROWATCH1 = "/gaw"
SLASH_GUARDAGGROWATCH2 = "/guardaggro"
SlashCmdList.GUARDAGGROWATCH = function(msg) GAW:Slash(msg) end

BINDING_HEADER_GUARDAGGROWATCH = "Guard Aggro Watch"
BINDING_NAME_GAW_MARK_GUARD = "Mark guard at my position"
BINDING_NAME_GAW_MARK_EDGE = "Mark aggro line point"
BINDING_NAME_GAW_MARK_SAFE = "Mark blind spot"
BINDING_NAME_GAW_UNDO = "Undo last mark"
BINDING_NAME_GAW_TOGGLE_RADAR = "Toggle radar"

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

GAW:RegisterEvent("ADDON_LOADED")
GAW:RegisterEvent("PLAYER_REGEN_DISABLED")
GAW:RegisterEvent("PLAYER_REGEN_ENABLED")
GAW:RegisterEvent("PLAYER_ENTER_COMBAT")
GAW:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
GAW:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        GuardAggroWatchDB = GuardAggroWatchDB or {}
        local db = GuardAggroWatchDB
        db.settings = db.settings or {}
        db.points = db.points or {}
        CopyDefaults(DEFAULTS, db.settings)
        self.db = db
        if ns.Radar then ns.Radar:ApplySettings() end
        C_Timer.NewTicker(0.1, function() self:OnTick(0.1) end)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStart = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatStart = nil
    elseif event == "PLAYER_ENTER_COMBAT"
        or (event == "UNIT_SPELLCAST_SUCCEEDED" and UnitCanAttack("player", "target")) then
        -- You started auto-attacking or cast something with an enemy targeted. Remember it so
        -- guards answering your gank aren't mistaken for a proximity pull. (The combat log is
        -- restricted on this client, so these events stand in for it.)
        lastOffense = GetTime()
    end
end)
