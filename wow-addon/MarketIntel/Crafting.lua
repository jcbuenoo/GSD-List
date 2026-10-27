-- Market Intel: crafting profit for your favourite recipes.
-- Recipes are learnt when you open a profession window. Only recipes starred
-- as favourites in TSM's crafting window are evaluated (plus any you star in
-- Market Intel's Crafting tab, as a backup if TSM's favourites can't be read).
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
	local prof = GetTradeSkillLine and GetTradeSkillLine() or "?"
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
	local prof = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or "Enchanting"
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
-- TSM keeps favourites in its saved variables (TradeSkillMasterDB) under a key
-- containing "favorite"; the values are recipe spell IDs or "c:<spellID>"
-- craft strings. TSM does not document this, so we read it defensively.
local tsmCache, tsmCacheAt
local function SpellIDFrom(v)
	if type(v) == "number" then return v end
	if type(v) == "string" then return tonumber(v:match("^c:(%d+)") or v:match("^(%d+)$")) end
	return nil
end

function C.GetTSMFavorites()
	local now = GetTime()
	if tsmCacheAt and now - tsmCacheAt < 10 then return tsmCache end
	tsmCacheAt = now
	tsmCache = nil
	local db = TradeSkillMasterDB
	if type(db) ~= "table" then return nil end
	local favs, found = {}, false
	for k, v in pairs(db) do
		if type(k) == "string" and k:lower():find("favorite", 1, true) and type(v) == "table" then
			found = true
			for fk, fv in pairs(v) do
				local id
				if fv == true then id = SpellIDFrom(fk) else id = SpellIDFrom(fv) or SpellIDFrom(fk) end
				if id then favs[id] = true end
			end
		end
	end
	if found then tsmCache = favs end
	return tsmCache
end

-- Favourite spell IDs and where they came from.
function C.GetFavorites()
	local favs, tsm = {}, C.GetTSMFavorites()
	for id in pairs(tsm or {}) do favs[id] = "TSM" end
	for id in pairs(Stars()) do favs[id] = favs[id] or "Market Intel" end
	return favs, tsm ~= nil
end

function C.ToggleStar(spellID)
	local stars = Stars()
	stars[spellID] = not stars[spellID] or nil
	ns.Fire("MI_DATA_UPDATED")
end

function C.IsStarred(spellID) return Stars()[spellID] == true end

---------------------------------------------------------------------------
-- Prices and profit
---------------------------------------------------------------------------
-- Price per reagent: TSM's material price (it knows vendor prices), else the
-- normal price from history (steadier than one search), else the latest
-- market value, else Auctionator.
function C.ReagentPrice(key)
	local tsm = ns.Integrations.GetTSMPrice(key, "matprice")
	if tsm then return tsm, "TSM" end
	local ref = ns.History.GetReference(key)
	if ref then return ref, "normal" end
	local latest = ns.History.GetLatest(key)
	if latest then return latest.mkt, "AH" end
	local a = ns.Integrations.GetAuctionatorPrice(key)
	if a then return a, "Auctionator" end
	return nil
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
	for spellID, rec in pairs(Recipes()) do
		local source = favs[spellID]
		if source or showAll then
			local base = C.Evaluate(rec)
			local withDeals = C.Evaluate(rec, deals)
			out[#out + 1] = {
				spellID = spellID, rec = rec, name = rec.n, prof = rec.prof, key = rec.item, fav = source,
				cost = base.cost, value = base.value, profit = base.profit, margin = base.margin, missing = base.missing,
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
	for spellID, rec in pairs(Recipes()) do
		if favs[spellID] and rec.r[deal.key] and rec.item then
			local before = C.Evaluate(rec)
			local after = C.Evaluate(rec, { [deal.key] = deal.unit })
			if after.profit and after.profit > 0 and (not before.profit or after.profit > before.profit)
				and (not best or after.profit > best.profit) then
				best = { spellID = spellID, name = rec.n, profit = after.profit, before = before.profit }
			end
		end
	end
	return best
end
