-- GSD List: a lightweight notepad with an optional to-do list.
-- Uses only textures, fonts and templates that ship with the game client.
-- The window is built the first time it is opened; until then only the
-- minimap button exists.

local ADDON_NAME = ...
local GSD = {}

local CreateFrame, GameTooltip, tinsert, tremove = CreateFrame, GameTooltip, tinsert, tremove
local cos, sin, rad, deg, atan2 = math.cos, math.sin, math.rad, math.deg, math.atan2
local min, max, floor = math.min, math.max, math.floor

local DEFAULTS = {
    notes = "",
    todos = {},
    todoEnabled = true,
    activeTab = "notes",
    width = 360,
    height = 420,
    minimap = { hide = false, angle = 200 },
}

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROW_HEIGHT = 22
local MAX_TODO_LETTERS = 255
local COMPLETE_DELAY = 0.6     -- seconds a ticked task stays visible before it is removed
local DRAG_SCROLL_SPEED = 200  -- pixels per second while dragging past the list edge
local db

local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local INSET_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Drop malformed entries (e.g. from a hand-edited SavedVariables file) and
-- completed ones, which auto-clear (older versions kept them until cleared)
local function SanitizeTodos(todos)
    for i = #todos, 1, -1 do
        local item = todos[i]
        if type(item) ~= "table" or type(item.text) ~= "string" or item.text == "" or item.done then
            tremove(todos, i)
        else
            item.done = false
        end
    end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(NORMAL_FONT_COLOR_CODE .. "GSD List:|r " .. msg)
end

--------------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------------

function GSD:CreateMainFrame()
    local f = CreateFrame("Frame", "GSDListFrame", UIParent, BACKDROP_TEMPLATE)
    f:Hide()
    f:SetSize(db.width, db.height)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(280, 260, 900, 900)
    else
        f:SetMinResize(280, 260)
        f:SetMaxResize(900, 900)
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        GSD:SavePosition()
    end)
    f:SetBackdrop(DIALOG_BACKDROP)
    tinsert(UISpecialFrames, "GSDListFrame") -- close with Escape
    self.frame = f

    -- Header banner + title
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(256, 64)
    header:SetPoint("TOP", 0, 12)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("GSD List")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Tabs
    self.tabs = {}
    local function MakeTab(key, label)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(80, 22)
        b:SetText(label)
        b:SetScript("OnClick", function() GSD:SelectTab(key) end)
        self.tabs[key] = b
        return b
    end
    MakeTab("notes", "Notes"):SetPoint("TOPLEFT", 18, -30)
    MakeTab("todo", "To-Do"):SetPoint("LEFT", self.tabs.notes, "RIGHT", 4, 0)

    -- Content area shared by both pages
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 16, -56)
    content:SetPoint("BOTTOMRIGHT", -16, 40)
    self.content = content

    -- Footer: optional to-do toggle
    local toggle = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    toggle:SetSize(24, 24)
    toggle:SetPoint("BOTTOMLEFT", 16, 14)
    toggle.Text:SetText("Enable To-Do List")
    toggle:SetScript("OnClick", function(self)
        GSD:SetTodoEnabled(self:GetChecked() and true or false)
    end)
    self.todoToggle = toggle

    -- Resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -8, 8)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        db.width, db.height = f:GetSize()
        GSD:SavePosition()
    end)

    self:CreateNotesPage()
    self:CreateTodoPage()
    self:RestorePosition()

    f:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        GSD:EndDrag(false)
        GSD.notesEdit:ClearFocus() -- also saves the notes
        GSD.todoInput:ClearFocus()
    end)

    self.todoToggle:SetChecked(db.todoEnabled)
    self.tabs.todo:SetShown(db.todoEnabled)
    self:RefreshTodos()
    self:SelectTab(db.activeTab)
end

function GSD:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint()
    db.point = { point, relPoint, x, y }
end

function GSD:RestorePosition()
    local f = self.frame
    f:ClearAllPoints()
    if db.point then
        f:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        f:SetPoint("CENTER")
    end
end

function GSD:SelectTab(key)
    if key ~= "todo" or not db.todoEnabled then key = "notes" end
    db.activeTab = key
    if not self.frame then return end
    self.notesPage:SetShown(key == "notes")
    self.todoPage:SetShown(key == "todo")
    for k, b in pairs(self.tabs) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    if key == "notes" then self.todoInput:ClearFocus() else self.notesEdit:ClearFocus() end
end

function GSD:SetTodoEnabled(enabled)
    db.todoEnabled = enabled
    if self.frame then
        self.todoToggle:SetChecked(enabled)
        self.tabs.todo:SetShown(enabled)
    end
    self:SelectTab(enabled and db.activeTab or "notes")
end

function GSD:Toggle(tab)
    if not self.frame then self:CreateMainFrame() end
    local f = self.frame
    if f:IsShown() and (not tab or tab == db.activeTab) then
        f:Hide()
    else
        if tab then self:SelectTab(tab) end
        f:Show()
    end
end

--------------------------------------------------------------------------------
-- Notes page
--------------------------------------------------------------------------------

local function MakeScrollArea(parent, name)
    local inset = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    inset:SetBackdrop(INSET_BACKDROP)
    inset:SetBackdropColor(0, 0, 0, 0.6)
    inset:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    local scroll = CreateFrame("ScrollFrame", name, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    return inset, scroll
end

local function NotesOnUpdate(self, elapsed)
    ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
end

function GSD:CreateNotesPage()
    local page = CreateFrame("Frame", nil, self.content)
    page:SetAllPoints()

    local inset, scroll = MakeScrollArea(page, "GSDListNotesScroll")
    inset:SetAllPoints()

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetWidth(max(scroll:GetWidth(), 100))
    edit:SetText(db.notes)
    edit:SetCursorPosition(0)
    scroll:SetScrollChild(edit)
    scroll:HookScript("OnSizeChanged", function(_, w) edit:SetWidth(w) end)

    -- Clicking anywhere in the box (below the last line) focuses the editor
    inset:EnableMouse(true)
    inset:SetScript("OnMouseDown", function() edit:SetFocus() end)

    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
    edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    -- Keep the cursor in view only while typing; no per-frame work otherwise
    edit:SetScript("OnEditFocusGained", function(self) self:SetScript("OnUpdate", NotesOnUpdate) end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetScript("OnUpdate", nil)
        db.notes = self:GetText()
    end)

    self.notesPage = page
    self.notesEdit = edit
end

--------------------------------------------------------------------------------
-- To-Do page
--------------------------------------------------------------------------------

local function SubmitTodo(input)
    GSD:AddTodo(input:GetText())
    input:SetText("")
end

function GSD:CreateTodoPage()
    local page = CreateFrame("Frame", nil, self.content)
    page:SetAllPoints()

    local input = CreateFrame("EditBox", "GSDListTodoInput", page, "InputBoxTemplate")
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", 6, -2)
    input:SetPoint("TOPRIGHT", -72, -2)
    input:SetAutoFocus(false)
    input:SetMaxLetters(MAX_TODO_LETTERS)
    input:SetScript("OnEnterPressed", SubmitTodo)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetSize(64, 22)
    add:SetPoint("TOPRIGHT", 0, -1)
    add:SetText("Add")
    add:SetScript("OnClick", function()
        SubmitTodo(input)
        input:SetFocus()
    end)

    local inset, scroll = MakeScrollArea(page, "GSDListTodoScroll")
    inset:SetPoint("TOPLEFT", 0, -28)
    inset:SetPoint("BOTTOMRIGHT", 0, 18)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(max(scroll:GetWidth(), 100), 1)
    scroll:SetScrollChild(list)
    scroll:HookScript("OnSizeChanged", function(_, w) list:SetWidth(w) end)

    -- Gold line showing where a dragged task will land
    local marker = list:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(1, 0.82, 0, 1)
    marker:SetHeight(2)
    marker:Hide()

    local count = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    count:SetPoint("BOTTOMLEFT", 4, 2)

    self.todoPage = page
    self.todoInput = input
    self.todoScroll = scroll
    self.todoList = list
    self.dropMarker = marker
    self.todoCount = count
    self.rows = {}
end

-- Ticked tasks stay visible briefly so the click registers (and can be undone
-- by unticking), then disappear on their own.
local function RemoveIfDone(item)
    local todos = db.todos
    for i = 1, #todos do
        if todos[i] == item then
            if item.done then
                tremove(todos, i)
                GSD:RefreshTodos()
            end
            return
        end
    end
end

-- Row handlers are shared by every row; each looks up its row via GetParent()
local function RowOnEnter(row)
    if GSD.dragItem then return end
    row.hl:Show()
    if row.text:IsTruncated() then
        GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(row.text:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function RowOnLeave(row)
    if GSD.dragItem then return end
    row.hl:Hide()
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function CheckOnClick(check)
    local item = db.todos[check:GetParent().index]
    if not item then return end
    item.done = check:GetChecked() and true or false
    GSD:RefreshTodos()
    if item.done then C_Timer.After(COMPLETE_DELAY, function() RemoveIfDone(item) end) end
end

local function DeleteOnClick(button)
    tremove(db.todos, button:GetParent().index)
    GSD:RefreshTodos()
end

--------------------------------------------------------------------------------
-- Drag to reorder. The OnUpdate only exists while a task is being dragged.
--------------------------------------------------------------------------------

-- Insertion slot (1 .. #todos + 1) under the cursor
function GSD:GetDropSlot()
    local list = self.todoList
    local _, y = GetCursorPosition()
    local offset = list:GetTop() - y / list:GetEffectiveScale()
    return min(max(floor(offset / ROW_HEIGHT + 0.5) + 1, 1), #db.todos + 1)
end

local function DragOnUpdate(_, elapsed)
    local self, scroll = GSD, GSD.todoScroll
    -- Scroll the list when the cursor is held above or below it
    local _, y = GetCursorPosition()
    y = y / scroll:GetEffectiveScale()
    local step, current = DRAG_SCROLL_SPEED * elapsed, scroll:GetVerticalScroll()
    if y > scroll:GetTop() then
        scroll:SetVerticalScroll(max(current - step, 0))
    elseif y < scroll:GetBottom() then
        scroll:SetVerticalScroll(min(current + step, scroll:GetVerticalScrollRange()))
    end
    local slot = self:GetDropSlot()
    self.dropSlot = slot
    self.dropMarker:ClearAllPoints()
    self.dropMarker:SetPoint("TOPLEFT", self.todoList, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT)
    self.dropMarker:SetPoint("RIGHT", self.todoList, "RIGHT")
    self.dropMarker:Show()
end

local function RowOnDragStart(row)
    local self = GSD
    self.dragItem = db.todos[row.index]
    self.dragRow = row
    self.dropSlot = row.index
    row:SetAlpha(0.5)
    GameTooltip:Hide()
    row:SetScript("OnUpdate", DragOnUpdate)
end

function GSD:EndDrag(drop)
    local item, row = self.dragItem, self.dragRow
    if not item then return end
    self.dragItem, self.dragRow = nil, nil
    row:SetScript("OnUpdate", nil)
    row:SetAlpha(1)
    row.hl:Hide()
    self.dropMarker:Hide()
    if not drop then return end
    -- Look the item up again: an auto-clear may have shifted it while dragging
    local todos = db.todos
    for from = 1, #todos do
        if todos[from] == item then
            local to = min(self.dropSlot, #todos + 1)
            if to > from then to = to - 1 end
            if to ~= from then
                tremove(todos, from)
                tinsert(todos, to, item)
            end
            break
        end
    end
    self:RefreshTodos()
end

local function RowOnDragStop() GSD:EndDrag(true) end

function GSD:GetRow(i)
    local row = self.rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, self.todoList)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnDragStart", RowOnDragStart)
    row:SetScript("OnDragStop", RowOnDragStop)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.35)
    hl:Hide()

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 0, 0)
    check:SetScript("OnClick", CheckOnClick)

    local del = CreateFrame("Button", nil, row)
    del:SetSize(22, 22)
    del:SetPoint("RIGHT", 0, 0)
    del:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    del:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    del:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    del:SetScript("OnClick", DeleteOnClick)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetPoint("RIGHT", del, "LEFT", -2, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    row.hl, row.check, row.text = hl, check, text
    self.rows[i] = row
    return row
end

function GSD:RefreshTodos()
    if not self.frame then return end
    local todos = db.todos
    local n = #todos
    for i = 1, n do
        local item, row = todos[i], self:GetRow(i)
        row.index = i
        row.text:SetText(item.text)
        row.check:SetChecked(item.done)
        if item.done then
            row.text:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
        else
            row.text:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        end
        row:Show()
    end
    for i = n + 1, #self.rows do
        self.rows[i]:Hide()
    end
    -- A hidden row never gets OnDragStop, so end a drag whose row just went away
    if self.dragRow and self.dragRow.index > n then self:EndDrag(false) end
    self.todoList:SetHeight(max(1, n * ROW_HEIGHT))
    if n == 0 then
        self.todoCount:SetText("Nothing to do!")
    elseif n == 1 then
        self.todoCount:SetText("1 task")
    else
        self.todoCount:SetFormattedText("%d tasks - drag to reorder", n)
    end
end

function GSD:AddTodo(text)
    text = text and strtrim(text)
    if not text or text == "" then return end
    tinsert(db.todos, { text = text, done = false })
    self:RefreshTodos()
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

function GSD:UpdateMinimapPosition()
    local angle = rad(db.minimap.angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

local function MinimapOnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    db.minimap.angle = deg(atan2(py / scale - my, px / scale - mx))
    GSD:UpdateMinimapPosition()
end

function GSD:CreateMinimapButton()
    local b = CreateFrame("Button", "GSDListMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GSD:Toggle(db.todoEnabled and "todo" or "notes")
        else
            GSD:Toggle()
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", MinimapOnDragUpdate)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GSD List")
        GameTooltip:AddLine("Left-click: Toggle notepad", 1, 1, 1)
        if db.todoEnabled then
            GameTooltip:AddLine("Right-click: Open to-do list", 1, 1, 1)
        end
        GameTooltip:AddLine("Drag: Move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = b
    self:UpdateMinimapPosition()
    b:SetShown(not db.minimap.hide)
end

--------------------------------------------------------------------------------
-- Shift-click item/quest/spell links into GSD List while one of its boxes has
-- focus. Current clients route links through ChatFrameUtil.InsertLink; older
-- ones through the ChatEdit_InsertLink global.
--------------------------------------------------------------------------------

local function OnInsertLink(link)
    if not link or not GSD.frame or not GSD.frame:IsShown() then return end
    if GSD.notesEdit:HasFocus() then
        GSD.notesEdit:Insert(link)
    elseif GSD.todoInput:HasFocus() then
        GSD.todoInput:Insert(link)
    end
end

local function HookLinks()
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
    end
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_GSDLIST1 = "/gsd"
SLASH_GSDLIST2 = "/gsdlist"
SlashCmdList.GSDLIST = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "" then
        GSD:Toggle()
    elseif msg == "todo" then
        GSD:SetTodoEnabled(not db.todoEnabled)
        Print("To-Do list " .. (db.todoEnabled and "enabled." or "disabled."))
    elseif msg == "minimap" then
        db.minimap.hide = not db.minimap.hide
        GSD.minimapButton:SetShown(not db.minimap.hide)
        Print("Minimap button " .. (db.minimap.hide and "hidden." or "shown."))
    elseif msg == "reset" then
        db.point, db.width, db.height = nil, DEFAULTS.width, DEFAULTS.height
        if GSD.frame then
            GSD.frame:SetSize(db.width, db.height)
            GSD:RestorePosition()
        end
        db.minimap.angle = DEFAULTS.minimap.angle
        GSD:UpdateMinimapPosition()
        Print("Window and minimap button positions reset.")
    else
        Print("Commands:")
        Print("  /gsd - toggle the window")
        Print("  /gsd todo - enable/disable the to-do list")
        Print("  /gsd minimap - show/hide the minimap button")
        Print("  /gsd reset - reset window and button positions")
    end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        if type(GSDListDB) ~= "table" then GSDListDB = {} end
        db = GSDListDB
        CopyDefaults(DEFAULTS, db)
        if type(db.notes) ~= "string" then db.notes = "" end
        if type(db.minimap.angle) ~= "number" then db.minimap.angle = DEFAULTS.minimap.angle end
        SanitizeTodos(db.todos)

        GSD:CreateMinimapButton()
        HookLinks()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGOUT")
    elseif event == "PLAYER_LOGOUT" and GSD.notesEdit then
        -- Notes still being typed (box focused) at /reload or logout
        db.notes = GSD.notesEdit:GetText()
    end
end)
