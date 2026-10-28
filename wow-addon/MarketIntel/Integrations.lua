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
-- Auctionator keeps, per realm ("Nightslayer Horde"), one entry per item:
--   { m = latest min price, l = { [day] = lowest }, h = { [day] = highest }, a = { [day] = quantity } }
-- where day counts days since 1 Jan 2020 (Auctionator's SCAN_DAY_0). Since its
-- database version 8 each realm is stored packed as one CBOR string; older
-- versions store a plain table. Both are read. We only read it, and anything
-- that does not have this shape is reported and skipped.
---------------------------------------------------------------------------
local function ScanDayZero()
	local c = Auctionator and Auctionator.Constants
	if c and type(c.SCAN_DAY_0) == "number" then return c.SCAN_DAY_0 end
	return time({ year = 2020, month = 1, day = 1, hour = 0 })
end

-- Minimal CBOR (RFC 8949) reader. Returns value(), mapHeader(), atBreak().
local floor, byte, sub, format = math.floor, string.byte, string.sub, string.format
function I.CBORDecoder(s)
	local pos = 1
	local function u(n)
		local v = 0
		for i = pos, pos + n - 1 do
			local b = byte(s, i)
			if not b then error("cbor: data ends early") end
			v = v * 256 + b
		end
		pos = pos + n
		return v
	end
	local function len(info)
		if info < 24 then return info end
		if info == 24 then return u(1) elseif info == 25 then return u(2)
		elseif info == 26 then return u(4) elseif info == 27 then return u(8) end
		if info == 31 then return nil end -- indefinite length
		error("cbor: bad length")
	end
	local function float(n)
		if n == 2 then
			local h = u(2)
			local sign, e, m = h >= 32768 and -1 or 1, floor(h / 1024) % 32, h % 1024
			if e == 0 then return sign * m * 2 ^ -24 elseif e == 31 then return nil end
			return sign * (1 + m / 1024) * 2 ^ (e - 15)
		elseif n == 4 then
			local b = u(4)
			local sign, e, m = b >= 2 ^ 31 and -1 or 1, floor(b / 2 ^ 23) % 256, b % 2 ^ 23
			if e == 0 then return sign * m * 2 ^ -149 elseif e == 255 then return nil end
			return sign * (1 + m / 2 ^ 23) * 2 ^ (e - 127)
		end
		local hi, lo = u(4), u(4)
		local sign, e, m = hi >= 2 ^ 31 and -1 or 1, floor(hi / 2 ^ 20) % 2048, (hi % 2 ^ 20) * 2 ^ 32 + lo
		if e == 0 then return sign * m * 2 ^ -1074 elseif e == 2047 then return nil end
		return sign * (1 + m / 2 ^ 52) * 2 ^ (e - 1023)
	end
	local function atBreak()
		if byte(s, pos) == 0xff then
			pos = pos + 1
			return true
		end
		if not byte(s, pos) then error("cbor: data ends early") end
		return false
	end
	local value
	value = function()
		local ib = byte(s, pos)
		if not ib then error("cbor: data ends early") end
		pos = pos + 1
		local major, info = floor(ib / 32), ib % 32
		if major == 0 then return len(info)
		elseif major == 1 then return -1 - len(info)
		elseif major == 2 or major == 3 then
			local n = len(info)
			if not n then
				local parts = {}
				while not atBreak() do parts[#parts + 1] = value() end
				return table.concat(parts)
			end
			if pos + n - 1 > #s then error("cbor: data ends early") end
			local str = sub(s, pos, pos + n - 1)
			pos = pos + n
			return str
		elseif major == 4 then
			local n, t = len(info), {}
			if n then
				for i = 1, n do t[i] = value() end
			else
				while not atBreak() do t[#t + 1] = value() end
			end
			return t
		elseif major == 5 then
			local n, t = len(info), {}
			if n then
				for _ = 1, n do
					local k = value()
					local v = value()
					if k ~= nil then t[k] = v end
				end
			else
				while not atBreak() do
					local k = value()
					local v = value()
					if k ~= nil then t[k] = v end
				end
			end
			return t
		elseif major == 6 then
			len(info) -- tag number: ignored
			return value()
		end
		if info == 20 then return false elseif info == 21 then return true
		elseif info == 22 or info == 23 or info < 20 or info == 24 then
			if info == 24 then u(1) end
			return nil
		elseif info >= 25 and info <= 27 then return float(2 ^ (info - 24)) end
		error("cbor: unsupported value")
	end
	-- Opens a map; returns its size (-1 for indefinite length) or nil if the data is not a map.
	local function mapHeader()
		local ib = byte(s, pos)
		if not ib or floor(ib / 32) ~= 5 then return nil end
		pos = pos + 1
		return len(ib % 32) or -1
	end
	return value, mapHeader, atBreak
end

-- Pick this auction house's entry in Auctionator's database (a table or a packed string).
function I.FindAuctionatorRealm(db)
	if type(db) ~= "table" then return nil end
	local realm = (GetRealmName() or ""):lower():gsub("%s+", "")
	local faction = (ns.realmKey or ""):match("%-(%a+)$") or ""
	faction = faction:lower()
	local matches = {}
	for key, value in pairs(db) do
		if type(key) == "string" and (type(value) == "table" or type(value) == "string") and not key:find("^__") then
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

-- Copy Auctionator's history into ours, as a background job within the frame budget.
-- verbose = print a message even when there is nothing to do.
function I.ImportAuctionator(verbose)
	if I.importing then return end
	local db = AUCTIONATOR_PRICE_DATABASE
	local realmData, realmName
	if type(db) == "table" then realmData, realmName = I.FindAuctionatorRealm(db) end
	if realmData == nil then
		-- Auctionator's database as loaded in memory, if it exposes it
		local live = Auctionator and type(Auctionator.Database) == "table" and Auctionator.Database.db
		if type(live) == "table" and next(live) then realmData, realmName = live, "Auctionator (loaded)" end
	end
	if realmData == nil then
		if verbose then
			if type(db) ~= "table" then
				ns.Print("Auctionator's price database was not found. Is Auctionator enabled?")
			else
				ns.Print("no Auctionator data for %s was found.", GetRealmName() or "this realm")
			end
		end
		return
	end
	local now = time()
	local today = ns.DayKey(now)
	local oldestDay = ns.DayKey(now - ns.settings.keepDays * 86400)
	local dayZero = ScanDayZero()
	local st = { items = 0, days = 0, bad = 0, skipped = 0, total = 0 }

	local function handle(key, entry)
		st.total = st.total + 1
		if type(key) == "number" then key = tostring(key) end
		-- plain item IDs only; "g:"/"gr:" (gear by item level / random suffix) and "p:" (pets) are skipped
		if type(key) ~= "string" or not key:match("^%d+$") then
			st.skipped = st.skipped + 1
			return
		end
		local converted = I.ConvertAuctionatorEntry(entry, dayZero, oldestDay, today)
		if not converted then
			st.bad = st.bad + 1
		elseif #converted > 0 then
			local added = ns.History.ImportDays(key, converted)
			if added > 0 then st.items, st.days = st.items + 1, st.days + added end
		end
	end

	local function finish()
		I.importing = nil
		ns.History.ResetIndex()
		local considered = st.total - st.skipped
		if st.notMap or (st.decodeError and st.items == 0) or (considered > 0 and st.bad > considered / 2) then
			ns.Print("Auctionator's data format was not recognized (%s), nothing imported.",
				st.decodeError or (st.notMap and "not a table") or format("%d of %d entries", st.bad, considered))
		else
			ns.realm.importedAuctionator = now
			if st.items > 0 or verbose then
				ns.Print("imported %d days of price history for %d items from Auctionator (%s)%s.", st.days, st.items, realmName,
					st.skipped > 0 and format("; %d gear/pet entries skipped", st.skipped) or "")
			end
			if st.decodeError then ns.Print("the rest of Auctionator's data could not be read (%s).", st.decodeError) end
		end
		ns.Fire("MI_DATA_UPDATED")
	end

	I.importing = true
	ns.RunJob(function(yield)
		if type(realmData) == "table" then
			local keys = {}
			for key in pairs(realmData) do keys[#keys + 1] = key end
			for i, key in ipairs(keys) do
				handle(key, realmData[key])
				if i % 50 == 0 then ns.Checkpoint(yield) end
			end
			return
		end
		local value, mapHeader, atBreak = I.CBORDecoder(realmData)
		local ok, count = pcall(mapHeader)
		if not ok or not count then
			st.notMap = true
			return
		end
		local i = 0
		while true do
			local more
			if count >= 0 then more = i < count else
				local okBreak, isBreak = pcall(atBreak)
				more = okBreak and not isBreak
				if not okBreak then st.decodeError = isBreak end
			end
			if not more then break end
			i = i + 1
			local okEntry, key, entry = pcall(function() return value(), value() end)
			if not okEntry then
				st.decodeError = tostring(key):gsub("^.-cbor: ", "")
				break
			end
			handle(key, entry)
			if i % 50 == 0 then ns.Checkpoint(yield) end
		end
	end, finish)
end

-- Import once per auction house, automatically. Days Market Intel already has
-- are never overwritten, so this is safe even after you have started scanning.
ns.On("MI_READY", function()
	if ns.realm and not ns.realm.importedAuctionator then
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
