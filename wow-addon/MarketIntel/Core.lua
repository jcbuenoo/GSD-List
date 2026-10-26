-- Market Intel: core namespace, saved variables, utilities, scheduler and slash commands.
local ADDON, ns = ...

ns.name = ADDON or "MarketIntel"
ns.version = "1.1.0"

local floor, format, tostring, tonumber, type, pairs = math.floor, string.format, tostring, tonumber, type, pairs

ns.DEFAULTS = {
	dealPct = 60,            -- a listing is a deal when its unit buyout is <= this % of the normal price
	minDealProfit = 20000,   -- copper; ignore deals that save less than this per auction (2g)
	minHistoryDays = 3,      -- days of history required before we trust our own normal price
	alertChat = true,
	alertSound = true,
	tooltip = true,
	rawDays = 2,             -- keep every snapshot this many days, then fold into daily summaries
	keepDays = 60,           -- history kept for items you search or watch
	scanKeepDays = 21,       -- history kept for items only ever seen in full scans
	minQuality = 1,          -- skip grey (poor) items
	replaceWindow = 1800,    -- seconds; a new snapshot this close to the previous one replaces it
	floodRatio = 2.0,        -- supply vs normal at which an item is "Flooded"
	crowdRatio = 1.4,
	thinRatio = 0.5,
	floodSellers = 15,
	crowdSellers = 8,
	useTSMFallback = true,   -- use TSM DBMarket as the normal price while our own history is too short
}

local DB_VERSION = 2 -- version 2: compact base-36 history strings

---------------------------------------------------------------------------
-- Printing / formatting
---------------------------------------------------------------------------
function ns.Print(msg, ...)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffMarket Intel:|r " .. tostring(msg))
end

local function BreakUp(n)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

-- Compact money text: "12g 30s", "45s 10c", "8c".
function ns.FormatMoney(copper)
	if not copper then return "|cff808080--|r" end
	copper = floor(copper + 0.5)
	local neg = copper < 0
	if neg then copper = -copper end
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local text
	if g > 0 then
		text = format("%s|cffffd700g|r %d|cffc7c7cfs|r", BreakUp(g), s)
	elseif s > 0 then
		text = format("%d|cffc7c7cfs|r %d|cffeda55fc|r", s, c)
	else
		text = format("%d|cffeda55fc|r", c)
	end
	return neg and ("-" .. text) or text
end

-- Parse "12g", "12.5", "12g 30s", "30s", "5c" into copper. A bare number means gold.
function ns.ParseMoney(text)
	if not text then return nil end
	text = text:lower():gsub("[%s,]+", "")
	if text == "" then return nil end
	local bare = tonumber(text)
	if bare then return floor(bare * 10000 + 0.5) end
	local total, matched = 0, false
	for num, unit in text:gmatch("([%d%.]+)([gsc])") do
		local v = tonumber(num)
		if not v then return nil end
		matched = true
		if unit == "g" then total = total + v * 10000
		elseif unit == "s" then total = total + v * 100
		else total = total + v end
	end
	if not matched then return nil end
	-- reject leftover junk such as "12gx"
	if text:gsub("[%d%.]+[gsc]", "") ~= "" then return nil end
	return floor(total + 0.5)
end

function ns.FormatAge(seconds)
	if not seconds then return "?" end
	if seconds < 60 then return "now" end
	if seconds < 3600 then return format("%dm", floor(seconds / 60)) end
	if seconds < 86400 then return format("%dh", floor(seconds / 3600)) end
	return format("%dd", floor(seconds / 86400))
end

function ns.FormatPct(ratio)
	if not ratio then return "--" end
	return format("%d%%", floor(ratio * 100 + 0.5))
end

---------------------------------------------------------------------------
-- Item keys: "itemID" or "itemID:suffixID" for random-suffix items ("of the Bear")
---------------------------------------------------------------------------
function ns.ItemKeyFromLink(link)
	if type(link) ~= "string" then return nil end
	local itemString = link:match("item:([%-%d:]+)")
	if not itemString then return nil end
	local fields = {}
	for v in (itemString .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = v end
	local id = tonumber(fields[1])
	if not id then return nil end
	local suffix = tonumber(fields[7]) or 0
	if suffix ~= 0 then return id .. ":" .. suffix end
	return tostring(id)
end

function ns.ItemIDFromKey(key)
	return tonumber((tostring(key):match("^(%d+)")))
end

function ns.ItemStringFromKey(key)
	local id, suffix = tostring(key):match("^(%d+):?(%-?%d*)$")
	if not id then return nil end
	if suffix and suffix ~= "" then
		return format("item:%s:0:0:0:0:0:%s", id, suffix)
	end
	return "item:" .. id
end

-- Best available link for a key, falling back to a coloured name.
function ns.GetItemLinkForKey(key, name, quality)
	local _, link = GetItemInfo(ns.ItemStringFromKey(key) or 0)
	if link then return link end
	name = name or ("item " .. tostring(key))
	local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then return color.hex .. name .. "|r" end
	return name
end

function ns.GetItemIcon(key)
	local id = ns.ItemIDFromKey(key)
	if not id then return nil end
	if GetItemIcon then return GetItemIcon(id) end
	return (select(10, GetItemInfo(id)))
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function ns.Median(list)
	local n = #list
	if n == 0 then return nil end
	local copy = {}
	for i = 1, n do copy[i] = list[i] end
	table.sort(copy)
	if n % 2 == 1 then return copy[(n + 1) / 2] end
	return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

-- Local calendar day as YYYYMMDD. date() is slow, so results are cached per
-- 15 minutes (every real time zone changes date on a 15-minute boundary).
local dayKeyCache = {}
function ns.DayKey(t)
	local bucket = floor(t / 900)
	local day = dayKeyCache[bucket]
	if not day then
		day = tonumber(date("%Y%m%d", bucket * 900))
		dayKeyCache[bucket] = day
	end
	return day
end

-- Noon of a YYYYMMDD day, as a timestamp (used for weekday maths and day ages).
function ns.DayToTime(day)
	local y, m, d = floor(day / 10000), floor(day / 100) % 100, day % 100
	return time({ year = y, month = m, day = d, hour = 12 })
end

---------------------------------------------------------------------------
-- Events and scheduler
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^MI_") then eventFrame:RegisterEvent(event) end
	end
	table.insert(handlers[event], fn)
end

function ns.Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then geterrorhandler()(err) end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

local timers = {}
function ns.After(delay, fn)
	local t = { at = GetTime() + delay, fn = fn }
	timers[#timers + 1] = t
	return t
end

function ns.Cancel(timer)
	if timer then timer.cancelled = true end
end

local tasks = {} -- functions called every frame until they return true
function ns.RunTask(fn)
	tasks[#tasks + 1] = fn
end

-- Per-frame time budget for background work, in milliseconds.
local clock = debugprofilestop or function() return GetTime() * 1000 end
local FRAME_BUDGET = 8
local budgetStart = 0
function ns.OverBudget()
	return clock() - budgetStart > FRAME_BUDGET
end

-- Run fn(yield) as a background job that pauses whenever the frame budget is
-- used up and continues next frame. onDone(ok) runs when it finishes.
function ns.RunJob(fn, onDone)
	local co = coroutine.create(fn)
	ns.RunTask(function()
		budgetStart = clock()
		local ok, err = coroutine.resume(co, coroutine.yield)
		if not ok then
			geterrorhandler()(err)
			if onDone then onDone(false) end
			return true
		end
		if coroutine.status(co) == "dead" then
			if onDone then onDone(true) end
			return true
		end
		return false
	end)
end

function ns.StartFrameBudget()
	budgetStart = clock()
end

-- Inside a job: give the frame back if the budget is used up.
function ns.Checkpoint(yield)
	if yield and ns.OverBudget() then yield() end
end

eventFrame:SetScript("OnUpdate", function()
	local now = GetTime()
	for i = #timers, 1, -1 do
		local t = timers[i]
		if t.cancelled then
			table.remove(timers, i)
		elseif now >= t.at then
			table.remove(timers, i)
			local ok, err = pcall(t.fn)
			if not ok then geterrorhandler()(err) end
		end
	end
	for i = #tasks, 1, -1 do
		local ok, done = pcall(tasks[i])
		if not ok then
			geterrorhandler()(done)
			table.remove(tasks, i)
		elseif done then
			table.remove(tasks, i)
		end
	end
end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
-- Gadgetzan, Booty Bay and Everlook share a neutral auction house with its own prices.
local NEUTRAL_MAPS = { [1446] = true, [1434] = true, [1452] = true }

function ns.GetAuctionHouseKey()
	local faction = UnitFactionGroup("player") or "Unknown"
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		if ok and mapID and NEUTRAL_MAPS[mapID] then faction = "Neutral" end
	end
	return (GetRealmName() or "Unknown") .. "-" .. faction
end

function ns.InitDB()
	if type(MarketIntelDB) ~= "table" then MarketIntelDB = {} end
	local db = MarketIntelDB
	if db.version ~= DB_VERSION then
		db.realms = nil -- older test builds used a different history format
		db.version = DB_VERSION
	end
	db.settings = db.settings or {}
	for k, v in pairs(ns.DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	db.realms = db.realms or {}
	db.watch = db.watch or {}
	ns.db = db
	ns.settings = db.settings
	ns.SetAuctionHouse(ns.GetAuctionHouseKey())
end

function ns.SetAuctionHouse(key)
	local db = ns.db
	db.realms[key] = db.realms[key] or { items = {} }
	ns.realmKey = key
	ns.realm = db.realms[key]
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
	if name ~= ns.name then return end
	ns.InitDB()
end)

ns.On("PLAYER_LOGIN", function()
	if not ns.db then ns.InitDB() end
	ns.playerName = UnitName("player")
	ns.SetAuctionHouse(ns.GetAuctionHouseKey())
	ns.History.Compact(time(), true)
	ns.Fire("MI_READY")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
	"/mi - open or close the window",
	"/mi deals | depth | history | watch | settings - open a tab",
	"/mi watch <item link or name> [max price, e.g. 12g] - add to watchlist",
	"/mi unwatch <item link or name> - remove from watchlist",
	"/mi scan - scan your watchlist (auction house must be open)",
	"/mi bags - market depth check for items in your bags",
	"/mi stats - how much data is stored",
	"/mi import - copy Auctionator's price history into Market Intel",
	"/mi purge - compact old data now",
	"/mi reset - delete all price history for this auction house",
}

-- Split "<link or name> [price]" where the name may contain spaces.
function ns.ParseItemAndPrice(rest)
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "" then return nil end
	local link, after = rest:match("^(|c%x+|Hitem:.-|h.-|h|r)%s*(.*)$")
	local name
	if link then
		name = link:match("|h%[(.-)%]|h")
	else
		-- a trailing token that parses as money is the price
		local head, tail = rest:match("^(.-)%s+(%S+)$")
		if head and ns.ParseMoney(tail) then
			name, after = head, tail
		else
			name, after = rest, ""
		end
	end
	return name, ns.ParseMoney(after), link
end

function ns.HandleSlash(input)
	input = input or ""
	local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "deals" or cmd == "depth" or cmd == "history" or cmd == "settings" then
		ns.UI.Show(cmd)
	elseif cmd == "watch" and rest == "" then
		ns.UI.Show("watch")
	elseif cmd == "watch" then
		local name, maxPrice = ns.ParseItemAndPrice(rest)
		if not name then return ns.Print("usage: /mi watch <item> [max price]") end
		ns.Watch.Add(name, maxPrice)
	elseif cmd == "unwatch" then
		local name = ns.ParseItemAndPrice(rest)
		if name and ns.Watch.Remove(name) then
			ns.Print("removed %s from the watchlist.", name)
		else
			ns.Print("%s is not on the watchlist.", tostring(name))
		end
	elseif cmd == "scan" then
		ns.Scanner.ScanWatchlist()
	elseif cmd == "bags" then
		ns.Analysis.PrintBagReport()
	elseif cmd == "stats" then
		local items, snaps, days = ns.History.CountData()
		ns.Print("%s: %d items, %d recent snapshots, %d daily summaries.", ns.realmKey, items, snaps, days)
	elseif cmd == "import" then
		ns.Integrations.ImportAuctionator(true)
	elseif cmd == "purge" then
		ns.History.Compact(time())
		ns.Print("old data compacted.")
	elseif cmd == "reset" then
		StaticPopup_Show("MARKETINTEL_RESET")
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end

SLASH_MARKETINTEL1 = "/mi"
SLASH_MARKETINTEL2 = "/marketintel"
SlashCmdList.MARKETINTEL = function(msg) ns.HandleSlash(msg) end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs.MARKETINTEL_RESET = {
	text = "Delete all Market Intel price history for this auction house?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		ns.realm.items = {}
		ns.History.ResetIndex()
		ns.Fire("MI_DATA_UPDATED")
		ns.Print("price history for %s deleted.", ns.realmKey)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
