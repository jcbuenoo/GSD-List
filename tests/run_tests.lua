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
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateFontString() return NewWidget("FontString", nil, self) end
function Widget:IsTruncated() return #self.text > 20 end
function Widget:SetResizeBounds(...) self.bounds = { ... } end
function Widget:IsOwned(o) return self.owner == o end
function Widget:SetOwner(o) self.owner = o; self.lines = {} end
function Widget:AddLine(t) self.lines[#self.lines + 1] = t end

function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name, parent)
    w.template = template
    if template == "UICheckButtonTemplate" then w.Text = NewWidget("FontString", nil, w) end
    return w
end

local function ResetEnvironment()
    created, focused = {}, nil
    for _, n in ipairs({ "GSDListDB", "GSDListFrame", "GSDListMinimapButton", "GSDListTodoInput",
        "GSDListNotesScroll", "GSDListTodoScroll", "SLASH_GSDLIST1", "SLASH_GSDLIST2" }) do
        _G[n] = nil
    end
    UIParent = NewWidget("Frame", "UIParent")
    Minimap = NewWidget("Frame", "Minimap"); Minimap.w = 140
    GameTooltip = NewWidget("GameTooltip", "GameTooltip")
    UISpecialFrames, SlashCmdList, ChatFontNormal = {}, {}, {}
    SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840 }
    BackdropTemplateMixin = {}
    chatLog = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chatLog[#chatLog + 1] = m end }
    -- Mirrors the 2.5.6 client: links go through ChatFrameUtil.InsertLink,
    -- and ChatEdit_InsertLink is only a deprecated alias.
    ChatFrameUtil = { InsertLink = function() return false end }
    ChatEdit_InsertLink = ChatFrameUtil.InsertLink
    ScrollingEdit_OnTextChanged = function(edit) edit.handleCursorChange = true end
    ScrollingEdit_OnCursorChanged = function(edit) edit.handleCursorChange = true end
    ScrollingEdit_OnUpdate = function(edit) edit.handleCursorChange = false end
    cursorX, cursorY = 150, 100
    timers = {}
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
end

local function RunTimers()
    local due = timers
    timers = {}
    for _, t in ipairs(due) do t.fn() end
    return #due
end

PlaySound = function() end
GetCursorPosition = function() return cursorX, cursorY end
NORMAL_FONT_COLOR_CODE = "|cffffd100"
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
tinsert, tremove, strlower = table.insert, table.remove, string.lower
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
-- Test runner
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
local function Input() return GSDListTodoInput end
local function AddViaInput(text) Input():SetText(text); Input():Fire("OnEnterPressed") end
local function Row(i) return GSDListFrame and (function()
    for _, w in ipairs(created) do if w.kind == "Frame" and w.index == i and w.shown then return w end end
end)() end
local function RowButtons(row)
    local check, buttons = nil, {}
    for _, w in ipairs(created) do
        if w.parent == row then
            if w.kind == "CheckButton" then check = w elseif w.kind == "Button" then buttons[#buttons + 1] = w end
        end
    end
    return check, buttons[1], #buttons -- check, delete, button count
end
local function TodoList()
    for _, w in ipairs(created) do if w.kind == "Frame" and w.parent == GSDListTodoScroll then return w end end
end
-- Drag row `from` and drop it with the cursor `offset` pixels below the list top
local function Drag(from, offset, frames)
    local row = Row(from)
    row:Fire("OnDragStart")
    cursorY = TodoList():GetTop() - offset
    for _ = 1, frames or 1 do row:Fire("OnUpdate", 0.016) end
    row:Fire("OnDragStop")
end
local function Tick(i)
    local check = RowButtons(Row(i))
    check.checked = not check.checked
    check:Fire("OnClick")
end
local function Notes()
    for _, w in ipairs(created) do if w.kind == "EditBox" and w.template == nil then return w end end
end
local function Texts(db)
    local t = {}
    for i, v in ipairs(db.todos) do t[i] = v.text end
    return table.concat(t, ",")
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

test("fresh install creates defaults", function()
    Load(nil)
    eq(type(GSDListDB), "table"); eq(GSDListDB.notes, ""); eq(#GSDListDB.todos, 0)
    eq(GSDListDB.todoEnabled, true); eq(GSDListDB.minimap.angle, 200); eq(GSDListDB.minimap.hide, false)
    eq(SLASH_GSDLIST1, "/gsd"); eq(SLASH_GSDLIST2, "/gsdlist")
end)

test("window is built lazily (only the minimap button exists at login)", function()
    Load(nil)
    eq(rawget(_G, "GSDListFrame"), nil, "main frame")
    assert(GSDListMinimapButton, "minimap button missing")
    assert(#created < 10, "too many objects at login: " .. #created)
end)

test("corrupted saved variables are repaired", function()
    Load({ notes = 42, todos = { "bad", { text = "" }, { text = "keep" }, { done = true },
        { text = "finished in 1.x", done = true } },
        minimap = { angle = "x" }, activeTab = "bogus" })
    eq(GSDListDB.notes, ""); eq(Texts(GSDListDB), "keep"); eq(GSDListDB.todos[1].done, false)
    eq(GSDListDB.minimap.angle, 200)
    Slash("")
    eq(GSDListDB.activeTab, "notes")
end)

test("existing data is kept", function()
    Load({ notes = "hello", todos = { { text = "a", done = false } }, width = 500 })
    eq(GSDListDB.notes, "hello"); eq(#GSDListDB.todos, 1); eq(GSDListDB.width, 500)
    Slash("")
    eq(Notes():GetText(), "hello")
    eq(GSDListFrame.w, 500)
end)

test("/gsd toggles the window, Escape is registered", function()
    Load(nil)
    Slash(""); eq(GSDListFrame:IsShown(), true)
    Slash(""); eq(GSDListFrame:IsShown(), false)
    eq(UISpecialFrames[1], "GSDListFrame")
end)

test("notes save on focus loss, on hide, and on logout", function()
    local loader = Load(nil)
    Slash("")
    local edit = Notes()
    edit:SetFocus(); edit.text = "Kara keys"; edit:ClearFocus()
    eq(GSDListDB.notes, "Kara keys")
    edit:SetFocus(); edit.text = "Kara keys + ZA"
    Slash("") -- hide while typing
    eq(GSDListDB.notes, "Kara keys + ZA")
    Slash(""); edit:SetFocus(); edit.text = "typed right before /reload"
    loader:Fire("OnEvent", "PLAYER_LOGOUT")
    eq(GSDListDB.notes, "typed right before /reload")
end)

test("notes do no per-frame work unless being edited", function()
    Load(nil)
    Slash("")
    local edit = Notes()
    eq(edit.scripts.OnUpdate, nil, "OnUpdate before focus")
    edit:SetFocus(); assert(edit.scripts.OnUpdate, "OnUpdate while typing")
    edit:Fire("OnUpdate", 0.016)
    edit:ClearFocus(); eq(edit.scripts.OnUpdate, nil, "OnUpdate after focus")
    for _, w in ipairs(created) do
        if w ~= edit then eq(w.scripts.OnUpdate, nil, "stray OnUpdate on " .. tostring(w.name or w.kind)) end
    end
end)

test("adding tasks trims text and rejects empty input", function()
    Load(nil)
    Slash("")
    AddViaInput("  Buy Netherweave  "); AddViaInput("   "); AddViaInput(""); AddViaInput("Attune Kara")
    eq(Texts(GSDListDB), "Buy Netherweave,Attune Kara")
    eq(Input():GetText(), "")
end)

test("ticking a task removes it automatically after a short delay", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b"); AddViaInput("c")
    Tick(2)
    eq(GSDListDB.todos[2].done, true); eq(Texts(GSDListDB), "a,b,c", "removed before the delay")
    eq(#timers, 1); assert(timers[1].delay > 0 and timers[1].delay < 2, "delay " .. timers[1].delay)
    RunTimers()
    eq(Texts(GSDListDB), "a,c")
end)

test("unticking before the delay keeps the task", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b")
    Tick(1); Tick(1)
    RunTimers()
    eq(Texts(GSDListDB), "a,b"); eq(GSDListDB.todos[1].done, false)
end)

test("auto-clear removes the right task even if the list changed meanwhile", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b"); AddViaInput("c")
    Tick(3)                                        -- tick "c"
    local _, del = RowButtons(Row(1)); del:Fire("OnClick") -- delete "a" before the timer fires
    AddViaInput("d")
    RunTimers()
    eq(Texts(GSDListDB), "b,d")
    Tick(1); _, del = RowButtons(Row(1)); del:Fire("OnClick") -- tick then delete "b" by hand
    RunTimers()
    eq(Texts(GSDListDB), "d")
end)

test("rows have no Clear Completed or arrow buttons", function()
    Load(nil)
    Slash("")
    AddViaInput("a")
    local _, _, count = RowButtons(Row(1))
    eq(count, 1, "buttons on a row")
    for _, w in ipairs(created) do
        assert(w.text ~= "Clear Completed", "Clear Completed button still exists")
    end
end)

test("drag a task down, up, to the ends, and onto itself", function()
    Load(nil)
    Slash("")
    for _, t in ipairs({ "a", "b", "c", "d" }) do AddViaInput(t) end
    Drag(1, 2.6 * 22); eq(Texts(GSDListDB), "b,c,a,d", "drop a between c and d")
    Drag(4, 0);        eq(Texts(GSDListDB), "d,b,c,a", "drop d at the top")
    Drag(1, 9999);     eq(Texts(GSDListDB), "b,c,a,d", "drop d past the end")
    Drag(2, -500);     eq(Texts(GSDListDB), "c,b,a,d", "drop b above the list")
    Drag(2, 1.2 * 22); eq(Texts(GSDListDB), "c,b,a,d", "drop b onto itself")
    Drag(2, 1.9 * 22); eq(Texts(GSDListDB), "c,b,a,d", "drop b just below itself")
end)

test("dragging shows a drop marker and cleans up afterwards", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b")
    local row = Row(1)
    row:Fire("OnDragStart")
    eq(row.alpha, 0.5); assert(row.scripts.OnUpdate, "no OnUpdate while dragging")
    cursorY = TodoList():GetTop() - 44; row:Fire("OnUpdate", 0.016)
    local marker
    for _, w in ipairs(created) do if w.kind == "Texture" and w.parent == TodoList() then marker = w end end
    eq(marker.shown, true); eq(marker.points[1][5], -44, "marker y")
    row:Fire("OnEnter"); eq(row.hl.shown, false, "hover highlight during drag")
    row:Fire("OnDragStop")
    eq(row.alpha, 1); eq(row.scripts.OnUpdate, nil); eq(marker.shown, false)
    Row(1):Fire("OnEnter"); eq(Row(1).hl.shown, true, "hover works after drag")
end)

test("dragging past the list edge scrolls it", function()
    Load(nil)
    Slash("")
    for i = 1, 30 do AddViaInput("t" .. i) end
    local scroll = GSDListTodoScroll
    scroll.top, scroll.bottom, scroll.range = 400, 200, 300
    local row = Row(1)
    row:Fire("OnDragStart")
    cursorY = 100; for _ = 1, 10 do row:Fire("OnUpdate", 0.1) end
    eq(scroll.vscroll, 200, "scrolled down")
    for _ = 1, 10 do row:Fire("OnUpdate", 0.1) end
    eq(scroll.vscroll, 300, "clamped to range")
    cursorY = 450; for _ = 1, 40 do row:Fire("OnUpdate", 0.1) end
    eq(scroll.vscroll, 0, "scrolled back up and clamped at 0")
    row:Fire("OnDragStop")
end)

test("closing the window mid-drag cancels the drag", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b")
    local row = Row(1)
    row:Fire("OnDragStart"); cursorY = TodoList():GetTop() - 999; row:Fire("OnUpdate", 0.016)
    Slash("")
    eq(row.scripts.OnUpdate, nil); eq(Texts(GSDListDB), "a,b")
    row:Fire("OnDragStop"); eq(Texts(GSDListDB), "a,b", "late OnDragStop moved the task")
end)

test("a task auto-cleared while being dragged does not break dragging", function()
    Load(nil)
    Slash("")
    AddViaInput("a"); AddViaInput("b"); AddViaInput("c")
    Tick(3)
    local row = Row(3)
    row:Fire("OnDragStart")
    RunTimers() -- "c" is removed mid-drag; its row is hidden
    eq(Texts(GSDListDB), "a,b"); eq(row.scripts.OnUpdate, nil)
    Row(1):Fire("OnEnter"); eq(Row(1).hl.shown, true, "hover stuck after cancelled drag")
    Drag(1, 9999); eq(Texts(GSDListDB), "b,a")
end)

test("task counter", function()
    Load(nil)
    Slash("")
    local function CounterText()
        for _, w in ipairs(created) do
            if w.kind == "FontString" and (w.text:find("task") or w.text == "Nothing to do!") then return w.text end
        end
    end
    eq(CounterText(), "Nothing to do!")
    AddViaInput("a"); eq(CounterText(), "1 task")
    AddViaInput("b"); eq(CounterText(), "2 tasks - drag to reorder")
end)

test("delete removes the right task and rows are reused", function()
    Load(nil)
    Slash("")
    for i = 1, 5 do AddViaInput("t" .. i) end
    local before = #created
    local _, del = RowButtons(Row(2)); del:Fire("OnClick")
    eq(Texts(GSDListDB), "t1,t3,t4,t5")
    eq(#created, before, "refresh created new widgets")
    AddViaInput("t6")
    eq(#created, before, "re-adding created new widgets")
    _, del = RowButtons(Row(1)); del:Fire("OnClick")
    eq(Texts(GSDListDB), "t3,t4,t5,t6")
end)

test("long tasks show a tooltip, short ones do not", function()
    Load(nil)
    Slash("")
    AddViaInput("short"); AddViaInput("a very long task that will not fit in the row")
    GameTooltip.owner = nil
    Row(1):Fire("OnEnter"); eq(GameTooltip.owner, nil)
    Row(2):Fire("OnEnter"); eq(GameTooltip.owner, Row(2))
    Row(2):Fire("OnLeave")
end)

test("to-do list can be disabled and re-enabled", function()
    Load(nil)
    Slash("")
    local todoTab
    for _, w in ipairs(created) do if w.text == "To-Do" then todoTab = w end end
    todoTab:Fire("OnClick"); eq(GSDListDB.activeTab, "todo")
    Slash("todo")
    eq(GSDListDB.todoEnabled, false); eq(todoTab.shown, false); eq(GSDListDB.activeTab, "notes")
    eq(GSDListFrame:IsShown(), true)
    GSDListMinimapButton:Fire("OnClick", "RightButton")
    eq(GSDListFrame:IsShown(), false, "right-click with to-do off toggles notes")
    Slash("todo"); eq(todoTab.shown, true)
    assert(chatLog[#chatLog]:find("enabled"), "no chat confirmation")
end)

test("disabling the to-do list before the window exists", function()
    Load(nil)
    Slash("todo"); eq(GSDListDB.todoEnabled, false)
    Slash("")
    local toggle
    for _, w in ipairs(created) do if w.kind == "CheckButton" and w.Text then toggle = w end end
    eq(toggle.checked, false); eq(toggle.Text.text, "Enable To-Do List")
end)

test("footer checkbox toggles the to-do list", function()
    Load(nil)
    Slash("")
    local toggle
    for _, w in ipairs(created) do if w.kind == "CheckButton" and w.Text then toggle = w end end
    toggle.checked = false; toggle:Fire("OnClick"); eq(GSDListDB.todoEnabled, false)
    toggle.checked = true; toggle:Fire("OnClick"); eq(GSDListDB.todoEnabled, true)
end)

test("minimap clicks open the right tab", function()
    Load(nil)
    local b = GSDListMinimapButton
    b:Fire("OnClick", "RightButton"); eq(GSDListFrame:IsShown(), true); eq(GSDListDB.activeTab, "todo")
    b:Fire("OnClick", "LeftButton"); eq(GSDListFrame:IsShown(), false)
    b:Fire("OnClick", "LeftButton"); eq(GSDListFrame:IsShown(), true); eq(GSDListDB.activeTab, "todo")
    b:Fire("OnClick", "RightButton"); eq(GSDListFrame:IsShown(), false)
end)

test("minimap button drags around the minimap", function()
    Load(nil)
    local b = GSDListMinimapButton
    b:Fire("OnDragStart"); assert(b.scripts.OnUpdate, "no drag handler")
    cursorX, cursorY = 100, 200 -- straight above the minimap centre
    b:Fire("OnUpdate")
    eq(GSDListDB.minimap.angle, 90)
    local p = b.points[#b.points]
    assert(math.abs(p[4]) < 1e-9 and math.abs(p[5] - 80) < 1e-9, "position " .. p[4] .. "," .. p[5])
    b:Fire("OnDragStop"); eq(b.scripts.OnUpdate, nil)
end)

test("minimap tooltip and hide/show", function()
    Load(nil)
    local b = GSDListMinimapButton
    b:Fire("OnEnter"); eq(GameTooltip.lines[1], "GSD List"); eq(#GameTooltip.lines, 4)
    Slash("minimap"); eq(b.shown, false); eq(GSDListDB.minimap.hide, true)
    Slash("minimap"); eq(b.shown, true)
    Load({ minimap = { hide = true } }); eq(GSDListMinimapButton.shown, false)
end)

test("/gsd reset works before and after the window exists", function()
    Load({ point = { "TOP", "TOP", 1, 2 }, width = 700, minimap = { angle = 10 } })
    Slash("reset")
    eq(GSDListDB.point, nil); eq(GSDListDB.width, 360); eq(GSDListDB.minimap.angle, 200)
    Slash(""); GSDListFrame:Fire("OnDragStop")
    assert(GSDListDB.point, "position not saved after drag")
    Slash("reset"); eq(GSDListDB.point, nil); eq(GSDListFrame.w, 360)
end)

test("unknown slash command prints help", function()
    Load(nil)
    Slash("whatever")
    assert(#chatLog >= 4 and chatLog[1]:find("Commands"), "help not printed")
end)

test("shift-click links go into the focused GSD box (2.5.6 ChatFrameUtil path)", function()
    Load(nil)
    local link = "|cff0070dd|Hitem:21877::::::::70:::::|h[Netherweave Cloth]|h|r"
    ChatFrameUtil.InsertLink(link)
    Slash("")
    local edit = Notes()
    edit:SetFocus(); ChatFrameUtil.InsertLink(link)
    eq(edit:GetText(), link)
    edit:ClearFocus(); eq(GSDListDB.notes, link)
    Input():SetFocus(); ChatFrameUtil.InsertLink(link)
    eq(Input():GetText(), link)
    Input():ClearFocus(); Input():SetText(""); ChatFrameUtil.InsertLink(link)
    eq(Input():GetText(), "", "inserted without focus")
end)

test("falls back to ChatEdit_InsertLink on clients without ChatFrameUtil", function()
    ResetEnvironment()
    local origReset = ResetEnvironment
    ResetEnvironment = function() origReset(); ChatFrameUtil = nil end
    local ok, err = pcall(function()
        Load(nil)
        Slash(""); Notes():SetFocus(); ChatEdit_InsertLink("[link]")
        eq(Notes():GetText(), "[link]")
    end)
    ResetEnvironment = origReset
    assert(ok, err)
end)

test("closing the window drops focus from both boxes", function()
    Load(nil)
    Slash("")
    Input():SetFocus(); Slash("")
    eq(Input():HasFocus(), false)
end)

test("stress: 500 tasks, reorder, then complete them all", function()
    Load(nil)
    Slash("")
    for i = 1, 500 do AddViaInput("task " .. i) end
    eq(#GSDListDB.todos, 500)
    local before = #created
    Drag(500, 0); eq(GSDListDB.todos[1].text, "task 500")
    for i = 1, 500 do Tick(i) end
    eq(RunTimers(), 500)
    eq(#GSDListDB.todos, 0); eq(#created, before, "widgets created after the first fill")
    for _, w in ipairs(created) do
        if w.kind == "Frame" and w.index then eq(w.shown, false, "row still shown") end
    end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
