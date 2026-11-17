-- Paladin Tracker: seal countdown bar + blessing timer icons (TBC Classic)
local ADDON = ...

local defaults = {
    locked = false,
    ownOnly = false,        -- only show blessings cast by you
    seal  = { point = "CENTER", x = 0,    y = -150, scale = 1 },
    bless = { point = "CENTER", x = 0,    y = -190, scale = 1 },
}

local BAR_W, BAR_H = 200, 20
local ICON_SIZE, ICON_GAP = 30, 3

-- Spell IDs (base ranks) are only used to resolve localized spell names.
local SEAL_IDS = { 21084, 21082, 20375, 20164, 20165, 20166, 31892, 31801, 348700 }
local BLESS_IDS = {
    19740, 19742, 20217, 1038, 19977, 20911, 1044, 1022, 6940,          -- single
    25782, 25894, 25898, 25895, 25890, 25899,                           -- greater
}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local sealNames, blessNames = {}, {}
local function BuildNames()
    for _, id in ipairs(SEAL_IDS) do local n = SpellName(id); if n then sealNames[n] = true end end
    for _, id in ipairs(BLESS_IDS) do local n = SpellName(id); if n then blessNames[n] = true end end
end
local function IsSeal(name)  return sealNames[name]  or name:find("^Seal of") end
local function IsBless(name) return blessNames[name] or name:find("^Blessing of") or name:find("^Greater Blessing of") end

-- Returns name, icon, duration, expirationTime, source (or nil) for buff index i.
local function GetBuff(i)
    if UnitBuff then
        local name, icon, _, _, duration, expires, source = UnitBuff("player", i)
        return name, icon, duration, expires, source
    end
    local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    if a then return a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit end
end

local DB

---------------------------------------------------------------------------
-- Movable container helper
---------------------------------------------------------------------------
local function MakeMovable(f, key, label)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        DB[key].point, DB[key].x, DB[key].y = p, x, y
    end)
    f.handle = f:CreateTexture(nil, "BACKGROUND")
    f.handle:SetAllPoints()
    f.handle:SetColorTexture(0, 1, 0, 0.25)
    f.handle:Hide()
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.label:SetText(label .. " (drag)")
    f.label:Hide()
end

---------------------------------------------------------------------------
-- Seal bar
---------------------------------------------------------------------------
local sealFrame = CreateFrame("Frame", "PaladinTrackerSeal", UIParent)
sealFrame:SetSize(BAR_W + BAR_H + 2, BAR_H)
MakeMovable(sealFrame, "seal", "Seal")

local sealIcon = sealFrame:CreateTexture(nil, "ARTWORK")
sealIcon:SetSize(BAR_H, BAR_H)
sealIcon:SetPoint("LEFT")
sealIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local bar = CreateFrame("StatusBar", nil, sealFrame)
bar:SetPoint("LEFT", sealIcon, "RIGHT", 2, 0)
bar:SetSize(BAR_W, BAR_H)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetMinMaxValues(0, 1)
bar:SetStatusBarColor(1, 0.8, 0.1)
local barBG = bar:CreateTexture(nil, "BACKGROUND")
barBG:SetAllPoints()
barBG:SetColorTexture(0, 0, 0, 0.6)

local sealText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sealText:SetPoint("LEFT", 4, 0)
local sealTime = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sealTime:SetPoint("RIGHT", -4, 0)

local sealData = { active = false }

local function UpdateSealBar()
    if sealData.preview then
        local t = GetTime() % 30
        sealData.name, sealData.icon = SpellName(21084) or "Seal of Righteousness", 135960
        sealData.duration, sealData.expires = 30, GetTime() + (30 - t)
    end
    if not sealData.name then return end
    sealIcon:SetTexture(sealData.icon)
    sealText:SetText(sealData.name)
    if sealData.duration and sealData.duration > 0 then
        local left = sealData.expires - GetTime()
        if left < 0 then left = 0 end
        bar:SetValue(left / sealData.duration)
        sealTime:SetFormattedText("%.1f", left)
        if left <= 5 then bar:SetStatusBarColor(1, 0.2, 0.1) else bar:SetStatusBarColor(1, 0.8, 0.1) end
    else
        bar:SetValue(1)
        sealTime:SetText("")
    end
end

sealFrame:SetScript("OnUpdate", function() if sealFrame:IsShown() then UpdateSealBar() end end)

---------------------------------------------------------------------------
-- Blessing icons
---------------------------------------------------------------------------
local blessFrame = CreateFrame("Frame", "PaladinTrackerBlessings", UIParent)
blessFrame:SetSize(ICON_SIZE * 4 + ICON_GAP * 3, ICON_SIZE)
MakeMovable(blessFrame, "bless", "Blessings")

local icons = {}
local function GetIcon(n)
    if icons[n] then return icons[n] end
    local b = CreateFrame("Frame", nil, blessFrame)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetHideCountdownNumbers(true)
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    b.text = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    icons[n] = b
    return b
end

local blessList = {}  -- {icon=, duration=, expires=}

local function FormatTime(s)
    if s >= 3600 then return string.format("%dh", math.ceil(s / 3600)) end
    if s >= 60 then return string.format("%dm", math.ceil(s / 60)) end
    return string.format("%d", math.ceil(s))
end

local function UpdateBlessTimes()
    local now = GetTime()
    for i, b in ipairs(blessList) do
        local f = icons[i]
        if b.preview and b.expires < now then b.expires = now + 300 end
        if b.duration and b.duration > 0 then
            local left = b.expires - now
            if left < 0 then left = 0 end
            f.text:SetText(FormatTime(left))
            if left <= 30 then f.text:SetTextColor(1, 0.2, 0.1) else f.text:SetTextColor(1, 1, 1) end
        else
            f.text:SetText("")
        end
    end
end
blessFrame:SetScript("OnUpdate", function() if blessFrame:IsShown() then UpdateBlessTimes() end end)

local function LayoutBlessings()
    local list = blessList
    if #list == 0 and not DB.locked then
        -- unlocked preview
        local now = GetTime()
        list = {
            { icon = 135906, duration = 300, expires = now + 187, preview = true },
            { icon = 135995, duration = 300, expires = now + 25, preview = true },
        }
        blessList = list
    end
    for i, b in ipairs(list) do
        local f = GetIcon(i)
        f:ClearAllPoints()
        f:SetPoint("LEFT", blessFrame, "LEFT", (i - 1) * (ICON_SIZE + ICON_GAP), 0)
        f.tex:SetTexture(b.icon)
        if b.duration and b.duration > 0 then
            f.cd:SetCooldown(b.expires - b.duration, b.duration)
        else
            f.cd:Clear()
        end
        f:Show()
    end
    for i = #list + 1, #icons do icons[i]:Hide() end
    blessFrame:SetWidth(math.max(#list, 1) * (ICON_SIZE + ICON_GAP) - ICON_GAP)
    UpdateBlessTimes()
end

---------------------------------------------------------------------------
-- Aura scan
---------------------------------------------------------------------------
local function Scan()
    if not DB then return end
    sealData.active, sealData.name = false, nil
    sealData.preview = false
    wipe(blessList)
    for i = 1, 40 do
        local name, icon, duration, expires, source = GetBuff(i)
        if not name then break end
        if IsSeal(name) then
            sealData.active = true
            sealData.name, sealData.icon = name, icon
            sealData.duration, sealData.expires = duration, expires
        elseif IsBless(name) and (not DB.ownOnly or source == "player") then
            blessList[#blessList + 1] = { icon = icon, duration = duration, expires = expires }
        end
    end
    if not sealData.active and not DB.locked then sealData.preview = true end
    sealFrame:SetShown(sealData.active or sealData.preview)
    blessFrame:SetShown(#blessList > 0 or not DB.locked)
    LayoutBlessings()
end

---------------------------------------------------------------------------
-- Lock / unlock + positions
---------------------------------------------------------------------------
local function ApplyPositions()
    for _, e in ipairs({ { sealFrame, "seal" }, { blessFrame, "bless" } }) do
        local f, k = e[1], e[2]
        f:SetScale(DB[k].scale or 1)
        f:ClearAllPoints()
        f:SetPoint(DB[k].point, UIParent, DB[k].point, DB[k].x, DB[k].y)
    end
end

local function ApplyLock()
    for _, f in ipairs({ sealFrame, blessFrame }) do
        f:EnableMouse(not DB.locked)
        f.handle:SetShown(not DB.locked)
        f.label:SetShown(not DB.locked)
    end
    Scan()
end

---------------------------------------------------------------------------
-- Events & slash commands
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        PaladinTrackerDB = PaladinTrackerDB or {}
        DB = PaladinTrackerDB
        for k, v in pairs(defaults) do
            if DB[k] == nil then
                if type(v) == "table" then DB[k] = CopyTable(v) else DB[k] = v end
            end
        end
        BuildNames()
        ApplyPositions()
        ApplyLock()
    elseif DB then
        Scan()
    end
end)

local function Say(msg) print("|cffF58CBAPaladinTracker:|r " .. msg) end

SLASH_PALADINTRACKER1 = "/pt"
SLASH_PALADINTRACKER2 = "/paladintracker"
SlashCmdList.PALADINTRACKER = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "lock" then
        DB.locked = true; ApplyLock(); Say("locked.")
    elseif cmd == "unlock" then
        DB.locked = false; ApplyLock(); Say("unlocked - drag the green boxes.")
    elseif cmd == "toggle" then
        DB.locked = not DB.locked; ApplyLock(); Say(DB.locked and "locked." or "unlocked.")
    elseif cmd == "own" then
        DB.ownOnly = not DB.ownOnly; Scan()
        Say("own blessings only: " .. (DB.ownOnly and "ON" or "OFF"))
    elseif cmd == "scale" then
        local which, val = arg:match("^(%a+)%s+([%d%.]+)$")
        val = tonumber(val)
        if (which == "seal" or which == "bless") and val and val >= 0.5 and val <= 3 then
            DB[which].scale = val; ApplyPositions()
        else
            Say("usage: /pt scale seal|bless 0.5-3")
        end
    elseif cmd == "reset" then
        DB.seal  = CopyTable(defaults.seal)
        DB.bless = CopyTable(defaults.bless)
        ApplyPositions(); Say("positions reset.")
    else
        Say("/pt lock | unlock | toggle | own | scale seal|bless <n> | reset")
    end
end
