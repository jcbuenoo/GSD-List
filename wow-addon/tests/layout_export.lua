-- Exports the resolved on-screen layout of every tab as JSON for tests/render_layout.js.
-- Usage (from the wow-addon folder): lua5.1 tests/layout_export.lua <output dir>
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local outDir = assert(arg[1], "output dir required")
local DAY = 86400

M.reset()
local ns = M.LoadAddon("MarketIntel", nil)
M.Tick(1)
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
QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
M.Tick(5)
for i = 1, 6 do ns.Watch.Add(ITEMS[i][1], ITEMS[i][3] * (i % 2 == 0 and 2 or 0.5)) end
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
}
for _, st in ipairs(states) do
	local tab = st[1]:match("^%a+")
	ns.UI.Show(tab)
	if st[2] then st[2]() end
	ns.UI.Refresh(true)
	write("layout-" .. st[1] .. ".json", M.ExportLayout(M.UIParent))
end
assert(#M.errors == 0, "errors: " .. tostring(M.errors[1]))
print("exported " .. #states .. " layouts; deals=" .. #ns.deals)
