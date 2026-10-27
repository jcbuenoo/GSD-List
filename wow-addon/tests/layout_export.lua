-- Exports the resolved on-screen layout of every tab as JSON for tests/render_layout.js.
-- Usage (from the wow-addon folder): lua5.1 tests/layout_export.lua <output dir>
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local outDir = assert(arg[1], "output dir required")
local DAY = 86400

M.reset()
local ns = M.LoadAddon("MarketIntel", nil)
M.Tick(1)
-- TSM with region data, starred recipes, gear item info
_G.TradeSkillMasterDB = { ["c@Tester - Dreamscythe@internalData@favoriteCrafts"] = { ["c:31080"] = true, ["c:28903"] = true, ["c:26751"] = true } }
local GEAR = {
	{ "Thunderfury Replica of the Monkey", 31001, 9000000, 42, 4 }, { "Ring of Twinking Power", 31002, 2600000, 19, 3 },
	{ "Stormshroud Pants", 31003, 4400000, 50, 3 }, { "Blackened Defias Belt", 31004, 800000, 29, 3 },
}
for _, g in ipairs(GEAR) do M.itemInfo[g[2]] = { name = g[1], equipLoc = "INVTYPE_WEAPON" } end
_G.TSM_API = { GetCustomPriceValue = function(source, item)
	local id = tonumber(item:match("i:(%d+)"))
	for _, g in ipairs(GEAR) do
		if g[2] == id then
			if source == "dbmarket" then return g[3] end
			if source == "dbregionsoldperday" then return 0.25 + (id % 3) / 10 end
		end
	end
	return nil
end }
M.tradeskill = { line = "Jewelcrafting", recipes = {
	{ name = "Bold Living Ruby", spell = 31080, item = { id = 23436, name = "Living Ruby" }, reagents = { { id = 23436, name = "Living Ruby", count = 1 } } },
	{ name = "Runed Living Ruby", spell = 28903, item = { id = 22445, name = "Arcane Dust" }, reagents = { { id = 23436, name = "Living Ruby", count = 1 } } },
	{ name = "Bolt of Imbued Netherweave", spell = 26751, item = { id = 21843, name = "Bolt of Imbued Netherweave" },
		reagents = { { id = 21877, name = "Netherweave Cloth", count = 6 }, { id = 22445, name = "Arcane Dust", count = 2 } } },
	{ name = "Not Starred Recipe", spell = 99999, item = { id = 22832, name = "Super Mana Potion" }, reagents = { { id = 22794, name = "Fel Lotus", count = 1 } } },
} }
M.FireEvent("TRADE_SKILL_SHOW"); M.Tick(1)
M.OpenAH()

-- realistic data: long names, big prices, many sellers
local ITEMS = {
	{ "Flask of Relentless Assault", 22854, 380000 }, { "Felsteel Longblade of the Bear", 24689, 12345678, 1201, 2 },
	{ "Primal Might", 23571, 1150000 }, { "Khorium Ore", 23426, 210000 }, { "Mercurial Adamantite", 23573, 95000 },
	{ "Enchant Weapon - Mongoose", 22559, 9990000 }, { "Netherweave Cloth", 21877, 2500 }, { "Super Mana Potion", 22832, 41000 },
	{ "Formula: Enchant Weapon - Major Spellpower", 28281, 4200000 }, { "Bolt of Imbued Netherweave", 21843, 160000 },
	{ "Adamantite Ore", 23425, 18000 }, { "Fel Lotus", 22794, 520000 }, { "Living Ruby", 23436, 2650000 },
	{ "Arcane Dust", 22445, 21000 }, { "Large Prismatic Shard", 22449, 480000 }, { "Void Crystal", 22450, 1890000 },
}
for d = 20, 1, -1 do
	M.now = M.now - d * DAY
	M.auctions = {}
	for _, it in ipairs(ITEMS) do
		local wobble = 1 + ((d * 7 + it[2]) % 11 - 5) / 40
		for a = 1, 6 do
			table.insert(M.auctions, { name = it[1], id = it[2], count = 1, buyout = math.floor(it[3] * wobble) + a * 100,
				owner = "Seller" .. a, suffix = it[4], quality = it[5] or 1 })
		end
	end
	QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
	M.Tick(3)
	M.Tick(900)
	M.now = M.now + d * DAY
end
-- today: flooded markets and some deals
M.auctions = {}
for i, it in ipairs(ITEMS) do
	local sellers = i % 3 == 0 and 18 or (i % 3 == 1 and 9 or 2)
	for a = 1, sellers do
		table.insert(M.auctions, { name = it[1], id = it[2], count = 20, buyout = (it[3] + a * 500) * 20,
			owner = "LongSellerName" .. a, suffix = it[4], quality = it[5] or 1 })
	end
	if i % 2 == 0 then
		table.insert(M.auctions, { name = it[1], id = it[2], count = 200, buyout = math.floor(it[3] * 0.4) * 200,
			owner = "Bargainhunterx", suffix = it[4], quality = it[5] or 1 })
	end
end
for i, g in ipairs(GEAR) do
	for a = 1, 3 do
		table.insert(M.auctions, { name = g[1], id = g[2], count = 1, buyout = math.floor(g[3] * (a == 1 and 0.5 + i / 50 or 1.05)),
			owner = "Gearseller" .. a, quality = g[5], level = g[4] })
	end
end
QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
M.Tick(5)
for i = 1, 6 do ns.Watch.Add(ITEMS[i][1], ITEMS[i][3] * (i % 2 == 0 and 2 or 0.5)) end
-- flips: a few cheap auctions under a normal wall, searched directly
for _, it in ipairs({ ITEMS[3], ITEMS[13], ITEMS[16] }) do
	M.auctions = {}
	for a = 1, 3 do table.insert(M.auctions, { name = it[1], id = it[2], count = 1, buyout = math.floor(it[3] * 0.55), owner = "Dumper" .. a }) end
	for a = 1, 8 do table.insert(M.auctions, { name = it[1], id = it[2], count = 1, buyout = math.floor(it[3] * 0.99), owner = "Wall" .. a }) end
	QueryAuctionItems(it[1], nil, nil, 0, false, nil, false, false)
	M.Tick(3)
end
-- ledger mail
M.CloseAH()
M.mail = {}
for i = 1, 14 do
	local it = ITEMS[i]
	local kinds = { "sold", "sold", "expired", "bought", "sold", "cancelled" }
	local kind = kinds[i % #kinds + 1]
	local subject = ({ sold = "Auction successful: ", expired = "Auction expired: ", bought = "Auction won: ", cancelled = "Auction cancelled: " })[kind] .. it[1]
	local m = { subject = subject, daysLeft = 30 - i * 0.7, money = it[3] }
	if kind == "sold" then m.invoice = { type = "seller", item = it[1], player = "Buyer" .. i, bid = it[3] * 5, buyout = it[3] * 5, deposit = 0, cut = math.floor(it[3] * 0.25) }
	elseif kind == "bought" then m.invoice = { type = "buyer", item = it[1], player = "Seller" .. i, bid = it[3] * 2, buyout = it[3] * 2 }; m.item = { name = it[1], id = it[2], count = 2 }
	else m.item = { name = it[1], id = it[2], count = 5 } end
	M.mail[#M.mail + 1] = m
end
M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
M.OpenAH()
ns.Watch.Add("Some Item Nobody Has Posted Yet")

local function write(name, data)
	local f = assert(io.open(outDir .. "/" .. name, "w"))
	f:write(data)
	f:close()
end

ns.UI.Show("deals")
local states = {
	{ "deals" }, { "depth" }, { "history", function() ns.UI.ShowHistory(ns.History.FindKeyByName("Primal Might")) end },
	{ "history-empty", function() ns.UI.Show("history"); ns.UI.GetPage("history"):Select(nil) end },
	{ "watch", function() ns.Scanner.ScanWatchlist() end }, { "settings" },
	{ "snipe" }, { "flips" }, { "crafting" }, { "ledger" },
	{ "export", function() ns.UI.Show("deals"); ns.Scanner.StopScan(true); M.Tick(1)
		for _, c in ipairs(ns.UI.GetPage("deals")._children) do if c._kind == "Button" and c:GetText() == "CSV" then c:Click() end end end },
}
for _, st in ipairs(states) do
	local tab = st[1]:match("^%a+")
	if tab ~= "export" then ns.UI.Show(tab) end
	if ns.Export.GetFrame() then ns.Export.GetFrame():Hide() end
	if st[2] then st[2]() end
	ns.UI.Refresh(true)
	write("layout-" .. st[1] .. ".json", M.ExportLayout(M.UIParent))
end
assert(#M.errors == 0, "errors: " .. tostring(M.errors[1]))
print(string.format("exported %d layouts; deals=%d snipes=%d flips=%d ledger=%d", #states, #ns.deals, #ns.snipes,
	#ns.Advisor.FindFlips(time()), #ns.Ledger.Entries()))
