-- Market Intel: main window with Deals, Depth, History, Watchlist and Settings tabs.
local _, ns = ...

local UI = {}
ns.UI = UI

local floor, max, min, format, ipairs, pairs, tonumber = math.floor, math.max, math.min, string.format, ipairs, pairs, tonumber
local ROW_H = 18
local WIDTH, HEIGHT = 740, 480
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local frame
local pages, tabButtons = {}, {}
local TAB_ORDER = { "deals", "depth", "history", "watch", "settings" }
local TAB_TITLES = { deals = "Deals", depth = "Depth", history = "History", watch = "Watchlist", settings = "Settings" }
local currentTab = "deals"
local listCount = 0

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function CheckBox(parent, label, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local fs = Text(cb, "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(label)
	cb.label = fs
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return cb
end

local function EditBox(parent, width, onEnter)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width, 20)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if onEnter then onEnter(self) end
	end)
	return eb
end

local function ShowItemTooltip(owner, key)
	if not key then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local itemString = ns.ItemStringFromKey(key)
	if itemString and GetItemInfo(itemString) then
		GameTooltip:SetHyperlink(itemString)
	else
		local item = ns.History.GetItem(key)
		GameTooltip:SetText(item and item.n or tostring(key))
		if item then ns.AddTooltipLines(GameTooltip, ns.ItemStringFromKey(key)) end
	end
	GameTooltip:Show()
end

-- Insert shift-clicked item links into our focused edit box.
UI.linkTargets = {}
if ChatEdit_InsertLink then
	hooksecurefunc("ChatEdit_InsertLink", function(link)
		if type(link) ~= "string" then return end
		for _, eb in ipairs(UI.linkTargets) do
			if eb:HasFocus() then
				eb:SetText(link:match("%[(.-)%]") or link)
				return
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Sortable, scrolling list
-- columns = { { title, width, justify, text = fn(entry), sort = fn(entry) }, ... }
---------------------------------------------------------------------------
function UI.CreateList(parent, columns, numRows, opts)
	opts = opts or {}
	listCount = listCount + 1
	local list = CreateFrame("Frame", nil, parent)
	list.data, list.columns, list.rows, list.headers = {}, columns, {}, {}
	list.sortCol, list.sortAsc = opts.sortCol, opts.sortAsc

	local totalW = 0
	for _, c in ipairs(columns) do totalW = totalW + c.width end
	list:SetSize(totalW + 26, (numRows + 1) * ROW_H + 4)

	-- headers
	local x = 0
	for i, c in ipairs(columns) do
		local h = CreateFrame("Button", nil, list)
		h:SetSize(c.width, ROW_H)
		h:SetPoint("TOPLEFT", x, 0)
		local fs = Text(h, "GameFontNormalSmall", c.justify)
		fs:SetAllPoints()
		fs:SetText(c.title)
		h.text = fs
		list.headers[i] = h
		h:SetScript("OnClick", function()
			if not c.sort then return end
			if list.sortCol == i then list.sortAsc = not list.sortAsc else list.sortCol, list.sortAsc = i, c.defaultAsc or false end
			list:Sort()
			list:Refresh()
		end)
		x = x + c.width
	end

	local scroll = CreateFrame("ScrollFrame", "MarketIntelList" .. listCount, list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -ROW_H - 2)
	scroll:SetPoint("BOTTOMRIGHT", -24, 0)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() list:Refresh() end)
	end)
	list.scroll = scroll
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local bar = _G[scroll:GetName() .. "ScrollBar"]
		if bar then bar:SetValue(bar:GetValue() - delta * ROW_H * 3) end
	end)

	for r = 1, numRows do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(totalW, ROW_H)
		row:SetPoint("TOPLEFT", 0, -r * ROW_H - 2)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, r % 2 == 0 and 0.04 or 0)
		row.cells = {}
		local cx = 0
		for i, c in ipairs(columns) do
			local fs = Text(row, "GameFontHighlightSmall", c.justify)
			if i == 1 and opts.icons then
				local icon = row:CreateTexture(nil, "ARTWORK")
				icon:SetSize(ROW_H - 2, ROW_H - 2)
				icon:SetPoint("LEFT", cx + 1, 0)
				row.icon = icon
				fs:SetPoint("LEFT", cx + ROW_H + 2, 0)
				fs:SetWidth(c.width - ROW_H - 6)
			else
				fs:SetPoint("LEFT", cx + 2, 0)
				fs:SetWidth(c.width - 6)
			end
			fs:SetHeight(ROW_H)
			fs:SetWordWrap(false)
			row.cells[i] = fs
			cx = cx + c.width
		end
		row:SetScript("OnClick", function(self, button)
			if self.entry and opts.onClick then opts.onClick(self.entry, button) end
		end)
		row:SetScript("OnEnter", function(self)
			if self.entry and opts.onEnter then opts.onEnter(self, self.entry) end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		list.rows[r] = row
	end

	function list:Sort()
		local c = self.columns[self.sortCol or 0]
		if not c or not c.sort then return end
		local asc, get = self.sortAsc, c.sort
		local keyed = {}
		for i, e in ipairs(self.data) do keyed[i] = { e = e, v = get(e), i = i } end
		table.sort(keyed, function(a, b)
			local va, vb = a.v, b.v
			if va == vb then return a.i < b.i end
			if va == nil then return false end
			if vb == nil then return true end
			if asc then return va < vb end
			return va > vb
		end)
		for i, k in ipairs(keyed) do self.data[i] = k.e end
	end

	function list:SetData(data)
		self.data = data
		self:Sort()
		self:Refresh()
	end

	function list:Refresh()
		for i, c in ipairs(self.columns) do
			local arrow = ""
			if self.sortCol == i then arrow = self.sortAsc and " ^" or " v" end
			self.headers[i].text:SetText(c.title .. arrow)
		end
		FauxScrollFrame_Update(scroll, #self.data, numRows, ROW_H)
		local offset = FauxScrollFrame_GetOffset(scroll)
		for r, row in ipairs(self.rows) do
			local e = self.data[r + offset]
			row.entry = e
			if e then
				for i, c in ipairs(self.columns) do row.cells[i]:SetText(c.text(e) or "") end
				if row.icon then row.icon:SetTexture(opts.icons(e)) end
				row:Show()
			else
				row:Hide()
			end
		end
	end

	return list
end

---------------------------------------------------------------------------
-- Common column builders
---------------------------------------------------------------------------
local function ItemLabel(key, name, quality)
	local item = key and ns.History.GetItem(key)
	name = name or (item and item.n) or tostring(key)
	quality = quality or (item and item.q)
	local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then return color.hex .. name .. "|r" end
	return name
end

local function IconFor(e) return ns.GetItemIcon(e.key) or "Interface\\Icons\\INV_Misc_QuestionMark" end

---------------------------------------------------------------------------
-- Deals tab
---------------------------------------------------------------------------
local function BuildDeals(page)
	local info = Text(page, "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 0, 0)
	info:SetWidth(560)
	page.info = info

	Button(page, "Clear", 80, function()
		ns.Analysis.ClearDeals()
		UI.Refresh()
	end):SetPoint("TOPRIGHT", 0, 2)

	local now = function() return time() end
	page.list = UI.CreateList(page, {
		{ title = "Item", width = 190, text = function(e) return ItemLabel(e.key, e.name) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Each", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.unit) end, sort = function(e) return e.unit end, defaultAsc = true },
		{ title = "Normal", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.ref) end, sort = function(e) return e.ref end },
		{ title = "%", width = 45, justify = "RIGHT", text = function(e)
			return e.reason == "watch" and not e.pct and "|cff00ff00watch|r" or ns.FormatPct(e.pct)
		end, sort = function(e) return e.pct or 0 end, defaultAsc = true },
		{ title = "Qty", width = 40, justify = "RIGHT", text = function(e) return tostring(e.count) end, sort = function(e) return e.count end },
		{ title = "Save", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.profit) end, sort = function(e) return e.profit or 0 end },
		{ title = "Seller", width = 95, text = function(e) return e.owner or "?" end, sort = function(e) return e.owner or "" end, defaultAsc = true },
		{ title = "Found", width = 45, justify = "RIGHT", text = function(e) return ns.FormatAge(now() - e.found) end, sort = function(e) return e.found end },
	}, 18, {
		icons = IconFor, sortCol = 6,
		onClick = function(e, button)
			if button == "LeftButton" and IsShiftKeyDown() then
				ChatEdit_InsertLink(ns.GetItemLinkForKey(e.key, e.name))
			elseif button == "LeftButton" then
				ns.Integrations.SearchItem(e.name)
			end
		end,
		onEnter = function(row, e)
			ShowItemTooltip(row, e.key)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(e.reason == "watch" and "Below your watchlist price." or "Priced well below normal.", 0, 1, 0)
			GameTooltip:AddLine("Click: search it on the auction house. Shift-click: link.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -22)

	function page:Update()
		local s = ns.settings
		info:SetText(format("Listings at or below |cffffffff%d%%|r of normal price that save at least %s, plus watchlist hits. Click a row to search it.",
			s.dealPct, ns.FormatMoney(s.minDealProfit)))
		page.list:SetData(ns.deals)
	end
end

---------------------------------------------------------------------------
-- Depth tab
---------------------------------------------------------------------------
local function BuildDepth(page)
	page.onlyBags, page.onlyWarn, page.recent = false, false, true
	local cb1 = CheckBox(page, "Only items in my bags", function(v) page.onlyBags = v; page:Update() end)
	cb1:SetPoint("TOPLEFT", -4, 4)
	local cb2 = CheckBox(page, "Only warnings", function(v) page.onlyWarn = v; page:Update() end)
	cb2:SetPoint("TOPLEFT", 170, 4)
	local cb3 = CheckBox(page, "Seen in last 24h", function(v) page.recent = v; page:Update() end)
	cb3:SetPoint("TOPLEFT", 300, 4)
	cb3:SetChecked(true)
	page.count = Text(page, "GameFontHighlightSmall", "RIGHT")
	page.count:SetPoint("TOPRIGHT", 0, -2)

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 200, text = function(e) return ItemLabel(e.key) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Depth", width = 80, text = function(e)
			return ns.Analysis.FormatRating(e.d.rating) .. (e.d.war and " |cffff5050war|r" or "")
		end, sort = function(e) return ns.Analysis.RATING_ORDER[e.d.rating] end, defaultAsc = true },
		{ title = "Min", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.d.latest.min) end, sort = function(e) return e.d.latest.min end },
		{ title = "Market", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.d.latest.mkt) end, sort = function(e) return e.d.latest.mkt end },
		{ title = "Auctions", width = 60, justify = "RIGHT", text = function(e) return tostring(e.d.latest.auc) end, sort = function(e) return e.d.latest.auc end },
		{ title = "Sellers", width = 55, justify = "RIGHT", text = function(e) return tostring(e.d.latest.sel) end, sort = function(e) return e.d.latest.sel end },
		{ title = "Supply", width = 60, justify = "RIGHT", text = function(e)
			return e.d.ratio and format("%.1fx", e.d.ratio) or "--"
		end, sort = function(e) return e.d.ratio or 0 end },
		{ title = "Seen", width = 45, justify = "RIGHT", text = function(e) return ns.FormatAge(e.d.age) end, sort = function(e) return -e.d.age end },
	}, 18, {
		icons = IconFor, sortCol = 2, sortAsc = true,
		onClick = function(e) UI.ShowHistory(e.key) end,
		onEnter = function(row, e)
			ShowItemTooltip(row, e.key)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(e.d.advice, 1, 0.82, 0, true)
			local cur = ns.current[e.key]
			if cur and cur.ladder then
				GameTooltip:AddLine("Cheapest price levels:", 0.7, 0.7, 0.7)
				for _, lvl in ipairs(cur.ladder) do
					GameTooltip:AddDoubleLine(format("  %d units (%d auctions)", lvl.qty, lvl.auc), ns.FormatMoney(lvl.unit), 1, 1, 1, 1, 1, 1)
				end
				if cur.cheapQty > 0 then
					GameTooltip:AddLine(format("%d units under 90%% of normal; buying them costs %s.", cur.cheapQty, ns.FormatMoney(cur.cheapCost)), 0.4, 1, 0.4, true)
				end
			end
			GameTooltip:AddLine("Click: open price history.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -22)

	function page:Update()
		local now = time()
		local bagKeys = page.onlyBags and ns.Analysis.GetBagKeys()
		local data = {}
		for key, item in pairs(ns.realm.items) do
			if (not page.recent or now - (item.seen or 0) <= 86400) and (not bagKeys or bagKeys[key]) then
				local d = ns.Analysis.GetDepth(key, now)
				if d and (not page.onlyWarn or d.rating == "FLOODED" or d.rating == "CROWDED" or d.war) then
					data[#data + 1] = { key = key, name = item.n or "", d = d }
				end
			end
		end
		page.count:SetText(format("%d items", #data))
		page.list:SetData(data)
	end
end

---------------------------------------------------------------------------
-- History tab: item list, statistics and a daily price chart
---------------------------------------------------------------------------
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local function CreateGraph(parent, w, h)
	local g = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
	g:SetSize(w, h)
	if g.SetBackdrop then
		g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		g:SetBackdropColor(0, 0, 0, 0.5)
		g:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	end
	g.bars = {}
	g.refLine = g:CreateTexture(nil, "OVERLAY")
	g.refLine:SetColorTexture(0.2, 0.8, 1, 0.7)
	g.refLine:SetHeight(1)
	g.hiLabel = Text(g, "GameFontHighlightSmall", "LEFT")
	g.hiLabel:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 2)
	g.loLabel = Text(g, "GameFontHighlightSmall", "LEFT")
	g.loLabel:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -2)
	g.startLabel = Text(g, "GameFontDisableSmall", "LEFT")
	g.startLabel:SetPoint("TOPLEFT", g.loLabel, "BOTTOMLEFT", 0, -2)
	g.endLabel = Text(g, "GameFontDisableSmall", "RIGHT")
	g.endLabel:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, -2)
	g.empty = Text(g, "GameFontDisable", "CENTER")
	g.empty:SetPoint("CENTER")

	local function Bar(i)
		local b = g.bars[i]
		if b then return b end
		b = CreateFrame("Frame", nil, g)
		b:EnableMouse(true)
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetPoint("BOTTOMLEFT")
		b.fill:SetPoint("BOTTOMRIGHT")
		b.minMark = b:CreateTexture(nil, "OVERLAY")
		b.minMark:SetColorTexture(1, 0.82, 0, 1)
		b.minMark:SetHeight(2)
		b.minMark:SetPoint("LEFT")
		b.minMark:SetPoint("RIGHT")
		b:SetScript("OnEnter", function(self)
			local d = self.day
			if not d then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(date("%a %d %b %Y", d.t))
			GameTooltip:AddDoubleLine("Market (avg)", ns.FormatMoney(d.mkt), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine("Lowest min", ns.FormatMoney(d.min), 1, 0.82, 0, 1, 1, 1)
			if d.qty then
				GameTooltip:AddDoubleLine("Avg supply", format("%d units, %d auctions, %d sellers", d.qty, d.auc, d.sel), 1, 1, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		g.bars[i] = b
		return b
	end

	-- series: daily list from History.GetDaily; rangeDays: width of the x axis
	function g:SetSeries(series, rangeDays, ref, now)
		for _, b in ipairs(self.bars) do b:Hide() end
		self.refLine:Hide()
		if #series == 0 then
			self.empty:SetText("No history yet")
			self.empty:Show()
			self.hiLabel:SetText("")
			self.loLabel:SetText("")
			self.startLabel:SetText("")
			self.endLabel:SetText("")
			return
		end
		self.empty:Hide()
		local lo, hi = math.huge, 0
		for _, d in ipairs(series) do
			lo = min(lo, d.min, d.mkt)
			hi = max(hi, d.mkt, d.min)
		end
		if ref then lo, hi = min(lo, ref), max(hi, ref) end
		local pad = max((hi - lo) * 0.1, hi * 0.02, 1)
		lo, hi = max(0, lo - pad), hi + pad
		local W, H = self:GetWidth(), self:GetHeight()
		local function Y(v) return (v - lo) / (hi - lo) * (H - 2) end
		local endT = ns.DayToTime(ns.DayKey(now or time()))
		local startT = endT - (rangeDays - 1) * 86400
		local slot = W / rangeDays
		local barW = max(1, slot - 1)
		for i, d in ipairs(series) do
			local b = Bar(i)
			local idx = floor((d.t - startT) / 86400 + 0.5)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", idx * slot + 1, 1)
			b:SetSize(barW, H - 2)
			b.fill:SetHeight(max(1, Y(d.mkt)))
			if ref and d.mkt < ref * 0.9 then
				b.fill:SetColorTexture(0.3, 0.9, 0.3, 0.8)
			elseif ref and d.mkt > ref * 1.1 then
				b.fill:SetColorTexture(0.95, 0.4, 0.3, 0.8)
			else
				b.fill:SetColorTexture(0.5, 0.6, 0.8, 0.8)
			end
			b.minMark:ClearAllPoints()
			b.minMark:SetPoint("BOTTOMLEFT", 0, max(0, Y(d.min) - 1))
			b.minMark:SetPoint("BOTTOMRIGHT", 0, max(0, Y(d.min) - 1))
			b.day = d
			b:Show()
		end
		if ref then
			self.refLine:ClearAllPoints()
			self.refLine:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 1, Y(ref) + 1)
			self.refLine:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, Y(ref) + 1)
			self.refLine:Show()
		end
		self.hiLabel:SetText(ns.FormatMoney(hi))
		self.loLabel:SetText(ns.FormatMoney(lo))
		self.startLabel:SetText(date("%d %b", startT))
		self.endLabel:SetText(date("%d %b", endT))
	end

	return g
end

local function BuildHistory(page)
	page.range = 30
	local search = EditBox(page, 200, function() page:Update() end)
	search:SetPoint("TOPLEFT", 6, -2)
	search:SetScript("OnTextChanged", function(_, userInput) if userInput then page:Update() end end)
	page.search = search
	table.insert(UI.linkTargets, search)
	local hint = Text(page, "GameFontDisableSmall")
	hint:SetPoint("LEFT", search, "RIGHT", 6, 0)
	hint:SetText("search")

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 170, text = function(e) return ItemLabel(e.key) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Market", width = 80, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.latest and e.latest.mkt) end, sort = function(e) return e.latest and e.latest.mkt or 0 end },
	}, 18, {
		icons = IconFor,
		onClick = function(e) page:Select(e.key) end,
		onEnter = function(row, e) ShowItemTooltip(row, e.key) end,
	})
	page.list:SetPoint("TOPLEFT", 0, -26)

	local detail = CreateFrame("Frame", nil, page)
	detail:SetPoint("TOPLEFT", 290, 0)
	detail:SetPoint("BOTTOMRIGHT")
	page.detail = detail

	local title = Text(detail, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -2)
	title:SetWidth(200)
	title:SetWordWrap(false)
	page.title = title

	local ranges = {}
	for i, days in ipairs({ 7, 30, 90 }) do
		local b = Button(detail, days .. "d", 40, function()
			page.range = days
			page:ShowDetail()
		end)
		b:SetPoint("TOPRIGHT", -(3 - i) * 42, 0)
		ranges[days] = b
	end
	page.ranges = ranges

	page.graph = CreateGraph(detail, 410, 120)
	page.graph:SetPoint("TOPLEFT", 0, -44)

	local left = Text(detail, "GameFontHighlightSmall")
	left:SetPoint("TOPLEFT", page.graph, "BOTTOMLEFT", 0, -34)
	left:SetWidth(205)
	left:SetJustifyV("TOP")
	local right = Text(detail, "GameFontHighlightSmall")
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 5, 0)
	right:SetWidth(200)
	right:SetJustifyV("TOP")
	local advice = Text(detail, "GameFontNormalSmall")
	advice:SetPoint("BOTTOMLEFT", 0, 4)
	advice:SetWidth(410)
	advice:SetJustifyV("BOTTOM")
	page.leftText, page.rightText, page.advice = left, right, advice

	local watchBtn = Button(detail, "Watch", 70, function()
		local item = page.selected and ns.History.GetItem(page.selected)
		if not item then return end
		if ns.Watch.Get(item.n) then ns.Watch.Remove(item.n) else ns.Watch.Add(item.n) end
		page:ShowDetail()
	end)
	watchBtn:SetPoint("TOPRIGHT", -130, 0)
	page.watchBtn = watchBtn

	function page:Select(key)
		page.selected = key
		page:ShowDetail()
	end

	function page:ShowDetail()
		for days, b in pairs(ranges) do
			if days == page.range then b:LockHighlight() else b:UnlockHighlight() end
		end
		local key = page.selected
		local item = key and ns.History.GetItem(key)
		if not item then
			title:SetText("Select an item")
			left:SetText("")
			right:SetText("")
			advice:SetText("Prices are recorded whenever you, Auctionator or TSM search the auction house. Run a full scan for complete coverage.")
			page.graph:SetSeries({}, page.range)
			watchBtn:Hide()
			return
		end
		watchBtn:Show()
		watchBtn:SetText(ns.Watch.Get(item.n) and "Unwatch" or "Watch")
		local now = time()
		title:SetText(ItemLabel(key))
		local ref, source = ns.History.GetReference(key, now)
		page.graph:SetSeries(ns.History.GetDaily(item, now, page.range), page.range, ref, now)
		local st = ns.History.GetStats(key, now)
		local l = st.latest
		local function line(label, value) return "|cffaaaaaa" .. label .. ":|r " .. value end
		local L = {}
		if l then
			L[#L + 1] = line("Min buyout", ns.FormatMoney(l.min))
			L[#L + 1] = line("Market", ns.FormatMoney(l.mkt))
			L[#L + 1] = line("Seen", ns.FormatAge(now - l.t) .. " ago" .. (l.full and "" or " (partial)"))
		end
		L[#L + 1] = line("7d avg", ns.FormatMoney(st.avg7))
		L[#L + 1] = line("30d avg", ns.FormatMoney(st.avg30))
		L[#L + 1] = line("30d low / high", ns.FormatMoney(st.low30) .. " / " .. ns.FormatMoney(st.high30))
		if st.change7 then L[#L + 1] = line("Now vs 7d", format("%+d%%", floor(st.change7 * 100 + 0.5))) end
		if st.volatility then L[#L + 1] = line("Daily swing", format("%d%%", floor(st.volatility * 100 + 0.5))) end
		left:SetText(table.concat(L, "\n"))

		local R = {}
		R[#R + 1] = line("Normal price", ref and (ns.FormatMoney(ref) .. " (" .. source .. ")") or "need more days")
		R[#R + 1] = line("Auctionator", ns.FormatMoney(ns.Integrations.GetAuctionatorPrice(key)))
		if ns.Integrations.HasTSM() then R[#R + 1] = line("TSM market", ns.FormatMoney(ns.Integrations.GetTSMPrice(key))) end
		local d = ns.Analysis.GetDepth(key, now)
		if d then
			R[#R + 1] = line("Depth", ns.Analysis.FormatRating(d.rating) .. format(" (%d auc, %d sellers)", d.latest.auc, d.latest.sel))
			if d.ratio then R[#R + 1] = line("Supply", format("%.1fx normal", d.ratio)) end
		end
		local profile, nDays = ns.History.GetWeekdayProfile(key, now)
		if profile then
			local best, worst
			for wd = 1, 7 do
				if profile[wd] then
					if not best or profile[wd] > profile[best] then best = wd end
					if not worst or profile[wd] < profile[worst] then worst = wd end
				end
			end
			R[#R + 1] = line("Best day to sell", format("%s (%+d%%)", WEEKDAYS[best], floor((profile[best] - 1) * 100 + 0.5)))
			R[#R + 1] = line("Best day to buy", format("%s (%+d%%)", WEEKDAYS[worst], floor((profile[worst] - 1) * 100 + 0.5)))
		else
			R[#R + 1] = line("Weekday pattern", format("needs 14 days (%d so far)", nDays))
		end
		right:SetText(table.concat(R, "\n"))
		advice:SetText(d and d.advice or "")
	end

	function page:Update()
		local keys = ns.History.Search(search:GetText(), 500)
		local data = {}
		for i, key in ipairs(keys) do
			local item = ns.realm.items[key]
			data[i] = { key = key, name = item.n or "", latest = ns.History.GetLatest(key) }
		end
		page.list:SetData(data)
		page:ShowDetail()
	end
end

function UI.ShowHistory(key)
	UI.Show("history")
	pages.history:Select(key)
end

---------------------------------------------------------------------------
-- Watchlist tab
---------------------------------------------------------------------------
local function BuildWatch(page)
	local nameLabel = Text(page, "GameFontNormalSmall")
	nameLabel:SetPoint("TOPLEFT", 4, 0)
	nameLabel:SetText("Item (type or shift-click)")
	local nameBox = EditBox(page, 220)
	nameBox:SetPoint("TOPLEFT", 8, -14)
	table.insert(UI.linkTargets, nameBox)
	local priceLabel = Text(page, "GameFontNormalSmall")
	priceLabel:SetPoint("TOPLEFT", 240, 0)
	priceLabel:SetText("Alert at or below (e.g. 12g 50s)")
	local priceBox = EditBox(page, 120)
	priceBox:SetPoint("TOPLEFT", 244, -14)

	local function Add()
		local name = nameBox:GetText()
		if name == "" then return end
		local priceText = priceBox:GetText()
		local price = ns.ParseMoney(priceText)
		if priceText ~= "" and not price then
			return ns.Print("could not read the price %q. Try 12g, 12g 50s or 75s.", priceText)
		end
		ns.Watch.Add(name, price)
		nameBox:SetText("")
		priceBox:SetText("")
	end
	nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Add() end)
	priceBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Add() end)
	Button(page, "Add / Update", 100, Add):SetPoint("TOPLEFT", 375, -13)
	page.scanBtn = Button(page, "Scan watchlist", 120, function()
		if ns.Scanner.status.scanning then ns.Scanner.StopScan() else ns.Scanner.ScanWatchlist() end
	end)
	page.scanBtn:SetPoint("TOPRIGHT", 0, -13)

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 220, text = function(e) return e.key and ItemLabel(e.key) or e.name end, sort = function(e) return e.lower end, defaultAsc = true },
		{ title = "Alert at", width = 95, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.max) end, sort = function(e) return e.max or 0 end },
		{ title = "Current min", width = 95, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.latest and e.latest.min) end, sort = function(e) return e.latest and e.latest.min or 0 end },
		{ title = "Normal", width = 95, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.key and ns.History.GetReference(e.key)) end },
		{ title = "Status", width = 110, text = function(e)
			if not e.latest then return "|cff909090not seen yet|r" end
			if e.buy then return "|cff00ff00BUY|r" end
			return e.max and "above limit" or "tracking"
		end, sort = function(e) return e.buy and 0 or 1 end, defaultAsc = true },
		{ title = "Seen", width = 50, justify = "RIGHT", text = function(e)
			return e.latest and ns.FormatAge(time() - e.latest.t) or "--"
		end, sort = function(e) return e.latest and e.latest.t or 0 end },
	}, 17, {
		icons = function(e) return e.key and ns.GetItemIcon(e.key) or "Interface\\Icons\\INV_Misc_QuestionMark" end,
		onClick = function(e, button)
			if button == "RightButton" then
				ns.Watch.Remove(e.name)
			elseif IsShiftKeyDown() then
				ns.Integrations.SearchItem(e.name)
			else
				nameBox:SetText(e.name)
				priceBox:SetText(e.max and (floor(e.max / 10000) .. "g " .. (floor(e.max / 100) % 100) .. "s") or "")
			end
		end,
		onEnter = function(row, e)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(e.name)
			GameTooltip:AddLine("Click: edit. Shift-click: search. Right-click: remove.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -42)

	function page:UpdateScanButton()
		local st = ns.Scanner.status
		page.scanBtn:SetText(st.scanning and format("Stop (%d/%d)", min(st.index, st.count), st.count) or "Scan watchlist")
	end

	function page:Update()
		page:UpdateScanButton()
		page.list:SetData(ns.Watch.List())
	end
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
local NUMBER_SETTINGS = {
	{ key = "dealPct", label = "Deal threshold (% of normal)", lo = 5, hi = 100 },
	{ key = "minDealProfit", label = "Minimum saving per deal (gold)", lo = 0, hi = 100000, gold = true },
	{ key = "minHistoryDays", label = "Days of history before trusting it", lo = 1, hi = 14 },
	{ key = "rawDays", label = "Keep every snapshot for (days)", lo = 1, hi = 14 },
	{ key = "keepDays", label = "Keep daily history for (days)", lo = 7, hi = 365 },
	{ key = "minQuality", label = "Minimum item quality (0 grey - 4 epic)", lo = 0, hi = 5 },
	{ key = "floodSellers", label = "Sellers for Flooded", lo = 2, hi = 100 },
	{ key = "crowdSellers", label = "Sellers for Crowded", lo = 2, hi = 100 },
	{ key = "floodRatio", label = "Supply ratio for Flooded", lo = 1, hi = 10, decimal = true },
	{ key = "crowdRatio", label = "Supply ratio for Crowded", lo = 1, hi = 10, decimal = true },
	{ key = "thinRatio", label = "Supply ratio for Thin", lo = 0.05, hi = 1, decimal = true },
}
local BOOL_SETTINGS = {
	{ key = "alertChat", label = "Print deals in chat" },
	{ key = "alertSound", label = "Play a sound for new deals" },
	{ key = "tooltip", label = "Show Market Intel on item tooltips" },
	{ key = "useTSMFallback", label = "Use TSM market value until I have enough history" },
}

local function FormatSetting(def, v)
	if def.gold then return tostring(v / 10000) end
	if def.decimal then return format("%.2f", v) end
	return tostring(v)
end

local function BuildSettings(page)
	page.controls = {}
	for i, def in ipairs(BOOL_SETTINGS) do
		local cb = CheckBox(page, def.label, function(v) ns.settings[def.key] = v end)
		cb:SetPoint("TOPLEFT", -4, 2 - (i - 1) * 24)
		cb.def = def
		page.controls[#page.controls + 1] = cb
	end
	for i, def in ipairs(NUMBER_SETTINGS) do
		local col, row = (i - 1) % 2, floor((i - 1) / 2)
		local x, y = col * 350, -110 - row * 30
		local label = Text(page, "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", x, y - 4)
		label:SetWidth(240)
		label:SetText(def.label)
		local eb = EditBox(page, 70)
		eb:SetPoint("TOPLEFT", x + 250, y)
		eb.def = def
		local function Apply(self)
			local v = tonumber(self:GetText())
			if v then
				if def.gold then v = floor(v * 10000 + 0.5) end
				local lo, hi = def.gold and def.lo * 10000 or def.lo, def.gold and def.hi * 10000 or def.hi
				v = max(lo, min(hi, v))
				if not def.decimal then v = floor(v + 0.5) end
				ns.settings[def.key] = v
			end
			self:SetText(FormatSetting(def, ns.settings[def.key]))
			UI.Refresh()
		end
		eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		eb:SetScript("OnEditFocusLost", Apply)
		page.controls[#page.controls + 1] = eb
	end

	page.addons = Text(page, "GameFontHighlightSmall")
	page.addons:SetPoint("BOTTOMLEFT", 0, 34)
	page.addons:SetWidth(700)

	Button(page, "Compact old data", 140, function()
		ns.History.Compact(time())
		ns.Print("old data compacted.")
		UI.Refresh()
	end):SetPoint("BOTTOMLEFT", 0, 0)
	Button(page, "Reset defaults", 120, function()
		for k, v in pairs(ns.DEFAULTS) do ns.settings[k] = v end
		page:Update()
	end):SetPoint("BOTTOMLEFT", 150, 0)
	Button(page, "Delete all history", 140, function()
		StaticPopup_Show("MARKETINTEL_RESET")
	end):SetPoint("BOTTOMRIGHT", 0, 0)

	function page:Update()
		for _, c in ipairs(page.controls) do
			if c.SetChecked then
				c:SetChecked(ns.settings[c.def.key] and true or false)
			elseif not c:HasFocus() then
				c:SetText(FormatSetting(c.def, ns.settings[c.def.key]))
			end
		end
		local items, snaps, days = ns.History.CountData()
		page.addons:SetText(format("Auction house: |cffffffff%s|r   Auctionator: %s   TSM: %s   Stored: %d items, %d snapshots, %d daily summaries",
			ns.realmKey or "?",
			ns.Integrations.HasAuctionator() and "|cff00ff00found|r" or "|cffff5050not found|r",
			ns.Integrations.HasTSM() and "|cff00ff00found|r" or "|cff909090not found|r",
			items, snaps, days))
	end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local BUILDERS = { deals = BuildDeals, depth = BuildDepth, history = BuildHistory, watch = BuildWatch, settings = BuildSettings }

local function UpdateStatus()
	if not frame then return end
	local st = ns.Scanner.status
	local text
	if st.fullScan then
		text = format("Reading full scan... %d%%", floor((st.fullScanProgress or 0) * 100))
	elseif st.scanning then
		text = format("Scanning watchlist %d/%d", min(st.index, st.count), st.count)
	elseif ns.Scanner.IsAuctionHouseOpen() then
		text = "Auction house open - searches are being recorded"
	else
		text = "Open the auction house and search (or run an Auctionator full scan) to collect prices"
	end
	frame.status:SetText(format("|cffaaaaaa%s|r   %s", ns.realmKey or "", text))
end

local function CreateMain()
	frame = CreateFrame("Frame", "MarketIntelFrame", UIParent, BACKDROP_TEMPLATE)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	frame:Hide()
	tinsert(UISpecialFrames, "MarketIntelFrame")

	local title = Text(frame, "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Market Intel")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	for i, tab in ipairs(TAB_ORDER) do
		local b = Button(frame, TAB_TITLES[tab], 100, function() UI.Show(tab) end)
		b:SetPoint("TOPLEFT", 18 + (i - 1) * 104, -38)
		tabButtons[tab] = b
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 20, -70)
		page:SetPoint("BOTTOMRIGHT", -20, 30)
		page:Hide()
		BUILDERS[tab](page)
		pages[tab] = page
	end

	frame.status = Text(frame, "GameFontHighlightSmall")
	frame.status:SetPoint("BOTTOMLEFT", 20, 14)
	frame.status:SetWidth(WIDTH - 40)

	frame:SetScript("OnShow", function() UI.Refresh(true) end)
end

function UI.Show(tab)
	if not frame then CreateMain() end
	if tab and pages[tab] then currentTab = tab end
	for name, page in pairs(pages) do
		if name == currentTab then page:Show() else page:Hide() end
		if name == currentTab then tabButtons[name]:LockHighlight() else tabButtons[name]:UnlockHighlight() end
	end
	frame:Show()
	UI.Refresh(true)
end

function UI.Toggle()
	if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

function UI.IsShown() return frame ~= nil and frame:IsShown() end
function UI.GetFrame() return frame end
function UI.GetPage(tab) return pages[tab] end

-- Refresh the visible tab. Data events can arrive many times a second, so
-- non-forced refreshes are throttled: once a second, or every 10 seconds on
-- the Depth tab, which rates every recently seen item and is the slowest.
local lastRefresh, pendingRefresh = 0, nil
function UI.Refresh(force)
	if not frame or not frame:IsShown() then return end
	UpdateStatus()
	local now = GetTime()
	local interval = currentTab == "depth" and 10 or 1
	if not force and now - lastRefresh < interval then
		if not pendingRefresh then
			pendingRefresh = ns.After(interval - (now - lastRefresh), function()
				pendingRefresh = nil
				UI.Refresh(true)
			end)
		end
		return
	end
	lastRefresh = now
	pages[currentTab]:Update()
end

ns.On("MI_DATA_UPDATED", function() UI.Refresh() end)
ns.On("MI_SCAN_PROGRESS", function()
	UpdateStatus()
	if pages.watch then pages.watch:UpdateScanButton() end
	if currentTab == "watch" then UI.Refresh() end
end)
ns.On("MI_AH_CLOSED", function() UpdateStatus() end)

-- A button on the auction house window.
ns.On("MI_AH_OPENED", function()
	UpdateStatus()
	if UI.ahButton or not AuctionFrame then return end
	local b = Button(AuctionFrame, "Market Intel", 110, function() UI.Toggle() end)
	b:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", -2, -40)
	UI.ahButton = b
end)
