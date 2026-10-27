MARKET INTEL 1.4.0 - auction house helper for WoW TBC Classic
=============================================================

Works alongside Auctionator and TradeSkillMaster (TSM). It never buys, posts
or cancels anything for you: it only records prices and makes suggestions.

INSTALL
-------
Put this "MarketIntel" folder in:
  World of Warcraft\_anniversary_\Interface\AddOns\
If the AddOns list says "out of date", tick "Load out of date AddOns".

UPDATING: exit the game, delete the old MarketIntel folder and put the new
one in its place. Your history, ledger, watchlist and settings are kept
(they are saved in WTF\Account\<ACCOUNT>\SavedVariables\MarketIntel.lua).

GETTING STARTED
---------------
1. Open the auction house and run Auctionator's Full Scan. Market Intel
   records everything you, Auctionator or TSM search.
2. At login it copies Auctionator's price history once per auction house,
   so normal prices work straight away. Chat says "imported N days of
   price history". Without Auctionator, give it about 3 days of scans.
3. Open your mailbox now and then: auction mail feeds the sales ledger.
4. Crafting reads your starred recipes straight from TSM. Without TSM, open
   your profession windows once so Market Intel learns your recipes.

Open the window with /mi, the minimap button, or the "Market Intel" button
next to the auction house.

WINDOW SIZE: drag the grip in the window's bottom-right corner to shrink or
grow the whole window (50% to 125%), e.g. to keep it beside the auction
house. Or type a size in Settings, or /mi size 75. The size is remembered.

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
           deposits, return and risk. Suggestions only. Needs a complete
           search of the item (all pages, or a full scan) from the last 2h.
Depth      Flooded / Crowded / Normal / Thin rating per item, price wars, and a
           "Post at" price from the posting advisor. Tick "Only items in my
           bags" before you post.
History    Daily price chart (7/30/90 days), averages, swings, best weekday to
           sell and to buy. CSV buttons export one item or all items.
Crafting   Profit for recipes you starred in TSM's crafting window (or starred
           here with right-click): material cost, sale price, profit, margin,
           and profit if you buy the current deals on materials. Read straight
           from TSM, no need to open your profession windows. Vendor items
           (thread, vials, flux) use the vendor price when it's cheaper.
           A yellow "?" means the crafted item has very few listings, so its
           price may be one seller's asking price: check before crafting.
Ledger     Sales, purchases, expired and cancelled auctions read from your
           mail: totals, AH cut, net profit and sell-through per item.
Watchlist  Price alerts: an item plus a price, e.g. "Khorium Ore" at 20g.
           "Scan watchlist" searches every watched item. BUY means it was
           under your price in the last 2 hours; "was under, Xh ago" means
           it was, but that auction may be gone.
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
/mi size 75            window size in % (50-125)
/mi stats | purge | reset | help

GOOD TO KNOW
------------
- Deals, snipes and flips are cleared on logout or /reload; price history,
  the ledger, recipes and settings are saved.
- Your faction auction house and the neutral one (Gadgetzan, Booty Bay,
  Everlook) are tracked separately. Switching between them clears the
  deals, snipes and flips lists, since those auctions are on the other AH.
- The normal price is the middle of the last 14 days' prices (the lower
  middle for an even number of days), so one overpriced listing can't set it.
- BoE snipes need TSM's region data (the TSM desktop app). Without it, turn
  off "Snipes need TSM sale rate" in Settings to use Market Intel's own
  prices instead.
- Sold quantities come from your auction list: open the "Auctions" tab at the
  auction house before collecting sales mail, or the ledger shows "?".

WHAT'S NEW
----------
1.4.0  Resizable window: drag the bottom-right corner, use Settings, or
       /mi size 75. Fits beside the auction house on smaller screens.
1.3.2  Fixed (found in real game data): items saved without a name during
       full scans; recipes filed under profession "UNKNOWN"; ledger names
       keeping the stack size, e.g. "Thorium Widget (2)". Your existing data
       is repaired automatically at the next login.
1.3.1  Auctionator import works with Auctionator 8+ (packed database).
       TSM starred recipes read correctly; no need to open professions.
       Vendor prices for materials. One silly listing can't set a normal
       price. Crafting marks thin markets with "?".
1.3.0  Fixed: advisor crash with only your own auctions up; ledger
       merging identical mails; faction/neutral AH lists mixing; flips from
       partial searches; stale watchlist BUY; minimap badge while open.
1.2.0  BoE Snipe, Flips, posting advisor, Crafting, Ledger, minimap
       button, CSV export, big alerts.
