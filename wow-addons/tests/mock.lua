-- Minimal WoW API mock for headless testing
NOW = 1000
function GetTime() return NOW end
bit = { band = function(a, b)
    local r, m = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
end }
COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_TYPE_PET = 0x1000
STANDARD_TEXT_FONT = "font"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
UNITS = {}
function UnitGUID(u) return UNITS[u] and UNITS[u].guid end
function UnitName(u) return UNITS[u] and UNITS[u].name end
function UnitIsPlayer(u) return UNITS[u] and UNITS[u].player end
function UnitCanAttack(_, u) return UNITS[u] and UNITS[u].enemy end
function UnitClass(u) return UNITS[u].class, UNITS[u].class end
function UnitRace(u) return UNITS[u].race, UNITS[u].race end
function IsInInstance() return INSTANCE ~= nil, INSTANCE or "none" end
PLAYERINFO = {}
function GetPlayerInfoByGUID(g) local p = PLAYERINFO[g]; if p then return p[1], p[1], p[2], p[2] end end
function GetSpellInfo(id) return "Spell" .. id, nil, id end
function GetSpellTexture(id) return id end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local r = {} for k, v in pairs(t) do r[k] = type(v) == "table" and CopyTable(v) or v end return r end
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT + 1] = m end }
SlashCmdList = {}
TICKERS = {}
C_Timer = { NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.cancelled = true end }; TICKERS[#TICKERS + 1] = t; return t end }
function RunTickers() for _, t in ipairs(TICKERS) do if not t.cancelled then t.fn() end end end

local function newObj(kind, parent)
    local o = { kind = kind, parent = parent, children = {}, shown = true, scripts = {}, events = {} }
    if parent then table.insert(parent.children, o) end
    local methods = {
        CreateTexture = function(self) return newObj("Texture", self) end,
        CreateFontString = function(self) return newObj("FontString", self) end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetScript = function(self, k, f) self.scripts[k] = f end,
        RegisterEvent = function(self, e) self.events[e] = true end,
        SetVertexColor = function(self, r, g, b) self.color = { r, g, b } end,
        SetTexture = function(self, t) self.texture = t end,
        SetDesaturated = function(self, d) self.desat = d end,
        SetCooldown = function(self, s, d) self.cdStart, self.cdDur = s, d end,
        GetFrameLevel = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    }
    return setmetatable(o, { __index = function(_, k) return methods[k] or function() end end })
end
UIParent = newObj("Frame")
FRAMES = {}
function CreateFrame(kind, name, parent)
    local f = newObj(kind, parent)
    FRAMES[#FRAMES + 1] = f
    if name then _G[name] = f end
    return f
end
function Fire(event, ...) for _, f in ipairs(FRAMES) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end end
CLEU = {}
function CombatLogGetCurrentEventInfo() return unpack(CLEU, 1, 13) end
function Log(event, srcGUID, srcName, srcFlags, destGUID, destName, destFlags, spellID)
    CLEU = { NOW, event, false, srcGUID, srcName, srcFlags, 0, destGUID, destName, destFlags, 0, spellID, "Spell" .. tostring(spellID) }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end
function LoadAddon(name, files, dir)
    local ns = {}
    for _, f in ipairs(files) do assert(loadfile(dir .. "/" .. f))(name, ns) end
    Fire("ADDON_LOADED", name)
    return ns
end
-- Collect visible rows under an anchor: { {name=, icons={ {tex, top, timer, label, color, desat} } } }
function Rows(anchor)
    local out = {}
    for _, row in ipairs(anchor.children) do
        if row.kind == "Frame" and row.shown and row.icons then
            local r = { name = row.name.text, icons = {} }
            for _, ic in ipairs(row.icons) do
                if ic.shown then
                    r.icons[#r.icons + 1] = { tex = ic.tex.texture, level = rawget(ic, "level") and ic.level.text, timer = ic.timer.text, label = rawget(ic, "label") and ic.label.text, color = ic.border.color, desat = ic.tex.desat }
                end
            end
            out[#out + 1] = r
        end
    end
    return out
end
