-- Market Intel: sales ledger. Reads auction house mail (sold, bought, expired,
-- cancelled) when you open your mailbox and keeps a record per auction house,
-- so you can see real profit and how well each item actually sells.
local _, ns = ...

local L = {}
ns.Ledger = L

local KEEP_DAYS = 180
local MAIL_DAYS = 30 -- auction mail lasts 30 days; used to work out when it was sent

-- "Auction expired: %s" -> "^Auction expired: (.+)$"
local function SubjectPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
	return "^" .. p .. "$"
end

local SUBJECTS -- built lazily: global strings are localised by the client
local function Subjects()
	if not SUBJECTS then
		SUBJECTS = {
			sold = SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"),
			bought = SubjectPattern(AUCTION_WON_MAIL_SUBJECT or "Auction won: %s"),
			expired = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"),
			cancelled = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s"),
		}
	end
	return SUBJECTS
end

local function Store()
	local realm = ns.realm
	realm.ledger = realm.ledger or {}
	realm.ledgerSeen = realm.ledgerSeen or {}
	return realm.ledger, realm.ledgerSeen
end

---------------------------------------------------------------------------
-- Your own auctions (to know how many were in a sold auction)
---------------------------------------------------------------------------
local owned = {} -- name -> list of { count, buyout }

ns.On("AUCTION_OWNED_LIST_UPDATE", function()
	wipe(owned)
	for i = 1, (GetNumAuctionItems("owner") or 0) do
		local name, _, count, _, _, _, _, minBid, _, buyout = GetAuctionItemInfo("owner", i)
		if name then
			owned[name] = owned[name] or {}
			table.insert(owned[name], { count = count, buyout = buyout, minBid = minBid })
		end
	end
	-- keep the last known list across sessions (sales are often collected later)
	ns.realm.owned = {}
	for name, list in pairs(owned) do ns.realm.owned[name] = list end
end)

local function GuessCount(name, price)
	local list = owned[name] or (ns.realm.owned and ns.realm.owned[name])
	for _, a in ipairs(list or {}) do
		if a.buyout == price or a.minBid == price then return a.count end
	end
	return nil
end

---------------------------------------------------------------------------
-- Reading the mailbox
---------------------------------------------------------------------------
-- Returns name, count of the first attachment (current client signature, older as fallback).
local function Attachment(i)
	local a, b, c, d = GetInboxItem(i, 1)
	if not a then return nil end
	if type(b) == "number" and type(d) == "number" then return a, d end -- name, itemID, texture, count
	return a, tonumber(c) or 1                                          -- name, texture, count
end

function L.Record(entry)
	local ledger = Store()
	ledger[#ledger + 1] = entry
	entry.key = entry.key or ns.History.FindKeyByName(entry.name)
end

-- A mail is identified by what it says plus when it was sent (to 5 minutes;
-- neighbouring slots are checked too), so the same mail is never counted
-- twice however often the mailbox is opened.
local SLOT = 300
local function MailId(kind, name, who, money, sentAt)
	return string.format("%s|%s|%s|%d|%d", kind, name or "?", who or "?", money or 0, math.floor(sentAt / SLOT))
end

-- Identical mails (one buyer buying several identical stacks, a batch of
-- auctions expiring together) are counted: seen[id] holds how many of that
-- exact mail were recorded, and only extra copies are added.
function L.ScanInbox()
	if not ns.realm then return 0 end
	local _, seen = Store()
	local subjects = Subjects()
	local now = time()
	local added = 0
	local found = {} -- id -> { entries, near = neighbouring ids }
	local order = {}
	for i = 1, (GetInboxNumItems() or 0) do
		local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
		if subject and daysLeft then
			local kind, itemName
			for k, pattern in pairs(subjects) do
				local m = pattern and subject:match(pattern)
				if m then kind, itemName = k, m break end
			end
			if kind then
				local invoiceType, invName, player, bid, deposit, consignment, invCount
				if GetInboxInvoiceInfo then
					local buyout, moneyDelay, etsDelay -- luacheck: ignore
					invoiceType, invName, player, bid, buyout, deposit, consignment, moneyDelay, etsDelay, invCount = GetInboxInvoiceInfo(i)
				end
				itemName = invName or itemName
				local sentAt = now - (MAIL_DAYS - daysLeft) * 86400
				local amount = bid or money or 0
				local id = MailId(kind, itemName, player or sender, amount, sentAt)
				local group = found[id]
				if not group then
					group = { entries = {}, near = {
						MailId(kind, itemName, player or sender, amount, sentAt - SLOT),
						MailId(kind, itemName, player or sender, amount, sentAt + SLOT) } }
					found[id] = group
					order[#order + 1] = id
				end
				do
					local entry = { t = math.floor(sentAt), type = kind, name = itemName, who = player }
					if kind == "sold" and (invoiceType == "seller" or not invoiceType) then
						entry.gross = bid or money
						entry.cut = consignment or 0
						entry.deposit = deposit or 0
						entry.net = (bid or money or 0) - (consignment or 0)
						entry.qty = tonumber(invCount) or GuessCount(itemName, bid)
					elseif kind == "bought" then
						entry.gross = bid
						local _, count = Attachment(i)
						entry.qty = count
					else -- expired / cancelled: the item comes back
						local _, count = Attachment(i)
						entry.qty = count
					end
					table.insert(group.entries, entry)
				end
			end
		end
	end
	for _, id in ipairs(order) do
		local group = found[id]
		local function count(v) return type(v) == "table" and v.n or (v and 1 or 0) end
		local already = math.max(count(seen[id]), count(seen[group.near[1]]), count(seen[group.near[2]]))
		for i = already + 1, #group.entries do
			L.Record(group.entries[i])
			added = added + 1
		end
		if #group.entries > already then seen[id] = { n = #group.entries, t = now } end
	end
	if added > 0 then
		L.Prune(now)
		ns.Fire("MI_DATA_UPDATED")
	end
	return added
end

function L.Prune(now)
	local ledger, seen = Store()
	local cutoff = now - KEEP_DAYS * 86400
	local keep = {}
	for _, e in ipairs(ledger) do
		if e.t >= cutoff then keep[#keep + 1] = e end
	end
	ns.realm.ledger = keep
	for id, v in pairs(seen) do
		local t = type(v) == "table" and v.t or v
		if t < now - (MAIL_DAYS + 2) * 86400 then seen[id] = nil end
	end
end

-- The inbox fires many updates while it loads; read it once things settle.
local pending
ns.On("MAIL_INBOX_UPDATE", function()
	ns.Cancel(pending)
	pending = ns.After(0.5, function()
		pending = nil
		L.ScanInbox()
	end)
end)

---------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------
-- Entries newest first, optionally only the last `days` days.
function L.Entries(days)
	local ledger = Store()
	local cutoff = days and (time() - days * 86400) or 0
	local out = {}
	for _, e in ipairs(ledger) do
		if e.t >= cutoff then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

-- Totals for the last `days` days (nil = everything).
function L.Summary(days)
	local s = { sales = 0, cut = 0, net = 0, spent = 0, sold = 0, bought = 0, expired = 0, cancelled = 0 }
	for _, e in ipairs(L.Entries(days)) do
		if e.type == "sold" then
			s.sales, s.cut, s.net, s.sold = s.sales + (e.gross or 0), s.cut + (e.cut or 0), s.net + (e.net or 0), s.sold + 1
		elseif e.type == "bought" then
			s.spent, s.bought = s.spent + (e.gross or 0), s.bought + 1
		elseif e.type == "expired" then
			s.expired = s.expired + 1
		elseif e.type == "cancelled" then
			s.cancelled = s.cancelled + 1
		end
	end
	s.profit = s.net - s.spent
	s.sellThrough = (s.sold + s.expired) > 0 and s.sold / (s.sold + s.expired) or nil
	return s
end

-- How one item sells for you: auctions sold/expired, sell-through and average price per item.
function L.ItemStats(name, days)
	if not name then return nil end
	local st = { sold = 0, expired = 0, units = 0, revenue = 0 }
	for _, e in ipairs(L.Entries(days or 30)) do
		if e.name == name then
			if e.type == "sold" then
				st.sold = st.sold + 1
				if e.qty then
					st.units = st.units + e.qty
					st.revenue = st.revenue + (e.gross or 0)
				end
			elseif e.type == "expired" then
				st.expired = st.expired + 1
			end
		end
	end
	if st.sold + st.expired == 0 then return nil end
	st.sellThrough = st.sold / (st.sold + st.expired)
	st.avgUnit = st.units > 0 and st.revenue / st.units or nil
	return st
end
