-- Minimal World of Warcraft (TBC Classic) client mock for running Market Intel outside the game.
-- Widget methods are restricted to a whitelist of real WoW API methods, so a typo or a
-- method that does not exist in the client raises an error instead of passing silently.
local M = {}

M.now = 1767268800 -- 2026-01-01 12:00 UTC
M.gt = 1000
M.errors = {}
M.chat = {}
M.sounds = 0
M.frames = {}
M.events = {}
M.queries = {}
M.auctions = {}         -- full AH contents: { name, id, count, buyout, owner, quality, suffix, uncached }
M.list = {}             -- current results list
M.listTotal = 0
M.ahThrottle = 0        -- seconds between allowed queries
M.lastQuery = -100
M.player = "Tester"
M.mapID = 1453          -- Stormwind
M.bags = {}

---------------------------------------------------------------------------
-- Lua / WoW global functions
---------------------------------------------------------------------------
-- Fresh client state for each test.
function M.reset()
	M.now, M.gt = 1767268800, 1000
	M.errors, M.chat, M.sounds, M.frames, M.events, M.queries = {}, {}, 0, {}, {}, {}
	M.auctions, M.list, M.listTotal, M.ahThrottle, M.lastQuery = {}, {}, 0, 0, -100
	M.mapID, M.bags, M.itemInfo, M.focus, M.shift, M.popup, M.ahOpen = 1453, {}, {}, nil, nil, nil, nil
	M.pendingUpdate, M.insertedLink = nil, nil
	_G.AuctionFrame, _G.Auctionator, _G.TSM_API, _G.TooltipDataProcessor = nil, nil, nil, nil
	M.install()
end

function M.install()
	_G.time = function(t) if t then return os.time(t) end return M.now end
	_G.date = function(fmt, t) return os.date(fmt, t or M.now) end
	_G.GetTime = function() return M.gt end
	_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	_G.tinsert = table.insert
	_G.strsplit = nil
	_G.geterrorhandler = function() return function(err) table.insert(M.errors, err) end end
	_G.hooksecurefunc = function(a, b, c)
		local tbl, name, fn = _G, a, b
		if type(a) == "table" then tbl, name, fn = a, b, c end
		local orig = tbl[name]
		assert(orig, "hooksecurefunc on missing function " .. tostring(name))
		tbl[name] = function(...)
			local r = { orig(...) }
			fn(...)
			return unpack(r)
		end
	end
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.chat, msg) end }
	_G.UnitName = function() return M.player end
	_G.UnitFactionGroup = function() return "Alliance" end
	_G.GetRealmName = function() return "Dreamscythe" end
	_G.C_Map = { GetBestMapForUnit = function() return M.mapID end }
	_G.PlaySound = function() M.sounds = M.sounds + 1 end
	_G.SOUNDKIT = { RAID_WARNING = 8959 }
	_G.YES, _G.NO = "Yes", "No"
	_G.SlashCmdList = {}
	_G.StaticPopupDialogs = {}
	_G.StaticPopup_Show = function(which) M.popup = which end
	_G.UISpecialFrames = {}
	_G.ITEM_QUALITY_COLORS = {
		[0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" },
		[3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" },
	}
	_G.IsShiftKeyDown = function() return M.shift end
	_G.NUM_AUCTION_ITEMS_PER_PAGE = 50
	_G.BackdropTemplateMixin = {}
	_G.ChatEdit_InsertLink = function(link) M.insertedLink = link return false end

	_G.GetItemInfo = function(item)
		local id = tonumber(tostring(item):match("(%d+)"))
		local info = id and M.itemInfo and M.itemInfo[id]
		if not info then return nil end
		return info.name, "|cffffffff|Hitem:" .. id .. "::::::::70:::::|h[" .. info.name .. "]|h|r", info.quality
	end
	_G.GetItemIcon = function(id) return "Interface\\Icons\\Item" .. tostring(id) end

	_G.C_Container = {
		GetContainerNumSlots = function(bag) return M.bags[bag] and #M.bags[bag] or 0 end,
		GetContainerItemLink = function(bag, slot) return M.bags[bag] and M.bags[bag][slot] end,
	}

	-- Auction house
	_G.CanSendAuctionQuery = function() return M.gt - M.lastQuery >= M.ahThrottle, true end
	_G.QueryAuctionItems = function(name, minLevel, maxLevel, page, usable, rarity, getAll, exact)
		assert(M.ahOpen, "QueryAuctionItems while AH closed")
		assert(M.gt - M.lastQuery >= M.ahThrottle, "QueryAuctionItems sent while throttled")
		M.lastQuery = M.gt
		table.insert(M.queries, { name = name, page = page or 0, getAll = getAll, exact = exact })
		local matches = {}
		for _, a in ipairs(M.auctions) do
			local n = a.name:lower()
			local q = (name or ""):lower()
			if q == "" or (exact and n == q) or (not exact and n:find(q, 1, true)) then
				matches[#matches + 1] = a
			end
		end
		M.listTotal = #matches
		M.list = {}
		if getAll then
			M.list = matches
		else
			local first = (page or 0) * 50
			for i = first + 1, math.min(first + 50, #matches) do M.list[#M.list + 1] = matches[i] end
		end
		M.pendingUpdate = true
	end
	_G.GetNumAuctionItems = function() return #M.list, M.listTotal end
	_G.GetAuctionItemInfo = function(_, i)
		local a = M.list[i]
		if not a or a.uncached then return nil end
		return a.name, "tex", a.count, a.quality or 1, true, 70, nil, 1, 1, a.buyout, 0, nil, nil, a.owner,
			a.owner, 0, a.id, true
	end
	_G.GetAuctionItemLink = function(_, i)
		local a = M.list[i]
		if not a or a.uncached then return nil end
		return M.Link(a.id, a.name, a.suffix)
	end

	-- Scroll helpers from FrameXML
	_G.FauxScrollFrame_Update = function(frame, numItems, numToDisplay, height)
		frame.numItems, frame.numToDisplay, frame.rowHeight = numItems, numToDisplay, height
		local maxOffset = math.max(0, numItems - numToDisplay)
		frame.offset = math.min(frame.offset or 0, maxOffset)
	end
	_G.FauxScrollFrame_GetOffset = function(frame) return frame.offset or 0 end
	_G.FauxScrollFrame_OnVerticalScroll = function(frame, value, rowHeight, fn)
		frame.offset = math.floor(value / rowHeight + 0.5)
		fn()
	end
end

function M.Link(id, name, suffix)
	return string.format("|cffffffff|Hitem:%d::::::%s::70:::::|h[%s]|h|r", id, suffix and tostring(suffix) or "", name)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Methods that exist on WoW widgets (checked against the TBC Classic / Classic Era API).
local REAL = {}
for m in ([[SetSize SetWidth SetHeight GetWidth GetHeight SetPoint ClearAllPoints SetAllPoints Show Hide IsShown
	IsVisible SetScript GetScript HookScript RegisterEvent UnregisterEvent SetFrameStrata SetToplevel EnableMouse
	EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing SetBackdrop
	SetBackdropColor SetBackdropBorderColor CreateFontString CreateTexture SetText GetText SetJustifyH SetJustifyV
	SetWordWrap SetTexture SetColorTexture SetHighlightTexture RegisterForClicks SetAutoFocus ClearFocus SetFocus
	HasFocus SetChecked GetChecked LockHighlight UnlockHighlight GetName GetParent GetChildren Click SetValue GetValue
	AddLine AddDoubleLine SetOwner SetHyperlink GetItem SetTextColor SetFontObject SetAlpha SetShown]]):gmatch("%S+") do
	REAL[m] = true
end
M.usedMethods = {}
M.missingMethods = {}

local Widget = {}
-- Methods that only exist on some widget types.
local ONLY = {
	SetChecked = { CheckButton = true }, GetChecked = { CheckButton = true },
	SetAutoFocus = { EditBox = true }, HasFocus = { EditBox = true }, SetFocus = { EditBox = true }, ClearFocus = { EditBox = true },
	SetTexture = { Texture = true }, SetColorTexture = { Texture = true },
	SetJustifyH = { FontString = true, EditBox = true }, SetJustifyV = { FontString = true, EditBox = true },
	SetWordWrap = { FontString = true },
	CreateFontString = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true, GameTooltip = true },
	CreateTexture = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true, GameTooltip = true },
	SetHighlightTexture = { Button = true, CheckButton = true }, RegisterForClicks = { Button = true, CheckButton = true },
	LockHighlight = { Button = true, CheckButton = true }, UnlockHighlight = { Button = true, CheckButton = true },
	Click = { Button = true, CheckButton = true }, SetValue = { Slider = true }, GetValue = { Slider = true },
	SetScript = { NotTexture = true }, RegisterEvent = { NotTexture = true },
}

-- Unknown keys behave like the real client: nil (so `if frame.Method then` works and calling a
-- missing method fails). Methods that exist only on other widget types are also nil.
function Widget:__index(k)
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	local only = ONLY[k]
	local kind = rawget(self, "_kind")
	if only then
		if only.NotTexture then
			if kind == "Texture" or kind == "FontString" then return nil end
		elseif not only[kind] then
			return nil
		end
	end
	local impl = rawget(Widget, k)
	if impl then
		M.usedMethods[k] = true
		return impl
	end
	if REAL[k] then
		M.usedMethods[k] = true
		return function() end
	end
	M.missingMethods[k] = true
	return nil
end

local function NewWidget(kind, name, parent)
	local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _scripts = {}, _shown = true,
		_children = {}, _w = 0, _h = 0 }, Widget)
	if parent and parent._children then table.insert(parent._children, w) end
	if name then _G[name] = w end
	table.insert(M.frames, w)
	return w
end

function Widget.SetScript(w, s, fn) w._scripts[s] = fn end
function Widget.GetScript(w, s) return w._scripts[s] end
function Widget.HookScript(w, s, fn)
	local old = w._scripts[s]
	w._scripts[s] = function(...) if old then old(...) end fn(...) end
end
function Widget.RegisterEvent(w, e) M.events[e] = M.events[e] or {}; table.insert(M.events[e], w) end
function Widget.Show(w)
	local was = w._shown
	w._shown = true
	if not was and w._scripts.OnShow then w._scripts.OnShow(w) end
end
function Widget.Hide(w)
	local was = w._shown
	w._shown = false
	if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Widget.IsShown(w) return w._shown end
function Widget.IsVisible(w)
	local p = w
	while p do
		if not p._shown then return false end
		p = p._parent
	end
	return true
end
function Widget.SetSize(w, x, y) w._w, w._h = x, y end
function Widget.SetWidth(w, x) w._w = x end
function Widget.SetHeight(w, y) w._h = y end
function Widget.GetWidth(w) return w._w end
function Widget.GetHeight(w) return w._h end
function Widget.SetPoint(w, ...)
	local n = select("#", ...)
	assert(n >= 1, "SetPoint needs a point")
	rawset(w, "_points", (rawget(w, "_points") or 0) + 1)
end
function Widget.SetText(w, t)
	assert(t == nil or type(t) == "string" or type(t) == "number", "SetText given " .. type(t))
	w._text = t and tostring(t) or ""
	if w._scripts.OnTextChanged and w._kind == "EditBox" then w._scripts.OnTextChanged(w, false) end
end
function Widget.GetText(w) return w._text or "" end
function Widget.SetChecked(w, v) w._checked = v and true or false end
function Widget.GetChecked(w) return w._checked end
function Widget.GetName(w) return w._name end
function Widget.GetParent(w) return w._parent end
function Widget.GetChildren(w) return unpack(w._children) end
function Widget.HasFocus(w) return M.focus == w end
function Widget.SetFocus(w) M.focus = w end
function Widget.ClearFocus(w)
	if M.focus == w then
		M.focus = nil
		if w._scripts.OnEditFocusLost then w._scripts.OnEditFocusLost(w) end
	end
end
function Widget.Click(w, button)
	if w._scripts.OnClick then w._scripts.OnClick(w, button or "LeftButton") end
end
function Widget.SetValue(w, v)
	w._value = v
	if w._scrollFrame then
		local sf = w._scrollFrame
		if sf._scripts.OnVerticalScroll then sf._scripts.OnVerticalScroll(sf, math.max(0, v)) end
	end
end
function Widget.GetValue(w) return w._value or 0 end
function Widget.SetTexture(w, t)
	assert(t == nil or type(t) == "string" or type(t) == "number", "SetTexture given " .. type(t))
	w._texture = t
end
function Widget.CreateFontString(w, name) return NewWidget("FontString", name, w) end
function Widget.CreateTexture(w, name) return NewWidget("Texture", name, w) end
function Widget.LockHighlight(w) w._locked = true end
function Widget.UnlockHighlight(w) w._locked = false end

local TEMPLATES = {
	FauxScrollFrameTemplate = function(w)
		assert(w._name, "FauxScrollFrameTemplate needs a global name")
		local bar = NewWidget("Slider", w._name .. "ScrollBar", w)
		bar._scrollFrame = w
	end,
	UIPanelButtonTemplate = true, UICheckButtonTemplate = true, InputBoxTemplate = true,
	UIPanelCloseButton = true, BackdropTemplate = true,
}

_G.CreateFrame = function(kind, name, parent, template)
	if template then
		for t in template:gmatch("[^,%s]+") do
			assert(TEMPLATES[t], "unknown template " .. t)
		end
	end
	local w = NewWidget(kind, name, parent)
	if kind == "EditBox" then w._shown = true end
	if template then
		for t in template:gmatch("[^,%s]+") do
			if type(TEMPLATES[t]) == "function" then TEMPLATES[t](w) end
		end
	end
	return w
end

function M.makeTooltip(name)
	local tt = NewWidget("GameTooltip", name)
	tt.lines = {}
	function tt.SetOwner(self) self.lines = {} end
	function tt.SetText(self, t) self.lines = { t } end
	function tt.AddLine(self, t) table.insert(self.lines, t) end
	function tt.AddDoubleLine(self, a, b) table.insert(self.lines, a .. " || " .. b) end
	function tt.SetHyperlink(self, link) self.lines = { "link:" .. link }; self._link = link
		if self._scripts.OnTooltipSetItem then self._scripts.OnTooltipSetItem(self) end
	end
	function tt.GetItem(self) return "x", self._link end
	return tt
end

---------------------------------------------------------------------------
-- Driving the client
---------------------------------------------------------------------------
function M.FireEvent(event, ...)
	for _, w in ipairs(M.events[event] or {}) do
		if w._scripts.OnEvent then w._scripts.OnEvent(w, event, ...) end
	end
end

-- Advance time and run OnUpdate handlers; delivers pending AH results first.
function M.Tick(seconds, step)
	step = step or 0.05
	local elapsed = 0
	repeat
		if M.pendingUpdate then
			M.pendingUpdate = false
			M.FireEvent("AUCTION_ITEM_LIST_UPDATE")
		end
		M.gt = M.gt + step
		elapsed = elapsed + step
		for _, w in ipairs(M.frames) do
			local fn = w._scripts.OnUpdate
			if fn then fn(w, step) end
		end
	until elapsed >= seconds - 1e-9
end

function M.OpenAH()
	M.ahOpen = true
	_G.AuctionFrame = _G.AuctionFrame or CreateFrame("Frame", "AuctionFrame", nil)
	M.FireEvent("AUCTION_HOUSE_SHOW")
end

function M.CloseAH()
	M.ahOpen = false
	M.list = {}
	M.FireEvent("AUCTION_HOUSE_CLOSED")
end

-- Load the addon from its .toc in a fresh namespace.
function M.LoadAddon(dir, savedVariables)
	_G.GameTooltip = M.makeTooltip("GameTooltip")
	_G.ItemRefTooltip = M.makeTooltip("ItemRefTooltip")
	_G.MarketIntelDB = savedVariables
	local ns = {}
	local toc = assert(io.open(dir .. "/MarketIntel.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") then
			local chunk = assert(loadfile(dir .. "/" .. line))
			chunk("MarketIntel", ns)
		end
	end
	M.FireEvent("ADDON_LOADED", "MarketIntel")
	M.FireEvent("PLAYER_LOGIN")
	return ns
end

-- Serialize like WoW's SavedVariables writer: only strings, numbers, booleans and tables.
function M.Serialize(v, seen)
	seen = seen or {}
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "table" then
		assert(not seen[v], "cycle in saved variables")
		seen[v] = true
		local parts = {}
		for k, val in pairs(v) do
			assert(type(k) == "string" or type(k) == "number", "bad key type " .. type(k))
			parts[#parts + 1] = "[" .. M.Serialize(k, seen) .. "]=" .. M.Serialize(val, seen)
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot save a " .. t .. " in SavedVariables")
end

function M.Deserialize(s)
	return assert(loadstring("return " .. s))()
end

return M
