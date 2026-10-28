-- World map overlay: shaded aggro zones, rings and hoverable mark pins on the open map.
local ADDON, ns = ...
local GAW = ns.GAW

local abs, date, format = math.abs, date, string.format

local WorldMap = {}
ns.WorldMap = WorldMap

local overlay, fills, rings
local pins, pinsUsed = {}, 0

local function PinOnEnter(self)
    local p = self.point
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.KIND_LABEL[p.kind])
    if p.name then GameTooltip:AddLine(p.name, 1, 1, 1) end
    if p.kind == "guard" then
        GameTooltip:AddLine(format("Aggro radius: %.0f yd%s", GAW:GuardRadius(p),
            p.r and " (fixed)" or (p.learned and " (learned)" or "")), 1, 1, 1)
    end
    if p.note then GameTooltip:AddLine(p.note, 0.4, 1, 0.4, true) end
    if p.t then GameTooltip:AddLine(date("%Y-%m-%d %H:%M", p.t), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function AcquirePin()
    pinsUsed = pinsUsed + 1
    local pin = pins[pinsUsed]
    if not pin then
        pin = CreateFrame("Frame", nil, overlay)
        pin:SetSize(14, 14)
        pin.tex = pin:CreateTexture(nil, "OVERLAY")
        pin.tex:SetAllPoints()
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", PinOnEnter)
        pin:SetScript("OnLeave", GameTooltip_Hide)
        pins[pinsUsed] = pin
    end
    pin:ClearAllPoints()
    pin:Show()
    return pin
end

local function Setup()
    if overlay or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 100)
    fills = ns.NewTexturePool(overlay, "BORDER")
    rings = ns.NewTexturePool(overlay, "ARTWORK")
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() WorldMap:Refresh() end)
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function() WorldMap:Refresh() end)
    end
    WorldMapFrame:HookScript("OnShow", function() WorldMap:Refresh() end)
end

function WorldMap:Refresh()
    Setup()
    if not overlay or not GAW.db then return end
    fills:ReleaseAll()
    rings:ReleaseAll()
    for i = 1, pinsUsed do pins[i]:Hide() end
    pinsUsed = 0
    if not WorldMapFrame:IsShown() or not GAW.db.settings.worldmap then return end

    local mapID = WorldMapFrame:GetMapID()
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    if not mapID or w == 0 then return end
    -- Keep pins the same on-screen size whatever the map zoom.
    local sc = WorldMapFrame.ScrollContainer
    local canvasScale = (sc and sc.GetCanvasScale and sc:GetCanvasScale()) or 1

    for _, p in ipairs(GAW.db.points) do
        local mx, my, rect = GAW:WorldToMap(p, mapID)
        if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
            local x, y = mx * w, -my * h
            if p.kind == "guard" and rect then
                local r = GAW:GuardRadius(p)
                local rw, rh = 2 * r / abs(rect.width) * w, 2 * r / abs(rect.height) * h
                local fill = fills:Acquire()
                fill:SetTexture(ns.MEDIA .. "disc")
                fill:SetVertexColor(1, 0.1, 0.1, 0.25)
                fill:SetSize(rw, rh)
                fill:SetPoint("CENTER", overlay, "TOPLEFT", x, y)
                local ring = rings:Acquire()
                ring:SetTexture(ns.MEDIA .. "ring")
                ring:SetVertexColor(1, 0.2, 0.2, 0.9)
                ring:SetSize(rw, rh)
                ring:SetPoint("CENTER", overlay, "TOPLEFT", x, y)
            end
            local pin = AcquirePin()
            pin.point = p
            pin.tex:SetTexture(ns.ICON[p.kind])
            pin:SetScale(1 / canvasScale)
            -- SetPoint offsets are in the pin's own (scaled) units.
            pin:SetPoint("CENTER", overlay, "TOPLEFT", x * canvasScale, y * canvasScale)
        end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Setup() end
end)
