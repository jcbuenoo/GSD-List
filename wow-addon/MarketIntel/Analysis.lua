-- Market Intel: snapshot statistics, deal detection, market depth ratings and the watchlist.
local _, ns = ...

local A = {}
ns.Analysis = A

local floor, max, min, pairs, ipairs, format = math.floor, math.max, math.min, pairs, ipairs, string.format

---------------------------------------------------------------------------
-- Snapshot statistics from a list of listings for one item
-- listing = { unit, count, buyout, owner }
---------------------------------------------------------------------------
-- Market value: quantity-weighted average of the cheapest 25% of units on
-- sale, ignoring listings priced far above the cheapest one (TSM style).
function A.MarketValue(sorted, totalQty)
	if #sorted == 0 then return nil end
	local want = max(1, totalQty * 0.25)
	local cheapest = sorted[1].unit
	local sum, qty = 0, 0
	for _, l in ipairs(sorted) do
		if qty >= want then break end
		if qty > 0 and l.unit > cheapest * 1.5 then break end
		local take = min(l.count, want - qty)
		sum = sum + l.unit * take
		qty = qty + take
	end
	return floor(sum / qty + 0.5)
end

-- Turn the listings of one item into a snapshot record.
function A.BuildSnapshot(listings, full, now)
	table.sort(listings, function(a, b) return a.unit < b.unit end)
	local qty, sellers, nSellers = 0, {}, 0
	for _, l in ipairs(listings) do
		qty = qty + l.count
		local owner = l.owner or "?"
		if not sellers[owner] then
			sellers[owner] = true
			nSellers = nSellers + 1
		end
	end
	local minUnit = listings[1].unit
	local wall = 0
	for _, l in ipairs(listings) do
		if l.unit <= minUnit * 1.05 then wall = wall + l.count else break end
	end
	return {
		t = now, min = floor(minUnit + 0.5), mkt = A.MarketValue(listings, qty), qty = qty,
		auc = #listings, sel = nSellers, wall = wall, full = full and true or false,
	}
end

-- Cheapest price levels, for the tooltip and History tab: { {unit, qty, auctions}, ... }
function A.BuildLadder(sorted, levels)
	local ladder = {}
	for _, l in ipairs(sorted) do
		local unit = floor(l.unit + 0.5)
		local top = ladder[#ladder]
		if top and top.unit == unit then
			top.qty = top.qty + l.count
			top.auc = top.auc + 1
		else
			if #ladder >= (levels or 5) then break end
			ladder[#ladder + 1] = { unit = unit, qty = l.count, auc = 1 }
		end
	end
	return ladder
end

---------------------------------------------------------------------------
-- Deals
---------------------------------------------------------------------------
ns.deals = {}       -- newest first, this session only
local dealIndex = {}
local MAX_DEALS = 200

local function DealId(key, l)
	return format("%s|%d|%d|%s", key, l.buyout, l.count, l.owner or "?")
end

-- Find listings worth buying. ref = normal unit price (may be nil), watchMax = watch limit (may be nil).
function A.FindDeals(key, listings, ref, watchMax)
	local out = {}
	local pct = ns.settings.dealPct / 100
	for _, l in ipairs(listings) do
		if not l.mine and l.buyout > 0 then
			local reason
			if watchMax and l.unit <= watchMax then
				reason = "watch"
			elseif ref and l.unit <= ref * pct and (ref - l.unit) * l.count >= ns.settings.minDealProfit then
				reason = "deal"
			end
			if reason then
				out[#out + 1] = {
					key = key, unit = l.unit, count = l.count, buyout = l.buyout, owner = l.owner,
					ref = ref, pct = ref and l.unit / ref or nil, reason = reason,
					profit = ref and (ref - l.unit) * l.count or nil, watchMax = watchMax,
				}
			end
		end
	end
	return out
end

-- Record a deal; returns true if it is new.
function A.AddDeal(deal, name, now)
	local id = DealId(deal.key, deal)
	if dealIndex[id] then
		dealIndex[id].t = now -- "last seen"
		return false
	end
	deal.id, deal.name, deal.t, deal.found = id, name, now, now
	table.insert(ns.deals, 1, deal)
	dealIndex[id] = deal
	while #ns.deals > MAX_DEALS do
		local old = table.remove(ns.deals)
		dealIndex[old.id] = nil
	end
	return true
end

-- After a complete scan of an item, drop deals that are no longer listed.
function A.PruneDeals(key, listings)
	local live = {}
	for _, l in ipairs(listings) do live[DealId(key, l)] = true end
	for i = #ns.deals, 1, -1 do
		local d = ns.deals[i]
		if d.key == key and not live[d.id] then
			table.remove(ns.deals, i)
			dealIndex[d.id] = nil
		end
	end
end

function A.ClearDeals()
	wipe(ns.deals)
	wipe(dealIndex)
end

local lastSound = 0
function A.Alert(deals)
	if #deals == 0 then return end
	local s = ns.settings
	if s.alertChat then
		local shown = 0
		for _, d in ipairs(deals) do
			if shown >= 5 then
				ns.Print("...and %d more deals. Type /mi deals to see them all.", #deals - shown)
				break
			end
			shown = shown + 1
			local link = ns.GetItemLinkForKey(d.key, d.name)
			if d.reason == "watch" then
				ns.Print("|cff00ff00WATCH|r %s x%d at %s each (your max %s)", link, d.count,
					ns.FormatMoney(d.unit), ns.FormatMoney(d.watchMax))
			else
				ns.Print("|cff00ff00DEAL|r %s x%d at %s each, %s of normal %s (save %s)", link, d.count,
					ns.FormatMoney(d.unit), ns.FormatPct(d.pct), ns.FormatMoney(d.ref), ns.FormatMoney(d.profit))
			end
		end
	end
	if s.alertSound and GetTime() - lastSound > 3 then
		lastSound = GetTime()
		PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
	end
end

---------------------------------------------------------------------------
-- Market depth
---------------------------------------------------------------------------
A.RATING_COLORS = {
	FLOODED = "|cffff3030", CROWDED = "|cffff9900", NORMAL = "|cffffffff", THIN = "|cff40ff40", UNKNOWN = "|cff909090",
}
A.RATING_TEXT = { FLOODED = "Flooded", CROWDED = "Crowded", NORMAL = "Normal", THIN = "Thin", UNKNOWN = "Unknown" }
A.RATING_ORDER = { FLOODED = 1, CROWDED = 2, THIN = 3, NORMAL = 4, UNKNOWN = 5 }

-- Price war: the minimum price fell 15%+ across 3+ snapshots in 24h with several sellers.
function A.IsPriceWar(key, now)
	local raw = ns.History.GetRaw(ns.History.GetItem(key))
	now = now or time()
	local recent = {}
	for _, s in ipairs(raw) do
		if now - s.t <= 86400 then recent[#recent + 1] = s end
	end
	if #recent < 3 then return false end
	for i = 2, #recent do
		if recent[i].min > recent[i - 1].min then return false end
	end
	local first, last = recent[1], recent[#recent]
	return last.min <= first.min * 0.85 and last.sel >= 4
end

-- Depth report for an item based on its latest snapshot.
function A.GetDepth(key, now)
	local latest = ns.History.GetLatest(key)
	if not latest then return nil end
	now = now or time()
	local s = ns.settings
	local normal = ns.History.GetNormalSupply(key, now)
	local d = {
		latest = latest, normal = normal, age = now - latest.t,
		ratio = (normal and normal > 0 and latest.full) and latest.qty / normal or nil,
		war = A.IsPriceWar(key, now),
	}
	local rating
	if latest.sel >= s.floodSellers or (d.ratio and d.ratio >= s.floodRatio) then
		rating = "FLOODED"
	elseif latest.sel >= s.crowdSellers or (d.ratio and d.ratio >= s.crowdRatio) then
		rating = "CROWDED"
	elseif not latest.full then
		rating = "UNKNOWN"
	elseif (d.ratio and d.ratio <= s.thinRatio) or latest.auc <= 2 then
		rating = "THIN"
	elseif d.ratio then
		rating = "NORMAL"
	else
		-- no supply history yet: judge on seller count alone
		rating = latest.sel <= 3 and "THIN" or "NORMAL"
	end
	d.rating = rating

	local advice
	if rating == "FLOODED" then
		advice = "Heavy competition. Hold stock or post only what sells fast."
	elseif rating == "CROWDED" then
		advice = "Busy market. Expect undercuts; post small batches."
	elseif rating == "THIN" then
		advice = "Little competition. Good time to post, and you can price higher."
	elseif rating == "UNKNOWN" then
		advice = "Partial scan only. Search the item fully for a reliable rating."
	else
		advice = "Normal supply."
	end
	if d.war then advice = advice .. " Price war: the minimum keeps dropping." end
	if latest.wall and latest.qty > 0 and latest.wall >= latest.qty * 0.5 and latest.auc >= 5 then
		advice = advice .. format(" Wall: %d of %d units within 5%% of the minimum.", latest.wall, latest.qty)
	end
	d.advice = advice
	return d
end

function A.FormatRating(rating)
	return (A.RATING_COLORS[rating] or "") .. (A.RATING_TEXT[rating] or rating) .. "|r"
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink

-- Item keys currently in the player's bags (backpack + 4 bags), with counts.
function A.GetBagKeys()
	local keys = {}
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local key = ns.ItemKeyFromLink(GetContainerItemLink(bag, slot))
			if key then keys[key] = true end
		end
	end
	return keys
end

function A.PrintBagReport()
	local rows = {}
	for key in pairs(A.GetBagKeys()) do
		local d = A.GetDepth(key)
		if d then rows[#rows + 1] = { key = key, d = d } end
	end
	if #rows == 0 then
		return ns.Print("no market data for anything in your bags yet. Scan the auction house first.")
	end
	table.sort(rows, function(a, b)
		return A.RATING_ORDER[a.d.rating] < A.RATING_ORDER[b.d.rating]
	end)
	ns.Print("market depth for items in your bags:")
	for _, r in ipairs(rows) do
		local item = ns.History.GetItem(r.key)
		local l = r.d.latest
		ns.Print("%s %s - min %s, %d auctions, %d sellers%s (%s ago)",
			A.FormatRating(r.d.rating), ns.GetItemLinkForKey(r.key, item.n, item.q),
			ns.FormatMoney(l.min), l.auc, l.sel,
			r.d.ratio and format(", supply %.1fx normal", r.d.ratio) or "",
			ns.FormatAge(r.d.age))
	end
end

---------------------------------------------------------------------------
-- Watchlist (account wide, matched by item name)
---------------------------------------------------------------------------
local W = {}
ns.Watch = W

function W.Add(name, maxPrice)
	name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
	if not name or name == "" then return false end
	local lower = name:lower()
	ns.db.watch[lower] = { name = name, max = maxPrice }
	ns.Print("watching %s%s.", name, maxPrice and (" (alert at or below " .. ns.FormatMoney(maxPrice) .. ")") or "")
	ns.Fire("MI_DATA_UPDATED")
	return true
end

function W.Remove(name)
	if not name then return false end
	local lower = name:lower()
	if not ns.db.watch[lower] then return false end
	ns.db.watch[lower] = nil
	ns.Fire("MI_DATA_UPDATED")
	return true
end

function W.Get(name)
	return name and ns.db.watch[name:lower()]
end

-- Sorted list of watch entries with their current market numbers.
function W.List()
	local out = {}
	for lower, w in pairs(ns.db.watch) do
		local key = ns.History.FindKeyByName(w.name)
		local latest = key and ns.History.GetLatest(key)
		out[#out + 1] = {
			lower = lower, name = w.name, max = w.max, key = key, latest = latest,
			buy = latest and w.max and latest.min <= w.max or false,
		}
	end
	table.sort(out, function(a, b)
		if a.buy ~= b.buy then return a.buy end
		return a.lower < b.lower
	end)
	return out
end
