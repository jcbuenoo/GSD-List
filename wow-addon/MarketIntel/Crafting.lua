-- Market Intel: crafting profit for your favourite recipes.
-- Recipes come from TSM's own recipe list, plus any learnt when you open a
-- profession window. Only recipes starred as favourites in TSM's crafting
-- window are evaluated (plus any you star in Market Intel's Crafting tab).
local _, ns = ...

local C = {}
ns.Crafting = C

local AH_CUT = 0.05

local function Recipes()
	ns.db.recipes = ns.db.recipes or {}
	return ns.db.recipes
end

local function Stars()
	ns.db.craftStars = ns.db.craftStars or {}
	return ns.db.craftStars
end

---------------------------------------------------------------------------
-- Learning recipes from the profession windows
---------------------------------------------------------------------------
local function SaveRecipe(spellID, rec)
	local recipes = Recipes()
	local old = recipes[spellID]
	-- reagent info can still be loading; never replace a complete recipe with a partial one
	if rec.incomplete and old and not old.incomplete then return end
	recipes[spellID] = rec
end

function C.ScanTradeSkill()
	if not GetNumTradeSkills then return end
	local prof = GetTradeSkillLine and GetTradeSkillLine()
	-- the window reports "UNKNOWN" until its data has loaded; TRADE_SKILL_UPDATE brings us back
	if not prof or prof == "" or prof == "UNKNOWN" then return end
	for i = 1, GetNumTradeSkills() do
		local name, kind = GetTradeSkillInfo(i)
		local link = name and kind ~= "header" and GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
		local spellID = link and tonumber(link:match("enchant:(%d+)"))
		if spellID then
			local lo, hi = GetTradeSkillNumMade(i)
			local rec = { n = name, prof = prof, item = ns.ItemKeyFromLink(GetTradeSkillItemLink(i)),
				made = ((lo or 1) + (hi or lo or 1)) / 2, r = {}, rn = {} }
			for j = 1, (GetTradeSkillNumReagents(i) or 0) do
				local rname, _, count = GetTradeSkillReagentInfo(i, j)
				local rkey = ns.ItemKeyFromLink(GetTradeSkillReagentItemLink(i, j))
				if rkey and count then
					rec.r[rkey], rec.rn[rkey] = count, rname
				else
					rec.incomplete = true
				end
			end
			SaveRecipe(spellID, rec)
		end
	end
end

-- Enchanting (and hunter pet training) use the older "craft" window in TBC.
function C.ScanCraft()
	if not GetNumCrafts then return end
	local prof = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
	if not prof or prof == "" or prof == "UNKNOWN" then prof = "Enchanting" end
	for i = 1, GetNumCrafts() do
		local name, _, kind = GetCraftInfo(i)
		local link = name and kind ~= "header" and GetCraftItemLink and GetCraftItemLink(i)
		local spellID = link and tonumber(link:match("enchant:(%d+)"))
		local numReagents = GetCraftNumReagents and GetCraftNumReagents(i) or 0
		if spellID and numReagents > 0 then
			local rec = { n = name, prof = prof, made = 1, r = {}, rn = {} } -- enchants make no item
			for j = 1, numReagents do
				local rname, _, count = GetCraftReagentInfo(i, j)
				local rkey = ns.ItemKeyFromLink(GetCraftReagentItemLink(i, j))
				if rkey and count then
					rec.r[rkey], rec.rn[rkey] = count, rname
				else
					rec.incomplete = true
				end
			end
			SaveRecipe(spellID, rec)
		end
	end
end

local scanTimer
local function ScheduleScan(fn)
	ns.Cancel(scanTimer)
	scanTimer = ns.After(0.5, function()
		scanTimer = nil
		fn()
		ns.Fire("MI_DATA_UPDATED")
	end)
end
ns.On("TRADE_SKILL_SHOW", function() ScheduleScan(C.ScanTradeSkill) end)
ns.On("TRADE_SKILL_UPDATE", function() ScheduleScan(C.ScanTradeSkill) end)
ns.On("CRAFT_SHOW", function() ScheduleScan(C.ScanCraft) end)
ns.On("CRAFT_UPDATE", function() ScheduleScan(C.ScanCraft) end)

---------------------------------------------------------------------------
-- Favourites: TSM's starred recipes
---------------------------------------------------------------------------
-- TSM keeps its data in TradeSkillMasterDB with keys like
--   "f@Horde - Nightslayer@internalData@isCraftFavorite" = { [12757595] = true, ... }
--   "f@Horde - Nightslayer@internalData@crafts" = { ["c:12757595"] = { name, profession,
--       itemString = "i:31080", numResult = 1, mats = { ["i:22451"] = 1, ... } }, ... }
-- (checked against a real TSM file for TBC Anniversary). Favourites and recipes
-- are read for your realm and faction; if those are missing, from any realm.
local tsmCache, tsmCacheAt

local function TSMTables(suffix)
	local db = TradeSkillMasterDB
	if type(db) ~= "table" then return {} end
	local realm, faction = GetRealmName() or "", UnitFactionGroup("player") or ""
	local mine, others = {}, {}
	for k, v in pairs(db) do
		if type(k) == "string" and type(v) == "table" then
			local f, r = k:match("^f@(.-) %- (.-)@internalData@" .. suffix .. "$")
			if f then
				if f == faction and r == realm then mine[#mine + 1] = v else others[#others + 1] = v end
			end
		end
	end
	return #mine > 0 and mine or others
end

-- One TSM recipe in Market Intel's recipe format.
local function FromTSM(c)
	local item = type(c.itemString) == "string" and c.itemString:match("^i:(%d+)$") or nil
	local rec = { n = tostring(c.name or "?"), prof = tostring(c.profession or "?"), item = item,
		made = tonumber(c.numResult) or 1, r = {}, rn = {}, tsm = true }
	for mat, count in pairs(type(c.mats) == "table" and c.mats or {}) do
		local id = type(mat) == "string" and mat:match("^i:(%d+)$")
		if id and tonumber(count) then rec.r[id] = tonumber(count) else rec.incomplete = true end
	end
	if not next(rec.r) then rec.incomplete = true end
	return rec
end

-- { favs = { ["c:N"] = true }, recipes = { ["c:N"] = rec }, found = favourites table exists }
function C.GetTSM()
	local now = GetTime()
	if tsmCacheAt and now - tsmCacheAt < 10 then return tsmCache end
	tsmCacheAt = now
	local favs, recipes, found = {}, {}, false
	for _, t in ipairs(TSMTables("isCraftFavorite")) do
		found = true
		for id, v in pairs(t) do
			if v then
				local cs = tostring(id)
				if not cs:find("^c:") then cs = "c:" .. cs end
				favs[cs] = true
			end
		end
	end
	for _, t in ipairs(TSMTables("crafts")) do
		for cs, c in pairs(t) do
			if type(cs) == "string" and type(c) == "table" and not recipes[cs] then recipes[cs] = FromTSM(c) end
		end
	end
	tsmCache = { favs = favs, recipes = recipes, found = found }
	return tsmCache
end

-- Every known recipe: TSM's list (ids "c:N") plus recipes learnt from the
-- profession windows (spell IDs) that TSM does not already have.
function C.AllRecipes()
	local all, names = {}, {}
	for id, rec in pairs(C.GetTSM().recipes) do
		all[id] = rec
		names[rec.n] = true
	end
	for id, rec in pairs(Recipes()) do
		if not names[rec.n] then all[id] = rec end
	end
	return all
end

function C.CountRecipes()
	local n = 0
	for _ in pairs(C.AllRecipes()) do n = n + 1 end
	return n
end

-- Favourite recipe ids and where they came from; second value: TSM favourites were found.
function C.GetFavorites()
	local tsm = C.GetTSM()
	local favs = {}
	for id in pairs(tsm.favs) do
		if tsm.recipes[id] then favs[id] = "TSM" end
	end
	for id in pairs(Stars()) do favs[id] = favs[id] or "Market Intel" end
	return favs, tsm.found
end

function C.ToggleStar(id)
	local stars = Stars()
	stars[id] = not stars[id] or nil
	ns.Fire("MI_DATA_UPDATED")
end

function C.IsStarred(id) return Stars()[id] == true end

---------------------------------------------------------------------------
-- Prices and profit
---------------------------------------------------------------------------
-- What a vendor charges for an item: Auctionator's vendor price cache, else TSM.
function C.VendorPrice(key)
	local cache = AUCTIONATOR_VENDOR_PRICE_CACHE
	local v = type(cache) == "table" and tonumber(cache[tostring(key)])
	if v and v > 0 then return v end
	return ns.Integrations.GetTSMPrice(key, "vendorbuy")
end

-- Price per reagent: TSM's material price if TSM has one; otherwise the cheaper
-- of the vendor price and the auction house (normal price from history, which
-- is steadier than one search, else the latest market value, else Auctionator).
function C.ReagentPrice(key)
	local tsm = ns.Integrations.GetTSMPrice(key, "matprice")
	if tsm then return tsm, "TSM" end
	local ah, source = ns.History.GetReference(key), "normal"
	if not ah then
		local latest = ns.History.GetLatest(key)
		ah, source = latest and latest.mkt, "AH"
	end
	if not ah then ah, source = ns.Integrations.GetAuctionatorPrice(key), "Auctionator" end
	local vendor = C.VendorPrice(key)
	if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
	return ah, ah and source or nil
end

-- What one crafted item sells for: the cheapest current listing, else normal price, else TSM.
function C.ResultValue(key)
	local cur = ns.current[key]
	if cur and cur.levels and cur.levels[1] then return cur.levels[1].unit end
	local latest = ns.History.GetLatest(key)
	if latest then return latest.min end
	return ns.History.GetReference(key) or ns.Integrations.GetTSMPrice(key, "dbmarket")
end

-- Cheapest live deal price per reagent key.
local function DealPrices()
	local out = {}
	for _, d in ipairs(ns.deals) do
		if not out[d.key] or d.unit < out[d.key] then out[d.key] = d.unit end
	end
	return out
end

-- Cost, value and profit of one recipe. overrides = { [reagentKey] = price } (deal prices).
function C.Evaluate(rec, overrides)
	local cost, missing, parts = 0, false, {}
	for rkey, count in pairs(rec.r) do
		local price, source = C.ReagentPrice(rkey)
		local o = overrides and overrides[rkey]
		if o and (not price or o < price) then price, source = o, "deal" end
		parts[#parts + 1] = { key = rkey, name = rec.rn[rkey] or ns.History.GetName(rkey), count = count, price = price, source = source }
		if price then cost = cost + price * count else missing = true end
	end
	table.sort(parts, function(a, b) return (a.price or 0) * a.count > (b.price or 0) * b.count end)
	local value = rec.item and C.ResultValue(rec.item)
	local out = { cost = cost, missing = missing or rec.incomplete, parts = parts, value = value }
	if rec.item and value then
		-- few days of data, or usually only one listed: the sale price rests on very few listings
		local days = #ns.History.GetDaily(ns.History.GetItem(rec.item), nil, 14)
		local supply = ns.History.GetNormalSupply(rec.item)
		out.thin = days < 3 or (supply ~= nil and supply < 2)
		-- far above TSM's regional average: probably an asking price nobody pays
		local region = ns.Integrations.GetTSMPrice(rec.item, "dbregionmarketavg")
		if region and value > region * 2 then out.thin = true end
	end
	if value and not out.missing then
		out.net = value * (1 - AH_CUT) * (rec.made or 1)
		out.profit = out.net - cost
		out.margin = cost > 0 and out.profit / cost or nil
	end
	return out
end

-- Rows for the Crafting tab: favourite recipes (or all known ones).
function C.List(showAll)
	local favs = C.GetFavorites()
	local deals = DealPrices()
	local out = {}
	for id, rec in pairs(C.AllRecipes()) do
		local source = favs[id]
		if source or showAll then
			local base = C.Evaluate(rec)
			local withDeals = C.Evaluate(rec, deals)
			out[#out + 1] = {
				spellID = id, rec = rec, name = rec.n, prof = rec.prof, key = rec.item, fav = source,
				cost = base.cost, value = base.value, profit = base.profit, margin = base.margin, missing = base.missing, thin = base.thin,
				parts = base.parts, dealProfit = (withDeals.profit and base.profit and withDeals.profit > base.profit + 0.5) and withDeals.profit or nil,
			}
		end
	end
	return out
end

-- For a new deal: the favourite recipe it helps most, if crafting becomes (more) profitable.
function C.DealImpact(deal)
	local favs = C.GetFavorites()
	local best
	for id, rec in pairs(C.AllRecipes()) do
		if favs[id] and rec.r[deal.key] and rec.item then
			local before = C.Evaluate(rec)
			local after = C.Evaluate(rec, { [deal.key] = deal.unit })
			if after.profit and after.profit > 0 and (not before.profit or after.profit > before.profit)
				and (not best or after.profit > best.profit) then
				best = { spellID = id, name = rec.n, profit = after.profit, before = before.profit }
			end
		end
	end
	return best
end
