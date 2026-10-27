-- Market Intel: main window with Deals, BoE Snipe, Flips, Depth, History, Crafting,
-- Ledger, Watchlist and Settings tabs.
local _, ns = ...

local UI = {}
ns.UI = UI

local floor, max, min, format, ipairs, pairs, tonumber = math.floor, math.max, math.min, string.format, ipairs, pairs, tonumber
local ROW_H = 18
local WIDTH, HEIGHT = 880, 500
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local frame
local pages, tabButtons = {}, {}
local TAB_ORDER = { "deals", "snipe", "flips", "depth", "history", "crafting", "ledger", "watch", "settings" }
local TAB_TITLES = {
	deals = "Deals", snipe = "BoE Snipe", flips = "Flips", depth = "Depth", history = "History",
	crafting = "Crafting", ledger = "Ledger", watch = "Watchlist", settings = "Settings",
}
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
	name = name or (key and ns.History.GetName(key)) or ("item " .. tostring(key))
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
	info:SetWidth(700)
	page.info = info

	Button(page, "Clear", 70, function()
		ns.Analysis.ClearDeals()
		UI.Refresh()
	end):SetPoint("TOPRIGHT", 0, 2)
	Button(page, "CSV", 50, function()
		local rows = {}
		for _, d in ipairs(ns.deals) do
			rows[#rows + 1] = { d.name, ns.ItemIDFromKey(d.key), d.unit, d.ref, d.pct, d.count, d.profit, d.owner, d.reason,
				d.craft and d.craft.name, d.craft and d.craft.profit, date("%Y-%m-%d %H:%M", d.found) }
		end
		ns.Export.Show("Deals", { "item", "itemID", "unit_copper", "normal_copper", "pct_of_normal", "qty", "saving_copper",
			"seller", "reason", "helps_recipe", "recipe_profit_copper", "found" }, rows)
	end):SetPoint("TOPRIGHT", -74, 2)

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
		{ title = "Craft", width = 110, text = function(e)
			return e.craft and ("|cff40ff40" .. ns.FormatMoney(e.craft.profit) .. "|r") or ""
		end, sort = function(e) return e.craft and e.craft.profit or -1 end },
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
			if e.craft then
				GameTooltip:AddLine(format("At this price, crafting %s makes %s (was %s).", e.craft.name,
					ns.FormatMoney(e.craft.profit), ns.FormatMoney(e.craft.before)), 0.4, 1, 0.4, true)
			end
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
		{ title = "Post at", width = 95, justify = "RIGHT", text = function(e)
			e.post = e.post or ns.Advisor.PostPrice(e.key) or false
			if not e.post then return "" end
			return (e.post.action == "HOLD" and "|cffff9900hold|r " or "") .. ns.FormatMoney(e.post.price)
		end, sort = function(e)
			e.post = e.post or ns.Advisor.PostPrice(e.key) or false
			return e.post and e.post.price or 0
		end },
	}, 18, {
		icons = IconFor, sortCol = 2, sortAsc = true,
		onClick = function(e) UI.ShowHistory(e.key) end,
		onEnter = function(row, e)
			ShowItemTooltip(row, e.key)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(e.d.advice, 1, 0.82, 0, true)
			local post = ns.Advisor.PostPrice(e.key)
			if post then
				GameTooltip:AddDoubleLine("Post at: " .. ns.Advisor.ACTION_TEXT[post.action], ns.FormatMoney(post.price), 1, 1, 1, 1, 1, 1)
				GameTooltip:AddLine(post.reason, 0.8, 0.8, 0.8, true)
			end
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
	Button(page, "CSV all", 60, function()
		local rows, now = {}, time()
		for _, key in ipairs(ns.History.Search("", nil)) do
			local st = ns.History.GetStats(key, now)
			local ref = ns.History.GetReference(key, now)
			local d = ns.Analysis.GetDepth(key, now)
			rows[#rows + 1] = { ns.History.GetName(key), ns.ItemIDFromKey(key), st.latest and st.latest.min, st.latest and st.latest.mkt,
				st.avg7 and floor(st.avg7), st.avg30 and floor(st.avg30), ref and floor(ref), d and d.rating, st.latest and date("%Y-%m-%d %H:%M", st.latest.t) }
		end
		ns.Export.Show("All items", { "item", "itemID", "min_copper", "market_copper", "avg7_copper", "avg30_copper", "normal_copper", "depth", "last_seen" }, rows)
	end):SetPoint("LEFT", search, "RIGHT", 8, 0)

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 182, text = function(e) return ItemLabel(e.key) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Market", width = 70, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.latest and e.latest.mkt) end, sort = function(e) return e.latest and e.latest.mkt or 0 end },
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

	page.graph = CreateGraph(detail, 540, 120)
	page.graph:SetPoint("TOPLEFT", 0, -44)

	local left = Text(detail, "GameFontHighlightSmall")
	left:SetPoint("TOPLEFT", page.graph, "BOTTOMLEFT", 0, -34)
	left:SetWidth(265)
	left:SetJustifyV("TOP")
	local right = Text(detail, "GameFontHighlightSmall")
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 5, 0)
	right:SetWidth(270)
	right:SetJustifyV("TOP")
	local advice = Text(detail, "GameFontNormalSmall")
	advice:SetPoint("BOTTOMLEFT", 0, 4)
	advice:SetWidth(540)
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
	local csvBtn = Button(detail, "CSV", 50, function()
		local item = page.selected and ns.History.GetItem(page.selected)
		if not item then return end
		local rows = {}
		for _, d in ipairs(ns.History.GetDaily(item, time())) do
			rows[#rows + 1] = { date("%Y-%m-%d", d.t), d.min, floor(d.mkt + 0.5), d.qty and floor(d.qty + 0.5), d.auc and floor(d.auc + 0.5), d.sel and floor(d.sel + 0.5) }
		end
		ns.Export.Show("History of " .. (item.n or "item"), { "date", "min_copper", "market_copper", "qty", "auctions", "sellers" }, rows)
	end)
	csvBtn:SetPoint("TOPRIGHT", -204, 0)
	page.csvBtn = csvBtn

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
			csvBtn:Hide()
			return
		end
		watchBtn:Show()
		csvBtn:Show()
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
			local age = now - l.t
			L[#L + 1] = line("Seen", (age < 60 and "just now" or (ns.FormatAge(age) .. " ago")) .. (l.full and "" or " (partial)"))
		end
		L[#L + 1] = line("7d avg", ns.FormatMoney(st.avg7))
		L[#L + 1] = line("30d avg", ns.FormatMoney(st.avg30))
		L[#L + 1] = line("30d low / high", ns.FormatMoney(st.low30) .. " / " .. ns.FormatMoney(st.high30))
		if st.change7 then L[#L + 1] = line("Now vs 7d", format("%+d%%", floor(st.change7 * 100 + 0.5))) end
		if st.volatility then L[#L + 1] = line("Daily swing", format("%d%%", floor(st.volatility * 100 + 0.5))) end
		left:SetText(table.concat(L, "\n"))

		local R = {}
		R[#R + 1] = line("Normal price", ref and (ns.FormatMoney(ref) .. " (" .. source .. ")") or "need more days")
		if ns.Integrations.HasAuctionator() then
			R[#R + 1] = line("Auctionator", ns.FormatMoney(ns.Integrations.GetAuctionatorPrice(key)))
		end
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
		page.scanBtn:SetText(st.scanning and format("Stop scan (%d/%d)", min(st.index, st.count), st.count) or "Scan watchlist")
	end

	function page:Update()
		page:UpdateScanButton()
		page.list:SetData(ns.Watch.List())
	end
end

---------------------------------------------------------------------------
-- BoE Snipe tab
---------------------------------------------------------------------------
local function BuildSnipe(page)
	local info = Text(page, "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 0, 0)
	info:SetWidth(560)
	page.info = info
	page.scanBtn = Button(page, "Scan BoE", 120, function()
		if ns.Scanner.status.scanning then ns.Scanner.StopScan() else ns.Snipe.Scan() end
	end)
	page.scanBtn:SetPoint("TOPRIGHT", -128, 2)
	info:SetWidth(560)
	Button(page, "Clear", 70, function() ns.Snipe.Clear(); UI.Refresh() end):SetPoint("TOPRIGHT", -54, 2)
	Button(page, "CSV", 50, function()
		local rows = {}
		for _, sn in ipairs(ns.snipes) do
			rows[#rows + 1] = { sn.name, ns.ItemIDFromKey(sn.key), sn.level, sn.unit, sn.ref, sn.pct, sn.sold, sn.source, sn.owner,
				date("%Y-%m-%d %H:%M", sn.found) }
		end
		ns.Export.Show("BoE snipes", { "item", "itemID", "req_level", "price_copper", "normal_copper", "pct_of_normal",
			"region_sold_per_day", "price_source", "seller", "found" }, rows)
	end):SetPoint("TOPRIGHT", 0, 2)

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 210, text = function(e) return ItemLabel(e.key, e.name, e.quality) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Lvl", width = 35, justify = "RIGHT", text = function(e) return tostring(e.level) end, sort = function(e) return e.level end },
		{ title = "Price", width = 90, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.unit) end, sort = function(e) return e.unit end, defaultAsc = true },
		{ title = "Normal", width = 90, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.ref) end, sort = function(e) return e.ref end },
		{ title = "%", width = 45, justify = "RIGHT", text = function(e) return ns.FormatPct(e.pct) end, sort = function(e) return e.pct end, defaultAsc = true },
		{ title = "Sold/day", width = 60, justify = "RIGHT", text = function(e)
			return e.sold and format("%.2f", e.sold) or "|cff909090?|r"
		end, sort = function(e) return e.sold or 0 end },
		{ title = "Source", width = 75, text = function(e) return e.source end, sort = function(e) return e.source end, defaultAsc = true },
		{ title = "Seller", width = 95, text = function(e) return e.owner or "?" end, sort = function(e) return e.owner or "" end, defaultAsc = true },
		{ title = "Found", width = 45, justify = "RIGHT", text = function(e) return ns.FormatAge(time() - e.found) end, sort = function(e) return e.found end },
	}, 18, {
		icons = IconFor, sortCol = 5, sortAsc = true,
		onClick = function(e, button)
			if button == "LeftButton" and IsShiftKeyDown() then
				ChatEdit_InsertLink(ns.GetItemLinkForKey(e.key, e.name, e.quality))
			elseif button == "LeftButton" then
				ns.Integrations.SearchItem(e.name)
			end
		end,
		onEnter = function(row, e)
			ShowItemTooltip(row, e.key)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(format("Listed at %s of its normal price (%s). You would save %s.", ns.FormatPct(e.pct),
				e.source, ns.FormatMoney(e.profit)), 1, 0.5, 0, true)
			GameTooltip:AddLine("Click: search it. Shift-click: link. Market Intel never buys for you.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -24)

	function page:UpdateScanButton()
		local st = ns.Scanner.status
		if st.scanning then
			page.scanBtn:SetText(format("Stop scan (%d/%d)", min(st.index, st.count), st.count))
		else
			page.scanBtn:SetText(format("Scan BoE %d-%d", ns.settings.snipeMinLevel, ns.settings.snipeMaxLevel))
		end
	end

	function page:Update()
		local s = ns.settings
		local note = ns.Integrations.HasTSM() and "" or " |cffff5050TSM not found: no sale-rate data.|r"
		info:SetText(format("Blue/epic gear, required level %d-%d, listed at or below %d%% of normal%s.%s",
			s.snipeMinLevel, s.snipeMaxLevel, s.snipePct,
			s.snipeRequireSaleRate and format(", selling %.2f+ a day in your region", s.snipeMinSold) or "", note))
		page:UpdateScanButton()
		page.list:SetData(ns.snipes)
	end
end

---------------------------------------------------------------------------
-- Flips tab
---------------------------------------------------------------------------
local RISK_COLOR = { Low = "|cff40ff40", Medium = "|cffffd200", High = "|cffff5050" }

local function BuildFlips(page)
	local info = Text(page, "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 0, 0)
	info:SetWidth(720)
	page.info = info
	Button(page, "CSV", 50, function()
		local rows = {}
		for _, f in ipairs(page.list.data) do
			rows[#rows + 1] = { f.name, ns.ItemIDFromKey(f.key), f.qty, f.auctions, f.maxUnit, f.cost, f.resale, f.profit, f.roi, f.risk }
		end
		ns.Export.Show("Flips", { "item", "itemID", "buy_units", "buy_auctions", "max_unit_copper", "cost_copper",
			"resell_unit_copper", "profit_copper", "roi", "risk" }, rows)
	end):SetPoint("TOPRIGHT", 0, 2)

	page.list = UI.CreateList(page, {
		{ title = "Item", width = 200, text = function(e) return ItemLabel(e.key, e.name) end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Buy", width = 75, justify = "RIGHT", text = function(e) return format("%d (%d)", e.qty, e.auctions) end, sort = function(e) return e.qty end },
		{ title = "Up to", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.maxUnit) end, sort = function(e) return e.maxUnit end },
		{ title = "Cost", width = 95, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.cost) end, sort = function(e) return e.cost end },
		{ title = "Relist at", width = 85, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.resale) end, sort = function(e) return e.resale end },
		{ title = "Profit", width = 95, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.profit) end, sort = function(e) return e.profit end },
		{ title = "Return", width = 55, justify = "RIGHT", text = function(e) return ns.FormatPct(e.roi) end, sort = function(e) return e.roi end },
		{ title = "Risk", width = 60, text = function(e) return (RISK_COLOR[e.risk] or "") .. e.risk .. "|r" end,
			sort = function(e) return e.risk == "Low" and 1 or e.risk == "Medium" and 2 or 3 end, defaultAsc = true },
	}, 18, {
		icons = IconFor, sortCol = 6,
		onClick = function(e) ns.Integrations.SearchItem(e.name) end,
		onEnter = function(row, e)
			ShowItemTooltip(row, e.key)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(format("Suggestion: buy the %d cheapest auction%s (%d units, up to %s each) for %s,",
				e.auctions, e.auctions == 1 and "" or "s", e.qty, ns.FormatMoney(e.maxUnit), ns.FormatMoney(e.cost)), 1, 1, 1, true)
			GameTooltip:AddLine(format("then relist at %s each. After the 5%% cut and deposits: %s profit (%s return).",
				ns.FormatMoney(e.resale), ns.FormatMoney(e.profit), ns.FormatPct(e.roi)), 1, 1, 1, true)
			GameTooltip:AddLine(format("Risk %s: depth %s%s.", e.risk, e.rating and ns.Analysis.RATING_TEXT[e.rating] or "unknown",
				e.sold and format(", TSM region sells %.1f a day", e.sold) or ""), 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine("Click: search it. Market Intel never buys for you.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -24)

	function page:Update()
		local s = ns.settings
		info:SetText(format("Suggestions only, nothing is bought for you. At least %s profit and %d%% return, from searches in the last %d min.",
			ns.FormatMoney(s.flipMinProfit), s.flipMinROI, s.flipMaxAge))
		page.list:SetData(ns.Advisor.FindFlips(time()))
	end
end

---------------------------------------------------------------------------
-- Crafting tab
---------------------------------------------------------------------------
local function BuildCrafting(page)
	page.showAll = false
	local cb = CheckBox(page, "Show all known recipes (right-click a row to star it)", function(v) page.showAll = v; page:Update() end)
	cb:SetPoint("TOPLEFT", -4, 4)
	page.source = Text(page, "GameFontHighlightSmall", "RIGHT")
	page.source:SetPoint("TOPRIGHT", -58, -2)
	Button(page, "CSV", 50, function()
		local rows = {}
		for _, e in ipairs(page.list.data) do
			rows[#rows + 1] = { e.name, e.prof, e.cost, e.value, e.profit, e.margin, e.dealProfit, e.fav or "" }
		end
		ns.Export.Show("Crafting", { "recipe", "profession", "cost_copper", "sells_for_copper", "profit_copper", "margin",
			"profit_with_deals_copper", "favourite_from" }, rows)
	end):SetPoint("TOPRIGHT", 0, 2)

	page.list = UI.CreateList(page, {
		{ title = "Recipe", width = 210, text = function(e) return e.key and ItemLabel(e.key, e.name) or e.name end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Profession", width = 90, text = function(e) return e.prof end, sort = function(e) return e.prof end, defaultAsc = true },
		{ title = "Cost", width = 90, justify = "RIGHT", text = function(e)
			return e.missing and "|cff909090missing|r" or ns.FormatMoney(e.cost)
		end, sort = function(e) return e.cost end },
		{ title = "Sells for", width = 90, justify = "RIGHT", text = function(e) return ns.FormatMoney(e.value) end, sort = function(e) return e.value or 0 end },
		{ title = "Profit", width = 95, justify = "RIGHT", text = function(e)
			if not e.profit then return "--" end
			return (e.profit >= 0 and "|cff40ff40" or "|cffff5050") .. (e.profit < 0 and "-" or "") .. ns.FormatMoney(math.abs(e.profit)) .. "|r"
		end, sort = function(e) return e.profit or -math.huge end },
		{ title = "Margin", width = 55, justify = "RIGHT", text = function(e) return ns.FormatPct(e.margin) end, sort = function(e) return e.margin or -math.huge end },
		{ title = "With deals", width = 95, justify = "RIGHT", text = function(e)
			if not e.dealProfit then return "" end
			return (e.dealProfit >= 0 and "|cff40ff40" or "|cffff5050") .. (e.dealProfit < 0 and "-" or "") .. ns.FormatMoney(math.abs(e.dealProfit)) .. "|r"
		end, sort = function(e) return e.dealProfit or -math.huge end },
		{ title = "Fav", width = 30, text = function(e) return e.fav == "TSM" and "|cffffd200TSM|r" or (e.fav and "|cffffd200*|r" or "") end },
	}, 18, {
		icons = function(e) return e.key and ns.GetItemIcon(e.key) or "Interface\\Icons\\Trade_Engraving" end, sortCol = 5,
		onClick = function(e, button)
			if button == "RightButton" then
				ns.Crafting.ToggleStar(e.spellID)
			elseif e.key then
				UI.ShowHistory(e.key)
			end
		end,
		onEnter = function(row, e)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(e.name)
			if e.rec.made and e.rec.made ~= 1 then GameTooltip:AddLine(format("Makes %.1f on average", e.rec.made), 0.8, 0.8, 0.8) end
			for _, part in ipairs(e.parts) do
				GameTooltip:AddDoubleLine(format("%dx %s", part.count, part.name or "?"),
					part.price and (ns.FormatMoney(part.price * part.count) .. " |cff909090(" .. part.source .. ")|r") or "|cffff5050no price|r", 1, 1, 1, 1, 1, 1)
			end
			if e.value then GameTooltip:AddDoubleLine("Sells for (after 5% cut)", ns.FormatMoney(e.value * 0.95), 1, 1, 1, 1, 1, 1) end
			GameTooltip:AddLine(e.fav == "TSM" and "Starred in TSM." or "Right-click: star or unstar in Market Intel.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -24)

	function page:Update()
		local _, tsmFound = ns.Crafting.GetFavorites()
		local n = 0
		for _ in pairs(ns.db.recipes or {}) do n = n + 1 end
		page.source:SetText(format("%d recipes known. TSM favourites: %s", n,
			tsmFound and "|cff40ff40read|r" or "|cffff9900not found (star recipes here instead)|r"))
		page.list:SetData(ns.Crafting.List(page.showAll))
	end
end

---------------------------------------------------------------------------
-- Ledger tab
---------------------------------------------------------------------------
local TYPE_TEXT = { sold = "|cff40ff40Sold|r", bought = "|cff66bbffBought|r", expired = "|cffff9900Expired|r", cancelled = "|cff909090Cancelled|r" }

local function BuildLedger(page)
	page.days = 30
	page.summary = Text(page, "GameFontHighlightSmall")
	page.summary:SetPoint("TOPLEFT", 0, -2)
	page.summary:SetWidth(560)
	page.periods = {}
	for i, days in ipairs({ 7, 30, 0 }) do
		local b = Button(page, days == 0 and "All" or (days .. "d"), 44, function() page.days = days; page:Update() end)
		b:SetPoint("TOPRIGHT", -54 - (3 - i) * 46, 2)
		page.periods[days] = b
	end
	Button(page, "CSV", 50, function()
		local rows = {}
		for _, e in ipairs(ns.Ledger.Entries(page.days > 0 and page.days or nil)) do
			rows[#rows + 1] = { date("%Y-%m-%d %H:%M", e.t), e.type, e.name, e.qty, e.gross, e.cut, e.net, e.who }
		end
		ns.Export.Show("Ledger", { "date", "type", "item", "qty", "amount_copper", "ah_cut_copper", "net_copper", "other_player" }, rows)
	end):SetPoint("TOPRIGHT", 0, 2)

	page.list = UI.CreateList(page, {
		{ title = "Date", width = 95, text = function(e) return date("%d %b %H:%M", e.t) end, sort = function(e) return e.t end },
		{ title = "Type", width = 75, text = function(e) return TYPE_TEXT[e.type] or e.type end, sort = function(e) return e.type end, defaultAsc = true },
		{ title = "Item", width = 220, text = function(e) return e.key and ItemLabel(e.key, e.name) or e.name end, sort = function(e) return e.name end, defaultAsc = true },
		{ title = "Qty", width = 40, justify = "RIGHT", text = function(e) return e.qty and tostring(e.qty) or "?" end, sort = function(e) return e.qty or 0 end },
		{ title = "Amount", width = 95, justify = "RIGHT", text = function(e) return e.gross and ns.FormatMoney(e.gross) or "" end, sort = function(e) return e.gross or 0 end },
		{ title = "AH cut", width = 80, justify = "RIGHT", text = function(e) return e.cut and e.cut > 0 and ns.FormatMoney(e.cut) or "" end, sort = function(e) return e.cut or 0 end },
		{ title = "Player", width = 110, text = function(e) return e.who or "" end, sort = function(e) return e.who or "" end, defaultAsc = true },
	}, 17, {
		icons = function(e) return e.key and ns.GetItemIcon(e.key) or "Interface\\Icons\\INV_Letter_15" end, sortCol = 1,
		onEnter = function(row, e)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(e.name or "?")
			local st = ns.Ledger.ItemStats(e.name)
			if st then
				GameTooltip:AddDoubleLine("Last 30 days", format("%d sold, %d expired", st.sold, st.expired), 1, 1, 1, 1, 1, 1)
				GameTooltip:AddDoubleLine("Sell-through", ns.FormatPct(st.sellThrough), 1, 1, 1, 1, 1, 1)
				if st.avgUnit then GameTooltip:AddDoubleLine("Average price each", ns.FormatMoney(st.avgUnit), 1, 1, 1, 1, 1, 1) end
			end
			GameTooltip:Show()
		end,
	})
	page.list:SetPoint("TOPLEFT", 0, -40)

	function page:Update()
		for days, b in pairs(page.periods) do
			if days == page.days then b:LockHighlight() else b:UnlockHighlight() end
		end
		local days = page.days > 0 and page.days or nil
		local sm = ns.Ledger.Summary(days)
		local entries = ns.Ledger.Entries(days)
		if #entries == 0 then
			page.summary:SetText("No auction mail recorded yet. Open your mailbox: sales, purchases and expired auctions are read from it.")
		else
			page.summary:SetText(format("Sales %s (%d)  -  AH cut %s  -  Bought %s (%d)\nNet profit %s%s  -  Expired %d, cancelled %d  -  Sell-through %s",
				ns.FormatMoney(sm.sales), sm.sold, ns.FormatMoney(sm.cut), ns.FormatMoney(sm.spent), sm.bought,
				sm.profit < 0 and "-" or "", ns.FormatMoney(math.abs(sm.profit)), sm.expired, sm.cancelled, ns.FormatPct(sm.sellThrough)))
		end
		page.list:SetData(entries)
	end
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
local NUMBER_SETTINGS = {
	{ key = "dealPct", label = "Deal threshold (% of normal)", lo = 5, hi = 100,
		tip = "A listing is a deal when its price per item is at or below this percentage of the normal price." },
	{ key = "minDealProfit", label = "Min. saving per deal (gold)", lo = 0, hi = 100000, gold = true,
		tip = "Ignore deals that save less than this per auction, so cheap items do not spam alerts." },
	{ key = "strongAlertMin", label = "Big alert from saving (gold)", lo = 0, hi = 100000, gold = true,
		tip = "Deals saving at least this much get the big alert (screen message and taskbar flash). Watchlist hits and BoE snipes always do." },
	{ key = "minHistoryDays", label = "History days before trusting", lo = 1, hi = 14,
		tip = "How many past days of prices an item needs before its normal price is used for deals." },
	{ key = "rawDays", label = "Keep every scan for (days)", lo = 1, hi = 14,
		tip = "Individual scans are kept this long (used for price-war detection), then merged into one entry per day." },
	{ key = "keepDays", label = "Days kept: searched items", lo = 7, hi = 365,
		tip = "Daily history kept for items you search for or watch." },
	{ key = "scanKeepDays", label = "Days kept: full-scan items", lo = 4, hi = 365,
		tip = "Daily history kept for items only ever seen in full scans. Lower this if your saved data gets large." },
	{ key = "minQuality", label = "Min. quality to record (0-4)", lo = 0, hi = 5,
		tip = "Items below this quality are not recorded. 0 grey, 1 white, 2 green, 3 blue, 4 epic." },
	{ key = "floodSellers", label = "Sellers for Flooded", lo = 2, hi = 100,
		tip = "An item with at least this many sellers is rated Flooded." },
	{ key = "crowdSellers", label = "Sellers for Crowded", lo = 2, hi = 100,
		tip = "An item with at least this many sellers is rated Crowded." },
	{ key = "floodRatio", label = "Supply ratio for Flooded", lo = 1, hi = 10, decimal = true,
		tip = "Flooded when the units on sale are at least this many times the item's normal supply." },
	{ key = "crowdRatio", label = "Supply ratio for Crowded", lo = 1, hi = 10, decimal = true,
		tip = "Crowded when the units on sale are at least this many times the item's normal supply." },
	{ key = "thinRatio", label = "Supply ratio for Thin", lo = 0.05, hi = 1, decimal = true,
		tip = "Thin when the units on sale are at most this fraction of the item's normal supply." },
	{ key = "postUndercut", label = "Undercut by (copper)", lo = 0, hi = 100000,
		tip = "The posting advisor suggests this much below the cheapest auction." },
	{ key = "postFloorPct", label = "Hold below (% of normal)", lo = 10, hi = 100,
		tip = "The posting advisor says Hold instead of undercutting below this percentage of the normal price." },
	{ key = "postPremiumPct", label = "Post-high premium (%)", lo = 0, hi = 200,
		tip = "When nobody else is selling, suggest this much above the normal price." },
	{ key = "flipMinProfit", label = "Flip min. profit (gold)", lo = 0, hi = 100000, gold = true,
		tip = "Only suggest flips that make at least this much after the AH cut and deposits." },
	{ key = "flipMinROI", label = "Flip min. return (%)", lo = 1, hi = 1000,
		tip = "Only suggest flips that return at least this percentage of the gold spent." },
	{ key = "flipMaxAge", label = "Flips from searches within (min)", lo = 5, hi = 1440,
		tip = "Flips are worked out from searches this recent; older listings may already be gone." },
	{ key = "snipePct", label = "Snipe below (% of normal)", lo = 5, hi = 100,
		tip = "BoE snipes are gear listed at or below this percentage of its normal price." },
	{ key = "snipeMinLevel", label = "Snipe min. required level", lo = 1, hi = 70,
		tip = "Lowest required level for BoE snipes." },
	{ key = "snipeMaxLevel", label = "Snipe max. required level", lo = 1, hi = 70,
		tip = "Highest required level for BoE snipes." },
	{ key = "snipeMinQuality", label = "Snipe min. quality (3-4)", lo = 2, hi = 4,
		tip = "3 = rare (blue) and epic, 4 = epic only. 2 adds green items." },
	{ key = "snipeMinSold", label = "Snipe min. region sold/day", lo = 0, hi = 100, decimal = true,
		tip = "Only snipe items that TSM says sell at least this many a day per auction house in your region." },
}
local BOOL_SETTINGS = {
	{ key = "alertChat", label = "Print alerts in chat" },
	{ key = "alertSound", label = "Play alert sounds" },
	{ key = "alertRaidWarning", label = "Big alerts: message on screen" },
	{ key = "alertFlash", label = "Big alerts: flash taskbar icon" },
	{ key = "tooltip", label = "Market Intel on item tooltips" },
	{ key = "useTSMFallback", label = "Use TSM price until enough history" },
	{ key = "snipeEnabled", label = "Look for BoE snipes" },
	{ key = "snipeRequireSaleRate", label = "Snipes need TSM sale rate" },
	{ key = "minimapHide", label = "Hide the minimap button" },
}

local function FormatSetting(def, v)
	if def.gold then return tostring(v / 10000) end
	if def.decimal then return format("%.2f", v) end
	return tostring(v)
end

local function SoundButton(page, key, prefix)
	local b
	b = Button(page, "", 200, function()
		local list, i = ns.Alerts.SOUNDS, 1
		for j, snd in ipairs(list) do if snd.id == ns.settings[key] then i = j end end
		local nextSound = list[i % #list + 1]
		ns.settings[key] = nextSound.id
		PlaySound(nextSound.kit, "Master")
		page:Update()
	end)
	b.update = function()
		for _, snd in ipairs(ns.Alerts.SOUNDS) do
			if snd.id == ns.settings[key] then b:SetText(prefix .. snd.label) end
		end
	end
	return b
end

local function BuildSettings(page)
	page.controls = {}
	for i, def in ipairs(BOOL_SETTINGS) do
		local col, row = (i - 1) % 3, floor((i - 1) / 3)
		local cb = CheckBox(page, def.label, function(v)
			ns.settings[def.key] = v
			if def.key == "minimapHide" then ns.Minimap.Refresh() end
		end)
		cb:SetPoint("TOPLEFT", -4 + col * 280, 4 - row * 25)
		cb.def = def
		page.controls[#page.controls + 1] = cb
	end
	page.sound1 = SoundButton(page, "alertSoundChoice", "Alert sound: ")
	page.sound1:SetPoint("TOPLEFT", 0, -76)
	page.sound2 = SoundButton(page, "strongSound", "Big alert sound: ")
	page.sound2:SetPoint("TOPLEFT", 280, -76)
	for i, def in ipairs(NUMBER_SETTINGS) do
		local col, row = (i - 1) % 3, floor((i - 1) / 3)
		local x, y = col * 280, -108 - row * 25
		local label = Text(page, "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", x, y - 4)
		label:SetWidth(190)
		label:SetText(def.label)
		local eb = EditBox(page, 60)
		eb:SetPoint("TOPLEFT", x + 196, y)
		eb.def = def
		eb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(def.label)
			GameTooltip:AddLine(def.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
	page.addons:SetPoint("BOTTOMLEFT", 0, 30)
	page.addons:SetWidth(840)

	Button(page, "Compact old data", 140, function()
		ns.History.Compact(time())
		ns.Print("old data compacted.")
		UI.Refresh()
	end):SetPoint("BOTTOMLEFT", 0, 0)
	Button(page, "Reset defaults", 120, function()
		for k, v in pairs(ns.DEFAULTS) do ns.settings[k] = v end
		ns.Minimap.Refresh()
		page:Update()
	end):SetPoint("BOTTOMLEFT", 150, 0)
	Button(page, "Import from Auctionator", 170, function()
		ns.Integrations.ImportAuctionator(true)
	end):SetPoint("BOTTOMLEFT", 280, 0)
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
		page.sound1.update()
		page.sound2.update()
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
local BUILDERS = {
	deals = BuildDeals, snipe = BuildSnipe, flips = BuildFlips, depth = BuildDepth, history = BuildHistory,
	crafting = BuildCrafting, ledger = BuildLedger, watch = BuildWatch, settings = BuildSettings,
}

local function UpdateStatus()
	if not frame then return end
	local st = ns.Scanner.status
	local text
	if st.fullScan then
		text = format("Reading full scan... %d%%", floor((st.fullScanProgress or 0) * 100))
	elseif st.scanning then
		text = format("%s: search %d/%d%s", st.label or "Scanning", min(st.index, st.count), st.count,
			st.pages and format(", page %d/%d", st.page + 1, st.pages) or "")
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
	UI.PlaceWindow()
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.settings.windowPos = { point, relPoint, x, y }
	end)
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
		local b = Button(frame, TAB_TITLES[tab], 88, function() UI.Show(tab) end)
		b:SetPoint("TOPLEFT", 18 + (i - 1) * 92, -38)
		tabButtons[tab] = b
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 20, -70)
		page:SetPoint("BOTTOMRIGHT", -20, 34)
		page:Hide()
		BUILDERS[tab](page)
		pages[tab] = page
	end

	frame.status = Text(frame, "GameFontHighlightSmall")
	frame.status:SetPoint("BOTTOMLEFT", 20, 14)
	frame.status:SetWidth(WIDTH - 40)

	frame:SetScript("OnShow", function()
		ns.Alerts.ClearUnseen()
		UI.Refresh(true)
	end)
end

-- Saved position if the window was ever moved; otherwise beside the auction
-- house when it is open (so it does not cover it), else the screen centre.
function UI.PlaceWindow()
	if not frame then return end
	frame:ClearAllPoints()
	local pos = ns.settings.windowPos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	elseif AuctionFrame and AuctionFrame:IsShown() then
		-- right of the auction house, below its Market Intel button, clear of the minimap
		frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 10, -70)
	else
		frame:SetPoint("CENTER")
	end
end

function UI.Show(tab)
	if not frame then CreateMain()
	elseif not frame:IsShown() then UI.PlaceWindow() end
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
	if pages.snipe then pages.snipe:UpdateScanButton() end
	if currentTab == "watch" or currentTab == "snipe" then UI.Refresh() end
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
