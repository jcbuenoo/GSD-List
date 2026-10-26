-- GSD List: a lightweight notepad with an optional to-do list.
-- Uses only textures, fonts and templates that ship with the game client.

local ADDON_NAME = ...
local GSD = {}

local DEFAULTS = {
    notes = "",
    todos = {},
    todoEnabled = true,
    activeTab = "notes",
    width = 360,
    height = 420,
    point = nil,
    minimap = { hide = false, angle = 200 },
}

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROW_HEIGHT = 22
local db

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

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(NORMAL_FONT_COLOR_CODE .. "GSD List:|r " .. msg)
end

local function SetInsetBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

--------------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------------

function GSD:CreateMainFrame()
    local f = CreateFrame("Frame", "GSDListFrame", UIParent, BACKDROP_TEMPLATE)
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
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:Hide()
    tinsert(UISpecialFrames, "GSDListFrame") -- close with Escape

    f:SetScript("OnShow", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839) end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
        GSD.notesEdit:ClearFocus()
        GSD.todoInput:ClearFocus()
    end)

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
    local toggleText = toggle:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    toggleText:SetPoint("LEFT", toggle, "RIGHT", 2, 1)
    toggleText:SetText("Enable To-Do List")
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

    self.frame = f
    self:CreateNotesPage()
    self:CreateTodoPage()
    self:RestorePosition()
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
    if key == "todo" and not db.todoEnabled then key = "notes" end
    db.activeTab = key
    self.notesPage:SetShown(key == "notes")
    self.todoPage:SetShown(key == "todo")
    for k, b in pairs(self.tabs) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    if key == "notes" then self.todoInput:ClearFocus() else self.notesEdit:ClearFocus() end
end

function GSD:SetTodoEnabled(enabled)
    db.todoEnabled = enabled
    self.todoToggle:SetChecked(enabled)
    self.tabs.todo:SetShown(enabled)
    self:SelectTab(enabled and db.activeTab or "notes")
end

function GSD:Toggle(tab)
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
    SetInsetBackdrop(inset)
    local scroll = CreateFrame("ScrollFrame", name, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    return inset, scroll
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
    edit:SetWidth(200)
    edit:SetText(db.notes or "")
    edit:SetCursorPosition(0)
    scroll:SetScrollChild(edit)

    scroll:HookScript("OnSizeChanged", function(_, w) edit:SetWidth(w) end)
    -- Clicking anywhere in the box (below the last line) focuses the editor
    inset:EnableMouse(true)
    inset:SetScript("OnMouseDown", function() edit:SetFocus() end)

    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
        if userInput then db.notes = self:GetText() end
    end)
    edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    edit:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
    end)
    edit:SetScript("OnEditFocusLost", function(self) db.notes = self:GetText() end)

    self.notesPage = page
    self.notesEdit = edit
end

--------------------------------------------------------------------------------
-- To-Do page
--------------------------------------------------------------------------------

local function MakeIconButton(parent, prefix, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(prefix .. "-Up")
    b:SetPushedTexture(prefix .. "-Down")
    b:SetDisabledTexture(prefix .. "-Disabled")
    b:SetHighlightTexture(prefix == "Interface\\Buttons\\UI-Panel-MinimizeButton"
        and prefix .. "-Highlight" or "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end

function GSD:CreateTodoPage()
    local page = CreateFrame("Frame", nil, self.content)
    page:SetAllPoints()

    local input = CreateFrame("EditBox", "GSDListTodoInput", page, "InputBoxTemplate")
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", 6, -2)
    input:SetPoint("TOPRIGHT", -72, -2)
    input:SetAutoFocus(false)
    input:SetMaxLetters(200)
    input:SetScript("OnEnterPressed", function(self)
        GSD:AddTodo(self:GetText())
        self:SetText("")
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetSize(64, 22)
    add:SetPoint("TOPRIGHT", 0, -1)
    add:SetText("Add")
    add:SetScript("OnClick", function()
        GSD:AddTodo(input:GetText())
        input:SetText("")
        input:SetFocus()
    end)

    local inset, scroll = MakeScrollArea(page, "GSDListTodoScroll")
    inset:SetPoint("TOPLEFT", 0, -28)
    inset:SetPoint("BOTTOMRIGHT", 0, 28)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(200, 1)
    scroll:SetScrollChild(list)
    scroll:HookScript("OnSizeChanged", function(_, w) list:SetWidth(w) end)

    local clear = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    clear:SetSize(120, 22)
    clear:SetPoint("BOTTOMLEFT", 0, 0)
    clear:SetText("Clear Completed")
    clear:SetScript("OnClick", function() GSD:ClearCompleted() end)

    local count = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", -4, 6)

    self.todoPage = page
    self.todoInput = input
    self.todoList = list
    self.todoCount = count
    self.rows = {}
end

function GSD:GetRow(i)
    local row = self.rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, self.todoList)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    row:EnableMouse(true)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.35)
    hl:Hide()

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 0, 0)
    check:SetScript("OnClick", function(self)
        local item = db.todos[row.index]
        if item then item.done = self:GetChecked() and true or false end
        GSD:RefreshTodos()
    end)

    local del = MakeIconButton(row, "Interface\\Buttons\\UI-Panel-MinimizeButton", 22)
    del:SetPoint("RIGHT", 0, 0)
    del:SetScript("OnClick", function()
        tremove(db.todos, row.index)
        GSD:RefreshTodos()
    end)

    local down = MakeIconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", 20)
    down:SetPoint("RIGHT", del, "LEFT", 2, 0)
    down:SetScript("OnClick", function() GSD:MoveTodo(row.index, 1) end)

    local up = MakeIconButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", 20)
    up:SetPoint("RIGHT", down, "LEFT", 2, 0)
    up:SetScript("OnClick", function() GSD:MoveTodo(row.index, -1) end)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetPoint("RIGHT", up, "LEFT", -2, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    -- Full text in a tooltip, useful when a long entry is truncated
    row:SetScript("OnEnter", function(self)
        hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(text:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        hl:Hide()
        GameTooltip:Hide()
    end)

    row.check, row.text, row.up, row.down = check, text, up, down
    self.rows[i] = row
    return row
end

function GSD:RefreshTodos()
    local todos = db.todos
    local done = 0
    for i, item in ipairs(todos) do
        local row = self:GetRow(i)
        row.index = i
        row.text:SetText(item.text)
        row.check:SetChecked(item.done)
        if item.done then
            done = done + 1
            row.text:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
        else
            row.text:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        end
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #todos)
        row:Show()
    end
    for i = #todos + 1, #self.rows do
        self.rows[i]:Hide()
    end
    self.todoList:SetHeight(math.max(1, #todos * ROW_HEIGHT))
    if #todos == 0 then
        self.todoCount:SetText("Nothing to do!")
    else
        self.todoCount:SetFormattedText("%d / %d done", done, #todos)
    end
end

function GSD:AddTodo(text)
    text = text and strtrim(text)
    if not text or text == "" then return end
    tinsert(db.todos, { text = text, done = false })
    self:RefreshTodos()
end

function GSD:MoveTodo(index, delta)
    local target = index + delta
    local todos = db.todos
    if target < 1 or target > #todos then return end
    todos[index], todos[target] = todos[target], todos[index]
    self:RefreshTodos()
end

function GSD:ClearCompleted()
    for i = #db.todos, 1, -1 do
        if db.todos[i].done then tremove(db.todos, i) end
    end
    self:RefreshTodos()
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

function GSD:UpdateMinimapPosition()
    local angle = math.rad(db.minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
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
        if button == "RightButton" and db.todoEnabled then
            GSD:Toggle("todo")
        else
            GSD:Toggle(button == "RightButton" and "notes" or nil)
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            GSD:UpdateMinimapPosition()
        end)
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
-- Shift-click item/quest/spell links into the notepad while it has focus
--------------------------------------------------------------------------------

local function HookLinks()
    if not ChatEdit_InsertLink then return end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and GSD.notesEdit and GSD.notesEdit:HasFocus() then
            GSD.notesEdit:Insert(link)
        elseif link and GSD.todoInput and GSD.todoInput:HasFocus() then
            GSD.todoInput:Insert(link)
        end
    end)
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
        GSD.frame:SetSize(db.width, db.height)
        GSD:RestorePosition()
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
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        GSDListDB = GSDListDB or {}
        db = GSDListDB
        CopyDefaults(DEFAULTS, db)

        GSD:CreateMainFrame()
        GSD:CreateMinimapButton()
        GSD:RefreshTodos()
        GSD:SetTodoEnabled(db.todoEnabled)
        HookLinks()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGOUT" and GSD.notesEdit then
        db.notes = GSD.notesEdit:GetText()
    end
end)
