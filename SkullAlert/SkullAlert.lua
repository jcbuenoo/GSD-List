-- SkullAlert: raid warning whenever a level ?? (skull) enemy-faction player is near you.
-- Inspired by Spy: watches every unit token the client exposes (target, mouseover,
-- focus, nameplates, group members' targets) plus the combat log for players that
-- were already identified as skulls.

local ADDON_NAME = ...

local SKULL_ICON = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
local SCAN_INTERVAL = 0.5
local BROADCAST_GAP = 3 -- minimum seconds between group chat messages, avoids chat throttling

local defaults = {
    enabled = true,
    localWarning = true, -- on-screen raid warning only you can see
    broadcast = false,   -- also announce to your group (/rw if raid lead/assist, else /raid or /party)
    sound = true,
    chat = true,         -- print a line in your chat frame
    cooldown = 60,       -- seconds before the same player can trigger another alert
    combatLog = true,    -- re-alert on known skulls seen only in the combat log
}

local db
local playerFaction
local known = {}        -- [guid] = { name, class, classFile, race, guild, lastAlert }
local lastBroadcast = 0

local frame = CreateFrame("Frame")

-- Unit tokens to scan every tick.
local scanUnits = { "target", "focus", "mouseover", "targettarget", "pettarget" }
for i = 1, 40 do scanUnits[#scanUnits + 1] = "nameplate" .. i end
for i = 1, 4 do scanUnits[#scanUnits + 1] = "party" .. i .. "target" end
for i = 1, 40 do scanUnits[#scanUnits + 1] = "raid" .. i .. "target" end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020SkullAlert|r: " .. msg)
end

local function ClassColored(text, classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return text end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), text)
end

local function CurrentLocation()
    local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end

local function Broadcast(text)
    local now = GetTime()
    if now - lastBroadcast < BROADCAST_GAP then return end
    local channel
    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            channel = "RAID_WARNING"
        else
            channel = "RAID"
        end
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if channel then
        lastBroadcast = now
        SendChatMessage(text, channel)
    end
end

local function Alert(info, source)
    local now = GetTime()
    if info.lastAlert and now - info.lastAlert < db.cooldown then return end
    info.lastAlert = now

    local desc = (info.race and info.class) and (info.race .. " " .. info.class) or "player"
    local guild = info.guild and (" <" .. info.guild .. ">") or ""

    if db.localWarning then
        local text = string.format("%s SKULL %s: %s (%s)%s %s", SKULL_ICON, playerFaction == "Horde" and "ALLIANCE" or "HORDE",
            ClassColored(info.name, info.classFile), desc, guild, SKULL_ICON)
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if db.sound then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if db.chat then
        Print(string.format("Level ?? %s%s %s detected via %s near %s.",
            ClassColored(info.name, info.classFile), guild, desc, source, CurrentLocation()))
    end
    if db.broadcast then
        Broadcast(string.format("{skull} Level ?? %s %s%s near %s {skull}", desc, info.name, guild, CurrentLocation()))
    end
end

local function ScanUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local faction = UnitFactionGroup(unit)
    if not faction or faction == playerFaction or faction == "Neutral" then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    -- UnitLevel returns -1 when the level is hidden (shown as ?? / skull).
    if UnitLevel(unit) ~= -1 then
        known[guid] = nil
        return
    end

    local info = known[guid]
    if not info then
        local class, classFile = UnitClass(unit)
        local name, realm = UnitName(unit)
        if realm and realm ~= "" then name = name .. "-" .. realm end
        info = {
            name = name or UNKNOWN,
            class = class,
            classFile = classFile,
            race = UnitRace(unit),
            guild = GetGuildInfo(unit),
        }
        known[guid] = info
    end
    Alert(info, (unit:gsub("%d+", "")))
end

local function ScanAll()
    if not db.enabled then return end
    for i = 1, #scanUnits do
        ScanUnit(scanUnits[i])
    end
end

local function OnCombatLog()
    local _, _, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags = CombatLogGetCurrentEventInfo()
    local hostilePlayer = bit.bor(COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_REACTION_HOSTILE)
    if srcGUID and known[srcGUID] and bit.band(srcFlags, hostilePlayer) == hostilePlayer then
        Alert(known[srcGUID], "combat log")
    end
    if dstGUID and known[dstGUID] and bit.band(dstFlags, hostilePlayer) == hostilePlayer then
        Alert(known[dstGUID], "combat log")
    end
end

local function UpdateCombatLogRegistration()
    if db.enabled and db.combatLog then
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function OnOff(value)
    return value and "|cff20ff20on|r" or "|cffff2020off|r"
end

local function PrintStatus()
    Print(string.format("enabled %s, warning %s, sound %s, chat %s, broadcast %s, combatlog %s, cooldown %ds",
        OnOff(db.enabled), OnOff(db.localWarning), OnOff(db.sound), OnOff(db.chat),
        OnOff(db.broadcast), OnOff(db.combatLog), db.cooldown))
end

local toggles = {
    warning = "localWarning",
    sound = "sound",
    chat = "chat",
    broadcast = "broadcast",
    combatlog = "combatLog",
}

local function SlashHandler(input)
    local cmd, arg = strsplit(" ", strlower(strtrim(input or "")), 2)
    if cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        UpdateCombatLogRegistration()
        Print("alerts " .. OnOff(db.enabled))
    elseif toggles[cmd] then
        local key = toggles[cmd]
        if arg == "on" then db[key] = true
        elseif arg == "off" then db[key] = false
        else db[key] = not db[key] end
        UpdateCombatLogRegistration()
        Print(cmd .. " " .. OnOff(db[key]))
    elseif cmd == "cd" or cmd == "cooldown" then
        local n = tonumber(arg)
        if n and n >= 0 then
            db.cooldown = n
            Print("cooldown set to " .. n .. "s")
        else
            Print("usage: /skull cd <seconds>")
        end
    elseif cmd == "test" then
        Alert({ name = "Testplayer", class = "Rogue", classFile = "ROGUE", race = playerFaction == "Horde" and "Night Elf" or "Undead",
            guild = "Test Guild" }, "test")
    elseif cmd == "reset" then
        wipe(known)
        Print("forgot all detected players.")
    elseif cmd == "status" then
        PrintStatus()
    else
        Print("commands:")
        Print("/skull on | off - enable or disable alerts")
        Print("/skull warning | sound | chat | broadcast | combatlog [on|off] - toggle outputs")
        Print("/skull cd <seconds> - per-player alert cooldown")
        Print("/skull test - fire a test alert")
        Print("/skull reset - forget detected players")
        Print("/skull status - show settings")
    end
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        SkullAlertDB = SkullAlertDB or {}
        db = SkullAlertDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        SLASH_SKULLALERT1 = "/skull"
        SLASH_SKULLALERT2 = "/skullalert"
        SlashCmdList.SKULLALERT = SlashHandler
    elseif event == "PLAYER_LOGIN" then
        playerFaction = UnitFactionGroup("player")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("PLAYER_FOCUS_CHANGED")
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        UpdateCombatLogRegistration()
        C_Timer.NewTicker(SCAN_INTERVAL, ScanAll)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "PLAYER_LEVEL_UP" then
        -- ?? is relative to your own level; re-evaluate everyone after dinging.
        wipe(known)
    elseif not db.enabled then
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        ScanUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        ScanUnit("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ScanUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ScanUnit(arg1)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
