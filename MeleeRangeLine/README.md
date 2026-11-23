# Melee Range Line

A World of Warcraft **TBC Classic Anniversary** addon. It draws a line from your character to your hostile target:

- **Green**: you're in melee range.
- **Red**: you're out of melee range.
- **Yellow**: the game couldn't give a range answer.

## Install

Copy the `MeleeRangeLine` folder into `World of Warcraft/_anniversary_/Interface/AddOns/`, then restart the game or
type `/reload`.

**Enemy nameplates must be on** (default key `V`, or type `/mrl plates`). The line ends at your target's nameplate,
so when that nameplate isn't on screen there's no line.

## How the range is checked

- **Warrior, Rogue, Hunter, Druid**, and Paladins or Shamans with Crusader Strike or Stormstrike: the addon asks the
  game whether one of your melee abilities can reach the target. This uses the real melee reach, including large
  bosses' bigger hitboxes.
- **Mage, Priest, Warlock, and Paladins or Shamans without those talents**: you have no melee ability to test with,
  so the addon falls back to duel distance (about 10 yards). That is wider than true melee range. `/mrl status` tells
  you which method you're on.

## Limits of what an addon can draw

- **No line on the ground.** WoW gives addons no way to draw in the 3D world, and it hides other units' map
  positions. The line is drawn on your screen, from your character to the target's nameplate. Tools that paint
  lines on the floor are third-party "unlockers", which break the rules and get accounts banned.
- **Nameplates are locked down.** Addons can't read where a nameplate is, and can't attach anything to one from
  outside it. Since 1.0.2 the line lives inside the target's nameplate, the way Plater attaches its frames.
- **Your end is a fixed screen point**, just below the centre of the screen, where your character stands with the
  default camera. Move it with `/mrl offset <x> <y>`.
- **Fallback dot.** If the target's nameplate isn't shown, or the game refuses the line, a dot at your character
  shows the range color instead. If the game refuses something, the addon prints one chat line saying what, and
  `/mrl status` repeats it.

## Commands (`/mrl` or `/meleeline`)

| Command | What it does |
| --- | --- |
| `/mrl on`, `off`, `toggle` | Show or hide the line |
| `/mrl thickness <1-20>` | Line width (default 3) |
| `/mrl alpha <0.1-1>` | Opacity (default 0.9) |
| `/mrl outline` | Turn the dark border on or off |
| `/mrl incolor <r g b>` / `outcolor <r g b>` | Colors, as 0–1 or 0–255 |
| `/mrl dot` | Turn the fallback range dot on or off |
| `/mrl offset <x> <y>` | Move the screen point (default `0 -60`) |
| `/mrl targetoffset <y>` | Move the target end up or down |
| `/mrl plates` | Turn on enemy nameplates (not in combat) |
| `/mrl status`, `/mrl reset` | Show settings and range method, or reset everything |

## Tests

```bash
pip install lupa
```

```bash
python3 tests/meleerangeline/run.py
```

These run the addon under Lua 5.1 against the strict client mock in `tests/guardaggrowatch/`. A call to a widget
method or global that isn't in Blizzard's 2.5.6 Anniversary UI source fails the run.
