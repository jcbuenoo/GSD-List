# SkullAlert (WoW TBC Anniversary)

Pops a raid warning (with sound) every time a **level ??** (skull) player of the
opposing faction is detected near you. Inspired by Spy.

## Install
Copy the `SkullAlert` folder to `World of Warcraft/_anniversary_/Interface/AddOns/`
and restart the game (or `/reload`).

## How detection works
"Level ??" means the enemy is 10+ levels above you (`UnitLevel` returns -1).
Every 0.5s, and on target / mouseover / focus / nameplate events, the addon checks:

- your target, focus, mouseover, target-of-target, pet's target
- every visible nameplate (**turn on enemy nameplates with `V`** for best range)
- every party/raid member's target

Once a player is identified as a skull, any combat-log activity from or against
them (about 50 yards) fires the alert again, after the cooldown.

## Commands (`/skull` or `/skullalert`)
| Command | Effect |
|---|---|
| `/skull on` / `off` | enable or disable |
| `/skull warning [on\|off]` | on-screen raid warning (only you see it) |
| `/skull sound [on\|off]` | raid warning sound |
| `/skull chat [on\|off]` | line in your chat frame |
| `/skull broadcast [on\|off]` | tell your group: `/rw` if raid lead/assist, else `/raid` or `/party` (off by default) |
| `/skull combatlog [on\|off]` | re-alert on known skulls seen in the combat log |
| `/skull cd <seconds>` | per-player cooldown (default 60) |
| `/skull test` | fire a test alert |
| `/skull reset` | forget detected players |
| `/skull status` | show settings |

## Limits
- The game only exposes an enemy's level through a unit you can see (nameplate,
  target, mouseover...). Enemies outside nameplate range, stealthed, or never
  seen can't be detected.
- At level 61+ nobody can be ?? to you (cap is 70), so the addon goes quiet.
