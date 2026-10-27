MARKET INTEL 1.3.0 - auction house helper for WoW TBC Classic
=============================================================

Works alongside Auctionator and TradeSkillMaster (TSM). It never buys, posts
or cancels anything for you: it only records prices and makes suggestions.

INSTALL
-------
Put this "MarketIntel" folder in:
  World of Warcraft\_anniversary_\Interface\AddOns\
If the AddOns list says "out of date", tick "Load out of date AddOns".

GETTING STARTED
---------------
1. Open the auction house and run Auctionator's Full Scan. Market Intel
   records everything you, Auctionator or TSM search.
2. On first use it copies Auctionator's price history, so normal prices
   work straight away (otherwise give it about 3 days of scans).
3. Open your mailbox now and then: auction mail feeds the sales ledger.
4. Open your profession windows once so it learns your recipes.

Open the window with /mi, the minimap button, or the "Market Intel" button
next to the auction house.

TABS
----
Deals      Auctions at or below 60% of the normal price that save at least 2g,
           plus watchlist hits. "Craft" shows when a deal makes one of your
           starred recipes profitable. Click a row to search it.
BoE Snipe  Blue/epic gear, required level 15-55, that TSM says sells at least
           0.1 a day in your region, listed at or below 65% of its normal
           price. Checked on every search and full scan; "Scan BoE" searches
           that whole category page by page.
Flips      Suggestions to buy the cheapest auctions of an item and relist them
           at the normal price, with cost, profit after the 5% cut and
           deposits, return and risk. Suggestions only.
Depth      Flooded / Crowded / Normal / Thin rating per item, price wars, and a
           "Post at" price from the posting advisor. Tick "Only items in my
           bags" before you post.
History    Daily price chart (7/30/90 days), averages, swings, best weekday to
           sell and to buy. CSV buttons export one item or all items.
Crafting   Profit for recipes you starred in TSM's crafting window (or starred
           here with right-click): material cost, sale price, profit, margin,
           and profit if you buy the current deals on materials.
Ledger     Sales, purchases, expired and cancelled auctions read from your
           mail: totals, AH cut, net profit and sell-through per item.
Watchlist  Price alerts: an item plus a price, e.g. "Khorium Ore" at 20g.
           "Scan watchlist" searches every watched item.
Settings   Every threshold (hover a box for help), alert options and sounds.

ALERTS
------
Chat line + sound for every find. Big finds (BoE snipes, watchlist hits,
deals saving 20g+) also show a raid-warning style message in the middle of
the screen and flash the taskbar icon if the game is in the background.
The minimap button shows how many alerts arrived since you last looked.

COMMANDS
--------
/mi                    open or close the window
/mi deals | snipe | flips | depth | history | crafting | ledger | watch | settings
/mi snipe              run the BoE snipe scan (auction house open)
/mi scan               scan your watchlist (auction house open)
/mi watch <item> 20g   alert when the item is at or below 20g
/mi unwatch <item>
/mi post <item>        suggested posting price
/mi bags               depth check for everything in your bags
/mi import             copy Auctionator's price history again
/mi minimap            show or hide the minimap button
/mi stats | purge | reset | help

GOOD TO KNOW
------------
- Deals, snipes and flips are cleared on logout or /reload; price history,
  the ledger, recipes and settings are saved.
- Your faction auction house and the neutral one (Gadgetzan, Booty Bay,
  Everlook) are tracked separately.
- BoE snipes need TSM's region data (the TSM desktop app). Without it, turn
  off "Snipes need TSM sale rate" in Settings to use Market Intel's own
  prices instead.
- Sold quantities come from your auction list: open the "Auctions" tab at the
  auction house before collecting sales mail, or the ledger shows "?".
