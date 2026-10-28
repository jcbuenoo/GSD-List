local addonName, ns = ...

local GetTime, UnitGUID, bit_band = GetTime, UnitGUID, bit.band
local CombatLogGetCurrentEventInfo, GetPlayerInfoByGUID = CombatLogGetCurrentEventInfo, GetPlayerInfoByGUID
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
local GetSpellInfo = GetSpellInfo or function(id)
    local info = C_Spell and C_Spell.GetSpellInfo(id)
    if info then return info.name, nil, info.iconID end
end
local GetSpellTexture = GetSpellTexture or (C_Spell and C_Spell.GetSpellTexture)

local DEDUPE_WINDOW = 1.0 -- same cast seen via combat log and unit events
local IDLE_TIMEOUT = 60   -- drop a pre-filled enemy row after this long without activity (outside arena)
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local DEFAULTS = {
    point = { "CENTER", "UIParent", "CENTER", 0, 150 },
    locked = false, scale = 1, iconSize = 30, maxRows = 6, maxIcons = 12,
    showUnused = "arena", -- "arena" | "always" | "never"
    useTalents = true,
    overrides = {},       -- [baseSpellID] = seconds
}

local db
local enemies = {}    -- [guid] = { name, class, race, arena, lastSeen, cds = { [baseID] = { start, duration } } }
local baseOf = {}     -- [any rank spellID] = base spellID
local nameToBase = {} -- fallback when the combat log gives spellID 0
local recent = {}     -- [guid:spellID] = time, for de-duplication
local inArena = false
local typeOrder, typeColor = {}, {}
for i, t in ipairs(ns.TYPES) do typeOrder[t.key], typeColor[t.key] = i, t.color end

-- Baseline spells to pre-fill as "ready", built once: [class or race] = { baseID, ... }
local prefill = { GENERAL = {} }
for id, s in pairs(ns.SPELLS) do
    baseOf[id] = id
    for _, r in ipairs(s.ranks or {}) do baseOf[r] = id end
    if not s.talent then
        local key = s.race or s.class
        prefill[key] = prefill[key] or {}
        table.insert(prefill[key], id)
    end
end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GSD CDs:|r " .. msg) end

local function GetDuration(base)
    local s = ns.SPELLS[base]
    return db.overrides[base] or s.cd + ((db.useTalents and s.adj) or 0)
end

local function ShowUnusedNow()
    return db.showUnused == "always" or (db.showUnused == "arena" and inArena)
end

local function GetEnemy(guid, name)
    local e = enemies[guid]
    if not e then
        e = { name = name and name:match("^[^-]+") or "?", cds = {} }
        enemies[guid] = e
    end
    if not e.class and GetPlayerInfoByGUID then
        local _, class, _, race = GetPlayerInfoByGUID(guid)
        e.class, e.race = class, race
    end
    e.lastSeen = GetTime()
    return e
end

-------------------------------------------------------------------------------
-- Cooldown state
-------------------------------------------------------------------------------

local function OnCast(guid, name, spellID)
    local base, reset = baseOf[spellID], ns.RESETS[spellID]
    if not base and not reset then return false end
    local now = GetTime()
    local key = guid .. ":" .. spellID
    if recent[key] and now - recent[key] < DEDUPE_WINDOW then return false end
    recent[key] = now

    local e = GetEnemy(guid, name)
    if type(reset) == "string" then -- every spell of that class except this one
        for id in pairs(e.cds) do
            if ns.SPELLS[id].class == reset and id ~= spellID then e.cds[id] = nil end
        end
    elseif reset then
        for _, id in ipairs(reset) do e.cds[id] = nil end
    end
    if base then
        e.cds[base] = { start = now, duration = GetDuration(base) }
        local class = ns.SPELLS[base].class
        if not e.class and class ~= "GENERAL" then e.class = class end
    end
    return true
end

-- In arena a pet's cast (Spell Lock) is credited to its owner's row.
local function ResolvePetOwner(petGUID)
    for i = 1, 5 do
        if UnitGUID("arenapet" .. i) == petGUID and UnitGUID("arena" .. i) then
            return UnitGUID("arena" .. i), UnitName("arena" .. i)
        end
    end
end

local function Prune(now)
    local showUnused = ShowUnusedNow()
    for guid, e in pairs(enemies) do
        for id, cd in pairs(e.cds) do
            if now >= cd.start + cd.duration then e.cds[id] = nil end
        end
        if not (next(e.cds) or (showUnused and (e.arena or now - e.lastSeen < IDLE_TIMEOUT))) then
            enemies[guid] = nil
        end
    end
    for key, t in pairs(recent) do
        if now - t > DEDUPE_WINDOW then recent[key] = nil end
    end
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "GSD_EnemyCDsAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(160, 18)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, "UIParent", rp, x, y }
end)
anchor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.text:SetPoint("CENTER")
anchor.text:SetText("GSD Enemy CDs (drag)")

local rows = {}

-- Font strings must have a font before SetText, so this runs at creation and on resize.
local function SetIconFont(icon, size)
    icon.timer:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(size * 0.42)), "OUTLINE")
end

-- Only touch the widget when the value changes; Render runs 10x a second.
local function SetText(fs, text)
    if fs.shownText ~= text then
        fs:SetText(text)
        fs.shownText = text
    end
end

local function CreateIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetAllPoints()
    icon.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", 2, -2)
    icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon.tex)
    icon.cd:SetDrawEdge(false)
    if icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(true) end
    icon.cd.noCooldownCount = true -- keep OmniCC off our icons; we draw our own timer
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cd:GetFrameLevel() + 2)
    icon.timer = overlay:CreateFontString(nil, "OVERLAY")
    icon.timer:SetPoint("CENTER", 0, 0)
    SetIconFont(icon, db.iconSize)
    return icon
end

local function LayoutRow(row, i)
    local size = db.iconSize
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 94, -4 - (i - 1) * (size + 4))
    row:SetSize((size + 3) * db.maxIcons, size)
    row.name:ClearAllPoints()
    row.name:SetPoint("RIGHT", row, "LEFT", -4, 0)
    row.name:SetWidth(90)
    for j, icon in ipairs(row.icons) do
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row, "LEFT", (j - 1) * (size + 3), 0)
        SetIconFont(icon, size)
    end
    row.layoutSize = size
end

local function GetRow(i, iconCount)
    local row = rows[i]
    if not row then
        row = CreateFrame("Frame", nil, anchor)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetJustifyH("RIGHT")
        row.icons = {}
        rows[i] = row
    end
    local grew = #row.icons < iconCount
    for j = #row.icons + 1, iconCount do row.icons[j] = CreateIcon(row) end
    if grew or row.layoutSize ~= db.iconSize then LayoutRow(row, i) end
    return row
end

local function FormatTime(t)
    return t >= 60 and string.format("%dm", math.ceil(t / 60)) or string.format("%d", math.ceil(t))
end

local function UpdateIcon(icon, base, cd, now)
    if icon.base ~= base then
        icon.tex:SetTexture((GetSpellTexture and GetSpellTexture(base)) or QUESTION_MARK)
        local c = typeColor[ns.SPELLS[base].type]
        icon.border:SetVertexColor(c[1], c[2], c[3])
        icon.base = base
    end
    -- no cd = known spell that hasn't been used: ready
    SetText(icon.timer, cd and FormatTime(cd.start + cd.duration - now) or "")
    local start, duration = cd and cd.start, cd and cd.duration
    if icon.cdStart ~= start or icon.cdDuration ~= duration or not icon.styled then
        icon.tex:SetDesaturated(cd ~= nil)
        icon.cd:SetCooldown(start or 0, duration or 0)
        icon.cdStart, icon.cdDuration, icon.styled = start, duration, true
    end
    icon:Show()
end

local function SortSpells(a, b)
    local ta, tb = typeOrder[ns.SPELLS[a.base].type], typeOrder[ns.SPELLS[b.base].type]
    if ta ~= tb then return ta < tb end
    local ra = a.cd and (a.cd.start + a.cd.duration) or 0
    local rb = b.cd and (b.cd.start + b.cd.duration) or 0
    if ra ~= rb then return ra < rb end
    return a.base < b.base
end

-- pooled list entries: no garbage per tick
local spellList, spellPool = {}, {}
local function AddSpell(base, cd)
    local n = #spellList + 1
    local item = spellPool[n] or {}
    spellPool[n], spellList[n] = item, item
    item.base, item.cd = base, cd
end

local function AddUnused(e, key)
    for _, base in ipairs(prefill[key]) do
        if not e.cds[base] then AddSpell(base, nil) end
    end
end

local function BuildSpellList(e, showUnused)
    wipe(spellList)
    for base, cd in pairs(e.cds) do AddSpell(base, cd) end
    if showUnused and e.class then
        AddUnused(e, "GENERAL")
        if prefill[e.class] then AddUnused(e, e.class) end
        if e.race and prefill[e.race] then AddUnused(e, e.race) end
    end
    table.sort(spellList, SortSpells)
end

local sortList, sortPool = {}, {}
local function SortEnemies(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    if a.e.arena ~= b.e.arena then return (a.e.arena or 9) < (b.e.arena or 9) end
    return a.e.lastSeen > b.e.lastSeen
end

local function Render()
    local now = GetTime()
    Prune(now)
    local showUnused = ShowUnusedNow()
    wipe(sortList)
    local targetGUID, focusGUID = UnitGUID("target"), UnitGUID("focus")
    for guid, e in pairs(enemies) do
        local n = #sortList + 1
        local item = sortPool[n] or {}
        sortPool[n], sortList[n] = item, item
        item.guid, item.e = guid, e
        -- in arena keep arena1-5 order stable instead of jumping to the target
        item.priority = (not inArena and ((guid == targetGUID and 1) or (guid == focusGUID and 2))) or 3
    end
    table.sort(sortList, SortEnemies)

    local shown = 0
    for _, item in ipairs(sortList) do
        if shown >= db.maxRows then break end
        local e = item.e
        BuildSpellList(e, showUnused)
        if #spellList > 0 then
            shown = shown + 1
            local count = math.min(#spellList, db.maxIcons)
            local row = GetRow(shown, count)
            SetText(row.name, item.guid == targetGUID and ("> " .. e.name) or e.name)
            if row.shownClass ~= e.class then
                local cc = e.class and RAID_CLASS_COLORS[e.class]
                row.name:SetTextColor(cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1)
                row.shownClass = e.class
            end
            for j = 1, count do UpdateIcon(row.icons[j], spellList[j].base, spellList[j].cd, now) end
            for j = count + 1, #row.icons do row.icons[j]:Hide() end
            row:Show()
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
end

local function ApplyLayout()
    local p = db.point
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    anchor:SetScale(db.scale)
    for i, row in ipairs(rows) do LayoutRow(row, i) end
    anchor:EnableMouse(not db.locked)
    anchor:SetBackdropColor(0.6, 0.1, 0.1, db.locked and 0 or 0.6)
    anchor.text:SetShown(not db.locked)
end

local ticker
local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, function()
        Render()
        if not next(enemies) then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function OnCombatLog()
    -- No UNIT_DIED handling on purpose: cooldowns survive death, and Feign Death is logged as a death.
    local _, event, _, srcGUID, srcName, srcFlags, _, destGUID, _, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    if event ~= "SPELL_CAST_SUCCESS" and not (event == "SPELL_AURA_APPLIED" and srcGUID == destGUID) then return end
    if bit_band(srcFlags, HOSTILE) == 0 then return end
    if spellID == 0 then spellID = nameToBase[spellName] or 0 end

    if bit_band(srcFlags, TYPE_PLAYER) ~= 0 then
        if OnCast(srcGUID, srcName, spellID) then StartTicker() end
    elseif bit_band(srcFlags, TYPE_PET) ~= 0 then
        local base = baseOf[spellID]
        if not (base and ns.SPELLS[base].pet) then return end
        local ownerGUID, ownerName = ResolvePetOwner(srcGUID)
        if OnCast(ownerGUID or srcGUID, ownerName or ((srcName or "Pet") .. " (pet)"), spellID) then StartTicker() end
    end
end

-- Some casts (PvP trinket in particular) can be missing from the combat log.
-- This event fires for every unit's every cast, so the cheap table lookup goes first.
local function OnUnitCast(unit, spellID)
    if not (baseOf[spellID] or ns.RESETS[spellID]) then return end
    if not (unit == "target" or unit == "focus" or unit:find("^arena%d$") or unit:find("^nameplate")) then return end
    if not UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    if OnCast(UnitGUID(unit), UnitName(unit), spellID) then StartTicker() end
end

local function OnArenaOpponent(unit, reason)
    if reason ~= "seen" or not unit:find("^arena%d$") or not UnitGUID(unit) then return end
    local e = GetEnemy(UnitGUID(unit), UnitName(unit))
    e.arena = tonumber(unit:match("%d"))
    e.class = e.class or select(2, UnitClass(unit))
    e.race = e.race or select(2, UnitRace(unit))
    StartTicker()
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "COMBAT_LOG_EVENT_UNFILTERED",
                     "UNIT_SPELLCAST_SUCCEEDED", "ARENA_OPPONENT_UPDATE", "PLAYER_TARGET_CHANGED" }) do
    frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnUnitCast(arg1, arg3)
    elseif event == "ARENA_OPPONENT_UPDATE" then
        OnArenaOpponent(arg1, arg2)
    elseif event == "ADDON_LOADED" and arg1 == addonName then
        GSD_EnemyCDsDB = GSD_EnemyCDsDB or {}
        db = GSD_EnemyCDsDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
        end
        for id in pairs(baseOf) do
            local name = GetSpellInfo(id)
            if name and not nameToBase[name] then nameToBase[name] = id end
        end
        ApplyLayout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        inArena = select(2, IsInInstance()) == "arena"
        wipe(enemies)
        Render()
    elseif event == "PLAYER_TARGET_CHANGED" and next(enemies) then
        Render()
    end
end)

-------------------------------------------------------------------------------
-- Test mode & slash commands
-------------------------------------------------------------------------------

-- { name, class, race, { { spellID, seconds since used } } }
local TEST_ENEMIES = {
    { "Stabbyboi", "ROGUE", "Human", { { 42292, 10 }, { 1766, 2 }, { 2094, 30 }, { 1856, 5 } } },
    { "Frostyfrank", "MAGE", "Gnome", { { 2139, 4 }, { 1953, 3 }, { 45438, 60 }, { 11958, 1 } } },
    { "Holyhank", "PRIEST", "Dwarf", { { 8122, 6 }, { 33206, 20 }, { 20594, 40 } } },
}

local function RunTest()
    local now = GetTime()
    for i, t in ipairs(TEST_ENEMIES) do
        local e = { name = t[1], class = t[2], race = t[3], lastSeen = now, cds = {} }
        for _, u in ipairs(t[4]) do e.cds[u[1]] = { start = now - u[2], duration = GetDuration(u[1]) } end
        enemies["test-" .. i] = e
    end
    StartTicker()
    Print("Test bars shown (they expire on their own).")
end

-- numeric settings: command = { db key, min, max }
local NUMBERS = {
    scale = { "scale", 0.5, 3 }, size = { "iconSize", 16, 64 },
    rows = { "maxRows", 1, 20 }, icons = { "maxIcons", 1, 30 },
}

local function Help()
    Print("commands:")
    Print("/gcd lock | unlock - toggle moving the bar")
    Print("/gcd test - show sample bars")
    Print("/gcd scale <0.5-3>, /gcd size <16-64>, /gcd rows <1-20>, /gcd icons <1-30>")
    Print("/gcd unused arena | always | never - pre-fill baseline cooldowns as ready (now " .. db.showUnused .. ")")
    Print("/gcd talents - assume common talent reductions (now " .. tostring(db.useTalents) .. ")")
    Print("/gcd trinket <sec> - PvP trinket cooldown (120 Medallion / 300 Insignia)")
    Print("/gcd set <spellID> <sec> | /gcd clear <spellID> - override one cooldown")
end

SLASH_GSDCD1 = "/gcd"
SlashCmdList.GSDCD = function(msg)
    local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
    local n, num = tonumber(a), NUMBERS[cmd]
    local base = n and baseOf[n]
    if num and n then
        n = math.min(num[3], math.max(num[2], n))
        db[num[1]] = cmd == "scale" and n or math.floor(n)
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = cmd == "lock"
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "unused" and (a == "arena" or a == "always" or a == "never") then
        db.showUnused = a
    elseif cmd == "talents" then
        db.useTalents = not db.useTalents
        Print("Talent reductions: " .. tostring(db.useTalents))
    elseif cmd == "trinket" and n then
        db.overrides[42292] = n
        Print("PvP trinket cooldown: " .. n .. "s")
    elseif cmd == "set" and base and tonumber(b) then
        db.overrides[base] = tonumber(b)
        Print((GetSpellInfo(base) or n) .. " cooldown: " .. b .. "s")
    elseif cmd == "clear" and base then
        db.overrides[base] = nil
        Print((GetSpellInfo(base) or n) .. " cooldown reset to default")
    else
        Help()
        return
    end
    ApplyLayout()
    Render()
end
