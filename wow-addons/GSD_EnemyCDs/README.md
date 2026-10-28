# GSD Enemy CDs

A movable enemy cooldown bar for WoW TBC Classic Anniversary. It shows one row per enemy player, with an icon for each important cooldown they've used and a timer until it's back.

## Core features

- **One row per enemy player** you're fighting (arena, battlegrounds, world PvP). Outside arena, your target and focus are listed first.
- **The important PvP cooldowns**, border-coloured by type and in this order:
  - **Gold – PvP trinket** (Medallion/Insignia)
  - **White – racials:** Will of the Forsaken, Escape Artist, Stoneform, War Stomp, Arcane Torrent, Perception, Berserking, Blood Fury, Gift of the Naaru
  - **Purple – interrupts:** Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock, Silence, Silencing Shot, Feral Charge
  - **Green – defensives:** Ice Block, Divine Shield, Blessing of Protection, Evasion, Vanish, Cloak of Shadows, Pain Suppression, Barkskin, Deterrence, Feign Death, Spell Reflection, Shield Wall and more
  - **Red – CC:** Blind, Kidney Shot, Gouge, Hammer of Justice, Repentance, Psychic Scream, Death Coil, Howl of Terror, Intimidating Shout, Freezing Trap, Scatter Shot, Bash, Frost Nova and more
  - **Blue – mobility:** Blink, Sprint, Shadowstep, Charge, Intercept, Intervene, Blessing of Freedom, Dash
  - **Orange – offensive:** Icy Veins, Arcane Power, Adrenaline Rush, Cold Blood, Death Wish, Avenging Wrath, Bestial Wrath, Bloodlust/Heroism and more
  - **Grey – utility:** Cold Snap, Preparation, Readiness, Nature's Swiftness, Innervate, Evocation and more
- **Arena pre-fill.** In arena, each opponent's row starts with their class's baseline spells, PvP trinket and racial, shown as ready. Talent spells appear once they're used.
- **Reset handling:**
  - **Cold Snap** clears frost cooldowns.
  - **Preparation** clears Vanish, Evasion, Sprint, Shadowstep, Cold Blood and Premeditation.
  - **Readiness** clears hunter cooldowns.
  - **A new Felhunter** clears Spell Lock.
- **Pets.** In arena, Felhunter Spell Lock is shown on the warlock's row.
- **Shared cooldowns.** Earth, Frost and Flame Shock share one icon, as do Freezing and Frost Trap.
- **Survives death.** Cooldowns persist through BG deaths and hunter Feign Death, like in the game.
- **Conservative timers.** Durations assume common PvP talents and a 2-minute trinket, so the bar may sometimes show a spell as ready when it's still down, but never shows it as down when it's actually ready.
- **Catches casts the combat log misses**, such as the trinket, via your target, focus, arena and nameplate units.
- **Lightweight.** No libraries; it only updates while something is tracked, and settings are saved per account.

## Commands

| Command | What it does | Default |
|---|---|---|
| `/gcd` | Show the command list | |
| `/gcd test` | Show sample rows so you can position and preview the bar | |
| `/gcd unlock` | Show the red header; drag it to move the bar | unlocked |
| `/gcd lock` | Hide the header and lock the bar in place | |
| `/gcd unused arena` | Pre-fill ready icons in arena only | arena |
| `/gcd unused always` | Pre-fill ready icons everywhere | |
| `/gcd unused never` | Only show cooldowns that have been used | |
| `/gcd talents` | Toggle talent-reduced durations (off = base cooldowns) | on |
| `/gcd trinket <sec>` | PvP trinket cooldown: `120` Medallion, `300` Insignia | 120 |
| `/gcd set <spellID> <sec>` | Override one cooldown (any rank's spell ID works) | |
| `/gcd clear <spellID>` | Remove an override | |
| `/gcd size <16-64>` | Icon size in pixels | 30 |
| `/gcd scale <0.5-3>` | Scale the whole bar | 1 |
| `/gcd rows <1-20>` | Maximum enemy rows | 6 |
| `/gcd icons <1-30>` | Maximum icons per row | 12 |

## Install

Copy this `GSD_EnemyCDs` folder to `World of Warcraft\_anniversary_\Interface\AddOns\` and `/reload`. Then run `/gcd test`, drag the bar into place and `/gcd lock`.

## Limitations

- Only casts within combat-log range (about 50 yards) are seen.
- Enemy talents can't be inspected, so cooldown lengths are best guesses. Use `/gcd set` to correct any you know.
- The game can't tell a Medallion from an Insignia (same spell), so the trinket assumes 2 minutes.
