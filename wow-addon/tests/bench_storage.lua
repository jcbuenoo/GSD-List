-- Storage benchmark: lua5.1 tests/bench_storage.lua <addon dir> [items] [days]
-- Simulates a big server: every item seen in 3 full scans a day, compacted at each login.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local dir, nItems, nDays = arg[1] or "MarketIntel", tonumber(arg[2]) or 10000, tonumber(arg[3]) or 30
M.reset()
local ns = M.LoadAddon(dir, nil)
M.Tick(1)
if arg[4] == "oldsettings" then -- the first version's retention, for a like-for-like size comparison
	ns.settings.rawDays, ns.settings.keepDays, ns.settings.scanKeepDays, ns.settings.replaceWindow = 3, 90, 90, 600
end
local base = M.now
local t0 = os.clock()
for d = nDays, 1, -1 do
	ns.History.Compact(base - d * 86400 + 3600) -- daily login
	for _, hour in ipairs({ 10, 15, 21 }) do
		local t = base - d * 86400 + (hour - 12) * 3600
		for i = 1, nItems do
			local price = 5000 + i * 37 + (d * 131 + hour * 7) % 900
			ns.History.AddSnapshot(tostring(20000 + i), "Item number " .. i, 2,
				{ t = t, min = price, mkt = price + 120, qty = 20 + i % 50, auc = 4 + i % 9, sel = 2 + i % 6, wall = 5, full = true })
		end
	end
end
ns.History.Compact(base)
M.Tick(30) -- let async compaction (new version) finish
local items, snaps, days = ns.History.CountData()
local bytes = M.WoWSavedSize(MarketIntelDB)
print(string.format("%s: %d items, %d days -> %.1f MB SavedVariables (%d bytes/item), %d snapshots, %d daily rows, %.1fs CPU",
	dir, items, nDays, bytes / 1048576, bytes / items, snaps, days, os.clock() - t0))
