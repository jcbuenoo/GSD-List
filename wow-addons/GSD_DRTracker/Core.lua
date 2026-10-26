local addonName, ns = ...

local GetTime, UnitGUID, bit_band = GetTime, UnitGUID, bit.band
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400

local GetSpellInfo = GetSpellInfo or function(id)
    local info = C_Spell and C_Spell.GetSpellInfo(id)
    if info then return info.name, nil, info.iconID end
end
local GetSpellTexture = GetSpellTexture or (C_Spell and C_Spell.GetSpellTexture)

-- Seconds a CC is assumed to last if we never see it fade (target out of combat log range).
local FAILSAFE_ACTIVE = 60
local MAX_LEVEL = 3
local MIN_LABEL_SIZE = 24 -- below this icon size the labels and the reset timer don't fit and are hidden

local DEFAULTS = {
    point = { "CENTER", "UIParent", "CENTER", 0, -150 },
    locked = false,
    scale = 1,
    iconSize = 30,
    maxRows = 8,
    resetTime = ns.RESET_TIME,
    showSelf = false,
    showLabels = true,
    categories = {}, -- [key] = false to hide
}

-- Next-application colour: 50% (yellow), 25% (orange), immune (red)
local LEVEL_COLORS = {
    [1] = { 1.0, 0.85, 0.0 },
    [2] = { 1.0, 0.45, 0.0 },
    [3] = { 0.9, 0.1, 0.1 },
}
local LEVEL_TEXT = { "50%", "25%", "IMM" }

local db
local units = {}       -- [guid] = { name, class, cats = { [cat] = state } }
local nameToCat = {}   -- fallback when the combat log gives spellID 0
local catOrder = {}    -- [key] = display index
local catInfo = {}     -- [key] = category entry
local playerGUID

for i, c in ipairs(ns.CATEGORIES) do
    catOrder[c.key] = i
    catInfo[c.key] = c
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GSD DR:|r " .. msg)
end

local function IsCategoryEnabled(cat)
    return db.categories[cat] ~= false
end

local function ShortName(name)
    return name and name:match("^[^-]+") or "?"
end

local function GetUnitEntry(guid, name)
    local u = units[guid]
    if not u then
        u = { name = ShortName(name), cats = {} }
        units[guid] = u
    end
    if not u.class and GetPlayerInfoByGUID then
        local _, class = GetPlayerInfoByGUID(guid)
        u.class = class
    end
    return u
end

-------------------------------------------------------------------------------
-- DR state
-------------------------------------------------------------------------------

local function ApplyDR(guid, name, spellID, cat)
    local now = GetTime()
    local u = GetUnitEntry(guid, name)
    local e = u.cats[cat]
    -- A CC can't land on an immune target, so landing at MAX_LEVEL means the real
    -- (15-20s) reset already happened: start over instead of staying on "IMM".
    if e and e.level < MAX_LEVEL and (e.active or now < e.resetAt) then
        e.level = e.level + 1
    else
        e = { level = 1, auras = {} }
        u.cats[cat] = e
    end
    e.active = true
    e.auras[spellID] = true
    e.spellID = spellID
    e.appliedAt = now
    e.resetAt = now + FAILSAFE_ACTIVE + db.resetTime
    u.lastUpdate = now
end

local function RemoveDR(guid, spellID, cat)
    local u = units[guid]
    local e = u and u.cats[cat]
    if not e then return end
    e.auras[spellID] = nil
    if next(e.auras) then return end -- another aura of this category is still up
    local now = GetTime()
    e.active = false
    e.resetAt = now + db.resetTime
    u.lastUpdate = now
end

local function Prune(now)
    for guid, u in pairs(units) do
        for cat, e in pairs(u.cats) do
            if not e.active and now >= e.resetAt then
                u.cats[cat] = nil
            elseif e.active and now >= e.resetAt - db.resetTime then
                -- never saw the aura fade; start the reset timer from the failsafe
                e.active = false
                wipe(e.auras)
            end
        end
        if not next(u.cats) then
            units[guid] = nil
        end
    end
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "GSD_DRTrackerAnchor", UIParent, "BackdropTemplate")
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
anchor:SetBackdropColor(0, 0.6, 0.3, 0.6)
anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.text:SetPoint("CENTER")
anchor.text:SetText("GSD DR Tracker (drag)")

local rows = {}

-- Font strings must have a font before SetText, so this runs at creation and on resize.
local function SetIconFonts(icon, size)
    local fontSize = math.max(8, math.floor(size * 0.36))
    icon.level:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    icon.timer:SetFont(STANDARD_TEXT_FONT, fontSize + 1, "OUTLINE")
    icon.label:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
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
    icon.cd:SetReverse(true)
    if icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(true) end
    icon.cd.noCooldownCount = true -- keep OmniCC off our icons; we draw our own timer
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cd:GetFrameLevel() + 2)
    icon.level = overlay:CreateFontString(nil, "OVERLAY")
    icon.level:SetPoint("TOP", 0, -1)
    icon.timer = overlay:CreateFontString(nil, "OVERLAY")
    icon.timer:SetPoint("BOTTOM", 0, 1)
    icon.label = overlay:CreateFontString(nil, "OVERLAY")
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    SetIconFonts(icon, db.iconSize)
    return icon
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, anchor)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("RIGHT")
    row.icons = {}
    rows[i] = row
    return row
end

local function LabelsShown()
    return db.showLabels and db.iconSize >= MIN_LABEL_SIZE
end

local function LayoutRow(row, i)
    local size = db.iconSize
    local labels = LabelsShown()
    local rowHeight = labels and size + 12 or size + 2 -- room for the category label under the icon
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 94, -4 - (i - 1) * (rowHeight + 2))
    row:SetSize((size + 3) * #ns.CATEGORIES, rowHeight)
    row.name:ClearAllPoints()
    row.name:SetPoint("RIGHT", row, "TOPLEFT", -4, -size / 2)
    row.name:SetWidth(90)
    for j, icon in ipairs(row.icons) do
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", (j - 1) * (size + 3), 0)
        SetIconFonts(icon, size)
        if labels then icon.label:Show() else icon.label:Hide() end
        -- small icons only have room for one line: keep the DR level, the sweep shows the time
        icon.level:ClearAllPoints()
        if size >= MIN_LABEL_SIZE then
            icon.level:SetPoint("TOP", 0, -1)
            icon.timer:Show()
        else
            icon.level:SetPoint("CENTER", 0, 0)
            icon.timer:Hide()
        end
    end
end

local function UpdateIcon(icon, cat, e, now)
    if icon.spellID ~= e.spellID then
        icon.tex:SetTexture((GetSpellTexture and GetSpellTexture(e.spellID)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon.spellID = e.spellID
    end
    if icon.shownLevel ~= e.level then
        local c = LEVEL_COLORS[e.level]
        icon.border:SetVertexColor(c[1], c[2], c[3])
        icon.level:SetTextColor(c[1], c[2], c[3])
        SetText(icon.level, LEVEL_TEXT[e.level])
        icon.shownLevel = e.level
    end
    SetText(icon.label, catInfo[cat].label)
    if e.active then
        -- CC is still on the target: the reset timer hasn't started yet
        SetText(icon.timer, "")
        if icon.cdStart then
            icon.tex:SetDesaturated(false)
            icon.cd:SetCooldown(0, 0)
            icon.cdStart = nil
        end
    else
        SetText(icon.timer, tostring(math.ceil(e.resetAt - now)))
        local start = e.resetAt - db.resetTime
        if icon.cdStart ~= start then
            icon.tex:SetDesaturated(true)
            icon.cd:SetCooldown(start, db.resetTime)
            icon.cdStart = start
        end
    end
    icon:Show()
end

local sortList, sortPool = {}, {}
local function SortUnits(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return (a.u.lastUpdate or 0) > (b.u.lastUpdate or 0)
end

local catList = {}
local function SortCats(a, b) return catOrder[a] < catOrder[b] end

local function Render()
    local now = GetTime()
    Prune(now)

    wipe(sortList)
    local targetGUID, focusGUID = UnitGUID("target"), UnitGUID("focus")
    for guid, u in pairs(units) do
        local n = #sortList + 1
        local item = sortPool[n] or {}
        sortPool[n] = item
        item.guid, item.u = guid, u
        item.priority = (guid == targetGUID and 1) or (guid == focusGUID and 2) or 3
        sortList[n] = item
    end
    table.sort(sortList, SortUnits)

    local shown = 0
    for _, item in ipairs(sortList) do
        if shown >= db.maxRows then break end
        local u = item.u
        wipe(catList)
        for cat in pairs(u.cats) do
            if IsCategoryEnabled(cat) then catList[#catList + 1] = cat end
        end
        if #catList > 0 then
            shown = shown + 1
            table.sort(catList, SortCats)
            local row = GetRow(shown)
            for j = #row.icons + 1, #catList do
                row.icons[j] = CreateIcon(row)
                row.needsLayout = true
            end
            if row.needsLayout or row.layoutSize ~= db.iconSize then
                LayoutRow(row, shown)
                row.needsLayout, row.layoutSize = nil, db.iconSize
            end
            SetText(row.name, item.guid == targetGUID and ("> " .. u.name) or u.name)
            if row.shownClass ~= u.class then
                local cc = u.class and RAID_CLASS_COLORS[u.class]
                if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(1, 1, 1) end
                row.shownClass = u.class
            end
            for j, cat in ipairs(catList) do
                UpdateIcon(row.icons[j], cat, u.cats[cat], now)
            end
            for j = #catList + 1, #row.icons do row.icons[j]:Hide() end
            row:Show()
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
end

local function ApplyLayout()
    anchor:ClearAllPoints()
    local p = db.point
    anchor:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    anchor:SetScale(db.scale)
    for i, row in ipairs(rows) do LayoutRow(row, i) end
    if db.locked then
        anchor:EnableMouse(false)
        anchor:SetBackdropColor(0, 0, 0, 0)
        anchor.text:Hide()
    else
        anchor:EnableMouse(true)
        anchor:SetBackdropColor(0, 0.6, 0.3, 0.6)
        anchor.text:Show()
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function IsTrackedDest(guid, flags)
    if guid == playerGUID then return db.showSelf end
    return bit_band(flags, HOSTILE) ~= 0 and bit_band(flags, PLAYER) ~= 0
end

local function OnCombatLog()
    local _, event, _, _, _, _, _, destGUID, destName, destFlags, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    if event == "UNIT_DIED" then
        -- Feign Death is logged as UNIT_DIED; keep hunters' DRs
        local u = units[destGUID]
        if u and u.class ~= "HUNTER" then units[destGUID] = nil end
        return
    end
    if event ~= "SPELL_AURA_APPLIED" and event ~= "SPELL_AURA_REFRESH" and event ~= "SPELL_AURA_REMOVED" then return end
    local cat = ns.SPELLS[spellID] or (spellID == 0 and nameToCat[spellName])
    if not cat or not IsTrackedDest(destGUID, destFlags) then return end
    if destGUID == playerGUID then destName = "You" end
    if event == "SPELL_AURA_REMOVED" then
        RemoveDR(destGUID, spellID, cat)
    else
        ApplyDR(destGUID, destName, spellID, cat)
    end
end

local ticker
local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, function()
        Render()
        if not next(units) then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
        if next(units) then StartTicker() end
    elseif event == "ADDON_LOADED" and arg1 == addonName then
        GSD_DRTrackerDB = GSD_DRTrackerDB or {}
        db = GSD_DRTrackerDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
        end
        for id, cat in pairs(ns.SPELLS) do
            local name = GetSpellInfo(id)
            if name then nameToCat[name] = cat end
        end
        ApplyLayout()
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(units) -- new zone / arena: old DRs are meaningless
        Render()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if next(units) then Render() end
    end
end)

-------------------------------------------------------------------------------
-- Test mode & slash commands
-------------------------------------------------------------------------------

local function RunTest()
    local now = GetTime()
    local function fake(guid, name, class, list)
        local u = { name = name, class = class, cats = {}, lastUpdate = now }
        for _, d in ipairs(list) do
            u.cats[d[1]] = {
                level = d[3], spellID = d[2], auras = {}, appliedAt = now,
                active = d[4] or false,
                resetAt = d[4] and (now + 8 + db.resetTime) or (now + d[5]),
            }
        end
        units[guid] = u
    end
    fake("test-1", "Healbot", "PRIEST", {
        { "incapacitate", 11297, 1, false, 18 },  -- Sapped, 50% next
        { "stun", 1833, 2, false, 12 },           -- Cheap Shot + HoJ, 25% next
        { "kidney_shot", 8643, 1, true },         -- Kidney currently on target
    })
    fake("test-2", "Facemelter", "MAGE", {
        { "stun", 1833, 3, false, 7 },            -- immune to stuns
        { "disorient", 2094, 1, false, 15 },      -- Blinded
    })
    fake("test-3", "Bubblegum", "PALADIN", {
        { "fear", 5246, 1, false, 19 },
        { "root", 27088, 2, false, 10 },
    })
    StartTicker()
    Print("Test bars shown (they expire on their own).")
end

local function Help()
    Print("commands:")
    Print("/gdr lock | unlock - toggle moving the bar")
    Print("/gdr test - show sample bars")
    Print("/gdr scale <0.5-3>, /gdr size <16-64>, /gdr rows <1-20>")
    Print("/gdr reset <15-20> - DR reset time in seconds (now " .. db.resetTime .. ")")
    Print("/gdr self - also track DRs on yourself (now " .. tostring(db.showSelf) .. ")")
    Print("/gdr labels - category names under icons (now " .. tostring(db.showLabels) .. ", hidden below size " .. MIN_LABEL_SIZE .. ")")
    Print("/gdr preset all | rogue - rogue = Stun, Kidney, Incap (Sap), Blind/Cyclone only")
    Print("/gdr cats - list categories,  /gdr cat <key> - toggle one")
end

SLASH_GSDDR1 = "/gdr"
SlashCmdList.GSDDR = function(msg)
    local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(arg)
    if cmd == "lock" then
        db.locked = true
    elseif cmd == "unlock" then
        db.locked = false
    elseif cmd == "test" then
        RunTest()
    elseif cmd == "scale" and n then
        db.scale = math.min(3, math.max(0.5, n))
    elseif cmd == "size" and n then
        db.iconSize = math.min(64, math.max(16, math.floor(n)))
    elseif cmd == "rows" and n then
        db.maxRows = math.min(20, math.max(1, math.floor(n)))
    elseif cmd == "reset" and n then
        db.resetTime = math.min(20, math.max(15, n))
    elseif cmd == "self" then
        db.showSelf = not db.showSelf
        Print("Track yourself: " .. tostring(db.showSelf))
    elseif cmd == "labels" then
        db.showLabels = not db.showLabels
        Print("Labels: " .. tostring(db.showLabels))
    elseif cmd == "preset" and (arg == "all" or arg == "rogue") then
        for _, c in ipairs(ns.CATEGORIES) do
            db.categories[c.key] = (arg == "all" or ns.ROGUE_PRESET[c.key]) and true or false
        end
        Print("Preset: " .. arg)
    elseif cmd == "cats" then
        for _, c in ipairs(ns.CATEGORIES) do
            local on = IsCategoryEnabled(c.key) and "|cff00ff00on|r" or "|cffff0000off|r"
            Print(string.format("%s [%s] %s - %s", on, c.key, c.label, c.desc))
        end
    elseif cmd == "cat" and catInfo[arg] then
        db.categories[arg] = not IsCategoryEnabled(arg)
        Print(arg .. ": " .. (IsCategoryEnabled(arg) and "on" or "off"))
    else
        Help()
        return
    end
    ApplyLayout()
    Render()
end
