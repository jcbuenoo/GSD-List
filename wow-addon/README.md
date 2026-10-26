# Market Intel (WoW TBC Classic addon)

Market Intel records auction house prices over time and uses them to flag bargains and crowded markets. It works alongside **Auctionator** and **TradeSkillMaster** and doesn't replace either one.

It adds three things:

- **Price history:** a daily record of every item you see on the AH, with charts, averages, trend, volatility and the best weekday to sell or buy.
- **Deal alerts:** listings far below the item's normal price, plus your own watchlist price targets.
- **Market depth warnings:** whether a market is Flooded, Crowded, Normal or Thin, plus price-war and price-wall detection.

## Install

1. Copy the `MarketIntel` folder into `World of Warcraft/_anniversary_/Interface/AddOns/`. The client folder may be named differently, such as `_classic_`.
2. Restart the game. If the addon shows as "out of date", tick **Load out of date AddOns** on the character-select AddOns screen. To see your client's interface number, run `/dump select(4, GetBuildInfo())`. Then update the `## Interface:` line in `MarketIntel.toc` to match.

## Getting data

You don't need to do anything special. Every time the auction house shows results, Market Intel reads them. That includes your own searches, Auctionator's shopping lists, Auctionator's **Full Scan**, TSM searches and the default Browse tab.

- **Full scan** (best). Auctionator's full scan reads the whole AH in one go, about once every 15 minutes. Market Intel reads those results in the background, 1,000 rows per frame, so the game doesn't freeze.
- **Normal searches.** Pages of the same search are merged. If you only looked at page 1 of 3, that snapshot is marked *partial*: its prices are used, but its supply numbers are not.
- **Watchlist scan.** `/mi scan`, or the button on the Watchlist tab, searches each watched item by exact name, every page.

Each auction house is tracked separately: your faction's AH, plus the neutral AH in Gadgetzan, Booty Bay and Everlook.

## How it works

### Price history
For every item and every scan, Market Intel stores:

- the minimum buyout;
- the **market value**: the average price of the cheapest 25% of units on sale, ignoring anything priced over 1.5× the cheapest;
- units on sale, auctions, sellers;
- the "wall": units within 5% of the minimum.

Every scan is kept for 3 days, then merged into one summary per day, which is kept for 90 days. Searching the same item again within 10 minutes replaces the snapshot instead of adding another. About 110 bytes are saved per item.

**History tab:** search for an item to see:

- a daily chart (bar = market value, yellow mark = lowest price that day, blue line = normal price; green or red bars are more than 10% below or above normal);
- latest min and market, 7-day and 30-day averages, 30-day low and high, today vs the 7-day average, and the average daily swing;
- Auctionator's and TSM's prices next to Market Intel's;
- the best weekday to sell and to buy, once there are 14 days of data.

**Tooltips:** item tooltips show min/market with trend, the 7d/30d averages, the normal price, the depth rating, and how many you have listed.

### Deal alerts
- The **normal price** is the median daily market value over the last 14 days, not counting today, so a crash today can't lower the bar. It needs at least 3 days of history. Until then, TSM's `DBMarket` is used if TSM is installed.
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

## Commands

```
/mi                      open or close the window (there is also a button next to the AH window)
/mi deals|depth|history|watch|settings
/mi watch <item or shift-click link> [max price, e.g. 12g or 12g50s]
/mi unwatch <item>
/mi scan                 scan the watchlist (AH must be open)
/mi bags                 depth check for your bags
/mi stats | purge | reset
```

## Tests

From this folder, run:

```
lua5.1 tests/run_tests.lua
luacheck MarketIntel
```

The tests run the real addon files inside a mock WoW client (`tests/wowmock.lua`). The mock simulates the auction house, item links, saved variables, tooltips and UI widgets.

They cover data capture, merging pages, history and compaction, deal and depth logic, full and watchlist scans, closing the AH mid-scan, the neutral AH, saved-variable round-trips, Auctionator/TSM integration, and clicking through every tab.

## Known limitations

- Supply-based ratings and the normal price need a few days of scans before they mean anything.
- Not tracked: sale rate (needs TSM's desktop app data) and bid-only auctions.
- Random-suffix items ("of the Bear") are tracked per suffix, so each needs its own history.
- If you start a different search while a full scan is still being read, that full scan is saved as partial.
