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
