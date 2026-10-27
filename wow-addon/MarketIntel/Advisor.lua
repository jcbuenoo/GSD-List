-- Market Intel: posting price advisor and flip finder.
-- Both only make suggestions. Nothing is ever posted or bought automatically.
local _, ns = ...

local AD = {}
ns.Advisor = AD

local floor, max, min = math.floor, math.max, math.min
local AH_CUT = 0.05

local function VendorPrice(key)
	return (select(11, GetItemInfo(ns.ItemStringFromKey(key) or 0))) or 0
end

-- Cheapest price levels from other sellers: the latest search this session,
-- or just the minimum from history.
local function Levels(key)
	local cur = ns.current[key]
	if cur and cur.levels then return cur.levels, cur.t end
	local latest = ns.History.GetLatest(key)
	if latest then return { { unit = latest.min, qty = 1, auc = 1 } }, latest.t end
	return nil
end

AD.ACTION_TEXT = {
	UNDERCUT = "|cffffffffUndercut|r", PREMIUM = "|cff40ff40Post high|r", HOLD = "|cffff9900Hold|r",
	VENDOR = "|cffff5050Vendor it|r",
}

-- Suggested posting price per item.
-- Returns { price, action, reason, ref, net } or nil when there is no data at all.
function AD.PostPrice(key)
	local s = ns.settings
	local levels = Levels(key)
	local ref = ns.History.GetReference(key)
	if not levels and not ref then return nil end
	local item = ns.History.GetItem(key)
	local depth = ns.Analysis.GetDepth(key)
	local stats = item and ns.Ledger.ItemStats(item.n)
	local floorPrice = ref and ref * s.postFloorPct / 100
	local vendor = VendorPrice(key)
	local cheapest = levels and levels[1] and levels[1].unit
	local advice

	if not cheapest then
		advice = { price = floor(ref * (1 + s.postPremiumPct / 100)), action = "PREMIUM",
			reason = "Nobody else is selling it. Post above the normal price." }
	elseif floorPrice and cheapest - s.postUndercut < floorPrice then
		-- The market is below what this item is normally worth. If only a little
		-- cheap stock sits there (by units, not auctions), price against the first
		-- level at a fair price; it will likely be bought out.
		local cheapQty, cheapAuc, totalQty, fair = 0, 0, 0, nil
		for _, lvl in ipairs(levels) do
			totalQty = totalQty + lvl.qty
			if lvl.unit - s.postUndercut < floorPrice then
				cheapQty, cheapAuc = cheapQty + lvl.qty, cheapAuc + lvl.auc
			elseif not fair then
				fair = lvl
			end
		end
		if fair and cheapQty <= max(3, totalQty * 0.15) then
			advice = { price = fair.unit - s.postUndercut, action = "UNDERCUT",
				reason = string.format("Only %d cheap unit%s (%d auction%s) below normal; undercut the next fair price instead.",
					cheapQty, cheapQty == 1 and "" or "s", cheapAuc, cheapAuc == 1 and "" or "s") }
		else
			advice = { price = floor(ref), action = "HOLD",
				reason = string.format("The lowest price is %d%% below normal. Hold, or post at the normal price and wait.",
					floor((1 - cheapest / ref) * 100 + 0.5)) }
		end
	elseif depth and depth.rating == "FLOODED" and not (stats and stats.sellThrough >= 0.6) then
		advice = { price = cheapest - s.postUndercut, action = "HOLD",
			reason = "Flooded market. Hold your stock, or undercut only what you need to sell now." }
	elseif depth and depth.rating == "THIN" and ref and cheapest > ref then
		advice = { price = cheapest - s.postUndercut, action = "PREMIUM",
			reason = "Little competition and the price is above normal. Undercut slightly and enjoy the margin." }
	elseif depth and depth.rating == "THIN" and ref then
		advice = { price = max(cheapest - s.postUndercut, floor(ref)), action = "PREMIUM",
			reason = "Little competition. Post at the normal price or just under the cheapest." }
	else
		advice = { price = cheapest - s.postUndercut, action = "UNDERCUT", reason = "Undercut the cheapest auction." }
	end

	advice.price = max(1, floor(advice.price))
	if vendor > 0 and advice.price * (1 - AH_CUT) <= vendor then
		advice.action = "VENDOR"
		advice.reason = "The auction price after the 5% cut is no better than selling to a vendor."
		advice.price = vendor
	end
	advice.ref = ref
	advice.net = floor(advice.price * (1 - AH_CUT))
	if stats then
		advice.reason = advice.reason .. string.format(" You sold %d of your last %d auctions.", stats.sold, stats.sold + stats.expired)
	end
	return advice
end

---------------------------------------------------------------------------
-- Flip finder
---------------------------------------------------------------------------
-- 24-hour deposit in TBC: 15% of the vendor price per 12 hours.
local function Deposit(key, qty)
	return VendorPrice(key) * 0.3 * qty
end

-- Best way to buy the cheapest auctions of one item and relist them.
-- Returns nil when no flip clears the minimum profit and return.
function AD.EvaluateFlip(key, now)
	local s = ns.settings
	local cur = ns.current[key]
	if not cur or not cur.levels or #cur.levels == 0 or now - cur.t > s.flipMaxAge * 60 then return nil end
	local ref = ns.History.GetReference(key, now)
	if not ref then return nil end
	local depth = ns.Analysis.GetDepth(key, now)
	if depth and depth.rating == "FLOODED" then return nil end

	-- don't suggest buying more than the market normally holds (or a week of TSM sales)
	local sold = ns.Integrations.GetTSMPrice(key, "dbregionsoldperday")
	local normal = ns.History.GetNormalSupply(key, now)
	local cap = normal or math.huge
	if sold then cap = min(cap, max(1, sold * 7)) end

	local levels = cur.levels
	local best
	local qty, cost = 0, 0
	for k = 1, #levels do
		local lvl = levels[k]
		local nextPrice = levels[k + 1] and levels[k + 1].unit - s.postUndercut
		local resale = min(ref, nextPrice or ref)
		if lvl.unit >= resale * 0.9 then break end
		qty, cost = qty + lvl.qty, cost + lvl.unit * lvl.qty
		if qty > cap then break end
		local profit = resale * qty * (1 - AH_CUT) - cost - Deposit(key, qty)
		local roi = profit / cost
		if profit >= s.flipMinProfit and roi * 100 >= s.flipMinROI and (not best or profit > best.profit) then
			best = { key = key, qty = qty, auctions = 0, maxUnit = lvl.unit, cost = cost, resale = floor(resale),
				profit = floor(profit), roi = roi, levels = k }
		end
	end
	if not best then return nil end
	for k = 1, best.levels do best.auctions = best.auctions + levels[k].auc end
	local stats = ns.Ledger.ItemStats(ns.History.GetName(key))
	local evidence = (sold and sold >= 1) or (stats and stats.sellThrough >= 0.6)
	if depth and depth.rating == "CROWDED" then
		best.risk = "High"
	elseif evidence then
		best.risk = "Low"
	else
		best.risk = "Medium"
	end
	best.sold, best.rating = sold, depth and depth.rating
	return best
end

-- All flips from this session's searches, most profitable first.
function AD.FindFlips(now)
	now = now or time()
	local out = {}
	for key in pairs(ns.current) do
		local f = AD.EvaluateFlip(key, now)
		if f then
			f.name = ns.History.GetName(key) or tostring(key)
			out[#out + 1] = f
		end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end
