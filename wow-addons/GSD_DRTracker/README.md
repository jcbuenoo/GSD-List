# GSD DR Tracker

A movable diminishing returns (DR) bar for WoW TBC Classic Anniversary. It shows one row per enemy player and one icon per DR category. It's built for PvP, with Sap and rogue stuns shown first.

## Core features

- **One row per enemy player** you CC (arena, battlegrounds, world PvP, duels). Your current target is listed first and marked with `>`.
- **Next-CC strength on every icon**, colour-coded:
  - **50%** (yellow): your next CC in this category lasts half as long
  - **25%** (orange): quarter duration
  - **IMM** (red): the target is immune
- **Reset countdown and sweep.** The 20s DR reset only starts once the CC fades. While the CC is still on the target, the timer is blank.
- **Sap and rogue stuns first.** Order: Stun → Kidney → Incap (Sap) → Blind, then the rest.
- **All 15 TBC DR categories**, from DRList-1.0:

  | Label | Key | Shares DR |
  |---|---|---|
  | Stun | `stun` | Cheap Shot, HoJ, Bash, Pounce, Intercept, Charge, Shadowfury, Concussion Blow, Intimidation, War Stomp |
  | Kidney | `kidney_shot` | Kidney Shot only (**not** shared with Cheap Shot in TBC) |
  | Incap | `incapacitate` | Sap, Gouge, Polymorph, Repentance, Freezing Trap, Wyvern Sting, Maim, Hibernate, Banish |
  | Blind | `disorient` | Blind, Cyclone |
  | Fear | `fear` | Fear, Psychic Scream, Howl of Terror, Seduction, Intimidating Shout, Scare Beast, Turn Evil |
  | RStun | `random_stun` | Proc stuns: Impact, Mace Specialization, Blackout, Improved Concussive Shot, Seal of Justice, Stoneclaw |
  | Root | `root` | Frost Nova, Entangling Roots, Nature's Grasp, Freeze |
  | RRoot | `random_root` | Proc roots: Frostbite, Entrapment, Improved Hamstring, Improved Wing Clip |
  | Scat | `scatter` | Scatter Shot, Dragon's Breath |
  | Coil | `death_coil` | Death Coil only |
  | MC | `mind_control` | Mind Control |
  | Disarm | `disarm` | Disarm, Riposte |
  | CAtk | `counterattack` | Counterattack only |
  | Chast | `chastise` | Chastise only |
  | UA | `unstable_affliction` | Unstable Affliction silence |

- **Self-correcting.** If a CC lands while the bar says IMM, the real reset must already have happened (TBC resets take 15–20s), so the icon goes back to 50%.
- **Hunter-safe.** Feign Death is logged as a death, but it doesn't wipe the hunter's DRs.
- **Readable at any size.** Below 24px icons, the category labels and countdown are hidden so the DR level stays readable.
- **Optional self-tracking.** It can also show the DRs on you.
- **Lightweight.** No libraries; it only updates while something is being tracked, and settings are saved per account.

## Commands

| Command | What it does | Default |
|---|---|---|
| `/gdr` | Show the command list | |
| `/gdr test` | Show sample rows so you can position and preview the bar | |
| `/gdr unlock` | Show the green header; drag it to move the bar | unlocked |
| `/gdr lock` | Hide the header and lock the bar in place | |
| `/gdr preset rogue` | Only Stun, Kidney, Incap (Sap/Gouge) and Blind | |
| `/gdr preset all` | Every category | all |
| `/gdr cats` | List all categories, whether each is on, and what shares it | |
| `/gdr cat <key>` | Toggle one category, e.g. `/gdr cat fear` (keys in the table above) | |
| `/gdr self` | Also track DRs on yourself (row named "You") | off |
| `/gdr labels` | Show/hide the category name under each icon | on |
| `/gdr reset <15-20>` | DR reset window in seconds | 20 |
| `/gdr size <16-64>` | Icon size in pixels | 30 |
| `/gdr scale <0.5-3>` | Scale the whole bar | 1 |
| `/gdr rows <1-20>` | Maximum enemy rows | 8 |

## Install

Copy this `GSD_DRTracker` folder to `World of Warcraft\_anniversary_\Interface\AddOns\` and `/reload`. Then run `/gdr test`, drag the bar into place and `/gdr lock`.

## Limitations

- Only CC applied within combat-log range (about 50 yards) is seen.
- The bar uses the maximum 20s reset, so a DR can actually reset up to 5s earlier than shown.
