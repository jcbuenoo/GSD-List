-- Market Intel: reads auction house results.
--
-- Passive capture: every search made by you, Auctionator, TSM or the default UI
-- (including Auctionator's full scan) is read from the results list and turned
-- into price snapshots. Pages of the same search are merged before saving.
-- Active scans: the watchlist scan (/mi scan) and the BoE snipe scan (/mi snipe)
-- send a list of searches, page by page, at the speed the auction house allows.
local _, ns = ...

local S = {}
ns.Scanner = S
ns.current = {} -- this session's detail per item key: price levels, own listings, cheap stock

local ipairs, pairs = ipairs, pairs
local PAGE_SIZE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local IDLE_COMMIT = 2       -- seconds after the last result update before saving
local MISSING_TOLERANCE = 0.01

local ahOpen = false
local queryCount = 0    -- QueryAuctionItems calls seen; tells re-fired events from new results
local capture           -- results of the current search
local commitTimer

function S.IsAuctionHouseOpen() return ahOpen end

local function NewCapture(qkey, getAll)
	return { qkey = qkey, getAll = getAll, pages = {}, page = 0 }
end

---------------------------------------------------------------------------
-- Reading rows
---------------------------------------------------------------------------
-- Returns a listing table, false for rows we deliberately skip, or nil if the row is not loaded yet.
local function ReadRow(i)
	local name, _, count, quality, _, level, _, _, _, buyout, _, _, _, owner, _, _, itemId = GetAuctionItemInfo("list", i)
	-- the client returns "" (not nil) for items it has not loaded yet: read them again later
	if not name or name == "" or not itemId then return nil end
	if not buyout or buyout <= 0 or not count or count <= 0 then return false end -- bid-only
	if (quality or 0) < ns.settings.minQuality then return false end
	local key = ns.ItemKeyFromLink(GetAuctionItemLink("list", i)) or tostring(itemId)
	return {
		key = key, name = name, quality = quality, count = count, buyout = buyout, level = level, itemId = itemId,
		unit = buyout / count, owner = owner, mine = owner ~= nil and (owner == ns.playerName or owner == ns.playerFullName),
	}
end

local function ReadPage(batch)
	local page = { rows = {}, seen = 0, missing = 0 }
	for i = 1, batch do
		local row = ReadRow(i)
		if row == nil then
			page.missing = page.missing + 1
		else
			page.seen = page.seen + 1
			if row then page.rows[#page.rows + 1] = row end
		end
	end
	return page
end

---------------------------------------------------------------------------
-- Saving a capture
---------------------------------------------------------------------------
local function ScheduleCommit()
	ns.Cancel(commitTimer)
	commitTimer = ns.After(IDLE_COMMIT, function() S.Commit(capture) end)
end

local function CommitItem(key, listings, full, now, newDeals, focus, newSnipes)
	local first = listings[1]
	local snap = ns.Analysis.BuildSnapshot(listings, full, now) -- sorts listings by unit price
	local ref = ns.History.GetReference(key, now)
	local watch = ns.Watch.Get(first.name)
	-- BoE snipes first: an auction that is a snipe is reported only as a snipe, not also as a deal
	local sniped = ns.Snipe.Check(key, listings, now, newSnipes)
	for _, deal in ipairs(ns.Analysis.FindDeals(key, listings, ref, watch and watch.max)) do
		if not sniped[ns.Analysis.DealId(key, deal)] then
			if ns.Analysis.AddDeal(deal, first.name, now) then newDeals[#newDeals + 1] = deal end
		end
	end
	if full then
		ns.Analysis.PruneDeals(key, listings)
		ns.Snipe.Prune(key, listings)
	end

	local mine, cheapQty, cheapCost = 0, 0, 0
	for _, l in ipairs(listings) do
		if l.mine then mine = mine + l.count end
		if ref and l.unit < ref * 0.9 and not l.mine then
			cheapQty = cheapQty + l.count
			cheapCost = cheapCost + l.buyout
		end
	end
	local levels = ns.Analysis.BuildLadder(listings, 40, true)
	ns.current[key] = {
		t = now, ladder = { levels[1], levels[2], levels[3], levels[4], levels[5] }, levels = levels, mine = mine,
		cheapQty = cheapQty, cheapCost = cheapCost, ref = ref, full = full,
	}
	ns.History.AddSnapshot(key, first.name, first.quality, snap, focus)
end

-- Save the merged pages of a capture. Small searches are saved at once; big
-- ones (full scans) run as a background job within a per-frame time budget.
local SYNC_ROWS = 1000

local function SaveCapture(cap, yield)
	local seen, missing, byKey, keys = 0, 0, {}, {}
	for _, page in pairs(cap.pages) do
		seen, missing = seen + page.seen, missing + page.missing
		for i, row in ipairs(page.rows) do
			local list = byKey[row.key]
			if not list then
				list = {}
				byKey[row.key] = list
				keys[#keys + 1] = row.key
			end
			list[#list + 1] = row
			if i % 500 == 0 then ns.Checkpoint(yield) end
		end
	end
	if #keys == 0 then return end
	local total = cap.total or seen
	local full = not cap.aborted and seen + missing >= total and missing <= total * MISSING_TOLERANCE
	local now = cap.updatedAt or time() -- when the results arrived, not when we save them
	local newDeals, newSnipes = {}, {}
	for i, key in ipairs(keys) do
		CommitItem(key, byKey[key], full, now, newDeals, not cap.getAll, newSnipes)
		if i % 20 == 0 then ns.Checkpoint(yield) end
	end
	-- snipes first: if both fire at once, the on-screen alert goes to the snipe
	ns.Snipe.Alert(newSnipes)
	ns.Analysis.Alert(newDeals)
	ns.Fire("MI_DATA_UPDATED")
	ns.Fire("MI_CAPTURE_SAVED", #keys, full, cap.getAll)
end

function S.Commit(cap)
	if not cap or cap.committing or not cap.dirty then return end
	ns.Cancel(commitTimer)
	cap.dirty = false
	local rows = 0
	for _, page in pairs(cap.pages) do rows = rows + #page.rows end
	if rows <= SYNC_ROWS then return SaveCapture(cap) end
	cap.committing = true
	ns.RunJob(function(yield) SaveCapture(cap, yield) end, function() cap.committing = nil end)
end

---------------------------------------------------------------------------
-- Full scan (getAll): read thousands of rows over several frames
---------------------------------------------------------------------------
local function ReadFullScan(cap, batch)
	cap.processing = true
	cap.updatedAt = time()
	cap.total = batch
	local rows, seen, missingIdx = {}, 0, {}
	local i, retries, waitUntil = 1, 0, nil
	local status = S.status
	status.fullScan = true
	ns.RunTask(function()
		if not ahOpen then
			cap.aborted = true
		end
		if cap.aborted then
			missingIdx = {}
		elseif waitUntil then
			if GetTime() < waitUntil then return false end
			waitUntil = nil
			-- retry rows whose item info was not cached yet
			local still = {}
			for _, idx in ipairs(missingIdx) do
				local row = ReadRow(idx)
				if row == nil then still[#still + 1] = idx
				else
					seen = seen + 1
					if row then rows[#rows + 1] = row end
				end
			end
			missingIdx = still
			retries = retries + 1
		elseif i <= batch then
			ns.StartFrameBudget()
			repeat
				local stop = math.min(i + 99, batch)
				for idx = i, stop do
					local row = ReadRow(idx)
					if row == nil then missingIdx[#missingIdx + 1] = idx
					else
						seen = seen + 1
						if row then rows[#rows + 1] = row end
					end
				end
				i = stop + 1
			until i > batch or ns.OverBudget()
			status.fullScanProgress = (i - 1) / batch
			ns.Fire("MI_SCAN_PROGRESS")
			return false
		end
		if not cap.aborted and #missingIdx > 0 and retries < 3 then
			waitUntil = GetTime() + 1.5
			return false
		end
		cap.pages[0] = { rows = rows, seen = seen, missing = #missingIdx }
		cap.dirty, cap.updatedAt = true, cap.updatedAt or time()
		cap.processing = nil
		S.lastFullRead = { query = queryCount, batch = batch, at = GetTime() }
		status.fullScan = nil
		S.Commit(cap)
		if capture == cap then capture = nil end
		if cap.aborted then
			ns.Print("full scan interrupted; saved what was read (%d of %d auctions).", seen, batch)
		else
			ns.Print("full scan read: %d auctions.", seen)
		end
		ns.Fire("MI_SCAN_PROGRESS")
		return true
	end)
end

---------------------------------------------------------------------------
-- Events and the QueryAuctionItems hook
---------------------------------------------------------------------------
local function OnQuery(name, minLevel, maxLevel, page, usable, rarity, getAll, exact)
	queryCount = queryCount + 1
	local qkey
	if getAll then
		qkey = "*getall*"
	else
		qkey = table.concat({ tostring(name or ""), tostring(minLevel or ""), tostring(maxLevel or ""),
			tostring(usable or ""), tostring(rarity or ""), tostring(exact or "") }, "|")
	end
	if capture and capture.processing then
		-- another search replaced the full-scan results before we finished reading them
		capture.aborted = true
		return
	end
	-- A new search starts at page 0; also never merge with pages read long ago.
	local stale = capture and capture.updatedAt and time() - capture.updatedAt > 300
	if not capture or capture.qkey ~= qkey or getAll or (page or 0) == 0 or stale then
		if capture then S.Commit(capture) end
		capture = NewCapture(qkey, getAll and true or false)
	end
	capture.page = page or 0
	capture.hooked = true
end

if QueryAuctionItems then
	hooksecurefunc("QueryAuctionItems", OnQuery)
end

ns.On("AUCTION_ITEM_LIST_UPDATE", function()
	if not ahOpen then return end
	if capture and capture.processing then return end
	local batch, total = GetNumAuctionItems("list")
	batch, total = batch or 0, total or 0
	if not capture then capture = NewCapture("?", false) end
	if capture.getAll or batch > PAGE_SIZE then
		-- The client re-fires this event while item info loads. Read a full scan
		-- only once: skip it if no new query was sent since we last read one.
		local last = S.lastFullRead
		-- Without the hook (queryCount stays 0) fall back to a 5 minute window.
		if last and last.query == queryCount and last.batch == batch and (queryCount > 0 or GetTime() - last.at < 300) then
			if capture.qkey == "?" then capture = nil end
			return
		end
		capture.getAll = true
		if batch > 0 then ReadFullScan(capture, batch) end
		return
	end
	capture.total = total
	capture.pages[capture.page] = ReadPage(batch)
	capture.dirty, capture.updatedAt = true, time()
	S.status.lastUpdate = GetTime()
	ScheduleCommit()
end)

ns.On("AUCTION_HOUSE_SHOW", function()
	ahOpen = true
	ns.playerName = ns.playerName or UnitName("player")
	ns.playerFullName = ns.playerName .. "-" .. (GetRealmName() or ""):gsub("%s+", "")
	local key = ns.GetAuctionHouseKey()
	if key ~= ns.realmKey then
		-- a different auction house (faction vs neutral): live listings, deals,
		-- snipes and flips from the other one no longer apply
		wipe(ns.current)
		ns.Analysis.ClearDeals()
		ns.Snipe.Clear()
	end
	ns.SetAuctionHouse(key)
	ns.Fire("MI_AH_OPENED")
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	if capture and capture.processing then
		capture.aborted = true -- the full-scan task notices and saves what it has
	elseif capture then
		S.Commit(capture)
	end
	capture = nil
	ahOpen = false
	S.StopScan(true)
	ns.Fire("MI_AH_CLOSED")
end)

---------------------------------------------------------------------------
-- Active scans: a list of searches, each read page by page
---------------------------------------------------------------------------
S.status = {} -- for the UI: scanning, label, index, count, fullScan, fullScanProgress

local QUERY_TIMEOUT = 6

-- queries = { { name, minLevel, maxLevel, rarity, exact }, ... }
-- onDone(cancelled) runs at the end.
function S.RunQueries(label, queries, onDone)
	if not ahOpen then ns.Print("open the auction house first.") return false end
	if S.status.scanning then ns.Print("a %s is already running.", S.status.label or "scan") return false end
	if capture and capture.processing then ns.Print("wait for the full scan to finish.") return false end
	if #queries == 0 then return false end

	local st = S.status
	st.scanning, st.label, st.index, st.count, st.page = true, label, 1, #queries, 0
	st.cancel = nil
	local waiting, sentAt, gotAt = false, 0, nil
	ns.Fire("MI_SCAN_PROGRESS")

	local function finish(cancelled)
		if capture then S.Commit(capture) end
		st.scanning, st.onUpdate = nil, nil
		if onDone then onDone(cancelled) end
		ns.Fire("MI_SCAN_PROGRESS")
	end
	st.onUpdate = function() if waiting then gotAt = GetTime() end end
	ns.RunTask(function()
		if st.cancel or not ahOpen then
			finish(true)
			return true
		end
		local now = GetTime()
		if waiting then
			-- give item info a moment to load after the results arrive
			local done = (gotAt and now - gotAt > 0.4) or now - sentAt > QUERY_TIMEOUT
			if not done then return false end
			waiting = false
			local _, total = GetNumAuctionItems("list")
			if gotAt and (st.page + 1) * PAGE_SIZE < (total or 0) then
				st.page = st.page + 1
				st.pages = math.ceil((total or 0) / PAGE_SIZE)
			else
				st.index, st.page, st.pages = st.index + 1, 0, nil
			end
			ns.Fire("MI_SCAN_PROGRESS")
			gotAt = nil
		end
		if st.index > st.count then
			finish(false)
			return true
		end
		if CanSendAuctionQuery() then
			local q = queries[st.index]
			QueryAuctionItems(q.name or "", q.minLevel, q.maxLevel, st.page, false, q.rarity, false, q.exact and true or false)
			waiting, sentAt, gotAt = true, now, nil
		end
		return false
	end)
	return true
end

function S.ScanWatchlist()
	local names = {}
	for _, w in pairs(ns.db.watch) do names[#names + 1] = w.name end
	table.sort(names)
	if #names == 0 then return ns.Print("your watchlist is empty. Add items with /mi watch <item>.") end
	local queries = {}
	for i, name in ipairs(names) do queries[i] = { name = name, exact = true } end
	local startDeals = #ns.deals
	S.RunQueries("watchlist scan", queries, function(cancelled)
		if not cancelled then
			ns.Print("watchlist scan finished: %d items, %d new deals.", #names, #ns.deals - startDeals)
		end
	end)
end

function S.StopScan(silent)
	if S.status.scanning then
		S.status.cancel = true
		if not silent then ns.Print("%s stopped.", S.status.label or "scan") end
	end
end

ns.On("AUCTION_ITEM_LIST_UPDATE", function()
	if S.status.onUpdate then S.status.onUpdate() end
end)
