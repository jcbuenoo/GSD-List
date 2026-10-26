-- Randomised stress test for GSD List: lua5.1 tests/fuzz_tests.lua [runs] [steps]
-- Drives the addon with random sequences of user actions (with fixed seeds, so
-- failures reproduce) and checks after every step that the saved data stays
-- consistent, nothing errors, and nothing is left running every frame.

local TESTS_DIR = (arg[0]:match("^(.*)[/\\]") or ".")
local mock = dofile(TESTS_DIR .. "/mock_wow.lua")
mock.addonFile = os.getenv("GSD_ADDON") or "GSDList/GSDList.lua"
local RUNS, STEPS = tonumber(arg[1]) or 300, tonumber(arg[2]) or 150

local function Slash(msg) SlashCmdList.GSDLIST(msg) end
local function G(name) return rawget(_G, name) end -- widgets that may not exist yet
local function Find(pred) for _, w in ipairs(mock.created()) do if pred(w) then return w end end end
local function ByFile(file)
    return Find(function(w) return w.normal and w.normal.file == file end)
end
local function Rows()
    local rows = {}
    for _, w in ipairs(mock.created()) do
        if w.kind == "Frame" and w.index and w.shown then rows[#rows + 1] = w end
    end
    return rows
end
local function RowParts(row)
    local check, del
    for _, w in ipairs(mock.created()) do
        if w.parent == row then
            if w.kind == "CheckButton" then check = w elseif w.kind == "Button" then del = w end
        end
    end
    return check, del
end
local function Notes() return Find(function(w) return w.kind == "EditBox" and w.template == nil end) end
local function TitleButton()
    return Find(function(w) return w.kind == "Button" and w.normal == nil and type(w.tooltip) == "function" end)
end
local function MenuClick(menu, text)
    for _, node in ipairs(menu.children) do
        if (node.text:gsub("^%s+", "")) == text and node.enabled then
            if node.kind == "button" then node.a(node.data) else node.b(node.data) end
            return true
        end
    end
end

local WORDS = { "cloth", "Kara", "nether", "gold", "|cff0070dd|Hitem:21877::::::::70:::::|h[Netherweave Cloth]|h|r",
    "ZA", "boss", "%s", "100%", "a|b", "" }
local function Word(rnd) return WORDS[rnd(#WORDS)] end

-- Each action does something a player could do
local ACTIONS = {
    function(rnd) Slash("add " .. Word(rnd) .. " " .. Word(rnd)) end,
    function(rnd) Slash("note " .. Word(rnd)) end,
    function() Slash("") end,
    function() Slash("undo") end,
    function() Slash("lock") end,
    function() Slash("todo") end,
    function(rnd) Slash("search " .. Word(rnd)) end,
    function(rnd) -- type into the to-do box and press Enter
        if G("GSDListTodoInput") and mock.Visible(G("GSDListTodoInput")) then
            G("GSDListTodoInput"):SetText(Word(rnd)); G("GSDListTodoInput"):Fire("OnEnterPressed")
        end
    end,
    function(rnd) -- tick or untick a task
        local rows = Rows()
        if #rows > 0 then
            local check = RowParts(rows[rnd(#rows)])
            check.checked = not check.checked; check:Fire("OnClick")
        end
    end,
    function(rnd) -- delete a task
        local rows = Rows()
        if #rows > 0 then
            local _, del = RowParts(rows[rnd(#rows)])
            del:Fire("OnClick")
        end
    end,
    function(rnd) -- drag a task somewhere
        local rows = Rows()
        if #rows > 0 then
            local row = rows[rnd(#rows)]
            row:Fire("OnDragStart")
            cursorY = 500 - rnd(30) * 20 + 10
            row:Fire("OnUpdate", 0.016)
            if rnd(10) > 1 then row:Fire("OnDragStop") else Slash("") end -- sometimes close mid-drag
        end
    end,
    function(rnd) -- answer an open popup
        local popup = popups[#popups]
        if popup and not popup.answered then
            popup.answered = true
            if popup.editBox then
                if rnd(3) == 1 then popup.cancel() else popup.enter(Word(rnd)) end
            elseif rnd(2) == 1 then popup.accept() else popup.cancel() end
        end
    end,
    function() -- let delayed completions fire
        local due = timers
        timers = {}
        for _, t in ipairs(due) do t.fn() end
    end,
    function(rnd) -- page menu actions
        local title = TitleButton()
        if title and mock.Visible(title) then
            title:Fire("OnClick")
            local options = { "New page", "New sub-note", "Rename", "Move up", "Move down", "Delete" }
            MenuClick(menus[#menus], options[rnd(#options)])
        end
    end,
    function(rnd) -- arrows
        local arrow = ByFile(rnd(2) == 1 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
            or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        if arrow and mock.Visible(arrow) and arrow.enabled then arrow:Fire("OnClick") end
    end,
    function(rnd) -- type in the note
        local edit = Notes()
        if edit and mock.Visible(edit) then
            edit:SetFocus(); edit:Insert(" " .. Word(rnd))
            if rnd(2) == 1 then edit:ClearFocus() end
        end
    end,
    function(rnd) -- search box: type, Enter, Escape
        if G("GSDListSearchBox") and mock.Visible(G("GSDListSearchBox")) then
            local r = rnd(3)
            if r == 1 then G("GSDListSearchBox"):SetText(Word(rnd))
            elseif r == 2 then shiftDown = rnd(2) == 1; G("GSDListSearchBox"):Fire("OnEnterPressed"); shiftDown = false
            else G("GSDListSearchBox"):Fire("OnEscapePressed") end
        end
    end,
    function(rnd) -- settings menu
        local gear = ByFile("Interface\\WorldMap\\GEAR_64GREY")
        if gear then
            gear:Fire("OnClick")
            local options = { "Enable to-do list", "Confirm completing tasks", "Lock window", "Show minimap button" }
            MenuClick(menus[#menus], options[rnd(#options)])
        end
    end,
    function(rnd) -- tabs
        local tab = Find(function(w)
            return w.template == "UIPanelButtonTemplate" and w.text:find(rnd(2) == 1 and "^Notes" or "^To%-Do")
        end)
        if tab and mock.Visible(tab) then tab:Fire("OnClick") end
    end,
    function(rnd) -- minimap button
        GSDListMinimapButton:Fire("OnClick", rnd(2) == 1 and "LeftButton" or "RightButton")
    end,
    function() -- undo button
        local undo = ByFile("Interface\\Buttons\\UI-RefreshButton")
        if undo and mock.Visible(undo) and undo.enabled then undo:Fire("OnClick") end
    end,
}

local function CheckInvariants(where)
    local db = GSDListDB
    -- Tasks: valid entries, no task in the list twice
    local seen = {}
    for i, item in ipairs(db.todos) do
        assert(type(item) == "table" and type(item.text) == "string" and item.text ~= "", where .. ": bad task " .. i)
        assert(not seen[item], where .. ": task listed twice: " .. item.text)
        seen[item] = true
    end
    -- Pages: a proper tree with unique ids, and the current page exists
    local ids, count, current = {}, 0, false
    local function Walk(list, depth)
        assert(depth <= 4, where .. ": pages nested deeper than 4 levels")
        for _, p in ipairs(list) do
            assert(type(p.title) == "string" and type(p.text) == "string" and type(p.children) == "table",
                where .. ": malformed page")
            assert(not ids[p.id], where .. ": duplicate page id " .. tostring(p.id))
            ids[p.id], count = true, count + 1
            if p.id == db.currentPage then current = true end
            Walk(p.children, depth + 1)
        end
    end
    Walk(db.pages, 1)
    assert(count >= 1, where .. ": no pages left")
    assert(current or db.currentPage == nil, where .. ": current page " .. tostring(db.currentPage) .. " missing")
    if G("GSDListFrame") then
        -- Visible rows match the task list
        if mock.Visible(G("GSDListTodoScroll")) then
            local shown = 0
            for _, w in ipairs(mock.created()) do
                if w.kind == "Frame" and w.index and w.shown then shown = shown + 1 end
            end
            assert(shown == #db.todos, ("%s: %d rows shown for %d tasks"):format(where, shown, #db.todos))
            -- A ticked box means done, except for the one task waiting on the confirmation popup
            local waiting = 0
            for _, row in ipairs(Rows()) do
                local check = RowParts(row)
                local item = db.todos[row.index]
                if check.checked and not item.done then waiting = waiting + 1 end
                assert(check.checked or not item.done, where .. ": done task shown unticked")
            end
            assert(waiting <= 1, ("%s: %d tasks shown ticked but not done"):format(where, waiting))
        end
        -- The tab count matches
        local tab = Find(function(w) return w.template == "UIPanelButtonTemplate" and w.text:find("^To%-Do") end)
        local n = #db.todos
        local expected = n == 0 and "To-Do" or n > 99 and "To-Do (99+)" or ("To-Do (" .. n .. ")")
        assert(tab.text == expected, where .. ": tab says " .. tab.text .. ", expected " .. expected)
    end
end

-- After the user stops, nothing should keep running every frame
local function CheckIdle(where)
    for _, w in ipairs(mock.created()) do
        local edit = w.kind == "EditBox" and w.template == nil
        if w.scripts.OnUpdate and not (edit and w:HasFocus()) then
            for _ = 1, 10 do if w.scripts.OnUpdate then w:Fire("OnUpdate", 0.016) end end
            assert(not w.scripts.OnUpdate or (w.kind == "Frame" and w.index),
                where .. ": OnUpdate left running on " .. tostring(w.name or w.kind))
        end
    end
end

local failures = 0
for run = 1, RUNS do
    math.randomseed(run)
    local rnd = math.random
    local log = {}
    local ok, err = pcall(function()
        mock.Load(run % 3 == 0 and { confirmComplete = false } or nil)
        for step = 1, STEPS do
            local a = rnd(#ACTIONS)
            log[#log + 1] = a
            ACTIONS[a](rnd)
            CheckInvariants(("run %d step %d"):format(run, step))
        end
        -- Finish any drag, let timers fire, leave the notes, then check for idle work
        for _, w in ipairs(mock.created()) do if w.kind == "Frame" and w.index then w:Fire("OnDragStop") end end
        for _, t in ipairs(timers) do t.fn() end
        if G("GSDListFrame") then Notes():ClearFocus() end
        CheckIdle(("run %d end"):format(run))
        CheckInvariants(("run %d end"):format(run))
    end)
    if not ok then
        failures = failures + 1
        print(("FAIL  run %d (seed %d): %s\n      actions: %s"):format(run, run, tostring(err),
            table.concat(log, ",", math.max(1, #log - 15))))
        if failures >= 5 then break end
    end
end
print(("%d random runs x %d steps, %d failures"):format(RUNS, STEPS, failures))
os.exit(failures == 0 and 0 or 1)
