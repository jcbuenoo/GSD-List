# Market Intel (WoW TBC Classic addon)

Market Intel records auction house prices over time and uses them to flag bargains and crowded markets. It works alongside **Auctionator** and **TradeSkillMaster** and doesn't replace either one.

It never buys, posts or cancels anything: it records prices and makes suggestions.

- **Price history:** a daily record of every item you see on the AH, with charts, averages, trend, volatility and the best weekday to sell or buy.
- **Deal alerts:** listings far below the item's normal price, plus your own watchlist price targets.
- **BoE snipe:** blue/epic gear (required level 15-55) that sells regularly in your region, listed well below its normal price.
- **Flip finder:** cheap auctions you could buy and relist, with profit, return and risk.
- **Posting price advisor:** what to post at (or whether to hold), per item.
- **Market depth warnings:** whether a market is Flooded, Crowded, Normal or Thin, plus price-war and price-wall detection.
- **Crafting profit** for the recipes you starred in TSM, including what current deals on materials do to the profit.
- **Sales ledger:** sales, purchases, expired and cancelled auctions read from your mail.
- **Minimap button, CSV export, and big on-screen alerts** for the best finds.

`MarketIntel/README.txt` (inside the zip) is the short player guide; this file also covers how it works and the test tools.

## Install

1. Download `dist/MarketIntel-1.3.1.zip` and unzip it into `World of Warcraft/_anniversary_/Interface/AddOns/`. It unpacks into a `MarketIntel` folder. The client folder may be named differently, such as `_classic_`.
2. Restart the game. If the addon shows as "out of date", tick **Load out of date AddOns** on the character-select AddOns screen. To see your client's interface number, run `/dump select(4, GetBuildInfo())`. Then update the `## Interface:` line in `MarketIntel.toc` to match.

## Getting data

You don't need to do anything special. Every time the auction house shows results, Market Intel reads them. That includes your own searches, Auctionator's shopping lists, Auctionator's **Full Scan**, TSM searches and the default Browse tab.

- **Full scan** (best). Auctionator's full scan reads the whole AH in one go, about once every 15 minutes. Market Intel reads and saves those results in the background, using about 8 ms per frame, so the game doesn't freeze.
- **Normal searches.** Pages of the same search are merged. If you only looked at page 1 of 3, that snapshot is marked *partial*: its prices are used, but its supply numbers are not.
- **Watchlist scan.** `/mi scan`, or the button on the Watchlist tab, searches each watched item by exact name, every page.

Each auction house is tracked separately: your faction's AH, plus the neutral AH in Gadgetzan, Booty Bay and Everlook.

### Starting with Auctionator's history
Auctionator already keeps a record of the lowest price it saw each day. The first time you log in with no Market Intel data, the addon copies that history over automatically, so normal prices and deal alerts work from day one instead of after 3 days. You can run it again any time with `/mi import` or the **Import from Auctionator** button in Settings.

- Days Market Intel already has are never overwritten.
- Auctionator only records prices and quantity, not sellers. Imported days count toward the normal price and normal supply.
- Gear that Auctionator tracks per item level is skipped.
- Both of Auctionator's storage formats are read: the packed (CBOR) format of Auctionator's database version 8 and later, and the older plain table. This was checked against a real Auctionator file.
- If the format isn't recognized, the import says so and changes nothing.
- It runs once per auction house, even if you have already scanned there.

## How it works

### Price history
For every item and every scan, Market Intel stores:

- the minimum buyout;
- the **market value**: the average price of the cheapest 25% of units on sale, ignoring anything priced over 1.5× the cheapest;
- units on sale, auctions, sellers;
- the "wall": units within 5% of the minimum.

Every scan is kept for 2 days, then merged into one summary per day. Searching the same item again within 30 minutes replaces the snapshot instead of adding another.

How long daily history is kept depends on how the item was seen:

- items you **searched for or watch**: 60 days;
- items only ever seen in **full scans**: 21 days.

Both can be changed in Settings. With these defaults, a big server where 10,000 items show up in full scans every day uses about 8 MB of saved data after a month.

**History tab:** search for an item to see:

- a daily chart (bar = market value, yellow mark = lowest price that day, blue line = normal price; green or red bars are more than 10% below or above normal);
- latest min and market, 7-day and 30-day averages, 30-day low and high, today vs the 7-day average, and the average daily swing;
- Auctionator's and TSM's prices next to Market Intel's;
- the best weekday to sell and to buy, once there are 14 days of data.

**Tooltips:** item tooltips show min/market with trend, the 7d/30d averages, the normal price, the depth rating, and how many you have listed.

### Deal alerts
- The **normal price** is the median daily market value over the last 14 days, not counting today, so a crash today can't lower the bar. With an even number of days it takes the lower middle value, so two days of one silly listing can't drag it halfway up. It needs at least 3 days of history. Until then, TSM's `DBMarket` is used if TSM is installed.
- A listing is a **deal** when its unit price is at or below **60%** of normal *and* buying it saves at least **2g**. Both numbers can be changed in Settings. Your own auctions are never flagged.
- **Watchlist targets** alert whenever an item is at or below your price, even with no history: `/mi watch Khorium Ore 20g`.
- New deals print in chat (up to 5 at once) and play a sound (at most once every 3 seconds). The same listing never alerts twice. When a later full search shows a deal has sold, it's removed from the Deals tab.
- **Deals tab:** click a row to search that item. With Auctionator installed this uses its shopping tab, otherwise the default Browse tab. Shift-click links the item in chat. Buying is always done by you; addons are not allowed to buy automatically.

### Market depth
Each item is compared with its own typical supply: the median units on sale per day over 14 days.

| Rating | When |
|---|---|
| **Flooded** | 15+ sellers, or 2× normal supply |
| **Crowded** | 8+ sellers, or 1.4× normal supply |
| **Thin** | 2 or fewer auctions, or half the normal supply (good time to post) |
| **Normal** | everything else |
| **Unknown** | only part of the search was seen |

It also flags:

- **Price war:** the minimum fell 15%+ across 3 or more scans within 24 hours, with 4+ sellers.
- **Wall:** half or more of the units sit within 5% of the minimum.

**Depth tab:** filter to *items in my bags* or *only warnings*. Hovering a row shows the 5 cheapest price levels, plus how many units sit below 90% of normal and what buying them would cost. `/mi bags` prints the same check in chat.

### BoE snipe
Every search and full scan is checked for gear that:

- is rare (blue) or epic, with a required level of 15-55;
- TSM says sells at least 0.1 a day per auction house in your region (`DBRegionSoldPerDay`);
- is listed at or below 65% of its normal price: TSM `DBMarket`, then `DBRegionMarketAvg`, then Market Intel's own history.

The **Scan BoE** button (or `/mi snipe`) searches that whole category page by page: rare, then epic, levels 15-55. An auction that is a snipe is reported only as a snipe, not also as a deal. Snipes always get the big alert. Without TSM's region data nothing qualifies, unless you untick *Snipes need TSM sale rate*.

### Flip finder
For each item searched in the last 2 hours, it works out how many of the cheapest auctions you could buy and relist just under the next price (never above the normal price):

- **Profit** is counted after the 5% AH cut and 24-hour deposits.
- **Shown only if** it makes at least 5g and a 15% return.
- **Never more than the market normally holds**, or a week of TSM's regional sales.
- **Risk** is Low with sales evidence (TSM or your own ledger), Medium without, and High in crowded markets. Flooded markets are skipped.

It only suggests; clicking a row just searches the item.

### Posting price advisor
Shown as **Post at** on tooltips and the Depth tab, and with `/mi post <item>`:

- **Undercut** the cheapest auction by 1 copper in a normal market.
- **Hold** when the cheapest price is below 85% of normal. A little cheap stock (at most 15% of the units listed, or 3 units) is ignored, and you undercut the next fair price instead.
- **Hold** in a Flooded market unless your ledger shows you sell at least 60% of what you post.
- **Post high** in a Thin market, or 10% above normal when nobody else is selling.
- **Vendor it** when the auction price after the cut is no better than a vendor's.

### Crafting profit
- **Learning recipes:** opening a profession window records each recipe's materials and result (Enchanting too).
- **Which recipes:** only recipes starred as favourites in TSM's crafting window are evaluated, for your realm and faction. Market Intel reads them from TSM's saved data (`isCraftFavorite` and TSM's recipe list), so you don't even need to open your profession windows. This was checked against a real TSM file: all 51 favourites matched. If TSM's data is missing, right-click recipes in the Crafting tab to star them there instead.
- **Material cost:** TSM's `MatPrice` if available. Otherwise the cheaper of the vendor price (from Auctionator's vendor price cache) and the AH: the normal price, else the latest market value, else Auctionator.
- **Thin markets:** a yellow **?** next to the profit means the result item has under 3 days of prices, usually only one listed, or a price more than double TSM's regional average. The "price" may be one seller's asking price.
- **Sale price:** the cheapest current auction of the result, minus the 5% cut.
- **Deals:** when a deal lowers a material's cost, the Deals tab and the alert show what that recipe would make.

### Sales ledger
When you open your mailbox, auction mail is recorded once each: sold, won, expired and cancelled.

- **Sold:** sale price, AH cut and buyer. The quantity comes from your own auction list (open the AH *Auctions* tab before collecting).
- **Won and returned:** quantities come from the attached items.
- **Summary:** sales, AH cut, purchases, net profit and sell-through for 7 days, 30 days or everything. Kept for 180 days.

### Alerts, minimap, CSV
- **Alerts:** every find prints in chat and plays a sound (both sounds can be chosen). Big finds also show a raid-warning style message on screen and flash the taskbar icon. Big finds are BoE snipes, watchlist hits and deals saving 20g or more.
- **Minimap button:** left-click opens the window, right-click opens Settings, drag moves it. A red number shows alerts since you last opened the window.
- **CSV export:** every list has a **CSV** button. It opens the data as CSV, ready to copy with Ctrl+C into a spreadsheet.

## Commands

```
/mi                      open or close the window (there is also a button next to the AH window)
/mi deals|depth|history|watch|settings
/mi watch <item or shift-click link> [max price, e.g. 12g or 12g50s]
/mi unwatch <item>
/mi scan                 scan the watchlist (AH must be open)
/mi bags                 depth check for your bags
/mi import               copy Auctionator's price history
/mi snipe                BoE snipe scan (AH open)
/mi flips | crafting | ledger
/mi post <item>          suggested posting price
/mi minimap              show or hide the minimap button
/mi stats | purge | reset
```

## Tests

From this folder, run:

```
lua5.1 tests/run_tests.lua
luacheck MarketIntel
```

The tests run the real addon files inside a mock WoW client (`tests/wowmock.lua`). The mock simulates the auction house, item links, saved variables, tooltips and UI widgets.

They cover data capture, merging pages, history and compaction, deal and depth logic, full and watchlist scans, closing the AH mid-scan, the neutral AH, saved-variable round-trips, the Auctionator import, Auctionator/TSM integration, and clicking through every tab.

Extra tools:

- `lua5.1 tests/layout_export.lua <dir>` then `node tests/render_layout.js <dir>`: works out where every element sits on screen, draws each tab in Chromium as a screenshot, and reports clipped text, overlapping controls and anything outside the window.
- `lua5.1 tests/bench_scan.lua`: how long each frame takes while a 40,000-auction full scan is saved.
- `lua5.1 tests/bench_storage.lua`: saved-data size after a month of full scans.
- `lua5.1 tests/fuzz.lua [runs] [steps]`: randomized stress test (random searches, scans, relogs, mail, clicks and settings), checking saved data and that nothing ever buys.

## Known limitations

- Supply-based ratings and the normal price need a few days of scans before they mean anything.
- Not tracked: sale rate (needs TSM's desktop app data) and bid-only auctions.
- Random-suffix items ("of the Bear") are tracked per suffix, so each needs its own history.
- If you start a different search while a full scan is still being read, that full scan is saved as partial.

## Still to check in the real game

The tests use a mock client, so these details are written from the TBC Classic / Classic Era API but haven't been confirmed in-game yet:

- The `## Interface:` number in the `.toc` file (20504/20505).
- The return order of `GetAuctionItemInfo` (item ID as the 17th value), and the exact-match argument of `QueryAuctionItems` (8th).
- Map IDs used to detect the neutral AH: 1446 Tanaris, 1434 Stranglethorn, 1452 Winterspring.
- Auctionator's `MultiSearchExact` API. If it's missing, row clicks fall back to the default Browse search.
- That TSM's `DBRegionSoldPerDay`, `DBRegionMarketAvg` and `MatPrice` sources return data for your Classic region (they need the TSM desktop app). Auctionator's saved format and TSM's starred recipes have now been checked against real files.
- Mail functions (`GetInboxInvoiceInfo`, `GetInboxItem`) and the profession window functions return values in the order expected.
- Whether the auction house's quality filter is "exactly this quality" or "this quality and above". The snipe scan searches rare and epic separately, so both cases are covered.
- The layout was drawn and checked in a browser with a similar font, not in the game itself. WoW's font is a little different, so very long item names may cut off at slightly different points.
