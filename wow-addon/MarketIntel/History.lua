-- Market Intel: price history storage, compaction and statistics.
--
-- Per auction house (realm + faction) we keep, for each item key:
--   n = name, q = quality, seen = last time seen
--   s = recent snapshots, one string each: "time:min:market:qty:auctions:sellers:wall:full"
--   d = daily summaries for older days:    "day:min:marketSum:n:qtySum:aucSum:selSum:nFull"
-- Strings keep the SavedVariables file small; they are decoded on demand.
local _, ns = ...

local H = {}
ns.History = H

local format, tonumber, pairs, ipairs, max, min = string.format, tonumber, pairs, ipairs, math.max, math.min
local DAY = 86400
-- decoded snapshot lists, keyed by item table; weak so it never reaches SavedVariables
local rawCache = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
function H.EncodeSnap(s)
	return format("%d:%d:%d:%d:%d:%d:%d:%d", s.t, s.min, s.mkt, s.qty, s.auc, s.sel, s.wall or 0, s.full and 1 or 0)
end

function H.DecodeSnap(str)
	local t, mn, mkt, qty, auc, sel, wall, full = str:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d)$")
	if not t then return nil end
	return {
		t = tonumber(t), min = tonumber(mn), mkt = tonumber(mkt), qty = tonumber(qty),
		auc = tonumber(auc), sel = tonumber(sel), wall = tonumber(wall), full = full == "1",
	}
end

local function EncodeDay(d)
	return format("%d:%d:%d:%d:%d:%d:%d:%d", d.day, d.min, d.mktSum, d.n, d.qtySum, d.aucSum, d.selSum, d.nFull)
end

local function DecodeDay(str)
	local day, mn, mktSum, n, qtySum, aucSum, selSum, nFull = str:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
	if not day then return nil end
	return {
		day = tonumber(day), min = tonumber(mn), mktSum = tonumber(mktSum), n = tonumber(n),
		qtySum = tonumber(qtySum), aucSum = tonumber(aucSum), selSum = tonumber(selSum), nFull = tonumber(nFull),
	}
end

-- Fold a snapshot into a day accumulator. Supply numbers only count complete scans.
local function AddToDay(acc, snap)
	acc.min = acc.min and min(acc.min, snap.min) or snap.min
	acc.mktSum = acc.mktSum + snap.mkt
	acc.n = acc.n + 1
	if snap.full then
		acc.qtySum = acc.qtySum + snap.qty
		acc.aucSum = acc.aucSum + snap.auc
		acc.selSum = acc.selSum + snap.sel
		acc.nFull = acc.nFull + 1
	end
end

local function NewDay(day)
	return { day = day, mktSum = 0, n = 0, qtySum = 0, aucSum = 0, selSum = 0, nFull = 0 }
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
function H.GetItem(key)
	return ns.realm and ns.realm.items[key]
end

function H.AddSnapshot(key, name, quality, snap)
	local items = ns.realm.items
	local item = items[key]
	if not item then
		item = { s = {}, d = {} }
		items[key] = item
	end
	item.n = name or item.n
	item.q = quality or item.q
	item.seen = max(item.seen or 0, snap.t)
	rawCache[item] = nil

	local list = item.s
	local last = list[#list] and H.DecodeSnap(list[#list])
	if last and snap.t >= last.t and snap.t - last.t < ns.settings.replaceWindow
		and ns.DayKey(last.t) == ns.DayKey(snap.t) then
		-- Same scan session (more pages, or a repeat search): replace instead of piling up.
		-- A partial result never overwrites a complete one with smaller numbers.
		if last.full and not snap.full then
			snap.qty, snap.auc, snap.sel, snap.wall, snap.full = last.qty, last.auc, last.sel, last.wall, true
			snap.min = min(snap.min, last.min)
		end
		list[#list] = H.EncodeSnap(snap)
	else
		list[#list + 1] = H.EncodeSnap(snap)
	end
end

-- Move old snapshots into daily summaries and drop data older than keepDays.
function H.Compact(now)
	if not ns.realm then return end
	local rawCutoff = ns.DayKey(now - ns.settings.rawDays * DAY)
	local keepCutoff = ns.DayKey(now - ns.settings.keepDays * DAY)
	for key, item in pairs(ns.realm.items) do
		rawCache[item] = nil
		local keep, folded = {}, {}
		for _, str in ipairs(item.s or {}) do
			local snap = H.DecodeSnap(str)
			if snap then
				local day = ns.DayKey(snap.t)
				if day < rawCutoff then
					folded[day] = folded[day] or NewDay(day)
					AddToDay(folded[day], snap)
				else
					keep[#keep + 1] = str
				end
			end
		end
		item.s = keep
		if next(folded) then
			local byDay = {}
			for _, str in ipairs(item.d or {}) do
				local d = DecodeDay(str)
				if d then byDay[d.day] = d end
			end
			for day, acc in pairs(folded) do
				local d = byDay[day]
				if d then
					d.min = min(d.min, acc.min)
					d.mktSum, d.n = d.mktSum + acc.mktSum, d.n + acc.n
					d.qtySum, d.aucSum, d.selSum, d.nFull = d.qtySum + acc.qtySum, d.aucSum + acc.aucSum, d.selSum + acc.selSum, d.nFull + acc.nFull
				else
					byDay[day] = acc
				end
			end
			local days = {}
			for _, d in pairs(byDay) do days[#days + 1] = d end
			table.sort(days, function(a, b) return a.day < b.day end)
			item.d = {}
			for _, d in ipairs(days) do item.d[#item.d + 1] = EncodeDay(d) end
		end
		local dkeep = {}
		for _, str in ipairs(item.d or {}) do
			local d = DecodeDay(str)
			if d and d.day >= keepCutoff then dkeep[#dkeep + 1] = str end
		end
		item.d = dkeep
		if #item.s == 0 and #item.d == 0 then ns.realm.items[key] = nil end
	end
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function H.GetRaw(item)
	if not item then return {} end
	if rawCache[item] then return rawCache[item] end
	local out = {}
	for _, str in ipairs(item.s or {}) do
		local snap = H.DecodeSnap(str)
		if snap then out[#out + 1] = snap end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	rawCache[item] = out
	return out
end

function H.GetLatest(key)
	local raw = H.GetRaw(H.GetItem(key))
	return raw[#raw]
end

-- Daily series (oldest first): { day, t, min, mkt, qty, auc, sel, hasSupply }
-- sinceDays limits how far back to go; nil means everything.
function H.GetDaily(item, now, sinceDays)
	if not item then return {} end
	now = now or time()
	local cutoff = sinceDays and ns.DayKey(now - sinceDays * DAY) or 0
	local byDay = {}
	for _, str in ipairs(item.d or {}) do
		local d = DecodeDay(str)
		if d and d.day >= cutoff then byDay[d.day] = d end
	end
	for _, snap in ipairs(H.GetRaw(item)) do
		local day = ns.DayKey(snap.t)
		if day >= cutoff then
			-- decoded summaries are fresh tables, so adding to them is safe
			local acc = byDay[day]
			if not acc then
				acc = NewDay(day)
				byDay[day] = acc
			end
			AddToDay(acc, snap)
		end
	end
	local out = {}
	for day, d in pairs(byDay) do
		if d.n > 0 then
			out[#out + 1] = {
				day = day, t = ns.DayToTime(day), min = d.min, mkt = d.mktSum / d.n,
				qty = d.nFull > 0 and d.qtySum / d.nFull or nil,
				auc = d.nFull > 0 and d.aucSum / d.nFull or nil,
				sel = d.nFull > 0 and d.selSum / d.nFull or nil,
			}
		end
	end
	table.sort(out, function(a, b) return a.day < b.day end)
	return out
end

local function Avg(series, field, fromDay)
	local sum, n = 0, 0
	for _, d in ipairs(series) do
		if d.day >= fromDay and d[field] then
			sum, n = sum + d[field], n + 1
		end
	end
	return n > 0 and sum / n or nil
end

-- Summary statistics for tooltips and the History tab.
function H.GetStats(key, now)
	local item = H.GetItem(key)
	if not item then return nil end
	now = now or time()
	local series = H.GetDaily(item, now, 30)
	local latest = H.GetLatest(key)
	local stats = { latest = latest, days = #series, series = series }
	local d7, d30 = ns.DayKey(now - 7 * DAY), ns.DayKey(now - 30 * DAY)
	stats.avg7 = Avg(series, "mkt", d7)
	stats.avg30 = Avg(series, "mkt", d30)
	for _, d in ipairs(series) do
		stats.low30 = stats.low30 and min(stats.low30, d.min) or d.min
		stats.high30 = stats.high30 and max(stats.high30, d.mkt) or d.mkt
	end
	if latest and stats.avg7 and stats.avg7 > 0 then
		stats.change7 = latest.mkt / stats.avg7 - 1
	end
	-- volatility: average absolute day-to-day move of the market value
	if #series >= 3 then
		local moves, sum = 0, 0
		for i = 2, #series do
			if series[i - 1].mkt > 0 then
				sum = sum + math.abs(series[i].mkt / series[i - 1].mkt - 1)
				moves = moves + 1
			end
		end
		stats.volatility = moves > 0 and sum / moves or nil
	end
	return stats
end

-- Normal (reference) price used for deal detection: the median of daily
-- market values over the last 14 days, excluding today so a fresh crash or
-- a single cheap listing cannot drag it down.
function H.GetReference(key, now)
	now = now or time()
	local item = H.GetItem(key)
	local today = ns.DayKey(now)
	if item then
		local values = {}
		for _, d in ipairs(H.GetDaily(item, now, 14)) do
			if d.day ~= today then values[#values + 1] = d.mkt end
		end
		if #values >= ns.settings.minHistoryDays then
			return ns.Median(values), "history"
		end
	end
	if ns.settings.useTSMFallback then
		local tsm = ns.Integrations.GetTSMPrice(key)
		if tsm and tsm > 0 then return tsm, "TSM" end
	end
	return nil
end

-- Typical supply (median auctions-on-AH quantity per day, excluding today).
function H.GetNormalSupply(key, now)
	now = now or time()
	local item = H.GetItem(key)
	if not item then return nil end
	local today = ns.DayKey(now)
	local values = {}
	for _, d in ipairs(H.GetDaily(item, now, 14)) do
		if d.day ~= today and d.qty then values[#values + 1] = d.qty end
	end
	if #values < 3 then return nil end
	return ns.Median(values)
end

-- Average market value per weekday relative to the overall average.
-- Returns ratios[1..7] (1 = Sunday) and the number of days used.
function H.GetWeekdayProfile(key, now)
	local series = H.GetDaily(H.GetItem(key), now, 90)
	if #series < 14 then return nil, #series end
	local overall = 0
	for _, d in ipairs(series) do overall = overall + d.mkt end
	overall = overall / #series
	if overall <= 0 then return nil, #series end
	local sum, cnt = {}, {}
	for _, d in ipairs(series) do
		local wd = tonumber(date("%w", d.t)) + 1
		sum[wd] = (sum[wd] or 0) + d.mkt
		cnt[wd] = (cnt[wd] or 0) + 1
	end
	local ratios = {}
	for wd = 1, 7 do
		if cnt[wd] then ratios[wd] = (sum[wd] / cnt[wd]) / overall end
	end
	return ratios, #series
end

function H.CountData()
	local items, snaps, days = 0, 0, 0
	for _, item in pairs(ns.realm and ns.realm.items or {}) do
		items = items + 1
		snaps = snaps + #(item.s or {})
		days = days + #(item.d or {})
	end
	return items, snaps, days
end

-- Find item keys whose name contains the (lowercase) search text.
function H.Search(text, limit)
	text = (text or ""):lower()
	local out = {}
	for key, item in pairs(ns.realm and ns.realm.items or {}) do
		if item.n and (text == "" or item.n:lower():find(text, 1, true)) then
			out[#out + 1] = key
		end
	end
	table.sort(out, function(a, b)
		local ia, ib = ns.realm.items[a], ns.realm.items[b]
		if (ia.seen or 0) ~= (ib.seen or 0) then return (ia.seen or 0) > (ib.seen or 0) end
		return ia.n < ib.n
	end)
	if limit and #out > limit then
		for i = #out, limit + 1, -1 do out[i] = nil end
	end
	return out
end

-- Find a stored key by exact (case-insensitive) item name.
function H.FindKeyByName(name)
	if not name then return nil end
	name = name:lower()
	local best, bestSeen
	for key, item in pairs(ns.realm and ns.realm.items or {}) do
		if item.n and item.n:lower() == name and (item.seen or 0) > (bestSeen or -1) then
			best, bestSeen = key, item.seen or 0
		end
	end
	return best
end
