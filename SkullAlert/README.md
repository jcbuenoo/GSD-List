# SkullAlert (WoW TBC Anniversary)

Pops a raid warning (with sound) every time a **level ??** (skull) player of the
opposing faction is detected near you. Inspired by Spy.

"Level ??" means the enemy is 10+ levels above you, e.g. **63+ when you are 53**.
The threshold follows your level automatically.

## Core features
- **Skull detection** – alerts on any opposing-faction player whose level shows as ??.
  Same-faction players and NPCs (including ?? bosses/elites) are ignored.
- **Raid warning alert** – big on-screen raid warning with a skull icon, the player's
  name in class color, race, class and guild. Only you see it.
- **Sound** – plays the raid warning sound on the Master channel, so you hear it even
  with game sounds turned down.
- **Chat log line** – name, guild, race/class, how they were detected and your current
  zone/subzone.
- **Many detection sources** – target, focus, mouseover, target-of-target, every enemy
  nameplate, and the targets of your party/raid members and your pet.
- **Combat log re-alerts** – once a skull is known, any fighting from or against them
  within combat log range (~50 yards) alerts again, even if you can't see them.
- **Anti-spam cooldown** – each player alerts at most once per cooldown (60s by
  default), no matter how many sources see them at once.
- **Optional group broadcast** – tells your group with a `{skull}` marker: `/rw` if
  you are raid leader/assist, otherwise `/raid` or `/party`. Off by default and
  throttled to one message every 3 seconds.
- **Lightweight** – no timers or polling; it only reacts to game events. The combat
  log is ignored entirely until a skull has been seen, and everything stops listening
  when the addon is turned off.
- **Saved settings** – your choices are kept between sessions and characters' logins.

## Commands
Use `/skull` or `/skullalert`. Typing `/skull` alone lists the commands.

| Command | What it does | Default |
|---|---|---|
| `/skull on` / `/skull off` | Turn all alerts on or off | on |
| `/skull warning [on\|off]` | On-screen raid warning (only you see it) | on |
| `/skull sound [on\|off]` | Raid warning sound | on |
| `/skull chat [on\|off]` | Line in your chat frame | on |
| `/skull broadcast [on\|off]` | Announce skulls to your group | off |
| `/skull combatlog [on\|off]` | Re-alert on known skulls seen in the combat log | on |
| `/skull cd <seconds>` | Per-player alert cooldown | 60 |
| `/skull test` | Fire a test alert (never sent to your group) | – |
| `/skull reset` | Forget all detected players | – |
| `/skull status` | Show current settings | – |

Leaving out `on`/`off` flips the setting. Examples:

```
/skull broadcast on
/skull cd 30
/skull sound
```

## Install
1. Close WoW completely.
2. Copy the `SkullAlert` folder into
   `World of Warcraft/_anniversary_/Interface/AddOns/`, so the result is
   `AddOns/SkullAlert/SkullAlert.toc` (not `AddOns/SkullAlert/SkullAlert/...`).
3. Start WoW, click **AddOns** on character select and make sure SkullAlert is
   ticked. If it says "Out of date", tick **Load out of date AddOns**.
4. In game, type `/skull test` to check it works, and press `V` to show enemy
   nameplates for the best detection range.

New addons need a full game restart; `/reload` is enough only after editing an
addon that was already installed.

## Limits
- The game only exposes an enemy's level through a unit you can see (nameplate,
  target, mouseover...). Enemies outside nameplate range, stealthed, or never
  seen can't be detected.
- A skull that stays on screen alerts once; you're alerted again when their nameplate
  reappears, when you target/mouse over them after the cooldown, or when they fight
  near you.
- At level 61+ nobody can be ?? to you (cap is 70), so the addon goes quiet.

## Tests
`tests/skullalert_test.lua` (repo root) runs the addon against a mocked WoW API:
`lua5.1 tests/skullalert_test.lua`
