-- Radar HUD: a top-down view of the ground around you with every guard's aggro ring drawn to scale.
local ADDON, ns = ...
local GAW = ns.GAW

local sqrt, sin, cos, abs, max = math.sqrt, math.sin, math.cos, math.abs, math.max
local format = string.format

local SIZE = 200
local ICON_SIZE = 14

local Radar = {}
ns.Radar = Radar

local frame = CreateFrame("Frame", "GuardAggroWatchRadar", UIParent)
frame:SetSize(SIZE, SIZE)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if not GAW.db.settings.radarLocked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    GAW.db.settings.radarPoint = { point, relPoint, x, y }
end)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.5)

-- Everything drawn on the "ground" lives in a clipped canvas so big rings get cut at the edges.
local clip = CreateFrame("Frame", nil, frame)
clip:SetAllPoints()
clip:SetClipsChildren(true)
local canvas = CreateFrame("Frame", nil, clip)
canvas:SetAllPoints()

local fills = ns.NewTexturePool(canvas, "BORDER")
local rings = ns.NewTexturePool(canvas, "ARTWORK")
local icons = ns.NewTexturePool(canvas, "OVERLAY")

-- Scale ring at half the radar range.
local scaleRing = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
scaleRing:SetTexture(ns.MEDIA .. "ring")
scaleRing:SetVertexColor(1, 1, 1, 0.15)
scaleRing:SetPoint("CENTER")

local arrow = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
arrow:SetSize(28, 28)
arrow:SetPoint("CENTER")

local rangeText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rangeText:SetPoint("TOPLEFT", 4, -4)

local northText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
northText:SetText("N")

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
status:SetPoint("TOP", frame, "BOTTOM", 0, -4)
status:SetWidth(SIZE + 80)

local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail:SetPoint("TOP", status, "BOTTOM", 0, -2)
detail:SetWidth(SIZE + 80)

function Radar:ApplySettings()
    local s = GAW.db.settings
    frame:SetScale(s.radarScale)
    frame:ClearAllPoints()
    local p = s.radarPoint
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    frame:EnableMouse(not s.radarLocked)
    frame:SetShown(s.radarShown)
    rangeText:SetText(format("%d yd", s.radarRange))
    scaleRing:SetSize(SIZE / 2, SIZE / 2)
end

local function Place(tex, size, x, y)
    tex:SetSize(size, size)
    tex:SetPoint("CENTER", canvas, "CENTER", x, y)
end

local STATE_TEXT = {
    inside  = "|cffff3333INSIDE AGGRO RANGE|r",
    caution = "|cffffcc00CAUTION - near the line|r",
    safe    = "|cff33ff33SAFE|r",
}

function Radar:Update(pos, st)
    if not frame:IsShown() then return end
    fills:ReleaseAll()
    rings:ReleaseAll()
    icons:ReleaseAll()

    local s = GAW.db.settings
    if not pos then
        status:SetText("|cff999999Position unavailable here|r")
        detail:SetText("")
        return
    end

    local half = SIZE / 2
    local ppy = half / s.radarRange -- pixels per yard
    -- With rotation the radar turns with you (your facing is always up), like looking at the ground.
    local rot = s.radarRotate and pos.facing or 0
    local c, sn = cos(rot), sin(rot)
    local limit = s.radarRange * 1.5

    for _, p in ipairs(GAW.db.points) do
        if p.inst == pos.inst then
            local e, n = GAW:Offset(pos, p)
            local d = sqrt(e * e + n * n)
            local r = p.kind == "guard" and GAW:GuardRadius(p) or 0
            if d - r - s.warnYards <= limit then
                local x = (e * c + n * sn) * ppy
                local y = (-e * sn + n * c) * ppy
                if p.kind == "guard" then
                    local fill = fills:Acquire()
                    fill:SetTexture(ns.MEDIA .. "disc")
                    fill:SetVertexColor(1, 0.1, 0.1, 0.25)
                    Place(fill, 2 * r * ppy, x, y)

                    local ring = rings:Acquire()
                    ring:SetTexture(ns.MEDIA .. "ring")
                    ring:SetVertexColor(1, 0.2, 0.2, 0.95)
                    Place(ring, 2 * r * ppy, x, y)

                    local warn = rings:Acquire()
                    warn:SetTexture(ns.MEDIA .. "ring")
                    warn:SetVertexColor(1, 0.85, 0, 0.45)
                    Place(warn, 2 * (r + s.warnYards) * ppy, x, y)
                end
                if d <= limit then
                    local icon = icons:Acquire()
                    icon:SetTexture(ns.ICON[p.kind])
                    if p.kind == "aggro" then icon:SetVertexColor(1, 0.6, 0.2, 0.8) end
                    Place(icon, p.kind == "aggro" and ICON_SIZE - 4 or ICON_SIZE, x, y)
                end
            end
        end
    end

    arrow:SetRotation(s.radarRotate and 0 or pos.facing)
    -- "N" marker sits on the radar edge in the direction of north.
    northText:ClearAllPoints()
    northText:SetPoint("CENTER", frame, "CENTER", sn * (half - 8), c * (half - 8))

    if st.state == "none" then
        status:SetText("|cff999999No guard marks nearby|r")
    elseif st.state == "inside" then
        status:SetText(format("%s  %.1f yd in", STATE_TEXT.inside, -st.margin))
    else
        status:SetText(format("%s  %.1f yd to the line", STATE_TEXT[st.state], st.margin))
    end

    local parts = {}
    if st.guard then
        parts[#parts + 1] = format("%s: %.0f yd away, %.0f yd radius",
            st.guard.name or "Guard", st.dist, st.radius)
    end
    if st.inside > 1 then parts[#parts + 1] = format("|cffff3333inside %d rings|r", st.inside) end
    if st.safeSpot then
        parts[#parts + 1] = "|cff33ff33On blind spot|r" .. (st.safeSpot.note and (": " .. st.safeSpot.note) or "")
    end
    local live = st.live
    if live and live.count > 0 then
        parts[#parts + 1] = format("Guards on nameplates: %d%s", live.count,
            live.nearest and format(" (closest within ~%d yd)", live.nearest) or "")
    end
    detail:SetText(table.concat(parts, "\n"))
end
