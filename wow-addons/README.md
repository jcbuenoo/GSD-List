# GSD PvP addons for WoW TBC Classic Anniversary

Two standalone, dependency-free addons. Each one is a movable bar with one row per enemy player you're fighting.

| Addon | Slash | What it shows |
|---|---|---|
| `GSD_DRTracker` | `/gdr` | Diminishing returns per enemy: Stun, Kidney, Incap (Sap/Gouge/Poly), Blind/Cyclone, Fear, Roots, and so on |
| `GSD_EnemyCDs`  | `/gcd` | Enemy cooldowns per enemy: PvP trinket, racials, interrupts, defensives, CC, mobility, offensive CDs |

TOC interface: `20506, 20505` (2.5.6 and 2.5.5 Anniversary clients).

Each addon folder also has its own README with the full feature list and command reference: [GSD_DRTracker](GSD_DRTracker/README.md), [GSD_EnemyCDs](GSD_EnemyCDs/README.md).

## Install

Copy both folders into `World of Warcraft\_anniversary_\Interface\AddOns\`, so you end up with
`...\AddOns\GSD_DRTracker\GSD_DRTracker.toc` and `...\AddOns\GSD_EnemyCDs\GSD_EnemyCDs.toc`.
Then restart the game or `/reload`.

First run: `/gdr test` and `/gcd test` show sample rows. Drag the coloured header to move each bar, then use `/gdr lock` and `/gcd lock`.

## DR Tracker (`/gdr`)

Each icon is one DR category on that enemy. The icon shows the last spell used, and the text tells you what your **next** CC in that category will do:

- **50%** (yellow): half duration
- **25%** (orange): quarter duration
- **IMM** (red): immune
- No number at the bottom means the CC is still on the target, so the 20s reset hasn't started yet. Once it fades, a countdown and sweep show when the DR resets.
- If a CC lands while the bar shows IMM, the DR must already have reset (TBC resets take 15-20s), so the bar corrects itself to 50%.
- Below 24px icon size, the category name and countdown are hidden so the DR level stays readable. The sweep still shows the time.

The things rogues usually get wrong in TBC:

- **Cheap Shot and Kidney Shot do not share DR.** Cheap Shot is in the shared *Stun* category (HoJ, Bash, Pounce, Intercept, Charge, Shadowfury, Concussion Blow, Intimidation, War Stomp). Kidney Shot only DRs with itself.
- **Sap shares DR with Gouge, Polymorph, Repentance, Freezing Trap, Wyvern Sting, Maim, Hibernate and Banish** (the *Incap* category). If the mage just sheeped someone, your Sap on them is 50%.
- **Blind shares DR with Cyclone only**, not with Sap.
- Proc stuns (Impact, Mace Specialization, Blackout and others) have their own *RStun* (random stun) category.

Commands:

```
/gdr lock | unlock      move the bar
/gdr test               sample rows
/gdr preset rogue       only Stun, Kidney, Incap (Sap/Gouge), Blind/Cyclone
/gdr preset all         every category (default)
/gdr cats               list categories and what's in them
/gdr cat <key>          toggle one category (e.g. /gdr cat fear)
/gdr self               also show DRs on yourself
/gdr labels             show/hide category names under icons
/gdr reset <15-20>      DR reset window (default 20)
/gdr scale <n> | size <px> | rows <n>
```

## Enemy Cooldowns (`/gcd`)

An icon appears when an enemy uses a tracked spell, with a sweep and a timer until it's ready. Border colours: gold = trinket, white = racial, purple = interrupt, green = defensive, red = CC, blue = mobility, orange = offensive, grey = utility.

- **In arena** (default `unused arena`), each opponent's row is pre-filled with their baseline class spells, PvP trinket and racial, all shown as ready. Talent spells (Cold Snap, Preparation, Pain Suppression and others) appear once they're used.
- **Resets are handled.** Cold Snap clears the frost cooldowns, Preparation clears Vanish/Evasion/Sprint/Shadowstep/Cold Blood/Premeditation, Readiness clears hunter cooldowns, and summoning a new Felhunter clears Spell Lock.
- **Pets**: in arena, Felhunter Spell Lock is shown on the warlock's row.
- **Cooldowns survive death.** A player who dies and rezzes in a BG still shows their used trinket. Hunter Feign Death (logged as a death) doesn't clear anything either.
- **The PvP trinket defaults to 2 min** (Medallion). The old level-60 Insignia is 5 min and casts the same spell, so the addon can't tell them apart. 2 min is the safer guess: the bar may show their trinket as ready when it's actually down, but never the other way round. If you know they have an Insignia, use `/gcd trinket 300`.
- **Durations assume common PvP talents by default.** For example: Vanish/Evasion/Sprint 3:30, Blind 1:30, HoJ 45s, Ice Block 4 min, Intercept 15s. This is conservative for the same reason. Use `/gcd talents` to switch to untalented base values.

Commands:

```
/gcd lock | unlock
/gcd test
/gcd unused arena | always | never     pre-fill ready icons
/gcd talents                           toggle talent-reduced durations
/gcd trinket <sec>                     120 (Medallion) or 300 (Insignia)
/gcd set <spellID> <sec>               override one cooldown (any rank ID works)
/gcd clear <spellID>
/gcd scale <n> | size <px> | rows <n> | icons <n>
```

## Limitations

- Everything comes from the combat log and cast events, so only things that happen near you are seen (the Classic combat log range is about 50 yards). A cooldown used out of range isn't tracked.
- Talents can't be inspected on enemies, so cooldown lengths are best guesses. Adjust with `/gcd set`.
- DR reset in TBC varies between 15 and 20s. The bar uses 20s, so a DR may actually reset a few seconds before the bar says it does.

## Existing addons these were modelled on

- **OmniBar**: the standard enemy cooldown bar; its TBC spell table was used to cross-check spell IDs and cooldowns. https://www.curseforge.com/wow/addons/omnibar
- **DRList-1.0** (MIT, by Wardz): the DR category library most DR addons use. The TBC DR spell list here comes from it. https://github.com/wardz/DRList-1.0
- **Diminish / DRTracker / Gladius / sArena**: DR icons on unit or arena frames.
- **CooldownWatch - Classic**: another enemy cooldown tracker that lists TBC Anniversary support. https://www.curseforge.com/wow/addons/cooldownwatch-rg
- **SequenGladius**, **Arena Armory**, **RaidToolKit_SUI**: TBC Anniversary arena frame suites with DR modules.

The addons in this folder differ in being a single standalone bar each, covering everyone you're fighting (BGs and world PvP as well as arena), with Sap and rogue stuns put first.

## Tests

`wow-addons/tests/` contains a headless harness that mocks the WoW API and replays combat-log events under Lua 5.1 (the WoW Lua version):

```
pip install lupa
python3 wow-addons/tests/run.py wow-addons wow-addons/tests/test_dr.lua
python3 wow-addons/tests/run.py wow-addons wow-addons/tests/test_cd.lua
python3 wow-addons/tests/ui_test.py wow-addons <out_dir>
```

The mock throws "Font not set" when text is set on a font string with no font, like the real client does.
`ui_test.py` resolves every frame anchor into screen coordinates. It checks that icons, rows, labels and the text inside icons don't collide at sizes 16, 30 and 36, then writes `ui.html` and, if Node Playwright is installed, a `ui.png` screenshot.
