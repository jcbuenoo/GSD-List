-- Market Intel: price history storage, compaction and statistics.
--
-- Per auction house (realm + faction) we keep, for each item key:
--   n = name, q = quality, seen = last time seen, f = 1 if you searched it directly (kept longer)
--   s = recent snapshots, one string:  "t,min,mkt,qty,auc,sel,wall,full;t,min,..."
--   d = daily summaries, one string:   "day,min,mkt,qty,auc,sel,n;day,..."
-- Numbers are hexadecimal and each item holds just two strings, which keeps the
-- SavedVariables file small. Everything is decoded on demand and cached.
local _, ns = ...

local H = {}
ns.History = H

local floor, tonumber, pairs, ipairs, max, min, concat, format = math.floor, tonumber, pairs, ipairs, math.max, math.min, table.concat, string.format
local DAY = 86400

-- Decoded data, keyed by item table. Weak, so it never reaches SavedVariables.
local rawCache = setmetatable({}, { __mode = "k" })
local dayCache = setmetatable({}, { __mode = "k" })
local seriesCache = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
-- Optional numbers are written as "" when missing.
local function Hex(n)
	if not n then return "" end
	return format("%x", max(0, floor(n + 0.5)))
end

local function Num(s)
	if s == "" then return nil end
	return tonumber(s, 16)
end

local function EncodeSnap(s)
	return format("%x,%x,%x,%x,%x,%x,%x,%d", s.t, max(0, floor(s.min + 0.5)), max(0, floor(s.mkt + 0.5)),
		s.qty, s.auc, s.sel, s.wall or 0, s.full and 1 or 0)
end

local function EncodeRaw(list)
	local parts = {}
	for i, s in ipairs(list) do parts[i] = EncodeSnap(s) end
	return concat(parts, ";")
end

local function DecodeRaw(str)
	local out = {}
	for t, mn, mkt, qty, auc, sel, wall, full in (str or ""):gmatch("(%w+),(%w+),(%w+),(%w+),(%w+),(%w+),(%w+),([01])") do
		out[#out + 1] = {
			t = Num(t), min = Num(mn), mkt = Num(mkt), qty = Num(qty), auc = Num(auc),
			sel = Num(sel), wall = Num(wall), full = full == "1",
		}
	end
	return out
end

-- Daily entries: supply fields (qty, auc, sel) are nil when no complete scan was seen that day.
local function EncodeDays(list)
	local parts = {}
	for i, d in ipairs(list) do
		parts[i] = concat({ Hex(d.day), Hex(d.min), Hex(d.mkt), Hex(d.qty), Hex(d.auc), Hex(d.sel), Hex(d.n) }, ",")
	end
	return concat(parts, ";")
end

local function DecodeDays(str)
	local out = {}
	for day, mn, mkt, qty, auc, sel, n in (str or ""):gmatch("(%w+),(%w+),(%w+),(%w*),(%w*),(%w*),(%w+)") do
		out[#out + 1] = { day = Num(day), min = Num(mn), mkt = Num(mkt), qty = Num(qty), auc = Num(auc), sel = Num(sel), n = Num(n) }
	end
	return out
end

-- Average a list of snapshots into one daily entry.
local function SummarizeDay(day, snaps)
	local d = { day = day, n = #snaps }
	local mktSum, qty, auc, sel, nFull = 0, 0, 0, 0, 0
	for _, s in ipairs(snaps) do
		d.min = d.min and min(d.min, s.min) or s.min
		mktSum = mktSum + s.mkt
		if s.full then
			qty, auc, sel, nFull = qty + s.qty, auc + s.auc, sel + s.sel, nFull + 1
		end
	end
	d.mkt = mktSum / #snaps
	if nFull > 0 then d.qty, d.auc, d.sel = qty / nFull, auc / nFull, sel / nFull end
	return d
end

-- Merge two summaries of the same day, weighted by how many snapshots each holds.
local function MergeDay(a, b)
	local n = a.n + b.n
	local function avg(x, y)
		if x and y then return (x * a.n + y * b.n) / n end
		return x or y
	end
	return { day = a.day, n = n, min = min(a.min, b.min), mkt = avg(a.mkt, b.mkt), qty = avg(a.qty, b.qty), auc = avg(a.auc, b.auc), sel = avg(a.sel, b.sel) }
end

local dayTimes = {}
local function DayTime(day)
	local t = dayTimes[day]
	if not t then
		t = ns.DayToTime(day)
		dayTimes[day] = t
	end
	return t
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function H.GetItem(key)
	return ns.realm and ns.realm.items[key]
end

-- Snapshots, oldest first. The returned list is shared: do not modify it.
function H.GetRaw(item)
	if not item then return {} end
	local raw = rawCache[item]
	if not raw then
		raw = DecodeRaw(item.s)
		table.sort(raw, function(a, b) return a.t < b.t end)
		rawCache[item] = raw
	end
	return raw
end

local function GetDays(item)
	local days = dayCache[item]
	if not days then
		days = DecodeDays(item.d)
		dayCache[item] = days
	end
	return days
end

function H.GetLatest(key)
	local raw = H.GetRaw(H.GetItem(key))
	return raw[#raw]
end

local function Invalidate(item)
	rawCache[item], dayCache[item], seriesCache[item] = nil, nil, nil
end

-- Daily series, oldest first: { day, t, min, mkt, qty, auc, sel }.
-- sinceDays limits how far back to go (nil = everything). The result is cached
-- and shared: do not modify it.
function H.GetDaily(item, now, sinceDays)
	if not item then return {} end
	now = now or time()
	local today = ns.DayKey(now)
	local cacheKey = (sinceDays or "all") .. ":" .. today
	local cache = seriesCache[item]
	if cache and cache[cacheKey] then return cache[cacheKey] end

	local cutoff = sinceDays and ns.DayKey(now - sinceDays * DAY) or 0
	local byDay, order = {}, {}
	for _, d in ipairs(GetDays(item)) do
		if d.day >= cutoff then
			byDay[d.day] = d
			order[#order + 1] = d.day
		end
	end
	local rawByDay = {}
	for _, s in ipairs(H.GetRaw(item)) do
		local day = ns.DayKey(s.t)
		if day >= cutoff then
			if not rawByDay[day] then
				rawByDay[day] = {}
				if not byDay[day] then order[#order + 1] = day end
			end
			table.insert(rawByDay[day], s)
		end
	end
	table.sort(order)
	local out = {}
	for _, day in ipairs(order) do
		local d = byDay[day]
		if rawByDay[day] then
			local fresh = SummarizeDay(day, rawByDay[day])
			d = d and MergeDay(d, fresh) or fresh
		end
		out[#out + 1] = { day = day, t = DayTime(day), min = d.min, mkt = d.mkt, qty = d.qty, auc = d.auc, sel = d.sel }
	end
	cache = cache or {}
	cache[cacheKey] = out
	seriesCache[item] = cache
	return out
end

---------------------------------------------------------------------------
-- Name index (lowercase name -> most recently seen key)
---------------------------------------------------------------------------
local nameIndex, nameIndexOwner

local function NameIndex()
	local items = ns.realm and ns.realm.items
	if nameIndexOwner ~= items then
		nameIndex, nameIndexOwner = {}, items
		for key, item in pairs(items or {}) do
			if item.n then
				local lower = item.n:lower()
				local cur = nameIndex[lower]
				if not cur or (items[cur].seen or 0) < (item.seen or 0) then nameIndex[lower] = key end
			end
		end
	end
	return nameIndex
end

function H.FindKeyByName(name)
	if not name then return nil end
	return NameIndex()[name:lower()]
end

function H.ResetIndex()
	nameIndexOwner = nil
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
-- focus: the item was searched directly (not just seen in a full scan), so keep its history longer.
function H.AddSnapshot(key, name, quality, snap, focus)
	local items = ns.realm.items
	local item = items[key]
	if not item then
		item = { s = "", d = "" }
		items[key] = item
	end
	if name and item.n ~= name then
		item.n = name
		if nameIndexOwner == items then nameIndex[name:lower()] = key end
	end
	item.q = quality or item.q
	item.seen = max(item.seen or 0, snap.t)
	if focus then item.f = 1 end

	local raw = H.GetRaw(item)
	local last = raw[#raw]
	if last and snap.t >= last.t and snap.t - last.t < ns.settings.replaceWindow
		and ns.DayKey(last.t) == ns.DayKey(snap.t) then
		-- Same scan session (more pages, or a repeat search): replace instead of piling up.
		-- A partial result never overwrites a complete one with smaller numbers.
		if last.full and not snap.full then
			snap.qty, snap.auc, snap.sel, snap.wall, snap.full = last.qty, last.auc, last.sel, last.wall, true
			snap.min = min(snap.min, last.min)
		end
		raw[#raw] = snap
		item.s = (item.s:match("^(.*);[^;]*$") or "") -- drop the last entry...
		item.s = item.s == "" and EncodeSnap(snap) or (item.s .. ";" .. EncodeSnap(snap)) -- ...and write the new one
	elseif last and snap.t < last.t then
		raw[#raw + 1] = snap
		table.sort(raw, function(a, b) return a.t < b.t end)
		item.s = EncodeRaw(raw)
	else
		raw[#raw + 1] = snap
		item.s = item.s == "" and EncodeSnap(snap) or (item.s .. ";" .. EncodeSnap(snap))
	end
	seriesCache[item] = nil
end

-- Add whole days of history from another source (the Auctionator import).
-- Days we already have are left alone; ours are more detailed. Returns days added.
function H.ImportDays(key, newDays, focus)
	local items = ns.realm.items
	local item = items[key]
	if not item then
		item = { s = "", d = "" }
		items[key] = item
	end
	local have = {}
	for _, d in ipairs(GetDays(item)) do have[d.day] = true end
	for _, s in ipairs(H.GetRaw(item)) do have[ns.DayKey(s.t)] = true end
	local days, added = GetDays(item), 0
	for _, d in ipairs(newDays) do
		if not have[d.day] then
			days[#days + 1] = d
			have[d.day] = true
			added = added + 1
			item.seen = max(item.seen or 0, DayTime(d.day))
		end
	end
	if added > 0 then
		table.sort(days, function(a, b) return a.day < b.day end)
		item.d = EncodeDays(days)
		seriesCache[item] = nil
		if focus then item.f = 1 end
	end
	if item.s == "" and item.d == "" then items[key] = nil end
	return added
end

-- Compact one item: fold old snapshots into daily summaries and drop expired days.
-- Returns false if the item has no data left.
local function CompactItem(item, rawCutoff, keepCutoff, scanCutoff)
	local raw = H.GetRaw(item)
	local days = GetDays(item)
	local cutoff = item.f and keepCutoff or scanCutoff
	local changed = false

	if raw[1] and ns.DayKey(raw[1].t) < rawCutoff then
		local keep, fold, foldOrder = {}, {}, {}
		for _, s in ipairs(raw) do
			local day = ns.DayKey(s.t)
			if day < rawCutoff then
				if not fold[day] then
					fold[day] = {}
					foldOrder[#foldOrder + 1] = day
				end
				table.insert(fold[day], s)
			else
				keep[#keep + 1] = s
			end
		end
		local byDay = {}
		for _, d in ipairs(days) do byDay[d.day] = d end
		for _, day in ipairs(foldOrder) do
			local summary = SummarizeDay(day, fold[day])
			if byDay[day] then
				for i, d in ipairs(days) do
					if d.day == day then days[i] = MergeDay(d, summary) end
				end
			else
				days[#days + 1] = summary
			end
		end
		table.sort(days, function(a, b) return a.day < b.day end)
		item.s = EncodeRaw(keep)
		changed = true
	end

	if days[1] and days[1].day < cutoff then
		local keep = {}
		for _, d in ipairs(days) do
			if d.day >= cutoff then keep[#keep + 1] = d end
		end
		days = keep
		changed = true
	end
	if changed then
		item.d = EncodeDays(days)
		Invalidate(item)
	end
	return item.s ~= "" or item.d ~= ""
end

-- Fold old snapshots into daily summaries and drop data past its retention.
-- Searched/watched items keep keepDays of history; items only ever seen in full
-- scans keep scanKeepDays. With async = true the work is spread over frames.
function H.Compact(now, async)
	if not ns.realm then return end
	local s = ns.settings
	local rawCutoff = ns.DayKey(now - s.rawDays * DAY)
	local keepCutoff = ns.DayKey(now - s.keepDays * DAY)
	local scanCutoff = ns.DayKey(now - max(s.scanKeepDays, s.minHistoryDays + 1) * DAY)
	local items = ns.realm.items
	-- watched items always count as searched
	for _, w in pairs(ns.db.watch) do
		local key = H.FindKeyByName(w.name)
		if key then items[key].f = 1 end
	end
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local i = 1
	local function step(limit)
		local stop = min(#keys, i + limit - 1)
		for j = i, stop do
			local item = items[keys[j]]
			if item and not CompactItem(item, rawCutoff, keepCutoff, scanCutoff) then
				items[keys[j]] = nil
			end
		end
		i = stop + 1
		if i > #keys then
			H.ResetIndex()
			return true
		end
	end
	if async then
		ns.RunTask(function() return step(500) end)
	else
		step(#keys)
	end
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------
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
	stats.avg7 = Avg(series, "mkt", ns.DayKey(now - 7 * DAY))
	stats.avg30 = Avg(series, "mkt", ns.DayKey(now - 30 * DAY))
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
	if item then
		local today = ns.DayKey(now)
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

-- Typical supply (median units on the AH per day, excluding today).
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
		if item.s ~= "" then snaps = snaps + select(2, item.s:gsub(";", "")) + 1 end
		if item.d ~= "" then days = days + select(2, item.d:gsub(";", "")) + 1 end
	end
	return items, snaps, days
end

-- Display name for a key, even for imported items we have not seen yet.
function H.GetName(key)
	local item = H.GetItem(key)
	if item and item.n then return item.n end
	local name = GetItemInfo(ns.ItemStringFromKey(key) or 0)
	if name and item then item.n = name end
	return name
end

-- Find item keys whose name contains the (lowercase) search text, most recently seen first.
function H.Search(text, limit)
	text = (text or ""):lower()
	local items = ns.realm and ns.realm.items or {}
	local out = {}
	for key, item in pairs(items) do
		local name = item.n or H.GetName(key)
		if name and (text == "" or name:lower():find(text, 1, true)) then
			out[#out + 1] = key
		end
	end
	table.sort(out, function(a, b)
		local ia, ib = items[a], items[b]
		if (ia.seen or 0) ~= (ib.seen or 0) then return (ia.seen or 0) > (ib.seen or 0) end
		return (ia.n or "") < (ib.n or "")
	end)
	if limit and #out > limit then
		for i = #out, limit + 1, -1 do out[i] = nil end
	end
	return out
end
