-- Interface layout tests for GSD List: lua5.1 tests/layout_tests.lua [dump.lua]
-- Builds the window in many states and sizes with the mocked client, resolves
-- every anchor into a rectangle, and checks that controls stay inside the
-- window, don't overlap, and leave usable space. Text widths are estimates
-- (the game's font isn't available here), so a small margin is allowed.
-- With a file argument it also writes the resolved layouts (JSON) for rendering.

local TESTS_DIR = (arg[0]:match("^(.*)[/\\]") or ".")
local mock = dofile(TESTS_DIR .. "/mock_wow.lua")
mock.addonFile = os.getenv("GSD_ADDON") or "GSDList/GSDList.lua"
local DUMP_FILE = arg[1]

local BORDER = 6 -- the 24px dialog border covers about this much of each edge

local function Descends(w, ancestor)
    w = w.parent
    while w do
        if w == ancestor then return true end
        w = w.parent
    end
    return false
end

-- Scrolled content (note text, task rows) may extend past its viewport
local function InScrollContent(w)
    local node = w
    while node.parent do
        if node.parent.kind == "ScrollFrame" and node.kind ~= "Slider" then return node end
        node = node.parent
    end
end

local function Overlap(a, b)
    local w = math.min(a.r, b.r) - math.max(a.l, b.l)
    local h = math.min(a.t, b.t) - math.max(a.b, b.b)
    return w > 0.5 and h > 0.5
end

local function Describe(w)
    if w.name then return w.name end
    local label = (w.text ~= "" and ("'" .. w.text:sub(1, 20) .. "'"))
        or (w.normal and w.normal.file and w.normal.file:match("([^\\]+)$"))
        or w.file and w.file:match("([^\\]+)$") or w.part or w.template or ""
    return w.kind .. "(" .. label .. ")"
end

local failures, checks, layouts = {}, 0, {}
local function Fail(state, msg) failures[#failures + 1] = state .. ": " .. msg end

-- The window title is drawn on the header banner on purpose
local function Banner(w)
    return w.file == "Interface\\DialogFrame\\UI-DialogBox-Header" or (w.kind == "FontString" and w.text == "GSD List")
end

-- Controls that count as solid for overlap checks
local function Solid(w, frame)
    if not mock.Visible(w) or w == frame then return false end
    local k = w.kind
    if k == "Button" or k == "CheckButton" or k == "EditBox" or k == "Slider" then return true end
    if k == "FontString" then
        -- Labels drawn inside their own button don't collide with it
        return w.text ~= "" and not (w.parent and (w.parent.kind == "Button" or w.parent.kind == "CheckButton"))
    end
    if k == "Texture" then return w.file == "Interface\\DialogFrame\\UI-DialogBox-Header" or w.part == "inputBorder" end
    return false
end

local function CheckState(state, setup)
    local frame = GSDListFrame
    -- The game fires OnSizeChanged once a scroll frame's size is known; the
    -- addon sizes the scrolled content from it
    for _, w in ipairs(mock.created()) do
        if w.kind == "ScrollFrame" then
            local r = mock.Rect(w)
            w:Fire("OnSizeChanged", r.r - r.l, r.t - r.b)
        end
    end
    local fr = mock.Rect(frame)
    local widgets = {}
    for _, w in ipairs(mock.created()) do
        if w ~= frame and Descends(w, frame) and mock.Visible(w) then widgets[#widgets + 1] = w end
    end

    -- 1. Everything solid stays inside the window and clear of its border
    for _, w in ipairs(widgets) do
        if Solid(w, frame) and not InScrollContent(w) and not Banner(w) then
            checks = checks + 1
            local r = mock.Rect(w)
            -- The close button and resize grip sit on the border by design, like Blizzard's own
            local pad = (w.template == "UIPanelCloseButton" or w == GSD_GRIP) and 0 or BORDER
            if r.l < fr.l + pad - 0.5 or r.r > fr.r - pad + 0.5 or r.t > fr.t - pad + 0.5 or r.b < fr.b + pad - 0.5 then
                Fail(state, ("%s outside the window (l=%.0f r=%.0f t=%.0f b=%.0f, window %dx%d)"):format(
                    Describe(w), r.l - fr.l, fr.r - r.r, fr.t - r.t, r.b - fr.b, frame.w, frame.h))
            end
        end
    end

    -- 2. No two solid controls overlap (scrolled rows only checked against each other)
    local solids = {}
    for _, w in ipairs(widgets) do if Solid(w, frame) then solids[#solids + 1] = w end end
    for i = 1, #solids do
        for j = i + 1, #solids do
            local a, b = solids[i], solids[j]
            if not Descends(a, b) and not Descends(b, a) and (InScrollContent(a) == InScrollContent(b))
                and not (Banner(a) and Banner(b)) then
                checks = checks + 1
                if Overlap(mock.Rect(a), mock.Rect(b)) then
                    Fail(state, Describe(a) .. " overlaps " .. Describe(b))
                end
            end
        end
    end

    -- 3. Button labels fit their buttons (estimated width, 2px slack each side)
    for _, w in ipairs(widgets) do
        if w.template == "UIPanelButtonTemplate" and w.text ~= "" then
            checks = checks + 1
            local textWidth = #w.text * 10 * mock.CHAR_WIDTH
            if textWidth > w.w - 4 then
                Fail(state, ("label %s (~%.0fpx) does not fit its %dpx button"):format(Describe(w), textWidth, w.w))
            end
        end
    end

    -- 4. Usable space
    local lineHeight = GSDListDB.textSize + 2
    if GSDListFrame and mock.Visible(GSDListNotesScroll) then
        checks = checks + 1
        local r = mock.Rect(GSDListNotesScroll)
        if r.t - r.b < 3 * lineHeight then
            Fail(state, ("notes area only %.0fpx tall (< 3 lines)"):format(r.t - r.b))
        end
    end
    if mock.Visible(GSDListTodoScroll) then
        checks = checks + 1
        local r = mock.Rect(GSDListTodoScroll)
        if r.t - r.b < 2 * (GSDListDB.textSize + 8) then
            Fail(state, ("task list only %.0fpx tall (< 2 rows)"):format(r.t - r.b))
        end
    end
    for _, name in ipairs({ "GSDListNotesScrollScrollBar", "GSDListTodoScrollScrollBar" }) do
        local bar = rawget(_G, name)
        if bar and mock.Visible(bar) then
            checks = checks + 1
            local r = mock.Rect(bar)
            if r.t - r.b < 24 then
                Fail(state, ("%s track %.0fpx, too short for its 24px thumb"):format(name, r.t - r.b))
            end
        end
    end

    -- 5. Empty-list and empty-page hints fit inside their area once wrapped
    for _, w in ipairs(widgets) do
        if w.kind == "FontString" and (w.text:find("No tasks") or w.text:find("Click here to write")) then
            checks = checks + 1
            local r = mock.Rect(w)
            local width = r.r - r.l
            local lines = 0
            for line in (w.text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(#line * 10 * mock.CHAR_WIDTH / width))
            end
            local inset = mock.Rect(w.parent)
            if lines * 12 + 8 > inset.t - inset.b then
                Fail(state, ("hint needs %d lines, its area is %.0fpx tall"):format(lines, inset.t - inset.b))
            end
        end
    end

    if DUMP_FILE then
        local items = {}
        for _, w in ipairs(widgets) do
            local r = mock.Rect(w)
            items[#items + 1] = {
                kind = w.kind, template = w.template, part = w.part, file = w.file
                    or (w.normal and w.normal.file), text = w.text, size = mock.FontSize(w),
                fontTemplate = w.fontTemplate, enabled = w.enabled, checked = w.checked,
                alpha = w.alpha, desaturated = w.normal and w.normal.desaturated,
                texCoord = w.texCoord, color = w.color, textColor = w.textColor,
                backdrop = w.backdrop and (w.backdrop.edgeFile or w.backdrop.bgFile),
                backdropColor = w.backdropColor, disabledFile = w.disabledFile,
                parentKind = w.parent and w.parent.kind, parentTemplate = w.parent and w.parent.template,
                clip = (function()
                    local c = InScrollContent(w)
                    if not c then return nil end
                    local v = mock.Rect(c.parent) -- the scroll viewport that clips this content
                    return { v.l - fr.l, fr.t - v.t, v.r - fr.l, fr.t - v.b }
                end)(),
                l = r.l - fr.l, r = r.r - fr.l, t = fr.t - r.t, b = fr.t - r.b,
                depth = (function() local d, n = 0, w; while n.parent do d = d + 1; n = n.parent end; return d end)(),
            }
        end
        layouts[#layouts + 1] = { name = state, w = frame.w, h = frame.h, items = items, setup = setup,
            backdrop = frame.backdrop and frame.backdrop.edgeFile }
    end
end

--------------------------------------------------------------------------------
-- States to check
--------------------------------------------------------------------------------

local function Slash(msg) SlashCmdList.GSDLIST(msg) end
local function Build(sv, width, height)
    sv = sv or {}
    sv.width, sv.height = width, height
    mock.Load(sv)
    Slash("")
    for _, w in ipairs(mock.created()) do
        if w.normal and w.normal.file == "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" then GSD_GRIP = w end
    end
end
local function AddTasks(n) for i = 1, n do Slash("add Task number " .. i) end end
local function Tab(name)
    for _, w in ipairs(mock.created()) do
        if w.template == "UIPanelButtonTemplate" and w.text:find("^" .. name) then w:Fire("OnClick") end
    end
end
local function DeepPages()
    return { { id = 1, title = "Raid", text = "line one\nline two", children = {
        { id = 2, title = "Karazhan", text = "", children = {
            { id = 3, title = "Attunement chain", text = "", children = {
                { id = 4, title = "The Master's Key", text = "", children = {} } } } } } } } }
end

local SIZES = { { 200, 150, "min" }, { 250, 200, "small" }, { 300, 340, "default" }, { 900, 900, "max" } }
for _, size in ipairs(SIZES) do
    local w, h, label = size[1], size[2], size[3]
    for _, textSize in ipairs({ 10, 12, 14 }) do
        local tag = ("%s %dx%d text %d"):format(label, w, h, textSize)
        Build({ textSize = textSize }, w, h)
        CheckState(tag .. " notes")
        AddTasks(3); Tab("To%-Do"); CheckState(tag .. " to-do (3 tasks)")
    end
    local tag = ("%s %dx%d"):format(label, w, h)
    Build(nil, w, h); Tab("To%-Do"); CheckState(tag .. " to-do empty")
    Build(nil, w, h); AddTasks(120); Tab("To%-Do"); CheckState(tag .. " to-do (120 tasks)")
    Build({ pages = DeepPages(), currentPage = 4 }, w, h); CheckState(tag .. " deep page title")
    Build({ pages = DeepPages() }, w, h)
    for _, x in ipairs(mock.created()) do
        if x.normal and x.normal.file == "Interface\\Common\\UI-Searchbox-Icon" then x:Fire("OnClick") end
    end
    GSDListSearchBox:SetText("line"); CheckState(tag .. " search open")
    Build({ locked = true, todoEnabled = false }, w, h); CheckState(tag .. " locked, to-do off")
end

for _, f in ipairs(failures) do print("FAIL  " .. f) end
print(("%d layout checks, %d problems"):format(checks, #failures))

if DUMP_FILE then
    -- Minimal JSON writer for the renderer
    local function Json(v)
        if type(v) == "table" then
            local parts = {}
            if #v > 0 then
                for _, x in ipairs(v) do parts[#parts + 1] = Json(x) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            for k, x in pairs(v) do parts[#parts + 1] = Json(tostring(k)) .. ":" .. Json(x) end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif type(v) == "string" then
            return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
        elseif v == nil then return "null"
        else return tostring(v) end
    end
    local out = assert(io.open(DUMP_FILE, "w"))
    out:write(Json(layouts), "\n")
    out:close()
end

os.exit(#failures == 0 and 0 or 1)
