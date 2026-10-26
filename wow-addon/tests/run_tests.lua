-- Run with: lua5.1 tests/run_tests.lua   (from the wow-addon folder)
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local ADDON_DIR = "MarketIntel"
local DAY = 86400

local passed, failed = 0, {}
local function test(name, fn)
	M.reset()
	local ok, err = xpcall(fn, debug.traceback)
	if ok and #M.errors > 0 then
		ok, err = false, "addon error handler received: " .. tostring(M.errors[1])
	end
	if ok then
		passed = passed + 1
		print("  ok   " .. name)
	else
		table.insert(failed, name)
		print("  FAIL " .. name .. "\n" .. tostring(err))
	end
end

local function eq(a, b, msg)
	if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, tol, msg)
	if not a or math.abs(a - b) > (tol or 1) then error((msg or "not close") .. ": expected ~" .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function chatHas(pattern)
	for _, line in ipairs(M.chat) do if line:find(pattern) then return line end end
	return nil
end

-- Add n auctions of an item. price = per unit copper.
local function addAuctions(name, id, n, price, opts)
	opts = opts or {}
	for i = 1, n do
		local count = opts.count or 1
		local unit = price + (opts.step or 0) * (i - 1)
		table.insert(M.auctions, {
			name = name, id = id, count = count, buyout = unit * count, quality = opts.quality or 1,
			owner = opts.owner or ("Seller" .. ((i - 1) % (opts.sellers or 3) + 1)), suffix = opts.suffix,
		})
	end
end

local function load(sv)
	return M.LoadAddon(ADDON_DIR, sv)
end

local function search(name, page)
	QueryAuctionItems(name, nil, nil, page or 0, false, nil, false, false)
	M.Tick(0.1)
end

-- Record one day of history for an item: a full search at the current time.
local function recordDays(ns, name, id, days, price, auctions)
	for d = days, 1, -1 do
		M.now = M.now - d * DAY
		M.auctions = {}
		addAuctions(name, id, auctions or 10, price)
		search(name)
		M.Tick(3)
		M.now = M.now + d * DAY
	end
	M.auctions = {}
end

print("Market Intel tests")

---------------------------------------------------------------------------
test("loads cleanly and creates saved variables", function()
	local ns = load(nil)
	assert(MarketIntelDB and MarketIntelDB.settings and MarketIntelDB.realms, "db missing")
	eq(ns.realmKey, "Dreamscythe-Alliance")
	eq(ns.settings.dealPct, 60)
	assert(SlashCmdList.MARKETINTEL, "slash command missing")
end)

test("money formatting and parsing", function()
	local ns = load(nil)
	eq(ns.FormatMoney(123456), "12|cffffd700g|r 34|cffc7c7cfs|r")
	eq(ns.FormatMoney(4510), "45|cffc7c7cfs|r 10|cffeda55fc|r")
	eq(ns.FormatMoney(8), "8|cffeda55fc|r")
	eq(ns.FormatMoney(12345678), "1,234|cffffd700g|r 56|cffc7c7cfs|r")
	eq(ns.FormatMoney(nil), "|cff808080--|r")
	eq(ns.ParseMoney("12"), 120000)
	eq(ns.ParseMoney("1.5"), 15000)
	eq(ns.ParseMoney("12g"), 120000)
	eq(ns.ParseMoney("12g 50s"), 125000)
	eq(ns.ParseMoney("12G50S3C"), 125003)
	eq(ns.ParseMoney("75s"), 7500)
	eq(ns.ParseMoney("abc"), nil)
	eq(ns.ParseMoney("12gx"), nil)
	eq(ns.ParseMoney(""), nil)
end)

test("item keys from links, including random suffix items", function()
	local ns = load(nil)
	eq(ns.ItemKeyFromLink(M.Link(23446, "Adamantite Bar")), "23446")
	eq(ns.ItemKeyFromLink(M.Link(24689, "Felsteel Longblade of the Bear", 1201)), "24689:1201")
	eq(ns.ItemKeyFromLink(M.Link(24689, "x", -45)), "24689:-45")
	eq(ns.ItemKeyFromLink("not a link"), nil)
	eq(ns.ItemIDFromKey("24689:1201"), 24689)
	eq(ns.ItemStringFromKey("24689:1201"), "item:24689:0:0:0:0:0:1201")
	eq(ns.ItemStringFromKey("23446"), "item:23446")
	eq(ns.ItemKeyFromLink(ns.ItemStringFromKey("24689:1201")), "24689:1201")
end)

test("slash argument parsing (names with spaces, prices, links)", function()
	local ns = load(nil)
	local n, p = ns.ParseItemAndPrice("Primal Might 95g")
	eq(n, "Primal Might"); eq(p, 950000)
	n, p = ns.ParseItemAndPrice("Flask of Relentless Assault")
	eq(n, "Flask of Relentless Assault"); eq(p, nil)
	n, p = ns.ParseItemAndPrice(M.Link(22854, "Flask of Relentless Assault") .. " 30g 50s")
	-- "30g 50s" has a space, only the last token is treated as the price
	eq(n, "Flask of Relentless Assault")
	n, p = ns.ParseItemAndPrice(M.Link(22854, "Flask of Relentless Assault") .. " 30g")
	eq(n, "Flask of Relentless Assault"); eq(p, 300000)
end)

---------------------------------------------------------------------------
test("passive capture merges pages into one complete snapshot", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Adamantite Ore", 23425, 70, 10000, { count = 20, step = 100, sellers = 7 })
	search("Adamantite Ore", 0)
	search("Adamantite Ore", 1)
	M.Tick(3)
	local s = ns.History.GetLatest("23425")
	assert(s, "no snapshot")
	eq(s.auc, 70, "auctions"); eq(s.qty, 1400, "quantity"); eq(s.sel, 7, "sellers")
	eq(s.min, 10000, "min"); eq(s.full, true, "full")
	-- cheapest 25% of 1400 units = 350 units: 17 auctions of 20 + 10 units of the 18th = 3,789,000c / 350
	near(s.mkt, 10826, 1, "market value")
	eq(#ns.realm.items["23425"].s, 1, "one snapshot")
end)

test("an old search is not re-saved with a new timestamp when the next search starts", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Fel Iron Bar", 23445, 5, 30000)
	addAuctions("Arcane Dust", 22445, 5, 20000)
	search("Fel Iron Bar"); M.Tick(3)
	local seenAt = ns.History.GetLatest("23445").t
	M.now = M.now + 1800
	search("Arcane Dust"); M.Tick(3)
	eq(#ns.realm.items["23445"].s, 1, "stale results saved again")
	eq(ns.History.GetLatest("23445").t, seenAt, "timestamp moved")
end)

test("repeating a search later does not merge in pages from the old search", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Fire", 21884, 60, 150000)
	search("Primal Fire", 0); search("Primal Fire", 1); M.Tick(3)
	M.now = M.now + 3600
	M.auctions = {}
	addAuctions("Primal Fire", 21884, 60, 90000)
	search("Primal Fire", 0); M.Tick(3) -- only the first page this time
	local s = ns.History.GetLatest("21884")
	eq(s.auc, 50, "old page 2 merged in"); eq(s.full, false)
	eq(s.min, 90000)
end)

test("only the first page seen -> snapshot marked partial", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Adamantite Ore", 23425, 70, 10000)
	search("Adamantite Ore", 0)
	M.Tick(3)
	local s = ns.History.GetLatest("23425")
	eq(s.full, false); eq(s.auc, 50)
	eq(ns.Analysis.GetDepth("23425").rating, "UNKNOWN")
end)

test("works without the QueryAuctionItems hook (results arrive with no known query)", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Fel Iron Bar", 23445, 12, 30000)
	M.list, M.listTotal = M.auctions, #M.auctions
	M.FireEvent("AUCTION_ITEM_LIST_UPDATE")
	M.Tick(3)
	local s = ns.History.GetLatest("23445")
	assert(s and s.full and s.auc == 12, "snapshot from un-hooked results")
end)

test("bid-only and grey items are skipped; random suffix items kept separate", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Felsteel Longblade of the Bear", 24689, 3, 500000, { suffix = 1201, quality = 2 })
	addAuctions("Felsteel Longblade of the Tiger", 24689, 2, 900000, { suffix = 1202, quality = 2 })
	addAuctions("Broken Fang", 1000, 5, 100, { quality = 0 })
	table.insert(M.auctions, { name = "Bid Only Thing", id = 2000, count = 1, buyout = 0, owner = "X" })
	search("")
	M.Tick(3)
	eq(ns.History.GetLatest("24689:1201").min, 500000)
	eq(ns.History.GetLatest("24689:1202").min, 900000)
	eq(ns.History.GetLatest("1000"), nil, "grey item stored")
	eq(ns.History.GetLatest("2000"), nil, "bid-only stored")
end)

test("repeat searches within 10 minutes replace the snapshot; partial never shrinks a full one", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Fire", 21884, 60, 150000)
	search("Primal Fire", 0); search("Primal Fire", 1); M.Tick(3)
	eq(ns.History.GetLatest("21884").qty, 60)
	M.now = M.now + 120
	search("Primal Fire", 0); M.Tick(3) -- only page 1 this time
	local item = ns.realm.items["21884"]
	eq(#item.s, 1, "replaced, not appended")
	eq(ns.History.GetLatest("21884").qty, 60, "partial must not shrink the full quantity")
	M.now = M.now + 3600
	search("Primal Fire", 0); M.Tick(3)
	eq(#item.s, 2, "new snapshot after the replace window")
end)

---------------------------------------------------------------------------
test("normal price = median of past days, excluding today", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	local ref, src = ns.History.GetReference("23571")
	eq(src, "history"); eq(ref, 800000)
	-- a crash today does not move the reference
	addAuctions("Primal Might", 23571, 10, 200000)
	search("Primal Might"); M.Tick(3)
	eq(ns.History.GetReference("23571"), 800000)
end)

test("too little history -> TSM fallback, else no reference", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 2, 800000)
	eq(ns.History.GetReference("23571"), nil)
	TSM_API = { GetCustomPriceValue = function(src, item)
		assert(src == "dbmarket" and item == "i:23571")
		return 750000
	end }
	local ref, src = ns.History.GetReference("23571")
	eq(ref, 750000); eq(src, "TSM")
	ns.settings.useTSMFallback = false
	eq(ns.History.GetReference("23571"), nil)
end)

test("deal alert: cheap listing found, chat + sound, own auctions ignored", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	addAuctions("Primal Might", 23571, 10, 800000)
	addAuctions("Primal Might", 23571, 1, 400000, { owner = "Cheapo" })       -- 50% -> deal
	addAuctions("Primal Might", 23571, 1, 300000, { owner = M.player })        -- mine -> ignored
	addAuctions("Primal Might", 23571, 1, 600000, { owner = "Meh" })          -- 75% -> not a deal
	search("Primal Might"); M.Tick(3)
	eq(#ns.deals, 1, "deal count")
	local d = ns.deals[1]
	eq(d.owner, "Cheapo"); eq(d.unit, 400000); near(d.pct, 0.5, 0.001); eq(d.profit, 400000)
	assert(chatHas("DEAL"), "no chat alert")
	eq(M.sounds, 1)
	-- the same listing seen again is not re-alerted
	local lines = #M.chat
	M.now = M.now + 60
	search("Primal Might"); M.Tick(3)
	eq(#ns.deals, 1); eq(#M.chat, lines, "duplicate alert")
	eq(ns.current["23571"].mine, 1, "own listing counted")
end)

test("deal minimum saving filters out cheap junk", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Netherweave Cloth", 21877, 5, 3000)
	addAuctions("Netherweave Cloth", 21877, 1, 1000, { count = 5, owner = "Cheap" }) -- saves 1s
	search("Netherweave Cloth"); M.Tick(3)
	eq(#ns.deals, 0, "tiny saving must not alert")
	ns.settings.minDealProfit = 0
	M.now = M.now + 700
	search("Netherweave Cloth"); M.Tick(3)
	eq(#ns.deals, 1)
end)

test("watchlist price alert works with no history at all", function()
	local ns = load(nil)
	M.OpenAH()
	SlashCmdList.MARKETINTEL("watch Khorium Ore 20g")
	assert(ns.Watch.Get("khorium ore"), "watch not added")
	addAuctions("Khorium Ore", 23426, 3, 250000)
	addAuctions("Khorium Ore", 23426, 1, 190000, { owner = "Lucky" })
	search("Khorium Ore"); M.Tick(3)
	eq(#ns.deals, 1); eq(ns.deals[1].reason, "watch")
	assert(chatHas("WATCH"), "no watch alert")
	local w = ns.Watch.List()[1]
	eq(w.buy, true, "watch list shows BUY")
end)

test("deals that sell are removed after the next complete search", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	addAuctions("Primal Might", 23571, 5, 800000)
	addAuctions("Primal Might", 23571, 1, 300000, { owner = "Cheapo" })
	search("Primal Might"); M.Tick(3)
	eq(#ns.deals, 1)
	table.remove(M.auctions) -- someone bought it
	M.now = M.now + 60
	search("Primal Might"); M.Tick(3)
	eq(#ns.deals, 0, "sold deal still listed")
end)

---------------------------------------------------------------------------
test("compaction folds old snapshots into daily summaries without changing the series", function()
	local ns = load(nil)
	M.OpenAH()
	for d = 10, 1, -1 do
		for h = 0, 2 do
			M.now = 1767268800 - d * DAY + h * 3600
			M.auctions = {}
			addAuctions("Fel Lotus", 22794, 4 + h, 300000 + d * 1000 + h * 500)
			search("Fel Lotus"); M.Tick(3)
		end
	end
	M.now = 1767268800
	local item = ns.realm.items["22794"]
	eq(#item.s, 30)
	local before = ns.History.GetDaily(item, M.now)
	ns.History.Compact(M.now)
	eq(#item.s, 9, "raw kept for 3 days") -- days -1,-2,-3 (cutoff day -3 kept)
	eq(#item.d, 7)
	local after = ns.History.GetDaily(item, M.now)
	eq(#after, #before)
	for i = 1, #before do
		eq(after[i].day, before[i].day)
		near(after[i].mkt, before[i].mkt, 0.01, "mkt day " .. i)
		eq(after[i].min, before[i].min)
		near(after[i].qty, before[i].qty, 0.01)
	end
	-- compacting twice changes nothing
	ns.History.Compact(M.now)
	eq(#item.d, 7)
	-- 100 days later everything is gone
	ns.History.Compact(M.now + 100 * DAY)
	eq(ns.realm.items["22794"], nil, "expired item not deleted")
end)

test("stats: averages, change vs 7d, volatility, weekday profile", function()
	local ns = load(nil)
	M.OpenAH()
	for d = 20, 1, -1 do
		M.now = 1767268800 - d * DAY
		M.auctions = {}
		local wd = tonumber(os.date("%w", M.now))
		addAuctions("Mongoose", 22559, 6, wd == 2 and 1200000 or 1000000) -- Tuesdays are expensive
		search("Mongoose"); M.Tick(3)
	end
	M.now = 1767268800
	local st = ns.History.GetStats("22559")
	assert(st.avg7 and st.avg30 and st.low30 and st.high30, "missing stats")
	assert(st.volatility and st.volatility > 0, "volatility")
	local profile, n = ns.History.GetWeekdayProfile("22559")
	eq(n, 20)
	assert(profile[3] > 1.1, "Tuesday should be the best day")
end)

---------------------------------------------------------------------------
test("depth ratings: flooded, crowded, thin, normal and price war", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Mercurial Adamantite", 23573, 5, 100000, 10)
	addAuctions("Mercurial Adamantite", 23573, 10, 100000, { sellers = 3 })
	search("Mercurial Adamantite"); M.Tick(3)
	eq(ns.Analysis.GetDepth("23573").rating, "NORMAL")
	M.now = M.now + 700
	M.auctions = {}
	addAuctions("Mercurial Adamantite", 23573, 25, 100000, { sellers = 3 })
	search("Mercurial Adamantite"); M.Tick(3)
	local d = ns.Analysis.GetDepth("23573")
	eq(d.rating, "FLOODED", "2.5x supply"); near(d.ratio, 2.5, 0.01)
	M.now = M.now + 700
	M.auctions = {}
	addAuctions("Mercurial Adamantite", 23573, 10, 100000, { sellers = 9 })
	search("Mercurial Adamantite"); M.Tick(3)
	eq(ns.Analysis.GetDepth("23573").rating, "CROWDED", "9 sellers")
	M.now = M.now + 700
	M.auctions = {}
	addAuctions("Mercurial Adamantite", 23573, 4, 100000, { sellers = 2 })
	search("Mercurial Adamantite"); M.Tick(3)
	eq(ns.Analysis.GetDepth("23573").rating, "THIN")

	-- price war: min keeps falling with many sellers
	for i = 0, 3 do
		M.now = M.now + 1800
		M.auctions = {}
		addAuctions("Bloodstone", 23436, 8, 50000 - i * 6000, { sellers = 5 })
		search("Bloodstone"); M.Tick(3)
	end
	assert(ns.Analysis.GetDepth("23436").war, "price war not detected")
	assert(ns.Analysis.GetDepth("23436").advice:find("Price war"), "advice")
end)

---------------------------------------------------------------------------
test("full scan (getAll): 20k auctions read over several frames, uncached rows retried", function()
	local ns = load(nil)
	M.OpenAH()
	for i = 1, 4000 do addAuctions("Item " .. i, 30000 + i, 5, 1000 + i, { sellers = 4 }) end
	for i = 1, 50 do M.auctions[i * 7].uncached = true end
	local t0 = os.clock()
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(0.06)
	assert(ns.Scanner.status.fullScan, "full scan should be in progress")
	M.Tick(0.5)
	for i = 1, 50 do M.auctions[i * 7].uncached = nil end -- item info arrives
	M.Tick(5)
	local cpu = os.clock() - t0
	assert(not ns.Scanner.status.fullScan, "full scan never finished")
	local items = ns.History.CountData()
	eq(items, 4000)
	local s = ns.History.GetLatest("30001")
	eq(s.full, true); eq(s.auc, 5)
	assert(chatHas("full scan read: 20000 auctions"), "summary message")
	print(string.format("       (20k-auction scan processed in %.2fs CPU)", cpu))
end)

test("full scan interrupted by closing the AH saves what was read as partial", function()
	local ns = load(nil)
	M.OpenAH()
	for i = 1, 3000 do addAuctions("Item " .. i, 30000 + i, 1, 1000) end
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(0.06)
	M.CloseAH()
	M.Tick(1)
	assert(chatHas("full scan interrupted"), "no interrupt message")
	local items = ns.History.CountData()
	assert(items > 0 and items < 3000, "expected a partial save, got " .. items)
	eq(ns.History.GetLatest("30001").full, false)
end)

test("watchlist scan queries each item (exact, all pages) and respects the throttle", function()
	local ns = load(nil)
	M.OpenAH()
	M.ahThrottle = 0.5
	ns.Watch.Add("Primal Fire")
	ns.Watch.Add("Primal Water")
	addAuctions("Primal Fire", 21884, 120, 150000)
	addAuctions("Primal Water", 21885, 5, 90000)
	addAuctions("Primal Fire Shard", 99999, 3, 1)
	ns.Scanner.ScanWatchlist()
	M.Tick(10)
	assert(not ns.Scanner.status.scanning, "scan did not finish")
	eq(#M.queries, 4, "3 pages of Primal Fire + 1 of Primal Water")
	for _, q in ipairs(M.queries) do eq(q.exact, true, "exact match") end
	local s = ns.History.GetLatest("21884")
	eq(s.auc, 120); eq(s.full, true)
	eq(ns.History.GetLatest("21885").auc, 5)
	eq(ns.History.GetLatest("99999"), nil, "non-exact match recorded")
	assert(chatHas("watchlist scan finished"), "finish message")
end)

test("watchlist scan stops cleanly when the AH closes", function()
	local ns = load(nil)
	M.OpenAH()
	M.ahThrottle = 1
	for i = 1, 5 do ns.Watch.Add("Thing " .. i) end
	ns.Scanner.ScanWatchlist()
	M.Tick(1.5)
	M.CloseAH()
	M.Tick(2)
	assert(not ns.Scanner.status.scanning, "still scanning")
end)

test("neutral auction house gets its own price data", function()
	local ns = load(nil)
	M.mapID = 1446 -- Tanaris / Gadgetzan
	M.OpenAH()
	eq(ns.realmKey, "Dreamscythe-Neutral")
	addAuctions("Fel Iron Ore", 23424, 3, 20000)
	search("Fel Iron Ore"); M.Tick(3)
	M.CloseAH()
	M.mapID = 1453
	M.OpenAH()
	eq(ns.realmKey, "Dreamscythe-Alliance")
	eq(ns.History.GetLatest("23424"), nil, "neutral data leaked into faction AH")
end)

---------------------------------------------------------------------------
test("saved variables round-trip and stay compact", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	for i = 1, 2000 do addAuctions("Item " .. i, 30000 + i, 3, 1000 + i) end
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(5)
	ns.History.GetRaw(ns.realm.items["23571"]) -- fill the decode cache
	ns.Watch.Add("Primal Might", 500000)
	local saved = M.Serialize(MarketIntelDB)
	print(string.format("       (2001 items -> %d KB of SavedVariables, about %d bytes per item)",
		math.floor(#saved / 1024), math.floor(#saved / 2001)))
	assert(not saved:find("_raw"), "cache leaked into saved variables")
	M.reset()
	local ns2 = load(M.Deserialize(saved))
	eq(ns2.History.GetReference("23571"), 800000, "history lost after reload")
	eq(ns2.Watch.Get("primal might").max, 500000)
	eq(ns2.History.CountData(), 2001)
end)

test("tooltip shows market lines for items with history", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	GameTooltip:SetHyperlink(M.Link(23571, "Primal Might"))
	local text = table.concat(GameTooltip.lines, "\n")
	assert(text:find("Market Intel"), "no header")
	assert(text:find("Normal price %(history%)"), "no normal price")
	assert(text:find("Depth:"), "no depth")
	ns.settings.tooltip = false
	GameTooltip:SetHyperlink(M.Link(23571, "Primal Might"))
	eq(#GameTooltip.lines, 1, "tooltip setting ignored")
	-- items we know nothing about add nothing
	ns.settings.tooltip = true
	GameTooltip:SetHyperlink(M.Link(1, "Unknown"))
	eq(#GameTooltip.lines, 1)
end)

test("integrations: Auctionator search + price, and broken APIs never error", function()
	local ns = load(nil)
	local searched
	Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(caller, id) assert(caller == "MarketIntel") return id == 1 and 5000 or nil end,
		MultiSearchExact = function(caller, terms) searched = terms[1] end,
	} } }
	eq(ns.Integrations.GetAuctionatorPrice("1"), 5000)
	eq(ns.Integrations.SearchItem("Primal Might"), true)
	eq(searched, "Primal Might")
	Auctionator.API.v1.GetAuctionPriceByItemID = function() error("boom") end
	eq(ns.Integrations.GetAuctionatorPrice("1"), nil)
	TSM_API = { GetCustomPriceValue = function() error("no data") end }
	eq(ns.Integrations.GetTSMPrice("1"), nil)
	-- without Auctionator the default browse search is used
	Auctionator = nil
	eq(ns.Integrations.SearchItem("X"), false, "AH closed")
	M.OpenAH()
	eq(ns.Integrations.SearchItem("X"), true)
	eq(M.queries[#M.queries].exact, true)
end)

test("bag report and slash commands", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	M.bags[0] = { M.Link(23571, "Primal Might"), nil }
	M.bags[1] = { M.Link(5, "Unknown thing") }
	SlashCmdList.MARKETINTEL("bags")
	assert(chatHas("Primal Might"), "bag report missing item")
	for _, cmd in ipairs({ "help", "stats", "purge", "deals", "depth", "history", "watch", "settings", "", "scan", "unwatch Nothing" }) do
		SlashCmdList.MARKETINTEL(cmd)
	end
	SlashCmdList.MARKETINTEL("reset")
	eq(M.popup, "MARKETINTEL_RESET")
	StaticPopupDialogs.MARKETINTEL_RESET.OnAccept()
	eq(ns.History.CountData(), 0)
end)

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------
local function populate(ns)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 800000)
	for i = 1, 40 do recordDays(ns, "Gem " .. i, 40000 + i, 1, 10000 * i) end
	M.now = M.now + 60 -- the gems are now just over 24h old
	addAuctions("Primal Might", 23571, 30, 800000, { sellers = 16 })
	addAuctions("Primal Might", 23571, 1, 300000, { owner = "Cheapo" })
	search("Primal Might"); M.Tick(3)
	ns.Watch.Add("Primal Might", 350000)
	ns.Watch.Add("Never Seen Item")
end

test("UI: every tab builds and fills with data", function()
	local ns = load(nil)
	populate(ns)
	SlashCmdList.MARKETINTEL("")
	assert(ns.UI.IsShown(), "window not shown")
	for _, tab in ipairs({ "deals", "depth", "history", "watch", "settings" }) do
		ns.UI.Show(tab)
		assert(ns.UI.GetPage(tab):IsShown(), tab .. " hidden")
	end
	local deals = ns.UI.GetPage("deals").list
	ns.UI.Show("deals")
	eq(#deals.data, 1)
	assert(deals.rows[1]:IsShown() and deals.rows[1].cells[1]:GetText():find("Primal Might"), "deal row")
	ns.UI.Show("depth")
	local depth = ns.UI.GetPage("depth").list
	eq(#depth.data, 1, "only Primal Might is fresh (24h filter)")
	assert(depth.rows[1].cells[2]:GetText():find("Flooded"), "16 sellers should be flooded")
	ns.UI.Show("watch")
	local watch = ns.UI.GetPage("watch").list
	eq(#watch.data, 2)
	assert(watch.rows[1].cells[5]:GetText():find("BUY"), "BUY status first")
	assert(watch.rows[2].cells[5]:GetText():find("not seen"), "unseen item")
end)

test("UI: sorting, scrolling and clicking rows", function()
	local ns = load(nil)
	populate(ns)
	ns.UI.Show("history")
	local page = ns.UI.GetPage("history")
	local list = page.list
	eq(#list.data, 41)
	-- sort by market value, descending then ascending
	list.headers[2]:Click()
	assert(list.data[1].latest.mkt >= list.data[2].latest.mkt, "descending sort")
	list.headers[2]:Click()
	assert(list.data[1].latest.mkt <= list.data[2].latest.mkt, "ascending sort")
	assert(list.headers[2].text:GetText():find("%^"), "sort arrow")
	-- scroll to the end
	_G[list.scroll:GetName() .. "ScrollBar"]:SetValue(1000 * 18)
	eq(list.scroll.offset, 41 - 18, "clamped scroll offset")
	assert(list.rows[18]:IsShown() and list.rows[18].entry == list.data[41], "last row")
	-- mouse wheel
	list:GetScript("OnMouseWheel")(list, 1)
	-- click a row -> detail panel
	list.rows[1]:Click()
	assert(page.selected, "row click did not select")
	assert(page.title:GetText() ~= "Select an item", "detail title")
	for _, days in ipairs({ 7, 30, 90 }) do page.ranges[days]:Click() end
	-- search box filters
	page.search:SetText("gem 1")
	page.search:GetScript("OnTextChanged")(page.search, true)
	eq(#list.data, 11, "Gem 1, Gem 10-19")
	-- the graph drew bars for Primal Might
	page:Select("23571")
	local shown = 0
	for _, b in ipairs(page.graph.bars) do if b:IsShown() then shown = shown + 1 end end
	eq(shown, 6, "5 past days + today")
	page.graph.bars[1]:GetScript("OnEnter")(page.graph.bars[1])
	assert(GameTooltip.lines[1], "bar tooltip")
	-- watch toggle from history
	page.watchBtn:Click()
	eq(ns.Watch.Get("Primal Might"), nil, "unwatch from history")
	page.watchBtn:Click()
	assert(ns.Watch.Get("Primal Might"), "watch from history")
	-- deal row click searches the AH; depth row click opens history
	ns.UI.Show("deals")
	ns.UI.GetPage("deals").list.rows[1]:Click()
	eq(M.queries[#M.queries].name, "Primal Might")
	M.shift = true
	ns.UI.GetPage("deals").list.rows[1]:Click()
	assert(M.insertedLink, "shift-click link")
	M.shift = nil
	ns.UI.Show("depth")
	ns.UI.GetPage("depth").list.rows[1]:Click()
	assert(ns.UI.GetPage("history"):IsShown(), "depth click opens history")
	-- hover tooltips on every list
	for _, tab in ipairs({ "deals", "depth", "history", "watch" }) do
		ns.UI.Show(tab)
		local row = ns.UI.GetPage(tab).list.rows[1]
		row:GetScript("OnEnter")(row)
		row:GetScript("OnLeave")(row)
	end
end)

test("UI: watchlist editing, bad price, right-click remove, scan button", function()
	local ns = load(nil)
	populate(ns)
	ns.UI.Show("watch")
	local page = ns.UI.GetPage("watch")
	local boxes = {}
	for _, c in ipairs(page._children) do if c._kind == "EditBox" then boxes[#boxes + 1] = c end end
	local nameBox, priceBox = boxes[1], boxes[2]
	nameBox:SetText("Primal Earth")
	priceBox:SetText("12 gold")
	nameBox:GetScript("OnEnterPressed")(nameBox)
	assert(chatHas("could not read the price"), "bad price accepted")
	eq(ns.Watch.Get("Primal Earth"), nil)
	priceBox:SetText("12g 50s")
	priceBox:GetScript("OnEnterPressed")(priceBox)
	eq(ns.Watch.Get("Primal Earth").max, 125000)
	eq(nameBox:GetText(), "", "box cleared")
	-- shift-clicking a link while the box has focus fills it
	nameBox:SetFocus()
	ChatEdit_InsertLink(M.Link(23571, "Primal Might"))
	eq(nameBox:GetText(), "Primal Might")
	nameBox:ClearFocus()
	-- left click fills the boxes for editing
	page:Update()
	page.list.rows[1]:Click("LeftButton")
	eq(nameBox:GetText(), "Primal Might")
	eq(priceBox:GetText(), "35g 0s")
	-- right click removes
	page.list.rows[1]:Click("RightButton")
	eq(ns.Watch.Get("Primal Might"), nil)
	-- scan button toggles start/stop
	M.ahThrottle = 1
	page.scanBtn:Click()
	assert(ns.Scanner.status.scanning, "scan not started")
	assert(page.scanBtn:GetText():find("Stop %(1/2%)"), "button label right after starting: " .. page.scanBtn:GetText())
	M.Tick(1.1)
	assert(page.scanBtn:GetText():find("Stop"), "button label while scanning")
	page.scanBtn:Click()
	M.Tick(0.2)
	assert(not ns.Scanner.status.scanning, "scan not stopped")
end)

test("UI: settings edit boxes validate and clamp", function()
	local ns = load(nil)
	ns.UI.Show("settings")
	local page = ns.UI.GetPage("settings")
	local function box(key)
		for _, c in ipairs(page.controls) do if c.def.key == key and not c.SetChecked then return c end end
		for _, c in ipairs(page.controls) do if c.def.key == key then return c end end
	end
	local eb = box("dealPct")
	eq(eb:GetText(), "60")
	eb:SetFocus(); eb:SetText("500"); eb:ClearFocus()
	eq(ns.settings.dealPct, 100, "clamped to 100")
	eb:SetFocus(); eb:SetText("abc"); eb:ClearFocus()
	eq(ns.settings.dealPct, 100, "junk ignored"); eq(eb:GetText(), "100")
	local gold = box("minDealProfit")
	eq(gold:GetText(), "2")
	gold:SetFocus(); gold:SetText("7.5"); gold:ClearFocus()
	eq(ns.settings.minDealProfit, 75000)
	local ratio = box("thinRatio")
	ratio:SetFocus(); ratio:SetText("0.3"); ratio:ClearFocus()
	eq(ns.settings.thinRatio, 0.3)
	local cb = box("alertSound")
	cb:SetChecked(false); cb:Click()
	eq(ns.settings.alertSound, false)
	-- reset defaults
	for _, c in ipairs(page._children) do
		if c._kind == "Button" and c:GetText() == "Reset defaults" then c:Click() end
	end
	eq(ns.settings.dealPct, 60); eq(ns.settings.alertSound, true)
	eq(box("dealPct"):GetText(), "60", "box shows reset value")
end)

test("UI: auction house button, status line and refresh throttling", function()
	local ns = load(nil)
	M.OpenAH()
	assert(ns.UI.ahButton, "no AH button")
	ns.UI.ahButton:Click()
	assert(ns.UI.IsShown(), "AH button does not open the window")
	local f = ns.UI.GetFrame()
	assert(f.status:GetText():find("Auction house open"), "status line")
	-- many data events in a short time cause at most one deferred refresh
	local page = ns.UI.GetPage("deals")
	local calls, orig = 0, page.Update
	page.Update = function(...) calls = calls + 1 return orig(...) end
	for _ = 1, 20 do ns.Fire("MI_DATA_UPDATED") end
	M.Tick(1.5)
	assert(calls <= 2, "refresh not throttled: " .. calls)
	-- ESC-closable
	eq(UISpecialFrames[1], "MarketIntelFrame")
	ns.UI.Toggle()
	assert(not ns.UI.IsShown())
	-- reopening the AH does not create a second button
	M.CloseAH(); M.OpenAH()
	local n = 0
	for _, c in ipairs(AuctionFrame._children) do if c._kind == "Button" then n = n + 1 end end
	eq(n, 1)
end)

test("UI: depth and history tabs stay fast with thousands of items", function()
	local ns = load(nil)
	M.OpenAH()
	for i = 1, 6000 do addAuctions("Item " .. i, 30000 + i, 4, 1000 + i, { sellers = 4 }) end
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(5)
	eq(ns.History.CountData(), 6000)
	for _, tab in ipairs({ "depth", "history" }) do
		ns.UI.Show(tab)
		local t0 = os.clock()
		ns.UI.GetPage(tab):Update()
		print(string.format("       (%s tab refresh with 6000 items: %.3fs CPU)", tab, os.clock() - t0))
	end
end)

test("UI: empty states render without data", function()
	local ns = load(nil)
	for _, tab in ipairs({ "deals", "depth", "history", "watch", "settings" }) do ns.UI.Show(tab) end
	local h = ns.UI.GetPage("history")
	eq(h.title:GetText(), "Select an item")
	assert(h.graph.empty:GetText():find("No history"), "graph empty text")
end)

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, #failed))
local used = {}
for m in pairs(M.usedMethods) do used[#used + 1] = m end
table.sort(used)
print("widget methods used: " .. table.concat(used, ", "))
os.exit(#failed == 0 and 0 or 1)
