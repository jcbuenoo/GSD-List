-- Market Intel: price history and depth lines on item tooltips.
local _, ns = ...

local format = string.format

local function TrendText(change)
	if not change then return "" end
	if change >= 0.05 then return format(" |cff40ff40(+%d%% vs 7d)|r", change * 100 + 0.5) end
	if change <= -0.05 then return format(" |cffff5050(%d%% vs 7d)|r", change * 100 - 0.5) end
	return " |cffccccccsteady|r"
end

function ns.AddTooltipLines(tooltip, link)
	if not ns.settings or not ns.settings.tooltip or not link then return end
	local key = ns.ItemKeyFromLink(link)
	if not key then return end
	local stats = ns.History.GetStats(key)
	if not stats or not stats.latest then return end
	local l = stats.latest
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("|cff33ccffMarket Intel|r", format("|cffaaaaaaseen %s ago|r", ns.FormatAge(time() - l.t)))
	tooltip:AddDoubleLine("Min buyout / market", ns.FormatMoney(l.min) .. " / " .. ns.FormatMoney(l.mkt) .. TrendText(stats.change7), 1, 1, 1, 1, 1, 1)
	if stats.avg7 then
		tooltip:AddDoubleLine("7d / 30d average", ns.FormatMoney(stats.avg7) .. " / " .. ns.FormatMoney(stats.avg30), 1, 1, 1, 1, 1, 1)
	end
	local ref, source = ns.History.GetReference(key)
	if ref then
		tooltip:AddDoubleLine("Normal price (" .. source .. ")", ns.FormatMoney(ref), 1, 1, 1, 1, 1, 1)
	end
	local d = ns.Analysis.GetDepth(key)
	if d then
		local detail = format("%d auctions, %d sellers", l.auc, l.sel)
		if d.ratio then detail = detail .. format(", %.1fx supply", d.ratio) end
		tooltip:AddDoubleLine("Depth: " .. ns.Analysis.FormatRating(d.rating), detail, 1, 1, 1, 1, 1, 1)
		if d.war then tooltip:AddLine("|cffff5050Price war: the minimum keeps dropping.|r") end
	end
	local advice = ns.Advisor.PostPrice(key)
	if advice then
		tooltip:AddDoubleLine("Post at: " .. ns.Advisor.ACTION_TEXT[advice.action], ns.FormatMoney(advice.price), 1, 1, 1, 1, 1, 1)
	end
	local sales = ns.Ledger.ItemStats(ns.History.GetName(key))
	if sales then
		tooltip:AddDoubleLine("Your sales (30d)", format("%d sold, %d expired (%d%%)", sales.sold, sales.expired,
			sales.sellThrough * 100 + 0.5), 1, 1, 1, 1, 1, 1)
	end
	local cur = ns.current[key]
	if cur and cur.mine and cur.mine > 0 then
		tooltip:AddLine(format("|cffaaaaaaYou have %d listed.|r", cur.mine))
	end
	tooltip:Show()
end

local function OnTooltipSetItem(tooltip)
	local _, link = tooltip:GetItem()
	ns.AddTooltipLines(tooltip, link)
end

ns.On("MI_READY", function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnTooltipSetItem(tooltip) end
		end)
	else
		GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
		ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
	end
end)
