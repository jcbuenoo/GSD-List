-- Market Intel: BoE snipe. Flags rare and epic gear (required level 15-55 by
-- default) that TSM says sells regularly across the region, listed well
-- below its normal price. Checked on every search and full scan, and by the
-- dedicated BoE snipe scan. Suggestions only: nothing is ever bought.
local _, ns = ...

local SN = {}
ns.Snipe = SN
ns.snipes = {} -- newest first, this session only

local index = {}
local MAX_SNIPES = 200
-- equippable but not what people snipe as gear
local NOT_GEAR = { INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_NON_EQUIP = true, [""] = true }

local function EquipLoc(itemId)
	if GetItemInfoInstant then
		local _, _, _, equipLoc = GetItemInfoInstant(itemId)
		if equipLoc then return equipLoc end
	end
	return (select(9, GetItemInfo(itemId)))
end

function SN.IsGear(itemId)
	local loc = itemId and EquipLoc(itemId)
	return loc ~= nil and not NOT_GEAR[loc]
end

-- Normal price and regional sale rate for a gear item.
-- Returns ref, source, soldPerDay (soldPerDay is nil without TSM region data).
function SN.Reference(itemId, key)
	local tsmKey = tostring(itemId)
	local sold = ns.Integrations.GetTSMPrice(tsmKey, "dbregionsoldperday")
	local ref = ns.Integrations.GetTSMPrice(tsmKey, "dbmarket")
	if ref then return ref, "TSM market", sold end
	ref = ns.Integrations.GetTSMPrice(tsmKey, "dbregionmarketavg")
	if ref then return ref, "TSM region", sold end
	ref = ns.History.GetReference(key)
	if ref then return ref, "history", sold end
	return nil, nil, sold
end

local function SnipeId(key, l)
	return string.format("%s|%d|%d|%s", key, l.buyout, l.count, l.owner or "?")
end

-- Called for every item in every saved search. listings are sorted by unit price.
-- Returns the set of auction ids that are snipes (so they are not also reported as deals).
local NONE = {}
function SN.Check(key, listings, now, out)
	local s = ns.settings
	if not s.snipeEnabled then return NONE end
	local first = listings[1]
	if (first.quality or 0) < s.snipeMinQuality or not first.level then return NONE end
	if first.level < s.snipeMinLevel or first.level > s.snipeMaxLevel then return NONE end
	if not SN.IsGear(first.itemId) then return NONE end
	local ref, source, sold = SN.Reference(first.itemId, key)
	if not ref then return NONE end
	if s.snipeRequireSaleRate and (not sold or sold < s.snipeMinSold) then return NONE end
	local ids = {}
	local limit = ref * s.snipePct / 100
	for _, l in ipairs(listings) do
		if l.unit > limit then break end
		if not l.mine then
			local id = SnipeId(key, l)
			ids[id] = true
			if index[id] then
				index[id].t = now
			else
				local snipe = {
					id = id, key = key, name = l.name, level = l.level, quality = l.quality, unit = l.unit,
					count = l.count, buyout = l.buyout, owner = l.owner, ref = ref, source = source, sold = sold,
					pct = l.unit / ref, profit = (ref - l.unit) * l.count, t = now, found = now,
				}
				table.insert(ns.snipes, 1, snipe)
				index[id] = snipe
				if out then out[#out + 1] = snipe end
				while #ns.snipes > MAX_SNIPES do
					local old = table.remove(ns.snipes)
					index[old.id] = nil
				end
			end
		end
	end
	return ids
end

-- After a complete search of an item, drop snipes that are gone (sold or cancelled).
function SN.Prune(key, listings)
	local live = {}
	for _, l in ipairs(listings) do live[SnipeId(key, l)] = true end
	for i = #ns.snipes, 1, -1 do
		local sn = ns.snipes[i]
		if sn.key == key and not live[sn.id] then
			table.remove(ns.snipes, i)
			index[sn.id] = nil
		end
	end
end

function SN.Clear()
	wipe(ns.snipes)
	wipe(index)
end

function SN.Alert(list)
	if not list or #list == 0 then return end
	local lines = {}
	for _, sn in ipairs(list) do
		lines[#lines + 1] = string.format("|cffff8000BOE SNIPE|r %s (lvl %d) at %s, %s of %s, sells %s/day",
			ns.GetItemLinkForKey(sn.key, sn.name, sn.quality), sn.level, ns.FormatMoney(sn.unit),
			ns.FormatPct(sn.pct), ns.FormatMoney(sn.ref), sn.sold and string.format("%.2f", sn.sold) or "?")
	end
	ns.Alerts.Notify("snipe", lines, true, string.format("BoE snipe: %s", list[1].name))
end

-- Search rare and epic items in the level range, every page.
function SN.Scan()
	local s = ns.settings
	local queries = {}
	for q = s.snipeMinQuality, 4 do
		queries[#queries + 1] = { name = "", minLevel = s.snipeMinLevel, maxLevel = s.snipeMaxLevel, rarity = q }
	end
	local before = #ns.snipes
	return ns.Scanner.RunQueries("BoE snipe scan", queries, function(cancelled)
		if not cancelled then
			ns.Print("BoE snipe scan finished: %d snipes found.", #ns.snipes - before)
		end
	end)
end
