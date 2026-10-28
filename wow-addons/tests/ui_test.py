"""Interface test: lay out both bars with the mock, check geometry, render a screenshot.

Usage: python3 ui_test.py <addons_dir> <out_dir>
Writes <out_dir>/ui.html and <out_dir>/ui.png (PNG needs Playwright).
"""
import html
import os
import re
import sys

import lupa.lua51 as lua51

ADDONS, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

# spell names from the data-file comments, for readable placeholder icons
NAMES = {}
for addon in ("GSD_DRTracker", "GSD_EnemyCDs"):
    for m in re.finditer(r"\[(\d+)\]\s*=.*?-- ([^\n(]+)", open(os.path.join(ADDONS, addon, "Data.lua")).read()):
        NAMES.setdefault(int(m.group(1)), m.group(2).strip())

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ADDONS = ADDONS
lua.execute("dofile(%r); dofile(%r)" % (os.path.join(HERE, "mock.lua"), os.path.join(HERE, "layout.lua")))
lua.execute("""
UNITS.player = { guid = "me", name = "Me" }
LoadAddon("GSD_DRTracker", { "Data.lua", "Core.lua" }, ADDONS .. "/GSD_DRTracker")
LoadAddon("GSD_EnemyCDs", { "Data.lua", "Core.lua" }, ADDONS .. "/GSD_EnemyCDs")
Fire("PLAYER_LOGIN"); Fire("PLAYER_ENTERING_WORLD")
""")

failures = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


def items():
    lst = lua.eval("Layout({ GSD_DRTrackerAnchor, GSD_EnemyCDsAnchor })")
    out = []
    for i in range(1, len(lst) + 1):
        it = lst[i]
        d = {k: it[k] for k in ("kind", "l", "r", "t", "b", "depth", "text", "texture", "desat",
                                "cdStart", "cdDur", "reverse", "justify", "fontSize")}
        for k in ("textColor", "color", "bg"):
            d[k] = list(it[k].values()) if it[k] else None
        out.append(d)
    return out


def overlap(a, b, pad=0):
    return a["l"] < b["r"] - pad and b["l"] < a["r"] - pad and a["b"] < b["t"] - pad and b["b"] < a["t"] - pad


def geometry_checks(tag):
    """Check rows/icons/text of both bars don't collide."""
    lua.eval("Layout({ GSD_DRTrackerAnchor, GSD_EnemyCDsAnchor })")  # refresh cached rects
    for anchor_name in ("GSD_DRTrackerAnchor", "GSD_EnemyCDsAnchor"):
        rows = lua.eval("""(function(a)
            local out = {}
            for _, row in ipairs(a.children) do
                if row.kind == "Frame" and row.shown and row.icons then out[#out + 1] = row end
            end
            return out end)(%s)""" % anchor_name)
        row_boxes = []
        for ri in range(1, len(rows) + 1):
            row = rows[ri]
            icons = [row.icons[j] for j in range(1, len(row.icons) + 1) if row.icons[j].shown]
            rects = [dict(lua.eval("Rect")(ic)) for ic in icons]
            name = dict(lua.eval("Rect")(row.name))
            for a in range(len(rects)):
                for b in range(a + 1, len(rects)):
                    if overlap(rects[a], rects[b]):
                        check(False, f"[{tag}] {anchor_name} row {ri}: icons {a + 1} and {b + 1} overlap")
            if rects:
                check(name["r"] <= rects[0]["l"], f"[{tag}] {anchor_name} row {ri}: name left of icons")
                # text inside each icon must fit the icon width
                for ic, rc in zip(icons, rects):
                    iw = rc["r"] - rc["l"]
                    for fs_name in ("level", "timer"):
                        fs = lua.eval("function(i, k) return rawget(i, k) end")(ic, fs_name)
                        if fs and fs.text:
                            tw = len(fs.text) * fs.fontSize * 0.6
                            if tw > iw:
                                check(False, f"[{tag}] {anchor_name} row {ri}: '{fs.text}' ({tw:.0f}px) wider than icon ({iw:.0f}px)")
                # visible texts inside one icon must not sit on top of each other
                for ic in icons:
                    boxes = []
                    for fs_name in ("level", "timer"):
                        fs = lua.eval("function(i, k) return rawget(i, k) end")(ic, fs_name)
                        if fs and fs.shown and fs.text:
                            boxes.append((fs_name, dict(lua.eval("Rect")(fs))))
                    if len(boxes) == 2 and overlap(boxes[0][1], boxes[1][1], pad=1):
                        check(False, f"[{tag}] {anchor_name} row {ri}: level and timer text overlap")
                # category labels under DR icons must not run into each other
                labels = []
                for ic in icons:
                    lab = lua.eval("function(i) return rawget(i, 'label') end")(ic)
                    if lab and lab.shown:
                        labels.append(dict(lua.eval("Rect")(lab)) | {"text": lab.text})
                for a in range(len(labels) - 1):
                    if labels[a]["r"] > labels[a + 1]["l"]:
                        check(False, f"[{tag}] {anchor_name} row {ri}: labels '{labels[a]['text']}' and '{labels[a + 1]['text']}' overlap")
                bottom = min([rc["b"] for rc in rects] + [lb["b"] for lb in labels])
                row_boxes.append({"l": min(name["l"], rects[0]["l"]), "r": max(rc["r"] for rc in rects),
                                  "t": max(rc["t"] for rc in rects), "b": bottom})
        for a in range(len(row_boxes) - 1):
            check(not overlap(row_boxes[a], row_boxes[a + 1]), f"[{tag}] {anchor_name}: rows {a + 1} and {a + 2} don't overlap")
        check(len(row_boxes) > 0, f"[{tag}] {anchor_name}: rows rendered ({len(row_boxes)})")
    return True


def to_html(snapshots):
    now = lua.eval("NOW")
    parts = []
    for title, its in snapshots:
        divs = []
        for it in its:
            x, y, w, h = it["l"], 720 - it["t"], it["r"] - it["l"], it["t"] - it["b"]
            style = f"left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px;height:{h:.0f}px;"
            if it["kind"] == "Frame" and it["bg"] and it["bg"][3] > 0:
                r, gg, b, a = it["bg"]
                divs.append(f'<div class="o" style="{style}background:rgba({r*255:.0f},{gg*255:.0f},{b*255:.0f},{a})"></div>')
            elif it["kind"] == "Texture" and it["color"]:
                r, gg, b = it["color"]
                divs.append(f'<div class="o" style="{style}background:rgb({r*255:.0f},{gg*255:.0f},{b*255:.0f})"></div>')
            elif it["kind"] == "Texture" and it["texture"] is not None and isinstance(it["texture"], (int, float)):
                sid = int(it["texture"])
                hue = (sid * 47) % 360
                name = NAMES.get(sid, str(sid))
                abbr = "".join(w[0] for w in re.findall(r"[A-Za-z]+", name))[:3]
                filt = "filter:grayscale(1) brightness(.75);" if it["desat"] else ""
                divs.append(f'<div class="o tex" title="{html.escape(name)}" style="{style}{filt}background:linear-gradient(135deg,hsl({hue},55%,42%),hsl({hue},60%,22%))">{abbr}</div>')
            elif it["kind"] == "Cooldown" and it["cdDur"]:
                frac = max(0, min(1, (it["cdStart"] + it["cdDur"] - now) / it["cdDur"]))
                deg = frac * 360
                grad = (f"conic-gradient(transparent {360-deg}deg, rgba(0,0,0,.65) 0)" if it["reverse"]
                        else f"conic-gradient(rgba(0,0,0,.65) {deg}deg, transparent 0)")
                divs.append(f'<div class="o" style="{style}background:{grad}"></div>')
            elif it["kind"] == "FontString" and it["text"]:
                c = it["textColor"] or [1, 0.82, 0]
                align = {"RIGHT": "right", "LEFT": "left"}.get(it["justify"], "center")
                fs = it["fontSize"] or 11
                divs.append(f'<div class="o txt" style="{style}font-size:{fs}px;line-height:{h:.0f}px;text-align:{align};'
                            f'color:rgb({c[0]*255:.0f},{c[1]*255:.0f},{c[2]*255:.0f})">{html.escape(it["text"])}</div>')
        parts.append(f'<section><h2>{html.escape(title)}</h2><div class="screen">{"".join(divs)}</div></section>')
    return """<!doctype html><meta charset="utf-8"><title>GSD addons UI test</title>
<style>body{background:#111;color:#ddd;font-family:sans-serif;margin:16px}
.screen{position:relative;width:1280px;height:720px;background:radial-gradient(#2f3b2f,#1a1f1a);overflow:hidden;border:1px solid #444}
.o{position:absolute;box-sizing:border-box}.tex{color:#fff;font:bold 9px sans-serif;display:flex;align-items:center;justify-content:center;opacity:.95}
.txt{font-family:'Arial Narrow',Arial,sans-serif;font-weight:bold;white-space:nowrap;text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000}
h2{font-size:15px}</style>""" + "".join(parts)


snapshots = []

# 1. both test modes, default settings, unlocked
lua.execute('SlashCmdList.GSDDR("test"); SlashCmdList.GSDCD("test"); NOW = NOW + 0.1; RunTickers()')
geometry_checks("test mode")
snapshots.append(("Test mode, default size 30, unlocked (/gdr test, /gcd test)", items()))

# 2. arena with pre-filled cooldowns, locked, larger icons, every DR category on one enemy
lua.execute("""
INSTANCE = "arena"; Fire("PLAYER_ENTERING_WORLD")
SlashCmdList.GSDDR("lock"); SlashCmdList.GSDCD("lock"); SlashCmdList.GSDCD("size 36"); SlashCmdList.GSDDR("size 36")
UNITS.arena1 = { guid = "a1", name = "Rogueone", class = "ROGUE", race = "Human" }
UNITS.arena2 = { guid = "a2", name = "Priestly", class = "PRIEST", race = "Scourge" }
UNITS.arena3 = { guid = "a3", name = "Magey", class = "MAGE", race = "Gnome" }
for i = 1, 3 do Fire("ARENA_OPPONENT_UPDATE", "arena" .. i, "seen") end
PLAYERINFO.a1 = { "ROGUE", "Human" }
Log("SPELL_CAST_SUCCESS", "a1", "Rogueone", 0x440, nil, nil, 0, 31224)
Log("SPELL_CAST_SUCCESS", "a3", "Magey", 0x440, nil, nil, 0, 42292)
Log("SPELL_CAST_SUCCESS", "a3", "Magey", 0x440, nil, nil, 0, 1953)
local ids = { 1833, 8643, 11297, 2094, 6215, 12355, 27088, 12494, 19503, 27223, 10912, 676, 27067, 44047, 43523 }
for _, id in ipairs(ids) do
    Log("SPELL_AURA_APPLIED", "me", "Me", 0x511, "a1", "Rogueone", 0x440, id)
    Log("SPELL_AURA_REMOVED", "me", "Me", 0x511, "a1", "Rogueone", 0x440, id)
end
NOW = NOW + 3; RunTickers()
""")
geometry_checks("arena size 36")
snapshots.append(("Arena, pre-filled cooldowns, locked, size 36, all 15 DR categories on one enemy", items()))

# 3. smallest icon size
lua.execute('SlashCmdList.GSDDR("size 16"); SlashCmdList.GSDCD("size 16"); NOW = NOW + 0.1; RunTickers()')
geometry_checks("size 16")
snapshots.append(("Arena, minimum size 16", items()))

page = os.path.join(OUT, "ui.html")
open(page, "w").write(to_html(snapshots))
# Screenshot with Node Playwright if it's installed (optional)
import subprocess
shot = os.path.join(OUT, "ui.png")
js = ("const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();"
      "const p=await b.newPage({viewport:{width:1320,height:800}});"
      f"await p.goto('file://{os.path.abspath(page)}');await p.screenshot({{path:'{shot}',fullPage:true}});"
      "await b.close();})().catch(e=>{console.error(e.message);process.exit(1)});")
res = subprocess.run(["node", "-e", js], capture_output=True, text=True)
print("screenshot:", shot if res.returncode == 0 else "skipped (" + (res.stderr.strip() or "node/playwright missing") + ")")
print("ALL PASSED" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
