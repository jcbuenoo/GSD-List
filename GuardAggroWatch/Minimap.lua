-- Minimap overlay: guard aggro rings drawn as dotted circles plus mark icons.
local ADDON, ns = ...
local GAW = ns.GAW

local sqrt, sin, cos, max, min, floor, pi = math.sqrt, math.sin, math.cos, math.max, math.min, math.floor, math.pi

-- Minimap diameter in yards per zoom level (same table HereBeDragons-Pins uses).
local MINIMAP_SIZE = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

local Minimap_ = {}
ns.Minimap = Minimap_

local overlay = CreateFrame("Frame", nil, Minimap)
overlay:SetAllPoints()
overlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)

local dots = ns.NewTexturePool(overlay, "ARTWORK")
local icons = ns.NewTexturePool(overlay, "OVERLAY")

-- Ironforge and Undercity use the indoor zoom table. The game doesn't say which one is active,
-- so nudge the zoom and see which CVar follows it.
local indoors, checking = false, false
local function UpdateIndoors()
    if checking then return end
    checking = true
    local zoom = Minimap:GetZoom()
    if not GetCVar("minimapZoom") or not GetCVar("minimapInsideZoom") then
        indoors = IsIndoors and IsIndoors() or false
        checking = false
        GAW:Update(true)
        return
    end
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
        Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
    end
    indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
    Minimap:SetZoom(zoom)
    checking = false
    GAW:Update(true)
end
overlay:RegisterEvent("MINIMAP_UPDATE_ZOOM")
overlay:RegisterEvent("PLAYER_ENTERING_WORLD")
overlay:RegisterEvent("ZONE_CHANGED_INDOORS")
overlay:RegisterEvent("ZONE_CHANGED_NEW_AREA")
overlay:SetScript("OnEvent", UpdateIndoors)

function Minimap_:Update(pos)
    dots:ReleaseAll()
    icons:ReleaseAll()
    if not pos or not GAW.db.settings.minimap then return end

    local sizes = MINIMAP_SIZE[indoors and "indoor" or "outdoor"]
    local diameter = sizes[Minimap:GetZoom()] or sizes[0]
    local radiusPx = Minimap:GetWidth() / 2
    local ppy = radiusPx / (diameter / 2)
    local rot = (GetCVar("rotateMinimap") == "1") and pos.facing or 0
    local c, sn = cos(rot), sin(rot)
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local edge = radiusPx - 3

    local function visible(x, y)
        if square then return x >= -edge and x <= edge and y >= -edge and y <= edge end
        return x * x + y * y <= edge * edge
    end
    local function toMinimap(e, n)
        return (e * c + n * sn) * ppy, (-e * sn + n * c) * ppy
    end

    for _, p in ipairs(GAW.db.points) do
        if p.inst == pos.inst then
            local e, n = GAW:Offset(pos, p)
            local r = p.kind == "guard" and GAW:GuardRadius(p) or 0
            if sqrt(e * e + n * n) - r <= diameter / 2 then
                if p.kind == "guard" then
                    local count = max(12, min(64, floor(2 * pi * r * ppy / 5)))
                    for k = 1, count do
                        local ang = 2 * pi * k / count
                        local x, y = toMinimap(e + r * cos(ang), n + r * sin(ang))
                        if visible(x, y) then
                            local dot = dots:Acquire()
                            dot:SetTexture(ns.MEDIA .. "disc")
                            dot:SetVertexColor(1, 0.15, 0.15, 0.9)
                            dot:SetSize(3, 3)
                            dot:SetPoint("CENTER", overlay, "CENTER", x, y)
                        end
                    end
                end
                local x, y = toMinimap(e, n)
                if visible(x, y) then
                    local icon = icons:Acquire()
                    icon:SetTexture(ns.ICON[p.kind])
                    icon:SetSize(10, 10)
                    icon:SetPoint("CENTER", overlay, "CENTER", x, y)
                end
            end
        end
    end
end
