-- Randomized stress test: thousands of random actions in random order, checking
-- invariants after each one. Usage: lua5.1 tests/fuzz.lua [runs] [steps] [first seed]
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")

local RUNS, STEPS, SEED0 = tonumber(arg[1]) or 20, tonumber(arg[2]) or 400, tonumber(arg[3]) or 1
local DAY = 86400

local ITEMS = {
	{ "Netherweave Cloth", 21877, 2500, 1, 70 }, { "Primal Might", 23571, 1150000, 1, 70 },
	{ "Living Ruby", 23436, 2650000, 2, 70 }, { "Khorium Ore", 23426, 210000, 1, 70 },
	{ "Arcane Dust", 22445, 21000, 1, 70 }, { "Penny Item", 40001, 1, 1, 1 }, -- 1 copper
	{ "Huge Price", 40002, 99990000, 4, 70 }, -- 9,999g
	{ "Blade of Twinking", 30001, 2000000, 3, 29, "INVTYPE_WEAPON" },
	{ "Epic Cloak", 30002, 5000000, 4, 45, "INVTYPE_CLOAK" },
	{ "Felsteel Longblade of the Bear", 24689, 1234567, 2, 66, "INVTYPE_WEAPON", 1201 },
	{ "Grey Junk", 40003, 50, 0, 1 }, { "Weird \"Quoted\", Name", 40004, 33333, 1, 70 },
}

local function forbid()
	_G.PlaceAuctionBid = function() error("addon tried to buy") end
	_G.PostAuction = function() error("addon tried to post") end
	_G.StartAuction = function() error("addon tried to post") end
	_G.CancelAuction = function() error("addon tried to cancel") end
end

local function finite(x) return type(x) ~= "number" or (x == x and x ~= math.huge and x ~= -math.huge) end

local function checkInvariants(ns, where)
	assert(#M.errors == 0, where .. ": addon error: " .. tostring(M.errors[1]))
	for key, item in pairs(ns.realm.items) do
		for _, field in ipairs({ "s", "d" }) do
			local str = item[field]
			assert(type(str) == "string", where .. ": " .. key .. "." .. field .. " is not a string")
			if str ~= "" then
				local entries = select(2, str:gsub(";", "")) + 1
				local decoded = field == "s" and #ns.History.GetRaw(item) or #ns.History.GetDaily(item, M.now) -- days may merge raw
				if field == "s" then assert(decoded == entries, where .. ": " .. key .. " raw decode " .. decoded .. "/" .. entries) end
				assert(not str:find("[^%w,;]"), where .. ": bad characters in " .. key .. "." .. field)
			end
		end
		for _, snap in ipairs(ns.History.GetRaw(item)) do
			for k, v in pairs(snap) do assert(finite(v), where .. ": " .. key .. " snap." .. k .. " not finite") end
			assert(snap.min >= 0 and snap.mkt >= 0 and snap.qty >= 0, where .. ": negative snapshot " .. key)
		end
		for _, d in ipairs(ns.History.GetDaily(item, M.now)) do
			for k, v in pairs(d) do assert(finite(v), where .. ": " .. key .. " day." .. k .. " not finite") end
		end
		local d = ns.Analysis.GetDepth(key, M.now)
		assert(d == nil or ns.Analysis.RATING_TEXT[d.rating], where .. ": bad depth rating")
	end
	assert(#ns.deals <= 200 and #ns.snipes <= 200, where .. ": too many deals")
	for _, deal in ipairs(ns.deals) do
		assert(finite(deal.unit) and finite(deal.pct) and finite(deal.profit), where .. ": deal not finite")
		assert(deal.unit > 0, where .. ": deal with no price")
	end
	for _, f in ipairs(ns.Advisor.FindFlips(M.now)) do
		assert(f.profit >= ns.settings.flipMinProfit and finite(f.roi), where .. ": bad flip")
		assert(f.cost > 0 and f.qty > 0, where .. ": empty flip")
	end
end

local function run(seed)
	math.randomseed(seed)
	local R = math.random
	M.reset()
	forbid()
	for _, it in ipairs(ITEMS) do M.itemInfo[it[2]] = { name = it[1], equipLoc = it[6] or "" } end
	if R() < 0.5 then
		_G.TSM_API = { GetCustomPriceValue = function(src, item)
			local id = tonumber(item:match("i:(%d+)"))
			for _, it in ipairs(ITEMS) do
				if it[2] == id then
					if src == "dbregionsoldperday" then return (id % 5) / 4 end
					if src == "dbmarket" or src == "matprice" then return it[3] end
				end
			end
		end }
	end
	_G.TradeSkillMasterDB = R() < 0.5 and { ["c@x@favoriteCrafts"] = { ["c:31080"] = true } } or nil
	local saved
	local ns = M.LoadAddon("MarketIntel", nil)
	M.Tick(1)
	local log = {}

	local function addRandomAuctions(n)
		for _ = 1, n do
			local it = ITEMS[R(#ITEMS)]
			local factor = ({ 0.3, 0.55, 0.9, 1, 1, 1.05, 1.2, 3 })[R(8)]
			local count = ({ 1, 1, 5, 20, 200 })[R(5)]
			local unit = math.max(1, math.floor(it[3] * factor))
			table.insert(M.auctions, {
				name = it[1], id = it[2], count = count, buyout = R() < 0.05 and 0 or unit * count,
				owner = R() < 0.1 and M.player or ("Seller" .. R(12)), quality = it[4], level = it[5], suffix = it[7],
				uncached = R() < 0.03 or nil, minBid = math.max(1, unit * count - 1),
			})
		end
	end

	local actions = {
		function() addRandomAuctions(R(30)) return "add auctions" end,
		function() -- auctions sell or expire
			for _ = 1, R(10) do if #M.auctions > 0 then table.remove(M.auctions, R(#M.auctions)) end end
			return "remove auctions"
		end,
		function()
			if not M.ahOpen then return "skip search (AH closed)" end
			local it = ITEMS[R(#ITEMS)]
			local page = R() < 0.7 and 0 or R(0, 2)
			if M.gt - M.lastQuery < M.ahThrottle then return "skip (throttled)" end
			QueryAuctionItems(R() < 0.8 and it[1] or "", nil, nil, page, false, nil, false, R() < 0.5)
			M.Tick(R() * 3)
			return "search " .. it[1] .. " p" .. page
		end,
		function()
			if not M.ahOpen then return "skip full scan" end
			if M.gt - M.lastQuery < M.ahThrottle then return "skip full scan (throttled)" end
			QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
			M.Tick(R() < 0.8 and 6 or 0.05) -- sometimes interrupted by the next action
			return "full scan"
		end,
		function()
			if M.ahOpen then M.CloseAH() return "close AH" end
			M.mapID = R() < 0.2 and 1446 or 1453
			M.OpenAH() return "open AH map " .. M.mapID
		end,
		function()
			local jump = ({ 60, 600, 3600, 6 * 3600, DAY, 3 * DAY, 25 * DAY })[R(7)]
			M.now = M.now + jump
			M.Tick(1)
			return "time +" .. jump
		end,
		function() -- relog: save variables to text and load them back
			saved = M.Serialize(MarketIntelDB)
			local tsm, tsmdb = _G.TSM_API, _G.TradeSkillMasterDB
			local now, auctions, infos = M.now, M.auctions, M.itemInfo
			M.reset()
			forbid()
			M.now, M.auctions, M.itemInfo, _G.TSM_API, _G.TradeSkillMasterDB = now, auctions, infos, tsm, tsmdb
			ns = M.LoadAddon("MarketIntel", M.Deserialize(saved))
			M.Tick(2)
			return "relog"
		end,
		function()
			M.mail = {}
			for _ = 1, R(6) do
				local it = ITEMS[R(#ITEMS)]
				local kind = ({ "sold", "bought", "expired", "cancelled", "junk" })[R(5)]
				local m = { daysLeft = 30 - R() * 29, money = it[3] }
				if kind == "sold" then
					m.subject = "Auction successful: " .. it[1]
					m.invoice = { type = "seller", item = it[1], player = "B" .. R(3), bid = it[3] * 2, buyout = it[3] * 2, deposit = 0, cut = math.floor(it[3] * 0.1) }
				elseif kind == "bought" then
					m.subject = "Auction won: " .. it[1]
					m.invoice = { type = "buyer", item = it[1], player = "S" .. R(3), bid = it[3], buyout = it[3] }
					m.item = { name = it[1], id = it[2], count = R(20) }
				elseif kind == "junk" then
					m.subject = "Hi " .. R(100)
				else
					m.subject = (kind == "expired" and "Auction expired: " or "Auction cancelled: ") .. it[1]
					m.item = { name = it[1], id = it[2], count = R(20) }
				end
				table.insert(M.mail, m)
			end
			M.FireEvent("MAIL_INBOX_UPDATE"); M.Tick(1)
			return "mail x" .. #M.mail
		end,
		function()
			M.tradeskill = { line = "Jewelcrafting", recipes = {
				{ name = "Bold Living Ruby", spell = 31080, item = { id = 23436, name = "Living Ruby" }, reagents = { { id = 23436, name = "Living Ruby", count = 1 } } },
				{ name = "Bolt", spell = 26751, item = { id = 21843, name = "Bolt of Imbued Netherweave" },
					reagents = { { id = 21877, name = "Netherweave Cloth", count = 6 }, { id = 22445, name = "Arcane Dust", count = 2 } } },
			} }
			M.FireEvent("TRADE_SKILL_SHOW"); M.Tick(1)
			if R() < 0.5 then ns.Crafting.ToggleStar(26751) end
			return "tradeskill"
		end,
		function() -- click around the UI
			local tabs = { "deals", "snipe", "flips", "depth", "history", "crafting", "ledger", "watch", "settings" }
			local tab = tabs[R(#tabs)]
			ns.UI.Show(tab)
			local page = ns.UI.GetPage(tab)
			if page.list then
				local list = page.list
				if R() < 0.5 then list.headers[R(#list.headers)]:Click() end
				_G[list.scroll:GetName() .. "ScrollBar"]:SetValue(R(0, 40) * 18)
				local row = list.rows[R(#list.rows)]
				if row:IsShown() then
					row:GetScript("OnEnter")(row)
					M.shift = R() < 0.2
					if R() < 0.7 and (tab ~= "watch" or R() < 0.5) then row:Click(R() < 0.8 and "LeftButton" or "RightButton") end
					M.shift = nil
				end
			end
			for _, c in ipairs(page._children) do
				if c._kind == "Button" and (c:GetText() == "CSV" or c:GetText() == "CSV all") and R() < 0.3 then
					c:Click()
					ns.Export.GetFrame():Hide()
				end
			end
			if R() < 0.3 then ns.UI.Toggle() end
			return "UI " .. tab
		end,
		function() -- random setting through its edit box
			ns.UI.Show("settings")
			local controls = ns.UI.GetPage("settings").controls
			local c = controls[R(#controls)]
			if c.SetChecked then
				c:SetChecked(not c:GetChecked()); c:Click()
			else
				c:SetFocus()
				c:SetText(({ "0", "1", "-5", "abc", "999999", "0.5", "", "3", "60" })[R(9)])
				c:ClearFocus()
			end
			return "setting " .. c.def.key
		end,
		function()
			local cmds = { "", "deals", "bags", "stats", "purge", "help", "post Primal Might", "watch Primal Might 50g",
				"unwatch Primal Might", "watch Living Ruby", "scan", "snipe", "import", "minimap", "post Nothing At All", "watch" }
			SlashCmdList.MARKETINTEL(cmds[R(#cmds)])
			M.Tick(R() * 5)
			return "slash"
		end,
		function() M.ahThrottle = ({ 0, 0.3, 1 })[R(3)]; M.Tick(R() * 10) return "tick" end,
		function() GameTooltip:SetHyperlink(M.Link(ITEMS[R(#ITEMS)][2], "x")) return "tooltip" end,
	}

	for step = 1, STEPS do
		local idx = R(#actions)
		local okAct, name = xpcall(actions[idx], debug.traceback)
		if not okAct then
			local tail = {}
			for i = math.max(1, #log - 8), #log do tail[#tail + 1] = log[i] end
			return false, string.format("step %d action #%d crashed: %s\n    last actions: %s", step, idx, name, table.concat(tail, " > "))
		end
		log[#log + 1] = name
		local ok, err = pcall(checkInvariants, ns, string.format("seed %d step %d (%s)", seed, step, name))
		if not ok then
			local tail = {}
			for i = math.max(1, #log - 8), #log do tail[#tail + 1] = log[i] end
			return false, err .. "\n    last actions: " .. table.concat(tail, " > ")
		end
	end
	-- final relog round-trip must keep everything readable
	local text = M.Serialize(MarketIntelDB)
	assert(M.Deserialize(text), "saved variables do not load")
	return true, #text
end

local failures, maxSize = 0, 0
local t0 = os.clock()
for seed = SEED0, SEED0 + RUNS - 1 do
	local ok, passed, detail = pcall(run, seed)
	if not ok or not passed then
		failures = failures + 1
		print("FAIL seed " .. seed .. ": " .. tostring(ok and detail or passed))
	else
		maxSize = math.max(maxSize, detail)
	end
end
print(string.format("fuzz: %d runs x %d steps, %d failed, %.1fs, largest saved data %d KB",
	RUNS, STEPS, failures, os.clock() - t0, maxSize / 1024))
os.exit(failures == 0 and 0 or 1)
