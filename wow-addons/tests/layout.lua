-- Resolves mock frame anchors into screen rectangles (UIParent = 1280x720, y up)
-- and returns a flat list of visible draw items for the interface test.
local SCREEN_W, SCREEN_H = 1280, 720
UIParent.rect = { l = 0, r = SCREEN_W, b = 0, t = SCREEN_H }

local function pointPos(rect, name)
    local x = name:find("LEFT") and rect.l or name:find("RIGHT") and rect.r or (rect.l + rect.r) / 2
    local y = name:find("TOP") and rect.t or name:find("BOTTOM") and rect.b or (rect.t + rect.b) / 2
    return x, y
end

local function textWidth(o)
    return #(o.text or "") * (o.fontSize or 10) * 0.6
end


function Rect(o)
    if o.rect then return o.rect end
    if o.allPoints then o.rect = Rect(o.allPoints) return o.rect end
    local w = o.w or (o.kind == "FontString" and textWidth(o)) or 0
    local h = o.h or (o.kind == "FontString" and (o.fontSize or 10) + 2) or 0
    local l, r, t, b, cx, cy
    for _, pt in ipairs(o.points or {}) do
        local px, py = pointPos(Rect(pt.rel), pt.rp)
        px, py = px + pt.x, py + pt.y
        if pt.p:find("LEFT") then l = px elseif pt.p:find("RIGHT") then r = px else cx = px end
        if pt.p:find("TOP") then t = py elseif pt.p:find("BOTTOM") then b = py else cy = py end
    end
    if not l and not r then cx = cx or 0; l, r = cx - w / 2, cx + w / 2 end
    l = l or r - w; r = r or l + w
    if not t and not b then cy = cy or 0; t, b = cy + h / 2, cy - h / 2 end
    t = t or b + h; b = b or t - h
    o.rect = { l = l, r = r, t = t, b = b }
    return o.rect
end

local function visible(o)
    while o do
        if not o.shown then return false end
        o = o.parent
    end
    return true
end

function Layout(anchors)
    for _, f in ipairs(FRAMES) do f.rect = nil end
    local function clear(o) o.rect = nil; for _, c in ipairs(o.children) do clear(c) end end
    for _, a in ipairs(anchors) do clear(a) end
    local items = {}
    local function walk(o, depth)
        if not visible(o) then return end
        local r = Rect(o)
        items[#items + 1] = {
            kind = o.kind, l = r.l, r = r.r, t = r.t, b = r.b, depth = depth,
            text = o.text, textColor = o.textColor, color = o.color, texture = o.texture,
            desat = o.desat, bg = o.bg, cdStart = o.cdStart, cdDur = o.cdDur, reverse = o.reverse,
            justify = o.justify, fontSize = o.fontSize, role = o.role,
        }
        for _, c in ipairs(o.children) do walk(c, depth + 1) end
    end
    for _, a in ipairs(anchors) do walk(a, 0) end
    return items
end
