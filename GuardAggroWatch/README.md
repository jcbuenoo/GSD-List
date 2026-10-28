# Guard Aggro Watch (TBC Classic Anniversary)

A rogue's helper for hanging around enemy capitals. You mark where the guards stand. The addon then draws each guard's
aggro ring to scale and warns you as you get close to it. You can also mark the blind spots where you can gank
without pulling guards.

## Install
Copy the `GuardAggroWatch` folder into `World of Warcraft/_anniversary_/Interface/AddOns/`. If the game says the
addon is out of date, check your client's number with `/dump select(4, GetBuildInfo())` and put that number on the
`## Interface:` line of `GuardAggroWatch.toc`.

## What you get
- **Radar** (movable, under `/gaw unlock`): a top-down view of the ground around you. It turns with you by default.
  Red areas are guard aggro zones. The yellow ring around each one is your caution buffer. A skull marks a guard,
  a red X marks a spot where you were pulled, and a green check marks a blind spot.
- **Status line**: SAFE / CAUTION / INSIDE AGGRO RANGE, with the exact yards to the line.
- **Alerts**: a whisper sound when you get near the line. A raid-warning sound and a red pulse at the screen edges
  when you cross it.
- **Minimap**: dotted aggro rings and mark icons.
- **World map**: shaded aggro zones and pins. Hover a pin to see its details.
- **Auto-learning**: when a guard on your nameplates targets you and you didn't start a fight, the addon records
  the spot. It also tightens the nearest guard's ring to the distance you were actually pulled from.
- Marks are account-wide. The easiest way to map a city is to walk it on an alt of that faction: stand next to each
  guard, target it, and type `/gaw guard`.

## Commands (`/gaw`)
| Command | What it does |
|---|---|
| `/gaw guard [yd]` | Mark a guard at your feet. Target the guard first so its level is used. `yd` sets a fixed radius |
| `/gaw guard ahead <yd> [radius]` | Mark a guard `<yd>` straight ahead of you |
| `/gaw edge` | Mark a point on the aggro line |
| `/gaw safe [note]` / `/gaw safe ahead <yd> [note]` | Mark a blind spot |
| `/gaw undo`, `/gaw del`, `/gaw clear`, `/gaw clear all` | Remove the last mark / the nearest mark / this map's marks / everything |
| `/gaw setr <yd>\|auto` | Set the nearest guard's radius, or go back to the computed one |
| `/gaw list` | Show mark counts per city |
| `/gaw radar\|minimap\|map\|rotate\|sound\|flash\|auto` | Turn each feature on or off |
| `/gaw lock\|unlock`, `/gaw range <yd>`, `/gaw scale <n>` | Radar placement and size |
| `/gaw warn <yd>`, `/gaw default <yd>` | Size of the caution buffer / radius used when a guard's level is unknown |
| `/gaw addname [text]` | Treat NPCs whose names contain this text (or your target's name) as guards |

You can also set key bindings under Key Bindings → Guard Aggro Watch.

## Limits (these come from the game, not from bugs)
- **Addons can't draw on the actual 3D ground** in TBC Classic, and world markers don't exist in TBC. The radar,
  minimap and world map are the "ground markings".
- **Addons can't read NPC positions.** Guards have to be marked by hand, or with `ahead`. Rings around patrolling
  guards are only approximate.
- The ring uses the usual aggro rule of thumb: about 20 yd against an equal-level mob, plus or minus 1 yd per level
  of difference, limited to 5-45 yd. Stealth lets you get much closer than that. Once you open on someone, you are
  visible and the full ring applies. Guards may also come running because your victim is in combat near them.
  Calibrate with real pulls (auto-learning) and keep a buffer.
- Guard name matching only works on English clients. Use `/gaw addname` for other languages.
- Positions don't work inside instances.
