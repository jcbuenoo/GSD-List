-- Offline test suite for GSD List.
-- Runs the addon against a mocked WoW API: lua5.1 tests/run_tests.lua
-- It checks logic and wiring, not rendering, so it does not replace an in-game check.

local ADDON_FILE = arg[1] or "GSDList/GSDList.lua"

--------------------------------------------------------------------------------
-- Mock WoW API
--------------------------------------------------------------------------------

local created, focused
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
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:SetWidth(w) self.w = w end
function Widget:SetHeight(h) self.h = h end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:GetSize() return self.w, self.h end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() self.points = {} end
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
function Widget:CreateFontString() return NewWidget("FontString", nil, self) end
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
function Widget:SetFont(file, size, flags) self.font = { file, size, flags } end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end

function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name, parent)
    w.template = template
    if template == "UICheckButtonTemplate" then w.Text = NewWidget("FontString", nil, w) end
    return w
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

local function ResetEnvironment()
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

local function Load(savedVariables)
    ResetEnvironment()
    GSDListDB = savedVariables
    local chunk = assert(loadfile(ADDON_FILE))
    chunk("GSDList", {})
    local loader = created[#created]
    loader:Fire("OnEvent", "ADDON_LOADED", "SomeOtherAddon")
    assert(GSDListDB == savedVariables, "reacted to another addon's ADDON_LOADED")
    loader:Fire("OnEvent", "ADDON_LOADED", "GSDList")
    return loader
end

--------------------------------------------------------------------------------
-- Test runner and helpers
--------------------------------------------------------------------------------

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("PASS  " .. name)
    else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function Slash(msg) SlashCmdList.GSDLIST(msg) end
local function Open() if not (rawget(_G, "GSDListFrame") and GSDListFrame.shown) then Slash("") end end
local function Input() return GSDListTodoInput end
local function AddViaInput(text) Input():SetText(text); Input():Fire("OnEnterPressed") end
local function Find(pred) for _, w in ipairs(created) do if pred(w) then return w end end end
local function Row(i)
    return Find(function(w) return w.kind == "Frame" and w.index == i and w.shown end)
end
local function RowButtons(row)
    local check, buttons = nil, {}
    for _, w in ipairs(created) do
        if w.parent == row then
            if w.kind == "CheckButton" then check = w elseif w.kind == "Button" then buttons[#buttons + 1] = w end
        end
    end
    return check, buttons[1], #buttons -- check, delete, button count
end
local function Notes() return Find(function(w) return w.kind == "EditBox" and w.template == nil end) end
local function Button(text) return Find(function(w) return w.kind == "Button" and w.text == text end) end
local function IconButton(file)
    return Find(function(w) return w.kind == "Button" and w.normal and w.normal.file == file end)
end
local function TodoList()
    return Find(function(w) return w.kind == "Frame" and w.parent == GSDListTodoScroll end)
end
local function Texts(db)
    local t = {}
    for i, v in ipairs(db.todos) do t[i] = v.text end
    return table.concat(t, ",")
end
local function Tick(i)
    local check = RowButtons(Row(i))
    check.checked = not check.checked
    check:Fire("OnClick")
end
-- Drag row `from` and drop it with the cursor `offset` pixels below the list top
local function Drag(from, offset, frames)
    local row = Row(from)
    row:Fire("OnDragStart")
    cursorY = TodoList():GetTop() - offset
    for _ = 1, frames or 1 do row:Fire("OnUpdate", 0.016) end
    row:Fire("OnDragStop")
end
local function LastPopup() return popups[#popups] end
local function MenuItem(menu, text)
    for _, node in ipairs(menu.children) do
        if node.text == text or (node.text:gsub("^%s+", "")) == text then return node end
    end
    error("menu item not found: " .. text)
end
local function Click(node)
    assert(node.enabled, "menu item disabled: " .. node.text)
    if node.kind == "button" then return node.a(node.data) end
    return node.b(node.data)
end
-- The page title is the only plain (texture-less) button with a dynamic tooltip
local function TitleButton()
    return Find(function(w) return w.kind == "Button" and w.normal == nil and type(w.tooltip) == "function" end)
end
local function PageMenu() TitleButton():Fire("OnClick"); return menus[#menus] end
local function PageTitle()
    return Find(function(w) return w.kind == "FontString" and w.parent == TitleButton() end).text
end
local function SettingsMenu()
    IconButton("Interface\\WorldMap\\GEAR_64GREY"):Fire("OnClick")
    return menus[#menus]
end
local function NewPageVia(item, name)
    Click(MenuItem(PageMenu(), item))
    LastPopup().enter(name)
end
local function PrevArrow() return IconButton("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up") end
local function NextArrow() return IconButton("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up") end
local function UndoButton() return IconButton("Interface\\PaperDollInfoFrame\\UI-GearManager-Undo") end
local function LockButton() return IconButton("Interface\\LFGFrame\\UI-LFG-ICON-LOCK") end
local function SearchFor(text)
    IconButton("Interface\\Common\\UI-Searchbox-Icon"):Fire("OnClick")
    GSDListSearchBox:SetText(text)
end
local function MatchCount()
    return Find(function(w) return w.kind == "FontString" and w.parent == GSDListSearchBox.parent end).text
end
local function Pages(db)
    local out = {}
    local function walk(list, depth)
        for _, p in ipairs(list) do
            out[#out + 1] = string.rep(">", depth) .. p.title
            walk(p.children, depth + 1)
        end
    end
    walk(db.pages, 0)
    return table.concat(out, ",")
end

--------------------------------------------------------------------------------
-- Tests: load and saved data
--------------------------------------------------------------------------------

test("fresh install creates defaults and a first page", function()
    Load(nil)
    eq(type(GSDListDB), "table"); eq(#GSDListDB.todos, 0)
    eq(Pages(GSDListDB), "Notes"); eq(GSDListDB.pages[1].text, "")
    eq(GSDListDB.todoEnabled, true); eq(GSDListDB.confirmComplete, true); eq(GSDListDB.locked, false)
    eq(GSDListDB.textSize, 12); eq(GSDListDB.minimap.angle, 200)
    eq(SLASH_GSDLIST1, "/gsd")
end)

test("window is built lazily (only the minimap button exists at login)", function()
    Load(nil)
    eq(rawget(_G, "GSDListFrame"), nil, "main frame")
    assert(GSDListMinimapButton, "minimap button missing")
    local frames = 0
    for _, w in ipairs(created) do
        if (w.kind == "Frame" or w.kind == "Button") and w ~= UIParent and w ~= Minimap then frames = frames + 1 end
    end
    eq(frames, 2, "frames at login (minimap button + event frame)")
end)

test("1.x notes are migrated into the first page", function()
    Load({ notes = "old notes", todos = { { text = "a" } } })
    eq(Pages(GSDListDB), "Notes"); eq(GSDListDB.pages[1].text, "old notes"); eq(GSDListDB.notes, nil)
    Open()
    eq(Notes():GetText(), "old notes")
end)

test("corrupted saved variables are repaired", function()
    Load({ todos = { "bad", { text = "" }, { text = "keep" }, { done = true }, { text = "old", done = true } },
        pages = { "bad", { title = 5, text = 7, children = "x", id = "y" }, { id = 3, title = "B" },
            { id = 3, title = "dup" } },
        minimap = { angle = "x" }, activeTab = "bogus", textSize = "big", nextPageId = "z" })
    eq(Texts(GSDListDB), "keep")
    eq(Pages(GSDListDB), "Untitled,B,dup")
    local ids = {}
    for _, p in ipairs(GSDListDB.pages) do
        assert(type(p.id) == "number" and not ids[p.id], "bad or duplicate id"); ids[p.id] = true
        eq(type(p.text), "string"); eq(type(p.children), "table")
    end
    assert(GSDListDB.nextPageId > 3, "nextPageId not past existing ids")
    eq(GSDListDB.minimap.angle, 200); eq(GSDListDB.textSize, 12)
    Open()
    eq(GSDListDB.activeTab, "notes")
end)

test("/gsd toggles the window, Escape is registered", function()
    Load(nil)
    Slash(""); eq(GSDListFrame:IsShown(), true)
    Slash(""); eq(GSDListFrame:IsShown(), false)
    eq(UISpecialFrames[1], "GSDListFrame")
end)

--------------------------------------------------------------------------------
-- Tests: size, lock, settings
--------------------------------------------------------------------------------

test("window can shrink to 200x150", function()
    Load({ width = 100, height = 50 })
    Open()
    local b = GSDListFrame.bounds
    eq(b[1], 200); eq(b[2], 150)
    eq(GSDListFrame.w, 200, "saved width below the minimum is clamped")
    eq(GSDListFrame.h, 150)
end)

test("default size is compact", function()
    Load(nil)
    Open()
    eq(GSDListFrame.w, 300); eq(GSDListFrame.h, 340)
end)

test("lock stops moving and resizing, and persists", function()
    Load(nil)
    Open()
    local grip = IconButton("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    GSDListFrame:Fire("OnDragStart"); eq(GSDListFrame.moving, true); GSDListFrame:Fire("OnDragStop")
    LockButton():Fire("OnClick")
    eq(GSDListDB.locked, true); eq(grip.shown, false)
    GSDListFrame:Fire("OnDragStart"); assert(not GSDListFrame.moving, "moved while locked")
    grip:Fire("OnMouseDown"); assert(not GSDListFrame.sizing, "resized while locked")
    Slash("lock"); eq(GSDListDB.locked, false); eq(grip.shown, true)
    assert(chatLog[#chatLog]:find("unlocked"), "no chat confirmation")
    Load({ locked = true }); Open()
    GSDListFrame:Fire("OnDragStart"); assert(not GSDListFrame.moving, "lock not restored on load")
end)

test("settings menu toggles every option", function()
    Load(nil)
    Open()
    local menu = SettingsMenu()
    Click(MenuItem(menu, "Confirm completing tasks")); eq(GSDListDB.confirmComplete, false)
    Click(MenuItem(menu, "Lock window")); eq(GSDListDB.locked, true)
    eq(MenuItem(menu, "Lock window").a(), true, "checkbox state reader")
    Click(MenuItem(menu, "Show minimap button")); eq(GSDListMinimapButton.shown, false)
    Click(MenuItem(menu, "Enable to-do list")); eq(GSDListDB.todoEnabled, false)
    Click(MenuItem(menu, "Reset position")); eq(GSDListDB.point, nil)
end)

test("text size changes fonts and task row height", function()
    Load(nil)
    Open()
    AddViaInput("a"); AddViaInput("b")
    local large
    for _, n in ipairs(MenuItem(SettingsMenu(), "Text size").children) do
        if n.text == "Large" then large = n end
    end
    Click(large)
    eq(GSDListDB.textSize, 14)
    eq(GSDListNotesFont.font[2], 14); eq(GSDListTaskFont.font[2], 14)
    eq(Row(2).h, 22)
    local p = Row(2).points[#Row(2).points]
    eq(p[3], -22, "row not re-anchored")
    Load({ textSize = 10 }); Open(); AddViaInput("x"); eq(Row(1).h, 18)
end)

--------------------------------------------------------------------------------
-- Tests: note pages
--------------------------------------------------------------------------------

test("notes save on focus loss, on hide, and on logout", function()
    local loader = Load(nil)
    Open()
    local edit = Notes()
    edit:SetFocus(); edit.text = "Kara keys"; edit:ClearFocus()
    eq(GSDListDB.pages[1].text, "Kara keys")
    edit:SetFocus(); edit.text = "Kara keys + ZA"
    Slash("") -- hide while typing
    eq(GSDListDB.pages[1].text, "Kara keys + ZA")
    Slash(""); edit:SetFocus(); edit.text = "typed right before /reload"
    loader:Fire("OnEvent", "PLAYER_LOGOUT")
    eq(GSDListDB.pages[1].text, "typed right before /reload")
end)

test("typing in notes does not hit Blizzard's nil cursorOffset error", function()
    Load({ pages = { { id = 1, title = "P", text = "hello", children = {} } } })
    Open()
    local edit = Notes()
    edit:SetFocus(); edit:Insert(" world"); edit:Fire("OnUpdate", 0.016)
    eq(edit:GetText(), "hello world")
end)

test("add pages and nested sub-notes from the page menu", function()
    Load(nil)
    Open()
    NewPageVia("New page", "Raid")
    eq(Pages(GSDListDB), "Notes,Raid"); eq(PageTitle(), "Raid")
    NewPageVia("New sub-note", "Karazhan")
    eq(Pages(GSDListDB), "Notes,Raid,>Karazhan"); eq(PageTitle(), "Raid / Karazhan")
    NewPageVia("New sub-note", "Attunement")
    eq(PageTitle(), "Raid / Karazhan / Attunement")
    NewPageVia("New page", "  ")
    eq(Pages(GSDListDB), "Notes,Raid,>Karazhan,>>Attunement,>>Untitled")
end)

test("new page lands after its original page even if pages moved meanwhile", function()
    Load(nil)
    Open()
    NewPageVia("New page", "B")
    Click(MenuItem(PageMenu(), "New page")) -- popup open for a page after "B"
    local popup = LastPopup()
    Click(MenuItem(PageMenu(), "Move up"))  -- "B" moves above "Notes"
    popup.enter("C")
    eq(Pages(GSDListDB), "B,C,Notes")
end)

test("nesting stops at four levels", function()
    Load(nil)
    Open()
    for i = 1, 3 do NewPageVia("New sub-note", "L" .. i) end
    eq(Pages(GSDListDB), "Notes,>L1,>>L2,>>>L3")
    eq(MenuItem(PageMenu(), "New sub-note").enabled, false)
end)

test("page name popup accepts with the button, and cancel does nothing", function()
    Load(nil)
    Open()
    Click(MenuItem(PageMenu(), "New page"))
    LastPopup().accept("Gold")
    eq(Pages(GSDListDB), "Notes,Gold")
    Click(MenuItem(PageMenu(), "New page")); LastPopup().cancel()
    eq(Pages(GSDListDB), "Notes,Gold", "cancel still created a page")
end)

test("arrows walk pages depth-first and switching saves text", function()
    Load(nil)
    Open()
    Notes():SetFocus(); Notes().text = "page one"; Notes():ClearFocus()
    NewPageVia("New page", "Raid"); NewPageVia("New sub-note", "Kara"); Notes().text = "kara text"
    eq(NextArrow().enabled, false, "next at last page")
    PrevArrow():Fire("OnClick"); eq(PageTitle(), "Raid"); eq(Notes():GetText(), "")
    eq(GSDListDB.pages[2].children[1].text, "kara text", "text not saved when switching")
    PrevArrow():Fire("OnClick"); eq(PageTitle(), "Notes"); eq(Notes():GetText(), "page one")
    eq(PrevArrow().enabled, false, "prev at first page")
    NextArrow():Fire("OnClick"); NextArrow():Fire("OnClick"); eq(PageTitle(), "Raid / Kara")
end)

test("page menu lists the tree and jumps to a page", function()
    Load(nil)
    Open()
    NewPageVia("New page", "Raid"); NewPageVia("New sub-note", "Kara")
    local menu = PageMenu()
    local kara = MenuItem(menu, "Kara")
    eq(kara.text, "    Kara", "sub-notes are indented")
    eq(kara.a(kara.data), true, "current page is selected")
    eq(Click(MenuItem(menu, "Notes")), MenuResponse.Close)
    eq(PageTitle(), "Notes"); eq(GSDListDB.currentPage, GSDListDB.pages[1].id)
end)

test("rename and reorder pages", function()
    Load(nil)
    Open()
    NewPageVia("New page", "B"); NewPageVia("New page", "C")
    Click(MenuItem(PageMenu(), "Rename")); LastPopup().enter("Crafting")
    eq(Pages(GSDListDB), "Notes,B,Crafting"); eq(PageTitle(), "Crafting")
    Click(MenuItem(PageMenu(), "Rename")); LastPopup().enter("   ")
    eq(PageTitle(), "Crafting", "blank rename applied")
    eq(MenuItem(PageMenu(), "Move down").enabled, false)
    Click(MenuItem(PageMenu(), "Move up")); eq(Pages(GSDListDB), "Notes,Crafting,B")
    Click(MenuItem(PageMenu(), "Move up")); eq(Pages(GSDListDB), "Crafting,Notes,B")
    eq(MenuItem(PageMenu(), "Move up").enabled, false)
    eq(PrevArrow().enabled, false, "nav not refreshed after move")
end)

test("delete a page (with sub-notes) after confirmation, then undo", function()
    Load(nil)
    Open()
    NewPageVia("New page", "Raid"); Notes().text = "raid text"
    NewPageVia("New sub-note", "Kara")
    PrevArrow():Fire("OnClick") -- back on Raid
    Click(MenuItem(PageMenu(), "Delete"))
    assert(LastPopup().text:find("everything nested"), "no nested warning: " .. LastPopup().text)
    LastPopup().cancel(); eq(Pages(GSDListDB), "Notes,Raid,>Kara", "deleted on cancel")
    Click(MenuItem(PageMenu(), "Delete")); LastPopup().accept()
    eq(Pages(GSDListDB), "Notes"); eq(PageTitle(), "Notes")
    UndoButton():Fire("OnClick")
    eq(Pages(GSDListDB), "Notes,Raid,>Kara"); eq(PageTitle(), "Raid"); eq(Notes():GetText(), "raid text")
end)

test("the last remaining page cannot be deleted", function()
    Load(nil)
    Open()
    eq(MenuItem(PageMenu(), "Delete").enabled, false)
end)

--------------------------------------------------------------------------------
-- Tests: search
--------------------------------------------------------------------------------

test("search finds matches across pages, case-insensitive, and cycles", function()
    Load({ pages = {
        { id = 1, title = "A", text = "buy cloth\nsell CLOTH", children = {
            { id = 2, title = "A1", text = "nothing", children = {} } } },
        { id = 3, title = "B", text = "more cloth here", children = {} } }, currentPage = 1 })
    Open()
    SearchFor("cloth")
    eq(MatchCount(), "1/3"); eq(PageTitle(), "A")
    eq(Notes().highlight[1], 4); eq(Notes().highlight[2], 9); eq(Notes().cursor, 9)
    GSDListSearchBox:Fire("OnEnterPressed"); eq(MatchCount(), "2/3"); eq(Notes().highlight[1], 15)
    GSDListSearchBox:Fire("OnEnterPressed"); eq(MatchCount(), "3/3"); eq(PageTitle(), "B")
    GSDListSearchBox:Fire("OnEnterPressed"); eq(MatchCount(), "1/3", "no wrap"); eq(PageTitle(), "A")
    shiftDown = true; GSDListSearchBox:Fire("OnEnterPressed"); shiftDown = false
    eq(MatchCount(), "3/3", "shift-enter goes back")
end)

test("search starts from the current page and reports no matches", function()
    Load({ pages = {
        { id = 1, title = "A", text = "zul", children = {} },
        { id = 2, title = "B", text = "zul aman", children = {} } }, currentPage = 2 })
    Open()
    SearchFor("zul"); eq(MatchCount(), "2/2"); eq(PageTitle(), "B")
    SearchFor("gruul"); assert(MatchCount():find("0/0"), "no-match text: " .. MatchCount())
    SearchFor(""); eq(MatchCount(), "")
end)

test("search sees unsaved typing and closing lands the cursor on the match", function()
    Load(nil)
    Open()
    Notes():SetFocus(); Notes().text = "first line\nfind me"
    SearchFor("find")
    eq(MatchCount(), "1/1")
    GSDListSearchBox:Fire("OnEscapePressed")
    eq(Notes():HasFocus(), true, "cursor not placed in notes"); eq(Notes().cursor, 15)
    eq(GSDListSearchBox.parent.shown, false, "search row still shown")
end)

test("search scrolls only briefly; no per-frame work when idle", function()
    Load({ pages = { { id = 1, title = "A", text = "x\nx\nneedle", children = {} } } })
    Open()
    local edit = Notes()
    eq(edit.scripts.OnUpdate, nil, "OnUpdate before searching")
    SearchFor("needle")
    assert(edit.scripts.OnUpdate, "no scroll-to-match update")
    for _ = 1, 10 do if edit.scripts.OnUpdate then edit:Fire("OnUpdate", 0.016) end end
    eq(edit.scripts.OnUpdate, nil, "OnUpdate left running after search")
    for _, w in ipairs(created) do
        eq(w.scripts.OnUpdate, nil, "stray OnUpdate on " .. tostring(w.name or w.kind))
    end
end)

test("/gsd search opens the window with the query", function()
    Load({ pages = { { id = 1, title = "A", text = "netherweave", children = {} } } })
    Slash("search Nether")
    eq(GSDListFrame:IsShown(), true); eq(GSDListSearchBox:GetText(), "Nether"); eq(MatchCount(), "1/1")
end)

--------------------------------------------------------------------------------
-- Tests: to-do list
--------------------------------------------------------------------------------

test("adding tasks trims text, rejects empty input, updates the tab count", function()
    Load(nil)
    Open()
    local tab = Button("To-Do")
    AddViaInput("  Buy Netherweave  "); AddViaInput("   "); AddViaInput(""); AddViaInput("Attune Kara")
    eq(Texts(GSDListDB), "Buy Netherweave,Attune Kara")
    eq(Input():GetText(), ""); eq(tab.text, "To-Do (2)")
end)

test("ticking asks for confirmation by default", function()
    Load(nil)
    Open()
    AddViaInput("a"); AddViaInput("b")
    Tick(1)
    eq(#popups, 1); assert(LastPopup().text:find("a"), "popup text: " .. LastPopup().text)
    LastPopup().cancel()
    eq(Texts(GSDListDB), "a,b"); eq(RowButtons(Row(1)).checked, false, "checkbox left ticked after No")
    Tick(1); LastPopup().accept()
    eq(Texts(GSDListDB), "b"); eq(#timers, 0)
end)

test("confirming a task that was deleted meanwhile does nothing", function()
    Load(nil)
    Open()
    AddViaInput("a"); AddViaInput("b")
    Tick(1)
    local popup = LastPopup()
    local _, del = RowButtons(Row(1)); del:Fire("OnClick")
    popup.accept()
    eq(Texts(GSDListDB), "b")
end)

test("without confirmation, ticked tasks clear after a short delay", function()
    Load({ confirmComplete = false })
    Open()
    AddViaInput("a"); AddViaInput("b"); AddViaInput("c")
    Tick(2)
    eq(#popups, 0); eq(Texts(GSDListDB), "a,b,c", "removed before the delay")
    assert(timers[1].delay > 0 and timers[1].delay < 2, "delay " .. timers[1].delay)
    for _, t in ipairs(timers) do t.fn() end
    eq(Texts(GSDListDB), "a,c")
    timers = {}
    Tick(1); Tick(1)
    for _, t in ipairs(timers) do t.fn() end
    eq(Texts(GSDListDB), "a,c", "unticked task removed")
end)

test("rows have only a checkbox and a delete button", function()
    Load(nil)
    Open()
    AddViaInput("a")
    local _, _, count = RowButtons(Row(1))
    eq(count, 1)
    eq(Button("Clear Completed"), nil)
end)

test("drag a task down, up, to the ends, and onto itself", function()
    Load(nil)
    Open()
    for _, t in ipairs({ "a", "b", "c", "d" }) do AddViaInput(t) end
    local h = 20
    Drag(1, 2.6 * h); eq(Texts(GSDListDB), "b,c,a,d", "drop a between c and d")
    Drag(4, 0);       eq(Texts(GSDListDB), "d,b,c,a", "drop d at the top")
    Drag(1, 9999);    eq(Texts(GSDListDB), "b,c,a,d", "drop d past the end")
    Drag(2, -500);    eq(Texts(GSDListDB), "c,b,a,d", "drop b above the list")
    Drag(2, 1.2 * h); eq(Texts(GSDListDB), "c,b,a,d", "drop b onto itself")
end)

test("dragging shows a drop marker, scrolls, and cleans up", function()
    Load(nil)
    Open()
    for i = 1, 30 do AddViaInput("t" .. i) end
    local scroll = GSDListTodoScroll
    scroll.top, scroll.bottom, scroll.range = 400, 200, 300
    local row = Row(1)
    row:Fire("OnDragStart")
    eq(row.alpha, 0.5)
    cursorY = 100; for _ = 1, 20 do row:Fire("OnUpdate", 0.1) end
    eq(scroll.vscroll, 300, "scrolls down and clamps")
    cursorY = 450; for _ = 1, 40 do row:Fire("OnUpdate", 0.1) end
    eq(scroll.vscroll, 0, "scrolls up and clamps")
    local marker = Find(function(w) return w.kind == "Texture" and w.parent == TodoList() end)
    eq(marker.shown, true)
    row:Fire("OnDragStop")
    eq(row.alpha, 1); eq(row.scripts.OnUpdate, nil); eq(marker.shown, false)
end)

test("closing the window mid-drag cancels the drag", function()
    Load(nil)
    Open()
    AddViaInput("a"); AddViaInput("b")
    local row = Row(1)
    row:Fire("OnDragStart"); cursorY = TodoList():GetTop() - 999; row:Fire("OnUpdate", 0.016)
    Slash("")
    eq(row.scripts.OnUpdate, nil)
    row:Fire("OnDragStop"); eq(Texts(GSDListDB), "a,b", "late OnDragStop moved the task")
end)

test("long tasks show a tooltip, short ones do not", function()
    Load(nil)
    Open()
    AddViaInput("short"); AddViaInput("a very long task that will not fit in the row")
    GameTooltip.owner = nil
    Row(1):Fire("OnEnter"); eq(GameTooltip.owner, nil)
    Row(2):Fire("OnEnter"); eq(GameTooltip.owner, Row(2))
end)

test("to-do list can be disabled from chat", function()
    Load(nil)
    Open()
    local tab = Button("To-Do")
    tab:Fire("OnClick"); eq(GSDListDB.activeTab, "todo")
    Slash("todo")
    eq(GSDListDB.todoEnabled, false); eq(tab.shown, false); eq(GSDListDB.activeTab, "notes")
    GSDListMinimapButton:Fire("OnClick", "RightButton")
    eq(GSDListFrame:IsShown(), false, "right-click with to-do off toggles notes")
    Slash("todo"); eq(tab.shown, true)
end)

--------------------------------------------------------------------------------
-- Tests: undo
--------------------------------------------------------------------------------

test("undo restores deleted, completed, added and moved tasks", function()
    Load(nil)
    Open()
    local undo = UndoButton()
    eq(undo.enabled, false, "enabled with nothing to undo")
    AddViaInput("a"); AddViaInput("b"); AddViaInput("c")
    eq(undo.enabled, true)
    local _, del = RowButtons(Row(2)); del:Fire("OnClick")
    eq(Texts(GSDListDB), "a,c")
    undo:Fire("OnClick"); eq(Texts(GSDListDB), "a,b,c", "delete")
    Tick(3); LastPopup().accept(); eq(Texts(GSDListDB), "a,b")
    undo:Fire("OnClick"); eq(Texts(GSDListDB), "a,b,c", "complete")
    eq(RowButtons(Row(3)).checked, false, "restored task still ticked")
    Drag(1, 9999); eq(Texts(GSDListDB), "b,c,a")
    undo:Fire("OnClick"); eq(Texts(GSDListDB), "a,b,c", "move")
    undo:Fire("OnClick"); eq(Texts(GSDListDB), "a,b", "add")
    undo:Fire("OnClick"); undo:Fire("OnClick")
    eq(Texts(GSDListDB), ""); eq(undo.enabled, false)
    Slash("undo"); assert(chatLog[#chatLog]:find("Nothing to undo"), "no message when empty")
end)

test("undo tooltip names the action", function()
    Load(nil)
    Open()
    AddViaInput("Buy cloth")
    eq(UndoButton().tooltip(), "Undo add \"Buy cloth\"")
    UndoButton():Fire("OnEnter"); eq(GameTooltip.owner, UndoButton())
end)

test("undo history is capped", function()
    Load(nil)
    Open()
    for i = 1, 30 do AddViaInput("t" .. i) end
    for _ = 1, 40 do Slash("undo") end
    eq(#GSDListDB.todos, 10, "undo went past its limit")
end)

--------------------------------------------------------------------------------
-- Tests: quick add from chat
--------------------------------------------------------------------------------

test("/gsd add works before the window exists, keeps links, and is undoable", function()
    Load(nil)
    local link = "|cff0070dd|Hitem:21877::::::::70:::::|h[Netherweave Cloth]|h|r"
    Slash("add Farm 20x " .. link .. "  ")
    eq(Texts(GSDListDB), "Farm 20x " .. link)
    assert(chatLog[#chatLog]:find("Added task"), "no confirmation")
    eq(rawget(_G, "GSDListFrame"), nil, "window built by quick add")
    Slash("ADD second"); eq(#GSDListDB.todos, 2)
    Slash("add"); assert(chatLog[#chatLog]:find("Usage"), "no usage for empty add")
    Slash("undo"); eq(#GSDListDB.todos, 1)
    Open(); assert(Button("To-Do (1)"), "tab count after quick add")
end)

test("/gsd note appends to the current page", function()
    Load(nil)
    Slash("note first")
    Slash("note second")
    eq(GSDListDB.pages[1].text, "first\nsecond")
    Open()
    eq(Notes():GetText(), "first\nsecond")
    Notes():SetFocus(); Notes().text = "typed"
    Slash("note third")
    eq(Notes():GetText(), "typed\nthird", "unsaved typing lost")
    Slash("note"); assert(chatLog[#chatLog]:find("Usage"), "no usage for empty note")
end)

test("unknown slash command prints help", function()
    Load(nil)
    Slash("whatever")
    assert(#chatLog >= 6 and chatLog[1]:find("Commands"), "help not printed")
end)

--------------------------------------------------------------------------------
-- Tests: misc
--------------------------------------------------------------------------------

test("minimap clicks, drag and tooltip", function()
    Load(nil)
    local b = GSDListMinimapButton
    b:Fire("OnClick", "RightButton"); eq(GSDListFrame:IsShown(), true); eq(GSDListDB.activeTab, "todo")
    b:Fire("OnClick", "RightButton"); eq(GSDListFrame:IsShown(), false)
    b:Fire("OnDragStart"); cursorX, cursorY = 100, 200; b:Fire("OnUpdate")
    eq(GSDListDB.minimap.angle, 90); b:Fire("OnDragStop"); eq(b.scripts.OnUpdate, nil)
    b:Fire("OnEnter"); eq(GameTooltip.lines[1], "GSD List")
    Slash("minimap"); eq(b.shown, false); Slash("minimap"); eq(b.shown, true)
end)

test("/gsd reset works before and after the window exists", function()
    Load({ point = { "TOP", "TOP", 1, 2 }, width = 700, minimap = { angle = 10 } })
    Slash("reset")
    eq(GSDListDB.point, nil); eq(GSDListDB.width, 300); eq(GSDListDB.minimap.angle, 200)
    Open(); GSDListFrame:Fire("OnDragStop"); assert(GSDListDB.point, "position not saved")
    Slash("reset"); eq(GSDListDB.point, nil)
end)

test("shift-click links go into the focused GSD box", function()
    Load(nil)
    local link = "|cff0070dd|Hitem:21877::::::::70:::::|h[Netherweave Cloth]|h|r"
    ChatFrameUtil.InsertLink(link)
    Open()
    Notes():SetFocus(); ChatFrameUtil.InsertLink(link)
    eq(Notes():GetText(), link)
    Notes():ClearFocus(); eq(GSDListDB.pages[1].text, link)
    Input():SetFocus(); ChatFrameUtil.InsertLink(link); eq(Input():GetText(), link)
end)

test("falls back to ChatEdit_InsertLink on clients without ChatFrameUtil", function()
    local origReset = ResetEnvironment
    ResetEnvironment = function() origReset(); ChatFrameUtil = nil end
    local ok, err = pcall(function()
        Load(nil)
        Open(); Notes():SetFocus(); ChatEdit_InsertLink("[link]")
        eq(Notes():GetText(), "[link]")
    end)
    ResetEnvironment = origReset
    assert(ok, err)
end)

test("stress: 500 tasks and 200 pages", function()
    Load({ confirmComplete = false })
    Open()
    for i = 1, 500 do AddViaInput("task " .. i) end
    local before = #created
    Drag(500, 0); eq(GSDListDB.todos[1].text, "task 500")
    for i = 1, 500 do Tick(i) end
    for _, t in ipairs(timers) do t.fn() end
    eq(#GSDListDB.todos, 0); eq(#created, before, "widgets created after the first fill")
    for i = 1, 200 do NewPageVia("New page", "p" .. i) end
    eq(PageMenu().scroll, 400, "long page menu does not scroll")
    for _ = 1, 200 do PrevArrow():Fire("OnClick") end
    eq(PageTitle(), "Notes")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
