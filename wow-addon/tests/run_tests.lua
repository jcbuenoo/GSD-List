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
-- number of entries in an encoded history string
local function entries(str)
	if not str or str == "" then return 0 end
	return select(2, str:gsub(";", "")) + 1
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
	eq(entries(ns.realm.items["23425"].s), 1, "one snapshot")
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
	eq(entries(ns.realm.items["23445"].s), 1, "stale results saved again")
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

test("repeat searches within 30 minutes replace the snapshot; partial never shrinks a full one", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Fire", 21884, 60, 150000)
	search("Primal Fire", 0); search("Primal Fire", 1); M.Tick(3)
	eq(ns.History.GetLatest("21884").qty, 60)
	M.now = M.now + 120
	search("Primal Fire", 0); M.Tick(3) -- only page 1 this time
	local item = ns.realm.items["21884"]
	eq(entries(item.s), 1, "replaced, not appended")
	eq(ns.History.GetLatest("21884").qty, 60, "partial must not shrink the full quantity")
	M.now = M.now + 3600
	search("Primal Fire", 0); M.Tick(3)
	eq(entries(item.s), 2, "new snapshot after the replace window")
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
	eq(entries(item.s), 30)
	local before = ns.History.GetDaily(item, M.now)
	ns.History.Compact(M.now)
	eq(entries(item.s), 6, "raw kept for 2 days") -- days -1 and -2
	eq(entries(item.d), 8)
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
	eq(entries(item.d), 8)
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

test("full scan is read once even when the client re-fires the update event", function()
	local ns = load(nil)
	M.OpenAH()
	for i = 1, 500 do addAuctions("Item " .. i, 30000 + i, 2, 1000 + i) end
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(2)
	for _ = 1, 3 do M.FireEvent("AUCTION_ITEM_LIST_UPDATE"); M.Tick(1) end
	local reads = 0
	for _, line in ipairs(M.chat) do if line:find("full scan read") then reads = reads + 1 end end
	eq(reads, 1, "full scan re-read")
	-- a new full scan later is read again
	M.Tick(900)
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(2)
	reads = 0
	for _, line in ipairs(M.chat) do if line:find("full scan read") then reads = reads + 1 end end
	eq(reads, 2, "second full scan ignored")
end)

test("own auctions are recognised with a realm suffix on the name", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Air", 22451, 1, 100000, { owner = "Tester-Dreamscythe" })
	addAuctions("Primal Air", 22451, 2, 120000, { owner = "Someone" })
	search("Primal Air"); M.Tick(3)
	eq(ns.current["22451"].mine, 1)
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
-- Build a fake Auctionator database the way Auctionator stores it.
local function fakeAuctionator(realmKey, items, daysBack)
	local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
	local today = math.floor((M.now - day0) / DAY)
	local realm = {}
	for id, price in pairs(items) do
		local e = { m = price, l = {}, h = {}, a = {} }
		for d = today - daysBack, today - 1 do
			e.l[tostring(d)] = price
			e.h[tostring(d)] = price * 1.2
			e.a[tostring(d)] = 40
		end
		realm[tostring(id)] = e
	end
	realm["g:28432:115"] = { m = 5, l = { ["2000"] = 5 }, h = {} }
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 6, [realmKey] = realm, ["Other Realm"] = { ["1"] = { m = 1, l = {}, h = {} } } }
end

test("Auctionator history import seeds normal prices immediately", function()
	fakeAuctionator("Dreamscythe", { [23571] = 800000, [22451] = 100000 }, 10)
	local ns = load(nil) -- empty history -> imports automatically on login
	M.Tick(1)
	assert(chatHas("imported 20 days of price history for 2 items"), "import message: " .. tostring(M.chat[#M.chat]))
	local ref, src = ns.History.GetReference("23571")
	eq(src, "history"); eq(ref, 880000, "midpoint of Auctionator's low and high")
	eq(ns.History.GetItem("g:28432:115"), nil, "gear keys must be skipped")
	eq(ns.History.GetNormalSupply("23571"), 40)
	-- importing again adds nothing; our own days are never overwritten
	M.chat = {}
	SlashCmdList.MARKETINTEL("import")
	M.Tick(1)
	assert(chatHas("imported 0 days"), "re-import should add nothing")
	-- and we never auto-import twice
	eq(type(ns.realm.importedAuctionator), "number")
end)

-- Minimal CBOR encoder (tests only), producing data the way Auctionator 8+ packs it:
-- map keys as byte strings, empty tables as empty arrays.
local function cborHead(major, n)
	if n < 24 then return string.char(major * 32 + n) end
	if n < 256 then return string.char(major * 32 + 24, n) end
	if n < 65536 then return string.char(major * 32 + 25, math.floor(n / 256), n % 256) end
	local b = {}
	for i = 3, 0, -1 do b[#b + 1] = math.floor(n / 256 ^ i) % 256 end
	return string.char(major * 32 + 26, unpack(b))
end
local function cbor(v)
	local t = type(v)
	if t == "number" then
		if v >= 0 and v % 1 == 0 then return cborHead(0, v) end
		if v < 0 and v % 1 == 0 then return cborHead(1, -1 - v) end
		error("floats not needed in tests")
	elseif t == "string" then return cborHead(2, #v) .. v
	elseif t == "boolean" then return string.char(v and 0xf5 or 0xf4)
	elseif t == "table" then
		if next(v) == nil then return string.char(0x80) end
		local parts, n = {}, 0
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			parts[#parts + 1] = cbor(k) .. cbor(v[k])
			n = n + 1
		end
		return cborHead(5, n) .. table.concat(parts)
	end
	error("cannot encode " .. t)
end

test("CBOR decoder reads Auctionator's packed format, including floats and odd encodings", function()
	local ns = load(nil)
	local value = ns.Integrations.CBORDecoder(cbor({ ["25115"] = { a = { ["2488"] = 2 }, l = {}, m = 1660800, h = { ["2488"] = 1220199 } } }))
	local t = value()
	eq(t["25115"].m, 1660800); eq(t["25115"].h["2488"], 1220199); eq(next(t["25115"].l), nil)
	-- floats (half, single, double), negative ints, true/false/nil, tags, indefinite strings/arrays/maps
	local raw = string.char(0x88, 0xf9, 0x3e, 0x00, 0xfa, 0x40, 0x49, 0x0f, 0xdb, 0xfb, 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18,
		0x38, 0x63, 0xf5, 0xf6, 0xc1, 0x1a, 0x5f, 0x5e, 0x10, 0x00)
		.. string.char(0x5f, 0x42, 0x61, 0x62, 0x41, 0x63, 0xff) -- indefinite byte string "abc"
	value = ns.Integrations.CBORDecoder(raw .. string.char(0xbf, 0x41, 0x6b, 0x9f, 0x01, 0x02, 0xff, 0xff))
	t = value()
	eq(t[1], 1.5); near(t[2], 3.14159274, 1e-6); near(t[3], math.pi, 1e-12); eq(t[4], -100); eq(t[5], true); eq(t[6], nil)
	eq(t[7], 1600000000); eq(t[8], "abc")
	local m = value()
	eq(m.k[2], 2)
	-- truncated data is reported, not crashed on
	local ok, err = pcall(ns.Integrations.CBORDecoder(string.char(0x45, 0x31, 0x32)))
	assert(not ok and tostring(err):find("ends early"), "truncated: " .. tostring(err))
end)

test("Auctionator import reads the packed (CBOR) database of Auctionator 8+", function()
	local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
	local today = math.floor((M.now - day0) / DAY)
	local function entry(price, withLow)
		local e = { a = {}, h = {}, l = {}, m = price }
		for d = today - 6, today - 1 do
			e.h[tostring(d)] = price + 1000
			e.a[tostring(d)] = 12
			if withLow then e.l[tostring(d)] = price - 1000 end
		end
		return e
	end
	local realm = { ["23571"] = entry(800000, true), ["22451"] = entry(100000, false),
		["gr:9844:of Intellect"] = entry(5, true), ["g:28432:115"] = entry(5, true), ["p:1234"] = entry(5, true) }
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["Dreamscythe Alliance"] = cbor(realm), ["Other Realm Horde"] = cbor({}) }
	local ns = load(nil)
	M.Tick(1)
	assert(chatHas("imported 12 days of price history for 2 items"), "import message: " .. tostring(M.chat[#M.chat]))
	assert(chatHas("3 gear/pet entries skipped"), "skipped count")
	eq(ns.History.GetReference("23571"), 800000, "midpoint of low and high")
	eq(ns.History.GetReference("22451"), 101000, "high only")
	eq(ns.History.GetNormalSupply("23571"), 12)
	-- corrupt packed data is reported and nothing breaks
	M.reset()
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["Dreamscythe Alliance"] = cbor(realm):sub(1, 200) }
	ns = load(nil)
	M.Tick(1)
	assert(chatHas("could not be read") or chatHas("not recognized"), "corrupt data not reported: " .. tostring(M.chat[#M.chat]))
	eq(#M.errors, 0)
	-- not a map at all
	M.reset()
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["Dreamscythe Alliance"] = "\1\2\3" }
	ns = load(nil)
	SlashCmdList.MARKETINTEL("import")
	M.Tick(1)
	assert(chatHas("not recognized"), "non-map not reported")
end)

test("Auctionator import also runs for an auction house that already has scan data", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Might", 23571, 3, 800000)
	search("Primal Might"); M.Tick(3)
	M.CloseAH()
	local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
	local d = tostring(math.floor((M.now - day0) / DAY) - 2)
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["Dreamscythe Alliance"] = cbor({ ["23571"] = { h = { [d] = 900000 }, l = {}, a = {}, m = 1 } }) }
	ns.Fire("MI_READY") -- next login
	M.Tick(1)
	eq(#ns.History.GetDaily(ns.History.GetItem("23571"), M.now), 2, "imported day added next to today's scan")
	eq(type(ns.realm.importedAuctionator), "number")
end)

test("a few days of one silly listing cannot set the normal price; thin crafting prices are flagged", function()
	-- the real Gnomish Flame Turret case: 5.81g for two days, then a lone 1,004g listing for two days
	local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
	local today = math.floor((M.now - day0) / DAY)
	local turret = { h = {}, l = {}, a = {}, m = 10042300 }
	for i, p in ipairs({ 58100, 58100, 10042300, 10042300 }) do
		turret.h[tostring(today - 5 + i)] = p
		turret.a[tostring(today - 5 + i)] = ({ 68, 15, 8, 1 })[i]
	end
	local ray = { h = {}, l = {}, a = {}, m = 4500000 }
	for i = 1, 3 do ray.h[tostring(today - 4 + i)] = 4500000; ray.a[tostring(today - 4 + i)] = 1 end
	_G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["Dreamscythe Alliance"] = cbor({ ["23841"] = turret, ["10716"] = ray }) }
	_G.TradeSkillMasterDB = {
		["f@Alliance - Dreamscythe@internalData@isCraftFavorite"] = { [1] = true, [2] = true },
		["f@Alliance - Dreamscythe@internalData@crafts"] = {
			["c:1"] = { name = "Gnomish Flame Turret", profession = "Engineering", itemString = "i:23841", numResult = 3, mats = { ["i:3371"] = 1 } },
			["c:2"] = { name = "Gnomish Shrink Ray", profession = "Engineering", itemString = "i:10716", numResult = 1, mats = { ["i:3371"] = 1 } },
		},
	}
	_G.AUCTIONATOR_VENDOR_PRICE_CACHE = { ["3371"] = 4 }
	local ns = load(nil)
	M.Tick(1)
	eq(ns.History.GetReference("23841"), 58100, "lone 1,004g listing set the normal price")
	local byName = {}
	for _, e in ipairs(ns.Crafting.List(false)) do byName[e.name] = e end
	eq(byName["Gnomish Flame Turret"].thin, false)
	near(byName["Gnomish Flame Turret"].profit, 58100 * 0.95 * 3 - 4, 1)
	eq(byName["Gnomish Shrink Ray"].thin, true, "one listing a day must be flagged")
	eq(byName["Gnomish Flame Turret"].parts[1].source, "vendor")
	ns.UI.Show("crafting")
	local found
	for _, row in ipairs(ns.UI.GetPage("crafting").list.rows) do
		if row.entry and row.entry.name == "Gnomish Shrink Ray" then found = row.cells[5]:GetText() end
	end
	assert(found and found:find("%?"), "thin profit not marked")
end)

test("Auctionator import picks the right faction and rejects unknown formats", function()
	fakeAuctionator("Dreamscythe Horde", { [1] = 100 }, 5)
	AUCTIONATOR_PRICE_DATABASE["Dreamscythe Alliance"] = AUCTIONATOR_PRICE_DATABASE["Dreamscythe Horde"]
	AUCTIONATOR_PRICE_DATABASE["Dreamscythe Horde"] = { ["2"] = { m = 1, l = { ["100"] = 1 }, h = {} } }
	local ns = load(nil)
	M.Tick(1)
	local _, name = ns.Integrations.FindAuctionatorRealm(AUCTIONATOR_PRICE_DATABASE)
	eq(name, "Dreamscythe Alliance")
	assert(ns.History.GetItem("1"), "alliance data not imported")
	-- a database with a different shape is reported, not imported
	M.reset()
	_G.AUCTIONATOR_PRICE_DATABASE = { Dreamscythe = { ["5"] = 12345, ["6"] = "x", ["7"] = { price = 3 } } }
	ns = load(nil)
	M.Tick(1)
	SlashCmdList.MARKETINTEL("import")
	M.Tick(1)
	assert(chatHas("format was not recognized"), "unknown format not reported")
	eq(ns.History.CountData(), 0)
	-- no Auctionator at all
	M.reset()
	ns = load(nil)
	SlashCmdList.MARKETINTEL("import")
	assert(chatHas("was not found"), "missing Auctionator not reported")
end)

test("items only seen in full scans keep less history than searched items", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Searched Thing", 501, 3, 1000)
	addAuctions("Scanned Thing", 502, 3, 1000)
	local base = M.now
	for d = 40, 1, -1 do
		M.now = base - d * DAY
		search("Searched Thing"); M.Tick(3)
		QueryAuctionItems("", nil, nil, 0, false, nil, true, false); M.Tick(3)
		M.Tick(900)
	end
	M.now = base
	ns.History.Compact(M.now)
	local searched = ns.History.GetDaily(ns.History.GetItem("501"), M.now)
	local scanned = ns.History.GetDaily(ns.History.GetItem("502"), M.now)
	eq(#searched, 40, "searched item keeps 60 days")
	eq(#scanned, 21, "scan-only item keeps 21 days")
end)

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
-- 1.2 features
---------------------------------------------------------------------------
-- The addon must never buy or post: these fail the test if ever called.
local function forbidBuying()
	_G.PlaceAuctionBid = function() error("addon tried to buy an auction") end
	_G.PostAuction = function() error("addon tried to post an auction") end
	_G.StartAuction = function() error("addon tried to post an auction") end
end

test("ledger: reads sold/bought/expired/cancelled mail once, with totals and sell-through", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Primal Might", 23571, 3, 800000); search("Primal Might"); M.Tick(3)
	M.owned = { { name = "Primal Might", count = 2, buyout = 1700000, minBid = 1600000, quality = 1, id = 23571 } }
	M.FireEvent("AUCTION_OWNED_LIST_UPDATE")
	M.CloseAH()
	M.mail = {
		{ subject = "Auction successful: Primal Might", money = 1615000, daysLeft = 29.5,
			invoice = { type = "seller", item = "Primal Might", player = "Buyerguy", bid = 1700000, buyout = 1700000, deposit = 0, cut = 85000 } },
		{ subject = "Auction won: Khorium Ore", daysLeft = 29.0, item = { name = "Khorium Ore", id = 23426, count = 5 },
			invoice = { type = "buyer", item = "Khorium Ore", player = "Seller1", bid = 1000000, buyout = 1000000 } },
		{ subject = "Auction expired: Primal Might", daysLeft = 28.0, item = { name = "Primal Might", id = 23571, count = 1 } },
		{ subject = "Auction cancelled: Fel Lotus", daysLeft = 27.0, item = { name = "Fel Lotus", id = 22794, count = 4 } },
		{ subject = "Hello from a friend", money = 100, daysLeft = 3 },
	}
	M.FireEvent("MAIL_INBOX_UPDATE")
	M.Tick(1)
	local entries = ns.Ledger.Entries()
	eq(#entries, 4, "auction mails recorded")
	local sold
	for _, e in ipairs(entries) do if e.type == "sold" then sold = e end end
	eq(sold.qty, 2, "quantity from your own auction list"); eq(sold.net, 1615000); eq(sold.cut, 85000); eq(sold.who, "Buyerguy")
	-- reopening the mailbox later (days left has dropped) records nothing new
	M.now = M.now + 1800
	for _, m in ipairs(M.mail) do m.daysLeft = m.daysLeft - 1800 / 86400 end
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(#ns.Ledger.Entries(), 4, "mail counted twice")
	local sm = ns.Ledger.Summary(30)
	eq(sm.sales, 1700000); eq(sm.spent, 1000000); eq(sm.profit, 615000); eq(sm.expired, 1); eq(sm.cancelled, 1)
	near(sm.sellThrough, 0.5, 0.001)
	local st = ns.Ledger.ItemStats("Primal Might")
	eq(st.sold, 1); eq(st.expired, 1); eq(st.avgUnit, 850000)
end)

test("posting advisor: undercut, hold, skip a thin undercut, post high, vendor", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Primal Might", 23571, 5, 1000000)
	local function post(listings)
		M.auctions = {}
		for _, l in ipairs(listings) do addAuctions("Primal Might", 23571, l[2], l[1], { sellers = l[3] or 3 }) end
		M.now = M.now + 1900
		search("Primal Might"); M.Tick(3)
		return ns.Advisor.PostPrice("23571")
	end
	local a = post({ { 990000, 6 } })
	eq(a.action, "UNDERCUT"); eq(a.price, 989999); eq(a.net, math.floor(989999 * 0.95))
	a = post({ { 600000, 6 } })
	eq(a.action, "HOLD", "60% of normal"); eq(a.price, 1000000)
	a = post({ { 500000, 1 }, { 980000, 6 } })
	eq(a.action, "UNDERCUT", "one cheap unit"); eq(a.price, 979999)
	-- one cheap auction of many units is real competition: hold
	M.auctions = {}
	addAuctions("Primal Might", 23571, 1, 500000, { count = 50 })
	addAuctions("Primal Might", 23571, 6, 980000)
	M.now = M.now + 1900
	search("Primal Might"); M.Tick(3)
	a = ns.Advisor.PostPrice("23571")
	eq(a.action, "HOLD", "50 cheap units")
	a = post({ { 1300000, 1, 1 } })
	eq(a.action, "PREMIUM", "thin market above normal"); eq(a.price, 1299999)
	-- vendor check
	M.itemInfo[23571] = { name = "Primal Might", sellPrice = 2000000 }
	_G.GetItemInfo = (function(orig) return function(item, ...)
		local id = tonumber(tostring(item):match("(%d+)"))
		if id == 23571 then return "Primal Might", M.Link(23571, "Primal Might"), 1, 70, 70, "Trade Goods", "", 20, "", "tex", 2000000 end
		return orig(item, ...)
	end end)(_G.GetItemInfo)
	a = post({ { 990000, 6 } })
	eq(a.action, "VENDOR")
	-- /mi post prints the advice
	SlashCmdList.MARKETINTEL("post Primal Might")
	assert(chatHas("Primal Might: .*Vendor it"), "slash post")
end)

test("flip finder suggests buying cheap auctions to relist, never buys", function()
	forbidBuying()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Living Ruby", 23436, 5, 1000000)
	M.auctions = {}
	addAuctions("Living Ruby", 23436, 3, 500000)         -- 3 cheap
	addAuctions("Living Ruby", 23436, 6, 980000, { sellers = 4 }) -- then the normal wall
	search("Living Ruby"); M.Tick(3)
	local flips = ns.Advisor.FindFlips(M.now)
	eq(#flips, 1)
	local f = flips[1]
	eq(f.qty, 3); eq(f.auctions, 3); eq(f.cost, 1500000); eq(f.resale, 979999)
	eq(f.profit, math.floor(979999 * 3 * 0.95 - 1500000))
	assert(f.roi > 0.8, "roi")
	-- too little profit -> no suggestion
	ns.settings.flipMinProfit = 20000000
	eq(#ns.Advisor.FindFlips(M.now), 0)
	ns.settings.flipMinProfit = 50000
	-- old searches are ignored
	eq(#ns.Advisor.FindFlips(M.now + 3 * 3600), 0, "stale listings")
	-- the tab works and clicking only searches
	ns.UI.Show("flips")
	local list = ns.UI.GetPage("flips").list
	eq(#list.data, 1)
	list.rows[1]:Click()
	eq(M.queries[#M.queries].name, "Living Ruby")
end)

local function gearSetup()
	M.itemInfo[30001] = { name = "Blade of Twinking", equipLoc = "INVTYPE_WEAPON" }
	M.itemInfo[30002] = { name = "Sixty Helm", equipLoc = "INVTYPE_HEAD" }
	M.itemInfo[30003] = { name = "Rare Pattern", equipLoc = "" }
	M.itemInfo[30004] = { name = "Slow Seller Ring", equipLoc = "INVTYPE_FINGER" }
	_G.TSM_API = { GetCustomPriceValue = function(source, item)
		local id = tonumber(item:match("i:(%d+)"))
		local market = { [30001] = 2000000, [30002] = 3000000, [30003] = 900000, [30004] = 500000 }
		local sold = { [30001] = 0.35, [30002] = 0.5, [30003] = 1, [30004] = 0.02 }
		if source == "dbmarket" then return market[id] end
		if source == "dbregionsoldperday" then return sold[id] end
		return nil
	end }
end

test("BoE snipe: blue/epic gear lvl 15-55 that sells, under 65% of TSM market, big alert", function()
	forbidBuying()
	local ns = load(nil)
	gearSetup()
	M.OpenAH()
	table.insert(M.auctions, { name = "Blade of Twinking", id = 30001, count = 1, buyout = 1100000, owner = "Cheap", quality = 3, level = 29 }) -- 55%
	table.insert(M.auctions, { name = "Blade of Twinking", id = 30001, count = 1, buyout = 1900000, owner = "Normal", quality = 3, level = 29 })
	table.insert(M.auctions, { name = "Sixty Helm", id = 30002, count = 1, buyout = 900000, owner = "X", quality = 4, level = 60 })       -- level too high
	table.insert(M.auctions, { name = "Rare Pattern", id = 30003, count = 1, buyout = 100000, owner = "X", quality = 3, level = 30 })     -- not gear
	table.insert(M.auctions, { name = "Slow Seller Ring", id = 30004, count = 1, buyout = 100000, owner = "X", quality = 3, level = 30 }) -- sells too slowly
	table.insert(M.auctions, { name = "Blade of Twinking", id = 30001, count = 1, buyout = 500000, owner = M.player, quality = 3, level = 29 }) -- mine
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(5)
	eq(#ns.snipes, 1, "snipes")
	local sn = ns.snipes[1]
	eq(sn.owner, "Cheap"); eq(sn.level, 29); near(sn.pct, 0.55, 0.001); eq(sn.source, "TSM market"); eq(sn.sold, 0.35)
	assert(chatHas("BOE SNIPE"), "chat alert")
	assert(M.raidWarnings[1] and M.raidWarnings[1]:find("Blade of Twinking"), "screen alert")
	eq(M.flashes, 1, "taskbar flash")
	-- without TSM sale data nothing qualifies unless the requirement is turned off
	ns.Snipe.Clear()
	_G.TSM_API = nil
	M.now = M.now + 3600
	QueryAuctionItems("Blade of Twinking", nil, nil, 0, false, nil, false, false); M.Tick(3)
	eq(#ns.snipes, 0)
end)

test("BoE snipe scan searches rare and epic, levels 15-55, every page", function()
	local ns = load(nil)
	gearSetup()
	M.OpenAH()
	M.ahThrottle = 0.5
	for i = 1, 70 do
		table.insert(M.auctions, { name = "Blade of Twinking", id = 30001, count = 1, buyout = 1900000 + i, owner = "S" .. i, quality = 3, level = 29 })
	end
	table.insert(M.auctions, { name = "Blade of Twinking", id = 30001, count = 1, buyout = 1000000, owner = "Lucky", quality = 3, level = 29 })
	table.insert(M.auctions, { name = "Epic Thing", id = 30002, count = 1, buyout = 1000000, owner = "Lucky", quality = 4, level = 50 })
	ns.UI.Show("snipe")
	ns.UI.GetPage("snipe").scanBtn:Click()
	M.Tick(1)
	assert(ns.UI.GetPage("snipe").scanBtn:GetText():find("Stop"), "button while scanning")
	M.Tick(15)
	assert(not ns.Scanner.status.scanning, "scan did not finish")
	local rarities, pages = {}, 0
	for _, q in ipairs(M.queries) do
		eq(q.minLevel, 15); eq(q.maxLevel, 55)
		rarities[q.rarity] = true
		pages = pages + 1
	end
	assert(rarities[3] and rarities[4], "rare and epic passes")
	eq(pages, 3, "2 pages of blues + 1 of epics")
	eq(#ns.snipes, 2, "both cheap items found")
	assert(chatHas("BoE snipe scan finished: 2 snipes"), "finish message")
end)

test("crafting: TSM-starred recipes only, profit, and deals that make a craft profitable", function()
	local ns = load(nil)
	-- TSM's real layout (TBC Anniversary): favourites are craft numbers, recipes live under "crafts"
	_G.TradeSkillMasterDB = {
		["f@Alliance - Dreamscythe@internalData@isCraftFavorite"] = { [12757595] = true },
		["f@Alliance - Dreamscythe@internalData@crafts"] = {
			["c:12757595"] = { name = "Bold Living Ruby", profession = "Jewelcrafting", itemString = "i:24027", numResult = 1,
				mats = { ["i:23436"] = 1 }, players = { Tester = true } },
			["c:5555"] = { name = "Smooth Golden Draenite", profession = "Jewelcrafting", itemString = "i:23114", numResult = 1,
				mats = { ["i:23112"] = 1 } },
		},
		["f@Horde - Otherrealm@internalData@isCraftFavorite"] = { [99] = true }, -- another realm: ignored
		["g@ @mainUIContext@isFavorite"] = { [1] = true }, -- unrelated TSM setting: ignored
	}
	M.tradeskill = { line = "Jewelcrafting", recipes = {
		{ name = "Gems", header = true },
		{ name = "Bold Living Ruby", spell = 31080, item = { id = 24027, name = "Bold Living Ruby" },
			reagents = { { id = 23436, name = "Living Ruby", count = 1 } } },
		{ name = "Smooth Golden Draenite", spell = 25255, item = { id = 23114, name = "Smooth Golden Draenite" },
			reagents = { { id = 23112, name = "Golden Draenite", count = 1 } } },
	} }
	M.FireEvent("TRADE_SKILL_SHOW"); M.Tick(1)
	eq(ns.db.recipes[31080].prof, "Jewelcrafting")
	eq(ns.db.recipes[31080].r["23436"], 1)
	M.OpenAH()
	recordDays(ns, "Living Ruby", 23436, 5, 1000000)
	recordDays(ns, "Bold Living Ruby", 24027, 5, 1000000)
	M.auctions = {}
	addAuctions("Living Ruby", 23436, 4, 1000000)
	addAuctions("Bold Living Ruby", 24027, 4, 1000000)
	search("Living Ruby"); search("Bold Living Ruby"); M.Tick(3)
	local list = ns.Crafting.List(false)
	eq(#list, 1, "only the TSM favourite")
	eq(list[1].fav, "TSM"); eq(list[1].name, "Bold Living Ruby"); eq(list[1].spellID, "c:12757595")
	near(list[1].profit, 1000000 * 0.95 - 1000000, 1, "loses the AH cut")
	-- a Living Ruby deal makes the starred craft profitable, and the alert says so
	M.chat = {}
	addAuctions("Living Ruby", 23436, 1, 500000, { owner = "Cheapo" })
	M.now = M.now + 1900
	search("Living Ruby"); M.Tick(3)
	assert(chatHas("Bold Living Ruby craft now"), "deal alert mentions the craft")
	eq(ns.deals[1].craft.name, "Bold Living Ruby")
	list = ns.Crafting.List(false)
	near(list[1].dealProfit, 1000000 * 0.95 - 500000, 1)
	-- all recipes view (TSM's list plus the profession window, without duplicates), star one in Market Intel
	eq(#ns.Crafting.List(true), 2)
	ns.Crafting.ToggleStar("c:5555")
	eq(#ns.Crafting.List(false), 2)
	ns.UI.Show("crafting")
	assert(ns.UI.GetPage("crafting").source:GetText():find("read"), "TSM favourites read")
end)

test("crafting: no TSM data falls back to Market Intel stars; enchanting recipes are learnt", function()
	local ns = load(nil)
	M.craft = { recipes = { { name = "Enchant Weapon - Mongoose", spell = 27984,
		reagents = { { id = 22449, name = "Large Prismatic Shard", count = 6 }, { id = 22446, name = "Greater Planar Essence", count = 6 } } } } }
	M.FireEvent("CRAFT_SHOW"); M.Tick(1)
	eq(ns.db.recipes[27984].prof, "Enchanting")
	eq(#ns.Crafting.List(false), 0)
	ns.Crafting.ToggleStar(27984)
	local list = ns.Crafting.List(false)
	eq(#list, 1); eq(list[1].fav, "Market Intel"); eq(list[1].missing, true, "no reagent prices yet")
	ns.UI.Show("crafting")
	assert(ns.UI.GetPage("crafting").source:GetText():find("not found"), "TSM missing note")
end)

test("minimap button: opens window, settings on right-click, drag, alert badge, hide", function()
	local ns = load(nil)
	local b = ns.Minimap.GetButton()
	assert(b and b:IsShown(), "no minimap button")
	b:GetScript("OnClick")(b, "LeftButton")
	assert(ns.UI.IsShown(), "left click opens")
	b:GetScript("OnClick")(b, "RightButton")
	assert(ns.UI.GetPage("settings"):IsShown(), "right click opens settings")
	ns.UI.Toggle()
	-- drag to the top of the minimap
	local cx, cy = Minimap:GetCenter()
	M.cursor = { cx, cy + 100 }
	b:GetScript("OnDragStart")(b)
	b:GetScript("OnUpdate")(b)
	b:GetScript("OnDragStop")(b)
	near(ns.settings.minimapAngle, 90, 0.5)
	-- alerts show a count until the window is opened
	ns.Alerts.Notify("deals", { "a", "b" }, false, "x")
	eq(b.badge:GetText(), "2")
	ns.UI.Show("deals")
	eq(b.badge:GetText(), "")
	SlashCmdList.MARKETINTEL("minimap")
	assert(not b:IsShown(), "hide")
	b:GetScript("OnEnter")(b)
end)

test("strong alerts only for big deals; CSV export escapes and opens from every tab", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Netherweave Cloth", 21877, 5, 30000)
	addAuctions("Netherweave Cloth", 21877, 1, 10000, { count = 5, owner = "Cheap" }) -- saves 10g: normal alert
	search("Netherweave Cloth"); M.Tick(3)
	eq(#ns.deals, 1); eq(#M.raidWarnings, 0, "small deal must not raid-warn")
	recordDays(ns, "Primal Might", 23571, 5, 1000000)
	M.auctions = {}
	addAuctions("Primal Might", 23571, 1, 400000, { owner = "Cheap" }) -- saves 60g
	search("Primal Might"); M.Tick(3)
	eq(#M.raidWarnings, 1, "big deal raid warning")
	local csv = ns.Export.ToCSV({ "a", "b", "c" }, { { 'He said "hi"', "x,y", 1.5 } })
	eq(csv, 'a,b,c\n"He said ""hi""","x,y",1.5000')
	-- every CSV button opens the export window with a header row
	for _, tab in ipairs({ "deals", "snipe", "flips", "crafting", "ledger", "history" }) do
		ns.UI.Show(tab)
		for _, c in ipairs(ns.UI.GetPage(tab)._children) do
			if c._kind == "Button" and (c:GetText() == "CSV" or c:GetText() == "CSV all") then
				c:Click()
				local f = ns.Export.GetFrame()
				assert(f:IsShown(), tab .. " export not shown")
				assert(f.edit:GetText():find("^[%w_]+,"), tab .. " export has no header")
				f:Hide()
			end
		end
	end
end)

---------------------------------------------------------------------------
-- 1.2.1 regressions
---------------------------------------------------------------------------
test("advisor: only your own auctions and no normal price does not crash", function()
	local ns = load(nil)
	M.OpenAH()
	addAuctions("Lonely Thing", 41000, 3, 50000, { owner = M.player })
	search("Lonely Thing"); M.Tick(3)
	local a = ns.Advisor.PostPrice("41000")
	assert(a, "should still advise from the last price seen")
	eq(a.action, "PREMIUM"); eq(a.price, 55000)
	assert(a.reason:find("No normal price"), a.reason)
	-- the tooltip, Depth tab and /mi post all work
	GameTooltip:SetHyperlink(M.Link(41000, "Lonely Thing"))
	ns.UI.Show("depth")
	SlashCmdList.MARKETINTEL("post Lonely Thing")
	assert(chatHas("Lonely Thing: "), "post output")
	eq(ns.Advisor.PostPrice("999999"), nil, "unknown item")
end)

test("ledger: identical mails are each counted, and collecting mail never double counts", function()
	local ns = load(nil)
	local function sale(minutesAgo)
		return { subject = "Auction successful: Netherweave Cloth", money = 95000, daysLeft = 30 - minutesAgo / 1440,
			invoice = { type = "seller", item = "Netherweave Cloth", player = "Bulkbuyer", bid = 100000, buyout = 100000, deposit = 0, cut = 5000 } }
	end
	M.mail = { sale(10), sale(10), sale(10) } -- one buyer bought three identical stacks
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(#ns.Ledger.Entries(), 3, "three identical sales")
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(#ns.Ledger.Entries(), 3, "reopening")
	table.remove(M.mail); table.remove(M.mail) -- collected two of them
	M.now = M.now + 120
	for _, m in ipairs(M.mail) do m.daysLeft = m.daysLeft - 120 / 86400 end
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(#ns.Ledger.Entries(), 3, "after collecting")
	table.insert(M.mail, sale(0)) -- a new identical sale, 12 minutes after the first ones
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(#ns.Ledger.Entries(), 4, "new identical sale")
	-- five identical stacks expiring together
	M.mail = {}
	for _ = 1, 5 do table.insert(M.mail, { subject = "Auction expired: Fel Lotus", daysLeft = 29.5, item = { name = "Fel Lotus", id = 22794, count = 2 } }) end
	M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
	eq(ns.Ledger.Summary(30).expired, 5)
end)

test("switching between faction and neutral auction house clears live listings, deals and flips", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Living Ruby", 23436, 5, 1000000)
	M.auctions = {}
	addAuctions("Living Ruby", 23436, 3, 500000)
	addAuctions("Living Ruby", 23436, 6, 980000)
	search("Living Ruby"); M.Tick(3)
	assert(#ns.deals > 0 and #ns.Advisor.FindFlips(M.now) > 0, "setup")
	M.CloseAH()
	M.mapID = 1446 -- Gadgetzan
	M.OpenAH()
	eq(#ns.deals, 0, "faction deals shown at the neutral AH")
	eq(#ns.Advisor.FindFlips(M.now), 0, "faction flips shown at the neutral AH")
	eq(ns.current["23436"], nil)
	-- returning to the same auction house keeps things
	M.auctions = {}
	addAuctions("Living Ruby", 23436, 2, 700000)
	search("Living Ruby"); M.Tick(3)
	M.CloseAH(); M.OpenAH()
	assert(ns.current["23436"], "same AH should keep live data")
end)

test("flips are not suggested from a partial search", function()
	local ns = load(nil)
	M.OpenAH()
	recordDays(ns, "Living Ruby", 23436, 5, 1000000, 60)
	M.auctions = {}
	addAuctions("Living Ruby", 23436, 3, 500000)
	addAuctions("Living Ruby", 23436, 60, 980000)
	search("Living Ruby", 0); M.Tick(3) -- page 1 of 2 only
	eq(ns.History.GetLatest("23436").full, false)
	eq(#ns.Advisor.FindFlips(M.now), 0)
	search("Living Ruby", 1); M.Tick(3)
	eq(#ns.Advisor.FindFlips(M.now), 1, "complete search")
end)

test("watchlist BUY only for recent prices; badge ignores alerts while the window is open", function()
	local ns = load(nil)
	M.OpenAH()
	ns.Watch.Add("Khorium Ore", 200000)
	addAuctions("Khorium Ore", 23426, 2, 150000)
	search("Khorium Ore"); M.Tick(3)
	eq(ns.Watch.List()[1].buy, true)
	M.now = M.now + 5 * 3600
	local w = ns.Watch.List()[1]
	eq(w.buy, false, "stale BUY"); eq(w.wasUnder, true)
	ns.UI.Show("watch")
	assert(ns.UI.GetPage("watch").list.rows[1].cells[5]:GetText():find("was under"), "stale status text")
	local before = ns.Alerts.unseen
	ns.Alerts.Notify("deals", { "x" }, false, "x")
	eq(ns.Alerts.unseen, before, "badge counted while open")
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
	for _, tab in ipairs({ "deals", "snipe", "flips", "depth", "history", "crafting", "ledger", "watch", "settings" }) do
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
	assert(page.scanBtn:GetText():find("Stop scan %(1/2%)"), "button label right after starting: " .. page.scanBtn:GetText())
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

test("UI: window opens beside the auction house and remembers where it was dragged", function()
	local ns = load(nil)
	M.OpenAH()
	ns.UI.ahButton:Click()
	local f = ns.UI.GetFrame()
	local point, rel, relPoint, x = f:GetPoint()
	eq(point, "TOPLEFT"); eq(rel, AuctionFrame); eq(relPoint, "TOPRIGHT"); eq(x, 10)
	local r, ah = M.Rect(f), M.Rect(AuctionFrame)
	assert(r.l >= ah.r, "window covers the auction house")
	local mm, btn = M.Rect(Minimap), M.Rect(ns.UI.ahButton)
	assert(r.r <= mm.l, "window covers the minimap")
	assert(r.t <= btn.b, "window covers the Market Intel button")
	-- drag it somewhere: position saved and restored next time
	f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60)
	f:GetScript("OnDragStop")(f)
	ns.UI.Toggle(); ns.UI.Toggle()
	point, rel, relPoint, x = f:GetPoint()
	eq(point, "TOPLEFT"); eq(x, 50)
	eq(ns.settings.windowPos[4], -60)
	-- settings boxes explain themselves on hover
	ns.UI.Show("settings")
	local eb
	for _, c in ipairs(ns.UI.GetPage("settings").controls) do if c.def.tip and not eb then eb = c end end
	eb:GetScript("OnEnter")(eb)
	assert(GameTooltip.lines[2] and #GameTooltip.lines[2] > 20, "no setting tooltip")
end)

test("UI: empty states render without data", function()
	local ns = load(nil)
	for _, tab in ipairs({ "deals", "snipe", "flips", "depth", "history", "crafting", "ledger", "watch", "settings" }) do ns.UI.Show(tab) end
	assert(ns.UI.GetPage("ledger").summary:GetText():find("Open your mailbox"), "empty ledger hint")
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
local missing = {}
for m in pairs(M.missingMethods) do missing[#missing + 1] = m end
table.sort(missing)
print("looked up but not on that widget type (nil, as in WoW): " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
os.exit(#failed == 0 and 0 or 1)
