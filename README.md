# GSD-List
GSD List

## Market Intel (WoW TBC Classic addon)

This repository also contains **Market Intel**, an auction house addon for World of Warcraft TBC Classic (Anniversary) that works alongside Auctionator and TradeSkillMaster. It records prices and makes suggestions; it never buys, posts or cancels anything for you.

- **Download:** [`wow-addon/dist/MarketIntel-1.4.1.zip`](wow-addon/dist/MarketIntel-1.4.1.zip). Unzip it into `World of Warcraft/_anniversary_/Interface/AddOns/`.
- **Full guide:** [`wow-addon/README.md`](wow-addon/README.md)

### Core features
- **Price history** for every item you see on the AH, starting from Auctionator's history so it works from day one.
- **Deal alerts** for listings far below normal price, plus watchlist price targets.
- **BoE Snipe:** cheap blue and epic gear (required level 15-55) that sells regularly in your region.
- **Flip finder:** cheap auctions you could buy and relist, with profit and risk.
- **Posting advisor:** what to post at, or whether to hold.
- **Market depth:** Flooded, Crowded, Normal or Thin, plus price wars.
- **Crafting profit** for the recipes you starred in TSM.
- **Sales ledger** read from your auction mail.
- **Minimap button, CSV export, big on-screen alerts, and a resizable window.**

### Commands
| Command | What it does |
|---|---|
| `/mi` | Open or close the window |
| `/mi deals`, `snipe`, `flips`, `depth`, `history`, `crafting`, `ledger`, `watch`, `settings` | Open that tab (`/mi snipe` also runs a BoE scan when the AH is open) |
| `/mi scan` | Search every watchlist item (AH open) |
| `/mi watch <item> [price]` | Add to the watchlist, e.g. `/mi watch Khorium Ore 20g` |
| `/mi unwatch <item>` | Remove from the watchlist |
| `/mi post <item>` | Suggested posting price |
| `/mi bags` | Market depth for everything in your bags |
| `/mi import` | Copy Auctionator's price history again |
| `/mi size <50-125>` | Window size in % |
| `/mi minimap` | Show or hide the minimap button |
| `/mi stats` | How much data is stored |
| `/mi purge` | Compact old data now |
| `/mi reset` | Delete all price history for this auction house (asks first) |
| `/mi help` | List all commands in game |
