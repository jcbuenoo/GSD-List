-- GSD List: a lightweight notepad with nested note pages and an optional to-do list.
-- Uses only textures, fonts, templates and menus that ship with the game client.
-- The window is built the first time it is opened; until then only the
-- minimap button exists.

local ADDON_NAME = ...
local GSD = { undo = {} }

local CreateFrame, GameTooltip, tinsert, tremove = CreateFrame, GameTooltip, tinsert, tremove
local cos, sin, rad, deg, atan2 = math.cos, math.sin, math.rad, math.deg, math.atan2
local min, max, floor = math.min, math.max, math.floor
local strfind, strlower, strrep, strmatch = string.find, string.lower, string.rep, string.match

local DEFAULTS = {
    pages = {},
    nextPageId = 1,
    todos = {},
    todoEnabled = true,
    confirmComplete = true,
    locked = false,
    textSize = 12,
    activeTab = "notes",
    width = 300,
    height = 340,
    minimap = { hide = false, angle = 200 },
}

local MIN_WIDTH, MIN_HEIGHT, MAX_SIZE = 200, 150, 900
local MAX_DEPTH = 4            -- nesting levels for note pages
local MAX_TODO_LETTERS = 255
local MAX_TITLE_LETTERS = 40
local MAX_MATCHES = 500
local UNDO_LIMIT = 20
local COMPLETE_DELAY = 0.6     -- seconds a ticked task stays visible before it is removed
local DRAG_SCROLL_SPEED = 200  -- pixels per second while dragging past the list edge
local TEXT_SIZES = { { 10, "Small" }, { 12, "Medium" }, { 14, "Large" } }
local HIGHLIGHT = "Interface\\Buttons\\UI-Common-MouseHilight"

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local db

local WINDOW_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 24, edgeSize = 24,
    insets = { left = 7, right = 7, top = 7, bottom = 7 },
}
local INSET_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(NORMAL_FONT_COLOR_CODE .. "GSD List:|r " .. msg)
end

local function IndexOf(list, value)
    for i = 1, #list do
        if list[i] == value then return i end
    end
end

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

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

-- Drop malformed tasks (e.g. from a hand-edited SavedVariables file) and
-- completed ones, which auto-clear (versions before 1.2 kept them)
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

local function SanitizePages(list, depth, seen)
    for i = #list, 1, -1 do
        local page = list[i]
        if type(page) ~= "table" then
            tremove(list, i)
        else
            if type(page.title) ~= "string" or page.title == "" then page.title = "Untitled" end
            if type(page.text) ~= "string" then page.text = "" end
            if type(page.children) ~= "table" or depth > 20 then page.children = {} end
            if type(page.id) ~= "number" or seen[page.id] then page.id = nil end
            if page.id then seen[page.id] = true end
            SanitizePages(page.children, depth + 1, seen)
        end
    end
end

local function AssignMissingIds(list)
    for _, page in ipairs(list) do
        if not page.id then
            page.id = db.nextPageId
            db.nextPageId = db.nextPageId + 1
        end
        AssignMissingIds(page.children)
    end
end

local function NewPage(title)
    local page = { id = db.nextPageId, title = title, text = "", children = {} }
    db.nextPageId = db.nextPageId + 1
    return page
end

local function LoadDatabase()
    if type(GSDListDB) ~= "table" then GSDListDB = {} end
    db = GSDListDB
    -- Versions before 2.0 had a single note string
    local oldNotes = db.notes
    db.notes = nil
    CopyDefaults(DEFAULTS, db)
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = DEFAULTS.minimap.angle end
    if type(db.textSize) ~= "number" then db.textSize = DEFAULTS.textSize end
    if type(db.nextPageId) ~= "number" then db.nextPageId = 1 end
    SanitizeTodos(db.todos)

    local seen = {}
    SanitizePages(db.pages, 0, seen)
    for id in pairs(seen) do db.nextPageId = max(db.nextPageId, id + 1) end
    AssignMissingIds(db.pages)
    if #db.pages == 0 then
        local page = NewPage("Notes")
        if type(oldNotes) == "string" then page.text = oldNotes end
        db.pages[1] = page
    end
end

--------------------------------------------------------------------------------
-- Note pages (a tree; navigation walks it depth-first)
--------------------------------------------------------------------------------

-- Depth-first list of every page: { page, depth, siblings, index }
function GSD:GetFlatPages()
    if self.flat then return self.flat end
    local flat = {}
    local function Walk(list, depth)
        for i, page in ipairs(list) do
            flat[#flat + 1] = { page = page, depth = depth, siblings = list, index = i }
            Walk(page.children, depth + 1)
        end
    end
    Walk(db.pages, 0)
    self.flat = flat
    return flat
end

function GSD:PagesChanged()
    self.flat = nil
end

function GSD:FindPage(id)
    for pos, entry in ipairs(self:GetFlatPages()) do
        if entry.page.id == id then return entry, pos end
    end
end

function GSD:CurrentPage()
    local entry, pos = self:FindPage(db.currentPage)
    if not entry then
        entry, pos = self:GetFlatPages()[1], 1
        db.currentPage = entry.page.id
    end
    return entry, pos
end

function GSD:SaveNotes()
    if self.editingPage then self.editingPage.text = self.notesEdit:GetText() end
end

function GSD:ShowPage(id)
    db.currentPage = id
    if not self.frame then return end
    self:SaveNotes()
    local entry = self:CurrentPage()
    self.editingPage = entry.page
    self.notesEdit:SetText(entry.page.text)
    self.notesEdit:SetCursorPosition(0)
    self.notesScroll:SetVerticalScroll(0)
    self:UpdatePageNav()
end

function GSD:StepPage(delta)
    local flat = self:GetFlatPages()
    local _, pos = self:CurrentPage()
    local target = flat[pos + delta]
    if target then self:ShowPage(target.page.id) end
end

function GSD:UpdatePageNav()
    local flat = self:GetFlatPages()
    local entry, pos = self:CurrentPage()
    -- Breadcrumb: walk back through the depth-first list to collect ancestors
    local path, depth = entry.page.title, entry.depth
    for i = pos - 1, 1, -1 do
        if flat[i].depth < depth then
            path = flat[i].page.title .. " / " .. path
            depth = flat[i].depth
        end
    end
    self.pageTitle:SetText(path)
    self.prevPage:SetEnabled(pos > 1)
    self.nextPage:SetEnabled(pos < #flat)
end

local function PromptName(prompt, default, callback)
    StaticPopup_Show("GSDLIST_NAME", prompt, nil, { default = default, callback = callback })
end

function GSD:AddPage(asChild)
    local entry = self:CurrentPage()
    PromptName(asChild and "Name of the new sub-note:" or "Name of the new page:", "", function(title)
        title = strtrim(title or "")
        local page = NewPage(title ~= "" and title or "Untitled")
        if asChild then
            tinsert(entry.page.children, page)
        else
            -- Look the position up again: pages may have moved while the popup was open
            local index = IndexOf(entry.siblings, entry.page) or #entry.siblings
            tinsert(entry.siblings, index + 1, page)
        end
        self:PagesChanged()
        self:ShowPage(page.id)
    end)
end

function GSD:RenamePage()
    local page = self:CurrentPage().page
    PromptName("Rename page:", page.title, function(title)
        title = strtrim(title or "")
        if title ~= "" then page.title = title end
        self:UpdatePageNav()
    end)
end

function GSD:MovePage(delta)
    local entry = self:CurrentPage()
    local list, from = entry.siblings, entry.index
    local to = from + delta
    if to < 1 or to > #list then return end
    list[from], list[to] = list[to], list[from]
    self:PagesChanged()
    self:UpdatePageNav()
end

function GSD:DeletePage()
    if #self:GetFlatPages() <= 1 then return end
    local entry = self:CurrentPage()
    local page = entry.page
    local function Delete()
        local list = entry.siblings
        local index = IndexOf(list, page)
        if not index then return end
        self:SaveNotes()
        tremove(list, index)
        self:PagesChanged()
        self:PushUndo({ kind = "page", page = page, siblings = list, index = index,
            label = "delete page \"" .. page.title .. "\"" })
        local nextPage = list[index] or list[index - 1]
        self.editingPage = nil
        self:ShowPage(nextPage and nextPage.id or self:GetFlatPages()[1].page.id)
    end
    local message = "Delete the page \"" .. page.title .. "\""
    if #page.children > 0 then message = message .. " and everything nested under it" end
    StaticPopup_Show("GSDLIST_CONFIRM", message .. "?", nil, { onAccept = Delete })
end

--------------------------------------------------------------------------------
-- Undo (this session only)
--------------------------------------------------------------------------------

function GSD:PushUndo(action)
    local stack = self.undo
    stack[#stack + 1] = action
    if #stack > UNDO_LIMIT then tremove(stack, 1) end
    self:UpdateUndoButton()
end

function GSD:Undo()
    local action = tremove(self.undo)
    if not action then
        Print("Nothing to undo.")
        return
    end
    local todos = db.todos
    if action.kind == "task" then
        tinsert(todos, min(action.index, #todos + 1), action.item)
        self:SelectTab("todo")
    elseif action.kind == "add" then
        local i = IndexOf(todos, action.item)
        if i then tremove(todos, i) end
    elseif action.kind == "move" then
        local i = IndexOf(todos, action.item)
        if i then
            tremove(todos, i)
            tinsert(todos, min(action.from, #todos + 1), action.item)
        end
    elseif action.kind == "page" then
        tinsert(action.siblings, min(action.index, #action.siblings + 1), action.page)
        self:PagesChanged()
        self:ShowPage(action.page.id)
        self:SelectTab("notes")
    end
    self:RefreshTodos()
    self:UpdateUndoButton()
end

function GSD:UpdateUndoButton()
    if not self.frame then return end
    local enabled = #self.undo > 0
    self.undoButton:SetEnabled(enabled)
    self.undoButton:GetNormalTexture():SetDesaturated(not enabled)
    self.undoButton:SetAlpha(enabled and 1 or 0.4)
end

--------------------------------------------------------------------------------
-- Popups (the game's own StaticPopup dialogs)
--------------------------------------------------------------------------------

local function PopupEditBox(dialog)
    return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

StaticPopupDialogs.GSDLIST_CONFIRM = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) data.onAccept() end,
    OnCancel = function(_, data) if data and data.onCancel then data.onCancel() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs.GSDLIST_NAME = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    OnShow = function(dialog, data)
        local editBox = PopupEditBox(dialog)
        editBox:SetMaxLetters(MAX_TITLE_LETTERS)
        editBox:SetText(data.default or "")
        editBox:HighlightText()
        editBox:SetFocus()
    end,
    OnAccept = function(dialog, data) data.callback(PopupEditBox(dialog):GetText()) end,
    EditBoxOnEnterPressed = function(editBox, data)
        data.callback(editBox:GetText())
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Small shared widgets
--------------------------------------------------------------------------------

local function ButtonOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local tip = self.tooltip
    if type(tip) == "function" then tip = tip(self) end
    GameTooltip:SetText(tip, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function ButtonOnLeave(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function IconButton(parent, texture, size, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture(HIGHLIGHT, "ADD")
    b.tooltip = tooltip
    b:SetScript("OnEnter", ButtonOnEnter)
    b:SetScript("OnLeave", ButtonOnLeave)
    return b
end

local function ArrowButton(parent, which, tooltip)
    local prefix = "Interface\\Buttons\\UI-SpellbookIcon-" .. which
    local b = IconButton(parent, prefix .. "-Up", 18, tooltip)
    b:SetPushedTexture(prefix .. "-Down")
    b:SetDisabledTexture(prefix .. "-Disabled")
    return b
end

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetText(text)
    return b
end

local function MakeScrollArea(parent, name)
    local inset = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    inset:SetBackdrop(INSET_BACKDROP)
    inset:SetBackdropColor(0, 0, 0, 0.6)
    inset:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    local scroll = CreateFrame("ScrollFrame", name, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -25, 4)
    return inset, scroll
end

--------------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------------

local function WindowOnDragStart(self)
    if not db.locked then self:StartMoving() end
end

local function WindowOnDragStop(self)
    self:StopMovingOrSizing()
    GSD:SavePosition()
end

function GSD:CreateMainFrame()
    local f = CreateFrame("Frame", "GSDListFrame", UIParent, BACKDROP_TEMPLATE)
    f:Hide()
    f:SetSize(max(db.width, MIN_WIDTH), max(db.height, MIN_HEIGHT))
    f:SetFrameStrata("HIGH") -- below popups and menus, which use DIALOG and above
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_SIZE, MAX_SIZE)
    else
        f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        f:SetMaxResize(MAX_SIZE, MAX_SIZE)
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", WindowOnDragStart)
    f:SetScript("OnDragStop", WindowOnDragStop)
    f:SetBackdrop(WINDOW_BACKDROP)
    tinsert(UISpecialFrames, "GSDListFrame") -- close with Escape
    self.frame = f

    self.notesFont = CreateFont("GSDListNotesFont")
    self.notesFont:SetFontObject(ChatFontNormal)
    self.taskFont = CreateFont("GSDListTaskFont")
    self.taskFont:SetFontObject(GameFontHighlight)

    -- Header banner, sized to the title like the game's own small dialogs
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -2)
    title:SetText("GSD List")
    local header = "Interface\\DialogFrame\\UI-DialogBox-Header"
    local mid = f:CreateTexture(nil, "ARTWORK")
    mid:SetTexture(header)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", 0, 10)
    mid:SetSize(title:GetStringWidth() + 10, 32)
    local left = f:CreateTexture(nil, "ARTWORK")
    left:SetTexture(header)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetSize(24, 32)
    local right = f:CreateTexture(nil, "ARTWORK")
    right:SetTexture(header)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetSize(24, 32)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)

    local lock = IconButton(f, "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", 14, function()
        return db.locked and "Unlock window" or "Lock window (stops moving and resizing)"
    end)
    lock:SetPoint("RIGHT", close, "LEFT", 0, 0)
    lock:SetScript("OnClick", function() GSD:SetLocked(not db.locked) end)
    self.lockButton = lock

    local settings = IconButton(f, "Interface\\WorldMap\\GEAR_64GREY", 16, "Settings")
    settings:SetPoint("TOPLEFT", 8, -6)
    settings:SetScript("OnClick", function(b) GSD:OpenSettingsMenu(b) end)

    -- Tab row
    self.tabs = {}
    self.tabs.notes = SmallButton(f, "Notes", 50)
    self.tabs.notes:SetPoint("TOPLEFT", 8, -25)
    self.tabs.todo = SmallButton(f, "To-Do", 66)
    self.tabs.todo:SetPoint("LEFT", self.tabs.notes, "RIGHT", 2, 0)
    for key, tab in pairs(self.tabs) do
        tab:SetScript("OnClick", function() GSD:SelectTab(key) end)
    end

    local undo = IconButton(f, "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo", 18, function()
        local action = GSD.undo[#GSD.undo]
        return action and ("Undo " .. action.label) or "Nothing to undo"
    end)
    undo:SetPoint("TOPRIGHT", -9, -25)
    undo:SetScript("OnClick", function() GSD:Undo() end)
    self.undoButton = undo

    -- Content area shared by both pages
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 8, -45)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    self.content = content

    -- Resize grip, sitting on the bottom-right corner of the border
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(content:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() if not db.locked then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        db.width, db.height = f:GetSize()
        GSD:SavePosition()
    end)
    self.grip = grip

    self:CreateNotesPage()
    self:CreateTodoPage()
    self:RestorePosition()

    f:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        GSD:EndDrag(false)
        GSD:CloseSearch(false)
        GSD.notesEdit:ClearFocus() -- also saves the notes
        GSD.todoInput:ClearFocus()
    end)

    self:ApplyTextSize()
    self:SetLocked(db.locked)
    self.tabs.todo:SetShown(db.todoEnabled)
    self:ShowPage(db.currentPage)
    self:RefreshTodos()
    self:UpdateUndoButton()
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

function GSD:ResetPosition()
    db.point, db.width, db.height = nil, DEFAULTS.width, DEFAULTS.height
    if self.frame then
        self.frame:SetSize(db.width, db.height)
        self:RestorePosition()
    end
    db.minimap.angle = DEFAULTS.minimap.angle
    self:UpdateMinimapPosition()
end

function GSD:SetLocked(locked)
    db.locked = locked
    if not self.frame then return end
    self.grip:SetShown(not locked)
    self.lockButton:GetNormalTexture():SetDesaturated(not locked)
    self.lockButton:SetAlpha(locked and 1 or 0.5)
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
    if key == "notes" then
        self.todoInput:ClearFocus()
    else
        self:CloseSearch(false)
        self.notesEdit:ClearFocus()
    end
end

function GSD:SetTodoEnabled(enabled)
    db.todoEnabled = enabled
    if self.frame then self.tabs.todo:SetShown(enabled) end
    self:SelectTab(enabled and db.activeTab or "notes")
end

function GSD:SetMinimapShown(shown)
    db.minimap.hide = not shown
    self.minimapButton:SetShown(shown)
end

function GSD:SetTextSize(size)
    db.textSize = size
    self:ApplyTextSize()
end

function GSD:ApplyTextSize()
    if not self.frame then return end
    local size = db.textSize
    local file, _, flags = ChatFontNormal:GetFont()
    self.notesFont:SetFont(file, size, flags)
    file, _, flags = GameFontHighlight:GetFont()
    self.taskFont:SetFont(file, size, flags)
    self.rowHeight = size + 8
    for i, row in ipairs(self.rows) do self:LayoutRow(row, i) end
    self:RefreshTodos()
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

local function OpenMenu(owner, generator)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, generator)
    end
end

local function CloseMenu() return MenuResponse and MenuResponse.Close end

function GSD.OpenSettingsMenu(_, owner)
    OpenMenu(owner, function(_, root)
        root:CreateTitle("GSD List")
        root:CreateCheckbox("Enable to-do list", function() return db.todoEnabled end,
            function() GSD:SetTodoEnabled(not db.todoEnabled) end)
        root:CreateCheckbox("Confirm completing tasks", function() return db.confirmComplete end,
            function() db.confirmComplete = not db.confirmComplete end)
        root:CreateCheckbox("Lock window", function() return db.locked end,
            function() GSD:SetLocked(not db.locked) end)
        root:CreateCheckbox("Show minimap button", function() return not db.minimap.hide end,
            function() GSD:SetMinimapShown(db.minimap.hide) end)
        local sizes = root:CreateButton("Text size")
        for _, s in ipairs(TEXT_SIZES) do
            sizes:CreateRadio(s[2], function(size) return db.textSize == size end,
                function(size) GSD:SetTextSize(size) end, s[1])
        end
        root:CreateDivider()
        root:CreateButton("Reset position", function() GSD:ResetPosition() end)
    end)
end

function GSD:OpenPageMenu(owner)
    local flat = self:GetFlatPages()
    local entry = self:CurrentPage()
    OpenMenu(owner, function(_, root)
        root:CreateTitle("Pages")
        for _, e in ipairs(flat) do
            root:CreateRadio(strrep("    ", e.depth) .. e.page.title,
                function(id) return id == db.currentPage end,
                function(id) GSD:ShowPage(id); return CloseMenu() end, e.page.id)
        end
        if #flat > 20 and root.SetScrollMode then root:SetScrollMode(400) end
        root:CreateDivider()
        root:CreateButton("New page", function() GSD:AddPage(false) end)
        root:CreateButton("New sub-note", function() GSD:AddPage(true) end):SetEnabled(entry.depth < MAX_DEPTH - 1)
        root:CreateButton("Rename", function() GSD:RenamePage() end)
        root:CreateButton("Move up", function() GSD:MovePage(-1) end):SetEnabled(entry.index > 1)
        root:CreateButton("Move down", function() GSD:MovePage(1) end):SetEnabled(entry.index < #entry.siblings)
        root:CreateButton("Delete", function() GSD:DeletePage() end):SetEnabled(#flat > 1)
    end)
end

--------------------------------------------------------------------------------
-- Notes page
--------------------------------------------------------------------------------

-- Keeps the cursor in view. Runs only while the box has focus, or for a few
-- frames after a search moves the cursor; there is no per-frame work otherwise.
local function NotesOnUpdate(self, elapsed)
    ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
    if not self:HasFocus() then
        self.followFrames = (self.followFrames or 0) - 1
        if self.followFrames <= 0 then self:SetScript("OnUpdate", nil) end
    end
end

local function FollowCursor(edit)
    edit.followFrames = 5
    edit:SetScript("OnUpdate", NotesOnUpdate)
end

function GSD:CreateNotesPage()
    local page = CreateFrame("Frame", nil, self.content)
    page:SetAllPoints()

    -- Page row: arrows, page title and search. The search bar reuses the same row.
    local nav = CreateFrame("Frame", nil, page)
    nav:SetPoint("TOPLEFT")
    nav:SetPoint("TOPRIGHT")
    nav:SetHeight(18)

    local prev = ArrowButton(nav, "PrevPage", "Previous page")
    prev:SetPoint("LEFT", -2, 0)
    prev:SetScript("OnClick", function() GSD:StepPage(-1) end)
    local search = IconButton(nav, "Interface\\Common\\UI-Searchbox-Icon", 14, "Search all notes")
    search:SetPoint("RIGHT", -2, 0)
    search:SetScript("OnClick", function() GSD:OpenSearch() end)
    local nextPage = ArrowButton(nav, "NextPage", "Next page")
    nextPage:SetPoint("RIGHT", search, "LEFT", 0, 0)
    nextPage:SetScript("OnClick", function() GSD:StepPage(1) end)

    local titleButton = CreateFrame("Button", nil, nav)
    titleButton:SetPoint("LEFT", prev, "RIGHT", 0, 0)
    titleButton:SetPoint("RIGHT", nextPage, "LEFT", 0, 0)
    titleButton:SetHeight(18)
    titleButton:SetHighlightTexture(HIGHLIGHT, "ADD")
    titleButton.tooltip = function()
        return GSD.pageTitle:GetText() .. "\n|cffffd100Click for pages: switch, add, nest, rename, delete|r"
    end
    titleButton:SetScript("OnEnter", ButtonOnEnter)
    titleButton:SetScript("OnLeave", ButtonOnLeave)
    titleButton:SetScript("OnClick", function(b) GSD:OpenPageMenu(b) end)
    local pageTitle = titleButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    pageTitle:SetAllPoints()
    pageTitle:SetWordWrap(false)

    local searchRow = CreateFrame("Frame", nil, page)
    searchRow:SetAllPoints(nav)
    searchRow:Hide()
    local closeSearch = IconButton(searchRow, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 18, "Close search")
    closeSearch:SetPoint("RIGHT", 0, 0)
    closeSearch:SetScript("OnClick", function() GSD:CloseSearch(true) end)
    local matchCount = searchRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    matchCount:SetPoint("RIGHT", closeSearch, "LEFT", -2, 0)
    local searchBox = CreateFrame("EditBox", "GSDListSearchBox", searchRow, "SearchBoxTemplate")
    searchBox:SetHeight(18)
    searchBox:SetPoint("LEFT", 6, 0)
    searchBox:SetPoint("RIGHT", matchCount, "LEFT", -4, 0)
    searchBox:HookScript("OnTextChanged", function() GSD:RunSearch() end)
    searchBox:SetScript("OnEnterPressed", function()
        GSD:GoToMatch(GSD.matchIndex + (IsShiftKeyDown() and -1 or 1))
    end)
    searchBox:SetScript("OnEscapePressed", function() GSD:CloseSearch(true) end)

    local inset, scroll = MakeScrollArea(page, "GSDListNotesScroll")
    inset:SetPoint("TOPLEFT", 0, -20)
    inset:SetPoint("BOTTOMRIGHT")

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(self.notesFont)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetWidth(max(scroll:GetWidth(), 100))
    ScrollingEdit_SetCursorOffsets(edit, 0, 0) -- required before ScrollingEdit_OnUpdate runs
    scroll:SetScrollChild(edit)
    scroll:HookScript("OnSizeChanged", function(_, w) edit:SetWidth(w) end)

    -- Clicking anywhere in the box (below the last line) focuses the editor
    inset:EnableMouse(true)
    inset:SetScript("OnMouseDown", function() edit:SetFocus() end)

    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
    edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    edit:SetScript("OnEditFocusGained", function(self) self:SetScript("OnUpdate", NotesOnUpdate) end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetScript("OnUpdate", nil)
        GSD:SaveNotes()
    end)

    self.notesPage = page
    self.notesEdit = edit
    self.notesScroll = scroll
    self.pageTitle = pageTitle
    self.prevPage, self.nextPage = prev, nextPage
    self.navRow, self.searchRow = nav, searchRow
    self.searchBox, self.matchCount = searchBox, matchCount
    self.matches, self.matchIndex = {}, 0
end

--------------------------------------------------------------------------------
-- Search across every note page
--------------------------------------------------------------------------------

function GSD:OpenSearch(query)
    self.navRow:Hide()
    self.searchRow:Show()
    self.searching = true
    if query then self.searchBox:SetText(query) end
    self.searchBox:SetFocus()
    self:RunSearch()
end

-- land: put the cursor on the current match so you can start editing there
function GSD:CloseSearch(land)
    if not self.searching then return end
    self.searching = false
    local match = self.matches[self.matchIndex]
    self.searchRow:Hide()
    self.navRow:Show()
    self.searchBox:ClearFocus()
    self.matches, self.matchIndex = {}, 0
    if land and match then
        local edit = self.notesEdit
        edit:SetFocus()
        edit:SetCursorPosition(match.stop)
        edit:HighlightText(match.start - 1, match.stop)
    end
end

function GSD:RunSearch()
    if not self.searching then return end
    self:SaveNotes()
    local query = strlower(self.searchBox:GetText() or "")
    local matches, first = {}, nil
    if query ~= "" then
        local _, currentPos = self:CurrentPage()
        for pos, entry in ipairs(self:GetFlatPages()) do
            local text, init = strlower(entry.page.text), 1
            while #matches < MAX_MATCHES do
                local s, e = strfind(text, query, init, true)
                if not s then break end
                matches[#matches + 1] = { id = entry.page.id, start = s, stop = e }
                if not first and pos >= currentPos then first = #matches end
                init = e + 1
            end
        end
    end
    self.matches = matches
    self:GoToMatch(first or 1)
end

function GSD:GoToMatch(index)
    local matches = self.matches
    local n = #matches
    if n == 0 then
        self.matchIndex = 0
        self.matchCount:SetText(self.searchBox:GetText() == "" and "" or "|cffff20200/0|r")
        return
    end
    index = (index - 1) % n + 1
    self.matchIndex = index
    local match = matches[index]
    if match.id ~= self.editingPage.id then self:ShowPage(match.id) end
    local edit = self.notesEdit
    edit:SetCursorPosition(match.stop)
    edit:HighlightText(match.start - 1, match.stop)
    FollowCursor(edit)
    self.matchCount:SetFormattedText("%d/%d", index, n)
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

    local add = SmallButton(page, "Add", 38)
    add:SetPoint("TOPRIGHT", 0, 0)
    add:SetScript("OnClick", function()
        SubmitTodo(GSD.todoInput)
        GSD.todoInput:SetFocus()
    end)

    local input = CreateFrame("EditBox", "GSDListTodoInput", page, "InputBoxTemplate")
    input:SetHeight(18)
    input:SetPoint("TOPLEFT", 6, 0)
    input:SetPoint("RIGHT", add, "LEFT", -4, 0)
    input:SetAutoFocus(false)
    input:SetFontObject(ChatFontSmall)
    input:SetMaxLetters(MAX_TODO_LETTERS)
    input:SetScript("OnEnterPressed", SubmitTodo)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local inset, scroll = MakeScrollArea(page, "GSDListTodoScroll")
    inset:SetPoint("TOPLEFT", 0, -20)
    inset:SetPoint("BOTTOMRIGHT")

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(max(scroll:GetWidth(), 100), 1)
    scroll:SetScrollChild(list)
    scroll:HookScript("OnSizeChanged", function(_, w) list:SetWidth(w) end)

    -- Gold line showing where a dragged task will land
    local marker = list:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(1, 0.82, 0, 1)
    marker:SetHeight(2)
    marker:Hide()

    local empty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 8, -8)
    empty:SetPoint("RIGHT", -8, 0)
    empty:SetText("No tasks. Type one above and press Enter.\nDrag tasks to reorder them.")

    self.todoPage = page
    self.todoInput = input
    self.todoScroll = scroll
    self.todoList = list
    self.dropMarker = marker
    self.todoEmpty = empty
    self.rows = {}
    self.rowHeight = db.textSize + 8
end

function GSD:CompleteTodo(item)
    local i = IndexOf(db.todos, item)
    if not i then return end
    tremove(db.todos, i)
    item.done = false
    self:PushUndo({ kind = "task", item = item, index = i, label = "complete \"" .. item.text .. "\"" })
    self:RefreshTodos()
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
    if not check:GetChecked() then
        item.done = false
        GSD:RefreshTodos()
    elseif db.confirmComplete then
        StaticPopup_Show("GSDLIST_CONFIRM", "Mark this task as complete?\n\n" .. item.text, nil, {
            onAccept = function() GSD:CompleteTodo(item) end,
            onCancel = function() GSD:RefreshTodos() end,
        })
    else
        -- Stays visible briefly so the click registers and can be undone by unticking
        item.done = true
        GSD:RefreshTodos()
        C_Timer.After(COMPLETE_DELAY, function() if item.done then GSD:CompleteTodo(item) end end)
    end
end

local function DeleteOnClick(button)
    local index = button:GetParent().index
    local item = tremove(db.todos, index)
    if item then
        GSD:PushUndo({ kind = "task", item = item, index = index, label = "delete \"" .. item.text .. "\"" })
    end
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
    return min(max(floor(offset / self.rowHeight + 0.5) + 1, 1), #db.todos + 1)
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
    self.dropMarker:SetPoint("TOPLEFT", self.todoList, "TOPLEFT", 0, -(slot - 1) * self.rowHeight)
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
    local from = IndexOf(todos, item)
    if from then
        local to = min(self.dropSlot, #todos + 1)
        if to > from then to = to - 1 end
        if to ~= from then
            tremove(todos, from)
            tinsert(todos, to, item)
            self:PushUndo({ kind = "move", item = item, from = from, label = "move \"" .. item.text .. "\"" })
        end
    end
    self:RefreshTodos()
end

local function RowOnDragStop() GSD:EndDrag(true) end

function GSD:LayoutRow(row, i)
    local h = self.rowHeight
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
    row.check:SetSize(h, h)
    row.delete:SetSize(h - 2, h - 2)
end

function GSD:GetRow(i)
    local row = self.rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, self.todoList)
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
    check:SetPoint("LEFT", 0, 0)
    check:SetScript("OnClick", CheckOnClick)

    local del = CreateFrame("Button", nil, row)
    del:SetPoint("RIGHT", 0, 0)
    del:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    del:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    del:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    del:SetScript("OnClick", DeleteOnClick)

    local text = row:CreateFontString(nil, "ARTWORK")
    text:SetFontObject(self.taskFont)
    text:SetPoint("LEFT", check, "RIGHT", 1, 0)
    text:SetPoint("RIGHT", del, "LEFT", -1, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    row.hl, row.check, row.delete, row.text = hl, check, del, text
    self:LayoutRow(row, i)
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
    self.todoList:SetHeight(max(1, n * self.rowHeight))
    self.todoEmpty:SetShown(n == 0)
    self.tabs.todo:SetText(n > 0 and ("To-Do (" .. n .. ")") or "To-Do")
end

function GSD:AddTodo(text)
    text = text and strtrim(text)
    if not text or text == "" then return end
    local item = { text = text, done = false }
    tinsert(db.todos, item)
    self:PushUndo({ kind = "add", item = item, label = "add \"" .. text .. "\"" })
    self:RefreshTodos()
    return item
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
-- Slash commands, including quick add from chat
--------------------------------------------------------------------------------

local HELP = {
    "/gsd - toggle the window",
    "/gsd add <task> - add a to-do task (item links work)",
    "/gsd note <text> - add a line to the current note page",
    "/gsd search <text> - search all notes",
    "/gsd undo - undo the last change",
    "/gsd lock - lock or unlock the window",
    "/gsd todo - enable/disable the to-do list",
    "/gsd minimap - show/hide the minimap button",
    "/gsd reset - reset window and button positions",
}

local COMMANDS = {}

COMMANDS[""] = function() GSD:Toggle() end

COMMANDS.add = function(text)
    local item = GSD:AddTodo(text)
    if not item then
        Print("Usage: /gsd add <task>")
        return
    end
    Print("Added task: " .. item.text .. (db.todoEnabled and "" or " (the to-do list is turned off: /gsd todo)"))
end

COMMANDS.note = function(text)
    if text == "" then
        Print("Usage: /gsd note <text>")
        return
    end
    if GSD.frame then GSD:SaveNotes() end
    local page = GSD:CurrentPage().page
    page.text = page.text == "" and text or (page.text .. "\n" .. text)
    if GSD.editingPage == page then GSD.notesEdit:SetText(page.text) end
    Print("Added to note page \"" .. page.title .. "\".")
end

COMMANDS.search = function(text)
    if not GSD.frame then GSD:CreateMainFrame() end
    GSD:SelectTab("notes")
    GSD.frame:Show()
    GSD:OpenSearch(text)
end

COMMANDS.undo = function() GSD:Undo() end

COMMANDS.lock = function()
    GSD:SetLocked(not db.locked)
    Print("Window " .. (db.locked and "locked." or "unlocked."))
end

COMMANDS.todo = function()
    GSD:SetTodoEnabled(not db.todoEnabled)
    Print("To-Do list " .. (db.todoEnabled and "enabled." or "disabled."))
end

COMMANDS.minimap = function()
    GSD:SetMinimapShown(db.minimap.hide)
    Print("Minimap button " .. (db.minimap.hide and "hidden." or "shown."))
end

COMMANDS.reset = function()
    GSD:ResetPosition()
    Print("Window and minimap button positions reset.")
end

SLASH_GSDLIST1 = "/gsd"
SLASH_GSDLIST2 = "/gsdlist"
SlashCmdList.GSDLIST = function(msg)
    local cmd, rest = strmatch(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    local handler = COMMANDS[strlower(cmd)]
    if handler then
        handler(rest)
    else
        Print("Commands:")
        for _, line in ipairs(HELP) do Print("  " .. line) end
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
        LoadDatabase()
        GSD:CreateMinimapButton()
        HookLinks()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGOUT")
    elseif event == "PLAYER_LOGOUT" then
        -- Notes still being typed (box focused) at /reload or logout
        if GSD.frame then GSD:SaveNotes() end
    end
end)
