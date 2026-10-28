import sys, json, math, re
from lupa import lua51
from PIL import Image, ImageDraw, ImageFont
import os
HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, 'run.py')).read().split('L.execute(open(script).read())')[0].replace('__file__', repr(os.path.join(HERE, 'run.py'))))
L.execute(open(os.path.join(HERE, 'experiment.lua')).read())
frames = L.globals().FRAMES
def load_tga(name):
    return Image.open(os.path.join(addon, 'media', name + '.tga')).convert('RGBA')
tex = {k: load_tga(k) for k in ['disc', 'ring', 'arrow']}
def icon(kind):
    im = Image.new('RGBA', (64, 64), (0,0,0,0)); d = ImageDraw.Draw(im)
    if 'RaidTargetingIcon_8' in kind:
        d.ellipse((8,4,56,48), fill=(235,235,235,255)); d.ellipse((18,18,30,30), fill=(0,0,0,255)); d.ellipse((34,18,46,30), fill=(0,0,0,255)); d.rectangle((20,46,44,60), fill=(235,235,235,255))
    elif 'NotReady' in kind:
        d.line((10,10,54,54), fill=(255,60,60,255), width=12); d.line((54,10,10,54), fill=(255,60,60,255), width=12)
    else:
        d.line((8,34,26,52), fill=(60,255,60,255), width=12); d.line((26,52,58,12), fill=(60,255,60,255), width=12)
    return im
S = 2  # supersample
W_, H_ = 200, 200
def strip(t): return re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', t)
panels = []
for i in range(1, len(frames) + 1):
    f = frames[i]
    im = Image.new('RGBA', (W_*S, H_*S), (0,0,0,0))
    order = {'BACKGROUND':0, 'BORDER':1, 'ARTWORK':2, 'OVERLAY':3}
    items = sorted([f['items'][j] for j in range(1, len(f['items'])+1)], key=lambda it: order.get(it['layer'], 0))
    for it in items:
        t = it['tex']
        if t == 'color':
            c = it['color']; bg = Image.new('RGBA', im.size, tuple(int(v*255) for v in (c[1],c[2],c[3],c[4]))); im = Image.alpha_composite(im, bg); continue
        name = t.split('\\')[-1]
        src = tex[name] if name in tex else icon(t)
        w, h = max(1, int(it['w']*S)), max(1, int(it['h']*S))
        s = src.resize((w, h), Image.LANCZOS)
        if it['rot']: s = s.rotate(math.degrees(it['rot']), expand=True)
        c = it['color']
        r,g,b,a = s.split()
        tint = Image.merge('RGBA', (r.point(lambda v: v*c[1]), g.point(lambda v: v*c[2]), b.point(lambda v: v*c[3]), a.point(lambda v: v*c[4])))
        cx, cy = W_*S/2 + it['x']*S, H_*S/2 - it['y']*S
        layer = Image.new('RGBA', im.size, (0,0,0,0)); layer.paste(tint, (int(cx - tint.width/2), int(cy - tint.height/2)), tint)
        im = Image.alpha_composite(im, layer)
    im = im.resize((W_, H_), Image.LANCZOS)
    panel = Image.new('RGB', (W_+40, H_+150), (24, 26, 30)); panel.paste(im, (20, 30), im)
    d = ImageDraw.Draw(panel); d.rectangle((19,29,20+W_,30+H_), outline=(90,90,90))
    d.text((8, 8), f['label'], fill=(255,210,80))
    y = H_ + 38
    for j in range(1, len(f['text'])+1):
        for line in strip(f['text'][j]).split('\n'):
            d.text((8, y), line, fill=(230,230,230)); y += 13
    d.text((8, y+2), f"sounds: {f['sounds'] or '-'}   screen flash: {'ON' if f['flash'] else 'off'}", fill=(150,200,255))
    panels.append(panel)
out = Image.new('RGB', (sum(p.width for p in panels), panels[0].height), (24,26,30))
x = 0
for p in panels: out.paste(p, (x, 0)); x += p.width
out = out.resize((out.width*2, out.height*2), Image.NEAREST)
out.save(sys.argv[1]); print('saved', out.size)
for i in range(1, len(frames)+1):
    f = frames[i]; print(f['label'], '|', ' / '.join(strip(f['text'][j]).replace('\n',' ; ') for j in range(1, len(f['text'])+1)), '| sounds', f['sounds'], 'flash', f['flash'])
