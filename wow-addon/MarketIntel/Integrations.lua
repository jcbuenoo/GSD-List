-- Market Intel: optional hooks into Auctionator and TradeSkillMaster.
-- Everything is wrapped in pcall so a change in either addon's API cannot break ours.
local _, ns = ...

local I = {}
ns.Integrations = I

local CALLER = "MarketIntel"

local function AuctionatorAPI()
	return Auctionator and Auctionator.API and Auctionator.API.v1
end

function I.HasAuctionator()
	return AuctionatorAPI() ~= nil
end

function I.HasTSM()
	return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

-- Auctionator's latest recorded minimum buyout (per unit), or nil.
function I.GetAuctionatorPrice(key)
	local api = AuctionatorAPI()
	local id = ns.ItemIDFromKey(key)
	if not api or not api.GetAuctionPriceByItemID or not id then return nil end
	local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
	if ok and type(price) == "number" and price > 0 then return price end
	return nil
end

-- TSM market value. Only available with the TSM desktop app's price data.
function I.GetTSMPrice(key, source)
	if not I.HasTSM() then return nil end
	local id = ns.ItemIDFromKey(key)
	if not id then return nil end
	local ok, price = pcall(TSM_API.GetCustomPriceValue, source or "dbmarket", "i:" .. id)
	if ok and type(price) == "number" and price > 0 then return price end
	return nil
end

---------------------------------------------------------------------------
-- Importing Auctionator's price history
--
-- Auctionator keeps, per realm, a table of items: { m = latest min price,
-- l = { [day] = lowest price }, h = { [day] = highest min price }, a = { [day] = quantity } }
-- where day counts days since Auctionator's SCAN_DAY_0 (1 Jan 2020). We only read it,
-- and only if it has exactly that shape; anything else is reported and skipped.
---------------------------------------------------------------------------
local function ScanDayZero()
	local c = Auctionator and Auctionator.Constants
	if c and type(c.SCAN_DAY_0) == "number" then return c.SCAN_DAY_0 end
	return time({ year = 2020, month = 1, day = 1, hour = 0 })
end

-- Pick the realm table in Auctionator's database that matches this auction house.
function I.FindAuctionatorRealm(db)
	if type(db) ~= "table" then return nil end
	local realm = (GetRealmName() or ""):lower():gsub("%s+", "")
	local faction = (ns.realmKey or ""):match("%-(%a+)$") or ""
	faction = faction:lower()
	local matches = {}
	for key, value in pairs(db) do
		if type(key) == "string" and type(value) == "table" and not key:find("^__") then
			local k = key:lower():gsub("%s+", "")
			if realm ~= "" and k:find(realm, 1, true) then matches[#matches + 1] = key end
		end
	end
	if #matches > 1 then
		for _, key in ipairs(matches) do
			if key:lower():find(faction, 1, true) then return db[key], key end
		end
	end
	if matches[1] then return db[matches[1]], matches[1] end
	return nil
end

-- Convert one Auctionator item entry into Market Intel daily summaries.
-- Returns nil if the entry does not look like Auctionator price data.
function I.ConvertAuctionatorEntry(entry, dayZero, oldestDay, today)
	if type(entry) ~= "table" or (type(entry.l) ~= "table" and type(entry.h) ~= "table") then return nil end
	local low, high, avail = entry.l or {}, entry.h or {}, type(entry.a) == "table" and entry.a or {}
	local days, seen = {}, {}
	local function add(dayKey)
		local n = tonumber(dayKey)
		if not n or seen[n] then return end
		seen[n] = true
		local lo, hi = tonumber(low[dayKey]), tonumber(high[dayKey])
		local price = lo or hi
		if not price or price <= 0 then return end
		local day = ns.DayKey(dayZero + n * 86400 + 43200)
		if day < oldestDay or day > today then return end
		local qty = tonumber(avail[dayKey])
		days[#days + 1] = {
			day = day, min = lo or hi, mkt = (lo and hi) and (lo + hi) / 2 or price,
			qty = qty and qty > 0 and qty or nil, n = 1,
		}
	end
	for dayKey in pairs(low) do add(dayKey) end
	for dayKey in pairs(high) do add(dayKey) end
	table.sort(days, function(a, b) return a.day < b.day end)
	return days
end

-- Copy Auctionator's history into ours, spread over several frames.
-- verbose = print a message even when there is nothing to do.
function I.ImportAuctionator(verbose)
	if I.importing then return end
	local db = AUCTIONATOR_PRICE_DATABASE
	if type(db) ~= "table" then
		if verbose then ns.Print("Auctionator's price database was not found. Is Auctionator enabled?") end
		return
	end
	local realmDB, realmName = I.FindAuctionatorRealm(db)
	if not realmDB then
		if verbose then ns.Print("no Auctionator data for %s was found.", GetRealmName() or "this realm") end
		return
	end
	local now = time()
	local today = ns.DayKey(now)
	local oldestDay = ns.DayKey(now - ns.settings.keepDays * 86400)
	local dayZero = ScanDayZero()
	local keys = {}
	for key in pairs(realmDB) do
		-- plain item IDs only; Auctionator's "g:" (gear by item level) and "p:" (pet) keys are skipped
		if type(key) == "string" and key:match("^%d+$") then keys[#keys + 1] = key
		elseif type(key) == "number" then keys[#keys + 1] = tostring(key) end
	end
	I.importing = true
	local i, items, days, bad, newest = 1, 0, 0, 0, 0
	ns.RunTask(function()
		local stop = math.min(#keys, i + 299)
		for j = i, stop do
			local key = keys[j]
			local entry = realmDB[key] or realmDB[tonumber(key)]
			local converted = I.ConvertAuctionatorEntry(entry, dayZero, oldestDay, today)
			if not converted then
				bad = bad + 1
			elseif #converted > 0 then
				newest = math.max(newest, converted[#converted].day)
				local added = ns.History.ImportDays(key, converted)
				if added > 0 then
					items, days = items + 1, days + added
				end
			end
		end
		i = stop + 1
		if i <= #keys then return false end
		I.importing = nil
		ns.realm.importedAuctionator = now
		ns.History.ResetIndex()
		if bad > #keys / 2 then
			ns.Print("Auctionator's data format was not recognized (%d of %d entries), nothing useful imported.", bad, #keys)
		elseif items > 0 or verbose then
			ns.Print("imported %d days of price history for %d items from Auctionator (%s).", days, items, realmName)
		end
		ns.Fire("MI_DATA_UPDATED")
		return true
	end)
end

-- On first use, seed an empty auction house history from Auctionator automatically.
ns.On("MI_READY", function()
	if ns.realm and not ns.realm.importedAuctionator and next(ns.realm.items) == nil then
		I.ImportAuctionator(false)
	end
end)

-- Search the auction house for an item, preferring Auctionator's shopping tab.
-- Returns true if a search was started.
function I.SearchItem(name)
	if not name or name == "" then return false end
	local api = AuctionatorAPI()
	if api and api.MultiSearchExact then
		local ok = pcall(api.MultiSearchExact, CALLER, { name })
		if ok then return true end
	end
	if not ns.Scanner.IsAuctionHouseOpen() then
		ns.Print("open the auction house first.")
		return false
	end
	if not CanSendAuctionQuery() then
		ns.Print("the auction house is busy, try again in a moment.")
		return false
	end
	-- Fall back to the default browse tab.
	if AuctionFrameTab1 and AuctionFrameTab_OnClick then pcall(AuctionFrameTab_OnClick, AuctionFrameTab1) end
	if BrowseName then BrowseName:SetText(name) end
	QueryAuctionItems(name, nil, nil, 0, false, nil, false, true)
	return true
end
