-- Market Intel: reads auction house results.
--
-- Passive capture: every search made by you, Auctionator, TSM or the default UI
-- (including Auctionator's full scan) is read from the results list and turned
-- into price snapshots. Pages of the same search are merged before saving.
-- Active scan: /mi scan or the Scan button searches each watchlist item.
local _, ns = ...

local S = {}
ns.Scanner = S
ns.current = {} -- this session's detail per item key: ladder, own listings, cheap stock

local ipairs, pairs = ipairs, pairs
local PAGE_SIZE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local CHUNK = 1000          -- rows read per frame during a full scan
local COMMIT_CHUNK = 400    -- items saved per frame during a large commit
local IDLE_COMMIT = 2       -- seconds after the last result update before saving
local MISSING_TOLERANCE = 0.01

local ahOpen = false
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
	local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemId = GetAuctionItemInfo("list", i)
	if not name or not itemId then return nil end
	if not buyout or buyout <= 0 or not count or count <= 0 then return false end -- bid-only
	if (quality or 0) < ns.settings.minQuality then return false end
	local key = ns.ItemKeyFromLink(GetAuctionItemLink("list", i)) or tostring(itemId)
	return {
		key = key, name = name, quality = quality, count = count, buyout = buyout,
		unit = buyout / count, owner = owner, mine = owner ~= nil and owner == ns.playerName,
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

local function CommitItem(key, listings, full, now, newDeals)
	local first = listings[1]
	local snap = ns.Analysis.BuildSnapshot(listings, full, now) -- sorts listings by unit price
	local ref = ns.History.GetReference(key, now)
	local watch = ns.Watch.Get(first.name)
	for _, deal in ipairs(ns.Analysis.FindDeals(key, listings, ref, watch and watch.max)) do
		if ns.Analysis.AddDeal(deal, first.name, now) then newDeals[#newDeals + 1] = deal end
	end
	if full then ns.Analysis.PruneDeals(key, listings) end

	local mine, cheapQty, cheapCost = 0, 0, 0
	for _, l in ipairs(listings) do
		if l.mine then mine = mine + l.count end
		if ref and l.unit < ref * 0.9 and not l.mine then
			cheapQty = cheapQty + l.count
			cheapCost = cheapCost + l.buyout
		end
	end
	ns.current[key] = {
		t = now, ladder = ns.Analysis.BuildLadder(listings, 5), mine = mine,
		cheapQty = cheapQty, cheapCost = cheapCost, ref = ref, full = full,
	}
	ns.History.AddSnapshot(key, first.name, first.quality, snap)
end

-- Save the merged pages of a capture. Large captures are saved over several frames.
function S.Commit(cap)
	if not cap or cap.committing or not cap.dirty then return end
	ns.Cancel(commitTimer)
	cap.dirty = false
	local seen, missing, byKey, keys = 0, 0, {}, {}
	for _, page in pairs(cap.pages) do
		seen, missing = seen + page.seen, missing + page.missing
		for _, row in ipairs(page.rows) do
			local list = byKey[row.key]
			if not list then
				list = {}
				byKey[row.key] = list
				keys[#keys + 1] = row.key
			end
			list[#list + 1] = row
		end
	end
	if #keys == 0 then return end
	local total = cap.total or seen
	local full = not cap.aborted and seen + missing >= total and missing <= total * MISSING_TOLERANCE
	local now = cap.updatedAt or time() -- when the results arrived, not when we save them
	local newDeals = {}
	local function finish()
		cap.committing = nil
		ns.Analysis.Alert(newDeals)
		ns.Fire("MI_DATA_UPDATED")
		ns.Fire("MI_CAPTURE_SAVED", #keys, full, cap.getAll)
	end
	if #keys <= COMMIT_CHUNK then
		for _, key in ipairs(keys) do CommitItem(key, byKey[key], full, now, newDeals) end
		return finish()
	end
	cap.committing = true
	local i = 1
	ns.RunTask(function()
		local stop = math.min(i + COMMIT_CHUNK - 1, #keys)
		for j = i, stop do CommitItem(keys[j], byKey[keys[j]], full, now, newDeals) end
		i = stop + 1
		if i > #keys then
			finish()
			return true
		end
	end)
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
			local stop = math.min(i + CHUNK - 1, batch)
			for idx = i, stop do
				local row = ReadRow(idx)
				if row == nil then missingIdx[#missingIdx + 1] = idx
				else
					seen = seen + 1
					if row then rows[#rows + 1] = row end
				end
			end
			i = stop + 1
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
	ns.SetAuctionHouse(ns.GetAuctionHouseKey())
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
-- Active watchlist scan
---------------------------------------------------------------------------
S.status = {} -- for the UI: scanning, index, count, fullScan, fullScanProgress

local QUERY_TIMEOUT = 6

function S.ScanWatchlist()
	if not ahOpen then return ns.Print("open the auction house first.") end
	if S.status.scanning then return ns.Print("a watchlist scan is already running.") end
	if capture and capture.processing then return ns.Print("wait for the full scan to finish.") end
	local names = {}
	for _, w in pairs(ns.db.watch) do names[#names + 1] = w.name end
	table.sort(names)
	if #names == 0 then return ns.Print("your watchlist is empty. Add items with /mi watch <item>.") end

	local st = S.status
	st.scanning, st.index, st.count, st.page = true, 1, #names, 0
	st.cancel = nil
	local waiting, sentAt, gotAt = false, 0, nil
	local startDeals = #ns.deals
	ns.Fire("MI_SCAN_PROGRESS")

	st.onUpdate = function() if waiting then gotAt = GetTime() end end
	ns.RunTask(function()
		if st.cancel or not ahOpen then
			st.scanning, st.onUpdate = nil, nil
			ns.Fire("MI_SCAN_PROGRESS")
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
			else
				st.index, st.page = st.index + 1, 0
				ns.Fire("MI_SCAN_PROGRESS")
			end
			gotAt = nil
		end
		if st.index > st.count then
			if capture then S.Commit(capture) end
			st.scanning, st.onUpdate = nil, nil
			ns.Print("watchlist scan finished: %d items, %d new deals.", st.count, #ns.deals - startDeals)
			ns.Fire("MI_SCAN_PROGRESS")
			return true
		end
		if CanSendAuctionQuery() then
			QueryAuctionItems(names[st.index], nil, nil, st.page, false, nil, false, true)
			waiting, sentAt, gotAt = true, now, nil
		end
		return false
	end)
end

function S.StopScan(silent)
	if S.status.scanning then
		S.status.cancel = true
		if not silent then ns.Print("watchlist scan stopped.") end
	end
end

ns.On("AUCTION_ITEM_LIST_UPDATE", function()
	if S.status.onUpdate then S.status.onUpdate() end
end)
