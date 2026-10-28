-- Frame-time benchmark: lua5.1 tests/bench_scan.lua [items] [auctions per item]
-- Reads and saves a full scan on top of 3 weeks of history and reports the slowest frame.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local nItems, per = tonumber(arg[1]) or 10000, tonumber(arg[2]) or 4
M.reset()
local ns = M.LoadAddon("MarketIntel", nil)
M.Tick(1)
local base = M.now
for d = 21, 1, -1 do -- history: one snapshot a day
	for i = 1, nItems do
		local p = 5000 + i * 37
		ns.History.AddSnapshot(tostring(20000 + i), "Item " .. i, 2,
			{ t = base - d * 86400, min = p, mkt = p + 100, qty = 30, auc = 6, sel = 4, wall = 3, full = true })
	end
end
ns.History.Compact(base)
M.Tick(30)
for i = 1, nItems do
	for a = 1, per do
		table.insert(M.auctions, { name = "Item " .. i, id = 20000 + i, count = 5, buyout = (5000 + i * 37 + a * 50) * 5, owner = "S" .. a })
	end
end
local done = false
ns.On("MI_CAPTURE_SAVED", function() done = true end)
collectgarbage("collect") -- start the measurement with a clean heap
M.OpenAH()
QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
local worst, total, frames = 0, 0, 0
for _ = 1, 2000 do
	local t0 = os.clock()
	M.Tick(0.016, 0.016)
	local dt = os.clock() - t0
	worst, total, frames = math.max(worst, dt), total + dt, frames + 1
	if os.getenv("VERBOSE") and dt > 0.015 then print(string.format("  frame %d: %.0f ms (reading=%s)", frames, dt * 1000, tostring(ns.Scanner.status.fullScan))) end
	if done then break end
end
print(string.format("full scan of %d auctions (%d items, 21 days history): %d frames, %.2fs total CPU, slowest frame %.0f ms",
	nItems * per, nItems, frames, total, worst * 1000))
