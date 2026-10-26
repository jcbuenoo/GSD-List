-- Mocked WoW API shared by the GSD List test scripts. It models enough of the
-- client (widgets, anchors, fonts, menus, popups, timers) to load the addon
-- outside the game. Load it with dofile; it returns the helper table.

--------------------------------------------------------------------------------
-- Mock WoW API
--------------------------------------------------------------------------------

local M = {}
local created, focused
function M.created() return created end
local Widget = {}
Widget.__index = function(self, k)
    local m = Widget[k]
    if m then return m end
    -- Methods we don't model are no-ops; they still have to be called with ':'
    if type(k) == "string" and k:match("^%u") then
        return function(s) assert(type(s) == "table", "method " .. k .. " called with '.'") end
    end
end

local function NewWidget(kind, name, parent)
    local w = setmetatable({ kind = kind, name = name, parent = parent, scripts = {},
        shown = true, text = "", checked = false, enabled = true, w = 300, h = 300, points = {} }, Widget)
    created[#created + 1] = w
    if name then _G[name] = w end
    return w
end

function Widget:SetScript(n, f) self.scripts[n] = f end
function Widget:GetScript(n) return self.scripts[n] end
function Widget:HookScript(n, f)
    local old = self.scripts[n]
    self.scripts[n] = old and function(...) old(...); f(...) end or f
end
function Widget:Fire(n, ...) local f = self.scripts[n]; if f then return f(self, ...) end end
function Widget:GetParent() return self.parent end
function Widget:SetText(t) self.text = t; self:Fire("OnTextChanged", false) end
function Widget:GetText() return self.text end
function Widget:SetFormattedText(f, ...) self.text = f:format(...) end
function Widget:Insert(t) self.text = self.text .. t; self:Fire("OnTextChanged", true) end
function Widget:SetCursorPosition(p) self.cursor = p end
function Widget:HighlightText(s, e) self.highlight = { s, e } end
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked end
function Widget:SetEnabled(v) self.enabled = v and true or false end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled end
function Widget:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Widget:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
    local w = self
    while w do if not w.shown then return false end; w = w.parent end
    return true
end
function Widget:SetFocus()
    if focused == self then return end
    if focused then focused:ClearFocus() end
    focused = self; self:Fire("OnEditFocusGained")
end
function Widget:ClearFocus() if focused == self then focused = nil; self:Fire("OnEditFocusLost") end end
function Widget:HasFocus() return focused == self end
function Widget:SetSize(w, h) self.w, self.h, self.sizedW, self.sizedH = w, h, true, true end
function Widget:SetWidth(w) self.w, self.sizedW = w, true end
function Widget:SetHeight(h) self.h, self.sizedH = h, true end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:GetSize() return self.w, self.h end
-- SetPoint keeps the raw calls in `points` (tests read them) and a normalised
-- copy per anchor point in `anchors`, which the layout engine below resolves.
function Widget:SetPoint(point, a, b, c, d)
    self.points[#self.points + 1] = { point, a, b, c, d }
    local rel, relPoint, x, y
    if type(a) == "number" then rel, relPoint, x, y = nil, point, a, b
    elseif type(a) == "table" then rel, relPoint, x, y = a, b or point, c, d
    else rel, relPoint, x, y = nil, b or point, c, d end
    if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
    self.anchors = self.anchors or {}
    self.anchors[point] = { rel = rel or self.parent, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function Widget:SetAllPoints(rel)
    self:SetPoint("TOPLEFT", rel or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel or self.parent, "BOTTOMRIGHT", 0, 0)
end
function Widget:ClearAllPoints() self.points, self.anchors = {}, {} end
function Widget:GetPoint() return "TOPLEFT", UIParent, "BOTTOMLEFT", 123, 456 end
function Widget:GetCenter() return 100, 100 end
function Widget:GetTop() return self.top or 500 end
function Widget:GetBottom() return self.bottom or 100 end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetVerticalScroll() return self.vscroll or 0 end
function Widget:SetVerticalScroll(v) self.vscroll = v end
function Widget:GetVerticalScrollRange() return self.range or 0 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return self.level or 1 end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateFontString(_, _, template)
    local fs = NewWidget("FontString", nil, self)
    fs.fontTemplate = template
    return fs
end
function Widget:SetFontObject(font) self.fontObject = font end
function Widget:SetNormalFontObject(font) self.normalFont = font end
function Widget:GetStringWidth() return #self.text * 5 end
function Widget:IsTruncated() return #self.text > 20 end
function Widget:SetResizeBounds(...) self.bounds = { ... } end
function Widget:StartMoving() self.moving = true end
function Widget:StartSizing() self.sizing = true end
function Widget:StopMovingOrSizing() self.moving, self.sizing = false, false end
function Widget:IsOwned(o) return self.owner == o end
function Widget:SetOwner(o) self.owner = o; self.lines = {} end
function Widget:AddLine(t) self.lines[#self.lines + 1] = t end
function Widget:SetNormalTexture(t) self.normal = NewWidget("Texture", nil, self); self.normal.file = t end
function Widget:GetNormalTexture() return self.normal end
function Widget:SetDesaturated(v) self.desaturated = v end
function Widget:SetTexture(f) self.file = f end
-- Visual properties, recorded for the layout renderer
function Widget:SetTexCoord(...) self.texCoord = { ... } end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function Widget:SetBackdrop(b) self.backdrop = b end
function Widget:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Widget:SetDisabledTexture(t) self.disabledFile = t end
-- A scroll child is laid out from its scroll frame's top-left corner
function Widget:SetScrollChild(child)
    child.anchors = { TOPLEFT = { rel = self, relPoint = "TOPLEFT", x = 0, y = 0 } }
end
function Widget:SetFont(file, size, flags) self.font = { file, size, flags } end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end

-- Template defaults and the children that matter for layout, taken from
-- Blizzard's XML for the 2.5.x client
local TEMPLATE_SIZES = {
    UIPanelButtonTemplate = { 40, 22 }, UIPanelCloseButton = { 32, 32 }, UICheckButtonTemplate = { 32, 32 },
}

function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name, parent)
    w.template = template
    w.sizedW, w.sizedH = false, false
    local size = TEMPLATE_SIZES[template]
    if size then w.w, w.h, w.sizedW, w.sizedH = size[1], size[2], true, true end
    if template == "UICheckButtonTemplate" then
        w.Text = NewWidget("FontString", nil, w)
        w.Text.fontTemplate = "GameFontNormalSmall"
        w.Text:SetPoint("LEFT", w, "RIGHT", -2, 0)
    elseif template == "UIPanelScrollFrameTemplate" then
        local bar = NewWidget("Slider", name and (name .. "ScrollBar"), w)
        bar:SetWidth(16)
        bar:SetPoint("TOPLEFT", w, "TOPRIGHT", 6, -16)
        bar:SetPoint("BOTTOMLEFT", w, "BOTTOMRIGHT", 6, 16)
        local up, down = NewWidget("Button", nil, bar), NewWidget("Button", nil, bar)
        up:SetSize(18, 16); up:SetPoint("BOTTOM", bar, "TOP")
        down:SetSize(18, 16); down:SetPoint("TOP", bar, "BOTTOM")
        w.ScrollBar, up.part, down.part = bar, "scrollUp", "scrollDown"
    elseif template == "InputBoxTemplate" or template == "SearchBoxTemplate" then
        local left = NewWidget("Texture", nil, w) -- the border art starts 5px left of the box
        left:SetSize(8, 20); left:SetPoint("LEFT", w, "LEFT", -5, 0); left.part = "inputBorder"
    end
    return w
end

--------------------------------------------------------------------------------
-- Layout engine: resolves anchors into screen rectangles (y grows upwards,
-- like the game). Enough of the real rules for the addon's own layouts.
--------------------------------------------------------------------------------

local FONT_SIZES = {
    GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
    GameFontNormal = 12, GameFontHighlight = 12, ChatFontNormal = 14, ChatFontSmall = 12,
}
M.CHAR_WIDTH = 0.58 -- average glyph width as a share of the font size (Friz Quadrata)

function M.FontSize(w)
    local font = w.fontObject
    if font and font.font then return font.font[2] end
    return FONT_SIZES[w.fontTemplate] or 12
end

function M.TextWidth(w)
    local longest = 0
    for line in (w.text .. "\n"):gmatch("(.-)\n") do
        local visible = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        longest = math.max(longest, #visible)
    end
    return longest * M.FontSize(w) * M.CHAR_WIDTH
end

local H = { LEFT = "l", RIGHT = "r", TOPLEFT = "l", BOTTOMLEFT = "l", TOPRIGHT = "r", BOTTOMRIGHT = "r" }
local V = { TOP = "t", BOTTOM = "b", TOPLEFT = "t", TOPRIGHT = "t", BOTTOMLEFT = "b", BOTTOMRIGHT = "b" }

local function PointXY(rect, point)
    local h, v = H[point], V[point]
    local x = h == "l" and rect.l or h == "r" and rect.r or (rect.l + rect.r) / 2
    local y = v == "t" and rect.t or v == "b" and rect.b or (rect.t + rect.b) / 2
    return x, y
end

function M.Rect(w)
    if w == UIParent then return { l = 0, r = 1920, t = 1080, b = 0 } end
    local l, r, t, b, cx, cy
    for point, a in pairs(w.anchors or {}) do
        local x, y = PointXY(M.Rect(a.rel), a.relPoint)
        x, y = x + a.x, y + a.y
        local h, v = H[point], V[point]
        if h == "l" then l = x elseif h == "r" then r = x else cx = x end
        if v == "t" then t = y elseif v == "b" then b = y else cy = y end
    end
    local width = (w.kind == "FontString" and not w.sizedW) and M.TextWidth(w) or w.w
    local lines = select(2, w.text:gsub("\n", "")) + 1
    local height = (w.kind == "FontString" and not w.sizedH) and (M.FontSize(w) + 2) * lines or w.h
    if not (l and r) then
        if l then r = l + width elseif r then l = r - width else l = (cx or 0) - width / 2; r = l + width end
    end
    if not (t and b) then
        if t then b = t - height elseif b then t = b + height else t = (cy or 0) + height / 2; b = t - height end
    end
    return { l = l, r = r, t = t, b = b }
end

-- Visible = shown along the whole parent chain
function M.Visible(w)
    while w do
        if not w.shown then return false end
        w = w.parent
    end
    return true
end

-- Menu system (MenuUtil) mock: records the generated elements so tests can click them
local function NewMenuNode(text, kind, a, b, data)
    local node = { text = text, kind = kind, a = a, b = b, data = data, enabled = true, children = {} }
    local function add(t, k, x, y, d)
        local child = NewMenuNode(t, k, x, y, d)
        node.children[#node.children + 1] = child
        return child
    end
    function node:CreateTitle(t) return add(t, "title") end
    function node:CreateDivider() return add("-", "divider") end
    function node:CreateButton(t, cb, d) return add(t, "button", cb, nil, d) end
    function node:CreateCheckbox(t, isSel, setSel, d) return add(t, "checkbox", isSel, setSel, d) end
    function node:CreateRadio(t, isSel, setSel, d) return add(t, "radio", isSel, setSel, d) end
    function node:SetEnabled(v) self.enabled = v end
    function node:SetScrollMode(h) self.scroll = h end
    return node
end

function M.ResetEnvironment()
    created, focused = {}, nil
    for _, n in ipairs({ "GSDListDB", "GSDListFrame", "GSDListMinimapButton", "GSDListTodoInput",
        "GSDListNotesScroll", "GSDListTodoScroll", "GSDListSearchBox", "SLASH_GSDLIST1", "SLASH_GSDLIST2" }) do
        _G[n] = nil
    end
    UIParent = NewWidget("Frame", "UIParent")
    Minimap = NewWidget("Frame", "Minimap"); Minimap.w = 140
    GameTooltip = NewWidget("GameTooltip", "GameTooltip")
    UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
    ChatFontNormal, ChatFontSmall = NewWidget("Font"), NewWidget("Font")
    GameFontHighlight, GameFontNormalSmall = NewWidget("Font"), NewWidget("Font")
    GameFontHighlightSmall, GameFontDisableSmall = NewWidget("Font"), NewWidget("Font")
    CreateFont = function(name) return NewWidget("Font", name) end
    SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840 }
    BackdropTemplateMixin = {}
    chatLog = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chatLog[#chatLog + 1] = m end }
    -- Mirrors the 2.5.6 client: links go through ChatFrameUtil.InsertLink,
    -- and ChatEdit_InsertLink is only a deprecated alias.
    ChatFrameUtil = { InsertLink = function() return false end }
    ChatEdit_InsertLink = ChatFrameUtil.InsertLink
    -- Same behaviour as Blizzard's helpers, including the arithmetic on
    -- cursorOffset that errors if ScrollingEdit_SetCursorOffsets was never called.
    ScrollingEdit_SetCursorOffsets = function(edit, offset, height)
        edit.cursorOffset, edit.cursorHeight = offset, height
    end
    ScrollingEdit_OnCursorChanged = function(edit, _, y, _, h)
        edit.cursorOffset, edit.cursorHeight = y, h
        edit.handleCursorChange = true
    end
    ScrollingEdit_OnUpdate = function(edit)
        if edit.handleCursorChange then
            local _ = -edit.cursorOffset + edit.cursorHeight
            edit.handleCursorChange = false
        end
    end
    ScrollingEdit_OnTextChanged = function(edit, scroll)
        edit.handleCursorChange = true
        ScrollingEdit_OnUpdate(edit, 0, scroll)
    end
    cursorX, cursorY = 150, 100
    timers = {}
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    shiftDown = false
    IsShiftKeyDown = function() return shiftDown end
    popups = {}
    StaticPopup_Show = function(which, text1, _, data)
        local info = assert(StaticPopupDialogs[which], "unknown popup " .. tostring(which))
        local dialog = NewWidget("Frame", nil, UIParent)
        local editBox = info.hasEditBox and NewWidget("EditBox", nil, dialog)
        if editBox then editBox.template = "popup" end
        function dialog:GetEditBox() return editBox end
        local popup = { which = which, text = info.text:format(text1), data = data, editBox = editBox }
        function popup.accept(input)
            if editBox and input then editBox.text = input end
            info.OnAccept(dialog, data)
        end
        function popup.cancel() if info.OnCancel then info.OnCancel(dialog, data, "clicked") end end
        function popup.enter(input) editBox.text = input; info.EditBoxOnEnterPressed(editBox, data) end
        if info.OnShow then info.OnShow(dialog, data) end
        popups[#popups + 1] = popup
        return dialog
    end
    hiddenPopups = {}
    StaticPopup_Hide = function(which) hiddenPopups[#hiddenPopups + 1] = which end
    menus = {}
    MenuResponse = { Close = 1, Refresh = 2 }
    MenuUtil = { CreateContextMenu = function(owner, generator)
        local root = NewMenuNode("root", "root")
        generator(owner, root)
        menus[#menus + 1] = root
    end }
end

PlaySound = function() end
GetCursorPosition = function() return cursorX, cursorY end
NORMAL_FONT_COLOR_CODE = "|cffffd100"
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
YES, NO, ACCEPT, CANCEL = "Yes", "No", "Accept", "Cancel"
tinsert, tremove = table.insert, table.remove
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
hooksecurefunc = function(tbl, key, hook)
    if type(tbl) == "string" then tbl, key, hook = _G, tbl, key end
    local orig = tbl[key]
    tbl[key] = function(...) local r = { orig(...) }; hook(...); return unpack(r) end
end

-- Strict globals: reading an undefined global is an error (catches typos)
local KNOWN_NIL = { GSDListDB = true, ChatFrameUtil = true, ChatEdit_InsertLink = true }
setmetatable(_G, { __index = function(_, k)
    if KNOWN_NIL[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "'", 2)
end })

function M.Load(savedVariables, addonFile)
    M.ResetEnvironment()
    GSDListDB = savedVariables
    local chunk = assert(loadfile(addonFile or M.addonFile))
    chunk("GSDList", {})
    local loader = created[#created]
    loader:Fire("OnEvent", "ADDON_LOADED", "SomeOtherAddon")
    assert(GSDListDB == savedVariables, "reacted to another addon's ADDON_LOADED")
    loader:Fire("OnEvent", "ADDON_LOADED", "GSDList")
    return loader
end

return M
