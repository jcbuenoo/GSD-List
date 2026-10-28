# Guard Aggro Watch tests

These run the addon under real Lua 5.1 (through `lupa`) against a **strict mock of the TBC Classic Anniversary
client**:

- Calling a widget method that isn't in Blizzard's API documentation raises an error.
- Reading a global that the mock doesn't provide raises an error. After the run, every global the addon read is
  checked against Blizzard's own UI code and docs, and the run also lists every global the addon created.

`api.json` is the list of real widget methods and globals, taken from Gethe/wow-ui-source (branch
`classic_anniversary`, client 2.5.6).

## Run

```bash
pip install lupa pillow
```

```bash
python3 tests/guardaggrowatch/run.py
```

The command exits with code 1 if any test fails or the addon reads an unknown global.

```bash
python3 tests/guardaggrowatch/render.py GuardAggroWatch/docs/radar_experiment.png
```

This walks a rogue through a mock city gate and renders what the radar draws at each step.

## Refresh the API list after a game patch

```bash
git clone --depth 1 -b classic_anniversary https://github.com/Gethe/wow-ui-source
```

```bash
python3 tests/guardaggrowatch/extract_api.py wow-ui-source/Interface/AddOns
```

Then move the new `api.json` into `tests/guardaggrowatch/`.

## Coverage (30 tests)

Loading and saved-data upgrades; every slash command, including bad input; the aggro radius formula and its limits;
SAFE/CAUTION/INSIDE changes with sounds, their throttles and the screen flash; overlapping rings; other continents;
instances where your position isn't available; a missing facing value; the `ahead` geometry; nameplate
auto-learning (clean pulls, pulls after you attacked, the 60 s de-dupe, name mismatches, friendly, dead and player
units, the 5 yd minimum); radar rotation geometry; minimap indoor/outdoor sizes, the CVar fallback, square shape,
rotation and edge clipping; world map pins, rings, zoom scale, continent maps, maps without position data and
tooltips; lock, scale and saving the dragged position; key bindings; clear-map and clear-all popups; performance.
